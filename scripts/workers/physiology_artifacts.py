"""Stream complete typed processed physiology tables into verified local artifacts.

No numerical processing, coordinate inference, raw duplication or model selection
occurs here. Callers supply explicit table types, units, identities and provenance.
"""
from __future__ import annotations

import copy
import hashlib
import json
import math
import os
from pathlib import Path
import re
import tempfile

SCHEMA = "brohn-physiology-tables/1.0"
KINDS = {"physiology-series", "physiology-events"}
MAX_BYTES = 2*1024**3
MAX_ROWS = 20000000
MAX_TABLES = 10000
MAX_LINE = 2*1024**2
TYPES = {"float64", "integer", "boolean", "string"}
HEX = re.compile(r"^[a-f0-9]{64}$")
ID = re.compile(r"^[A-Za-z][A-Za-z0-9_-]{0,159}$")


class ArtifactError(ValueError): pass


def require(condition, message):
    if not condition: raise ArtifactError(message)


def text(value, size=4000):
    return isinstance(value,str) and bool(value.strip()) and len(value.encode("utf-8"))<=size


def digest_file(path):
    sha=hashlib.sha256()
    with Path(path).open("rb") as stream:
        for block in iter(lambda:stream.read(1024**2),b""): sha.update(block)
    return sha.hexdigest()


def _plain(value, depth=0):
    require(depth<=24, "Artifact metadata nesting exceeds 24 levels.")
    if value is None or isinstance(value,(bool,str)): return value
    if isinstance(value,int):
        require(abs(value)<=2**53-1, "Encode large exact integers as declared decimal strings.")
        return value
    if isinstance(value,float):
        require(math.isfinite(value), "Nonfinite metadata must be explicitly represented with null and support evidence.")
        return value
    if isinstance(value,list): return [_plain(v,depth+1) for v in value]
    require(isinstance(value,dict) and all(isinstance(k,str) and k for k in value), "Metadata must contain plain JSON objects, arrays and scalar values.")
    require(not set(value)&{"path","source_path","output_directory","mask_path"}, "Artifact metadata cannot contain worker filesystem paths.")
    return {k:_plain(v,depth+1) for k,v in value.items()}


def encode(value):
    raw=json.dumps(_plain(value),sort_keys=True,separators=(",",":"),ensure_ascii=True,allow_nan=False).encode("ascii")+b"\n"
    require(len(raw)<=MAX_LINE, "Artifact record exceeds the 2 MiB line bound.")
    return raw


def provenance(value):
    require(isinstance(value,dict) and set(value)=={"source_sha256","engine","operation","origin","parameters"}, "Artifact provenance requires source_sha256, engine, operation, origin and frozen parameters.")
    require(isinstance(value["source_sha256"],str) and HEX.fullmatch(value["source_sha256"]), "Artifact needs its immutable source SHA-256.")
    require(text(value["operation"],128) and text(value["origin"],128), "Declare operation and source origin.")
    engine=value["engine"]
    require(isinstance(engine,dict) and text(engine.get("name"),500) and isinstance(engine.get("worker_sha256"),str) and HEX.fullmatch(engine["worker_sha256"]), "Artifact engine needs its name and worker implementation SHA-256.")
    require(isinstance(value["parameters"],dict), "Frozen parameters must be an explicit object.")
    result=_plain(copy.deepcopy(value));encode(result)
    return result


def columns(specification):
    require(isinstance(specification,list) and 1<=len(specification)<=128, "Declare 1 to 128 typed table columns.")
    names=[]
    for c in specification:
        require(isinstance(c,dict) and set(c)=={"name","type","unit","nullable","role"}, "Each column requires name, type, unit, nullable and role.")
        require(isinstance(c["name"],str) and ID.fullmatch(c["name"]) and c["name"] not in names, "Column names must be distinct safe identifiers.")
        names.append(c["name"])
        require(c["type"] in TYPES and isinstance(c["nullable"],bool), "Declare a supported column type and boolean nullability.")
        require(c["unit"] is None or text(c["unit"],128), "Column unit must be explicit text or null for nonnumeric labels.")
        require(text(c["role"],128), "Declare each column's measurement/support/coordinate role.")
        if c["type"] in {"float64","integer"}: require(text(c["unit"],128), "Numeric columns need explicit units, including dimensionless or index units.")
    return copy.deepcopy(specification)


def scalar(value, column):
    if value is None:
        require(column["nullable"], f"Column {column['name']} does not allow null.")
        return None
    kind=column["type"]
    # NumPy scalar conversion is explicit here, but strings and bools cannot
    # become numbers. Arrays/structured objects never receive scalar coercion.
    if type(value).__module__.startswith("numpy") and getattr(value,"ndim",None)==0: value=value.item()
    if kind=="float64": require(isinstance(value,(int,float)) and not isinstance(value,bool) and math.isfinite(value), f"Column {column['name']} needs a finite number or declared null.");return float(value)
    if kind=="integer": require(isinstance(value,int) and not isinstance(value,bool) and abs(value)<=2**53-1, f"Column {column['name']} needs an exact bounded integer.");return value
    if kind=="boolean": require(isinstance(value,bool), f"Column {column['name']} needs true/false, not a numeric replacement.");return value
    require(isinstance(value,str) and len(value.encode("utf-8"))<=16000, f"Column {column['name']} needs bounded text.")
    return value


def table_spec(table_id, identity, specification, coordinates, support, row_count):
    require(isinstance(table_id,str) and ID.fullmatch(table_id), "Table ID must be a safe stable identifier.")
    require(isinstance(identity,dict) and text(identity.get("recording_id"),500) and text(identity.get("channel"),500), "Every table needs explicit source recording and channel identities.")
    require(isinstance(coordinates,dict) and set(coordinates)=={"axis","reference","source_time_origin","source_time_unit"}, "Declare axis, reference and original clock origin/unit; no coordinate inference is allowed.")
    require(coordinates["axis"] in {"time","frequency","event"} and text(coordinates["reference"]), "Declare time, frequency or event coordinates and their reference.")
    require(coordinates["source_time_origin"] is None or text(coordinates["source_time_origin"],500), "Source clock origins must be exact strings or explicitly unavailable.")
    require(coordinates["source_time_unit"] is None or text(coordinates["source_time_unit"],32), "Source clock unit must be explicit or unavailable.")
    require(isinstance(support,dict), "Declare source/sample support metadata, even when empty.")
    require(isinstance(row_count,int) and not isinstance(row_count,bool) and 0<=row_count<=MAX_ROWS, "Declare a bounded exact row count.")
    return _plain({"type":"table","table_id":table_id,"identity":identity,"columns":columns(specification),
                   "coordinates":coordinates,"support":support,"expected_rows":row_count})


class TableWriter:
    """One append-only typed NDJSON stream, finalized only after all rows verify."""
    def __init__(self,directory,kind,source_provenance,max_bytes=MAX_BYTES,chunk_rows=512,preview_limit=2000):
        directory=Path(directory)
        require(directory.is_dir() and not directory.is_symlink(), "Artifact directory must already be an ordinary local directory.")
        self.directory=directory.resolve(strict=True)
        require(kind in KINDS, "Unsupported processed physiology artifact kind.")
        require(isinstance(max_bytes,int) and not isinstance(max_bytes,bool) and 1<=max_bytes<=MAX_BYTES, "Artifact byte bound must be 1 to 2 GiB.")
        require(isinstance(chunk_rows,int) and not isinstance(chunk_rows,bool) and 1<=chunk_rows<=4096, "Chunk size must be 1 to 4,096 rows.")
        require(isinstance(preview_limit,int) and not isinstance(preview_limit,bool) and 0<=preview_limit<=2000, "Preview budget must be at most 2,000 rows.")
        self.kind,self.max_bytes,self.chunk_rows,self.preview_limit=kind,max_bytes,chunk_rows,preview_limit
        self.provenance=provenance(source_provenance)
        self.provenance_sha256=hashlib.sha256(encode(self.provenance)).hexdigest()
        self.bytes=0;self.rows=0;self.tables=0;self.ids=set();self.closed=False;self.failed=False;self.preview=[];self.manifest=None
        descriptor,name=tempfile.mkstemp(prefix=".brohn-processed-",suffix=".ndjson.tmp",dir=self.directory)
        self.temporary=Path(name);self.stream=os.fdopen(descriptor,"wb")
        try: self._write({"type":"header","schema":SCHEMA,"kind":kind,"provenance":self.provenance,"provenance_sha256":self.provenance_sha256})
        except BaseException: self.abort();raise

    def _write(self,record):
        require(not self.closed and not self.failed, "Artifact writer is closed or failed.")
        raw=encode(record)
        require(self.bytes+len(raw)<=self.max_bytes, "Complete artifact exceeds its byte bound; nothing may be silently truncated.")
        self.stream.write(raw);self.bytes+=len(raw)

    def write_table(self,table_id,identity,specification,coordinates,support,rows,row_count):
        try:
            require(not self.closed and not self.failed, "Artifact writer is closed or failed.")
            declaration=table_spec(table_id,identity,specification,coordinates,support,row_count)
            require(table_id not in self.ids and self.tables<MAX_TABLES and self.rows+row_count<=MAX_ROWS, "Duplicate table ID or artifact table/row bound exceeded.")
            self._write(declaration);fields=declaration["columns"];names=[c["name"] for c in fields]
            pending=[];offset=0
            for row in rows:
                require(offset+len(pending)<row_count, "Table produced more rows than declared.")
                if isinstance(row,dict):
                    require(set(row)==set(names), "Table row fields differ from its declared schema.")
                    row=[row[name] for name in names]
                require(isinstance(row,(list,tuple)) and len(row)==len(fields), "Table row width differs from its typed schema.")
                clean=[scalar(v,c) for v,c in zip(row,fields)];pending.append(clean)
                if len(self.preview)<self.preview_limit:
                    self.preview.append({"table_id":table_id,"row_index":offset+len(pending)-1,"values":clean})
                if len(pending)>=self.chunk_rows:
                    self._write({"type":"rows","table_id":table_id,"offset":offset,"rows":pending});offset+=len(pending);pending=[]
            if pending: self._write({"type":"rows","table_id":table_id,"offset":offset,"rows":pending});offset+=len(pending)
            require(offset==row_count, "Table ended before its declared row count; no incomplete receipt is published.")
            self._write({"type":"table_end","table_id":table_id,"rows":offset})
            self.rows+=offset;self.tables+=1;self.ids.add(table_id)
            return {"table_id":table_id,"rows":offset}
        except BaseException:
            self.failed=True;self.abort();raise

    def write_arrays(self,table_id,identity,arrays,specification,coordinates,support):
        try:
            declared=columns(specification);names=[c["name"] for c in declared]
            require(isinstance(arrays,dict) and set(arrays)==set(names), "Arrays must exactly match explicit processed columns; omit raw source arrays deliberately.")
            lengths=[len(arrays[name]) for name in names]
            require(len(set(lengths))==1, "Processed arrays must have the same length; never infer or resample coordinates.")
            count=lengths[0]
            return self.write_table(table_id,identity,declared,coordinates,support,([arrays[name][i] for name in names] for i in range(count)),count)
        except BaseException:
            self.failed=True;self.abort();raise

    def finish(self):
        if self.manifest is not None: return copy.deepcopy(self.manifest)
        try:
            require(not self.closed and not self.failed, "Cannot publish an incomplete or failed artifact.")
            self._write({"type":"complete","tables":self.tables,"rows":self.rows,"provenance_sha256":self.provenance_sha256})
            self.stream.flush();os.fsync(self.stream.fileno());self.stream.close();self.closed=True
            sha=digest_file(self.temporary);target=self.directory/(self.kind+"-"+sha+".ndjson")
            require(target.parent.resolve()==self.directory, "Artifact destination escaped its attempt directory.")
            if os.path.lexists(target):
                require(target.is_file() and not target.is_symlink() and target.stat().st_size==self.bytes and digest_file(target)==sha, "Existing hash-named artifact is corrupt or not an ordinary file.")
                self.temporary.unlink()
            else: os.replace(self.temporary,target)
            self.manifest={"kind":self.kind,"path":str(target),"sha256":sha,"bytes":self.bytes,"schema":SCHEMA,
                           "media_type":"application/x-ndjson","tables":self.tables,"rows":self.rows,"provenance_sha256":self.provenance_sha256,
                           "complete":True,"preview_rows":len(self.preview),"preview_policy":"first_rows_only_for_diagnostics; not scientific sampling"}
            return copy.deepcopy(self.manifest)
        except BaseException:
            self.failed=True;self.abort();raise

    def abort(self):
        if not self.closed:
            self.stream.close();self.closed=True
        # Only this writer's mkstemp file can be removed. Published content is
        # left to the owning attempt's verified scratch lifecycle.
        if self.temporary.parent==self.directory and self.temporary.name.startswith(".brohn-processed-") and self.temporary.exists(): self.temporary.unlink()

    def __enter__(self): return self
    def __exit__(self,kind,value,traceback):
        if kind is not None or self.manifest is None: self.abort()


def _unique(pairs):
    result={}
    for key,value in pairs:
        require(key not in result,"Duplicate artifact JSON field.");result[key]=value
    return result


def _read_records(path):
    with Path(path).open("rb") as stream:
        while True:
            raw=stream.readline(MAX_LINE+1)
            if not raw: return
            require(len(raw)<=MAX_LINE and raw.endswith(b"\n"), "Artifact has an overlong or incomplete line.")
            try: record=json.loads(raw,object_pairs_hook=_unique,parse_constant=lambda x: (_ for _ in ()).throw(ArtifactError("Nonfinite artifact JSON.")))
            except (UnicodeDecodeError,json.JSONDecodeError) as error: raise ArtifactError("Malformed artifact JSON.") from error
            require(isinstance(record,dict), "Artifact lines must be typed objects.")
            yield record


def verify_artifact(manifest,directory=None,on_table=None,on_rows=None):
    """Verify entire immutable file, then stream bounded typed chunks to a caller.

    Callbacks run only after size/hash verification; a structural failure raises
    and callers must discard provisional callback output until return succeeds.
    """
    require(isinstance(manifest,dict) and manifest.get("kind") in KINDS and manifest.get("schema")==SCHEMA and manifest.get("complete") is True, "Unsupported or incomplete artifact manifest.")
    sha=manifest.get("sha256");path=Path(manifest.get("path",""))
    require(isinstance(sha,str) and HEX.fullmatch(sha) and path.is_file() and not path.is_symlink(), "Artifact is absent, not ordinary or has an invalid hash.")
    resolved=path.resolve(strict=True)
    if directory is not None: require(resolved.parent==Path(directory).resolve(strict=True), "Artifact leaves its declared attempt directory.")
    require(isinstance(manifest.get("bytes"),int) and 1<=manifest["bytes"]<=MAX_BYTES and resolved.stat().st_size==manifest["bytes"] and digest_file(resolved)==sha, "Artifact size or SHA-256 mismatch.")
    records=iter(_read_records(resolved));header=next(records,None)
    require(isinstance(header,dict) and set(header)=={"type","schema","kind","provenance","provenance_sha256"} and header["type"]=="header" and header["schema"]==SCHEMA and header["kind"]==manifest["kind"], "Artifact header does not match its manifest.")
    p=provenance(header["provenance"]);ph=hashlib.sha256(encode(p)).hexdigest()
    require(ph==header["provenance_sha256"]==manifest.get("provenance_sha256"), "Artifact provenance hash mismatch.")
    active=None;offset=0;row_total=0;table_total=0;ids=set();complete=False
    for record in records:
        require(not complete, "Records occur after the completion receipt.")
        kind=record.get("type")
        if kind=="table":
            require(active is None and set(record)=={"type","table_id","identity","columns","coordinates","support","expected_rows"}, "Invalid or nested table declaration.")
            active=table_spec(record["table_id"],record["identity"],record["columns"],record["coordinates"],record["support"],record["expected_rows"])
            require(active["table_id"] not in ids and table_total<MAX_TABLES, "Duplicate table ID or too many tables.")
            offset=0
            if on_table: on_table(copy.deepcopy(active))
        elif kind=="rows":
            require(active is not None and set(record)=={"type","table_id","offset","rows"} and record["table_id"]==active["table_id"] and record["offset"]==offset, "Artifact chunk is out of sequence or belongs to another table.")
            rows=record["rows"]
            require(isinstance(rows,list) and 1<=len(rows)<=4096 and offset+len(rows)<=active["expected_rows"], "Chunk rows violate the declared table count.")
            for row in rows:
                require(isinstance(row,list) and len(row)==len(active["columns"]), "Artifact row has the wrong width.")
                for value,column in zip(row,active["columns"]): scalar(value,column)
            if on_rows: on_rows(active["table_id"],offset,rows)
            offset+=len(rows)
        elif kind=="table_end":
            require(active is not None and set(record)=={"type","table_id","rows"} and record["table_id"]==active["table_id"] and record["rows"]==offset==active["expected_rows"], "Incomplete table receipt.")
            ids.add(active["table_id"]);table_total+=1;row_total+=offset;active=None
            require(row_total<=MAX_ROWS,"Artifact row bound exceeded.")
        elif kind=="complete":
            require(active is None and set(record)=={"type","tables","rows","provenance_sha256"} and record["tables"]==table_total==manifest.get("tables") and
                    record["rows"]==row_total==manifest.get("rows") and record["provenance_sha256"]==ph, "Final artifact receipt does not match its tables/counts/provenance.")
            complete=True
        else: raise ArtifactError("Unknown artifact record type.")
    require(complete and active is None, "Artifact ended before its complete receipt.")
    # Hash again after callbacks/streaming to detect replacement during reading.
    require(resolved.stat().st_size==manifest["bytes"] and digest_file(resolved)==sha,"Artifact changed during verification.")
    return {"schema":SCHEMA,"kind":manifest["kind"],"rows":row_total,"tables":table_total,"provenance":p,"verified":True}


def _column(name,kind,unit,nullable=False,role="processed_measure"):
    return {"name":name,"type":kind,"unit":unit,"nullable":nullable,"role":role}


def write_physiology_bundle(series_writer,event_writer,modality,identity,bundle,source_support,source_time_unit,table_prefix):
    """Adapter for existing physiology.dispatch bundles, before event mutation.

    Source support comes from the existing continuous-segment summary. It must
    contain exact source-row bounds, canonical amplitude unit and original clock
    origin. This helper does not run a method or turn display rows into full data.
    """
    require(modality in {"eda","eeg","ecg","ppg","respiration","emg"}, "This adapter only accepts registered physiology dispatch bundles.")
    require(series_writer.kind=="physiology-series" and event_writer.kind=="physiology-events", "Use the matching series and event artifact streams.")
    require(isinstance(source_support,dict) and {"source_row_start","source_row_end_exclusive","source_time_origin","unit"}<=set(source_support), "Full-series adapter needs original source-row bounds, clock origin and canonical unit.")
    start,end=source_support["source_row_start"],source_support["source_row_end_exclusive"]
    require(isinstance(start,int) and isinstance(end,int) and 0<=start<end, "Declare an increasing original source row interval.")
    require(isinstance(bundle,dict) and all(k in bundle for k in ("series","events","parameters","support")), "Expected a complete pre-display physiology bundle.")
    series=bundle["series"]
    require("time_s" in series and len(series["time_s"])==end-start, "Processed series must exactly match its source-row interval.")
    require(text(source_support["source_time_origin"],500) and text(source_time_unit,32), "Declare the original clock's exact origin and unit.")
    coordinates={"axis":"time","reference":"seconds relative to original recording start; no source timestamp rebasing",
                 "source_time_origin":source_support["source_time_origin"],"source_time_unit":source_time_unit}
    support={"source":source_support,"method":bundle["parameters"],"retained_support":bundle["support"],
             "raw_source_omitted":True,"source_sample_index_definition":"zero-based original source row/sample index"}
    time=_column("time_s","float64","s",role="coordinate")
    index=_column("source_sample_index","integer","sample_index",role="index")
    retained=_column("retained","boolean",None,role="support")
    if modality=="eda": selected=[time,index,*[_column(k,"float64","uS") for k in ("clean_us","tonic_us","phasic_us")],retained]
    elif modality=="emg": selected=[time,index,*[_column(k,"float64","uV") for k in ("clean_uv","rms_uv")],retained]
    elif modality in {"ecg","ppg","respiration"}: selected=[time,index,_column("clean","float64",source_support["unit"]),retained]
    else: selected=[] # Welch's only time-domain values are raw source voltage.
    output=[]
    if selected:
        names=[c["name"] for c in selected]
        require(set(names)-{"source_sample_index"}<=set(series), "Registered processed arrays are missing from the source bundle.")
        arrays={name:(range(start,end) if name=="source_sample_index" else series[name]) for name in names}
        output.append(series_writer.write_arrays(table_prefix+"-samples",identity,arrays,selected,coordinates,support))
    base=[_column("type","string",None,role="label")]
    if modality=="eda":
        event_columns=base+[_column("time_s","float64","s",role="coordinate"),_column("peak_sample","integer","segment_sample_index",role="index"),
            _column("source_peak_sample","integer","sample_index",role="index"),
            *[_column(k,"float64","s",True,role="derived_event") for k in ("onset_time_s","recovery_time_s")],
            *[_column(k,"float64","uS",True) for k in ("amplitude_us","peak_height_us")],
            *[_column(k,"float64","s",True) for k in ("rise_time_s","recovery_time_from_peak_s")],
            _column("recovery_fraction","float64","proportion"),_column("missing_reason","string",None,True,role="support")]
    elif modality=="eeg":
        event_columns=base+[_column("frequency_hz","float64","Hz",role="coordinate"),_column("density_uv2_hz","float64","uV^2/Hz")]
        coordinates={**coordinates,"axis":"frequency","reference":"declared Welch frequency bins; no temporal event interpretation"}
    elif modality in {"ecg","ppg"}:
        event_columns=base+[time,_column("sample_index","integer","segment_sample_index",role="index"),index,
                           _column("previous_interval_ms","float64","ms",True),_column("previous_interval_plausible","boolean",None,True,role="support")]
    elif modality=="respiration":
        event_columns=base+[time,*[_column(k,"float64","s",role="derived_event") for k in ("end_time_s","peak_time_s","duration_s","inspiration_s","expiration_s")],
                           _column("amplitude","float64",source_support["unit"])]
    else:
        event_columns=base+[time,*[_column(k,"float64","s",role="derived_event") for k in ("end_time_s","duration_s")],
                           _column("peak_rms_uv","float64","uV"),_column("boundary_truncated","boolean",None,role="support")]
        support={**support,"end_time_policy":"source worker's exclusive sample-cell boundary; final observed timestamp plus one declared sample interval"}
    if modality!="eeg": coordinates={**coordinates,"axis":"event"}
    def event_rows():
        for event in bundle["events"]:
            item=copy.deepcopy(event)
            for field,destination in (("peak_sample","source_peak_sample"),("sample_index","source_sample_index")):
                if field in item:
                    value=item[field]
                    if type(value).__module__.startswith("numpy"): value=value.item()
                    require(isinstance(value,int) and not isinstance(value,bool) and 0<=value<end-start, "Candidate index is outside its declared source segment.")
                    item[field]=value;item[destination]=start+value
            yield item
    output.append(event_writer.write_table(table_prefix+"-events",identity,event_columns,coordinates,support,event_rows(),len(bundle["events"])))
    return output


class ArtifactSet:
    """A job's two streams; publish manifests only after both close successfully."""
    def __init__(self,directory,source_provenance):
        self.series=TableWriter(directory,"physiology-series",source_provenance,preview_limit=0)
        try: self.events=TableWriter(directory,"physiology-events",source_provenance,preview_limit=0)
        except BaseException: self.series.abort();raise
    def finish(self):
        try:
            result=[]
            for writer in (self.series,self.events):
                if writer.tables: result.append(writer.finish())
                else: writer.abort()
            return result
        except BaseException: self.abort();raise
    def abort(self):
        self.series.abort();self.events.abort()
    def __enter__(self): return self
    def __exit__(self,kind,value,traceback): self.abort()


def write_eda_event_segment(writers,identity,bundle,source_support,source_time_unit,parameters,table_prefix):
    """Adapter for full continuous EDA-event segments, before display selection."""
    start,end=source_support["source_row_start"],source_support["source_row_end_exclusive"]
    require(isinstance(start,int) and isinstance(end,int) and 0<=start<end and len(bundle["times"])==end-start, "EDA segment source rows disagree with its processed sample count.")
    coordinates={"axis":"time","reference":"seconds relative to original source recording start",
                 "source_time_origin":source_support["source_time_origin"],"source_time_unit":source_time_unit}
    support={"source":source_support,"parameters":parameters,"raw_source_omitted":True,
             "detector_error":bundle["detector_error"],"source_sample_index_definition":"zero-based original source sample row"}
    fields=[_column("time_s","float64","s",role="coordinate"),_column("source_sample_index","integer","sample_index",role="index"),
            *[_column(k,"float64","uS") for k in ("clean_us","tonic_us","phasic_us")],_column("retained","boolean",None,role="support")]
    arrays={"time_s":bundle["times"],"source_sample_index":range(start,end),**{k:bundle[k] for k in ("clean_us","tonic_us","phasic_us","retained")}}
    writers.series.write_arrays(table_prefix+"-samples",identity,arrays,fields,coordinates,support)
    fields=[_column("type","string",None,role="label"),_column("peak_time_s","float64","s",role="coordinate"),
            _column("peak_sample_index","integer","segment_sample_index",role="index"),_column("source_peak_sample","integer","sample_index",role="index"),
            *[_column(k,"float64","s",True,role="derived_event") for k in ("onset_time_s","recovery_time_s")],
            *[_column(k,"float64","uS",True) for k in ("amplitude_us","peak_height_us")],_column("recovery_fraction","float64","proportion"),
            *[_column(k,"boolean",None,role="support") for k in ("onset_supported","recovery_supported")]]
    def rows():
        for c in bundle["candidates"]:
            require(0<=c["peak_sample_index"]<end-start,"SCR candidate lies outside its source segment.")
            yield {**c,"source_peak_sample":start+c["peak_sample_index"]}
    writers.events.write_table(table_prefix+"-candidates",identity,fields,{**coordinates,"axis":"event"},support,rows(),len(bundle["candidates"]))


def verify_manifest(items,directory=None):
    require(isinstance(items,list) and 1<=len(items)<=2,"Verification requires one or two physiology artifact manifests.")
    require(all(isinstance(m,dict) for m in items) and len({m.get("kind") for m in items})==len(items),"Artifact kinds must be distinct.")
    verified=[]
    for item in items:
        result=verify_artifact(item,directory)
        verified.append({"kind":item["kind"],"sha256":item["sha256"],"bytes":item["bytes"],"schema":SCHEMA,
                         "tables":result["tables"],"rows":result["rows"],"provenance_sha256":item["provenance_sha256"],"verified":True})
    return {"schema":"brohn-physiology-artifact-receipt/1.0","status":"verified","artifacts":verified}


def main():
    import argparse
    import sys
    parser=argparse.ArgumentParser(description="Verify complete typed physiology artifacts before fenced publication.")
    parser.add_argument("--verify-manifest",type=Path,required=True)
    parser.add_argument("--directory",type=Path)
    parser.add_argument("--output",type=Path,required=True)
    args=parser.parse_args();code=0
    safe=not os.path.lexists(args.output) and args.output.resolve()!=args.verify_manifest.resolve()
    try:
        require(safe,"Verification receipt must use a new output path; no existing file may be replaced.")
        require(args.verify_manifest.is_file() and args.verify_manifest.stat().st_size<=1024**2,"Artifact manifest exceeds 1 MiB or is absent.")
        items=json.loads(args.verify_manifest.read_text(encoding="utf-8"),object_pairs_hook=_unique,
                         parse_constant=lambda x: (_ for _ in ()).throw(ArtifactError("Nonfinite manifest JSON.")))
        result=verify_manifest(items,args.directory)
    except Exception as error:
        code=2;result={"schema":"brohn-physiology-artifact-receipt/1.0","status":"error","error":{"type":type(error).__name__,"message":str(error)[:1000]}}
    if not safe:
        print(json.dumps(result),file=sys.stderr);return code
    require(args.output.parent.is_dir(),"Receipt directory must already exist.")
    descriptor,name=tempfile.mkstemp(prefix=".brohn-artifact-verification-",suffix=".json.tmp",dir=args.output.parent)
    try:
        with os.fdopen(descriptor,"wb") as stream: stream.write(encode(result));stream.flush();os.fsync(stream.fileno())
        os.replace(name,args.output)
    finally:
        if os.path.exists(name): os.unlink(name)
    print(json.dumps({"status":result["status"],"artifacts":len(result.get("artifacts",[]))}));return code


if __name__=="__main__": raise SystemExit(main())

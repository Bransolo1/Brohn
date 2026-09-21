"""Reader compatibility of production-worker artifacts; no accuracy qualification."""
import csv
import hashlib
import importlib.util
import json
import math
from pathlib import Path
import sqlite3
import sys

ROOT=Path(__file__).resolve().parents[2]
def module(name,file):
    s=importlib.util.spec_from_file_location(name,ROOT/file);m=importlib.util.module_from_spec(s);s.loader.exec_module(m);return m
w=module("profile_values","scripts/workers/signal_values.py")
mode=sys.argv[1];folder=Path(sys.argv[2]);folder.mkdir(parents=True,exist_ok=True)

def check_artifacts(manifests,receipt,label):
    checks=[]
    for manifest in manifests:
        descriptor=w.preview.catalog({"page":{"offset":0,"limit":200}},manifest)
        assert descriptor["pagination"]["total_tables"]<=200,"Explicit fixture catalog bound exceeded"
        original={};declarations={}
        w.artifacts.verify_artifact(manifest,on_table=lambda t:declarations.update({t["table_id"]:t}),on_rows=lambda tid,offset,rows:original.setdefault(tid,[]).extend(rows))
        for table in descriptor["tables"]:
            for measure in table["value_columns"]:
                stem=hashlib.sha256((label+manifest["kind"]+table["table_id"]+measure["name"]).encode()).hexdigest()[:20]
                request={"schema":"brohn-signal-values-request/1.0","operation":"signal_values_export","artifact":manifest,"verification_receipt":receipt,
                    "binding":{"report_id":"compatibility-"+stem,"report_revision":1,"report_hash":"1"*64,"project_id":"reader-compatibility","catalog_id":"catalog-"+stem,"catalog_revision":1,"catalog_hash":"2"*64,"selection_hash":"3"*64},
                    "table":table,"selection":{"table_id":table["table_id"],"recording_id":table["identity"]["recording_id"],"channel":table["identity"]["channel"],"value_column":measure["name"],"range":None,"row_policy":"all_source_rows"},"export_path":str(folder/(stem+".csv"))}
                result=w.run(request)
                with Path(request["export_path"]).open(encoding="utf-8",newline="") as f:exported=list(csv.DictReader(f))
                native=original.get(table["table_id"],[]);columns=declarations[table["table_id"]]["columns"];names=[c["name"] for c in columns]
                assert len(exported)==len(native)==table["rows"]
                coordinate=table["coordinate_column"]
                for number,(actual,row) in enumerate(zip(exported,native)):
                    assert actual["table_row_index"]==str(number)
                    for out,column in [("coordinate",coordinate),("value",measure)]:
                        value=row[names.index(column["name"])];assert actual[out+"_is_null"]==("true" if value is None else "false")
                        if value is None:assert actual[out]==""
                        elif column["type"]=="float64":assert float(actual[out]).hex()==float(value).hex()
                        else:assert int(actual[out])==value
                    assert json.loads(actual["exact_record_json"])==dict(zip(names,row))
                    retention="not_declared" if "retained" not in names else "retained" if row[names.index("retained")] is True else "excluded" if row[names.index("retained")] is False else "unknown"
                    assert actual["retention"]==retention
                request.pop("export_path");request.update(operation="signal_values_page",page={"offset":0,"limit":25});page=w.run(request)
                assert page["full_source"]["rows"]==len(native) and len(page["rows"])==min(25,len(native))
                checks.append({"source":label,"kind":manifest["kind"],"table_id":table["table_id"],"measure":measure["name"],"unit":measure["unit"],"axis":table["coordinates"]["axis"],"rows":len(native),"artifact_sha256":manifest["sha256"],"export_sha256":result["csv"]["sha256"],"output":stem+".csv"})
    return checks

if mode in {"respiration","emg","audio","fnirs"}:
    import numpy as np
    physiology=module("profile_physiology","scripts/workers/physiology.py")
    if mode in {"respiration","emg"}:
        fixture=module("profile_parameters","tests/workers/physiology.py");case=fixture.PhysiologyTests();case.root=folder
        fs=100 if mode=="respiration" else 500;t=np.arange(6000 if mode=="respiration" else 5000)/fs
        values=np.sin(2*np.pi*(.2 if mode=="respiration" else 80)*t)
        request=case.request(mode,values,fs,parameters=fixture.RESPIRATION_DECLARATION if mode=="respiration" else {"burst_threshold_uv":.2})
    elif mode=="audio":
        import soundfile as sf
        fs=16000;t=np.arange(fs*30)/fs;source=folder/"original-tone.wav";sf.write(source,.25*np.sin(2*np.pi*200*t),fs,subtype="FLOAT")
        request=dict(schema="brohn-worker-request/1.0",operation="physiology",modality="audio",source_path=str(source),format="wav",metadata=dict(unit="FS",sampling_rate=fs,participant_id="fixture",session_id="original",origin="sample"))
    else:
        from snirf import Snirf
        fs=10;t=np.arange(3000)/fs;values=np.column_stack([100+2*np.sin(2*np.pi*1.1*t)+.4*np.sin(2*np.pi*.04*t),110+2*np.sin(2*np.pi*1.1*t)+.5*np.sin(2*np.pi*.04*t)])
        source=folder/"original-intensity.snirf"
        with Snirf(str(source),"w") as snirf:
            snirf.formatVersion="1.1";snirf.nirs.appendGroup();nirs=snirf.nirs[0]
            nirs.metaDataTags.SubjectID="synthetic";nirs.metaDataTags.MeasurementDate="2026-09-20";nirs.metaDataTags.MeasurementTime="00:00:00Z"
            nirs.metaDataTags.LengthUnit="mm";nirs.metaDataTags.TimeUnit="s";nirs.metaDataTags.FrequencyUnit="Hz"
            nirs.probe.wavelengths=np.array([760.,850.]);nirs.probe.sourcePos3D=np.array([[0.,0.,0.]]);nirs.probe.detectorPos3D=np.array([[30.,0.,0.]])
            nirs.data.appendGroup();data=nirs.data[0];data.time=t;data.dataTimeSeries=values
            for wavelength in [1,2]:
                data.measurementList.appendGroup();item=data.measurementList[-1];item.sourceIndex=1;item.detectorIndex=1;item.wavelengthIndex=wavelength;item.dataType=1;item.dataTypeIndex=1
            snirf.save()
        request=dict(schema="brohn-worker-request/1.0",operation="physiology",modality="fnirs",source_path=str(source),format="snirf",metadata=dict(unit="native",value_columns=["S1_D1 760","S1_D1 850"],sampling_rate=fs,participant_id="fixture",session_id="original",origin="sample"),parameters=dict(ppf=[6,6]))
    request["artifact_directory"]=str(folder/"artifacts");(folder/"artifacts").mkdir()
    (folder/"request.json").write_text(json.dumps(request),encoding="utf-8")
    result=physiology.run(request);(folder/"actual-worker-result.json").write_text(json.dumps(result,allow_nan=False),encoding="utf-8")
    assert result["artifacts"],result.get("status")
    receipt=w.artifacts.verify_manifest(result["artifacts"])
    checks=check_artifacts(result["artifacts"],receipt,"actual-production-worker-original-synthetic-"+mode)
elif mode in {"retained","recorded"}:
    if mode=="recorded":
        proof=json.loads((Path(sys.argv[3])/"acceptance.json").read_text());workspace=Path(proof["workspace"])
        connection=sqlite3.connect("file:"+(workspace/"catalog.sqlite").as_posix()+"?mode=ro",uri=True);inventory=[]
        for family,record in proof["reports"].items():
            body=json.loads(connection.execute("SELECT v.body_json FROM entities e JOIN entity_versions v ON v.kind=e.kind AND v.id=e.id AND v.revision=e.revision WHERE e.kind='report' AND e.id=?",(record["report_id"],)).fetchone()[0])
            inventory.append({"workspace":str(workspace),"report_id":record["report_id"],"kind":family,"artifacts":body["analysis"]["artifacts"],"verification":body["analysis"]["artifact_verification"]})
        connection.close();wanted={"ecg","ppg"}
    else:inventory=json.loads(Path(sys.argv[3]).read_text(encoding="utf-8-sig"));wanted={"eda","eeg","temperature","movement"}
    chosen={};checks=[]
    for item in inventory:
        if item["kind"] in wanted and item["kind"] not in chosen and item.get("verification"):
            chosen[item["kind"]]=item
    assert set(chosen)==wanted,set(chosen)
    for family,item in chosen.items():
        workspace=Path(item["workspace"]);database=next(workspace.glob("*.sqlite*"));connection=sqlite3.connect("file:"+database.as_posix()+"?mode=ro",uri=True)
        manifests=[]
        for a in item["artifacts"]:
            if a["kind"] not in {"physiology-series","physiology-events"}:continue
            row=connection.execute("SELECT size FROM objects WHERE hash=?",(a["hash"],)).fetchone();assert row and row[0]==a["size"]
            manifests.append({"kind":a["kind"],"sha256":a["hash"],"bytes":a["size"],"complete":True,"path":str(workspace/"objects"/"sha256"/a["hash"][:2]/a["hash"]),**{k:a[k] for k in ["schema","tables","rows","provenance_sha256"]}})
        connection.close();checks.extend(check_artifacts(manifests,item["verification"],"retained-actual-worker-"+family+"-"+item["report_id"]))
else:raise ValueError("Unknown profile")
(folder/"acceptance.json").write_text(json.dumps({"checks":checks,"scope":"Exact output-reader compatibility; no new scientific accuracy or hardware claim","worker_sha256":hashlib.sha256((ROOT/"scripts/workers/signal_values.py").read_bytes()).hexdigest()},indent=2),encoding="utf-8")
print(json.dumps({"profile":mode,"exact_table_measure_exports":len(checks),"rows_compared":sum(x["rows"] for x in checks),"output":str(folder)}))

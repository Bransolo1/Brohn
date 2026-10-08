"""Saved cardiac report preparation. No scientific processing or catalog access."""
from __future__ import annotations
import argparse
import copy
import hashlib
import platform
from pathlib import Path
import tempfile

import physiology_artifacts as tables
from cardiac_values import fields, strict_json, json_bytes, value_hash
from cardiac_display_core import (require, same, limit, Refusal, MIB, HASH, COUNTS, ref_valid, identity,
    cell_key, display_request, sealed_registry, bound_path, check_objects, OutputFiles, validate_analysis,
    VerifiedIndex, table_ref, export_csv)
import cardiac_display_policy as policy
import cardiac_display_geometry as geometry
import cardiac_display_lineage as lineage

PROFILE = "saved-cardiac-display/0.1"


def available(status="available", reason=None):
    return dict(status=status, reason_code=reason, original_reason=reason)


def file_json(path, maximum=48*MIB):
    limit(path.stat().st_size, maximum, "sealed_json_bytes")
    return strict_json(path.read_bytes())


def check_request(request):
    fields(request, ("schema", "report", "source", "source_closure", "display_request", "implementation", "streams",
                     "original_source", "sealed_objects", "lineage"), "Sealed cardiac display request")
    require(request["schema"] == "brohn-cardiac-display-worker-request/0.1", "Unsupported sealed request schema.")
    limit(len(json_bytes(request)), 48*MIB, "sealed_request_bytes")
    fields(request["report"], ("ref", "saved_body", "complete_analysis"), "Original report")
    source = request["source"]
    fields(source, ("report_ref", "analysis_hash", "analysis_value_hash", "dataset_ref", "result_object",
                   "original_stream_descriptors", "source_closure_hash"), "Exact saved source binding")
    for name in ("report_ref", "dataset_ref"):
        ref_valid(source[name])
    for name in ("analysis_hash", "analysis_value_hash", "source_closure_hash"):
        require(isinstance(source[name], str) and HASH.fullmatch(source[name]), "Invalid native/typed source hash.")
    require(same(request["report"]["ref"], source["report_ref"]), "Original report reference differs from source binding.")
    report = request["report"]
    require(same(report["saved_body"].get("analysis"), report["complete_analysis"]) and
            value_hash(report["complete_analysis"]) == source["analysis_value_hash"], "Complete analysis changed from sealed original.")
    require(report["saved_body"].get("id") == source["report_ref"]["id"] and
            report["saved_body"].get("dataset_id") == source["dataset_ref"]["id"], "Original report dataset/identity changed.")
    obj = source["result_object"]
    fields(obj, ("hash", "bytes", "media_type", "schema"), "Retained result reference")
    original = report["saved_body"].get("result_object", {})
    require(obj["hash"] == original.get("hash") and obj["bytes"] == original.get("size", original.get("bytes")) and
            obj["media_type"] == original.get("media_type") and obj["schema"] == "brohn-analysis-output/1.0", "Retained result descriptor differs.")
    require(isinstance(request["source_closure"], dict) and isinstance(request["implementation"], dict) and
            request["implementation"].get("profile") == PROFILE, "Missing source graph or implementation identity.")
    fields(request["lineage"], ("exclusion", "curation"), "Complete source lineage")
    normalized = display_request(request["display_request"])
    require(same(normalized, request["display_request"]), "Worker requires the exact normalized display request.")
    return normalized


def catalogue(record, ordinal, ref, analysis, domains, counts, key, figure, request):
    computed = record["status"] == "computed"
    reason = record.get("reason")
    component = available() if computed else available("unavailable", reason)
    peak_availability = (available() if counts["peaks"] else available("empty", "no_saved_detections")) if computed else available("unavailable", reason)
    interval_availability = (available() if counts["intervals"] else available("empty", "no_saved_intervals")) if computed else available("unavailable", reason)
    spectral = record.get("interval_spectrum", {})
    spectrum = available() if "spectrum" in domains else available("unavailable", spectral.get("unavailable_reason", reason))
    bounds = dict(start_s=policy.text_decimal(policy.coordinate(record["start_time_s"])), end_s=policy.text_decimal(policy.coordinate(record["end_time_s"])))
    require(max(abs(policy.coordinate(record[k])) for k in ("start_time_s", "end_time_s")) <= policy.Decimal("1e12"), "Source coordinate extent is outside the registered profile.")
    window_count = 0
    if computed:
        if request["time_focus"] is not None:
            window_count = 1
        else:
            try:
                window_count = policy.canonical_window_count(record["start_time_s"], record["end_time_s"])
            except policy.WindowLimit as error:
                if figure:
                    raise Refusal("canonical_window_count_limit", cell=key, resource="canonical_windows", measured=error.measured,
                                  maximum=20000, recovery="smaller_window", stage="display") from error
                # Evidence-only records have no active window index; source bounds stay available.
                window_count = 0
    refs = {name:table_ref(domains[name]) if name in domains else None for name in ("samples", "peaks", "spectrum")}
    return dict(kind="cardiac_cell", key=key, source_record_index=ordinal, identity=identity(record),
                binding_hash=value_hash(dict(source_record=record,tables=refs)), source_record_value_hash=value_hash(record),
                modality=analysis["kind"], interval_basis="detected_rr" if analysis["kind"] == "ecg" else "detected_prv",
                source_status=record["status"], original_reason=reason,
                label=f"{record['recording_id']} / {record['channel']} / {record['segment_id']}", unit=record["unit"],
                source_time_origin=record["source_time_origin"], source_time_unit=analysis["source"]["time_unit"],
                source_sample_start=record["source_row_start"], source_sample_end_exclusive=record["source_row_end_exclusive"],
                original_bounds=bounds, tables=refs, components=dict(raw=component,clean=component), detections=peak_availability,
                intervals=interval_availability, spectrum=spectrum, counts=counts, all_marker_joins_checked=True, model_hash=None,
                figure_state="unavailable" if not computed else "illustrated" if figure else "evidence_only",
                waveform_window_count=window_count, interval_page_count=(counts["peaks"]+1999)//2000,
                numerical_page_counts={name:(refs[name]["rows"]+49)//50 if refs[name] else 0 for name in refs},
                scientifically_qualified=False, normal_to_normal_confirmed=False)


def prepare(request, directory, pulse=None):
    normalized = check_request(request)
    report, source = request["report"], request["source"]
    analysis = report["complete_analysis"]
    modality = validate_analysis(analysis)
    registry = sealed_registry(request["sealed_objects"])
    check_objects(registry, pulse)
    original_path = bound_path(request["original_source"], registry)
    require(request["original_source"]["hash"] == analysis["source"]["sha256"] and
            request["original_source"]["bytes"] == analysis["source"]["bytes"], "Original source is not the saved analysis input.")
    retained = [Path(p) for p,o in registry.items() if o["hash"] == source["result_object"]["hash"] and o["bytes"] == source["result_object"]["bytes"]]
    require(retained, "Original retained result is not in the sealed object registry.")
    envelope = file_json(retained[0])
    require(envelope.get("schema") == "brohn-analysis-output/1.0" and same(envelope.get("report", {}).get("analysis"), analysis),
            "Original retained envelope does not contain the exact saved complete analysis.")
    require(same(source["original_stream_descriptors"], analysis["artifacts"]) and
            same([s["original"] for s in request["streams"]], analysis["artifacts"]), "Original stream membership or order changed.")
    receipt = analysis.get("artifact_verification")
    require((receipt is None and not request["streams"]) or (isinstance(receipt,dict) and
            receipt.get("schema") == "brohn-physiology-artifact-receipt/1.0" and receipt.get("status") == "verified" and
            same([s["original_verification"] for s in request["streams"]], receipt.get("artifacts"))), "Original complete stream receipts changed.")
    outputs = OutputFiles(directory)
    source_analysis = outputs.json("source-analysis.json", analysis, analysis["schema"], "complete_original_analysis")
    exclusion_binding, exclusion_object = lineage.exclusion(request["lineage"]["exclusion"], report, outputs)
    curation_objects = lineage.curation(request["lineage"]["curation"], request["original_source"], analysis, registry, outputs, pulse)
    # Private paths exist only in the sealed input. The complete authority graph and
    # original snapshot bodies are exported verbatim; bindings are never substituted.
    public_lineage = copy.deepcopy(request["lineage"])
    if public_lineage["curation"]:
        for name in ("decisions_object", "derived_csv_object"):
            public_lineage["curation"][name].pop("path")
    closure = outputs.json("source-closure.json", dict(source_closure=request["source_closure"], lineage=public_lineage),
                           "brohn-cardiac-complete-source-closure/0.1", "complete_original_lineage")
    originals = analysis["recordings"]
    keys = [cell_key(report["ref"], i+1, r) for i,r in enumerate(originals)]
    require(len(set(keys)) == len(keys), "Original cardiac cell keys collide.")
    selector = normalized["figure_cells"]
    require(set(selector["keys"]) <= set(keys), "An explicitly selected figure cell does not exist in this exact source.")
    chosen = set(keys[:10] if selector["scope"] == "first_chapter" else keys if selector["scope"] == "all_cells" else selector["keys"])
    overrides = {x["cell_key"]:x for x in normalized["cell_overrides"]}
    require(set(overrides) <= set(keys), "A display override names an absent original cell.")
    default = dict(time_focus=None, waveform_windows=dict(mode="first",numbers=[]), marker_pages=dict(mode="all",numbers=[]),
                   interval_pages=dict(mode="first",numbers=[]), numerical_pages=dict(mode="first",numbers=[]))
    features = {key:[] for key in keys}
    for i,f in enumerate(analysis["features"]):
        matches = [key for key,r in zip(keys, originals) if same(identity(f),identity(r))]
        require(len(matches) == 1, "A saved feature is not bound to exactly one original cell.")
        features[matches[0]].append(i)
    cells, catalog, source_counts, numerical = [], [], dict.fromkeys(COUNTS,0), []
    panels = 0
    model_bytes = 2
    with tempfile.TemporaryDirectory(prefix="cardiac-source-index-",dir=outputs.directory.parent) as scratch:
        index = None
        try:
            index = VerifiedIndex(request["streams"],analysis,registry,scratch,outputs,pulse)
            for item in index.tables:
                export_csv(index,item,outputs)
            complete = []
            # ALL cells/joins validate before any figure allocation or figure refusal.
            for ordinal,(record,key) in enumerate(zip(originals,keys),1):
                domains = index.cell_tables(record)
                counts, markers = geometry.complete_cell(index,domains,record,len(features[key]),ordinal,outputs,modality)
                saved_features = {analysis["features"][i]["name"]:analysis["features"][i] for i in features[key]}
                require(len(saved_features) == len(features[key]), "Duplicate saved feature in one source cell.")
                if domains:
                    prefix = "detected_rr" if modality == "ecg" else "detected_prv"
                    for name,count in (("detected_peak_count",counts["peaks"]),(prefix+"_interval_count",counts["intervals"]),
                                       (prefix+"_retained_interval_count",counts["plausible_intervals"])):
                        require(name in saved_features and same(saved_features[name]["value"],count), "Saved feature support count disagrees with complete rows.")
                    support = record["interval_spectrum"]["support"]
                    require(support["detected_peak_count"] == counts["peaks"] and support["interval_count"] == counts["intervals"] and
                            support["plausible_interval_count"] == counts["plausible_intervals"], "Saved spectrum support counts disagree with complete temporal rows.")
                complete.append((domains,counts,markers))
                for name in COUNTS:
                    source_counts[name] += counts[name]
            for ordinal,(record,key,(domains,counts,markers)) in enumerate(zip(originals,keys,complete),1):
                selection = overrides.get(key,default)
                figure = key in chosen
                cat = catalogue(record,ordinal,report["ref"],analysis,domains,counts,key,figure,selection)
                model = dict(catalogue=cat, original_record=record, feature_indices=features[key],
                             original_features=[analysis["features"][i] for i in features[key]], joined_markers_object=markers,
                             waveform_views=[], interval_views=[], spectrum_view=None)
                if record["status"] == "computed" and figure:
                    numbers = geometry.selected_numbers(cat["waveform_window_count"], selection["waveform_windows"])
                    limit(len(numbers)*2,100,"total_panels",recovery="fewer_figures",stage="display")
                    for n in numbers:
                        focus = selection["time_focus"]
                        window = policy.focus_window(focus["start_s"],focus["end_s"]) if focus else policy.canonical_window(record["start_time_s"],record["end_time_s"],n)
                        view = geometry.waveform(index,domains["samples"],record,window,outputs.directory/f"cell-{ordinal:04d}-markers.ndjson",selection["marker_pages"],counts["peaks"])
                        model["waveform_views"].append(view)
                        panels += 1+len(view["markers"]["resolved_page_numbers"])
                    model["interval_views"] = geometry.interval_views(index,domains["peaks"],selection["interval_pages"])
                    model["spectrum_view"] = geometry.spectrum_view(index,domains.get("spectrum"),cat["spectrum"],record)
                    panels += sum(v["axis"] is not None for v in model["interval_views"])+(1 if "spectrum" in domains else 0)
                    limit(panels,100,"total_panels",recovery="fewer_figures",stage="display")
                    for name,item in domains.items():
                        pages = policy.exact_pages(item["spec"]["expected_rows"],50,selection["numerical_pages"]["mode"],selection["numerical_pages"]["numbers"])
                        numerical.append(dict(cell_key=key,table_ref=table_ref(item),requested=selection["numerical_pages"],pages=pages))
                cat["model_hash"] = value_hash(model)
                cells.append(model)
                catalog.append(cat)
                model_bytes += len(json_bytes(model))+1
                limit(model_bytes,24*MIB,"display_model_bytes",recovery="fewer_figures",stage="display")
            source_rows,source_bytes,source_tables,verified = index.rows,index.bytes,len(index.tables),index.verified
        finally:
            if index is not None:
                index.close()
    # Page metadata is separate from complete scientific objects and never replaces a table.
    numerical_object = outputs.json("numerical-pages.json",dict(schema="brohn-cardiac-numerical-pages/0.1",items=numerical),
                                    "brohn-cardiac-numerical-pages/0.1","selected_numerical_page_index")
    outcome = dict(source_status=analysis["status"], original_reason=analysis["quality"].get("reason"),
                   cell_count=len(cells),exclusion_review_object=exclusion_object,scientific_processing_performed=False)
    scientific = [source_analysis]+[{k:p[k] for k in ("hash","bytes","media_type","schema")} for p in outputs.payloads
                    if p["role"] in ("complete_original_typed_stream","complete_table_csv","complete_joined_markers")]
    complete_lineage = [closure]+([exclusion_object] if exclusion_object else [])+curation_objects+[numerical_object]
    evidence = dict(schema="brohn-cardiac-display-evidence/0.1",source_ref=report["ref"],closure_hash=source["source_closure_hash"],
                    display_request=normalized,display_request_hash=value_hash(normalized),implementation_hash=value_hash(request["implementation"]),
                    input_binding_hash=value_hash(dict(source=source,display_request=normalized,implementation=request["implementation"],
                                                       source_closure_value_hash=value_hash(request["source_closure"]))),
                    source_analysis_object=source_analysis,complete_scientific_objects=scientific,complete_lineage_objects=complete_lineage,
                    exclusion_lineage=exclusion_binding,outcome=outcome,cells=cells,source_counts=source_counts,
                    projection_mode="source_identifiers",scientific_processing_performed=False)
    limit(len(json_bytes(catalog)),2*MIB,"catalogue_bytes",stage="projection")
    limit(len(json_bytes(evidence)),48*MIB,"evidence_bytes",stage="projection")
    evidence_object = outputs.json("cardiac-display.json",evidence,evidence["schema"],"prepared_display_evidence")
    check_objects(registry,pulse)
    verification = dict(schema="brohn-cardiac-display-verification/0.1",request_sha256=None,
                        analysis_value_hash=value_hash(analysis),source_closure_value_hash=value_hash(request["source_closure"]),
                        evidence_sha256=evidence_object["hash"],evidence_bytes=evidence_object["bytes"],original_streams=verified,
                        source_objects=[{k:o[k] for k in ("hash","bytes")} for o in registry.values()],
                        runtime=dict(Python=dict(implementation=platform.python_implementation(),version=platform.python_version())),
                        complete=True,scientific_processing=False)
    return evidence,catalog,verification,outputs.payloads


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--request",type=Path,required=True)
    parser.add_argument("--output",type=Path,required=True)
    parser.add_argument("--artifacts",type=Path,required=True)
    args=parser.parse_args()
    require(not args.output.exists() and args.output.parent.is_dir(),"Result path must be fresh in an owned directory.")
    request_hash=None
    try:
        limit(args.request.stat().st_size,48*MIB,"sealed_request_bytes")
        raw=args.request.read_bytes()
        request_hash=hashlib.sha256(raw).hexdigest()
        request=strict_json(raw)
        args.artifacts.mkdir(exist_ok=False)
        evidence,catalog,verification,payloads=prepare(request,args.artifacts)
        verification["request_sha256"]=request_hash
        e=next(p for p in payloads if p["role"]=="prepared_display_evidence")
        analysis=request["report"]["complete_analysis"]
        coverage=dict(cells=len(catalog),illustrated_cells=sum(c["figure_state"]=="illustrated" for c in catalog),
                      evidence_only_cells=sum(c["figure_state"]=="evidence_only" for c in catalog),unavailable_cells=sum(c["figure_state"]=="unavailable" for c in catalog),
                      features=len(analysis["features"]),original_stream_bytes=sum(a.get("size",a.get("bytes",0)) for a in analysis["artifacts"]),
                      original_rows=sum(a["rows"] for a in analysis["artifacts"]),original_tables=sum(a["tables"] for a in analysis["artifacts"]),
                      marker_joins=evidence["source_counts"]["peaks"],scientific_processing=False)
        result=dict(schema="brohn-cardiac-display-worker-result/0.1",artifact=dict(path=e["path"],sha256=e["hash"],bytes=e["bytes"],media_type=e["media_type"]),
                    source=request["source"],display_request=request["display_request"],implementation=request["implementation"],catalog=catalog,
                    coverage=coverage,payloads=payloads,verification=verification)
        code=0
    except Exception as error:
        if isinstance(error,Refusal):
            result=error.detail
            result["blocked_request_hash"]=request_hash or result["blocked_request_hash"]
        else:
            result=dict(schema="brohn-cardiac-display-worker-error/0.1",error=dict(type=type(error).__name__,message=str(error)[:1000]))
        code=2
    with args.output.open("xb") as stream:
        stream.write(json_bytes(result)+b"\n")
    return code


if __name__=="__main__":
    raise SystemExit(main())

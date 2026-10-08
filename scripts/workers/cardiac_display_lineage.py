"""Exact supplied saved-review relationships and full curation row crosswalk."""
import copy
import csv
from pathlib import Path
from cardiac_values import fields, strict_json, json_bytes, value_hash
from cardiac_display_core import require, same, integer, ref_valid, bound_path, limit, MIB


def snapshot(value):
    fields(value, ("ref", "body", "body_value_hash"), "Original entity snapshot")
    ref_valid(value["ref"])
    require(value_hash(value["body"]) == value["body_value_hash"], "Snapshot typed body changed.")
    return value["body"]


def exclusion(value, report, outputs):
    analysis = report["complete_analysis"]
    if "exclusion_review" not in analysis:
        require(value is None, "Direct report has an unexpected exclusion lineage.")
        return None, None
    require(value is not None, "Saved child requires original accepted-preview lineage.")
    fields(value, ("binding", "original_producer_request", "parent_report", "review", "catalogue", "accepted_preview"), "Saved exclusion input")
    binding = value["binding"]
    fields(binding, ("parent_report_ref", "review_ref", "catalogue_ref", "accepted_preview_ref", "preview_producer", "reanalysis_producer",
                     "accepted_preview_ledger_value_hash", "saved_exclusion_review_value_hash"), "Exclusion binding")
    for name, field in (("parent_report", "parent_report_ref"), ("review", "review_ref"), ("catalogue", "catalogue_ref"), ("accepted_preview", "accepted_preview_ref")):
        snapshot(value[name])
        require(same(value[name]["ref"], binding[field]), "Exclusion snapshot has a different exact reference.")
        require(binding[field]["project_id"] == report["ref"]["project_id"], "Exclusion lineage leaves source project.")
    parent = value["parent_report"]["body"]
    require(parent.get("analysis", {}).get("kind") == analysis["kind"] and "exclusion_review" not in parent.get("analysis", {}),
            "Only the registered direct parent report chain is supported.")
    for name, snapshot_name, operation in (("preview_producer", "accepted_preview", "preview_cardiac_review"),
                                           ("reanalysis_producer", None, "reanalyse_cardiac")):
        producer = binding[name]
        fields(producer, ("job_id", "operation", "attempt", "request_hash", "result_object"), "Original producer binding")
        body = value[snapshot_name]["body"] if snapshot_name else report["saved_body"]
        processing = body.get("processing", {})
        saved_object = body.get("result_object", {})
        require(producer["operation"] == operation and all(same(producer[k], processing.get(k)) for k in ("job_id", "attempt", "request_hash")) and
                producer["result_object"].get("hash") == saved_object.get("hash") and
                producer["result_object"].get("bytes") == saved_object.get("size", saved_object.get("bytes")) and
                producer["result_object"].get("media_type") == saved_object.get("media_type"), "Original producer binding differs from saved processing identity.")
    q = value["original_producer_request"]
    require(q.get("policy") == "cardiac-source-exclusion/1.0" and q.get("project_id") == report["ref"]["project_id"], "Original producer request policy/project changed.")
    for prefix, ref_name in (("review", "review_ref"), ("preview", "accepted_preview_ref")):
        ref = binding[ref_name]
        require(q.get(prefix+"_id") == ref["id"] and q.get(prefix+"_revision") == ref["revision"] and q.get(prefix+"_hash") == ref["body_hash"],
                "The accepted review/preview was not pinned by the original producer request.")
    preview = value["accepted_preview"]["body"].get("preview")
    require(isinstance(preview, dict) and preview.get("resolved_exclusion") is None and isinstance(preview.get("ledger"), dict),
            "An accepted reanalysis preview is required, not a boundary-resolution preview.")
    ledger = analysis["exclusion_review"]
    require(same(preview["ledger"], ledger) and value_hash(ledger) == binding["accepted_preview_ledger_value_hash"] == binding["saved_exclusion_review_value_hash"],
            "Accepted preview ledger differs from the complete saved child ledger.")
    review = binding["review_ref"]
    require(same(ledger.get("review_source"), dict(id=review["id"], revision=review["revision"], hash=review["body_hash"])) and
            ledger.get("schema") == "brohn-cardiac-exclusion-ledger/1.0" and ledger.get("policy") == q["policy"], "Ledger review/policy identity changed.")
    require(same(ledger.get("source"), dict(sha256=analysis["source"]["sha256"], bytes=analysis["source"]["bytes"])), "Ledger source changed.")
    body_prov = report["saved_body"].get("provenance", {}).get("cardiac_review", {})
    par = binding["parent_report_ref"]
    require(same(body_prov.get("parent_report"), dict(id=par["id"], revision=par["revision"], hash=par["body_hash"])) and
            same(body_prov.get("review_source"), ledger["review_source"]) and body_prov.get("policy") == q["policy"], "Original report provenance lost its parent/review.")
    require(same(value["review"]["body"].get("spans"), [
        {k: span[k] for k in ("id", "start_sample", "end_sample", "reason", "note")}
        for span in ledger["spans"]]), "Saved individual review decisions differ from the ledger.")
    obj = outputs.json("exclusion-review.json", ledger, ledger["schema"], "complete_exclusion_review")
    return copy.deepcopy(binding), obj


def curation(value, original_source, analysis, registry, outputs, pulse=None):
    if value is None:
        require("curation" not in analysis.get("exclusion_review", {}), "Curated ledger has no complete crosswalk input.")
        return []
    fields(value, ("binding", "decisions_object", "derived_csv_object", "format"), "Complete curation input")
    require(isinstance(value["binding"], dict) and value["format"] in ("csv", "tsv"), "Invalid curation binding/format.")
    require(same(value["derived_csv_object"], original_source), "Curated CSV is not the exact original analysis input.")
    decisions = bound_path(value["decisions_object"], registry)
    source = bound_path(value["derived_csv_object"], registry)
    path = outputs.path("curation-crosswalk.ndjson")
    keys = ("source_segment_id", "source_clock_id", "source_timestamp", "source_timestamp_unit", "brohn_segment_id")
    total = included = 0
    curated_ledger = analysis.get("exclusion_review", {}).get("curation")
    endpoints = {}
    if curated_ledger is not None:
        require(same(curated_ledger.get("decisions"), dict(sha256=value["decisions_object"]["hash"],bytes=value["decisions_object"]["bytes"])),
                "Curated ledger decisions object differs from complete crosswalk source.")
        for name in ("selected_first", "selected_last"):
            point = curated_ledger[name]
            endpoints.setdefault(point["source_sample_index"],[]).append(point)
    with decisions.open("rb") as decision_stream, source.open("r", encoding="utf-8-sig", newline="") as source_stream, path.open("xb") as target:
        reader = csv.DictReader(source_stream, delimiter="\t" if value["format"] == "tsv" else ",")
        require({"source_sequence", "source_identity_json", *keys} <= set(reader.fieldnames or []), "Curated source CSV has no complete saved crosswalk columns.")
        while True:
            line = decision_stream.readline(2*MIB+1)
            if not line:
                break
            limit(len(line), 2*MIB, "curation_line_bytes")
            require(line.endswith(b"\n"), "Incomplete curation decision line.")
            decision = strict_json(line)
            total += 1
            limit(total, 1000000, "curation_rows")
            require(isinstance(decision, dict) and integer(decision.get("source_sequence"), 1) and decision["source_sequence"] == total and
                    decision.get("disposition") in ("included", "excluded"), "Curation original sequence/disposition is invalid.")
            derived_index = None
            if decision["disposition"] == "included":
                row = next(reader, None)
                require(row is not None and row["source_sequence"] == str(total) and all(k in decision and row[k] == str(decision[k]) for k in keys) and
                        same(strict_json(row["source_identity_json"]), decision.get("source_identity")), "Included curation decision does not match its exact derived CSV row.")
                require(isinstance(decision["source_timestamp"], str) and isinstance(decision["source_identity"], dict), "Clock timestamps/identity must retain exact saved types.")
                derived_index = included
                included += 1
                for endpoint in endpoints.get(derived_index,[]):
                    expected = dict(source_sample_index=derived_index,source_sequence=decision["source_sequence"],source_identity=decision["source_identity"],
                                    **{k:decision[k] for k in keys})
                    require(same(endpoint,expected), "Saved curated endpoint differs from complete included decision/CSV crosswalk.")
            output = dict(decision_row_index=total-1, acquisition_sequence=decision["source_sequence"], disposition=decision["disposition"],
                          derived_row_index=derived_index, source_segment_id=decision.get("source_segment_id"), source_clock_id=decision.get("source_clock_id"),
                          source_timestamp=decision.get("source_timestamp"), source_timestamp_unit=decision.get("source_timestamp_unit"),
                          source_identity=decision.get("source_identity"), brohn_segment_id=decision.get("brohn_segment_id"), original_decision=decision)
            target.write(json_bytes(output)+b"\n")
            if total % 512 == 0:
                limit(outputs.bytes + target.tell(), 192*MIB, "projection_bytes", stage="projection")
                if pulse:
                    pulse()
        require(next(reader, None) is None and included == analysis["source"]["rows"], "Complete curation CSV/decision counts disagree.")
        if curated_ledger is not None:
            require(total == curated_ledger["all_acquisition_rows"] and included == curated_ledger["all_derived_rows"] and
                    all(0 <= i < included for i in endpoints), "Curated ledger complete counts/endpoints differ from full crosswalk.")
    return [outputs.copy("curation-decisions.ndjson", decisions, "brohn-stream-curation-decisions/1.0", "complete_original_curation_decisions"),
            outputs.register(path, "brohn-cardiac-curation-crosswalk/0.1", "complete_curation_crosswalk", "application/x-ndjson")]

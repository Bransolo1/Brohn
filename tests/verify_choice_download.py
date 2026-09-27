"""Independent complete-source choice-package oracle. No Brohn imports or fit.

Inputs are the separately retained original bundle and the actual downloaded ZIP.
Every original scientific scalar/collection is compared, then canonical CSVs,
choice identities, rendered marks and complete artifact inventory are checked.
"""
import argparse
import csv
import hashlib
import io
import json
import re
import zipfile
from collections import Counter
from decimal import Decimal
from html.parser import HTMLParser
from pathlib import Path
from xml.etree import ElementTree as ET

csv.field_size_limit(128 * 1024 * 1024)


def sha(data):
    return hashlib.sha256(data).hexdigest()


def loads(data):
    def pairs(xs):
        result = {}
        for k, v in xs:
            assert k not in result, "duplicate JSON key"
            result[k] = v
        return result
    return json.loads(data, parse_float=Decimal, object_pairs_hook=pairs,
                      parse_constant=lambda v: (_ for _ in ()).throw(ValueError(v)))


def same(a, b):
    if type(a) in (int, Decimal) and type(b) in (int, Decimal):
        return a == b
    if type(a) is not type(b):
        return False
    if isinstance(a, dict):
        return a.keys() == b.keys() and all(same(a[k], b[k]) for k in a)
    if isinstance(a, list):
        return len(a) == len(b) and all(same(x, y) for x, y in zip(a, b))
    return a == b


def inventory(path):
    with zipfile.ZipFile(path) as archive:
        entries = archive.infolist()
        names = [e.filename for e in entries]
        assert names == sorted(set(names)), "unordered or duplicate ZIP member"
        assert len(entries) <= 10000 and sum(e.file_size for e in entries) <= 512 * 1024 ** 2
        for e in entries:
            assert re.fullmatch(r"[A-Za-z0-9._/-]+", e.filename)
            assert all(x not in ("", ".", "..") for x in e.filename.split("/"))
            assert e.file_size <= 128 * 1024 ** 2 and e.compress_type == zipfile.ZIP_STORED
            assert not e.flag_bits & 1 and not e.is_dir() and not e.extra and not e.comment
            assert e.date_time == (1980, 1, 1, 0, 0, 0)
        payload = {e.filename: archive.read(e) for e in entries}
    manifest = loads(payload["manifest.json"])
    files = manifest["files"]
    assert len({f["path"] for f in files}) == len(files)
    assert set(payload) == {f["path"] for f in files} | {"manifest.json"}
    for f in files:
        assert len(payload[f["path"]]) == f["bytes"] and sha(payload[f["path"]]) == f["sha256"], f["path"]
    return payload, manifest


class Document(HTMLParser):
    def __init__(self):
        super().__init__()
        self.ids, self.references, self.tags, self.headings, self.rows = [], [], [], [], []
        self.heading = None
        self.row = None
        self.cell = None
        self.cells = []

    def handle_starttag(self, tag, attrs):
        attrs = dict(attrs)
        self.tags.append(tag)
        assert not any(k.lower().startswith("on") for k in attrs)
        if "id" in attrs:
            self.ids.append(attrs["id"])
        for k in ("href", "src", "xlink:href"):
            if k in attrs:
                self.references.append(attrs[k])
        if tag == "h2":
            self.heading = ""
        if tag == "tr":
            self.row, self.cells = True, []
        if tag in ("th", "td"):
            self.cell = ""

    def handle_endtag(self, tag):
        if tag == "h2" and self.heading is not None:
            self.headings.append(self.heading)
            self.heading = None
        if tag in ("th", "td") and self.cell is not None:
            self.cells.append(self.cell)
            self.cell = None
        if tag == "tr" and self.row:
            self.rows.append(self.cells)
            self.row = None

    def handle_data(self, value):
        if self.heading is not None:
            self.heading += value
        if self.cell is not None:
            self.cell += value


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--bundle", type=Path, required=True)
    parser.add_argument("--zip", type=Path, required=True)
    parser.add_argument("--html", type=Path)
    parser.add_argument("--compare-zip", type=Path)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    assert not args.output.exists(), "choose fresh oracle output"
    args.output.mkdir(parents=True)
    checks, scalars, alias_fields = [], 0, 0

    def check(label, condition):
        assert condition, label
        checks.append(label)

    bundle_bytes = args.bundle.read_bytes()
    bundle = loads(bundle_bytes)
    payload, manifest = inventory(args.zip)
    original_mode = bundle["selection"]["contents_policy"]["identifier_mode"] == "source_identifiers"
    check("independent CRC/size/hash/fixed ZIP inventory", bool(payload))
    check("exact original frozen selection", same(manifest["selection"], {k: v for k, v in bundle["selection"].items() if k not in ("intent_ref", "generation")}))
    for key, originals in [("reports", bundle["reports"]), ("task_displays", bundle["task_displays"]), ("choice_displays", bundle["choice_displays"]), ("distributions", bundle["distributions"])]:
        check("exact ordered original " + key, same(manifest["sources"][key], [x["ref"] for x in originals]))
    if args.html:
        check("actual HTML equals complete ZIP representation", args.html.read_bytes() == payload["report.html"])

    def projected_alias(a, b, path):
        nonlocal scalars, alias_fields
        if original_mode:
            assert same(a, b), path
            scalars += 1
        elif a is None or a == "":
            assert same(a, b), (path, "null/blank alias")
            alias_fields += 1
        else:
            assert isinstance(b, str) and re.fullmatch(r"(report-\d+|related-source-\d+)-(person|session|administration|source-attempt|source-person|source-session|exposure|assessment|event|step|visit|occurrence|clock-instance)-\d+", b), (path, a, b)
            alias_fields += 1

    def compare(a, b, path="", mapping=None):
        nonlocal scalars
        if isinstance(a, dict):
            assert isinstance(b, dict), path
            omitted = {"filename", "path"} & a.keys() if path.endswith("/parameters/mapping/protocol_registry") or path.startswith("/native-terminal") and path.endswith("/asset") else set()
            if path == "/provenance/source":
                omitted |= {"filename", "path", "name"} & a.keys()
            if path == "/provenance/run_evidence":
                omitted |= {"workspace_id", "job_id", "attempt"} & a.keys()
            if path.startswith("/provenance") and path.endswith(("/asset", "/protocol_registry")):
                omitted |= {"filename", "path"} & a.keys()
            assert a.keys() - omitted == b.keys(), (path, "key/null/absence conservation")
            for k, value in a.items():
                if k in omitted:
                    continue
                next_path = path + "/" + k
                identity = False
                if re.search(r"/source_rows/\d+/(original_cells|mapped_cells)$", path):
                    roles = ("participant", "session", "exposure") if path.endswith("/mapped_cells") else ("participant", "session", "attempt")
                    identity = mapping is not None and k in [mapping.get(role + "_column") for role in roles]
                elif not any("/" + field + "/" in next_path for field in ("value", "previous_value", "invalidated_value", "item_values", "value_before_conversion", "original_cells", "design")):
                    identity = k in {"participant_id", "session_id", "run_id", "person_id", "source_participant_id", "source_session_id", "source_attempt_id", "exposure_id", "source_exposure_id", "assessment_exposure_id", "assessment_id", "event_id", "first_answer_event_id", "last_answer_event_id", "step_id", "visit_id", "occurrence_id", "instance_id", "invalidated_by_event_id", "invalidated_event_id", "trigger_event_id", "previous_answer_event_id", "cause_event_id", "previous_head_event_id", "from_visit_id", "clock_segment_id"}
                    identity |= k == "attempt_id" and any("/" + branch + "/" in next_path for branch in ("task_scores", "task_attempts", "membership", "attempt_metrics"))
                    identity |= k == "id" and re.search(r"/task_attempts/\d+$", path) is not None
                    identity |= path.startswith("/native-terminal") and k in ("task_step_id", "attempt_id")
                    identity |= k == "id" and re.search(r"^/provenance/runs/\d+$", path) is not None
                if "/choice_tasks/" in next_path:
                    identity = bool(re.search(r"/choice_tasks/\d+/exposures/\d+/(participant_id|session_id|exposure_id)$", next_path) or re.search(r"/choice_tasks/\d+/collection_evidence/\d+/(run_id|step_id|clock/instance_id)$", next_path))
                if identity:
                    projected_alias(value, b[k], next_path)
                elif k in ("attempt_ids", "contributing_attempt_ids", "contributing_session_ids"):
                    assert len(value) == len(b[k]), next_path
                    for i, (x, y) in enumerate(zip(value, b[k])):
                        projected_alias(x, y, next_path + "/" + str(i))
                else:
                    compare(value, b[k], next_path, mapping)
        elif isinstance(a, list):
            assert isinstance(b, list) and len(a) == len(b), (path, "array order/length")
            for i, (x, y) in enumerate(zip(a, b)):
                compare(x, y, path + "/" + str(i), mapping)
        else:
            assert same(a, b), (path, a, b)
            scalars += 1

    def csv_rows(name):
        rows = list(csv.DictReader(io.StringIO(payload[name].decode("utf-8"), newline="")))
        assert all(int(row["source_order"]) == i + 1 for i, row in enumerate(rows)), name
        return [loads(row["record_json"]) for row in rows]

    for index, report in enumerate(bundle["reports"], 1):
        key = f"report-{index:02}"
        original = report["complete_analysis"]
        projection = loads(payload[f"evidence/{key}.json"])
        projected = projection["analysis"]
        mapping = original.get("parameters", {}).get("mapping")
        compare(original, projected, "/analysis", mapping)
        check(key + " every original scientific key/type/null/value/array preserved", True)
        compare(report["saved_body"]["provenance"], projection["provenance"], "/provenance", mapping)
        check(key + " original provenance values and declared operational omissions", True)
        task_entries = [e for e in bundle["task_displays"] if same(e["evidence"]["source"]["report_ref"], report["ref"])]
        assert len(task_entries) <= 1
        if task_entries:
            task = loads(payload[f"evidence/tasks/{key}.json"])
            raw_task = task_entries[0]["evidence"]
            check(key + " exact mixed task source binding and complete administration count", same(task["source_ref"], task_entries[0]["ref"]) and same(task["evidence"]["source"], raw_task["source"]) and len(task["evidence"]["administrations"]) == len(raw_task["administrations"]) and len(task["evidence"]["cohort_models"]) == len(raw_task["cohort_models"]))
            for field in ("task_scores", "task_attempts", "source_rows", "membership", "attempt_metrics", "per_session", "per_person", "summaries"):
                if field in projected:
                    check(key + " complete mixed task " + field, same(csv_rows(f"data/tasks/{key}-{field.replace('_', '-')}.csv"), projected[field]))
            for ai, (old, new) in enumerate(zip(raw_task["administrations"], task["evidence"]["administrations"]), 1):
                stem = f"data/tasks/{key}-administration-{ai:04}"
                score = projected["task_scores"][new["score_binding"]["index"] - 1]
                check(key + f" task administration {ai} all original expected positions", same(new["plot_model"]["rows"], old["plot_model"]["rows"]) and same(csv_rows(stem + "-positions.csv"), old["plot_model"]["rows"]))
                metric_rows = csv_rows(stem + "-metrics.csv")
                metrics = score.get("metrics", [])
                check(key + f" task administration {ai} full exact saved metric/support rows", len(metric_rows) == max(1, len(metrics)) and all(all(k in metric_rows[i] and same(v, metric_rows[i][k]) for k, v in metric.items()) for i, metric in enumerate(metrics)))
                if old["source_kind"] == "native":
                    compare(old["terminal_evidence"], new["terminal_evidence"], "/native-terminal", mapping)
                    check(key + f" task administration {ai} complete native terminal typed values", same(csv_rows(stem + "-terminal.csv"), new["terminal_evidence"]["rows"]))
                    if not original_mode:
                        check(key + f" task administration {ai} original bridge joins aliased score", all(r["participant_id"] == score["participant_id"] and r["session_id"] == score["session_id"] and r["attempt_id"] == new["terminal_evidence"]["task_step_id"] for r in new["terminal_evidence"]["rows"]))
                else:
                    attempt = projected["task_attempts"][new["score_binding"]["attempt_index"] - 1]
                    check(key + f" task administration {ai} full imported audit and responses", same(csv_rows(stem + "-responses.csv"), attempt["responses"]) and same(csv_rows(stem + "-audit.csv"), attempt["trial_audit"]) and same(new["plot_model"]["saved_score"], score))
        entries = [x for x in bundle["choice_displays"] if same(x["evidence"]["source"]["report_ref"], report["ref"])]
        if not original.get("choice_tasks"):
            assert not entries
            continue
        assert len(entries) == 1
        entry = entries[0]
        portable = loads(payload[f"evidence/choices/{key}.json"])
        saved = portable["evidence"]
        check(key + " exact original projection and result-object binding", same(projection["source_ref"], report["ref"]) and projection["source_analysis_sha256"] == entry["evidence"]["source"]["analysis_hash"] and same(projection["source_result_object"], report["saved_body"].get("result_object")))
        check(key + " original prepared choice binding and complete exercise order", same(portable["source_ref"], entry["ref"]) and same(saved["source"], entry["evidence"]["source"]) and same(saved["implementation"], entry["evidence"]["implementation"]) and same(saved["coverage"], entry["evidence"]["coverage"]) and len(saved["exercises"]) == len(original["choice_tasks"]))
        for ei, (source, transformed) in enumerate(zip(original["choice_tasks"], projected["choice_tasks"]), 1):
            item = saved["exercises"][ei - 1]
            raw = entry["evidence"]["exercises"][ei - 1]
            check(f"{key} exercise {ei} full result and both complete prepared models", same(item["original_result"], transformed) and same(raw["original_result"], source) and all(same(item[k], raw[k]) for k in raw if k != "original_result"))
            stem = f"data/choices/{key}-exercise-{ei:03}"
            collections = {"items": transformed["items"], "exposures": transformed["exposures"], "utilities": transformed["model"]["utilities"]}
            if "probabilities" in transformed["model"]:
                collections["probabilities"] = transformed["model"]["probabilities"]
            if "collection_evidence" in transformed:
                collections["timing"] = transformed["collection_evidence"]
            for name in ("items", "exposures", "utilities", "probabilities", "timing"):
                path = stem + "-" + name + ".csv"
                check(f"{key} exercise {ei} complete {name} presence and typed rows", same(csv_rows(path), collections[name]) if name in collections else path not in payload)
                coverage = next(c for c in manifest["choice_source_coverage"] if same(c["source_ref"], report["ref"]))
                assert same(coverage["coverage"], entry["evidence"]["coverage"])
                descriptor = next(c for c in coverage["collections"] if c["exercise_index"] == ei and c["collection"] == name)
                expected = dict(exercise_index=ei, collection=name, state="absent_by_schema" if name not in collections else "present_empty" if not collections[name] else "complete", rows=len(collections[name]) if name in collections else None, path=path if name in collections else None)
                assert same(descriptor, expected), (key, ei, name, "coverage")
            check(f"{key} exercise {ei} opaque response IDs never changed", [r["id"] for r in source["exposures"]] == [r["id"] for r in transformed["exposures"]])
            if "collection_evidence" in source:
                responses = {r["id"]: r for r in transformed["exposures"]}
                check(f"{key} exercise {ei} native timing joins exact aliased response session", all(t["response_id"] in responses and t["run_id"] == responses[t["response_id"]]["session_id"] for t in transformed["collection_evidence"]))
                links = {}
                for old, new in zip(source["collection_evidence"], transformed["collection_evidence"]):
                    for role, x, y in [("step", old["step_id"], new["step_id"]), ("clock", old["clock"]["instance_id"], new["clock"]["instance_id"])]:
                        identity = (old["run_id"], role, x)
                        assert identity not in links or links[identity] == y
                        links[identity] = y
        if original["kind"] == "explicit_choice":
            check(key + " imported observations and every selected/excluded raw row", same(projected["observations"], projected["choice_tasks"][0]["exposures"]) and same(csv_rows(f"data/choices/{key}-source-rows.csv"), projected["source_rows"]) and same(csv_rows(f"data/choices/{key}-observations.csv"), projected["observations"]))
            responses = {r["id"]: r for r in projected["observations"]}
            for row in projected["source_rows"]:
                if row["selected"]:
                    response = responses[row["response_id"]]
                    assert all(row["mapped_cells"][mapping[role + "_column"]] == response[role + "_id"] for role in ("participant", "session", "exposure"))
                else:
                    assert row["response_id"] is None and "mapped_cells" not in row
            check(key + " imported exact selected alias joins and excluded absence", True)
        # Mixed components remain represented in complete companions regardless of figures.
        for field in ("observations", "features"):
            if original["kind"] == "questionnaire":
                check(key + " full mixed explicit " + field, same(csv_rows(f"data/explicit/{key}-{field}.csv"), projected[field]))
        if original["kind"] == "questionnaire" and "scales" in projected:
            check(key + " full mixed scale observations", same(csv_rows(f"data/explicit/{key}-scales.csv"), projected["scales"]["observations"]))

    doc = Document()
    doc.feed(payload["report.html"].decode("utf-8"))
    check("offline HTML unique identifiers and visible source landmarks", len(doc.ids) == len(set(doc.ids)) and len(doc.headings) == len(set(doc.headings)))
    check("offline HTML no executable or network resources", not set(doc.tags) & {"script", "iframe", "object", "embed"} and all(not re.match(r"(?:https?:|file:|//)", ref) for ref in doc.references))
    for descriptor in manifest["files"]:
        if descriptor["media_type"] != "image/svg+xml":
            continue
        tree = ET.fromstring(payload[descriptor["path"]])
        ids = [node.attrib["id"] for node in tree.iter() if "id" in node.attrib]
        assert len(ids) == len(set(ids))
        for node in tree.iter():
            for role in ("aria-labelledby", "aria-describedby"):
                assert role not in node.attrib or all(x in ids for x in node.attrib[role].split())
        metadata = tree.find("{http://www.w3.org/2000/svg}metadata")
        binding = loads(metadata.text) if metadata is not None else {}
        if "exercise_key" not in binding:
            continue
        source = next(e for e in bundle["choice_displays"] if same(e["ref"], binding["source"]))
        exercise = next(e for e in source["evidence"]["exercises"] if e["key"] == binding["exercise_key"])
        model = exercise["counts_model" if binding["kind"] == "adjusted" else "utilities_model"]
        check(descriptor["path"] + " exact original rows/status in actual SVG", same(binding["rows"], model["rows"]) and same(binding["status"], model["status"]) and same(binding["reason"], model["reason"]))
        marks = [e for e in tree.iter() if "data-item-id" in e.attrib]
        assert len(marks) == len(model["rows"])
        finite = [float(r["value"]) for r in model["rows"] if r["value"] is not None]
        extent = 1 if binding["kind"] == "adjusted" else max([0.01] + [abs(v) for v in finite]) * 1.1
        for i, (mark, row) in enumerate(zip(marks, model["rows"]), 1):
            assert mark.attrib["data-item-id"] == row["item_id"] and int(mark.attrib["data-denominator"]) == row["complete_pair_exposures"]
            value = mark.attrib["data-value"]
            assert value == "unavailable" if row["value"] is None else Decimal(value) == row["value"]
            circles = mark.findall("{http://www.w3.org/2000/svg}circle")
            if row["value"] is None:
                assert not circles
            else:
                assert len(circles) == 1
                x = 250 + (float(row["value"]) + extent) / (2 * extent) * 420
                assert abs(float(circles[0].attrib["cx"]) - x) < 1e-9 and float(circles[0].attrib["cy"]) == 22 + i * 38
        if not model["rows"]:
            assert model["status"] in ("unavailable", "not_requested")
            assert not any(e.tag.rsplit("}", 1)[-1] in ("circle", "rect", "path", "line") for e in tree.iter())
        check(descriptor["path"] + " all actual SVG values/order/coordinates and unavailable panels", True)

    if args.compare_zip:
        previous, prior_manifest = inventory(args.compare_zip)
        check("focused comparison exact ordered sources and identity mode", same(prior_manifest["sources"], manifest["sources"]) and prior_manifest["projection"]["policy"]["identifier_mode"] == manifest["projection"]["policy"]["identifier_mode"])
        def complete(payload, manifest):
            return {f["path"]: (f["role"], f["media_type"], payload[f["path"]]) for f in manifest["files"] if (f["path"].startswith("evidence/") and not f["path"].startswith("evidence/distributions/")) or f["path"].startswith("data/choices/") or re.match(r"^data/(tasks|explicit)/report-\d+", f["path"])}
        check("focused figures preserve exact complete source/exercise companions", complete(payload, manifest) == complete(previous, prior_manifest))
        def distributions(payload, manifest):
            rows = []
            for descriptor in manifest["files"]:
                if re.fullmatch(r"evidence/distributions/section-\d+[.]json", descriptor["path"]):
                    original = loads(payload[descriptor["path"]])
                    refs = json.dumps({k: original[k] for k in ("schema", "source_ref", "source_report_ref")}, sort_keys=True, separators=(",", ":"))
                    rows.append((refs, descriptor["role"], descriptor["media_type"], payload[descriptor["path"]]))
            return Counter(rows)
        check("section ordinal relocation cannot lose or substitute exact distribution bytes and multiplicity", distributions(payload, manifest) == distributions(previous, prior_manifest))
    result = dict(schema="brohn-choice-independent-download/0.1", passed=True, checks=checks, unchanged_scientific_scalars=scalars, registered_alias_fields=alias_fields,
                  inputs=dict(bundle_sha256=sha(bundle_bytes), zip_sha256=sha(args.zip.read_bytes()), html_sha256=sha(args.html.read_bytes()) if args.html else None), verifier_sha256=sha(Path(__file__).read_bytes()),
                  scope="Independent exact complete scientific projection, choice model/CSV/actual SVG/ZIP proof and complete mixed task expected/terminal/metric companions. No source producer, scorer, worker, authority or browser-layout claim.")
    (args.output / "results.json").write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(dict(passed=True, checks=len(checks), scientific_scalars=scalars, alias_fields=alias_fields, receipt_sha256=sha((args.output / "results.json").read_bytes()))))


if __name__ == "__main__":
    main()

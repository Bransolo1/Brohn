"""Independent saved-value oracle: no EDA decomposition or scoring is called."""
import copy
import csv
import json
from pathlib import Path
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts/workers"))
import eda_review as reader
import physiology_artifacts as tables


def fixture(folder):
    folder = Path(folder); folder.mkdir(exist_ok=True, parents=True)
    raw = folder / "original-hand-source.csv"
    with raw.open("w",encoding="utf-8",newline="") as stream:
        writer=csv.writer(stream);writer.writerow(["time","conductance"])
        writer.writerows((i/25,1+2*(i/25)+max(0,2-abs(i/25-23))) for i in range(1001))
    p = dict(recipe="eda-event-highpass/1.0", baseline_s=[-2, 0], response_s=[0, 6], onset_latency_s=[.5, 4], recovery_end_s=10)
    group = dict(participant_id="SYNTHETIC-P1", session_id="SYNTHETIC-S1")
    identity = dict(recording_id="recording-1", segment_id="segment-1", channel="eda", group=group, origin="sample")
    coord = dict(axis="time", reference="seconds relative to original source recording start", source_time_origin="0", source_time_unit="s")
    support = dict(parameters=p, source=dict(sampling_rate=25), raw_source_omitted=True)
    provenance = dict(source_sha256=tables.digest_file(raw), engine=dict(name="Independent hand-written typed fixture", worker_sha256="a"*64),
                      operation="eda_events", origin="sample", parameters={"recording-1": p})
    def col(name, kind, unit, nullable=False, role="measurement"):
        return dict(name=name, type=kind, unit=unit, nullable=nullable, role=role)
    fields = [col("time_s", "float64", "s", role="coordinate"), col("source_sample_index", "integer", "sample_index", role="index"),
              *[col(k, "float64", "uS") for k in reader.COMPONENTS], col("retained", "boolean", None, role="support")]
    rows = []
    for i in range(1001):
        time = i / 25; tonic = 1 + 2*time; phasic = max(0, 2-abs(time-23))
        rows.append(dict(time_s=time, source_sample_index=i, clean_us=tonic+phasic, tonic_us=tonic, phasic_us=phasic, retained=10<=time<=30))
    series = tables.TableWriter(folder, "physiology-series", provenance)
    series.write_table("hand-samples", identity, fields, coord, support, rows, len(rows))
    first = series.finish()
    candidate = dict(type="scr_candidate", peak_time_s=23.0, peak_sample_index=575, source_peak_sample=575,
                     onset_time_s=21.0, recovery_time_s=24.0, amplitude_us=2.0, peak_height_us=2.0,
                     recovery_fraction=.5, onset_supported=True, recovery_supported=True)
    fields = [col("type", "string", None, role="label"), col("peak_time_s", "float64", "s", role="coordinate"),
              col("peak_sample_index", "integer", "sample_index"), col("source_peak_sample", "integer", "sample_index"),
              *[col(k, "float64", "s", True) for k in ("onset_time_s", "recovery_time_s")],
              *[col(k, "float64", "uS", True) for k in ("amplitude_us", "peak_height_us")], col("recovery_fraction", "float64", "proportion"),
              *[col(k, "boolean", None) for k in ("onset_supported", "recovery_supported")]]
    events = tables.TableWriter(folder, "physiology-events", provenance)
    events.write_table("hand-candidates", identity, fields, {**coord, "axis":"event"}, support, [candidate], 1)
    second = events.finish()
    selection = dict(recording_id="recording-1", event_id="event-1", channel="eda")
    event = dict(**selection, group=group, exposure_id="trial-1", condition_id="control", time_s=20.0, unit="uS", source_unit="uS",
                 source_time_origin="0", sampling_rate=25, status="computed", reason=None, scr_status="computed", scr_reason=None,
                 same_continuous_segment=True, overlapping_event_ids=[], recovery_missing_reason=None,
                 baseline_support=dict(requested_start_s=18, requested_end_s=20, complete=True, observed_start_s=18, observed_end_s=20, samples=51, duration_s=2, reason=None),
                 response_support=dict(requested_start_s=20, requested_end_s=26, complete=True, observed_start_s=20, observed_end_s=26, samples=151, duration_s=6, reason=None),
                 selected_scr={k:v for k,v in candidate.items() if k!="source_peak_sample"})
    features = [dict(**selection, name=k, value=v, unit="uS", eligible=True, support_status="computed", missing_reason=None,
                     denominator="one_event_within_person_session", exposure_id="trial-1", condition_id="control")
                for k,v in (("tonic_baseline_mean",39), ("tonic_response_mean",47), ("tonic_response_minus_baseline",8), ("scr_responder_amplitude",2))]
    target = dict(id="event-1", type="stimulus_event", code="A", recording_id="recording-1", exposure_id="trial-1", condition_id="control", time_s=20)
    export = folder / "exports"; export.mkdir()
    request = dict(schema="brohn-eda-review-request/1.0", binding=dict(selection=selection, origin="sample"), event=event, parameters=p,
                   features=features, source_events=[target], source_masks=[], artifacts=[first,second],
                   original_source=dict(path=str(raw), hash=tables.digest_file(raw), bytes=raw.stat().st_size), sealed_objects=[], export_directory=str(export))
    (folder / "fixture.json").write_text(json.dumps(request), encoding="utf-8")
    return request


class Review(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix="brohn-eda-review-unit-"); self.root=Path(self.tmp.name); self.request=fixture(self.root)
    def tearDown(self): self.tmp.cleanup()
    def test_every_selected_row_matches_hand_arithmetic(self):
        r=reader.review(self.request)
        with (self.root/"exports/eda-window-samples.csv").open(encoding="utf-8") as stream:
            rows=list(csv.DictReader(stream))
        self.assertEqual(len(rows),301);self.assertEqual([int(x["source_sample_index"]) for x in rows],list(range(450,751)))
        for row in rows:
            t=int(row["source_sample_index"])/25
            self.assertEqual(float(row["tonic_us"]),1+2*t);self.assertEqual(float(row["phasic_us"]),max(0,2-abs(t-23)))
            self.assertEqual(float(row["relative_time_s"]),t-20)
        self.assertEqual(r["counts"]["complete_artifact_rows"],1001);self.assertEqual(r["features"],self.request["features"])
        self.assertEqual([m["relative_time_s"] for m in r["markers"]],[1,3,4]);self.assertEqual([m["phasic_us"] for m in r["markers"]],[0,2,1])
    def test_wrong_clock_fails(self):
        self.request["event"]["source_time_origin"]="different";self.assertRaises(ValueError,reader.review,self.request)
    def test_wrong_saved_settings_fail(self):
        self.request["parameters"]["baseline_s"]=[-1,0];self.assertRaises(ValueError,reader.review,self.request)
    def test_wrong_original_source_fails(self):
        Path(self.request["original_source"]["path"]).write_text("changed",encoding="utf-8");self.assertRaises(ValueError,reader.review,self.request)
    def test_invented_selected_candidate_fails(self):
        self.request["event"]["selected_scr"]["amplitude_us"]=4;self.assertRaises(ValueError,reader.review,self.request)
    def test_overlap_preserves_unavailable_not_zero(self):
        self.request["event"].update(status="unavailable",reason="ambiguous_overlapping_events",scr_status="unavailable",selected_scr=None,overlapping_event_ids=["other"])
        self.request["features"][0].update(value=None,eligible=False,missing_reason="ambiguous_overlapping_events")
        r=reader.review(self.request);self.assertIsNone(r["features"][0]["value"]);self.assertTrue(all(not m["selected_for_event"] for m in r["markers"]))
        self.assertIn("ambiguous_overlapping_events",(self.root/"exports/eda-event-features.csv").read_text(encoding="utf-8"))
    def test_unsupported_recovery_stays_unusable(self):
        self.request["event"]["recovery_missing_reason"]="another_event_precedes_half_recovery"
        r=reader.review(self.request);m=next(m for m in r["markers"] if m["kind"]=="recovery")
        self.assertTrue(m["selected_for_event"]);self.assertFalse(m["event_measure_usable"])
    def test_incomplete_baseline_never_recomputed(self):
        e=self.request["event"];e["baseline_support"].update(complete=False,observed_start_s=None,observed_end_s=None,samples=0,reason="gap")
        e.update(status="unavailable",reason="incomplete_baseline_response_or_continuous_context",selected_scr=None)
        self.request["features"][0].update(value=None,eligible=False,missing_reason="gap")
        r=reader.review(self.request);self.assertFalse(r["event"]["baseline_support"]["complete"]);self.assertIsNone(r["features"][0]["value"])
    def test_preview_preserves_segment_and_retention_boundaries(self):
        rows=[dict(table_id="left" if i<4 else "right",retained=i%4>0,relative_time_s=i,phasic_us=i,source_sample_index=i) for i in range(8)]
        groups=reader.preview(rows,"phasic_us");self.assertEqual(len(groups),4);self.assertEqual(sum(g["source_rows"] for g in groups),8)
    def test_safe_text_keeps_empty_null_numeric_and_blocks_formulas(self):
        self.assertEqual(reader.safe(""),"");self.assertEqual(reader.safe(None),"");self.assertEqual(reader.safe(-2.5),"-2.5");self.assertEqual(reader.safe("=SUM(A1)"),"'=SUM(A1)")
    def test_corrupt_complete_artifact_fails(self):
        with Path(self.request["artifacts"][0]["path"]).open("ab") as f:f.write(b"x")
        self.assertRaises(ValueError,reader.review,self.request)


if __name__=="__main__":
    if len(sys.argv)>2 and sys.argv[1]=="--fixture":fixture(sys.argv[2])
    else:unittest.main()

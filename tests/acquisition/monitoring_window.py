"""Original high-rate replay and fixed-memory acquisition window evidence."""
import copy
import importlib.util
import json
import math
from pathlib import Path
import sys
import tempfile
import unittest

ROOT=Path(__file__).resolve().parents[2]
spec=importlib.util.spec_from_file_location("window_recorder",ROOT/"scripts/acquisition/lsl_recorder.py")
recorder=importlib.util.module_from_spec(spec);spec.loader.exec_module(recorder)

def criterion(kind="range_fraction",channel="c1",unit="uV"):
    rule={"id":"check-1","name":"Original replay acquisition check","version":"fixture/1","kind":kind,
          "channel_id":channel,"unit":unit,"source":"Original analytic fixture definition, not a physical-device limit",
          "rationale":"Software acceptance: exact samples and source codes must drive the selected check.",
          "window_s":5,"minimum_samples":2,"minimum_span_s":.1,"maximum_age_s":3}
    if kind!="cadence":rule["minimum_fraction"]=.9
    if kind in {"range_fraction","cadence"}:rule.update(lower=0 if kind=="range_fraction" else 900,upper=10 if kind=="range_fraction" else 1100)
    if kind=="source_code":rule["accepted_values"]=[1]
    return rule

def selection(n=1):
    channels=[{"id":f"c{i+1}","label":f"Original channel {i+1}","type":"ecg","unit":"uV","value_type":"float64"} for i in range(n)]
    return {"id":"source","uid":"original","source_id":"original","clock_id":"original-clock","clock_kind":"monotonic",
      "metadata_sha256":"a"*64,"kind":"signal","unit_provenance":"Original software fixture",
      "channels":channels,"gap_threshold_s":.1,"readiness":{"schema":"brohn-acquisition-readiness/1.1","modality":"ecg",
      "channels":[{"id":c["id"],"role":"signal"} for c in channels],"preview_channels":[c["id"] for c in channels[:8]],"acquisition_checks":[]}}

def request(directory,selected,id="original-window"):
    return {"schema":"brohn-lsl-record-request/1.0","recording_id":id,"output_root":str(directory),"lsl_session":"original-window",
      "origin":"sample","origin_statement":"Original software replay only; no physical source or participant.",
      "identity":{"participant_id":"original","session_id":"original"},"streams":[selected],
      "limits":{"max_duration_s":10,"max_samples":100000,"max_bytes":64*1024**2,"chunk_samples":512,"inlet_buffer":1}}

def row(sequence,t,values,segment=1,boundaries=None):
    return {"sequence":sequence,"segment":segment,"source_timestamp":repr(t),"values":values,
      "value_states":["observed" if value is not None else "nan" for value in values],"boundary_reasons":boundaries or []}

def replay(directory,selected,values,stamps,id):
    req=request(directory,selected,id);recorder.validate_request(req)
    target=Path(directory)/id;target.mkdir();(target/"chunks").mkdir()
    writer=recorder.Writer(target,req,{"engine":{"script_sha256":recorder.file_sha(spec.origin)},"streams":[]})
    writer.monitor[selected["id"]]["connection"]="subscribed"
    for start in range(0,len(values),512):writer.chunk(selected,values[start:start+512],stamps[start:start+512],100.,100.01)
    live=recorder.load(target/"status.json",2*1024**2)
    writer.finish("completed","original_replay")
    return {"id":id,"request":req,"live":live,"closed":recorder.load(target/"status.json",2*1024**2),"inspection":recorder.inspect_recording(target)}

class MonitoringWindow(unittest.TestCase):
    def test_high_cadence_history_is_fixed_memory_and_extreme_is_exact(self):
        s=selection(8);monitor=recorder.WindowMonitor(s,128)
        peak_sequence=51258
        for i in range(60000):
            values=[math.sin(i/71+j) for j in range(8)]
            if i+1==peak_sequence:values[3]=1234567.25
            monitor.append(row(i+1,i/10000,values))
            self.assertLessEqual(len(monitor.buckets),128)
        window=monitor.snapshot()
        self.assertGreater(window["actual_span_s"],4.8);self.assertLessEqual(window["actual_span_s"],5)
        self.assertLessEqual(window["plotted_points"],4096);self.assertGreater(window["committed_rows"],48000)
        peak=next(p for p in window["channels"][3]["points"] if p[0]==peak_sequence)
        self.assertEqual(peak[3],1234567.25);self.assertEqual(peak[2],repr((peak_sequence-1)/10000))
        self.assertEqual(sum(len(b["channels"]) for b in monitor.buckets),len(monitor.buckets)*8)
        self.assertTrue(all(set(b["channels"][0])=={"finite","nonfinite","first","min","max","last","fragment_first","fragment_last"} for b in monitor.buckets))

    def test_gaps_nonfinite_and_hidden_fragments_never_join(self):
        monitor=recorder.WindowMonitor(selection(),1)
        for i,value in enumerate([0.,None,1.,None,2.,None,3.,None,4.,None,5.]):monitor.append(row(i+1,i/100,[value]))
        w=monitor.snapshot();points=w["channels"][0]["points"]
        self.assertEqual(w["channels"][0]["finite"],6);self.assertEqual(w["channels"][0]["unavailable_numeric"],5)
        self.assertGreater(w["channels"][0]["omitted_fragments"],0)
        self.assertEqual(len({p[4] for p in points}),len(points))
        monitor.append(row(12,1.,[9.],boundaries=["declared_gap_threshold"]))
        self.assertEqual(monitor.snapshot()["boundaries"],1)
        monitor.append(row(13,.1,[7.],segment=2,boundaries=["timestamp_reversal"]))
        reset=monitor.snapshot();self.assertEqual(reset["committed_rows"],1);self.assertEqual(reset["prior_segments_discarded"],1)
        self.assertEqual(reset["channels"][0]["points"][0][0],13)

    def test_check_counts_use_every_committed_row_not_extrema_points(self):
        s=selection();s["readiness"]["acquisition_checks"]=[criterion()]
        monitor=recorder.WindowMonitor(s,4)
        for i in range(1000):monitor.append(row(i+1,i/1000,[999. if i==420 else 1.]))
        w=monitor.snapshot();self.assertEqual(w["checks"][0]["samples"],1000);self.assertEqual(w["checks"][0]["passed"],999)
        self.assertLessEqual(w["plotted_points"],16)
        self.assertEqual(w["checks"][0]["criterion"],s["readiness"]["acquisition_checks"][0])

    def test_complete_writer_retains_latest_row_and_source_only_code_counts(self):
        with tempfile.TemporaryDirectory(prefix="brohn-window-writer-") as directory:
            s=selection(3);s["readiness"]["modality"]="gaze"
            s["channels"][0]["unit"]=s["channels"][1]["unit"]="normalized";s["channels"][2]["unit"]="code"
            s["readiness"]["channels"]=[{"id":f"c{i+1}","role":role} for i,role in enumerate(["gaze_x","gaze_y","validity"])]
            rule=criterion("source_code","c3","code");s["readiness"]["acquisition_checks"]=[rule]
            values=[[.2,.3,1.] for _ in range(1000)];values[-1]=[.8,.9,0.]
            result=replay(directory,s,values,[i/1000 for i in range(1000)],"original-gaze")
            live=result["live"]["monitoring"]["streams"]["source"]
            self.assertEqual(result["inspection"]["samples"],1000)
            self.assertEqual(live["preview"][-1]["values"],[.8,.9,0.]);self.assertEqual(live["window"]["checks"][0]["passed"],999)
            self.assertEqual(live["window"]["committed_rows"],1000)
            self.assertIsNotNone(live["last_committed_monotonic_s"])

    def test_global_point_and_snapshot_budget_at_maximum_channel_layout(self):
        with tempfile.TemporaryDirectory(prefix="brohn-window-bound-") as directory:
            req=request(directory,selection(128));req["streams"]=[]
            for j in range(16):
                s=selection(128);s.update(id=f"source-{j}",uid=f"u-{j}",source_id=f"s-{j}");req["streams"].append(s)
            target=Path(directory)/"writer";target.mkdir();(target/"chunks").mkdir()
            writer=recorder.Writer(target,req,{"synthetic":True})
            try:
                for i in range(1000):
                    r=row(i+1,i/200,[math.sin(i/3+j)*1e100 for j in range(128)])
                    for window in writer.windows.values():window.append(r)
                writer.status("recording")
                status=recorder.load(target/"status.json",2*1024**2)
                self.assertLessEqual(sum(s["window"]["plotted_points"] for s in status["monitoring"]["streams"].values()),4096)
                self.assertTrue(all(w.capacity==8 for w in writer.windows.values()))
                self.assertLess((target/"status.json").stat().st_size,2*1024**2)
            finally:writer.journal.close()

    def test_criteria_require_native_units_type_support_and_evidence(self):
        s=selection();s["readiness"]["acquisition_checks"]=[criterion("source_code")]
        recorder.validate_acquisition_checks(s["readiness"],s["channels"])
        for field,value in [("unit","unknown"),("source",""),("minimum_samples",0),("maximum_age_s",None),("accepted_values",["1"])]:
            changed=copy.deepcopy(s);changed["readiness"]["acquisition_checks"][0][field]=value
            with self.subTest(field=field),self.assertRaises(recorder.RecorderError):recorder.validate_acquisition_checks(changed["readiness"],changed["channels"])

def fixtures(directory):
    directory=Path(directory);directory.mkdir(parents=True,exist_ok=True);results=[]
    s=selection();s["readiness"]["acquisition_checks"]=[criterion("finite_fraction"),{**criterion("cadence"),"id":"check-2"}]
    results.append(replay(directory,s,[[math.sin(i/25)] for i in range(6000)],[i/1000 for i in range(6000)],"window-ecg"))
    s=selection();s["channels"][0]["unit"]="uS";s["readiness"]["modality"]="eda";s["readiness"]["acquisition_checks"]=[criterion(unit="uS")]
    results.append(replay(directory,s,[[-1.],[1.],[float("nan")],[1.]],[0.,.1,.2,.3],"window-eda"))
    s=selection();s["channels"][0].update(unit="code",value_type="string");s["readiness"].update(modality="ppg",channels=[{"id":"c1","role":"contact"}])
    s["readiness"]["acquisition_checks"]=[{**criterion("source_code",unit="code"),"accepted_values":["contact"]}]
    results.append(replay(directory,s,[["contact"] for _ in range(5)],[0.,.1,.2,.3,.4],"window-contact"))
    (directory/"results.json").write_bytes(recorder.encoded(results))

if __name__=="__main__":
    if len(sys.argv)>1 and sys.argv[1]=="--fixture":fixtures(sys.argv[2])
    else:unittest.main()

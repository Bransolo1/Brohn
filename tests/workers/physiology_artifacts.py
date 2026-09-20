"""Complete typed artifact evidence beyond the preview budget, without raw copies."""
import copy
import hashlib
import importlib.util
import json
from pathlib import Path
import tempfile
import subprocess
import sys
import unittest
from unittest.mock import patch
import numpy as np

ROOT=Path(__file__).resolve().parents[2]
spec=importlib.util.spec_from_file_location("brohn_artifact_test",ROOT/"scripts/workers/physiology_artifacts.py")
worker=importlib.util.module_from_spec(spec);spec.loader.exec_module(worker)


class Artifacts(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory(prefix="brohn-processed-tests-");self.root=Path(self.tmp.name)
        self.p=dict(source_sha256="a"*64,engine=dict(name="test engine",worker_sha256="b"*64),operation="physiology",origin="sample",parameters={"recipe":"fixture/1"})
        self.identity=dict(recording_id="recording-1",channel="eda",group=dict(participant_id="p1",session_id="s1"))
        self.coords=dict(axis="time",reference="seconds relative to original recording start",source_time_origin="9999999999999999999",source_time_unit="ms")
        self.cols=[dict(name="time_s",type="float64",unit="s",nullable=False,role="coordinate"),
                   dict(name="tonic_us",type="float64",unit="uS",nullable=True,role="processed_measure"),
                   dict(name="retained",type="boolean",unit=None,nullable=False,role="support")]
    def tearDown(self): self.tmp.cleanup()
    def writer(self,**kwargs): return worker.TableWriter(self.root,"physiology-series",self.p,**kwargs)
    def write(self,count=20,**kwargs):
        with self.writer(**kwargs) as w:
            w.write_arrays("segment-1",self.identity,{"time_s":np.arange(count)/25,"tonic_us":np.arange(count)*.25,"retained":np.arange(count)%2==0},self.cols,self.coords,{"source_row_start":0,"source_row_end_exclusive":count})
            manifest=w.finish()
        return manifest,w
    def forge(self,manifest,records):
        path=Path(manifest["path"]);path.write_bytes(b"".join(worker.encode(r) for r in records))
        manifest=copy.deepcopy(manifest);manifest.update(sha256=worker.digest_file(path),bytes=path.stat().st_size)
        return manifest

    def test_full_12001_samples_survive_2000_preview_with_exact_types(self):
        manifest,w=self.write(12001,chunk_rows=137)
        observed=[];tables=[]
        receipt=worker.verify_artifact(manifest,self.root,on_table=tables.append,on_rows=lambda table,offset,rows:observed.extend(rows))
        self.assertEqual(receipt["rows"],12001);self.assertEqual(len(w.preview),2000)
        self.assertEqual(observed[-1],[480.,3000.,True])
        self.assertEqual(sum(row[1] for row in observed),.25*12000*12001/2)
        self.assertIsInstance(observed[1][2],bool)
        self.assertEqual(tables[0]["coordinates"]["source_time_origin"],"9999999999999999999")
        self.assertEqual(manifest["media_type"],"application/x-ndjson")

    def test_stream_generator_is_consumed_once_and_never_materialized(self):
        seen=[]
        def rows():
            for i in range(7000):
                seen.append(i);yield [i/25,None if i==3 else i/100,True]
        with self.writer(chunk_rows=64,preview_limit=0) as w:
            w.write_table("segment-1",self.identity,self.cols,self.coords,{},rows(),7000)
            manifest=w.finish()
        self.assertEqual(seen,list(range(7000)));self.assertEqual(w.preview,[])
        self.assertEqual(worker.verify_artifact(manifest)["rows"],7000)

    def test_idempotent_hash_named_completion(self):
        a,first=self.write();b,second=self.write()
        self.assertEqual(a,b);self.assertEqual(first.finish(),a)
        self.assertEqual(len(list(self.root.glob("*.ndjson"))),1)
        self.assertEqual(list(self.root.glob("*.tmp")),[])

    def test_independent_people_tables_never_merge(self):
        with self.writer() as w:
            for i,person in enumerate(["p1","p2"]):
                identity=copy.deepcopy(self.identity);identity["group"]["participant_id"]=person
                w.write_table("table-"+str(i),identity,self.cols,self.coords,{},[[0,1,True]],1)
            manifest=w.finish()
        tables=[];worker.verify_artifact(manifest,on_table=tables.append)
        self.assertEqual([t["identity"]["group"]["participant_id"] for t in tables],["p1","p2"])
        self.assertEqual(manifest["tables"],2)

    def test_7001_complete_event_candidates_not_capped_at_preview(self):
        cols=[dict(name="peak_time_s",type="float64",unit="s",nullable=False,role="coordinate"),
              dict(name="source_sample_index",type="integer",unit="sample_index",nullable=False,role="index"),
              dict(name="recovery_time_s",type="float64",unit="s",nullable=True,role="derived_event")]
        with worker.TableWriter(self.root,"physiology-events",self.p,preview_limit=7) as w:
            w.write_table("events",self.identity,cols,{**self.coords,"axis":"event"},{"recovery_fraction":.5},
                          ([i/25,i,None if i%2 else i/25+.5] for i in range(7001)),7001)
            manifest=w.finish()
        rows=[];worker.verify_artifact(manifest,on_rows=lambda t,o,r:rows.extend(r))
        self.assertEqual(len(rows),7001);self.assertEqual(len(w.preview),7)
        self.assertEqual(rows[1],[.04,1,None]);self.assertIsInstance(rows[1][1],int)

    def test_empty_table_has_explicit_complete_receipt(self):
        manifest,w=self.write(0)
        self.assertEqual(worker.verify_artifact(manifest)["rows"],0)
        self.assertEqual(manifest["tables"],1)

    def test_abort_on_interruption_removes_only_owned_temp(self):
        sibling=self.root/"keep.txt";sibling.write_text("keep")
        with self.assertRaises(KeyboardInterrupt):
            with self.writer() as w:
                def fail(): yield [0.,1.,True];raise KeyboardInterrupt()
                w.write_table("broken",self.identity,self.cols,self.coords,{},fail(),5)
        self.assertEqual(sibling.read_text(),"keep")
        self.assertEqual(list(self.root.glob("*.ndjson")),[]);self.assertEqual(list(self.root.glob("*.tmp")),[])
        with self.assertRaises(worker.ArtifactError): w.finish()

    def test_row_count_mismatch_never_publishes(self):
        for rows,count in [([[0.,1.,True]],2),([[0.,1.,True],[1.,2.,True]],1)]:
            with self.assertRaises(worker.ArtifactError):
                with self.writer() as w: w.write_table("broken",self.identity,self.cols,self.coords,{},rows,count)
            self.assertIsNone(w.manifest)
        self.assertEqual(list(self.root.iterdir()),[])

    def test_nonfinite_wrong_type_and_zero_substitution_rejected(self):
        for row in [[0,float("nan"),True],[0,float("inf"),True],[0,1,1],[0,"2",True],[None,1,True]]:
            with self.assertRaises(worker.ArtifactError):
                with self.writer() as w: w.write_table("broken",self.identity,self.cols,self.coords,{},[row],1)
        self.assertEqual(list(self.root.iterdir()),[])

    def test_array_length_or_unregistered_raw_field_rejected(self):
        for arrays in [dict(time_s=[0,1],tonic_us=[1],retained=[True]),dict(time_s=[0],tonic_us=[1],retained=[True],raw_us=[5])]:
            with self.assertRaises(worker.ArtifactError):
                with self.writer() as w: w.write_arrays("broken",self.identity,arrays,self.cols,self.coords,{})

    def test_declared_units_coordinates_and_provenance_required(self):
        bad=copy.deepcopy(self.cols);bad[1]["unit"]=None
        with self.assertRaises(worker.ArtifactError): worker.columns(bad)
        bad=copy.deepcopy(self.p);bad["source_sha256"]="bad"
        with self.assertRaises(worker.ArtifactError): worker.TableWriter(self.root,"physiology-series",bad)
        bad=copy.deepcopy(self.p);bad["parameters"]["source_path"]="C:/private"
        with self.assertRaises(worker.ArtifactError): worker.TableWriter(self.root,"physiology-series",bad)
        with self.assertRaises(worker.ArtifactError):
            with self.writer() as w: w.write_table("bad",self.identity,self.cols,{"axis":"time"},{},[],0)

    def test_table_id_path_traversal_and_duplicate_rejected(self):
        with self.assertRaises(worker.ArtifactError):
            with self.writer() as w: w.write_table("../outside",self.identity,self.cols,self.coords,{},[],0)
        with self.assertRaises(worker.ArtifactError):
            with self.writer() as w:
                w.write_table("same",self.identity,self.cols,self.coords,{},[],0)
                w.write_table("same",self.identity,self.cols,self.coords,{},[],0)

    def test_byte_bound_is_failure_not_truncation(self):
        with self.assertRaises(worker.ArtifactError):
            with self.writer(max_bytes=1000) as w:
                w.write_table("long",self.identity,self.cols,self.coords,{},([i,1,True] for i in range(500)),500)
                w.finish()
        self.assertEqual(list(self.root.iterdir()),[])

    def test_hash_corruption_is_rejected_before_rows_callbacks(self):
        manifest,_=self.write();path=Path(manifest["path"]);data=path.read_bytes();path.write_bytes(data[:-10]+b"bad-data!!")
        rows=[]
        with self.assertRaisesRegex(worker.ArtifactError,"SHA-256"): worker.verify_artifact(manifest,on_rows=lambda t,o,r:rows.extend(r))
        self.assertEqual(rows,[])

    def test_integrity_receipt_must_be_present_even_if_new_hash_supplied(self):
        manifest,_=self.write();records=list(worker._read_records(manifest["path"]))
        broken=self.forge(manifest,records[:-1])
        with self.assertRaisesRegex(worker.ArtifactError,"complete receipt"): worker.verify_artifact(broken)

    def test_forged_chunk_offsets_counts_and_types_rejected(self):
        for mutate in [lambda r:r[2].update(offset=1),lambda r:r[2]["rows"][0].__setitem__(2,0),lambda r:r[-1].update(rows=1),lambda r:r[1]["columns"][1].update(unit=None)]:
            manifest,_=self.write();records=list(worker._read_records(manifest["path"]));mutate(records)
            with self.assertRaises(worker.ArtifactError): worker.verify_artifact(self.forge(manifest,records))
            # This test deliberately corrupted a named artifact; remove only its
            # known local file before making the next independent fixture.
            path=Path(manifest["path"]);self.assertEqual(path.parent,self.root);path.unlink()

    def test_manifest_directory_and_provenance_swapping_rejected(self):
        manifest,_=self.write()
        other=self.root/"other";other.mkdir()
        with self.assertRaises(worker.ArtifactError): worker.verify_artifact(manifest,other)
        bad=copy.deepcopy(manifest);bad["provenance_sha256"]="c"*64
        with self.assertRaisesRegex(worker.ArtifactError,"provenance"): worker.verify_artifact(bad)

    def test_replacement_during_streaming_is_rejected(self):
        manifest,_=self.write()
        def modify(t,o,rows):
            path=Path(manifest["path"])
            with path.open("ab") as stream: stream.write(b" ")
        with self.assertRaises(worker.ArtifactError): worker.verify_artifact(manifest,on_rows=modify)

    def test_fsync_failure_has_no_manifest_and_preserves_siblings(self):
        sibling=self.root/"keep";sibling.write_text("keep")
        with self.assertRaises(OSError):
            with self.writer() as w:
                w.write_table("one",self.identity,self.cols,self.coords,{},[[0.,1.,True]],1)
                with patch.object(worker.os,"fsync",side_effect=OSError("disk interrupted")): w.finish()
        self.assertIsNone(w.manifest);self.assertEqual([p.name for p in self.root.iterdir()],["keep"])

    def test_verifier_cli_receipt_and_existing_output_protection(self):
        manifest,_=self.write(2100);path=self.root/"manifest.json";path.write_text(json.dumps([manifest]),encoding="utf-8")
        out=self.root/"receipt.json"
        args=[sys.executable,str(ROOT/"scripts/workers/physiology_artifacts.py"),"--verify-manifest",str(path),"--directory",str(self.root),"--output",str(out)]
        process=subprocess.run(args,capture_output=True,text=True)
        self.assertEqual(process.returncode,0,process.stderr)
        result=json.loads(out.read_text());self.assertEqual(result["status"],"verified")
        self.assertEqual(result["artifacts"][0]["rows"],2100);self.assertNotIn("path",result["artifacts"][0])
        original=out.read_bytes();process=subprocess.run(args,capture_output=True,text=True)
        self.assertEqual(process.returncode,2);self.assertEqual(out.read_bytes(),original)
        self.assertEqual(out.parent,self.root);out.unlink()
        Path(manifest["path"]).write_text("corrupt",encoding="utf-8")
        process=subprocess.run(args,capture_output=True,text=True)
        self.assertEqual(process.returncode,2);self.assertEqual(json.loads(out.read_text())["status"],"error")

    def test_actual_eda_processed_values_preserved_without_raw(self):
        spec=importlib.util.spec_from_file_location("eda_artifact_fixture",ROOT/"scripts/workers/eda_events.py")
        eda=importlib.util.module_from_spec(spec);spec.loader.exec_module(eda)
        # Use its tested versioned recipe without editing either scientific worker.
        ps=importlib.util.spec_from_file_location("eda_parameters",ROOT/"tests/workers/eda_events.py")
        fixture=importlib.util.module_from_spec(ps);ps.loader.exec_module(fixture)
        t=np.arange(3000)/25;dt=np.maximum(t-21,0);raw=5+.001*t+np.exp(-dt/2)-np.exp(-dt/.7)
        p=eda.settings(fixture.EDAEvents().parameters(),25);b=eda.decompose(raw,t,25,p)
        cols=self.cols+[dict(name="phasic_us",type="float64",unit="uS",nullable=False,role="processed_measure")]
        arrays={"time_s":b["times"],"tonic_us":b["tonic_us"],"retained":b["retained"],"phasic_us":b["phasic_us"]}
        with self.writer() as w:
            w.write_arrays("eda-continuous",self.identity,arrays,cols,self.coords,{"source_row_start":0,"source_row_end_exclusive":3000},)
            manifest=w.finish()
        observed=[];worker.verify_artifact(manifest,on_rows=lambda t,o,r:observed.extend(r))
        self.assertEqual(len(observed),3000)
        np.testing.assert_array_equal(np.asarray(observed)[:,1].astype(float),b["tonic_us"])
        np.testing.assert_array_equal(np.asarray(observed)[:,3].astype(float),b["phasic_us"])
        self.assertNotIn(b'raw_us',Path(manifest["path"]).read_bytes())

    def test_actual_standard_worker_artifacts_for_six_modalities(self):
        ps=importlib.util.spec_from_file_location("physiology_adapter_fixture",ROOT/"tests/workers/physiology.py")
        fixture=importlib.util.module_from_spec(ps);ps.loader.exec_module(fixture)
        case=fixture.PhysiologyTests();case.setUp()
        try:
            nk=fixture.worker.require_neurokit()
            fs=100;t=np.arange(6000)/fs
            examples={"eda":(25,nk.eda_simulate(duration=60,sampling_rate=25,scr_number=3,noise=0,random_state=1)),
                      "eeg":(256,20*np.sin(2*np.pi*10*np.arange(2560)/256)),
                      "ecg":(250,nk.ecg_simulate(duration=40,sampling_rate=250,noise=0,random_state=1)),
                      "ppg":(100,nk.ppg_simulate(duration=40,sampling_rate=100,heart_rate=70,random_state=1)),
                      "respiration":(100,np.sin(2*np.pi*.2*t)),
                      "emg":(500,np.sin(2*np.pi*80*np.arange(5000)/500))}
            for modality,(fs,x) in examples.items():
                with self.subTest(modality=modality):
                    directory=self.root/modality;directory.mkdir()
                    request=case.request(modality,x,fs,parameters=fixture.RESPIRATION_DECLARATION if modality=="respiration" else None);request["artifact_directory"]=str(directory)
                    result=fixture.worker.run(request)
                    self.assertTrue(result["quality"]["usable"])
                    self.assertTrue(result["quality"]["complete_processed_artifacts"])
                    self.assertTrue(result["artifacts"])
                    manifests={m["kind"]:m for m in result["artifacts"]}
                    for manifest in result["artifacts"]: worker.verify_artifact(manifest,directory)
                    self.assertEqual(manifests["physiology-events"]["rows"],result["quality"]["event_records_total"])
                    if modality=="eeg": self.assertNotIn("physiology-series",manifests)
                    else: self.assertEqual(manifests["physiology-series"]["rows"],len(x))
                    for manifest in result["artifacts"]:
                        tables=[];worker.verify_artifact(manifest,on_table=tables.append)
                        self.assertTrue(all(not c["name"].startswith("raw") for table in tables for c in table["columns"]))
        finally: case.tearDown()

    def test_actual_event_worker_preserves_full_series_and_source_indices(self):
        ps=importlib.util.spec_from_file_location("event_artifact_fixture",ROOT/"tests/workers/eda_events.py")
        fixture=importlib.util.module_from_spec(ps);ps.loader.exec_module(fixture)
        case=fixture.EDAEvents();case.setUp()
        try:
            t=np.arange(3000)/25;dt=np.maximum(t-21,0);x=5+.001*t+np.exp(-dt/2)-np.exp(-dt/.7)
            request=case.request(x);request["artifact_directory"]=str(self.root)
            result=fixture.worker.run(request)
            saved=next(m for m in result["artifacts"] if m["kind"]=="physiology-series")
            rows=[];worker.verify_artifact(saved,on_rows=lambda t,o,r:rows.extend(r))
            self.assertEqual(len(rows),3000);self.assertLessEqual(len(result["series"]),2000)
            self.assertEqual(rows[-1][1],2999)
            event=next(m for m in result["artifacts"] if m["kind"]=="physiology-events")
            self.assertEqual(worker.verify_artifact(event)["rows"],result["quality"]["scr_candidates"])
            self.assertEqual(result["engine"]["worker_sha256"],worker.digest_file(ROOT/"scripts/workers/eda_events.py"))
        finally: case.tearDown()

    def test_partial_scientific_failure_keeps_prior_valid_segment_artifacts(self):
        ps=importlib.util.spec_from_file_location("partial_artifact_fixture",ROOT/"tests/workers/physiology.py")
        fixture=importlib.util.module_from_spec(ps);ps.loader.exec_module(fixture)
        case=fixture.PhysiologyTests();case.setUp()
        try:
            values=np.r_[np.sin(2*np.pi*80*np.arange(5000)/500),np.nan,1.,2.]
            request=case.request("emg",values,500);request["artifact_directory"]=str(self.root)
            result=fixture.worker.run(request)
            self.assertEqual(result["status"],"partial")
            self.assertEqual(result["quality"]["unavailable_channel_segments"],1)
            saved=next(m for m in result["artifacts"] if m["kind"]=="physiology-series")
            self.assertEqual(worker.verify_artifact(saved)["rows"],5000)
            self.assertEqual(saved["tables"],1)
        finally: case.tearDown()

    @unittest.skipUnless(importlib.util.find_spec("parselmouth"),"Run in prepared vision-audio profile")
    def test_actual_audio_all_spectral_and_pitch_frames_preserved(self):
        import soundfile as sf
        spec=importlib.util.spec_from_file_location("audio_artifact_worker",ROOT/"scripts/workers/physiology.py")
        physiology=importlib.util.module_from_spec(spec);spec.loader.exec_module(physiology)
        fs=16000;t=np.arange(fs*30)/fs;path=self.root/"tone.wav"
        sf.write(path,.25*np.sin(2*np.pi*200*t),fs,subtype="FLOAT")
        directory=self.root/"artifacts";directory.mkdir()
        request=dict(schema="brohn-worker-request/1.0",operation="physiology",modality="audio",source_path=str(path),format="wav",
                     metadata=dict(unit="FS",sampling_rate=fs,participant_id="p1",session_id="s1",origin="sample"),artifact_directory=str(directory))
        result=physiology.run(request)
        manifests={m["kind"]:m for m in result["artifacts"]}
        self.assertEqual(manifests["physiology-series"]["rows"],result["quality"]["series_samples_total"])
        self.assertGreater(manifests["physiology-series"]["rows"],2000)
        self.assertEqual(manifests["physiology-events"]["rows"],result["quality"]["event_records_total"])
        for m in manifests.values(): worker.verify_artifact(m,directory)
        rows=[];worker.verify_artifact(manifests["physiology-events"],on_rows=lambda t,o,r:rows.extend(r))
        voiced=[r[2] for r in rows if r[3]]
        self.assertAlmostEqual(float(np.median(voiced)),200,delta=.1)

    @unittest.skipUnless(importlib.util.find_spec("snirf"),"Run in prepared acquisition profile")
    def test_actual_fnirs_full_processed_channels_and_geometry_preserved(self):
        from snirf import Snirf
        spec=importlib.util.spec_from_file_location("fnirs_artifact_worker",ROOT/"scripts/workers/physiology.py")
        physiology=importlib.util.module_from_spec(spec);spec.loader.exec_module(physiology)
        fs=10;times=np.arange(3000)/fs
        values=np.column_stack([100+2*np.sin(2*np.pi*1.1*times)+.4*np.sin(2*np.pi*.04*times),110+2*np.sin(2*np.pi*1.1*times)+.5*np.sin(2*np.pi*.04*times)])
        path=self.root/"fixture.snirf"
        with Snirf(str(path),"w") as snirf:
            snirf.formatVersion="1.1";snirf.nirs.appendGroup();nirs=snirf.nirs[0]
            nirs.metaDataTags.SubjectID="synthetic"
            nirs.metaDataTags.MeasurementDate="2026-09-08";nirs.metaDataTags.MeasurementTime="00:00:00Z"
            nirs.metaDataTags.LengthUnit="mm";nirs.metaDataTags.TimeUnit="s";nirs.metaDataTags.FrequencyUnit="Hz"
            nirs.probe.wavelengths=np.array([760.,850.]);nirs.probe.sourcePos3D=np.array([[0.,0.,0.]])
            nirs.probe.detectorPos3D=np.array([[30.,0.,0.]])
            nirs.data.appendGroup();data=nirs.data[0];data.time=times;data.dataTimeSeries=values
            for wavelength in [1,2]:
                data.measurementList.appendGroup();item=data.measurementList[-1]
                item.sourceIndex=1;item.detectorIndex=1;item.wavelengthIndex=wavelength;item.dataType=1;item.dataTypeIndex=1
            snirf.save()
        directory=self.root/"artifacts";directory.mkdir()
        request=dict(schema="brohn-worker-request/1.0",operation="physiology",modality="fnirs",source_path=str(path),format="snirf",
            metadata=dict(unit="native",value_columns=["S1_D1 760","S1_D1 850"],sampling_rate=fs,participant_id="p1",session_id="s1",origin="sample"),
            parameters=dict(ppf=[6,6]),artifact_directory=str(directory))
        result=physiology.run(request);saved=result["artifacts"][0]
        self.assertEqual(saved["rows"],6000);self.assertEqual(saved["tables"],2)
        self.assertEqual(len(result["series"]),2000)
        tables=[];collected={}
        def rows(table,offset,chunk): collected.setdefault(table,[]).extend(chunk)
        worker.verify_artifact(saved,directory,on_table=tables.append,on_rows=rows)
        table=tables[0];actual=np.asarray(collected[table["table_id"]])
        expected=-np.log(values[:,0]/values[:,0].mean())
        np.testing.assert_allclose(actual[:,2],expected,atol=1e-12)
        self.assertEqual(table["support"]["source"]["source_detector_distance_m"],.03)
        self.assertEqual(actual[-1,1],2999)


if __name__=="__main__": unittest.main(verbosity=2)

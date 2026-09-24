"""Long Windows attempt paths must not change complete typed artifact bytes."""
import importlib.util
from pathlib import Path
import tempfile
import unittest

ROOT=Path(__file__).resolve().parents[2]
spec=importlib.util.spec_from_file_location("physiology_artifact_paths",ROOT/"scripts/workers/physiology_artifacts.py")
worker=importlib.util.module_from_spec(spec);spec.loader.exec_module(worker)


class ArtifactPaths(unittest.TestCase):
    def test_complete_identical_bytes_under_long_attempt_path(self):
        with tempfile.TemporaryDirectory(prefix="brohn-artifact-path-") as temporary:
            root=Path(temporary).resolve()
            self.assertTrue(root.is_relative_to(Path(tempfile.gettempdir()).resolve()))
            target=root
            while len(str(target))<215:
                target=target/("p"*min(60,214-len(str(target))))
            target.mkdir(parents=True)
            self.assertEqual(len(str(target)),215)
            provenance=dict(source_sha256="a"*64,engine=dict(name="original fixture",worker_sha256="b"*64),operation="physiology",origin="sample",parameters={"recipe":"original-fixture/1"})
            columns=[dict(name="time_s",type="float64",unit="s",nullable=False,role="coordinate"),
                     dict(name="retained",type="boolean",unit=None,nullable=False,role="support")]
            coordinates=dict(axis="time",reference="original source time",source_time_origin="0",source_time_unit="s")
            def save(folder):
                with worker.TableWriter(folder,"physiology-series",provenance,preview_limit=0) as writer:
                    writer.write_table("original",{"recording_id":"original","channel":"eda"},columns,coordinates,{},[[0.,True],[.04,False]],2)
                    return writer.finish()
            short=save(root);long=save(target);again=save(target)
            self.assertEqual(long,again)
            self.assertLessEqual(len(str(Path(long["path"]))),250)
            self.assertEqual(Path(short["path"]).read_bytes(),Path(long["path"]).read_bytes())
            self.assertEqual(short["sha256"],long["sha256"])
            self.assertEqual(worker.verify_artifact(long,target)["rows"],2)
            self.assertEqual(list(target.glob("*.tmp")),[])
            self.assertEqual(len(list(target.glob("*.ndjson"))),1)


if __name__=="__main__":unittest.main()

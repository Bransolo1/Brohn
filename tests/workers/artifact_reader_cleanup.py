"""A rejected complete artifact must release its file despite retained tracebacks."""
import copy
import importlib.util
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("artifact_cleanup_subject", ROOT / "scripts/workers/physiology_artifacts.py")
subject = importlib.util.module_from_spec(spec)
spec.loader.exec_module(subject)


class ReaderCleanup(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix="brohn-artifact-cleanup-")
        self.root = Path(self.tmp.name)
        provenance = dict(source_sha256="a" * 64, engine=dict(name="cleanup fixture", worker_sha256="b" * 64),
                          operation="fixture", origin="sample", parameters={})
        columns = [dict(name="time_s", type="float64", unit="s", nullable=False, role="coordinate"),
                   dict(name="value", type="float64", unit="uV", nullable=False, role="processed_measure")]
        coordinates = dict(axis="time", reference="recording-relative seconds", source_time_origin="0", source_time_unit="s")
        with subject.TableWriter(self.root, "physiology-series", provenance) as writer:
            writer.write_table("samples", dict(recording_id="recording", channel="voltage"), columns,
                               coordinates, {}, [[0., 1.], [1., 2.]], 2)
            self.manifest = writer.finish()

    def tearDown(self):
        self.tmp.cleanup()

    def inspect_failure(self, expected, **callbacks):
        opened = []
        original_open = Path.open
        def observe(path, *args, **kwargs):
            stream = original_open(path, *args, **kwargs)
            if path.resolve() == Path(self.manifest["path"]).resolve():
                opened.append(stream)
            return stream
        retained_error = None
        try:
            with patch.object(Path, "open", observe):
                try:
                    subject.verify_artifact(self.manifest, **callbacks)
                except BaseException as error:
                    retained_error = error
            self.assertIsInstance(retained_error, expected)
            self.assertIsNotNone(retained_error.__traceback__)
            self.assertGreaterEqual(len(opened), 2)
            self.assertTrue(all(stream.closed for stream in opened), "Reader kept its file open after rejecting the artifact")
            # This actual operation is denied on Windows by an open ordinary
            # Python reader. Keep the original exception/traceback reachable.
            path = Path(self.manifest["path"])
            moved = path.with_suffix(".probe")
            path.rename(moved)
            moved.rename(path)
            self.assertEqual(subject.digest_file(path), self.manifest["sha256"])
            self.assertIsNotNone(retained_error.__traceback__)
        finally:
            # Test-only cleanup also makes the pre-fix failing case reproducible.
            for stream in opened:
                stream.close()

    def test_table_callback_error_releases_source(self):
        def fail(_):
            raise ValueError("Rejected selected table")
        self.inspect_failure(ValueError, on_table=fail)

    def test_row_callback_error_releases_source(self):
        def fail(*_):
            raise RuntimeError("Stopped while reading selected rows")
        self.inspect_failure(RuntimeError, on_rows=fail)

    def test_interruption_releases_source(self):
        def fail(*_):
            raise KeyboardInterrupt("Cancelled")
        self.inspect_failure(KeyboardInterrupt, on_rows=fail)

    def test_structural_rejection_releases_source(self):
        records = list(subject._read_records(self.manifest["path"]))
        records[2]["offset"] = 1
        path = Path(self.manifest["path"])
        path.write_bytes(b"".join(subject.encode(record) for record in records))
        self.manifest = copy.deepcopy(self.manifest)
        self.manifest.update(sha256=subject.digest_file(path), bytes=path.stat().st_size)
        self.inspect_failure(subject.ArtifactError)

    def test_header_rejection_releases_source(self):
        records = list(subject._read_records(self.manifest["path"]))
        records[0]["kind"] = "physiology-events"
        path = Path(self.manifest["path"])
        path.write_bytes(b"".join(subject.encode(record) for record in records))
        self.manifest.update(sha256=subject.digest_file(path), bytes=path.stat().st_size)
        self.inspect_failure(subject.ArtifactError)


if __name__ == "__main__":
    unittest.main()

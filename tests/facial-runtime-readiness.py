"""Readiness must verify bytes without inference, downloads or persistent PATH edits."""
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("facial_readiness", ROOT / "scripts/readiness/facial_runtime_check.py")
helper = importlib.util.module_from_spec(spec)
spec.loader.exec_module(helper)


class Readiness(unittest.TestCase):
    def test_exact_bytes_and_size(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "asset.bin"
            path.write_bytes(b"original")
            sha = hashlib.sha256(b"original").hexdigest()
            self.assertEqual(helper.checked_file(directory, "asset.bin", sha, 8)["status"], "ready")
            path.write_bytes(b"altered!")
            self.assertEqual(helper.checked_file(directory, "asset.bin", sha, 8)["status"], "mismatch")
            self.assertEqual(helper.checked_file(directory, "asset.bin", sha, 7)["status"], "mismatch")

    def test_missing_file(self):
        with tempfile.TemporaryDirectory() as directory:
            self.assertEqual(helper.checked_file(directory, "missing", "0" * 64)["status"], "missing")

    def test_outside_path_is_never_hashed(self):
        with tempfile.TemporaryDirectory() as directory, patch.object(helper, "digest", side_effect=AssertionError("must not read")):
            self.assertEqual(helper.checked_file(directory, "../elsewhere", "0" * 64)["status"], "mismatch")

    def test_assets_and_installed_source_are_both_required(self):
        with tempfile.TemporaryDirectory() as directory:
            base = Path(directory)
            manifest = base / "scripts/readiness"
            manifest.mkdir(parents=True)
            payload = base / "models"; payload.mkdir()
            dll = base / "native"; dll.mkdir()
            package = base / "package"; package.mkdir()
            records = []
            for where in (payload, dll, package):
                (where / "pinned").write_bytes(b"bytes")
            item = {"relative_path": "pinned", "sha256": hashlib.sha256(b"bytes").hexdigest(), "bytes": 5}
            (manifest / "facial-models.json").write_text(json.dumps({"files": [item]}), encoding="utf-8")
            (manifest / "facial-runtime.json").write_text(json.dumps({"files": [item], "package_sources": [{"path": "pinned", "sha256": item["sha256"]}]}), encoding="utf-8")
            class Distribution:
                def locate_file(self, _): return package
            with patch.dict(os.environ, {"BROHN_FACIAL_MODEL_DIR": str(payload), "BROHN_FACIAL_FFMPEG_DIR": str(dll)}), patch.object(helper.importlib.metadata, "distribution", return_value=Distribution()):
                self.assertEqual([x["status"] for x in helper.assets(base)], ["ready"] * 3)
                (package / "pinned").write_bytes(b"other")
                self.assertEqual([x["status"] for x in helper.assets(base)], ["ready", "ready", "mismatch"])
                with patch.dict(os.environ, {"BROHN_FACIAL_MODEL_DIR": ""}):
                    self.assertEqual(helper.assets(base)[0]["status"], "missing")

    @unittest.skipUnless(os.name == "nt", "Windows-only scoped DLL API")
    def test_environment_and_dll_handle_restored_after_import_failure(self):
        class Handle:
            closed = False
            def close(self): self.closed = True
        handle = Handle()
        with tempfile.TemporaryDirectory() as directory, patch.dict(os.environ, {"BROHN_FACIAL_FFMPEG_DIR": directory}), patch.object(os, "add_dll_directory", return_value=handle):
            before = dict(os.environ)
            with self.assertRaisesRegex(RuntimeError, "import failure"):
                with helper.import_environment():
                    self.assertEqual(os.environ["HF_HUB_OFFLINE"], "1")
                    self.assertEqual(os.environ["PATH"].split(os.pathsep)[0], directory)
                    raise RuntimeError("import failure")
            self.assertEqual(dict(os.environ), before)
            self.assertTrue(handle.closed)


if __name__ == "__main__":
    unittest.main(verbosity=2)

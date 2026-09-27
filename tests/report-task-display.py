"""Generate original synthetic sources and qualify saved task displays in owned copies.

Usage: python tests/report-task-display.py Rscript REPO FRESH_EVIDENCE
Set R_LIBS_USER, BROHN_PUBLICATION_PYTHON and BROHN_PUBLICATION_NATIVE_MANIFEST
to the installed qualified dependencies. Requires the Windows native read guard.
No user workspace or remote service is opened. All scientific fixture jobs precede
the separate saved-display boundary. Earlier failed directories are never reused.
"""
from pathlib import Path
import hashlib
import json
import os
import shutil
import subprocess
import sys


def main():
    if len(sys.argv) != 4:
        raise SystemExit(__doc__)
    rscript, repo = (Path(x).resolve(strict=True) for x in sys.argv[1:3])
    out = Path(sys.argv[3]).resolve()
    if out.exists() or os.name != "nt":
        raise SystemExit("Use a fresh evidence directory on the qualified Windows native runtime.")
    for key in ("BROHN_PUBLICATION_PYTHON", "BROHN_PUBLICATION_NATIVE_MANIFEST"):
        if not os.environ.get(key) or not Path(os.environ[key]).is_file():
            raise SystemExit(f"Configure the installed {key} before running this test.")
    tests = repo / "tests"
    required = ["report-task-source-corpus.R", "report-task-display-models.R",
                "report-task-display-backend.R", "report-task-display-boundaries.R"]
    for name in required:
        if not (tests / name).is_file():
            raise SystemExit(f"Missing {name}")
    out.mkdir(parents=True)
    checkout = out / "backend-checkout"
    checkout.mkdir()
    for name in ("R", "scripts", "tests", "www", "src", "examples", "renv"):
        if (repo / name).exists():
            shutil.copytree(repo / name, checkout / name,
                            ignore=shutil.ignore_patterns("node_modules", "__pycache__", ".Rhistory"))
    for name in ("app.R", "DESCRIPTION", "renv.lock", ".Rprofile"):
        if (repo / name).is_file():
            shutil.copy2(repo / name, checkout / name)
    receipt = {"schema": "brohn-task-display-portable-qualification/0.1", "passed": False,
               "phases": [], "scope": "Generated synthetic sources, copied checkout/store, no browser or physical qualification."}
    original = {str(p.relative_to(checkout)): hashlib.sha256(p.read_bytes()).hexdigest()
                for p in checkout.rglob("*") if p.is_file()}
    (out / "source-files.json").write_text(json.dumps(original, indent=2) + "\n", encoding="utf-8")

    def run(name, *args):
        log = out / (name + ".log")
        with log.open("wb") as stream:
            code = subprocess.run([str(rscript), str(checkout / "tests" / name), *map(str, args)],
                                  cwd=checkout, stdout=stream, stderr=subprocess.STDOUT, check=False).returncode
        receipt["phases"].append({"script": name, "exit_code": code, "log": log.name})
        if code:
            raise RuntimeError(f"{name} failed; retained evidence is {out}")

    try:
        corpus = out / "corpus-04"
        corpus.mkdir()
        config = {"checkout": checkout.as_posix(), "out": corpus.as_posix(),
                  "native_manifest": Path(os.environ["BROHN_PUBLICATION_NATIVE_MANIFEST"]).resolve().as_posix()}
        (corpus / "config.json").write_text(json.dumps(config, indent=2) + "\n", encoding="utf-8")
        run("report-task-source-corpus.R", corpus / "config.json")
        run("report-task-display-models.R", out, corpus, out / "models")
        backend = out / "backend"
        backend.mkdir()
        shutil.copytree(corpus / "workspace", backend / "workspace")
        config.update(out=backend.as_posix(), packet=out.as_posix(), corpora=["04"])
        (backend / "config.json").write_text(json.dumps(config, indent=2) + "\n", encoding="utf-8")
        run("report-task-display-backend.R", backend / "config.json")
        # A comment-only copied installation change qualifies historical reader
        # independence from current preparation identity. The repository is intact.
        target = checkout / "R/platform-task-display.R"
        target.write_bytes(target.read_bytes() + b"\n# Portable historical-reader identity fixture.\n")
        boundary = out / "boundaries"
        boundary.mkdir()
        shutil.copytree(backend / "workspace", boundary / "workspace")
        run("report-task-display-boundaries.R", checkout, backend, boundary)
        receipt["passed"] = True
    finally:
        (out / "results.json").write_text(json.dumps(receipt, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"passed": True, "evidence": str(out)}))


if __name__ == "__main__":
    main()

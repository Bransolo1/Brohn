"""Independent audit of genuine saved cursor history; never writes the store."""
import csv
import hashlib
import io
import json
from fractions import Fraction
from pathlib import Path
import sqlite3
import sys

from PIL import Image

folder = Path(sys.argv[1]).resolve()
assert folder.name.startswith("brohn-media-history-browser-")
copy = json.loads((folder / "copy-receipt.json").read_text(encoding="utf-8"))
population = json.loads((folder / "population-results.json").read_text(encoding="utf-8"))
config = json.loads((folder / "fixture.json").read_text(encoding="utf-8"))
source = Path(copy["source_workspace"])
workspace = Path(config["workspace"])
digest = lambda value: hashlib.sha256(value).hexdigest()
checks = []


def check(value, label):
    assert value, label
    checks.append(label)


def readonly(location):
    return sqlite3.connect((location / "catalog.sqlite").as_uri() + "?mode=ro", uri=True)


def object_bytes(descriptor):
    value = (workspace / "objects" / "sha256" / descriptor["hash"][:2] / descriptor["hash"]).read_bytes()
    assert digest(value) == descriptor["hash"]
    assert len(value) == descriptor["size"]
    return value


old, current = readonly(source), readonly(workspace)
try:
    original = old.execute("SELECT * FROM entity_versions ORDER BY kind,id,revision").fetchall()
    for row in original:
        actual = current.execute("SELECT * FROM entity_versions WHERE kind=? AND id=? AND revision=?", row[:3]).fetchone()
        assert actual == row
    check(True, "Every original immutable version retains its entire exact SQL row, JSON and body hash")
    for row in old.execute("SELECT * FROM jobs ORDER BY id").fetchall():
        columns = [x[1] for x in old.execute("PRAGMA table_info(jobs)")]
        actual = current.execute("SELECT * FROM jobs WHERE id=?", (row[columns.index("id")],)).fetchone()
        assert actual == row
    check(True, "Every inherited job retains its entire original receipt and attempt state")
    for obj in copy["objects"]:
        object_bytes({"hash": obj["sha256"], "size": obj["bytes"]})
    check(True, "Every copied original object retains its complete bytes and SHA256")
    old_ids = {r[0] for r in old.execute("SELECT id FROM jobs")}
    new_ids = {r[0] for r in current.execute("SELECT id FROM jobs")} - old_ids
    expected_jobs = population["new_media_jobs"]
    check(new_ids == {j["id"] for j in expected_jobs} and len(new_ids) == 42,
          "Exactly42 new requests exist, all from the declared saved-cursor preparation")
    check(all(j["operation"] == "media_review" and j["status"] == "succeeded" and j["attempt"] == 1 for j in expected_jobs),
          "All42 cursor requests succeeded once; no original extraction or acoustic analysis was repeated")
    check(current.execute("SELECT count(*) FROM entities WHERE kind='report'").fetchone() ==
          old.execute("SELECT count(*) FROM entities WHERE kind='report'").fetchone(),
          "Scientific report count is unchanged")
    samples = []
    for job in expected_jobs:
        body = json.loads(current.execute("SELECT body_json FROM entity_versions WHERE kind='media_review' AND id=? AND revision=1",
                                         (job["result"]["media_review_id"],)).fetchone()[0])
        sample = body["request"]["selection"]["cursor_sample"]
        samples.append(sample)
        mapping = body["result"]["mapping"]
        expected_time = Fraction(sample, 8000)
        for key in [mapping["nominal_container_time"], mapping["audio_frame"]["container_time"]]:
            assert Fraction(int(key["numerator"]), int(key["denominator"])) == expected_time
        assert mapping["selected_sample"] == sample and mapping["sampling_rate"] == 8000
        assert mapping["physical_synchronization"] == "not_established"
        frame_index = sample // 200
        assert body["result"]["coverage"]["frame"]["frame_index"] == frame_index
        original = config["original"]["regular"]["media"]["body"]
        for key in ["audio_review", "catalog", "dataset", "extraction", "report", "source", "audio_ledger"]:
            assert body["request"][key] == original["request"][key]
        artifacts = {a["kind"]: a for a in body["artifacts"]}
        ledger = list(csv.DictReader(io.StringIO(object_bytes(artifacts["video-frame-ledger"]).decode("utf-8"))))
        assert len(ledger) == 160
        for index, row in enumerate(ledger):
            assert Fraction(int(row["pts_ticks"])) * Fraction(row["time_base"]) == Fraction(index, 40)
            assert Fraction(int(row["duration_ticks"])) * Fraction(row["time_base"]) == Fraction(1, 40)
        png = object_bytes(artifacts["recorded-video-frame"])
        with Image.open(io.BytesIO(png)) as image:
            raw = image.tobytes()
            assert image.mode == "RGB" and image.size == (64, 48)
            assert raw == bytes((frame_index, 255-frame_index, frame_index*3 % 256)) * (64*48)
        assert digest(raw) == body["result"]["frame_extraction"]["rgb24_sha256"]
    check(sorted(samples) == list(range(10010, 10421, 10)), "All42 explicitly planned distinct original samples are represented exactly once")
    check(True, "Every saved mapping matches independent sample/8000 rational time and sample//200 source-frame arithmetic")
    check(True, "Every42 review retains the same exact parent, extraction, source, report, audio window and original inventory refs")
    check(True, "Every complete160-frame ledger retains original integer PTS and duration arithmetic")
    check(True, "Every selected PNG independently decodes to its original analytic RGB frame, with matching RGB SHA256")
    check(True, "Every saved mapping explicitly preserves physical synchronization as not established")
finally:
    old.close()
    current.close()

check(digest((source / "catalog.sqlite").read_bytes()) == copy["source_catalog_sha256"],
      "Protected original source catalog remains unchanged")
receipt = {"passed": True, "checks": checks, "new_media_jobs": 42, "new_scientific_jobs": 0,
           "scope": "Independent readonly original-source, full-object and arithmetic checks; no application or physical synchronization qualification."}
(folder / "independent-source-results.json").write_text(json.dumps(receipt, indent=2), encoding="utf-8")
print(json.dumps({"passed": True, "checks": len(checks)}))

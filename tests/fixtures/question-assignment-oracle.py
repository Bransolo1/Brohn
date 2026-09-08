"""Independent standard-library oracle for the published assignment contract.

Run explicitly to regenerate question-assignment-oracle.json; the R test only
reads the pinned expected artifact and never computes its expected permutations.
"""
import hashlib
import json
from pathlib import Path

rows = []
for allocation in range(1, 13):
    for question, scope, stimulus in [
        ("q-original", "before", None),
        ("q-after", "after_each", "stimulus-a"),
        ("q-after", "after_each", "stimulus-b"),
        ("q-end", "end", None),
    ]:
        hashes = {}
        for number in range(1, 7):
            option = f"choice{number}"
            payload = dict(schema_version="brohn-option-assignment/1.0", seed="104729",
                           allocation_index=str(allocation), question_id=question,
                           scope=scope, stimulus_id=stimulus, option_id=option)
            encoded = json.dumps(payload, sort_keys=True, separators=(",", ":"), ensure_ascii=False)
            hashes[option] = hashlib.sha256(encoded.encode("utf-8")).hexdigest()
        rows.append(dict(allocation_index=allocation, question_id=question,
                         scope=scope, stimulus_id=stimulus,
                         option_order=sorted(hashes, key=lambda key: (hashes[key], key)),
                         rank_hashes=hashes))
output = dict(origin="original_synthetic", oracle="Python standard-library hashlib and json; no R compiler calls", rows=rows)
Path(__file__).with_name("question-assignment-oracle.json").write_text(json.dumps(output, indent=2)+"\n", encoding="utf-8")

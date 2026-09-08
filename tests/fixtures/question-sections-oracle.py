"""Independent two-level hash/anchor oracle. No R imports or compiler calls."""
import hashlib
import json
from pathlib import Path

def rank(items, allocation, scope, stimulus, level, parent=None):
    movable = [(i, item) for i, item in enumerate(items) if item[1]]
    def key(item):
        value = dict(schema_version="brohn-questionnaire-order/1.0", seed="104729",
                     allocation_index=str(allocation), scope=scope, stimulus_id=stimulus,
                     level=level, parent_id=parent, item_id=item[0])
        encoded = json.dumps(value, sort_keys=True, separators=(",", ":"))
        return hashlib.sha256(encoded.encode()).hexdigest(), item[0]
    out = list(items)
    for (position, _), item in zip(movable, sorted([v for _, v in movable], key=key)):
        out[position] = item
    return out

before = [("section-first", False), ("section-choices", True), ("section-middle", False),
          ("section-extra", True), ("section-last", False)]
groups = {
    "section-first": [("group-start", False, ["q-start"])],
    "section-choices": [("group-pair", True, ["q-driver", "q-follow"]),
                        ("group-independent", True, ["q-independent"]),
                        ("group-anchor", False, ["q-anchor"]), ("group-later", True, ["q-later"])],
    "section-middle": [("group-middle", False, ["q-middle"])],
    "section-extra": [("group-extra", False, ["q-extra"])],
    "section-last": [("group-last", False, ["q-last"])],
    "section-after": [("group-after", True, ["q-after"]), ("group-after-extra", True, ["q-after-extra"])],
    "section-end": [("group-end", False, ["q-end"])],
}
rows = []
for allocation in range(1, 13):
    for scope, stimulus in [("before", None), ("after_each", "stimulus-a"), ("after_each", "stimulus-b"), ("end", None)]:
        layout = before if scope == "before" else [("section-after" if scope == "after_each" else "section-end", False)]
        sections = rank(layout, allocation, scope, stimulus, "section")
        ordered_groups = {section: rank(groups[section], allocation, scope, stimulus, "group", section) for section, _ in sections}
        rows.append(dict(allocation_index=allocation, scope=scope, stimulus_id=stimulus,
                         section_order=[s for s, _ in sections],
                         group_orders={s: [g[0] for g in ordered_groups[s]] for s, _ in sections},
                         question_order=[q for s, _ in sections for g in ordered_groups[s] for q in g[2]]))
Path(__file__).with_name("question-sections-oracle.json").write_text(json.dumps(dict(
    origin="original_synthetic", oracle="Independent Python hashlib/json with explicit anchored layouts", rows=rows), indent=2)+"\n")

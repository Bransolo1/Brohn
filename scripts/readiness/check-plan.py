"""Read-only preparation audit, with one generated repository status artifact.

Does not rerun methods, launch services, use devices, or activate product features.
"""
from collections import Counter
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import re

repo = Path(__file__).resolve().parents[2]
work = repo.parent.parent / "work"
def read(relative):
    return json.loads((repo / relative).read_text(encoding="utf-8-sig"))
checks = []
def check(name, passed, **details):
    checks.append(dict(name=name, passed=bool(passed), **details))

registry = read("docs/preparation/capability-register.json")
plan = read("docs/preparation/build-manifest.json")
capabilities = registry["capabilities"]
ids = [c["id"] for c in capabilities]
packages = {p["id"]: p for p in plan["work_packages"]}
owners = Counter(c for p in packages.values() for c in p["capability_ids"])
check("capability registry count and unique IDs", len(ids) == len(set(ids)) == registry["entry_count"])
check("every capability has exactly one owning work package", set(owners) == set(ids) and all(n == 1 for n in owners.values()))
check("work package IDs are unique", len(packages) == len(plan["work_packages"]))
check("work package prerequisites exist", all(d in packages for p in packages.values() for d in p["depends_on"]))
done, active = set(), set()
def visit(key):
    if key in active:
        return False
    if key in done:
        return True
    if key not in packages:
        return False
    active.add(key)
    if not all(visit(dep) for dep in packages[key]["depends_on"]):
        return False
    active.remove(key)
    done.add(key)
    return True
check("work package dependencies are acyclic", all(visit(key) for key in packages))
check("work package statuses and acceptance are explicit", all(p["status"] in plan["lifecycle"] and p["acceptance"] for p in packages.values()))

documents = ["docs/MASTER-ARCHITECTURE.md", "docs/preparation/LARGE-BUILD-READINESS.md",
             "docs/preparation/HOLISTIC-CAPABILITIES.md", "docs/preparation/PROTOCOL-TEMPLATES.md",
             "docs/preparation/ACQUISITION-TOOLING.md", "docs/preparation/PLATFORM-TOOLING.md",
             "docs/preparation/MEDIA-TOOLING.md", "docs/preparation/SEGMENTATION-TOOLING.md",
             "docs/preparation/ASTRA-BUILD-BRIEF.md", "docs/product/UNIFIED-EXPERIENCE.md",
             "docs/product/INTRODUCTION-AND-LAUNCH.md", "docs/brand/BRAND-SYSTEM.md",
             "docs/product/STUDY-LIFECYCLE.md", "docs/product/DESIGN-PORTABILITY.md"]
check("authoritative documents exist", all((repo / p).is_file() for p in documents))
broken = []
for relative in documents:
    path = repo / relative
    if not path.exists():
        continue
    for target in re.findall(r"\]\(([^)]+)\)", path.read_text(encoding="utf-8")):
        if "://" in target or target.startswith("#"):
            continue
        target = target.split("#")[0]
        if target and not (path.parent / target).exists():
            broken.append(dict(document=relative, target=target))
check("local links in architecture, tooling and product documents resolve", not broken, broken=broken)

journeys = read("docs/product/journey-acceptance.json")
surfaces = journeys["surface_coverage"]
surface_owners = Counter(c for surface in surfaces for c in surface["capability_ids"])
check("every capability appears once in the shared user interface map",
      set(surface_owners) == set(ids) and all(n == 1 for n in surface_owners.values()))
check("shared interface families have unique identities and states",
      len({surface["surface_id"] for surface in surfaces}) == len(surfaces)
      and all(surface["shared_states"] for surface in surfaces))
scenarios = journeys["journeys"]
check("planned whole-journey scenarios have unique identities and acceptance evidence",
      len({scenario["id"] for scenario in scenarios}) == len(scenarios) == journeys["journey_count"]
      and all(scenario["acceptance"] and scenario["evidence"] for scenario in scenarios))
check("usability goals remain explicitly unmeasured",
      all(scenario["status"] == "planned_not_executed"
          and scenario["target_status"] == "proposed_unmeasured" for scenario in scenarios))

scenario_map = {scenario["id"]: scenario for scenario in scenarios}
lifecycle = journeys["lifecycle_coverage"]
areas = {area["area_id"]: area for area in lifecycle}
expected_areas = {"workspace_history", "dataset_curation", "assets_templates", "clone", "portability",
                  "delivery", "participant_entry", "access_quotas", "resume_waves", "endings",
                  "collection_closure", "reanalysis", "collaboration", "backup", "retention"}
check("research lifecycle covers required operational areas exactly once",
      len(areas) == len(lifecycle) and set(areas) == expected_areas)
check("lifecycle areas link to known planned journeys",
      journeys["lifecycle_measurement_status"] == "planned_not_executed"
      and all(area["journey_ids"] and len(area["journey_ids"]) == len(set(area["journey_ids"]))
              and set(area["journey_ids"]) <= set(scenario_map)
              and area["measurement_status"] == "planned_not_executed" for area in lifecycle))
operational_cases = [scenario for scenario in scenarios if scenario.get("lifecycle_areas")]
check("operational journeys have known package owners and consistent reverse coverage",
      bool(operational_cases)
      and all(scenario.get("work_package_ids") and set(scenario["work_package_ids"]) <= set(packages)
              and set(scenario["lifecycle_areas"]) <= set(areas)
              and set(scenario["lifecycle_areas"]) == {key for key, area in areas.items()
                  if scenario["id"] in area["journey_ids"]} for scenario in operational_cases)
      and all(scenario_map[key].get("lifecycle_areas") for area in lifecycle for key in area["journey_ids"]
              if key in scenario_map))
check("local and hosted delivery have explicit package gates",
      {gate["id"] for gate in plan["delivery_gates"]} == {"local_lab", "hosted_participants"}
      and all(gate["required_packages"] and set(gate["required_packages"]) <= set(packages)
              and gate["acceptance"] for gate in plan["delivery_gates"]))
check("cross-cutting lifecycle and portability specifications resolve",
      all((repo / plan["cross_cutting_specifications"][key]).is_file()
          for key in ["study_lifecycle", "design_portability"]))

brand = read("www/brand/asset-manifest.json")
brand_results = read("docs/brand/verification.json")
brand_icons = [asset for asset in brand["assets"] if asset.startswith("www/brand/icons/")]
check("original brand assets exist and match declared icon inventory",
      len(set(brand_icons)) == len(brand_icons) == brand["icon_count"]
      and all((repo / asset).is_file() for asset in brand["assets"]))
font_path = repo / "www/brand/fonts/Manrope-Variable.ttf"
check("local brand font matches pinned provenance and includes its licence",
      font_path.is_file() and hashlib.sha256(font_path.read_bytes()).hexdigest() == brand["font"]["sha256"]
      and (repo / "www/brand/fonts/OFL.txt").is_file())
check("brand tokens and reviewable desktop/narrow previews exist",
      all((repo / asset).is_file() for asset in ["www/brand/tokens.css", "www/brand/tokens.json",
          "www/brand/brohn-app-icon-256.png", "docs/brand/preview.html", "docs/brand/brand-board.png",
          "docs/brand/brand-board-narrow.png", "docs/brand/interface-direction.png"]))
check("recorded brand contrast checks passed",
      bool(brand_results["colour_pairs"]) and all(pair["passed"] is True
          and pair["ratio"] >= pair["minimum"] for pair in brand_results["colour_pairs"]))
check("recorded desktop and narrow accessibility preview checks passed",
      brand_results["status"] == "passed" and not brand_results["failures"]
      and {view["viewport"] for view in brand_results["views"]} == {"1400px", "390px"}
      and all(not view["violations"] for view in brand_results["views"])
      and brand_results["reduced_motion_checked"] is True)

new_results = ["acquisition-results.json", "platform-results-r.json", "platform-results-web.json",
               "media-results.json", "segmentation-results.json"]
new_count = 0
evidence = []
for name in new_results:
    result = read("docs/preparation/" + name)
    records = result["checks"]
    passed = sum(row.get("passed") is True for row in records)
    check("recorded reference results: " + name, bool(records) and passed == len(records))
    new_count += passed
    evidence.append(dict(file="docs/preparation/" + name, passing_assertions=passed,
                         status=result.get("status", "recorded_reference_results")))

media = read("docs/preparation/media-models.json")
for model in media["models"]:
    path = work / "tooling/media-models" / model["filename"]
    check("cached model integrity: " + model["filename"], path.is_file() and hashlib.sha256(path.read_bytes()).hexdigest() == model["sha256"])
segment = read("docs/preparation/segmentation-results.json")
segment_path = work / "tooling/segmentation-venv/models/magic_touch_v1.tflite"
check("selected compatible segmentation model integrity", segment_path.is_file() and hashlib.sha256(segment_path.read_bytes()).hexdigest() == segment["model"]["sha256"])
media_result = read("docs/preparation/media-results.json")
check("media result binds current model manifest", hashlib.sha256((repo / "docs/preparation/media-models.json").read_bytes()).hexdigest() == media_result["model_manifest_sha256"])
for environment in ["methods-venv", "acquisition-venv", "vision-audio-venv", "segmentation-venv"]:
    check("local Python worker exists: " + environment, (work / "tooling" / environment / "Scripts/python.exe").is_file())
for library, required in [("r-library-platform", "RSQLite"), ("r-library-methods", "saccades"),
                          ("r-library-implicit-methods", "IATscores")]:
    check("isolated R preparation library exists: " + library, (work / library / required / "DESCRIPTION").is_file())
check("isolated survey/task packages exist", (work / "tooling/research-web-tools/node_modules/survey-core/package.json").is_file())

success = all(c["passed"] for c in checks)
report = dict(schema="brohn-large-build-preparation/0.1.0", generated_utc=datetime.now(timezone.utc).isoformat(),
              development_preparation_ready=success, product_implemented=False,
              capability_count=len(ids), family_count=len({c["family_id"] for c in capabilities}),
              work_packages=len(packages), new_reference_assertions=new_count,
              planned_journeys=len(scenarios), shared_ui_families=len(surfaces),
              lifecycle_areas=len(areas), planned_operational_journeys=len(operational_cases),
              original_icons=brand["icon_count"], brand_contrast_pairs=len(brand_results["colour_pairs"]),
              checks=checks, evidence=evidence,
              preserved_unavailable=media_result.get("unavailable_capabilities", []),
              selected_segmentation_fallback="MediaPipe 0.10.21 + MagicTouch v1; separate environment",
              external_inputs=plan["external_inputs"],
              limitations=["This reads recorded test evidence and verifies artifact presence/integrity; it does not rerun the tests.",
                           "Installed binaries are not evidence that all product routes, physical devices or populations are supported.",
                           "Planned usability scenarios are not participant findings; accessibility evidence covers the static brand preview only."])
output = repo / "docs/preparation/readiness-results.json"
output.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
print(json.dumps({key: report[key] for key in ["development_preparation_ready", "product_implemented", "capability_count", "family_count", "work_packages", "new_reference_assertions", "planned_journeys", "shared_ui_families", "lifecycle_areas", "planned_operational_journeys", "original_icons", "brand_contrast_pairs"]}))
if not success:
    print(json.dumps([c for c in checks if not c["passed"]]))
raise SystemExit(0 if success else 1)

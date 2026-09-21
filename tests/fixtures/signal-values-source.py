"""Original schema-shaped edge data, explicitly not measured physiology."""
import copy
import importlib.util
import json
from pathlib import Path
import sys

ROOT=Path(__file__).resolve().parents[2]
spec=importlib.util.spec_from_file_location("exact_values_fixture",ROOT/"tests/workers/signal_values.py")
m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
folder=Path(sys.argv[1]);fixture=m.Values();fixture.folder=folder
rows=[[float(i),float(i),True,i,"",False] for i in range(137)]
rows[1][1]=-0.0;rows[2][1]=None;rows[3][2]=False;rows[4][2]=None;rows[5][0]=None;rows[6][4]="\nOriginal \u96ea <script>literal</script>"
base=fixture.request(rows);tables=[]
m.w.artifacts.verify_artifact(base["artifact"],on_table=tables.append)
template=tables[0];manifests=[]
provenance={"source_sha256":"a"*64,"engine":{"name":"Original schema-shaped UI fixture","worker_sha256":"b"*64},"operation":"physiology","origin":"sample","parameters":{"scientifically_qualified":False}}
for kind,axes in [("physiology-series",["time","frequency"]),("physiology-events",["event"])]:
    dest=folder/kind;dest.mkdir()
    with m.w.artifacts.TableWriter(dest,kind,provenance,chunk_rows=17) as writer:
        for axis in axes:
            table=copy.deepcopy(template);table["columns"][0]["unit"]="Hz" if axis=="frequency" else "s"
            table["columns"][1]["unit"]="uV^2/Hz" if axis=="frequency" else "ms" if axis=="event" else "uS"
            coords={**table["coordinates"],"axis":axis}
            writer.write_table("exact-"+axis,table["identity"],table["columns"],coords,table["support"],rows,len(rows))
        manifests.append(writer.finish())
receipt=m.w.artifacts.verify_manifest(manifests)
(folder/"source.json").write_text(json.dumps({"artifacts":manifests,"artifact_verification":receipt,"oracle":{"source_rows":137,"null_value_row":2,"excluded_row":3,"unknown_row":4,"null_coordinate_row":5,"text_row":6,"signed_zero_row":1}}),encoding="utf-8")

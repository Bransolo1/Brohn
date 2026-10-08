"""Read exact original live PIDs through the same clock as the bounded observer."""
import json,math,sys
import psutil
assert psutil.__version__=='7.2.2'
pids=[int(value) for value in sys.argv[1:]]
assert pids and len(pids)==len(set(pids)) and all(pid>0 for pid in pids)
rows=[]
for pid in pids:
    process=psutil.Process(pid)
    creation=process.create_time();command=process.cmdline()
    assert math.isfinite(creation) and process.is_running() and process.create_time()==creation
    rows.append(dict(pid=pid,creation_decimal=repr(creation),creation_clock='psutil.Process.create_time/7.2.2',command=command))
print(json.dumps(dict(identities=rows),ensure_ascii=True))

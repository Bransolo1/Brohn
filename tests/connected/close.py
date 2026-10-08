"""Independent physical closure, then read-only inspection of the original collection."""
from common import *
HERE=Path(__file__).resolve().parent
import psutil,socket,sys,subprocess,math
assert len(sys.argv)==2
P=Path(sys.argv[1]).resolve();QA=Path(sys.executable).resolve()
errors=[];physical_errors=[];left=[];conserved=False
def optional(name):
    try:return read(P/name)
    except Exception as e:errors.append(name+': '+str(e));return None
try:pre=verify(P);conserved=True
except Exception as e:errors.append('inputs: '+str(e))
process=optional('PROCESS-RESULTS.json');native=optional('r-01/RESULTS.json')
cfg=optional('TEST-CONFIG.json')
startup_bindings=[]
if process:
    if process.get('observation_errors') or process.get('cleanup_errors'):
        physical_errors.append('Original process observation or cleanup was uncertain; closure cannot be qualified.')
    for row in process.get('observed_processes',[]):
        try:
            if psutil.Process(row['pid']).create_time()==row['created']:left.append(row)
        except psutil.NoSuchProcess:pass
        except Exception as e:physical_errors.append(str(e))
    if native and native.get('startup'):
        startup=native['startup']['owned']
        if len(startup)!=3 or {r['service'] for r in startup}!={'participant','acquisition','worker'}:
            errors.append('Startup did not retain exactly the three original owned services.')
        for row in startup:
            try:
                if row.get('creation_clock')!='psutil.Process.create_time/7.2.2':raise ValueError('Unbound original creation clock')
                value=row['creation_decimal']
                if not isinstance(value,str) or not value:raise ValueError('Missing live original creation decimal')
                creation=float(value)
                if not math.isfinite(creation):raise ValueError('Non-finite original creation decimal')
                matches=[r for r in process['observed_processes'] if r['pid']==row['pid'] and r['created']==creation and r['command']==row['command']]
                if len(matches)!=1:raise ValueError('Startup service lacks one exact observed descendant identity: '+row['service'])
                startup_bindings.append(dict(service=row['service'],startup=row,observed=matches[0]))
            except (KeyError,TypeError,ValueError) as error:errors.append('Startup identity: '+str(error))
    elif native and native.get('passed'):errors.append('Passing native result lacks original service startup identities.')
else:physical_errors.append('Missing valid original ownership receipt; cannot establish owned closure.')
rs=[];ports={}
try:
    scan_errors=[];rs=scan_r(psutil,scan_errors,'independent R scan')
    physical_errors.extend(scan_errors)
    if not cfg:raise ValueError('Missing original two-port configuration')
    for key in ['researcher_port','participant_port']:
        with socket.socket() as sock:
            sock.settimeout(.5);ports[key]=dict(port=cfg[key],closed=sock.connect_ex(('127.0.0.1',cfg[key]))!=0)
except Exception as e:physical_errors.append(str(e))
physical=bool(not left and not rs and len(ports)==2 and all(r['closed'] for r in ports.values()) and not physical_errors)
inspection=None;inspected=None
if physical and conserved and process and process.get('passed') and native and native.get('passed'):
    command=[str(QA),'-B',str(HERE/'inspect_saved.py'),str(P/'TEST-CONFIG.json'),str(P/'inspection')]
    try:
        child=subprocess.run(command,capture_output=True,text=True,timeout=30,creationflags=FLAGS)
        inspection=dict(command=command,exit_code=child.returncode,stdout=child.stdout,stderr=child.stderr)
        inspected=optional('inspection/RESULTS.json')
    except Exception as e:errors.append('inspection: '+str(e));inspection=dict(command=command,error=str(e))
    write(P/'INSPECTION-PROCESS.json',inspection)
try:verify(P)
except Exception as e:conserved=False;errors.append('final conservation: '+str(e))
passed=bool(physical and conserved and not errors and process and process.get('passed') and native and native.get('passed') and
    inspected and inspected.get('passed') and inspected.get('original_workspace_files_unchanged') and inspection.get('exit_code')==0)
out=dict(passed=passed,physical_closed=physical,protected_inputs_exact=conserved,remaining_owned=left,remaining_R=rs,
    ports=ports,errors=errors,physical_errors=physical_errors,forced=None if not process else process.get('forced_termination'),
    observed_identities=0 if not process else len(process.get('observed_processes',[])),
    startup_bindings=startup_bindings,
    process_result=None if not (P/'PROCESS-RESULTS.json').exists() else entry(P/'PROCESS-RESULTS.json'),
    native_result=native,inspection=inspection,reporter=entry(Path(__file__).resolve()))
write(P/'AFTER-CLOSED.json',out)
print(json.dumps(dict(passed=passed,physical_closed=physical,ports=ports,errors=errors,sha256=sha(P/'AFTER-CLOSED.json'))))
sys.exit(0 if passed else 1)

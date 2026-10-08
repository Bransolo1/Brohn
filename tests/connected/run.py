"""Run the genuine author -> Publish -> participant -> automatic report journey."""
from common import *
import argparse,math,socket,subprocess,sys,time
import psutil

HERE=Path(__file__).resolve().parent
def parser():
    p=argparse.ArgumentParser(description=__doc__)
    for name in ['checkout','rscript','r-library','node','chrome','workspace','output','methods-python','acquisition-python','publication-native-manifest']:
        p.add_argument('--'+name,required=True,type=Path)
    p.add_argument('--browser-package',type=Path,help='Installed package.json using the checkout pnpm lock; defaults to checkout/package.json.')
    p.add_argument('--researcher-port',type=int,default=48010)
    p.add_argument('--participant-port',type=int,default=48011)
    return p
def main():
    args=parser().parse_args();assert psutil.__version__=='7.2.2','Use the documented psutil7.2.2 environment.'
    checkout=source_path(args.checkout);output=args.output.resolve();workspace=args.workspace.resolve()
    assert checkout.is_dir() and (checkout/'scripts/run-brohn.R').is_file()
    assert not output.exists() and not workspace.exists(),'Choose fresh output and workspace paths. Prior evidence is never reset.'
    assert not output.is_relative_to(checkout) and not workspace.is_relative_to(checkout),'Keep generated data outside the checkout.'
    assert not output.is_relative_to(workspace) and not workspace.is_relative_to(output)
    assert args.researcher_port!=args.participant_port and all(1024<=x<=65535 for x in [args.researcher_port,args.participant_port])
    for port in [args.researcher_port,args.participant_port]:
        with socket.socket() as sock:
            sock.settimeout(.5);assert sock.connect_ex(('127.0.0.1',port))!=0,'Selected port is occupied.'
    package=(args.browser_package or checkout/'package.json').resolve()
    lock=package.parent/'pnpm-lock.yaml';metadata=package.parent/'node_modules/@playwright/test/package.json'
    assert sha(lock)==sha(checkout/'pnpm-lock.yaml'),'Install the checkout locked browser dependencies.'
    assert read(metadata)['version']==read(checkout/'package.json')['devDependencies']['@playwright/test']
    tools=[Path(sys.executable),args.rscript,args.node,args.chrome,args.methods_python,args.acquisition_python,args.publication_native_manifest,
        package,lock,metadata,checkout/'renv.lock',Path(psutil.__file__)]
    assert args.r_library.is_dir() and all(p.is_file() for p in tools)
    output.mkdir(parents=True);workspace.parent.mkdir(parents=True,exist_ok=True)
    write(output/'INPUTS.json',dict(checkout=str(checkout),source_files=source_files(checkout),
        test_files=[entry(p) for p in sorted(HERE.iterdir()) if p.is_file()],tools=[entry(p) for p in tools],
        selected_r_library=str(args.r_library.resolve()),psutil_version=psutil.__version__))
    config=dict(root=str(checkout),installation=str(checkout),workspace=str(workspace),node=str(args.node.resolve()),
        chrome=str(args.chrome.resolve()),python=str(Path(sys.executable).resolve()),package_json=str(package),
        researcher_port=args.researcher_port,participant_port=args.participant_port,browser_test=str(HERE/'connected.mjs'),
        browser_result=str(output/'r-01/browser/RESULTS.json'),identity_helper=str(HERE/'identity.py'))
    write(output/'TEST-CONFIG.json',config)
    env=dict(os.environ,LC_ALL='C',PYTHONDONTWRITEBYTECODE='1',R_LIBS_USER=str(args.r_library.resolve()),
        BROHN_PYTHON_METHODS=str(args.methods_python.resolve()),BROHN_PYTHON_ACQUISITION=str(args.acquisition_python.resolve()),
        BROHN_PUBLICATION_PYTHON=str(args.methods_python.resolve()),BROHN_PUBLICATION_NATIVE_MANIFEST=str(args.publication_native_manifest.resolve()),
        BROHN_HOSTED_PROFILE='')
    command=[str(args.rscript.resolve()),'--vanilla',str(HERE/'connected.R'),str(output/'TEST-CONFIG.json'),str(output/'r-01')]
    observed={};forced=[];phases=[];error=None;conserved=False;proc=None
    observation_errors=[];cleanup_errors=[]
    def all_r():return scan_r(psutil,observation_errors,'global R scan')
    def retain(p):
        stamp=p.create_time();assert math.isfinite(stamp)
        row=dict(pid=p.pid,created=stamp,parent_pid=p.ppid(),command=p.cmdline())
        if p.create_time()!=stamp:raise ValueError('Process identity changed during observation')
        observed[(p.pid,stamp)]=row
    def capture():
        for (pid,created),row in list(observed.items()):
            try:
                p=psutil.Process(pid)
                if p.create_time()!=created:continue
                for child in p.children(recursive=True):
                    try:
                        if child.create_time()>=created:retain(child)
                    except psutil.NoSuchProcess:pass
                    except Exception as caught:process_issue(observation_errors,'descendant observation',caught,child.pid)
            except psutil.NoSuchProcess:pass
            except Exception as caught:process_issue(observation_errors,'owned observation',caught,pid)
    def alive():
        result=[]
        for pid,created in observed:
            try:
                p=psutil.Process(pid)
                if p.create_time()==created:result.append((p,observed[(pid,created)]))
            except psutil.NoSuchProcess:pass
            except Exception as caught:process_issue(observation_errors,'owned liveness',caught,pid)
        return result
    began=time.monotonic()
    try:
        assert not all_r() and not observation_errors,'An R process or unverified process occupies the exclusive lane.'
        with (output/'r.stdout.log').open('xb') as stdout,(output/'r.stderr.log').open('xb') as stderr:
            proc=subprocess.Popen(command,cwd=checkout,env=env,stdout=stdout,stderr=stderr,creationflags=FLAGS)
            try:retain(psutil.Process(proc.pid))
            except Exception as caught:
                process_issue(observation_errors,'original launch observation',caught,proc.pid);raise
            write(output/'LAUNCH.json',dict(command=command,root=observed[next(iter(observed))],
                ceilings=dict(app_browser=240,phase=285,native_outer=300,postclose_inspector=30)))
            print(json.dumps(dict(started=True,pid=proc.pid,created=next(iter(observed))[1],output=str(output))),flush=True)
            while proc.poll() is None and time.monotonic()-began<285:
                capture()
                if observation_errors:raise RuntimeError('Process ownership could not be completely observed.')
                time.sleep(.1)
            capture();phases.append(dict(exit_code=proc.returncode,elapsed_s=time.monotonic()-began,timed_out=proc.poll() is None))
            assert proc.poll() is not None,'Native phase reached its285-second bound.'
            assert proc.returncode==0,'Original connected application journey returned nonzero.'
        deadline=min(began+300,time.monotonic()+3)
        while alive() and time.monotonic()<deadline:capture();time.sleep(.1)
        assert not alive() and not all_r() and not observation_errors,'Original launcher closure is incomplete or uncertain.'
        assert read(output/'r-01/RESULTS.json')['passed'],'Application/browser result failed.'
    except Exception as caught:error=str(caught)
    finally:
        # These helpers retain process-query failures. Unknown ownership never
        # becomes permission to terminate a process, nor a successful receipt.
        capture();deadline=min(began+300,time.monotonic()+5)
        while alive() and time.monotonic()<deadline:capture();time.sleep(.1)
        for process,row in reversed(alive()):
            try:
                if process.create_time()!=row['created'] or process.cmdline()!=row['command']:
                    raise ValueError('Original process identity could not be confirmed for cleanup')
                process.terminate();forced.append(dict(pid=row['pid'],created=row['created']))
            except psutil.NoSuchProcess:pass
            except Exception as caught:process_issue(cleanup_errors,'verified owner termination',caught,row['pid'])
        deadline=min(began+300,time.monotonic()+5)
        while alive() and time.monotonic()<deadline:time.sleep(.1)
        remaining=[row for process,row in alive()]
        remaining_r=all_r()
        try:verify(output);conserved=True
        except Exception as caught:error=(error or '')+'; conservation: '+str(caught)
        result=dict(passed=error is None and not forced and not remaining and conserved and not remaining_r and not observation_errors and not cleanup_errors,
            error=error,phases=phases,observation_errors=observation_errors,cleanup_errors=cleanup_errors,
            observed_processes=list(observed.values()),forced_termination=forced,remaining_owned=remaining,remaining_R=remaining_r,source_and_inputs_exact=conserved)
        write(output/'PROCESS-RESULTS.json',result)
    # A fresh interpreter performs independent closure and the original-data oracle.
    close_command=[sys.executable,'-B',str(HERE/'close.py'),str(output)]
    try:
        closed=subprocess.run(close_command,timeout=45,creationflags=FLAGS)
        write(output/'CLOSE-PROCESS.json',dict(command=close_command,exit_code=closed.returncode))
        return 0 if result['passed'] and closed.returncode==0 else 1
    except Exception as caught:
        write(output/'CLOSE-PROCESS.json',dict(command=close_command,error=str(caught),passed=False))
        return 1
if __name__=='__main__':sys.exit(main())

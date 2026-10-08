"""Mock-only runner robustness tests. No native process or listening socket starts."""
import contextlib,io,json,os,sys,tempfile,types,unittest
from pathlib import Path
from unittest.mock import patch
import common
import run as runner

class ClosedSocket:
    def __enter__(self):return self
    def __exit__(self,*args):pass
    def settimeout(self,value):pass
    def connect_ex(self,address):return 1

class Robustness(unittest.TestCase):
    def fixture(self,root):
        checkout=root/'checkout';checkout.mkdir();(checkout/'scripts').mkdir();(checkout/'scripts/run-brohn.R').write_text('# source')
        (checkout/'package.json').write_text(json.dumps({'devDependencies':{'@playwright/test':'1.63.0'}}))
        (checkout/'pnpm-lock.yaml').write_text('lockfileVersion: 9')
        metadata=checkout/'node_modules/@playwright/test';metadata.mkdir(parents=True)
        (metadata/'package.json').write_text(json.dumps({'version':'1.63.0'}))
        (checkout/'renv.lock').write_text('{}');library=root/'library';library.mkdir()
        tool=root/'selected-tool';tool.write_text('unexecuted mock tool')
        args=['runner','--checkout',str(checkout),'--output',str(root/'evidence'),'--workspace',str(root/'workspace'),'--r-library',str(library)]
        for flag in ['rscript','node','chrome','methods-python','acquisition-python','publication-native-manifest']:args+=['--'+flag,str(tool)]
        return checkout,args

    def test_source_reparse_is_refused_before_recursion(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp);(root/'R').mkdir();(root/'R/source.R').write_text('# retained')
            original=common.os.lstat;scans=[];scan=common.os.scandir
            def lstat(path,*args,**kwargs):
                value=original(path,*args,**kwargs)
                if Path(path)==root/'R':return types.SimpleNamespace(st_mode=value.st_mode,st_file_attributes=0x400)
                return value
            def scandir(path):scans.append(Path(path));return scan(path)
            with patch.object(common.os,'lstat',side_effect=lstat),patch.object(common.os,'scandir',side_effect=scandir):
                with self.assertRaisesRegex(ValueError,'reparse'):common.source_files(root)
            self.assertNotIn(root/'R',scans)

    def test_source_ancestor_alias_is_refused(self):
        with tempfile.TemporaryDirectory() as tmp:
            parent=Path(tmp);root=parent/'checkout';root.mkdir();original=common.os.lstat
            def lstat(path,*args,**kwargs):
                value=original(path,*args,**kwargs)
                if Path(path)==parent:return types.SimpleNamespace(st_mode=value.st_mode,st_file_attributes=0x400)
                return value
            with patch.object(common.os,'lstat',side_effect=lstat):
                with self.assertRaisesRegex(ValueError,'reparse'):common.source_files(root)

    def drive(self,kind):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp);checkout,args=self.fixture(root);state={'dead':False,'terminated':0,'time':0}
            class Owner:
                pid=101
                def create_time(self):return 12345.25
                def ppid(self):return 100
                def cmdline(self):return ['original mocked child']
                def children(self,recursive=True):raise runner.psutil.AccessDenied(self.pid)
                def terminate(self):
                    if kind=='cleanup':raise runner.psutil.AccessDenied(self.pid)
                    state['terminated']+=1;state['dead']=True
            owner=Owner()
            def process(pid):
                self.assertEqual(pid,101)
                if state['dead']:raise runner.psutil.NoSuchProcess(pid)
                return owner
            class Child:
                pid=101
                @property
                def returncode(self):return 1 if state['dead'] else None
                def poll(self):return self.returncode
            def tick():state['time']+=1;return state['time']
            def scan():
                if kind=='scan':raise runner.psutil.AccessDenied(999)
                return iter([])
            with contextlib.ExitStack() as stack:
                stack.enter_context(patch.object(sys,'argv',args))
                stack.enter_context(patch.object(runner.socket,'socket',return_value=ClosedSocket()))
                stack.enter_context(patch.object(runner.psutil,'process_iter',side_effect=scan))
                stack.enter_context(patch.object(runner.psutil,'Process',side_effect=process))
                launch=stack.enter_context(patch.object(runner.subprocess,'Popen',return_value=Child()))
                close=stack.enter_context(patch.object(runner.subprocess,'run',return_value=types.SimpleNamespace(returncode=0)))
                stack.enter_context(patch.object(runner.time,'monotonic',side_effect=tick))
                stack.enter_context(patch.object(runner.time,'sleep',return_value=None))
                stack.enter_context(contextlib.redirect_stdout(io.StringIO()))
                self.assertEqual(runner.main(),1)
            output=root/'evidence';result=common.read(output/'PROCESS-RESULTS.json')
            self.assertFalse(result['passed']);self.assertTrue(result['observation_errors'])
            self.assertTrue(result['source_and_inputs_exact']);self.assertTrue((output/'CLOSE-PROCESS.json').is_file())
            close.assert_called_once();self.assertEqual(close.call_args.kwargs['timeout'],45)
            if kind=='scan':launch.assert_not_called();self.assertEqual(state['terminated'],0)
            elif kind=='cleanup':self.assertTrue(result['cleanup_errors']);self.assertEqual(state['terminated'],0);self.assertTrue(result['remaining_owned'])
            else:self.assertEqual(state['terminated'],1);self.assertFalse(result['remaining_owned'])
            self.assertIn('unverified process' if kind=='scan' else 'ownership',result['error'])

    def test_preflight_denial_preserves_failure_and_closer(self):self.drive('scan')
    def test_midflight_observation_denial_preserves_receipt(self):self.drive('observation')
    def test_verified_cleanup_denial_is_retained(self):self.drive('cleanup')

if __name__=='__main__':unittest.main()

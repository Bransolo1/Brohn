# A deliberately stalled owned helper proves the actual R process boundary uses
# seconds and terminates descendants. No device or participant is contacted.
source("R/platform-load.R", encoding="UTF-8");brohn_load(ui=FALSE)
local({
  stopifnot(.Platform$OS.type=="windows")
  checks<-0L;check<-function(name,ok){if(!isTRUE(ok))stop(paste("Timeout QA:",name),call.=FALSE);checks<<-checks+1L}
  root<-tempfile("brohn-timeout-qa-");dir.create(root);root<-normalizePath(root,winslash="/")
  helper<-file.path(root,"original-stalled-helper.py");receipt<-file.path(root,"result.json");identity_path<-paste0(receipt,".owned.json")
  original<-.brohn_acq_script
  on.exit({
    assign(".brohn_acq_script",original,envir=.GlobalEnv)
    if(file.exists(identity_path)) for(identity in brohn_read_json_file(identity_path)) {
      try({handle<-ps::ps_handle(as.integer(identity$pid),as.POSIXct(identity$created,origin="1970-01-01",tz="UTC"));
        if(ps::ps_is_running(handle)) ps::ps_kill(handle)},silent=TRUE)
    }
    actual<-normalizePath(root,winslash="/",mustWork=FALSE)
    stopifnot(startsWith(tolower(actual),paste0(tolower(normalizePath(tempdir(),winslash="/")),"/")),grepl("^brohn-timeout-qa-",basename(actual)))
    unlink(actual,recursive=TRUE,force=TRUE)
  },add=TRUE)
  writeLines(c("import ctypes,json,os,pathlib,subprocess,sys,time", "from ctypes import wintypes",
    "kernel=ctypes.WinDLL('kernel32',use_last_error=True)",
    "kernel.OpenProcess.argtypes=[wintypes.DWORD,wintypes.BOOL,wintypes.DWORD];kernel.OpenProcess.restype=wintypes.HANDLE",
    "kernel.GetProcessTimes.argtypes=[wintypes.HANDLE]+[ctypes.POINTER(wintypes.FILETIME)]*4",
    "kernel.CloseHandle.argtypes=[wintypes.HANDLE]",
    "def identity(pid):",
    "    handle=kernel.OpenProcess(0x1000,False,pid)",
    "    if not handle: raise ctypes.WinError(ctypes.get_last_error())",
    "    try:",
    "        fields=[wintypes.FILETIME() for _ in range(4)]",
    "        if not kernel.GetProcessTimes(handle,*[ctypes.byref(f) for f in fields]): raise ctypes.WinError(ctypes.get_last_error())",
    "        created=((fields[0].dwHighDateTime<<32)|fields[0].dwLowDateTime)/10000000-11644473600",
    "        return {'pid':pid,'created':created}",
    "    finally: kernel.CloseHandle(handle)",
    "if '--child' in sys.argv:",
    "    pathlib.Path(sys.argv[-1]).write_text(json.dumps(identity(os.getpid())))",
    "    time.sleep(60);sys.exit(0)",
    "output=pathlib.Path(sys.argv[sys.argv.index('--output')+1])",
    "child_identity=pathlib.Path(str(output)+'.child.json')",
    "child=subprocess.Popen([sys.executable,__file__,'--child',str(child_identity)],creationflags=subprocess.CREATE_NO_WINDOW)",
    "while not child_identity.exists(): time.sleep(.01)",
    "pathlib.Path(str(output)+'.owned.json').write_text(json.dumps([identity(os.getpid()),json.loads(child_identity.read_text())]))",
    "time.sleep(60)","output.write_text(json.dumps({'status':'unexpected_completion'}))"),helper)
  assign(".brohn_acq_script",function() helper,envir=.GlobalEnv)
  began<-as.numeric(Sys.time())
  result<-tryCatch(.brohn_acq_run("original-stall",output=receipt,timeout=2),error=identity)
  elapsed<-as.numeric(Sys.time())-began
  check("real helper is interrupted at its two-second deadline",inherits(result,"error") && grepl("exceeded its 2 second time limit",conditionMessage(result),fixed=TRUE) && elapsed>=1.5 && elapsed<8)
  check("stalled process created ownership evidence but no completion receipt",file.exists(identity_path) && !file.exists(receipt))
  identities<-brohn_read_json_file(identity_path)
  alive<-function(identity) tryCatch(ps::ps_is_running(ps::ps_handle(as.integer(identity$pid),as.POSIXct(identity$created,origin="1970-01-01",tz="UTC"))),error=function(e) FALSE)
  deadline<-as.numeric(Sys.time())+3
  while(any(vapply(identities,alive,logical(1))) && as.numeric(Sys.time())<deadline) Sys.sleep(.05)
  check("timed-out owned interpreter is no longer running",length(identities)==2 && !alive(identities[[1]]))
  check("timeout also terminates the helper's owned descendant",!alive(identities[[2]]))
  cat(sprintf("Process timeout: %d actual scoped checks passed.\n",checks))
})

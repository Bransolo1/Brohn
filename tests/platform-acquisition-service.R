# Real Windows sharing locks on a fresh test-owned service file.
source("R/platform-load.R",encoding="UTF-8");brohn_load(ui=FALSE)
local({
  checks<-0L
  check<-function(name,ok) {if(!isTRUE(ok)) stop(paste("Acquisition service QA failed:",name),call.=FALSE);checks<<-checks+1L}
  rejected<-function(value) inherits(try(force(value),silent=TRUE),"try-error")
  until<-function(fn,timeout=5) {end<-as.numeric(Sys.time())+timeout;repeat {if(isTRUE(fn())) return(TRUE);if(as.numeric(Sys.time())>=end) return(FALSE);Sys.sleep(.01)}}
  root<-tempfile("brohn-acquisition-service-");dir.create(root);root<-normalizePath(root,winslash="/")
  store<-brohn_open_store(file.path(root,"workspace"));brohn_initialise_library(store);children<-list();manager<-NULL
  on.exit({
    for(child in children) if(child$is_alive()) {child$kill_tree();child$wait(3000)}
    if(!is.null(manager)) brohn_stop_acquisition_manager(store,manager)
    brohn_close_store(store)
    actual<-normalizePath(root,winslash="/",mustWork=FALSE)
    stopifnot(startsWith(tolower(actual),paste0(tolower(normalizePath(tempdir(),winslash="/")),"/")),grepl("^brohn-acquisition-service-",basename(actual)))
    unlink(actual,recursive=TRUE,force=TRUE)
  },add=TRUE)
  missing<-brohn_acquisition_service_status(store$root,store$workspace_id)
  check("absent service state is explicit and immediate",missing$status=="missing" && !missing$ready && missing$attempts==1)
  manager<-brohn_acquisition_manager(store);path<-file.path(store$root,"acquisitions","service.json")
  original<-readBin(path,"raw",n=65537)
  healthy<-brohn_acquisition_service_status(store$root,store$workspace_id)
  check("exact current process and workspace are verified",healthy$status=="ready" && healthy$ready && healthy$owner_status=="owned_alive")
  check("different workspace remains a distinct refusal",brohn_acquisition_service_status(store$root,"other-workspace")$status=="foreign_workspace")
  check("different expected PID cannot receive stop",rejected(brohn_request_acquisition_manager_stop(store$root,Sys.getpid()+1L)))
  if(.Platform$OS.type=="windows") {
    fixture<-file.path(root,"own-file-lock.py")
    writeLines(c("import ctypes,sys,time", "from pathlib import Path",
      "kernel=ctypes.WinDLL('kernel32',use_last_error=True)",
      "kernel.CreateFileW.argtypes=[ctypes.c_wchar_p,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_void_p,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_void_p]",
      "kernel.CreateFileW.restype=ctypes.c_void_p", "kernel.CloseHandle.argtypes=[ctypes.c_void_p]",
      "handle=kernel.CreateFileW(sys.argv[1],0x80000000,0,None,3,0x80,None)",
      "if handle==ctypes.c_void_p(-1).value: raise ctypes.WinError(ctypes.get_last_error())",
      "try:", "    Path(sys.argv[2]).write_text('locked')", "    deadline=time.monotonic()+15",
      "    while not Path(sys.argv[3]).exists():",
      "        if time.monotonic()>deadline: raise RuntimeError('Isolated lock fixture timed out')", "        time.sleep(.005)",
      "    time.sleep(int(sys.argv[4])/1000)", "finally:", "    kernel.CloseHandle(handle)"),fixture)
    lock<-function(label,delay) {
      ready<-file.path(root,paste0(label,"-ready"));release<-file.path(root,paste0(label,"-release"))
      child<-processx::process$new(.brohn_acq_python(),c(fixture,path,ready,release,as.character(delay)),
        stdout=file.path(root,paste0(label,".stdout")),stderr=file.path(root,paste0(label,".stderr")),windows_hide_window=TRUE,cleanup_tree=TRUE)
      children[[length(children)+1L]]<<-child
      locked<-until(function() file.exists(ready),timeout=15)
      if(!locked) cat(paste(readLines(file.path(root,paste0(label,".stderr")),warn=FALSE),collapse="\n"),"\n")
      check(paste(label,"actual exclusive file lock is acquired"),locked)
      list(child=child,release=release)
    }
    short<-lock("short",100)
    denied<-tryCatch(withCallingHandlers(readBin(path,"raw",n=1),warning=function(w) invokeRestart("muffleWarning")),error=identity)
    check("lock causes a real Windows open refusal",inherits(denied,"error"))
    writeLines("release",short$release)
    warnings<-character()
    recovered<-withCallingHandlers(brohn_acquisition_service_status(store$root,store$workspace_id),warning=function(w) {warnings<<-c(warnings,conditionMessage(w));invokeRestart("muffleWarning")})
    check("bounded retry recovers short sharing lock without warning spam",recovered$ready && recovered$attempts>1 && !length(warnings))
    short$child$wait(3000);check("short lock helper closes its owned file",!short$child$is_alive() && short$child$get_exit_status()==0)
    persistent<-lock("persistent",0);started<-as.numeric(Sys.time());warnings<-character()
    unavailable<-withCallingHandlers(brohn_acquisition_service_status(store$root,store$workspace_id),warning=function(w) {warnings<<-c(warnings,conditionMessage(w));invokeRestart("muffleWarning")})
    elapsed<-as.numeric(Sys.time())-started
    check("persistent lock is bounded and explicitly unavailable",unavailable$status=="unavailable" && !unavailable$ready && unavailable$attempts==10 && elapsed<3 && nzchar(unavailable$error))
    check("unavailable read has no false absent-owner claim or warnings",is.null(unavailable$owner_status) && !length(warnings) && identical(.brohn_acq_probe(manager$identity),"owned_alive"))
    check("unreadable state cannot authorize duplicate manager",rejected(brohn_acquisition_manager(store)))
    check("unreadable state cannot authorize stop control",rejected(brohn_request_acquisition_manager_stop(store$root,Sys.getpid())))
    writeLines("release",persistent$release);persistent$child$wait(3000)
    check("released persistent lock restores readiness",brohn_acquisition_ready(store$root,store$workspace_id))
  }
  writeBin(charToRaw("{"),path)
  corrupt<-brohn_acquisition_service_status(store$root,store$workspace_id)
  check("malformed JSON is invalid, not missing or retried",corrupt$status=="invalid" && !corrupt$ready && corrupt$attempts==1 && nzchar(corrupt$error))
  check("malformed state cannot authorize stop or duplicate owner",rejected(brohn_request_acquisition_manager_stop(store$root,Sys.getpid())) && rejected(brohn_acquisition_manager(store)))
  writeBin(as.raw(rep(32,65537)),path)
  check("oversized state is rejected before reading",brohn_acquisition_service_status(store$root)$status=="invalid")
  writeBin(charToRaw('{"status":"running"}'),path)
  check("missing ownership fields stay invalid",brohn_acquisition_service_status(store$root)$status=="invalid")
  writeBin(original,path);value<-brohn_parse(rawToChar(original));value$workspace_root<-root
  .brohn_acq_atomic(value,path)
  check("foreign source directory does not become this service",brohn_acquisition_service_status(store$root,store$workspace_id)$status=="foreign_workspace")
  writeBin(original,path)
  brohn_request_acquisition_manager_stop(store$root,Sys.getpid())
  check("recovered exact owner receives correctly bound stop",brohn_acquisition_stop_requested(store,manager))
  check("stop control does not alter original service bytes",identical(readBin(path,"raw",n=65537),original))
  brohn_stop_acquisition_manager(store,manager)
  check("orderly stopped service is explicit",brohn_acquisition_service_status(store$root,store$workspace_id)$status=="stopped")
  cat(sprintf("Acquisition service state: %d scoped checks passed.\n",checks))
})

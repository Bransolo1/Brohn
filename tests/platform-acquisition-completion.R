# Retained evidence for the intermittent completion assertion. Original local
# synthetic outlet only; no product monkeypatches and no active runtime access.
source("R/platform-load.R",encoding="UTF-8");brohn_load(ui=FALSE)
local({
  checks<-0L; children<-list(); manager<-NULL; store<-NULL; findings<-list()
  check<-function(name,ok) {if(!isTRUE(ok)) stop(paste("Acquisition completion QA failed:",name),call.=FALSE);checks<<-checks+1L}
  until<-function(fn,timeout=30) {end<-as.numeric(Sys.time())+timeout;repeat {if(isTRUE(fn())) return(TRUE);if(as.numeric(Sys.time())>=end) return(FALSE);Sys.sleep(.02)}}
  evidence_parent<-normalizePath("../../work/test-runs",winslash="/",mustWork=TRUE)
  # This exact-length prefix previously produced a failing 266-character chunk
  # path. The bounded filename regression must preserve collection and archive.
  root<-tempfile("brohn-acquisition-completion-",tmpdir=evidence_parent);dir.create(root);root<-normalizePath(root,winslash="/")
  cat("Retained acquisition completion evidence: ",root,"\n",sep="");flush.console()
  on.exit({
    if(!is.null(manager) && manager$is_alive() && !is.null(store)) {
      try(brohn_request_acquisition_manager_stop(store$root,manager$get_pid()),silent=TRUE)
      manager$wait(10000)
    }
    for(child in children) if(child$is_alive()) {child$kill_tree();child$wait(3000)}
    if(!is.null(store)) try(brohn_close_store(store),silent=TRUE)
    brohn_write_json_file(list(checks=checks,findings=findings,retained_root=root),file.path(root,"evidence.json"))
    if(exists("observations",inherits=FALSE)) brohn_write_json_file(observations,file.path(root,"last-observations.json"))
  },add=TRUE)
  store<-brohn_open_store(file.path(root,"workspace"));brohn_initialise_library(store)
  config<-file.path(root,"lsl.cfg");session<-brohn_id("synthetic");source_id<-brohn_id("source")
  writeLines(c("[multicast]","ResolveScope = machine","[lab]","KnownPeers = {127.0.0.1}",paste("SessionID =",session)),config)
  fixture<-file.path(root,"original-outlet.py")
  writeLines(c("import os,time", "from pathlib import Path", "import pylsl",
    "info=pylsl.StreamInfo('Brohn original completion QA','EDA',1,50,'double64',os.environ['BROHN_QA_SOURCE'])",
    "info.desc().append_child_value('origin','synthetic')",
    "c=info.desc().append_child('channels').append_child('channel')",
    "c.append_child_value('label','original_eda');c.append_child_value('unit','uS');c.append_child_value('type','EDA')",
    "outlet=pylsl.StreamOutlet(info,chunk_size=1,max_buffered=5)",
    "Path(os.environ['BROHN_QA_READY']).write_text('ready')", "i=0", "while True:",
    "    if outlet.have_consumers():", "        outlet.push_sample([float(i%5)],timestamp=pylsl.local_clock());i+=1", "    time.sleep(.02)"),fixture)
  outlet<-processx::process$new(.brohn_acq_python(),fixture,
    env=c("current",LSLAPICFG=config,BROHN_QA_SOURCE=source_id,BROHN_QA_READY=file.path(root,"outlet-ready")),
    stdout=file.path(root,"outlet.stdout"),stderr=file.path(root,"outlet.stderr"),windows_hide_window=TRUE,cleanup_tree=TRUE)
  children[[length(children)+1L]]<-outlet
  check("original isolated outlet starts",until(function() file.exists(file.path(root,"outlet-ready"))))
  manager<-processx::process$new(brohn_rscript(),c("--vanilla","scripts/run-acquisition.R","--root",store$root),
    env=c("current",R_LIBS_USER=paste(.libPaths(),collapse=.Platform$path.sep)),
    stdout=file.path(root,"manager.stdout"),stderr=file.path(root,"manager.stderr"),windows_hide_window=TRUE,cleanup_tree=TRUE)
  children[[length(children)+1L]]<-manager
  check("isolated manager ready",until(function() brohn_acquisition_ready(store$root)))
  study<-brohn_create_study(store,"Original repeated completion QA")
  discovery<-brohn_queue_lsl_discovery(store,study$id,session,source_id)
  check("exact source discovery completes",until(function() brohn_get_entity(store,"acquisition_discovery",discovery$id)$body$status %in% c("ready","failed")))
  discovery<-brohn_get_entity(store,"acquisition_discovery",discovery$id)
  check("original exact source discovered",identical(discovery$body$status,"ready") && length(discovery$body$result$streams)==1)
  observed<-discovery$body$result$streams[[1L]]
  channels<-list(list(id="eda",label="Original EDA",type="EDA",unit="uS",value_type="float64"))
  selected<-brohn_lsl_selection(discovery,observed$uid,"eda","declared-eda-clock","monotonic","signal",channels,"Original synthetic outlet declaration",.1)
  limits<-list(max_duration_s=30,max_samples=10000,max_bytes=4*1024^2,chunk_samples=32,inlet_buffer=2)
  observations<-list()
  observe<-function(id,phase) {
    warnings<-character()
    r<-withCallingHandlers(brohn_acquisition(store,id),warning=function(w) {warnings<<-c(warnings,conditionMessage(w));invokeRestart("muffleWarning")})
    row<-list(phase=phase,at=brohn_now(),revision=r$revision,status=r$body$status,
      completion_status=r$body$completion_status,original=r$body$original,
      inspection_complete=r$body$inspection$complete,inspection_samples=r$body$inspection$samples,
      inspection_quality_qualified=r$body$inspection$quality_qualified,inspection_signal_quality=r$body$inspection$signal_quality,
      inspection_quality_evidence=r$body$inspection$quality_evidence,
      python_request_hash=r$body$python_request_hash,live_snapshot=r$live_snapshot,error=r$body$error,warnings=as.list(warnings))
    observations[[length(observations)+1L]]<<-row
    r
  }
  repetitions<-as.integer(Sys.getenv("BROHN_ACQ_COMPLETION_REPETITIONS","8"))
  check("bounded explicit repetition count",is.finite(repetitions)&&repetitions>=1&&repetitions<=30)
  for(iteration in seq_len(repetitions)) {
    observations<-list()
    record<-brohn_queue_acquisition(store,study$id,discovery$id,list(selected),
      list(participant_id="explicit-original-P1",session_id=paste0("explicit-S",iteration)),"sample",
      "Original synthetic completion evidence only.",limits,study$revision,TRUE)
    check(paste(iteration,"receives ten original samples"),until(function() {r<-observe(record$id,"sampling");!is.null(r$live_snapshot)&&r$live_snapshot$samples>=10}))
    check(paste(iteration,"fresh request-bound stop accepted"),until(function() {
      r<-observe(record$id,"requesting_stop")
      !inherits(try(brohn_stop_acquisition(store,r$id,r$revision),silent=TRUE),"try-error")
    }))
    preserved<-until(function() !is.null(observe(record$id,"awaiting_archive")$body$original),timeout=20)
    record<-observe(record$id,"first_archived_read")
    brohn_write_json_file(observations,file.path(root,paste0("iteration-",iteration,"-observations.json")))
    check(paste(iteration,"archives original"),preserved)
    expected<-isTRUE(record$body$completion_status=="completed" && record$body$inspection$samples>=10 &&
      isTRUE(record$body$inspection$complete) && identical(record$live_snapshot$quality_qualified,FALSE))
    findings[[length(findings)+1L]]<-list(iteration=iteration,kind="unforced_completion",legacy_assertion=expected,record_id=record$id,
      completion_status=record$body$completion_status,inspection=record$body$inspection,live_snapshot=record$live_snapshot)
    # Retain the legacy assertion as evidence, but do not make telemetry
    # availability an acceptance requirement for a durable completed receipt.
    check(paste(iteration,"atomic stored completion receipt"),identical(record$body$completion_status,"completed") &&
      isTRUE(record$body$inspection$complete)&&record$body$inspection$samples>=10)
    check(paste(iteration,"persisted quality independent of optional telemetry"),identical(record$body$inspection$quality_qualified,FALSE) &&
      identical(record$body$inspection$signal_quality,"not_qualified")&&identical(record$body$inspection$quality_evidence,"verified_final_manifest"))
    check(paste(iteration,"every archived revision has final inspection"),all(vapply(observations,function(x)
      is.null(x$original)||(identical(x$completion_status,"completed")&&isTRUE(x$inspection_complete)&&x$inspection_samples>=10),logical(1))))
    archive<-brohn_acquisition_download(store,record$id);extracted<-file.path(root,paste0("iteration-",iteration,"-archive"));dir.create(extracted)
    zip::unzip(archive,exdir=extracted)
    manifest<-brohn_read_json_file(file.path(extracted,"manifest.json"),16*1024^2)
    check(paste(iteration,"immutable original proves complete and unqualified separately"),identical(manifest$completion_status,"completed") &&
      isTRUE(manifest$complete)&&identical(manifest$quality_qualified,FALSE)&&identical(manifest$signal_quality,"not_qualified")&&
      identical(.brohn_acq_hash(file.path(extracted,"manifest.json")),record$body$inspection$manifest_sha256))
    if(.Platform$OS.type=="windows") {
      legacy_path<-file.path(.brohn_acq_directory(store,record),"chunks",paste0("000001-",strrep("0",64),".jsonl"))
      check(paste(iteration,"real regression crosses old path limit with bounded checked chunk name"),nchar(legacy_path)>=260 &&
        all(vapply(manifest$chunks,function(x) grepl("^chunks/[0-9]{6}[.]jsonl$",x$path),logical(1))))
    }
    cat("Original completion cycle ",iteration," passed, samples=",record$body$inspection$samples,".\n",sep="");flush.console()
  }
  if(.Platform$OS.type=="windows") {
    path<-file.path(.brohn_acq_directory(store,record),"status.json")
    fixture<-file.path(root,"owned-status-lock.py");ready<-file.path(root,"lock-ready");release<-file.path(root,"lock-release")
    writeLines(c("import ctypes,sys,time", "from pathlib import Path", "k=ctypes.WinDLL('kernel32',use_last_error=True)",
      "k.CreateFileW.argtypes=[ctypes.c_wchar_p,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_void_p,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_void_p]",
      "k.CreateFileW.restype=ctypes.c_void_p", "k.CloseHandle.argtypes=[ctypes.c_void_p]",
      "h=k.CreateFileW(sys.argv[1],0x80000000,0,None,3,0x80,None)",
      "if h==ctypes.c_void_p(-1).value: raise ctypes.WinError(ctypes.get_last_error())", "try:",
      "    Path(sys.argv[2]).write_text('locked')", "    end=time.monotonic()+15", "    while not Path(sys.argv[3]).exists():",
      "        if time.monotonic()>end: raise RuntimeError('owned lock deadline')", "        time.sleep(.005)", "finally:", "    k.CloseHandle(h)"),fixture)
    locker<-processx::process$new(.brohn_acq_python(),c(fixture,path,ready,release),stdout=file.path(root,"lock.stdout"),
      stderr=file.path(root,"lock.stderr"),windows_hide_window=TRUE,cleanup_tree=TRUE)
    children[[length(children)+1L]]<-locker
    check("exclusive status lock acquired on test-owned completed recording",until(function() file.exists(ready)))
    locked<-observe(record$id,"forced_completed_status_lock")
    legacy<-isTRUE(locked$body$completion_status=="completed"&&locked$body$inspection$samples>=10&&
      isTRUE(locked$body$inspection$complete)&&identical(locked$live_snapshot$quality_qualified,FALSE))
    findings[[length(findings)+1L]]<-list(kind="forced_completed_status_lock",legacy_assertion=legacy,
      original_hash=locked$body$original$hash,revision=locked$revision,live_snapshot=locked$live_snapshot,inspection=locked$body$inspection,
      archived_manifest=manifest)
    check("real sharing lock makes optional live snapshot unavailable",is.null(locked$live_snapshot))
    check("same original assertion fails while durable complete evidence is unchanged",!legacy && identical(locked$body,record$body))
    check("new durable completion and explicit quality evidence remain true during lock",isTRUE(locked$body$inspection$complete) &&
      identical(locked$body$inspection$quality_qualified,FALSE) && identical(locked$body$inspection$signal_quality,"not_qualified") &&
      identical(locked$body$inspection$quality_evidence,"verified_final_manifest"))
    check("verified immutable original stays downloadable despite telemetry lock",identical(.brohn_acq_hash(brohn_acquisition_download(store,record$id)),record$body$original$hash))
    writeLines("release",release);locker$wait(3000)
    unlocked<-observe(record$id,"released_completed_status_lock")
    check("no catalog write needed to recover original assertion",identical(unlocked$revision,record$revision)&&identical(unlocked$body,record$body)&&identical(unlocked$live_snapshot$quality_qualified,FALSE))
    brohn_write_json_file(observations,file.path(root,"status-lock-observations.json"))
  }
  cat(sprintf("Acquisition completion: %d checks passed; evidence retained at %s.\n",checks,root))
})

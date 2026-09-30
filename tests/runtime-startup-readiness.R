# Real owned processes and fresh workspaces; no foreign service or user store changes.
args<-commandArgs(TRUE);stopifnot(length(args)==2L)
repo<-normalizePath(args[[1]],winslash="/",mustWork=TRUE);out<-args[[2]]
stopifnot(!file.exists(out));dir.create(out,recursive=TRUE);out<-normalizePath(out,winslash="/",mustWork=TRUE)
setwd(repo);source("R/platform-load.R",encoding="UTF-8");brohn_load(ui=FALSE)
local({
  checks<-list();processes<-list();states<-list();passed<-FALSE;failure<-NULL
  check<-function(ok,label){if(!isTRUE(ok))stop(label,call.=FALSE);checks[[length(checks)+1L]]<<-label;cat("PASS",label,"\n")}
  old_port<-Sys.getenv("BROHN_PARTICIPANT_PORT",unset=NA_character_)
  on.exit({
    for(s in states)try(brohn_stop_services(s),silent=TRUE)
    for(p in processes)try({if(p$is_alive())p$kill_tree();p$wait(5000)},silent=TRUE)
    if(is.na(old_port))Sys.unsetenv("BROHN_PARTICIPANT_PORT")else Sys.setenv(BROHN_PARTICIPANT_PORT=old_port)
    brohn_write_json_file(list(passed=passed,checks=checks,count=length(checks),failure=failure,
      source_sha256=digest::digest(file="R/platform-runtime.R",algo="sha256"),scope="Bounded real-process readiness and fresh owned native service boot; no recordings, scientific jobs or pre-existing service changes"),file.path(out,"results.json"))
  },add=TRUE)
  tryCatch({
    script<-file.path(out,"owned-child.R")
    writeLines(c('a<-commandArgs(TRUE)','if(a[[1]]=="dead"){cat("Intentional startup failure\\n",file=stderr());quit(status=23)}',
      'if(a[[1]]=="delayed"){Sys.sleep(4);writeLines("ready",a[[2]])}','Sys.sleep(60)'),script)
    new_child<-function(mode,label){
      ready<-file.path(out,paste0(label,"-ready"));logs<-list(stdout=file.path(out,paste0(label,".stdout")),stderr=file.path(out,paste0(label,".stderr")))
      p<-processx::process$new(brohn_rscript(),c("--vanilla",script,mode,ready),stdout=logs$stdout,stderr=logs$stderr,
        env=c("current",R_LIBS_USER=paste(.libPaths(),collapse=.Platform$path.sep)),cleanup_tree=TRUE,windows_hide_window=TRUE)
      processes[[length(processes)+1L]]<<-p
      state<-new.env(parent=emptyenv());state$owned<-list(acquisition=p);state$logs<-list(acquisition=logs)
      state$root<-out;state$session_id<-label;state$events<-list();dir.create(file.path(out,"logs"),showWarnings=FALSE)
      list(state=state,child=p,ready=ready)
    }
    delayed<-new_child("delayed","delayed");began<-proc.time()[["elapsed"]]
    .brohn_runtime_wait_ready(delayed$state,"acquisition",function()list(ready=file.exists(delayed$ready),status="waiting_for_owned_marker",error=NULL))
    elapsed<-proc.time()[["elapsed"]]-began
    check(elapsed>=4&&elapsed<15&&delayed$child$is_alive(),"Owned readiness arriving after old three-second window succeeds within fixed deadline")
    check(identical(delayed$state$events[[1]]$event,"startup_ready"),"Delayed readiness records elapsed time and owned identity")
    delayed$child$kill_tree();delayed$child$wait(5000)
    dead<-new_child("dead","dead");began<-proc.time()[["elapsed"]]
    error<-tryCatch({.brohn_runtime_wait_ready(dead$state,"acquisition",function()list(ready=FALSE,status="missing",error="No acquisition state was published."));NULL},error=identity)
    check(inherits(error,"error")&&proc.time()[["elapsed"]]-began<5,"Dead child fails promptly without waiting the full startup deadline")
    check(grepl("Exit code: 23",conditionMessage(error),fixed=TRUE)&&grepl("No acquisition state was published.",conditionMessage(error),fixed=TRUE)&&grepl(dead$state$logs$acquisition$stderr,conditionMessage(error),fixed=TRUE),"Dead child diagnostic includes exit code, exact readiness reason and owned log")
    hung<-new_child("waiting","timeout");began<-proc.time()[["elapsed"]]
    error<-tryCatch({.brohn_runtime_wait_ready(hung$state,"acquisition",function()list(ready=FALSE,status="foreign_workspace",error="Different workspace identity."),timeout_s=.4);NULL},error=identity)
    check(inherits(error,"error")&&proc.time()[["elapsed"]]-began<1&&hung$child$is_alive(),"Live child with wrong workspace readiness reaches a bounded deadline without accepting it")
    check(grepl("foreign_workspace",conditionMessage(error),fixed=TRUE),"Deadline failure retains actual readiness status")
    error<-tryCatch({.brohn_runtime_wait_ready(hung$state,"acquisition",function(){Sys.sleep(.2);list(ready=TRUE,status="ready",error=NULL)},timeout_s=.1);NULL},error=identity)
    check(inherits(error,"error")&&grepl("startup deadline",conditionMessage(error),fixed=TRUE),"A readiness response arriving after the elapsed deadline cannot be accepted")
    hung$child$kill_tree();hung$child$wait(5000)
    race<-new_child("waiting","probe-death-race");probes<-0L
    error<-tryCatch({.brohn_runtime_wait_ready(race$state,"acquisition",function(){probes<<-probes+1L
      if(probes==1L){race$child$kill_tree();race$child$wait(5000);return(list(ready=TRUE,status="ready",error=NULL))}
      list(ready=FALSE,status="owner_absent",error="The just-probed owner exited.")});NULL},error=identity)
    check(inherits(error,"error")&&probes==2L&&!is.null(race$state$owned$acquisition),"Child death after a ready probe requires a new probe and retains failed ownership")
    external<-new_child("waiting","verified-replacement");raced<-new_child("waiting","replaced-child");probes<-0L
    .brohn_runtime_wait_ready(raced$state,"acquisition",function(){probes<<-probes+1L
      if(probes==1L){raced$child$kill_tree();raced$child$wait(5000)}
      list(ready=TRUE,status="ready",error=NULL,value=list(process=list(pid=external$child$get_pid())))})
    check(probes==2L&&is.null(raced$state$owned$acquisition)&&external$child$is_alive(),"Fresh verified external replacement is never adopted or killed")
    external$child$kill_tree();external$child$wait(5000)
    root<-file.path(out,"fresh-workspace");port<-httpuv::randomPort(min=19000L,max=49000L)
    began<-proc.time()[["elapsed"]];state<-brohn_start_services(root,port);states[[length(states)+1L]]<-state
    check(setequal(names(state$owned),c("participant","acquisition","worker")),"Genuine fresh native boot owns all three services without prestarting a manager")
    check(brohn_participant_ready(state$workspace_id,port)&&brohn_acquisition_ready(root,state$workspace_id),"Both genuine services verify the exact fresh workspace")
    check(!brohn_participant_ready("other-workspace",port)&&!brohn_acquisition_ready(root,"other-workspace"),"Readiness rejects other workspace identities")
    check(state$owned$worker$is_alive()&&state$started$worker>=state$started$acquisition,"Worker starts only after acquisition readiness")
    ready<-Filter(function(e)identical(e$event,"startup_ready"),state$events)
    check(length(ready)==2L&&all(vapply(ready,function(e)e$elapsed_s<=15,logical(1))),"Genuine owned readiness events retain bounded elapsed timings")
    brohn_write_json_file(list(participant_port=port,workspace_id=state$workspace_id,boot_elapsed_s=proc.time()[["elapsed"]]-began,
      events=state$events,owned_pids=lapply(state$owned,function(p)p$get_pid())),file.path(out,"fresh-boot.json"))
    reused<-brohn_start_services(root,port);states[[length(states)+1L]]<-reused
    check(identical(names(reused$owned),"worker"),"Compatible existing participant and acquisition manager are reused without adoption")
    brohn_stop_services(reused);for(p in reused$owned)p$wait(5000)
    check(state$owned$participant$is_alive()&&state$owned$acquisition$is_alive()&&brohn_participant_ready(state$workspace_id,port),"Stopping a reusing runtime preserves both external service processes")
    collision<-tryCatch({brohn_start_services(file.path(out,"foreign-workspace"),port);NULL},error=identity)
    check(inherits(collision,"error")&&grepl("exited before readiness",conditionMessage(collision),fixed=TRUE),"Different-workspace port collision produces a dead-child startup diagnostic")
    check(state$owned$participant$is_alive()&&state$owned$acquisition$is_alive()&&brohn_participant_ready(state$workspace_id,port),"Port collision leaves existing workspace services alive")
    brohn_stop_services(state);for(p in state$owned)p$wait(5000)
    check(all(vapply(state$owned,function(p)!p$is_alive(),logical(1)))&&!brohn_participant_ready(state$workspace_id,port),"Normal shutdown leaves no owned process or participant listener")
    store<-brohn_open_store(root);jobs<-brohn_list_jobs(store,limit=100L);brohn_close_store(store)
    check(!length(jobs),"Fresh boot and shutdown create no scientific or other jobs")
    captured<-NULL;start_fault<-brohn_start_services;real_wait<-.brohn_runtime_wait_ready
    fault_wait<-function(s,name,probe,timeout_s=15){captured<<-s
      if(name=="acquisition"){s$owned[[name]]$kill_tree();s$owned[[name]]$wait(5000)}
      real_wait(s,name,probe,timeout_s)}
    environment(start_fault)<-list2env(list(.brohn_runtime_wait_ready=fault_wait),parent=environment(brohn_start_services))
    failed<-tryCatch({start_fault(file.path(out,"failed-start-workspace"),httpuv::randomPort(min=19000L,max=49000L));NULL},error=identity)
    check(inherits(failed,"error")&&grepl("exited before readiness",conditionMessage(failed),fixed=TRUE),"Deliberately killed owned acquisition child aborts real startup")
    check(isTRUE(captured$stopped)&&all(vapply(captured$owned,function(p)!p$is_alive(),logical(1))),"Failed startup waits for every owned process to exit without orphans")
    check(is.null(captured$owned$worker)&&!brohn_participant_ready(captured$workspace_id,captured$participant_port),"Failed acquisition startup never starts a worker and releases participant listener")
    brohn_write_json_file(list(error=conditionMessage(failed),events=captured$events,owned_pids=lapply(captured$owned,function(p)p$get_pid()),
      alive=lapply(captured$owned,function(p)p$is_alive()),fault="Test kills only the acquisition child just created by this fresh startup"),file.path(out,"failed-start.json"))
    captured<-NULL;start_worker_fault<-brohn_start_services;launches<-0L;actual_rscript<-brohn_rscript
    capture_wait<-function(s,name,probe,timeout_s=15){captured<<-s;real_wait(s,name,probe,timeout_s)}
    worker_failure<-function(){launches<<-launches+1L;if(launches==3L)stop("Injected worker launcher failure");actual_rscript()}
    environment(start_worker_fault)<-list2env(list(.brohn_runtime_wait_ready=capture_wait,brohn_rscript=worker_failure),parent=environment(brohn_start_services))
    failed<-tryCatch({start_worker_fault(file.path(out,"worker-failure-workspace"),httpuv::randomPort(min=19000L,max=49000L));NULL},error=identity)
    check(inherits(failed,"error")&&grepl("Injected worker launcher failure",conditionMessage(failed),fixed=TRUE),"Worker launch failure is exercised after both actual service readiness checks")
    check(launches==3L&&all(vapply(captured$owned,function(p)!p$is_alive(),logical(1))),"Worker launch failure leaves no owned processes")
    final_state<-brohn_acquisition_service_status(captured$root)
    check(identical(final_state$status,"stopped")&&identical(captured$owned$acquisition$get_exit_status(),0L),"Worker launch failure gracefully stops the exact owned acquisition manager before fallback")
    controls<-list.files(file.path(captured$root,"acquisitions"),pattern="^stop-manager-.*\\.json$")
    check(length(controls)==1L,"Failed startup leaves the exact manager stop control as cleanup evidence")
    brohn_write_json_file(list(error=conditionMessage(failed),events=captured$events,acquisition_status=final_state$status,
      acquisition_exit_code=captured$owned$acquisition$get_exit_status(),owned_pids=lapply(captured$owned,function(p)p$get_pid()),stop_controls=as.list(controls)),file.path(out,"worker-failure.json"))
    passed<-TRUE
  },error=function(e){failure<<-conditionMessage(e);stop(e)})
  cat(length(checks),"runtime startup checks passed\n")
})

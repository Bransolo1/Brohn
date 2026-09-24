source("R/platform-core.R",encoding="UTF-8");source("R/platform-sciat-window.R",encoding="UTF-8");source("R/platform-sciat-window-delivery.R",encoding="UTF-8")
local({
  folder<-commandArgs(trailingOnly=TRUE)[[1]];compiled<-brohn_parse(paste(readLines(file.path(folder,"compiled.json"),warn=FALSE),collapse="\n"))
  cases<-brohn_parse(paste(readLines(file.path(folder,"state-cases.json"),warn=FALSE),collapse="\n"));checks<-character()
  check<-function(n,x){stopifnot(isTRUE(x));checks<<-c(checks,n);cat("PASS",n,"\n")}
  clock<-function(x)list(id="browser-monotonic",unit="ms",value=format(x,scientific=FALSE,trim=TRUE,digits=17),instance_id="state-probe",time_origin_ms="1000000")
  event<-function(kind,data)list(type="task_event",clock=data$clock,payload=list(kind=kind,data=data))
  instruction<-function(c,s,at)event("task_instructions",list(task_id=c$id,step_id=s$id,block_id=s$block_id,procedure_hash=c$procedure_hash,clock=clock(at)))
  pair<-function(c,t,r,held) {
    start<-event("task_trial_started",list(task_id=c$id,trial_id=t$id,block_id=t$block_id,procedure_hash=c$procedure_hash,clock=clock(r$onset_ms),held_codes=held,
      timing_reference="requestAnimationFrame_before_paint",viewport=list(width=1280,height=900,device_pixel_ratio=1),stimulus_rect=list(x=100,y=100,width=400,height=100)))
    at<-max(unlist(r[c("onset_ms","response_closed_ms","feedback_start_ms","feedback_end_ms","blank_end_ms")]),
      vapply(r$keys,function(k)k$observed_ms,numeric(1)),r$onset_ms)+10
    end<-event("task_trial_finished",c(list(task_id=c$id,trial_id=t$id,block_id=t$block_id,procedure_hash=c$procedure_hash,clock=clock(at),frame_count=20,max_frame_gap_ms=16),r))
    list(start,end)
  }
  c<-compiled$A;t<-c$timeline[[2L]]
  for(case in cases$cases) {
    events<-c(list(instruction(c,c$timeline[[1L]],case$result$onset_ms-1)),pair(c,t,case$result,case$held))
    out<-brohn_sciat_window_replay(c,events)
    check(paste("Independent R replay accepts exact JS state evidence",case$name),!out$complete&&length(out$state$responses)==1L&&
      identical(out$state$responses[[1L]]$correct,case$result$correct))
  }
  for(name in names(cases$full)) {
    c<-compiled[[name]];events<-list();i<-1L;last<-1000
    for(t in c$timeline)if(t$type=="task_instructions")events<-c(events,list(instruction(c,t,last)))else{
      row<-cases$full[[name]][[i]];pair_events<-pair(c,t,row$result,row$held);events<-c(events,pair_events)
      last<-as.numeric(pair_events[[2L]]$clock$value);i<-i+1L
    }
    out<-brohn_sciat_window_replay(c,events)
    check(paste("Independent R replays all192 JavaScript-state trials",name),out$complete&&length(out$state$responses)==192L)
  }
  writeLines(brohn_json(list(passed=TRUE,checks=as.list(checks),complete_browser_or_session_qualification=FALSE),TRUE),file.path(folder,"independent-state-replay.json"),useBytes=TRUE)
})

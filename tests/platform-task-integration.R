source("R/platform-participant-equipment.R") # Registered optional new-draft policy.
# Receiver consistency checks using original deterministic evidence, independent
# of browser-generated latencies. This is software validation, not rig timing.
.libPaths(c(normalizePath("../../work/r-library-brohn",winslash="/",mustWork=FALSE),.libPaths()))
for(module in c("platform-core","platform-methods","platform-store","platform-delivery","platform-task-delivery"))source(paste0("R/",module,".R"))
local({
  n<-0L
  check<-function(name,ok){if(!isTRUE(ok))stop("FAIL: ",name);n<<-n+1L}
  rejects<-function(expr)inherits(try(force(expr),silent=TRUE),"try-error")
  design<-brohn_new_design("Synthetic receiver procedure","blank",id="task-receiver")
  design$participant_equipment<-NULL # Historical absent-policy receiver evidence.
  design$instructions<-"";design$blocks<-list(brohn_task_new("rt-deary-liewald-simple/1.0",id="simple-receiver"))
  protocol<-brohn_compile(design);main<-protocol$timeline[[1]];task<-main$task
  clock<-function(time,instance="page-clock")list(id="browser-monotonic",unit="ms",value=sprintf("%.6f",time),instance_id=instance,time_origin_ms="1700000000000.000")
  events<-list()
  append<-function(type,payload,time){e<-list(sequence=length(events)+1L,id=paste0("event-",length(events)+1L),type=type,
    step_id=main$id,stimulus_id=NULL,condition_id=NULL,question_id=NULL,phase=main$phase,clock=clock(time,"page-clock"),payload=payload);events[[length(events)+1L]]<<-e;invisible(e)}
  nested<-function(kind,data)append("task_event",list(kind=kind,data=data),as.numeric(data$clock$value)+5)
  append("step_started",list(resumed=FALSE),0)
  previous<-NULL;time<-10
  for(step in task$timeline){
    if(step$type=="task_instructions"){
      nested("task_instructions",list(task_id=task$id,step_id=step$id,block_id=step$block_id,clock=clock(time)))
      time<-time+20
    }else{
      onset<-max(time,if(is.null(previous))0 else previous+step$intertrial_ms)+step$foreperiod_ms
      nested("task_trial_started",list(task_id=task$id,trial_id=step$id,block_id=step$block_id,clock=clock(onset),
        observed_foreperiod_ms=step$foreperiod_ms,scheduled_foreperiod_ms=step$foreperiod_ms,
        observed_gap_since_previous_response_ms=if(is.null(previous))NULL else onset-previous,
        timing_reference="requestAnimationFrame_before_paint",viewport=list(width=1200,height=800,device_pixel_ratio=1),stimulus_rect=list(x=100,y=100,width=90,height=90)))
      key<-list(code=step$correct_code,clock=clock(onset+400),rt_ms=400,accepted=TRUE,phase="response",correct=TRUE,ignored_reason=NULL)
      nested("task_trial_finished",list(task_id=task$id,trial_id=step$id,block_id=step$block_id,outcome="correct",clock=clock(onset+405),
        response_code=step$correct_code,final_code=step$correct_code,first_correct=TRUE,first_response_ms=400,final_correct_ms=400,
        clock_instance_id="page-clock",onset_ms=onset,foreperiod_start_ms=onset-step$foreperiod_ms,observed_foreperiod_ms=step$foreperiod_ms,
        anticipatory_count=0L,keypresses=list(key),frame_count=24L,max_frame_gap_ms=17))
      previous<-onset+400;time<-onset+420
    }
  }
  before_finish<-events
  append("step_finished",list(task_outcome="completed",elapsed_ms=time),time+5)
  append("run_finished",list(outcome="completed"),time+10)
  state<-.brohn_delivery_replay(protocol,events)
  check("full original 28-trial nested procedure permits completion",state$run_finished&&state$ending_outcome=="completed"&&length(state$completed)==1L)
  finish<-events[[length(events)-1L]];finish$clock<-clock(30,"page-clock")
  check("cannot finish task after instructions alone",rejects(.brohn_delivery_replay(protocol,c(events[1:2],list(finish)))))
  check("cannot omit a trial",rejects(.brohn_delivery_replay(protocol,events[-3])))
  check("cannot omit block instructions",rejects(.brohn_delivery_replay(protocol,events[-2])))
  mutate<-function(name,fn){bad<-events;bad[[4]]$payload$data<-fn(bad[[4]]$payload$data);check(name,rejects(.brohn_delivery_replay(protocol,bad)))}
  mutate("summary cannot substitute an unobserved key",function(d){d$response_code<-"KeyI";d})
  mutate("summary cannot invent first RT",function(d){d$first_response_ms<-399;d})
  mutate("summary cannot invent final RT",function(d){d$final_correct_ms<-401;d})
  mutate("completion cannot change retained onset",function(d){d$onset_ms<-d$onset_ms+10;d})
  mutate("keypress must use the correct task clock",function(d){d$keypresses[[1]]$clock$instance_id<-"another-page";d})
  mutate("keypress RT must equal onset difference",function(d){d$keypresses[[1]]$rt_ms<-300;d})
  mutate("correctness must follow the frozen key map",function(d){d$keypresses[[1]]$correct<-FALSE;d})
  mutate("typed acceptance flags reject strings",function(d){d$keypresses[[1]]$accepted<-"true";d})
  mutate("unsupported score payload is rejected",function(d){d$score<-100;d})
  mutate("correct outcome cannot be reclassified as timeout",function(d){d$outcome<-"timeout";d})
  mutate("anticipatory counts must match retained keys",function(d){d$anticipatory_count<-1L;d})
  mutate("trial cannot include another key after correct completion",function(d){d$keypresses<-c(d$keypresses,d$keypresses);d})
  mutate("keypress from an earlier task boundary cannot become anticipation",function(d){key<-d$keypresses[[1]];key$clock<-clock(d$foreperiod_start_ms-10);key$accepted<-FALSE;key$phase<-"foreperiod";key$rt_ms<-NULL;key$ignored_reason<-"anticipatory";d$keypresses<-c(list(key),d$keypresses);d$anticipatory_count<-1L;d})
  bad<-events;bad[[2]]$payload$data$clock$instance_id<-"forged-first-task-clock"
  check("first nested clock must equal enclosing page identity",rejects(.brohn_delivery_replay(protocol,bad)))
  bad<-events;bad[[3]]$payload$data$scheduled_foreperiod_ms<-0
  check("foreperiod cannot replace frozen setting",rejects(.brohn_delivery_replay(protocol,bad)))
  bad<-events;bad[[3]]$payload$data$trial_id<-task$timeline[[3]]$id
  check("trial cursor rejects a foreign/future identity",rejects(.brohn_delivery_replay(protocol,bad)))
  bad<-events;bad[[4]]$clock$instance_id<-"reloaded-page"
  check("task cannot cross outer clock instances",rejects(.brohn_delivery_replay(protocol,bad)))
  bad<-events;bad[[4]]$stimulus_id<-"invented-stimulus"
  check("nested task cannot claim an unrelated main-study stimulus",rejects(.brohn_delivery_replay(protocol,bad)))
  # An interrupted foreperiod has no received onset, no scored key and cannot
  # unlock completion. Partial software evidence remains replayable.
  partial<-events[1:2];d<-events[[4]]$payload$data;d$outcome<-"interrupted";d$clock<-clock(100)
  d[c("response_code","final_code","first_response_ms","final_correct_ms","onset_ms","foreperiod_start_ms","observed_foreperiod_ms")]<-rep(list(NULL),7)
  d$foreperiod_start_ms<-30
  d$first_correct<-FALSE;d$keypresses<-list();d$frame_count<-0L;d$max_frame_gap_ms<-0
  e<-events[[4]];e$clock<-clock(105,"page-clock");e$payload$data<-d
  partial<-c(partial,list(e));s<-.brohn_delivery_replay(protocol,partial)
  check("partial interrupted foreperiod is retained without fabricated onset",isTRUE(s$active$task$incomplete))
  check("interrupted foreperiod cannot become completed task",rejects(.brohn_delivery_replay(protocol,c(partial,list(finish)))))
  bad<-partial;bad[[3]]$payload$data$foreperiod_start_ms<-0
  check("interrupted foreperiod cannot begin before the current instruction boundary",rejects(.brohn_delivery_replay(protocol,bad)))
  interruption<-events[[2]];interruption$clock<-clock(25,"page-clock");interruption$payload<-list(kind="task_interrupted",data=list(task_id=task$id,step_id=task$timeline[[1]]$id,reason="participant_stopped",clock=clock(20)))
  check("stopping at block instructions remains replayable",isTRUE(.brohn_delivery_replay(protocol,c(events[1:2],list(interruption)))$active$task$interrupted))
  interruption$payload$data["step_id"]<-list(NULL)
  check("stopping before first task instructions remains replayable",isTRUE(.brohn_delivery_replay(protocol,c(events[1],list(interruption)))$active$task$interrupted))
  cat(sprintf("platform-task-integration: %d checks passed\n",n))
})

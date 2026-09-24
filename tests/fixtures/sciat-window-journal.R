# Independent original numerical event fixture, not a person or browser clock.
original_sciat_window_journal <- function(compiled) {
  events<-list();time<-1000;trial_n<-0L
  clock<-function(t)list(id="browser-monotonic",unit="ms",value=format(t,scientific=FALSE,trim=TRUE,digits=17),
    instance_id="original-sciat-probe-page",time_origin_ms="1000000")
  emit<-function(kind,data,at){events[[length(events)+1L]]<<-list(type="task_event",clock=clock(at),payload=list(kind=kind,data=data));time<<-at}
  for(step in compiled$timeline) {
    common<-list(task_id=compiled$id,procedure_hash=compiled$procedure_hash,block_id=step$block_id)
    if(step$type=="task_instructions") {
      emit("task_instructions",c(common,list(step_id=step$id,clock=clock(time+1))),time+1);next
    }
    trial_n<-trial_n+1L;start<-time+16
    emit("task_trial_started",c(common,list(trial_id=step$id,clock=clock(start),held_codes=list(),
      timing_reference="requestAnimationFrame_before_paint",viewport=list(width=1280,height=900,device_pixel_ratio=1),
      stimulus_rect=list(x=400,y=300,width=400,height=100))),start)
    omission<-trial_n==3L;wrong<-trial_n %in% c(1L,29L);rt<-if(trial_n==2L)1500 else 400+(trial_n%%11L)*17
    code<-if(wrong)setdiff(c("KeyE","KeyI"),step$correct_code)else step$correct_code
    key<-function(type,at,accepted,reason,code_value=code,observed=at) {
      x<-list(type=type,code=code_value,event_ms=at,observed_ms=observed,trusted=TRUE,modifiers=FALSE,response_open=TRUE,accepted=accepted,ignored_reason=reason)
      x[["repeat"]]<-FALSE;x
    }
    keys<-if(omission)list()else list(key("down",start+rt,TRUE,NULL),key("up",start+rt+2,FALSE,"key_release"))
    if(wrong)keys<-c(keys,list(key("down",start+rt+5,FALSE,"after_first_response",step$correct_code),key("up",start+rt+7,FALSE,"key_release",step$correct_code)))
    close<-start+if(omission)1516 else rt+8
    feedback<-close+16;end<-feedback+if(omission)500 else 150;blank<-end+250
    emit("task_trial_finished",c(common,list(trial_id=step$id,clock=clock(blank),outcome=if(omission)"omission"else"response",
      response_outcome=if(omission)"omission"else"response",response_code=if(omission)NULL else code,response_ms=if(omission)NULL else rt,
      correct=if(omission)NULL else !wrong,onset_ms=start,deadline_ms=start+1500,response_closed_ms=close,
      feedback_start_ms=feedback,feedback_end_ms=end,blank_end_ms=blank,keys=keys,interruption_reason=NULL,frame_count=20L,max_frame_gap_ms=16)),blank)
  }
  events
}

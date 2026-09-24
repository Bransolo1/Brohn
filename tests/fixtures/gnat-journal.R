# Original authored receipt fixture. No browser/session qualification is implied.
original_gnat_journal <- function(compiled) {
  now<-100;events<-list();cell_counts<-list()
  emit<-function(kind,data,time) {
    clock<-list(id="browser-monotonic",unit="ms",value=format(time,scientific=FALSE,trim=TRUE,digits=17),instance_id="original-gnat-page",time_origin_ms="1000000")
    d<-c(list(task_id=compiled$id,procedure_hash=compiled$procedure_hash,clock=clock),data)
    events[[length(events)+1L]]<<-list(type="task_event",clock=clock,payload=list(kind=kind,data=d))
  }
  for(t in compiled$timeline) {
    now<-now+50
    if(t$type=="task_instructions") {emit("task_instructions",list(step_id=t$id,block_id=t$block_id),now);next}
    onset<-now;deadline<-onset+t$timeout_ms
    emit("task_trial_started",list(trial_id=t$id,block_id=t$block_id,held_codes=list(),timing_reference="requestAnimationFrame_before_paint",
      viewport=list(width=1280,height=800,device_pixel_ratio=1),stimulus_rect=list(x=480,y=350,width=320,height=80),visible=TRUE,focused=TRUE,
      release_wait=list(start_ms=onset-25,end_ms=onset,held_codes=list(),keys=list(),
        visibility=list(list(observed_ms=onset-25,visible=TRUE,focused=TRUE),list(observed_ms=onset,visible=TRUE,focused=TRUE)))),onset)
    respond<-t$expected_action=="go"
    if(t$phase=="test") {
      key<-paste(t$cell_id,t$expected_action);n<-brohn_default(cell_counts[[key]],0L)+1L;cell_counts[[key]]<-n
      quota<-switch(t$cell_id,"r1-positive"=c(27,6),"r1-negative"=c(21,9),"r2-positive"=c(24,3),"r2-negative"=c(15,15))
      respond<-n<=quota[if(t$expected_action=="go")1L else 2L]
    }
    outcome<-if(t$expected_action=="go")if(respond)"hit"else"miss"else if(respond)"false_alarm"else"correct_rejection"
    closed<-if(respond)onset+250 else deadline+11;blank<-closed+500;keys<-list()
    if(respond)keys<-list(
      list(type="down",code="Space",event_ms=onset+250,observed_ms=onset+250,`repeat`=FALSE,trusted=TRUE,modifiers=FALSE,response_open=TRUE,accepted=TRUE,ignored_reason=NULL),
      list(type="up",code="Space",event_ms=onset+270,observed_ms=onset+270,`repeat`=FALSE,trusted=TRUE,modifiers=FALSE,response_open=FALSE,accepted=FALSE,ignored_reason="key_release"))
    emit("task_trial_finished",list(trial_id=t$id,block_id=t$block_id,outcome=outcome,response_outcome=outcome,
      response_code=if(respond)"Space"else NULL,response_ms=if(respond)250 else NULL,correct=outcome %in% c("hit","correct_rejection"),
      onset_ms=onset,deadline_ms=deadline,deadline_timer_ms=if(respond)NULL else deadline+3,deadline_frame_ms=if(respond)NULL else deadline+11,
      response_closed_ms=closed,feedback_start_ms=closed,feedback_end_ms=closed+100,blank_end_ms=blank,keys=keys,
      visibility=list(list(observed_ms=onset,visible=TRUE,focused=TRUE),list(observed_ms=blank,visible=TRUE,focused=TRUE)),
      interruption_reason=NULL,frame_count=40L,max_frame_gap_ms=17),blank)
    now<-blank
  }
  events
}

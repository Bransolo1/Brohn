# Dedicated first-response replay inside Brohn's existing task_event envelope.
.brohn_sciat_window_require <- function(ok,message) {
  if(exists(".brohn_delivery_require",mode="function")) .brohn_delivery_require(ok,message,422L,"invalid_sciat_evidence") else brohn_require(ok,message)
}
.brohn_sciat_window_clock <- function(clock,instance=NULL,origin=NULL) {
  brohn_fields(clock,c("id","unit","value","instance_id","time_origin_ms"),label="SC-IAT clock")
  .brohn_sciat_window_require(identical(clock$id,"browser-monotonic")&&identical(clock$unit,"ms")&&
    brohn_text(clock$value,64)&&grepl("^[0-9]+([.][0-9]+)?$",clock$value)&&
    brohn_text(clock$time_origin_ms,64)&&grepl("^[0-9]+([.][0-9]+)?$",clock$time_origin_ms)&&
    brohn_text(clock$instance_id,128)&&brohn_number(as.numeric(clock$value),0,1e12),"SC-IAT requires a decimal browser clock, page instance and origin.")
  .brohn_sciat_window_require((is.null(instance)||identical(instance,clock$instance_id))&&
    (is.null(origin)||identical(origin,clock$time_origin_ms)),"A timed SC-IAT task cannot cross a page-clock restart.")
  as.numeric(clock$value)
}
.brohn_sciat_window_same <- function(a,b) if(is.null(a)||is.null(b))is.null(a)&&is.null(b)else
  is.numeric(a)&&is.numeric(b)&&length(a)==1L&&length(b)==1L&&is.finite(a)&&is.finite(b)&&abs(a-b)<=.002
.brohn_sciat_window_bool <- function(x)is.logical(x)&&length(x)==1L&&!is.na(x)
.brohn_sciat_window_delivery_new <- function()list(cursor=1L,active=NULL,last_clock=NULL,clock_instance=NULL,clock_origin=NULL,
  boundary_time=NULL,last_trial_id=NULL,last_instruction_id=NULL,interrupted=FALSE,incomplete=FALSE,completed=list(),responses=list())

.brohn_sciat_window_trial_replay <- function(data,onset,trial,observed) {
  require<-.brohn_sciat_window_require;same<-.brohn_sciat_window_same;bool<-.brohn_sciat_window_bool
  brohn_fields(data,c("task_id","trial_id","block_id","procedure_hash","clock","outcome","response_outcome","response_code","response_ms","correct",
    "onset_ms","deadline_ms","response_closed_ms","feedback_start_ms","feedback_end_ms","blank_end_ms","keys","interruption_reason",
    "frame_count","max_frame_gap_ms"),label="SC-IAT trial result")
  require(same(data$onset_ms,onset$time)&&same(data$deadline_ms,onset$time+1500)&&
    brohn_text(data$outcome,40)&&data$outcome %in% c("response","omission","interrupted")&&
    brohn_array(data$keys)&&length(data$keys)<=5000&&brohn_number(data$frame_count,1,1e8,TRUE)&&brohn_number(data$max_frame_gap_ms,0,3600000),
    "SC-IAT trial outcome, onset or observations are invalid.")
  held<-unlist(onset$held,use.names=FALSE);first<-NULL;last_event<-NULL;last_observed<-onset$time;late_conflict<-FALSE
  closed<-data$response_closed_ms
  require(is.null(closed)||brohn_number(closed,onset$time,observed+.002),"Invalid response-window closure.")
  for(k in data$keys) {
    brohn_fields(k,c("type","code","event_ms","observed_ms","repeat","trusted","modifiers","response_open","accepted","ignored_reason"),label="SC-IAT key observation")
    require(k$type %in% c("down","up")&&length(k$type)==1L&&k$code %in% c("KeyE","KeyI")&&length(k$code)==1L&&
      brohn_number(k$event_ms,0,observed+.002)&&brohn_number(k$observed_ms,last_observed,observed+.002)&&k$event_ms<=k$observed_ms+.002&&
      bool(k[["repeat"]])&&bool(k$trusted)&&bool(k$modifiers)&&bool(k$response_open)&&bool(k$accepted),"SC-IAT key type, clock or literal flags are invalid.")
    require(if(k$response_open)is.null(closed)||k$observed_ms<=closed+.002 else !is.null(closed)&&k$observed_ms>=closed-.002,
      "Key response-phase observation contradicts the retained response-window closure.")
    reversed<-!is.null(last_event)&&k$event_ms<last_event
    last_event<-k$event_ms;last_observed<-k$observed_ms
    reason<-if(!k$trusted)"synthetic_key_event"else if(k$modifiers)"modified_key"else if(reversed)"event_clock_reversed"else
      if(k$type=="up")"key_release"else if(k[["repeat"]])"key_repeat"else if(k$code %in% held)"key_held_from_previous_phase"else
        if(k$event_ms<onset$time)"anticipatory"else if(k$event_ms>onset$time+1500)"after_deadline"else
          if(!is.null(first))"after_first_response"else if(!k$response_open)"eligible_key_after_seal"else NULL
    require(identical(k$ignored_reason,reason)&&identical(k$accepted,is.null(reason)),"SC-IAT accepted key or ignored reason differs from independent replay.")
    if(k$trusted){if(k$type=="up")held<-setdiff(held,k$code)else held<-union(held,k$code)}
    if(is.null(reason))first<-k
    if(identical(reason,"eligible_key_after_seal")||identical(reason,"event_clock_reversed"))late_conflict<-TRUE
  }
  expected_outcome<-if(!is.null(first))"response"else if(!is.null(closed))"omission"else NULL
  require(identical(data$response_outcome,expected_outcome)&&identical(data$response_code,if(is.null(first))NULL else first$code)&&
    same(data$response_ms,if(is.null(first))NULL else first$event_ms-onset$time)&&
    identical(data$correct,if(is.null(first))NULL else first$code==trial$correct_code),"SC-IAT first-response summary differs from retained physical-key observations.")
  if(!is.null(closed))require(closed>=if(is.null(first))onset$time+1500 else first$observed_ms,
    "A response window cannot close before the first observed response or omission deadline.")
  feedback<-data$feedback_start_ms;end<-data$feedback_end_ms;blank<-data$blank_end_ms
  if(!is.null(feedback))require(!is.null(closed)&&brohn_number(feedback,closed,observed+.002),"Feedback cannot begin before response-window closure.")
  if(!is.null(end))require(!is.null(feedback)&&brohn_number(end,feedback+if(expected_outcome=="response")150 else 500,observed+.002),
    "Feedback was shorter than the frozen response/omission duration.")
  if(!is.null(blank))require(!is.null(end)&&brohn_number(blank,end+250,observed+.002),"The post-feedback blank is incomplete.")
  if(data$outcome=="interrupted")require(brohn_text(data$interruption_reason,500),"An interrupted trial needs its observed reason.") else {
    require(!late_conflict&&identical(data$outcome,expected_outcome)&&is.null(data$interruption_reason)&&!is.null(blank),
      "Complete SC-IAT trial evidence needs the actual response/omission, feedback and blank, without an unresolved clock conflict.")
  }
  list(trial_id=trial$id,mapping=trial$mapping,phase=trial$phase,scored=trial$scored,outcome=data$outcome,
    response_outcome=data$response_outcome,latency_ms=data$response_ms,correct=data$correct)
}

.brohn_sciat_window_delivery_apply <- function(state,event,step) {
  require<-.brohn_sciat_window_require;compiled<-step$task;t<-state$active$task
  require(!is.null(t)&&!t$interrupted&&identical(compiled$profile,brohn_sciat_window_profile()$id),"SC-IAT is absent or already interrupted.")
  brohn_fields(event$payload,c("kind","data"),c("clock_segment_id","time_origin_ms"),"SC-IAT task envelope")
  d<-event$payload$data;kind<-event$payload$kind
  require(brohn_text(kind,64)&&kind %in% c("task_instructions","task_trial_started","task_trial_finished","task_interrupted"),"Unsupported SC-IAT event.")
  require(is.list(d)&&identical(d$task_id,compiled$id)&&identical(d$procedure_hash,compiled$procedure_hash),"SC-IAT event belongs to another frozen procedure.")
  outer<-.brohn_sciat_window_clock(event$clock,state$active$instance)
  now<-.brohn_sciat_window_clock(d$clock,state$active$instance,event$clock$time_origin_ms)
  require(now>=state$active$time&&now<=outer+.002&&(is.null(t$last_clock)||now>=t$last_clock)&&
    (is.null(t$clock_origin)||identical(t$clock_origin,d$clock$time_origin_ms)),"SC-IAT clock reversed or left its current step.")
  t$clock_instance<-d$clock$instance_id;t$clock_origin<-d$clock$time_origin_ms;t$last_clock<-now
  expected<-if(t$cursor<=length(compiled$timeline))compiled$timeline[[t$cursor]]else NULL
  if(kind=="task_interrupted") {
    brohn_fields(d,c("task_id","step_id","procedure_hash","reason","clock"),label="SC-IAT interruption")
    choices<-c(expected$id,t$last_trial_id,t$last_instruction_id)
    require(brohn_text(d$reason,500)&&((is.null(d$step_id)&&t$cursor==1L)||(!is.null(d$step_id)&&d$step_id %in% choices)),"SC-IAT interruption must name its actual boundary.")
    t$interrupted<-TRUE;state$active$task<-t;return(state)
  }
  require(!t$incomplete&&!is.null(expected),"The SC-IAT sequence is incomplete or already finished.")
  if(kind=="task_instructions") {
    brohn_fields(d,c("task_id","step_id","block_id","procedure_hash","clock"),label="SC-IAT instructions")
    require(is.null(t$active)&&expected$type=="task_instructions"&&identical(d$step_id,expected$id)&&identical(d$block_id,expected$block_id),"SC-IAT instructions are out of order.")
    t$last_instruction_id<-expected$id;t$boundary_time<-now;t$cursor<-t$cursor+1L;state$active$task<-t;return(state)
  }
  require(expected$type=="task_trial"&&identical(d$trial_id,expected$id)&&identical(d$block_id,expected$block_id),"SC-IAT trial identity or order differs from the frozen sequence.")
  if(kind=="task_trial_started") {
    brohn_fields(d,c("task_id","trial_id","block_id","procedure_hash","clock","held_codes","timing_reference","viewport","stimulus_rect"),label="SC-IAT onset")
    require(is.null(t$active)&&now>=brohn_default(t$boundary_time,state$active$time)&&identical(d$timing_reference,"requestAnimationFrame_before_paint")&&
      brohn_array(d$held_codes)&&length(d$held_codes)<=2L&&!anyDuplicated(unlist(d$held_codes))&&all(unlist(d$held_codes) %in% c("KeyE","KeyI")),"SC-IAT onset/held-key snapshot is invalid.")
    brohn_fields(d$viewport,c("width","height","device_pixel_ratio"),label="SC-IAT viewport")
    brohn_fields(d$stimulus_rect,c("x","y","width","height"),label="SC-IAT stimulus rectangle")
    require(brohn_number(d$viewport$width,1,100000)&&brohn_number(d$viewport$height,1,100000)&&brohn_number(d$viewport$device_pixel_ratio,.1,20)&&
      brohn_number(d$stimulus_rect$x,-100000,100000)&&brohn_number(d$stimulus_rect$y,-100000,100000)&&
      brohn_number(d$stimulus_rect$width,.001,100000)&&brohn_number(d$stimulus_rect$height,.001,100000),"SC-IAT onset geometry is invalid.")
    t$active<-list(id=expected$id,time=now,held=d$held_codes);state$active$task<-t;return(state)
  }
  require(!is.null(t$active),"SC-IAT completion needs its previously received onset.")
  record<-.brohn_sciat_window_trial_replay(d,t$active,expected,now)
  t$responses[[length(t$responses)+1L]]<-record;t$completed[[length(t$completed)+1L]]<-expected$id
  t$last_trial_id<-expected$id;t$active<-NULL;t$cursor<-t$cursor+1L;t$boundary_time<-now
  t$incomplete<-identical(d$outcome,"interrupted");state$active$task<-t;state
}

.brohn_sciat_window_delivery_complete <- function(state,step,event) {
  t<-state$active$task
  .brohn_sciat_window_require(!is.null(t)&&!t$interrupted&&!t$incomplete&&is.null(t$active)&&
    t$cursor>length(step$task$timeline)&&length(t$responses)==192L&&identical(state$active$instance,event$clock$instance_id),
    "All 192 assigned SC-IAT trials, feedback and blank phases must be received before task completion.")
  invisible(TRUE)
}

brohn_sciat_window_replay <- function(compiled,events) {
  brohn_sciat_window_validate_compiled(compiled)
  brohn_require(brohn_array(events)&&length(events)>0L&&length(events)<=400L,"Supply bounded received SC-IAT task events.")
  first<-events[[1L]]
  # The actual outer step_started is checked by delivery. The pure task-only
  # probe starts at its first nested observation, before callback dispatch.
  start<-.brohn_sciat_window_clock(first$payload$data$clock,first$clock$instance_id,first$clock$time_origin_ms)
  state<-list(active=list(time=start,instance=first$clock$instance_id,task=.brohn_sciat_window_delivery_new()))
  for(e in events) {
    brohn_require(identical(e$type,"task_event"),"The pure replay accepts nested task events only; outer consent/session checks remain in delivery.")
    state<-.brohn_sciat_window_delivery_apply(state,e,list(task=compiled))
  }
  completed<-isTRUE(tryCatch({.brohn_sciat_window_delivery_complete(state,list(task=compiled),events[[length(events)]]);TRUE},error=function(e)FALSE))
  list(complete=completed,outer_session_qualified=FALSE,state=state$active$task,procedure_hash=compiled$procedure_hash,sequence_hash=compiled$sequence_hash)
}

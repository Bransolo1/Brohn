# Strict replay of task evidence inside the existing immutable delivery journal.
# This checks internal software consistency; client clocks are not physical rig
# qualification and the service never accepts a submitted score as an authority.
.brohn_task_delivery_require <- function(ok, message) .brohn_delivery_require(ok, message, 422L, "invalid_task_evidence")
.brohn_task_delivery_equal <- function(a,b,tolerance=.002) is.numeric(a) && length(a)==1L && is.finite(a) &&
  is.numeric(b) && length(b)==1L && is.finite(b) && abs(a-b)<=tolerance
.brohn_task_delivery_bool <- function(value) is.logical(value) && length(value)==1L && !is.na(value)
.brohn_task_delivery_clock <- function(clock, instance=NULL, origin=NULL) {
  brohn_fields(clock,c("id","unit","value","instance_id","time_origin_ms"),label="Task clock")
  .brohn_task_delivery_require(identical(clock$id,"browser-monotonic") && identical(clock$unit,"ms") &&
    brohn_text(clock$value,64) && grepl("^[0-9]+([.][0-9]+)?$",clock$value) &&
    brohn_text(clock$instance_id,128) && brohn_text(clock$time_origin_ms,64) &&
    grepl("^[0-9]+([.][0-9]+)?$",clock$time_origin_ms),"Task clock must retain its decimal milliseconds, page instance and origin.")
  time<-suppressWarnings(as.numeric(clock$value))
  .brohn_task_delivery_require(is.finite(time)&&time<=1e12,"Task clock is outside the supported range.")
  if(!is.null(instance)).brohn_task_delivery_require(identical(instance,clock$instance_id),"A task cannot continue across clock instances.")
  if(!is.null(origin)).brohn_task_delivery_require(identical(origin,clock$time_origin_ms),"Task clock origin changed.")
  time
}
.brohn_task_delivery_new <- function() list(cursor=1L,active=NULL,last_trial_id=NULL,last_instruction_id=NULL,last_clock=NULL,boundary_time=NULL,
  clock_instance=NULL,clock_origin=NULL,previous_response=NULL,previous_intertrial=NULL,interrupted=FALSE,completed=list())

.brohn_task_delivery_apply <- function(state,event,step) {
  brohn_fields(event$payload,c("kind","data"),c("clock_segment_id","time_origin_ms"),"Task event envelope")
  kind<-event$payload$kind;data<-event$payload$data;compiled<-step$task
  .brohn_task_delivery_require(brohn_text(kind,64)&&kind %in% c("task_instructions","task_trial_started","task_trial_finished","task_interrupted"),"Unsupported nested task event.")
  .brohn_task_delivery_require(is.list(data)&&!is.null(names(data)),"Task event needs a structured payload.")
  t<-state$active$task
  .brohn_task_delivery_require(!is.null(t)&&!t$interrupted,"The task is unavailable or already interrupted.")
  .brohn_task_delivery_require(identical(state$active$instance,event$clock$instance_id),"A task cannot continue after a page restart.")
  .brohn_task_delivery_require(identical(data$task_id,compiled$id),"Task event belongs to another task.")
  .brohn_task_delivery_require(identical(data$clock$instance_id,event$clock$instance_id),"Nested task evidence must use the enclosing page's clock identity.")
  observed<-.brohn_task_delivery_clock(data$clock,t$clock_instance,t$clock_origin)
  .brohn_task_delivery_require(observed>=state$active$time-.002 && observed<=as.numeric(event$clock$value)+.002 &&
    identical(data$clock$time_origin_ms,event$clock$time_origin_ms),"Task observation lies outside its enclosing browser clock segment.")
  .brohn_task_delivery_require(is.null(t$last_clock)||observed>=t$last_clock,"Task event clock reversed.")
  t$clock_instance<-data$clock$instance_id;t$clock_origin<-data$clock$time_origin_ms;t$last_clock<-observed
  expected<-if(t$cursor<=length(compiled$timeline))compiled$timeline[[t$cursor]]else NULL
  if(kind=="task_interrupted") {
    brohn_fields(data,c("task_id","step_id","reason","clock"),label="Task interruption")
    choices<-c(if(!is.null(expected))expected$id,if(is.null(t$active))c(t$last_trial_id,t$last_instruction_id))
    before_first<-is.null(data$step_id)&&t$cursor==1L&&is.null(t$active)&&is.null(t$last_trial_id)
    .brohn_task_delivery_require(brohn_text(data$reason,500)&&(before_first||(!is.null(data$step_id)&&data$step_id %in% choices)),"Task interruption needs its actual current boundary and reason.")
    t$interrupted<-TRUE;state$active$task<-t;return(state)
  }
  .brohn_task_delivery_require(!isTRUE(t$incomplete),"An incomplete timed trial must end the task as interrupted.")
  .brohn_task_delivery_require(!is.null(expected),"The task procedure is already complete.")
  if(kind=="task_instructions") {
    brohn_fields(data,c("task_id","step_id","block_id","clock"),label="Task instruction event")
    .brohn_task_delivery_require(is.null(t$active)&&expected$type=="task_instructions"&&identical(data$step_id,expected$id)&&identical(data$block_id,expected$block_id),"Task block instructions are missing, duplicated or out of order.")
    t$last_instruction_id<-expected$id;t$boundary_time<-observed
    t$cursor<-t$cursor+1L;state$active$task<-t;return(state)
  }
  .brohn_task_delivery_require(expected$type=="task_trial"&&identical(data$trial_id,expected$id)&&identical(data$block_id,expected$block_id),"Trial identity or order differs from the frozen task.")
  if(kind=="task_trial_started") {
    brohn_fields(data,c("task_id","trial_id","block_id","clock","observed_foreperiod_ms","scheduled_foreperiod_ms",
      "observed_gap_since_previous_response_ms","timing_reference","viewport","stimulus_rect"),label="Trial onset")
    .brohn_task_delivery_require(is.null(t$active),"Trial onset was already received.")
    .brohn_task_delivery_require(.brohn_task_delivery_equal(data$scheduled_foreperiod_ms,expected$foreperiod_ms)&&
      brohn_number(data$observed_foreperiod_ms,expected$foreperiod_ms-1,3600000)&&
      observed-data$observed_foreperiod_ms>=max(state$active$time,brohn_default(t$boundary_time,state$active$time))-.002&&
      identical(data$timing_reference,"requestAnimationFrame_before_paint"),"Trial foreperiod or onset reference differs from the procedure.")
    brohn_fields(data$viewport,c("width","height","device_pixel_ratio"),label="Task viewport")
    brohn_fields(data$stimulus_rect,c("x","y","width","height"),label="Task stimulus rectangle")
    .brohn_task_delivery_require(brohn_number(data$viewport$width,1,100000)&&brohn_number(data$viewport$height,1,100000)&&
      brohn_number(data$viewport$device_pixel_ratio,.1,20)&&all(vapply(data$stimulus_rect,is.numeric,logical(1)))&&
      brohn_number(data$stimulus_rect$x,-100000,100000)&&brohn_number(data$stimulus_rect$y,-100000,100000)&&
      brohn_number(data$stimulus_rect$width,.001,100000)&&brohn_number(data$stimulus_rect$height,.001,100000),"Task viewport or stimulus rectangle is invalid.")
    if(is.null(t$previous_response)).brohn_task_delivery_require(is.null(data$observed_gap_since_previous_response_ms),"The first trial cannot claim an earlier response.") else {
      .brohn_task_delivery_require(.brohn_task_delivery_equal(data$observed_gap_since_previous_response_ms,observed-t$previous_response)&&
        observed-t$previous_response>=t$previous_intertrial+expected$foreperiod_ms-2,"The observed interval since the previous response is inconsistent or too short.")
    }
    t$active<-list(id=expected$id,onset=observed,foreperiod=data$observed_foreperiod_ms);t$last_instruction_id<-NULL
    state$active$task<-t;return(state)
  }
  brohn_fields(data,c("task_id","trial_id","block_id","outcome","clock","response_code","final_code","first_correct",
    "first_response_ms","final_correct_ms","clock_instance_id","onset_ms","foreperiod_start_ms","observed_foreperiod_ms",
    "anticipatory_count","keypresses","frame_count","max_frame_gap_ms"),c("zoom_feedback_observed_ms"),"Trial completion")
  .brohn_task_delivery_require(brohn_text(data$outcome,30)&&data$outcome %in% c("correct","incorrect","timeout","interrupted")&&
    identical(data$clock_instance_id,t$clock_instance)&&.brohn_task_delivery_bool(data$first_correct)&&
    brohn_array(data$keypresses)&&length(data$keypresses)<=2000&&brohn_number(data$frame_count,0,1e8,TRUE)&&
    brohn_number(data$max_frame_gap_ms,0,3600000),"Trial outcome, key list or frame observations are invalid.")
  has_onset<-!is.null(t$active)
  if(has_onset) {
    .brohn_task_delivery_require(data$frame_count>=1&&.brohn_task_delivery_equal(data$onset_ms,t$active$onset)&&
      .brohn_task_delivery_equal(data$observed_foreperiod_ms,t$active$foreperiod)&&
      .brohn_task_delivery_equal(data$foreperiod_start_ms,data$onset_ms-data$observed_foreperiod_ms)&&observed>=data$onset_ms,
      "Trial completion changed the retained onset or foreperiod.")
  } else .brohn_task_delivery_require(data$outcome=="interrupted"&&is.null(data$onset_ms)&&is.null(data$observed_foreperiod_ms),"A trial without a received onset must remain interrupted.")
  .brohn_task_delivery_require(brohn_number(data$foreperiod_start_ms,0,1e12)&&
    data$foreperiod_start_ms>=max(state$active$time,brohn_default(t$boundary_time,state$active$time))-.002&&
    data$foreperiod_start_ms<=observed+.002,"The trial foreperiod must begin within its current task boundary.")
  accepted<-list();anticipatory<-0L;last_key<-NULL
  for(key in data$keypresses) {
    brohn_fields(key,c("code","clock","rt_ms","accepted","phase","correct","ignored_reason"),label="Task key observation")
    kt<-.brohn_task_delivery_clock(key$clock,t$clock_instance,t$clock_origin)
    .brohn_task_delivery_require(brohn_text(key$code,40)&&key$code %in% unlist(expected$allowed_codes)&&
      .brohn_task_delivery_bool(key$accepted)&&.brohn_task_delivery_bool(key$correct)&&
      identical(key$correct,identical(key$code,expected$correct_code))&&brohn_text(key$phase,30)&&
      key$phase %in% c("foreperiod","response")&&kt>=data$foreperiod_start_ms-.002&&kt<=observed+.002&&
      (is.null(last_key)||kt>=last_key),"Key identity, correctness, phase or order is inconsistent.")
    last_key<-kt
    if(key$phase=="foreperiod") {
      anticipatory<-anticipatory+1L
      .brohn_task_delivery_require(!key$accepted&&is.null(key$rt_ms)&&identical(key$ignored_reason,"anticipatory")&&
        (!has_onset||kt<data$onset_ms+.002),"An anticipatory key cannot become a scored response.")
    } else {
      .brohn_task_delivery_require(has_onset&&kt>=data$onset_ms-.002&&.brohn_task_delivery_equal(key$rt_ms,kt-data$onset_ms),"Key latency does not match its retained onset clock.")
      if(key$accepted) {
        .brohn_task_delivery_require(is.null(key$ignored_reason)&&key$rt_ms<=expected$timeout_ms+.002,"An ignored or late key cannot be accepted.")
        if(length(accepted)) .brohn_task_delivery_require(expected$forced_correction&&!accepted[[length(accepted)]]$correct,"A trial cannot accept another key after its terminal response.")
        accepted[[length(accepted)+1L]]<-key
      } else .brohn_task_delivery_require(brohn_text(key$ignored_reason,80)&&key$ignored_reason %in% c("key_repeat","key_held_from_previous_phase","synthetic_key_event","after_timeout")&&
        (key$ignored_reason!="after_timeout"||key$rt_ms>expected$timeout_ms),"Ignored response key needs a consistent reason.")
    }
  }
  .brohn_task_delivery_require(brohn_number(data$anticipatory_count,0,2000,TRUE)&&data$anticipatory_count==anticipatory,"Anticipatory-key count differs from the journal.")
  first<-if(length(accepted))accepted[[1]]else NULL
  final<-if(length(accepted)&&accepted[[length(accepted)]]$correct)accepted[[length(accepted)]]else NULL
  same_time<-function(a,b)if(is.null(a)||is.null(b))is.null(a)&&is.null(b)else .brohn_task_delivery_equal(a,b)
  .brohn_task_delivery_require(identical(data$response_code,if(is.null(first))NULL else first$code)&&
    identical(data$final_code,if(is.null(final))NULL else final$code)&&identical(data$first_correct,if(is.null(first))FALSE else first$correct)&&
    same_time(data$first_response_ms,if(is.null(first))NULL else first$rt_ms)&&same_time(data$final_correct_ms,if(is.null(final))NULL else final$rt_ms),"First/final response summary differs from retained key observations.")
  if(data$outcome=="correct").brohn_task_delivery_require(!is.null(final),"A correct trial requires a final correct key.")
  if(data$outcome=="incorrect").brohn_task_delivery_require(!expected$forced_correction&&!is.null(first)&&!first$correct&&length(accepted)==1L,"An incorrect completion is inconsistent with forced correction or first response.")
  if(data$outcome=="timeout").brohn_task_delivery_require(has_onset&&observed-data$onset_ms>=expected$timeout_ms-1&&is.null(final)&&
    (expected$forced_correction||!length(accepted)),"Timeout lacks the required observed duration or contains a terminal response.")
  if(!is.null(data$zoom_feedback_observed_ms)).brohn_task_delivery_require(expected$mode=="aat"&&brohn_number(data$zoom_feedback_observed_ms,0,3600000),"Zoom feedback is invalid for this task.")
  if(expected$mode=="aat"&&data$outcome=="correct").brohn_task_delivery_require(brohn_number(data$zoom_feedback_observed_ms,expected$zoom_duration_ms-2,3600000),"The approach/avoidance feedback observation is incomplete.")
  t$last_trial_id<-expected$id;t$completed<-c(t$completed,list(expected$id));t$active<-NULL;t$cursor<-t$cursor+1L;t$boundary_time<-observed
  t$previous_response<-if(!is.null(final))as.numeric(final$clock$value)else if(!is.null(first))as.numeric(first$clock$value)else observed
  t$previous_intertrial<-expected$intertrial_ms
  if(data$outcome=="interrupted"||(expected$forced_correction&&data$outcome!="correct"))t$incomplete<-TRUE
  state$active$task<-t;state
}
.brohn_task_delivery_complete <- function(state,step,event) {
  t<-state$active$task
  .brohn_task_delivery_require(!is.null(t)&&!isTRUE(t$interrupted)&&!isTRUE(t$incomplete)&&is.null(t$active)&&
    t$cursor>length(step$task$timeline)&&identical(state$active$instance,event$clock$instance_id),"Complete the entire assigned task before finishing its study step.")
  invisible(TRUE)
}

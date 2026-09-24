# Original full-profile journals with synthetic clock observations. These exercise
# the receiver without claiming a browser, person, or physical timing experiment.
original_task_journal <- function(protocol, outcome_for = function(trial) list(outcome="correct", rt=500)) {
  events <- list(); state <- .brohn_delivery_initial_state(); time <- 0
  clock <- function(t) list(id="browser-monotonic", unit="ms", value=format(t, scientific=FALSE, trim=TRUE, digits=17),
    instance_id="original-task-export-page", time_origin_ms="0")
  send <- function(type, step=NULL, payload=structure(list(), names=character()), at=time) {
    event <- list(sequence=length(events)+1L, id=paste0("original-event-",length(events)+1L), type=type,
      step_id=if(is.null(step))NULL else step$id, stimulus_id=if(is.null(step))NULL else step$stimulus_id,
      condition_id=if(is.null(step))NULL else step$condition_id,
      question_id=if(!is.null(step)&&step$type=="question")step$question$id else NULL,
      phase=if(type=="equipment_event")"equipment_setup"else if(is.null(step))"completion"else step$phase, clock=clock(at), payload=payload)
    state <<- .brohn_delivery_apply(state,event,protocol)
    events[[length(events)+1L]] <<- event; time <<- at
  }
  # Synthetic protocol evidence, not an observation of a physical keyboard.
  # Current designs must exercise the production gate; old absent policies keep
  # their original behavior. Camera receipts need a separate real capture fixture.
  equipment <- if (exists("brohn_equipment_requirements", mode="function")) brohn_equipment_requirements(protocol) else NULL
  if (!is.null(equipment)) {
    stopifnot(!isTRUE(equipment$camera))
    emit_equipment <- function(kind, evidence) send("equipment_event", payload=list(
      schema="brohn-participant-equipment-check/1.0", policy_hash=equipment$policy_hash,
      kind=kind, attempt_id=paste0("original-equipment-",kind), evidence=evidence), at=time)
    if (length(equipment$required_codes)) emit_equipment("keyboard", list(codes=equipment$required_codes,
      released=TRUE,focused=TRUE,visible=TRUE,last_input_ms=time))
    if (isTRUE(equipment$controls)) emit_equipment("controls", list(activation="keyboard_or_assistive",trusted=TRUE,last_input_ms=time))
  }
  for (step in protocol$timeline) {
    send("step_started",step,at=time+1)
    if(step$type=="task") for(trial in step$task$timeline) {
      send_task <- function(kind,data,at=time)send("task_event",step,list(kind=kind,data=data),at)
      if(trial$type=="task_instructions") {
        send_task("task_instructions",list(task_id=step$task$id,step_id=trial$id,block_id=trial$block_id,clock=clock(time)))
        next
      }
      t <- state$active$task
      boundary <- max(brohn_default(t$boundary_time,state$active$time),if(is.null(t$previous_response))0 else t$previous_response+t$previous_intertrial)
      onset <- boundary+trial$foreperiod_ms
      send_task("task_trial_started",list(task_id=step$task$id,trial_id=trial$id,block_id=trial$block_id,clock=clock(onset),
        observed_foreperiod_ms=trial$foreperiod_ms,scheduled_foreperiod_ms=trial$foreperiod_ms,
        observed_gap_since_previous_response_ms=if(is.null(t$previous_response))NULL else onset-t$previous_response,
        timing_reference="requestAnimationFrame_before_paint",viewport=list(width=800,height=600,device_pixel_ratio=1),
        stimulus_rect=list(x=100,y=100,width=50,height=50)),onset)
      outcome <- outcome_for(trial); correct <- outcome$outcome=="correct"; answered <- outcome$outcome!="timeout"
      first_correct <- answered && !identical(outcome$first_correct,FALSE) && correct
      rt <- if(answered)outcome$rt else NULL
      first_code <- if(!answered)NULL else if(first_correct)trial$correct_code else setdiff(unlist(trial$allowed_codes),trial$correct_code)[[1]]
      final_rt <- if(!correct)NULL else brohn_default(outcome$final_rt,rt)
      keys <- list()
      if(answered)keys <- list(list(code=first_code,clock=clock(onset+rt),rt_ms=rt,accepted=TRUE,phase="response",correct=first_correct,ignored_reason=NULL))
      if(correct&&!first_correct)keys[[2L]] <- list(code=trial$correct_code,clock=clock(onset+final_rt),rt_ms=final_rt,accepted=TRUE,phase="response",correct=TRUE,ignored_reason=NULL)
      feedback <- if(trial$mode=="aat"&&correct)trial$zoom_duration_ms else 0
      finished <- onset+if(!answered)trial$timeout_ms else if(correct)final_rt+feedback else rt
      payload <- list(task_id=step$task$id,trial_id=trial$id,block_id=trial$block_id,outcome=outcome$outcome,clock=clock(finished),
        response_code=first_code,final_code=if(correct)trial$correct_code else NULL,first_correct=first_correct,
        first_response_ms=rt,final_correct_ms=final_rt,clock_instance_id="original-task-export-page",onset_ms=onset,
        foreperiod_start_ms=boundary,observed_foreperiod_ms=trial$foreperiod_ms,anticipatory_count=0L,keypresses=keys,frame_count=1L,max_frame_gap_ms=16)
      if(trial$mode=="aat")payload$zoom_feedback_observed_ms <- feedback
      send_task("task_trial_finished",payload,finished)
    } else if(step$type=="question") {
      send("response",step,list(value=0,response_time_ms=1,scope=step$question$scope),time+1)
    } else if(step$type %in% c("stimulus","fixation","baseline")) time <- time+step$duration_ms
    send("step_finished",step,at=time+1)
  }
  send("run_finished",payload=list(outcome="completed"),at=time+1)
  events
}

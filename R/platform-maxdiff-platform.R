# Explicit choices use one resumable protocol step per frozen offered set.
brohn_maxdiff_clone <- function(exercise) {
  brohn_maxdiff_validate(exercise)
  result <- exercise; result$id <- brohn_id("maxdiff")
  map <- stats::setNames(vapply(result$items,function(i) brohn_id("md-item"),character(1)),brohn_ids(result$items))
  result$items <- lapply(result$items,function(i) {i$id<-unname(map[[i$id]]);i})
  result$sets <- lapply(result$sets,function(s) {s$id<-brohn_id("md-set");s$item_ids<-as.list(unname(map[unlist(s$item_ids)]));s})
  brohn_maxdiff_validate(result); result
}
brohn_maxdiff_steps <- function(exercise, allocation_index) {
  compiled <- brohn_maxdiff_compile(exercise, allocation_index)
  lapply(compiled$trials,function(trial) list(type="maxdiff",phase="explicit_choice",choice=list(
    exercise_id=exercise$id,design_hash=compiled$design_hash,set_id=trial$set_id,trial_id=trial$id,position=trial$position,
    item_order=trial$item_order,items=lapply(trial$item_order,function(id) brohn_find(exercise$items,id)),
    prompt=exercise$settings$prompt,best_label=exercise$settings$best_label,worst_label=exercise$settings$worst_label,required=exercise$settings$required)))
}
.brohn_maxdiff_delivery_answer <- function(step, event, state) {
  p <- event$payload; choice <- step$choice
  brohn_fields(p,c("value","response_time_ms","active_segment_response_ms","resumed"),c("clock_segment_id","time_origin_ms"),"Best-worst response")
  .brohn_delivery_require(is.logical(p$resumed) && length(p$resumed)==1L && !is.na(p$resumed) && identical(p$resumed,isTRUE(state$active$resumed)),
    "Best-worst recovery differs from its recorded onset.",422,"invalid_answer")
  elapsed <- as.numeric(event$clock$value)-state$active$time
  .brohn_delivery_require(identical(event$clock$instance_id,state$active$instance) && brohn_number(p$active_segment_response_ms,0,1e12) &&
    abs(p$active_segment_response_ms-elapsed)<.01 &&
    (if (p$resumed) is.null(p$response_time_ms) else brohn_number(p$response_time_ms,0,1e12) && abs(p$response_time_ms-elapsed)<.01),
    "Best-worst timing must retain its actual browser segment; resumed choices have no uninterrupted response time.",422,"invalid_answer")
  value <- p$value
  if (is.null(value)) {
    .brohn_delivery_require(!choice$required,"Choose both items before continuing.",422,"required_answer")
    return(NULL)
  }
  brohn_fields(value,c("best_id","worst_id"),label="Best-worst choices")
  .brohn_delivery_require(brohn_text(value$best_id,96) && brohn_text(value$worst_id,96) &&
    value$best_id %in% unlist(choice$item_order) && value$worst_id %in% unlist(choice$item_order) && value$best_id!=value$worst_id,
    "Choose two distinct items from the offered set.",422,"invalid_answer")
  value
}
brohn_score_run_maxdiff <- function(input) {
  exercises <- brohn_default(input$design$maxdiff,list())
  if (!length(exercises)) return(list())
  origins <- unique(vapply(input$runs,`[[`,character(1),"origin"))
  brohn_require(length(origins)==1L,"Keep best-worst collection origins in separate reports.")
  # Validate each full journal once, even when a study contains many exercises.
  for (run in input$runs) {
    brohn_require(identical(run$protocol$design_hash,brohn_hash(input$design)),"Best-worst runs must retain the same frozen study design.")
    expected<-unlist(lapply(exercises,brohn_maxdiff_steps,allocation_index=run$protocol$allocation_index),recursive=FALSE)
    actual<-lapply(Filter(function(s)s$type=="maxdiff",run$protocol$timeline),function(s)s[c("type","phase","choice")])
    brohn_require(identical(brohn_hash(actual),brohn_hash(expected)),"The best-worst offered sets or order differ from the frozen allocation.")
    state<-.brohn_delivery_replay(run$protocol,input$events[[run$id]])
    brohn_require(isTRUE(state$run_finished) && identical(state$ending_outcome,"completed"),"Automatic best-worst reports require a complete retained study journal.")
  }
  lapply(exercises,function(exercise) {
    responses <- list(); timing <- list()
    for (run in input$runs) {
      events <- input$events[[run$id]]
      steps <- Filter(function(s) s$type=="maxdiff" && identical(s$choice$exercise_id,exercise$id),run$protocol$timeline)
      for (step in steps) {
        selected <- Filter(function(e) e$type=="response" && identical(e$step_id,step$id),events)
        onsets <- Filter(function(e) e$type=="step_started" && identical(e$step_id,step$id),events)
        finishes <- Filter(function(e) e$type=="step_finished" && identical(e$step_id,step$id),events)
        brohn_require(length(selected)==1L && length(onsets)>=1L && length(finishes)==1L,"A completed best-worst set requires one retained response and completion.")
        event <- selected[[1]]; value <- event$payload$value; choice <- step$choice
        id <- paste0("md-response-",brohn_hash(list(run$id,step$id)))
        responses[[length(responses)+1L]] <- list(id=id,
          participant_id=if(isTRUE(run$participant_alias_supplied)) paste0("alias:",run$participant_alias) else paste0("unlinked:",run$id),
          participant_linkage=isTRUE(run$participant_alias_supplied),session_id=run$id,exposure_id=choice$trial_id,
          design_hash=choice$design_hash,set_id=choice$set_id,item_order=choice$item_order,presented=TRUE,
          status=if(is.null(value)) "missing" else "answered",best_id=value$best_id,worst_id=value$worst_id,
          missing_reason=if(is.null(value)) "explicit_optional_omission" else NULL)
        timing[[length(timing)+1L]] <- list(response_id=id,run_id=run$id,step_id=step$id,sequence=event$sequence,
          response_time_ms=event$payload$response_time_ms,active_segment_response_ms=event$payload$active_segment_response_ms,
          resumed=event$payload$resumed,clock=event$clock,event_hash=brohn_hash(event),onset_hashes=as.list(vapply(onsets,brohn_hash,character(1))))
      }
    }
    result <- brohn_maxdiff_analysis(exercise,responses,source=list(hash=brohn_hash(input$events),origin=origins[[1]]))
    result$collection_evidence <- timing; result$collection_evidence_hash <- brohn_hash(timing)
    result
  })
}
brohn_maxdiff_export_rows <- function(results) {
  unlist(lapply(results,function(result) {
    brohn_require(identical(result$design_hash,brohn_hash(result$design)) && identical(result$responses_hash,brohn_hash(result$exposures)),"Best-worst export evidence changed.")
    lapply(result$exposures,function(r) c(list(exercise_id=result$design$id,exercise_title=result$design$title,
      prompt=result$design$settings$prompt,best_label=result$design$settings$best_label,worst_label=result$design$settings$worst_label,
      source_hash=result$source$hash,origin=result$source$origin),r))
  }),recursive=FALSE)
}

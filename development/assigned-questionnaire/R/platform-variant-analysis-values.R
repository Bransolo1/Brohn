# Inactive private calculation bodies; see EXTRACTIONS.json and BODY-DIFF.patch.
.brohn_vra_revision_values <- function(run, events, context, state, require_sealed = TRUE) {
  if (is.null(context)) return(NULL)
  if (require_sealed) brohn_require(isTRUE(state$run_finished) && identical(state$ending_outcome, "completed") && !state$withdrawn,
    "Completed questionnaire analysis requires the original complete receiver journal.")
  result <- brohn_questionnaire_revision_projection(context, state$questionnaire, require_sealed)
  originals <- setNames(events, vapply(events, `[[`, character(1), "id"))
  result$history_events <- lapply(result$history_records, function(ref) {
    event <- originals[[ref$event_id]]
    brohn_require(!is.null(event) && identical(brohn_hash(event), ref$source_event_hash) && event$sequence == ref$sequence,
      "Questionnaire history differs from its original journal evidence.")
    event
  })
  participant <- if (isTRUE(run$participant_alias_supplied)) paste0("alias:", run$participant_alias) else paste0("unlinked:", run$id)
  result$effective_records <- lapply(result$effective_records, function(r) {
    r$participant_id <- participant; r$session_id <- run$id; r$participant_linkage <- isTRUE(run$participant_alias_supplied)
    r$origin <- run$origin; r$prompt <- context$steps[[r$step_id]]$question$prompt; r
  })
  result$source_projection_hash <- result$projection_hash
  result$projection_hash <- brohn_hash(result$effective_records)
  result$run_id <- run$id; result$events_hash <- brohn_hash(events)
  result
}

.brohn_vra_gnat_values <- function(compiled,responses,completed=TRUE,timing_known=TRUE) {
  brohn_require(brohn_array(responses)&&.brohn_gnat_bool(completed)&&.brohn_gnat_bool(timing_known),
    "GNAT scoring requires explicit response records, completion status and timing-definition status.")
  trials<-Filter(function(t)t$type=="task_trial",compiled$timeline);ids<-brohn_ids(trials)
  received<-vapply(responses,function(r)brohn_default(r$trial_id,""),character(1))
  brohn_require(!anyDuplicated(received)&&all(received %in% ids),"GNAT records contain unknown or duplicate trials.")
  rows<-lapply(seq_along(responses),function(i) {
    r<-responses[[i]];t<-trials[[match(received[i],ids)]]
    brohn_require(all(c("trial_id","outcome","response_outcome","response_code","response_ms","correct") %in% names(r))&&
      brohn_text(r$outcome,40)&&r$outcome %in% c("hit","miss","false_alarm","correct_rejection","interrupted"),"Keep explicit GNAT outcome, key, latency and accuracy cells.")
    responded<-!is.null(r$response_code)
    if(responded) {
      brohn_require(identical(r$response_code,"Space")&&brohn_number(r$response_ms,0,1e12),"GNAT reported responses need Space and a finite nonnegative millisecond value.")
      if(timing_known)brohn_require(r$response_ms<t$timeout_ms,"GNAT responses must be Space strictly before the frozen deadline.")
    }else brohn_require(is.null(r$response_ms),"Withholding cannot contain a fabricated response latency.")
    if(r$outcome=="interrupted") {
      brohn_require(is.null(r$correct)&&(is.null(r$response_outcome)||identical(r$response_outcome,.brohn_gnat_outcome(t$expected_action,responded))),"An interrupted trial retains no qualified accuracy.")
    }else {
      expected<-.brohn_gnat_outcome(t$expected_action,responded)
      brohn_require(identical(r$outcome,expected)&&identical(r$response_outcome,expected)&&identical(r$correct,expected %in% c("hit","correct_rejection")),
        "GNAT outcome or accuracy differs from the frozen expected action and explicit response.")
    }
    c(list(trial_id=t$id,block_id=t$block_id,phase=t$phase,round_id=t$round_id,cell_id=t$cell_id,category_role=t$category_role,expected_action=t$expected_action),
      r[c("outcome","response_outcome","response_code","response_ms","correct")])
  })
  complete<-timing_known&&completed&&setequal(ids,received)&&!any(vapply(rows,function(r)r$outcome=="interrupted",logical(1)))
  result<-list(schema_version="brohn-task-score/1.0",task_id=compiled$id,profile=compiled$profile,origin=compiled$origin,design_hash=compiled$design_hash,
    scoring_recipe="brohn-gnat-single-target-score/1.0",procedure_hash=compiled$procedure_hash,sequence_hash=compiled$sequence_hash,
    status=if(complete)"computed"else"unavailable",eligible=complete,metrics=list(),
    counts=list(expected=384L,received=length(received),expected_training=80L,expected_practice=64L,expected_test=240L,
      training=sum(vapply(rows,function(r)r$phase=="training",logical(1))),practice=sum(vapply(rows,function(r)r$phase=="practice",logical(1))),
      test=sum(vapply(rows,function(r)r$phase=="test",logical(1))),interrupted=sum(vapply(rows,function(r)r$outcome=="interrupted",logical(1)))),
    reason=if(!timing_known)"The declared response-time or terminal-response definition is unknown; GNAT scoring is unavailable."else
      if(complete)NULL else"Complete uninterrupted evidence for all 384 assigned trials is required.",limitations=as.list(c(
      "Named Brohn single-target adaptation; not original or vendor GNAT equivalence.",
      "Context-dependent discrimination contrast, without individual preference bands or diagnoses.",
      "Software arithmetic does not establish physical timing, stimulus validity or population reliability.")))
  cells<-list();rounds<-list();metrics<-list()
  for(round in 1:2)for(sign in c("positive","negative")) {
    id<-paste0("r",round,"-",sign);observed<-Filter(function(r)r$phase=="test"&&identical(r$cell_id,id),rows)
    valid<-Filter(function(r)r$outcome!="interrupted",observed);count<-function(k)sum(vapply(valid,function(r)r$outcome==k,logical(1)))
    rate_fn<-if(timing_known)brohn_gnat_sensitivity else .brohn_gnat_rates
    arithmetic<-rate_fn(count("hit"),count("miss"),count("false_alarm"),count("correct_rejection"))
    cell_complete<-length(valid)==60L&&arithmetic$signal==30L&&arithmetic$noise==30L
    cell<-c(list(id=id,round_id=paste0("r",round),pairing=paste0("target_",sign),deadline_ms=if(round==1L)750L else 600L,
      status=if(cell_complete&&timing_known)"available"else"unavailable",reason=if(!timing_known)"Declared timing definition is unknown; sensitivity and criterion are unavailable."else
        if(cell_complete)NULL else"All 30 signal and 30 noise test trials are required.",
      expected_signal=30L,expected_noise=30L,received_test=length(observed)),arithmetic[c("hits","misses","false_alarms","correct_rejections","raw_rates","corrected_rates","endpoint_adjustments")],
      list(d_prime=if(cell_complete&&timing_known)arithmetic$d_prime else NULL,criterion=if(cell_complete&&timing_known)arithmetic$criterion else NULL,
        response_rt=list(hit=.brohn_gnat_rt(valid,"hit"),false_alarm=.brohn_gnat_rt(valid,"false_alarm")),flags=list()))
    if(!cell_complete)cell$flags<-c(cell$flags,list("incomplete_cell"))
    if(!timing_known)cell$flags<-c(cell$flags,list("declared_timing_unknown"))
    if(any(unlist(arithmetic$endpoint_adjustments)))cell$flags<-c(cell$flags,list("endpoint_rate_correction"))
    if(cell_complete&&timing_known&&arithmetic$d_prime<=0)cell$flags<-c(cell$flags,list("little_or_reversed_discrimination"))
    if(length(valid)&&count("hit")+count("false_alarm")==length(valid))cell$flags<-c(cell$flags,list("all_go"))
    if(length(valid)&&count("miss")+count("correct_rejection")==length(valid))cell$flags<-c(cell$flags,list("all_no_go"))
    cells[[length(cells)+1L]]<-cell
    for(metric in c("d_prime","criterion"))metrics[[length(metrics)+1L]]<-list(name=paste0("GNAT_r",round,"_",sign,"_",metric),
      value=if(complete)cell[[metric]]else NULL,unit="dimensionless",direction=if(metric=="d_prime")"Higher means better signal/noise discrimination in this declared pairing."else"Positive means more conservative Go responding.",
      support=list(cell_id=id,deadline_ms=cell$deadline_ms,signal=arithmetic$signal,noise=arithmetic$noise,eligible=complete))
  }
  for(round in 1:2) {
    p<-cells[[(round-1L)*2L+1L]];n<-cells[[(round-1L)*2L+2L]];available<-p$status=="available"&&n$status=="available"
    contrast<-if(available)p$d_prime-n$d_prime else NULL
    rounds[[round]]<-list(id=paste0("r",round),deadline_ms=p$deadline_ms,pairing_order=compiled$assignment$round_pairing_order[[round]],
      positive_cell=p$id,negative_cell=n$id,contrast=contrast,status=if(available)"available_descriptive"else"unavailable")
    metrics[[length(metrics)+1L]]<-list(name=paste0("GNAT_r",round,"_target_positive_contrast"),value=if(complete)contrast else NULL,unit="dimensionless",
      direction="Target-positive minus target-negative sensitivity within this deadline and context.",support=list(deadline_ms=p$deadline_ms,test_trials=120L,eligible=complete))
  }
  result$metrics<-metrics
  context<-Filter(function(c)c$role=="context",compiled$categories)[[1L]]
  target<-Filter(function(c)c$role=="target",compiled$categories)[[1L]]
  result$scoring_audit<-list(schema="brohn-gnat-single-target-audit/1.0",endpoint_recipe="gnat-brohn-endpoint005/1.0",
    round_order=compiled$assignment$round_pairing_order,training_order=compiled$assignment$training_order,timing_known=timing_known,
    target=list(id=target$id,label=target$label),
    context=list(kind=compiled$provenance$context_kind,rationale=compiled$provenance$context_rationale,label=context$label),
    cells=cells,rounds=rounds,rows=rows)
  result
}

.brohn_vra_sciat_values <- function(compiled, responses, completed = TRUE) {
  brohn_require(brohn_array(responses), "SC-IAT scoring requires response records.")
  trials <- Filter(function(t) identical(t$type, "task_trial"), compiled$timeline)
  ids <- brohn_ids(trials)
  received <- vapply(responses, function(r) brohn_default(r$trial_id, ""), character(1))
  brohn_require(!anyDuplicated(received) && all(received %in% ids), "SC-IAT responses contain duplicate or unknown frozen trials.")
  result <- list(schema_version = "brohn-task-score/1.0", task_id = compiled$id,
    profile = compiled$profile, origin = compiled$origin, design_hash = compiled$design_hash,
    scoring_recipe = "brohn-sciat-response-window-score/1.0", procedure_hash = compiled$procedure_hash,
    sequence_hash = compiled$sequence_hash, status = "unavailable", eligible = FALSE,
    metrics = list(), counts = list(expected = length(ids), received = length(received)), reason = NULL,
    limitations = as.list(c(
      "Named Brohn first-response procedure; not equivalent to a correction-inclusive IAT or an exact original/vendor SC-IAT implementation.",
      "Descriptive task-level contrast; positive values mean faster target-positive responses. No individual preference or diagnostic bands.",
      "Source evidence, material validity, physical timing and population applicability remain separate from scoring arithmetic.")))
  if (!isTRUE(completed) || !setequal(ids, received)) {
    result$reason <- "Complete uninterrupted evidence for all 192 assigned trials is required."
    return(result)
  }
  ordered <- responses[match(ids, received)]
  if (any(vapply(ordered, function(r) identical(r$outcome, "interrupted"), logical(1)))) {
    result$reason <- "The task contains an interrupted trial."
    return(result)
  }
  rows <- lapply(seq_along(trials), function(i) {
    trial <- trials[[i]]; r <- ordered[[i]]
    brohn_require(all(c("trial_id", "outcome", "response_outcome", "response_code", "response_ms", "correct") %in% names(r)),
      "Keep explicit SC-IAT first-response fields, including null omission values.")
    brohn_require(brohn_text(r$outcome, 24) && r$outcome %in% c("response", "omission") && identical(r$response_outcome, r$outcome),
      "SC-IAT requires an actual first response or explicit omission.")
    if (r$outcome == "response") {
      brohn_require(brohn_text(r$response_code, 16) && r$response_code %in% c("KeyE", "KeyI") &&
        brohn_number(r$response_ms, 0, 1500) && is.logical(r$correct) && length(r$correct) == 1L &&
        !is.na(r$correct) && identical(r$correct, identical(r$response_code, trial$correct_code)),
        "SC-IAT first response, accuracy or inclusive 1500 ms window conflicts with the frozen trial.")
    } else brohn_require(is.null(r$response_code) && is.null(r$response_ms) && is.null(r$correct),
      "An omission has no response key, latency or observed accuracy.")
    data.frame(trial_id = trial$id, mapping = trial$mapping, outcome = r$outcome,
      latency_ms = brohn_default(r$response_ms, NA_real_), correct = brohn_default(r$correct, NA),
      stringsAsFactors = FALSE)
  })
  all_rows <- do.call(rbind, rows)
  scored <- vapply(trials, function(t) isTRUE(t$scored), logical(1))
  data <- all_rows[scored, , drop = FALSE]
  brohn_require(nrow(data) == 144L && all(table(factor(data$mapping, levels = c("A", "B"))) == 72L),
    "SC-IAT scoring requires both complete frozen 72-trial test mappings.")
  audit <- brohn_sciat_window_candidate_reduce(data)
  available <- identical(audit$status, "available_arithmetic")
  result$status <- if (available) "computed" else "unavailable"
  result$eligible <- available; result$reason <- audit$reason
  result$counts <- c(result$counts, list(practice = sum(!scored), scored = nrow(data),
    scored_responded = audit$counts$responded, scored_timeouts = audit$counts$omitted,
    removed_fast = audit$counts$removed_fast, retained = audit$counts$retained,
    retained_correct = audit$counts$retained_correct, retained_errors = audit$counts$retained_errors))
  result$metrics <- list(list(name = "SCIAT_target_positive_D", value = audit$target_positive_d, unit = "D",
    direction = "(Target-negative adjusted mean minus target-positive adjusted mean) / pooled original-correct sample SD; positive means faster target-positive responses.",
    support = list(test_trials = 144L, retained_responses = audit$counts$retained,
      pooled_correct_responses = audit$counts$retained_correct,
      sample_sd_divisor = max(0L, audit$counts$retained_correct - 1L))))
  result$scoring_audit <- list(schema = "brohn-sciat-response-window-audit/1.0",
    mapping_order = audit$mapping_order, mapping = audit$mapping, counts = audit$counts,
    minimum_retained_ms = 350L, response_window_ms = 1500L, error_penalty_ms = 400L,
    error_base = "All retained original response latencies in the same mapping, including errors",
    pooled_correct_sample_sd_ms = audit$pooled_correct_sample_sd_ms,
    reference_package_d = audit$reference_package_d, displayed_d = audit$target_positive_d,
    reference_sign = "The displayed target-positive contrast reverses the reference package's A-minus-B sign.",
    reference = brohn_sciat_window_candidate()$reference, qc = audit$qc,
    rows = lapply(seq_len(nrow(audit$rows)), function(i) lapply(as.list(audit$rows[i, , drop = FALSE]), function(value) {
      # Explicit omissions and excluded scoring latencies use NA internally.
      # Retain their named cells as JSON null; unexpected NaN/Inf still fail.
      if (length(value) == 1L && is.na(value) && !is.nan(value)) NULL else value
    })))
  result
}

.brohn_vra_task_values <- function(compiled,responses,completed=TRUE) {
  if (identical(compiled$profile, "gnat-brohn-single-target/1.0")) return(.brohn_vra_gnat_values(compiled,responses,completed))
  if (identical(compiled$profile, "sciat-brohn-response-window-im100/1.0")) return(.brohn_vra_sciat_values(compiled, responses, completed))
  brohn_require(identical(compiled$schema_version,"brohn-compiled-task/1.0") && brohn_array(responses),"Task scorer needs a compiled task and response-record array.")
  definition<-brohn_task_profile(compiled$profile)
  trials<-Filter(function(step)step$type=="task_trial",compiled$timeline)
  expected<-brohn_ids(trials)
  response_ids<-vapply(responses,function(response)brohn_default(response$trial_id,""),character(1))
  brohn_require(!anyDuplicated(response_ids)&&all(response_ids %in% expected),"Responses contain duplicate or unknown frozen trial IDs.")
  result<-list(schema_version="brohn-task-score/1.0",task_id=compiled$id,profile=compiled$profile,origin=compiled$origin,
    design_hash=compiled$design_hash,status="unavailable",eligible=FALSE,metrics=list(),counts=list(expected=length(trials),received=length(responses)),
    reason=NULL,limitations=c("Participant/task-level descriptive scoring; no population inference from trial rows.","Material validity, device timing and population applicability require their own evidence."))
  if(definition$kind %in% c("simple_rt","choice_rt")) {
    # Collection profiles remain frozen. New analyses explicitly identify the
    # corrected support policy; existing /1.0 report objects are never rewritten.
    result$schema_version<-"brohn-task-score/1.1"
    result$scoring_recipe<-"brohn-rt-metric-support/1.0"
    result$support_policy<-list(complete_trial_evidence_required=TRUE,
      aggregate_eligible_definition="At least one metric is supported; use each metric's eligibility for analysis or aggregation.",
      mean_median_minimum_correct=1L,sample_sd_minimum_correct=2L,
      compatibility="Earlier brohn-task-score/1.0 results required two retained correct responses before emitting any RT-task metric. This recipe permits one-response mean/median and independently supported rates; task collection, RT windows and previously published results are unchanged.")
  }
  if(!isTRUE(completed)||!setequal(response_ids,expected)){result$reason<-"Complete uninterrupted task evidence is required";return(result)}
  ordered<-responses[match(expected,response_ids)]
  rows<-lapply(seq_along(trials),function(i) {
    trial<-trials[[i]];response<-ordered[[i]]
    brohn_require(response$outcome %in% c("correct","incorrect","timeout","interrupted"),"Unsupported task response outcome.")
    brohn_require(is.logical(response$first_correct)&&length(response$first_correct)==1&&!is.na(response$first_correct),"Task response needs explicit first-response accuracy.")
    brohn_require(is.null(response$response_code)||response$response_code %in% unlist(trial$allowed_codes),"A recorded response key is not allowed in this trial.")
    brohn_require(identical(response$first_correct,!is.null(response$response_code)&&identical(response$response_code,trial$correct_code)),"First-response accuracy disagrees with the frozen correct key.")
    if(response$outcome=="correct")brohn_require(identical(response$final_code,trial$correct_code)&&!is.null(response$final_correct_ms),"Correct outcome requires the frozen correct key and final latency.")
    for(field in c("first_response_ms","final_correct_ms")) brohn_require(is.null(response[[field]])||brohn_number(response[[field]],0,trial$timeout_ms+2500),paste("Invalid",field))
    brohn_require(identical(is.null(response$response_code),is.null(response$first_response_ms)),"A first response needs both key and latency, or neither.")
    if(!is.null(response$final_correct_ms))brohn_require(!is.null(response$first_response_ms)&&response$final_correct_ms>=response$first_response_ms,"Final-correct latency cannot precede the first response.")
    if(response$first_correct)brohn_require(response$outcome=="correct"&&!is.null(response$first_response_ms)&&!is.null(response$final_correct_ms)&&abs(response$first_response_ms-response$final_correct_ms)<.000001,"A correct first response needs equal first/final latencies.")
    data.frame(trial_id=trial$id,score_block=brohn_default(trial$score_block,""),scored=trial$scored,
      category_id=brohn_default(trial$category_id,""),action=brohn_default(trial$action,""),
      latency_ms=if(definition$kind %in% c("iat","biat"))brohn_default(response$final_correct_ms,NA_real_)else brohn_default(response$first_response_ms,NA_real_),
      first_correct=response$first_correct,responded=!is.null(response$first_response_ms),outcome=response$outcome,stringsAsFactors=FALSE)
  })
  data<-do.call(rbind,rows)
  if(any(data$outcome=="interrupted")){result$reason<-"Task contains an interrupted trial";return(result)}
  result$counts$first_response_errors<-sum(data$responded & !data$first_correct)
  result$counts$timeouts<-sum(data$outcome=="timeout")
  if(definition$kind %in% c("iat","biat")) {
    if(any(data$outcome!="correct")){result$reason<-"Correction-inclusive tasks require a final correct response to every trial";return(result)}
    d<-brohn_iat_d1(data[data$scored,,drop=FALSE],completed=TRUE,biat=definition$kind=="biat")
    result$eligible<-d$eligible;result$status<-if(d$eligible)"computed"else"excluded";result$reason<-d$reason
    result$metrics<-list(list(name=if(definition$kind=="iat")"IAT_D1"else"BIAT_D",value=d$value,unit="D",direction=d$direction))
    result$scoring_audit<-d;return(result)
  }
  scored<-data[data$scored,,drop=FALSE]
  valid<-scored$first_correct & scored$outcome=="correct" & is.finite(scored$latency_ms) &
    scored$latency_ms>=compiled$scoring$rt_min_ms & scored$latency_ms<=compiled$scoring$rt_max_ms
  retained<-scored[valid,,drop=FALSE]
  result$counts$scored<-nrow(scored);result$counts$retained_correct<-nrow(retained)
  result$counts$errors<-sum(scored$responded & !scored$first_correct);result$counts$outside_rt_window<-sum(scored$first_correct & !valid)
  metric<-function(name,value,unit="ms",...)list(name=name,value=if(length(value)&&is.finite(value))unname(value)else NULL,unit=unit,...)
  if(definition$kind=="aat") {
    categories<-vapply(c("target_a","target_b"),function(role)Filter(function(category)category$role==role,compiled$categories)[[1]]$id,character(1))
    cells<-list();bias<-numeric()
    for(category in categories) {
      approach<-retained$latency_ms[retained$category_id==category & retained$action=="approach"]
      avoid<-retained$latency_ms[retained$category_id==category & retained$action=="avoid"]
      if(length(approach)<4||length(avoid)<4){result$reason<-"Each target-by-action cell needs at least four retained correct trials in this keyboard recipe";return(result)}
      difference<-mean(avoid)-mean(approach);bias<-c(bias,difference)
      cells[[length(cells)+1L]]<-list(category_id=category,approach_n=length(approach),avoid_n=length(avoid),approach_mean_ms=mean(approach),avoid_mean_ms=mean(avoid),avoid_minus_approach_ms=difference)
    }
    result$metrics<-list(metric("keyboard_aat_relative_approach_advantage",bias[1]-bias[2],direction="(avoid - approach) target A minus (avoid - approach) target B"))
    result$cells<-cells;result$limitations<-c(result$limitations,"Keyboard cue/zoom response measures key initiation, not joystick movement or execution time. The Brohn counts/windows are a named research recipe, not universal AAT defaults.")
  } else {
    n_correct<-nrow(retained);n_answered<-sum(scored$responded)
    n_errors<-sum(scored$responded & !scored$first_correct);n_test<-nrow(scored)
    n_omitted<-sum(scored$outcome=="timeout")
    result$counts$scored_responded<-n_answered;result$counts$scored_timeouts<-n_omitted
    rt_metric<-function(name,value,minimum,reason,sd=FALSE) {
      eligible<-n_correct>=minimum
      metric(name,if(eligible)value else NULL,eligible=eligible,
        reason=if(eligible)NULL else reason,
        support=list(eligible_count=n_correct,minimum_count=minimum,
          population="retained_correct_test_responses",numerator=NULL,denominator=n_correct,
          denominator_definition="Correct first responses in scored test trials within the frozen RT window; practice trials are excluded.",
          sample_sd_divisor=if(sd)max(0L,n_correct-1L)else NULL,
          rt_min_ms=compiled$scoring$rt_min_ms,rt_max_ms=compiled$scoring$rt_max_ms))
    }
    rate_metric<-function(name,numerator,denominator,population,description,reason) {
      eligible<-denominator>0L
      metric(name,if(eligible)numerator/denominator else NULL,"proportion",
        eligible=eligible,reason=if(eligible)NULL else reason,
        support=list(eligible_count=denominator,minimum_count=1L,population=population,
          numerator=numerator,denominator=denominator,denominator_definition=description))
    }
    result$metrics<-list(
      rt_metric("correct_test_rt_mean",if(n_correct)mean(retained$latency_ms)else NULL,1L,
        "No correct test response falls within the frozen RT window."),
      rt_metric("correct_test_rt_median",if(n_correct)stats::median(retained$latency_ms)else NULL,1L,
        "No correct test response falls within the frozen RT window."),
      rt_metric("correct_test_rt_sd",if(n_correct>=2L)stats::sd(retained$latency_ms)else NULL,2L,
        "At least two retained correct test responses are required for a sample standard deviation.",sd=TRUE),
      rate_metric("test_first_response_error_rate",n_errors,n_answered,"answered_test_trials",
        "Wrong first responses divided by all answered scored test trials, including responses outside the RT window; practice and no-response timeouts are excluded.",
        "No scored test trial has a recorded first response; the error rate is unavailable."),
      rate_metric("test_omission_rate",n_omitted,n_test,"all_scored_test_trials",
        "No-response timeouts divided by all scored test trials in the complete frozen task; practice trials are excluded.",
        "No scored test trial is available for the omission denominator."))
    available<-vapply(result$metrics,function(m)isTRUE(m$eligible),logical(1))
    result$eligible<-any(available)
    result$status<-if(all(available))"computed"else if(any(available))"partial"else"unavailable"
    if(!all(available))result$reason<-"Some metrics have insufficient support. Each available value retains its own trial population and denominator."
    return(result)
  }
  result$eligible<-TRUE;result$status<-"computed";result
}

.brohn_vra_scale_responses <- function(input, admitted) {
  responses<-list();assessments<-list();sources<-list()
  for(run in input$runs) {
    protocol<-run$protocol;events<-input$events[[run$id]]
    .brohn_vra_run_binding(run, input, admitted)
    participant<-if(isTRUE(run$participant_alias_supplied)) paste0("alias:",run$participant_alias) else paste0("unlinked:",run$id)
    if (!is.null(protocol$design$questionnaire_navigation)) {
      projection <- admitted[[run$id]]$projection
      records <- Filter(function(r) !isTRUE(r$information), projection$effective_records)
      responses <- c(responses, records)
      assessments <- c(assessments, lapply(records, function(r) r[c("participant_id", "session_id", "assessment_id", "scope", "stimulus_id", "condition_id", "assessment_exposure_id", "participant_linkage", "origin")]))
      sources[[length(sources)+1L]] <- list(run_id = run$id, design_hash = protocol$design_hash, protocol_hash = projection$protocol_hash,
        events_hash = projection$events_hash, origin = run$origin, answer_projection_hash = projection$projection_hash,
        questionnaire_policy_hash = projection$policy_hash)
      next
    }
    anchor<-NULL
    for(step in protocol$timeline) {
      if(step$type=="stimulus") anchor<-step
      if(step$type!="question") next
      q<-step$question;frozen<-brohn_find(protocol$design$questions,q$id)
      # Option presentation may be randomized in the protocol; compare codes by ID.
      reference<-q;reference$options<-frozen$options
      brohn_require(!is.null(frozen) && identical(brohn_hash(reference),brohn_hash(frozen)) &&
        setequal(vapply(q$options,function(o) brohn_hash(o),character(1)),vapply(frozen$options,function(o) brohn_hash(o),character(1))),"Question step differs from the frozen scale questionnaire.")
      if(q$scope=="after_each") brohn_require(!is.null(anchor) && identical(anchor$stimulus_id,step$stimulus_id) && identical(anchor$condition_id,step$condition_id),
        "An after-stimulus scale item lacks its exact frozen stimulus occurrence.")
      context<-list(participant_id=participant,session_id=run$id,assessment_id=if(q$scope=="after_each") paste0("stimulus-step:",anchor$id) else paste0("scope:",q$scope),
        scope=q$scope,stimulus_id=step$stimulus_id,condition_id=step$condition_id,assessment_exposure_id=if(q$scope=="after_each") anchor$id else NULL,
        participant_linkage=isTRUE(run$participant_alias_supplied),origin=run$origin)
      assessments[[length(assessments)+1L]]<-context
      found<-Filter(function(e) identical(e$type,"response") && identical(e$step_id,step$id),events)
      if(!length(found)) {
        skipped<-any(vapply(events,function(e) identical(e$type,"step_finished") && identical(e$step_id,step$id) && isTRUE(e$payload$skipped),logical(1)))
        responses[[length(responses)+1L]]<-c(context,list(question_id=q$id,step_id=step$id,exposure_id=step$id,value=NULL,missing_reason=if(skipped) "not_displayed" else "item_not_observed"))
      } else for(event in found) responses[[length(responses)+1L]]<-c(context,list(question_id=q$id,step_id=step$id,exposure_id=step$id,
        value=event$payload$value,missing_reason=if(is.null(event$payload$value)) "optional_omission" else NULL,sequence=event$sequence,event_id=event$id))
    }
    sources[[length(sources)+1L]]<-list(run_id=run$id,design_hash=protocol$design_hash,protocol_hash=brohn_hash(protocol),events_hash=brohn_hash(events),origin=run$origin)
  }
  list(responses=responses,assessments=assessments,source=list(kind="frozen_participant_protocol",runs=sources))
}

.brohn_vra_maxdiff_values <- function(input, admitted) {
  exercises <- brohn_default(input$design$maxdiff,list())
  if (!length(exercises)) return(list())
  origins <- unique(vapply(input$runs,`[[`,character(1),"origin"))
  brohn_require(length(origins)==1L,"Keep best-worst collection origins in separate reports.")
  for (run in input$runs) .brohn_vra_run_binding(run, input, admitted)
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

.brohn_vra_run_values <- function(input, admitted) {
  responses <- list(); task_scores <- list(); provenance <- list(); quality <- list(); design <- input$design
  revisions <- list()
  linked <- vapply(input$runs, function(r) isTRUE(r$participant_alias_supplied), logical(1))
  for (run in input$runs) {
    events <- input$events[[run$id]]
    # Explicit aliases can link repeats within this frozen cohort. Otherwise the
    # run is an unidentified session; never label its count unique participants.
    participant <- if (isTRUE(run$participant_alias_supplied)) paste0("alias:", run$participant_alias) else paste0("unlinked:", run$id)
    revision <- if (!is.null(run$protocol$design$questionnaire_navigation)) admitted[[run$id]]$projection else NULL
    if (!is.null(revision)) {
      responses <- c(responses, Filter(function(r) !isTRUE(r$information) && r$status %in% c("answered", "optional_omission"), revision$effective_records))
      revisions[[length(revisions)+1L]] <- revision
    }
    for (event in if (is.null(revision)) Filter(function(e) e$type == "response", events) else list()) {
      step <- brohn_find(run$protocol$timeline, event$step_id)
      if (!is.null(step) && step$type=="maxdiff") next
      brohn_require(!is.null(step) && step$type == "question", "A response has no matching frozen question step.")
      q <- step$question
      responses[[length(responses)+1L]] <- list(participant_id = participant, session_id = run$id,
        question_id = q$id, prompt = q$prompt, stimulus_id = step$stimulus_id, exposure_id = step$id,
        condition_id = step$condition_id, value = event$payload$value,
        missing_reason = if (is.null(event$payload$value)) "optional_omission" else NULL,
        response_time_ms = event$payload$response_time_ms, resumed = isTRUE(event$payload$resumed),
        origin = run$origin, sequence = event$sequence)
    }
    for (step in Filter(function(s) s$type == "task", run$protocol$timeline)) {
      recorded <- Filter(function(e) identical(e$type, "task_event") && identical(e$step_id, step$id) && identical(e$payload$kind, "task_trial_finished"), events)
      score <- .brohn_vra_task_values(step$task, lapply(recorded, function(e) e$payload$data), completed = TRUE)
      score$title <- step$task$title; score$participant_id <- participant; score$session_id <- run$id
      score$participant_linkage <- isTRUE(run$participant_alias_supplied)
      task_scores[[length(task_scores)+1L]] <- score
    }
    provenance[[length(provenance)+1L]] <- list(run_id=run$id, deployment_id=run$deployment_id,
      origin=run$origin, design_hash=run$protocol$design_hash, allocation_index=run$allocation_index,
      events_hash=brohn_hash(events), final_sequence=run$acked_sequence, finalized_at=run$finalized_at)
    quality[[length(quality)+1L]] <- list(run_id=run$id,
      visibility_event_count=sum(vapply(events, function(e) e$type == "visibility", logical(1))),
      participant_linkage=if (isTRUE(run$participant_alias_supplied)) "supplied_alias_not_identity_verified" else "unlinked_session",
      observed_timing="browser_timing_not_physical_qualification")
  }
  analysis <- brohn_questionnaire_analysis(responses, design)
  if (length(revisions)) analysis$questionnaire_revision <- list(schema = "brohn-questionnaire-revision-results/1.0", runs = revisions,
    interpretation = "One final effective answer per question occurrence enters analysis. Full acknowledged edit history is retained separately; revised or resumed values do not claim initial uninterrupted response time.")
  if (length(design$scales)) analysis$scales <- .brohn_vra_scale_values(input, admitted)
  if (length(design$maxdiff)) analysis$choice_tasks <- .brohn_vra_maxdiff_values(input, admitted)
  analysis$task_scores <- task_scores
  if (any(!linked)) {
    # Counts and numeric distributions still describe responses. Unknown repeat
    # identity cannot justify an independent-person interval or paired inference.
    analysis$contrasts <- list()
    analysis$quality["participant_count"] <- list(NULL)
    analysis$quality$unlinked_session_count <- sum(!linked)
    analysis$limitations <- c(list("Some sessions have no participant alias. Their responses remain visible, but unique-person counts and inferential condition contrasts are unavailable."), analysis$limitations)
  }
  report <- list(title = if (length(task_scores)) "Task and questionnaire results" else if (length(input$runs) == 1L) "Session responses" else "Release cohort responses",
    study_id = design$id, dataset_id = NULL, origin = input$runs[[1]]$origin,
    provenance = list(design = design, design_hash = brohn_hash(design), runs = provenance,
      cohort_policy = "explicit frozen completed-run membership; origin and design kept separate"),
    analysis = analysis, session_quality = quality)
  if (!is.null(input$run_evidence)) {
    evidence <- input$run_evidence
    report$provenance$run_evidence <- list(schema = evidence$schema, workspace_id = evidence$workspace_id,
      job_id = evidence$job_id, attempt = evidence$attempt, request_hash = evidence$request_hash, binding_hash = evidence$binding_hash,
      runs = lapply(evidence$runs, function(item) list(run_id = item$metadata$id,
        protocol_sha256 = item$protocol$sha256, protocol_bytes = item$protocol$bytes,
        journal_sha256 = item$journal$sha256, journal_bytes = item$journal$bytes,
        journal_rows_hash = item$journal$rows_hash, event_count = item$journal$event_count, final_sequence = item$journal$final_sequence)))
  }
  report
}


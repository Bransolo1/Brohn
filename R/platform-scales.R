# Explicit questionnaire arithmetic; no latent-trait or validity claim is made.
brohn_scale_recipe <- "explicit-questionnaire-scale/1.0"
brohn_scale_question_bounds <- function(q) {
  brohn_require(!is.null(q) && q$type %in% c("rating","number","slider"),
    "Scale items must be quantitative rating, number or slider questions. Numeric category codes are not scale items.")
  if(q$type=="rating") {
    brohn_require(length(q$options)>=2 && all(vapply(q$options,function(o) brohn_number(o$value),logical(1))),
      "A scale rating needs declared numeric option values.")
    values<-vapply(q$options,function(o) o$value,numeric(1));bounds<-c(min(values),max(values))
  } else bounds<-c(q$min,q$max)
  brohn_require(length(bounds)==2 && all(is.finite(bounds)) && bounds[1]<bounds[2],"Scale items need distinct finite lower and upper bounds.")
  unname(as.numeric(bounds))
}
brohn_validate_scales <- function(scales, design) {
  if(is.null(scales)) return(invisible(TRUE))
  brohn_require(brohn_array(scales) && length(scales)<=32L && !anyDuplicated(brohn_ids(scales)),"Use an array of at most 32 uniquely identified scales.")
  for(s in scales) {
    brohn_fields(s,c("schema","id","label","version","source","scope","items","scoring","conversion"),label="Questionnaire scale")
    brohn_require(identical(s$schema,"brohn-questionnaire-scale/1.0") && brohn_valid_id(s$id) && brohn_text(s$label,240) &&
      brohn_text(s$version,80) && brohn_text(s$source,4000),"Name the scale and declare its scoring source and version.")
    brohn_require(s$scope %in% c("before","end","after_each"),"Choose one assessment placement per scale.")
    brohn_require(brohn_array(s$items) && length(s$items)>=2L && length(s$items)<=100L,"A scale needs 2 to 100 quantitative items.")
    ids<-vapply(s$items,function(i) {brohn_fields(i,c("question_id","reverse","min","max"),label="Scale item");i$question_id},character(1))
    brohn_require(!anyDuplicated(ids),"A question cannot occur twice in one scale.")
    for(item in s$items) {
      q<-brohn_find(design$questions,item$question_id)
      guidance<-paste0("Scale '",s$label,"' still uses question '",brohn_default(q$prompt,item$question_id),"'. ",
        "Use Discard unsaved question edits, then edit or remove this scale key before changing its items.")
      brohn_require(!is.null(q),guidance)
      bounds<-tryCatch(brohn_scale_question_bounds(q),error=function(e) brohn_stop(paste(conditionMessage(e),guidance)))
      brohn_require(identical(q$scope,s$scope),paste("Scale items must share one assessment placement.",guidance))
      brohn_require(is.logical(item$reverse) && length(item$reverse)==1 && !is.na(item$reverse),"Each reverse key must be explicitly true or false.")
      brohn_require(brohn_number(item$min) && brohn_number(item$max) && identical(as.numeric(c(item$min,item$max)),bounds),
        paste("Item bounds differ from the frozen question. No reverse key was changed automatically.",guidance))
    }
    p<-s$scoring;brohn_fields(p,c("aggregation","missing","minimum_answered","prorate"),label="Scale scoring")
    brohn_require(p$aggregation %in% c("sum","mean") && p$missing %in% c("complete","minimum_answered") &&
      brohn_number(p$minimum_answered,1,length(s$items),TRUE) && is.logical(p$prorate) && length(p$prorate)==1 && !is.na(p$prorate),
      "Declare aggregation, missing-item rule and minimum answered count.")
    if(p$missing=="complete") brohn_require(p$minimum_answered==length(s$items) && !p$prorate,"Complete-item scoring requires every item and no prorating.")
    if(p$missing=="minimum_answered") {
      equal_ranges<-length(unique(vapply(s$items,function(i) brohn_json(list(i$min,i$max)),character(1))))==1L
      brohn_require(equal_ranges,"Partial-item scoring requires exactly equal item lower and upper bounds.")
      brohn_require(if(p$aggregation=="sum") p$prorate else !p$prorate,
        "Partial sums require explicit item-mean prorating; means use the available answered items directly.")
    }
    if(!is.null(s$conversion)) {
      brohn_fields(s$conversion,c("min","max"),label="Scale conversion")
      brohn_require(brohn_number(s$conversion$min,-1e9,1e9) && brohn_number(s$conversion$max,-1e9,1e9) && s$conversion$min<s$conversion$max,
        "Declare a finite increasing converted score range.")
    }
  }
  invisible(TRUE)
}
brohn_clone_scales <- function(scales, question_map) {
  if(is.null(scales)) return(NULL)
  lapply(scales,function(s) {
    s$id<-brohn_id("scale")
    s$items<-lapply(s$items,function(i) {
      brohn_require(i$question_id %in% names(question_map),"Cloning a scale requires every original question mapping.")
      i$question_id<-unname(question_map[[i$question_id]]);i
    });s
  })
}
.brohn_scale_context_key <- function(x) brohn_json(list(x$participant_id,x$session_id,x$assessment_id))
.brohn_scale_optional_identity <- function(x) if(is.null(x)||identical(x,"")) NULL else x
.brohn_scale_context <- function(r, scope) list(participant_id=r$participant_id,session_id=r$session_id,
  assessment_id=r$assessment_id,scope=scope,stimulus_id=.brohn_scale_optional_identity(r$stimulus_id),condition_id=.brohn_scale_optional_identity(r$condition_id),
  assessment_exposure_id=.brohn_scale_optional_identity(r$assessment_exposure_id),participant_linkage=isTRUE(r$participant_linkage),origin=.brohn_scale_optional_identity(r$origin))
brohn_score_scales <- function(responses, design, assessments=NULL, source=list()) {
  scales<-brohn_default(design$scales,list());brohn_validate_scales(scales,design)
  brohn_require(brohn_array(responses) && length(responses)<=250000L,"Scale scoring requires at most 250,000 explicit response records.")
  brohn_require(is.null(assessments)||brohn_array(assessments),"Expected assessments must be explicit records.")
  contexts<-list();groups<-list();unassigned<-list()
  add_context<-function(context) {
    brohn_require(all(vapply(context[c("participant_id","session_id","assessment_id")],brohn_text,logical(1),max=500)),"An assessment needs explicit participant, session and assessment identities.")
    brohn_require(brohn_text(context$scope,40) && context$scope %in% c("before","end","after_each"),"Declare a supported assessment placement.")
    key<-.brohn_scale_context_key(context)
    contexts[[key]]<<-c(contexts[[key]],list(context));key
  }
  for(a in brohn_default(assessments,list())) add_context(.brohn_scale_context(a,a$scope))
  for(i in seq_along(responses)) {
    r<-responses[[i]];q<-brohn_find(design$questions,r$question_id)
    if(is.null(q)||!brohn_text(r$assessment_id,500)) {
      unassigned[[length(unassigned)+1L]]<-list(source_row=i,question_id=r$question_id,
        reason=if(is.null(q)) "unknown_question" else "explicit_assessment_identity_required");next
    }
    context<-.brohn_scale_context(r,q$scope);key<-add_context(context)
    r$input_row<-i;groups[[key]]<-c(groups[[key]],list(r))
  }
  brohn_require(length(contexts)<=50000L,"Too many distinct assessments for this scale recipe.")
  scores<-list();item_evidence<-list()
  for(key in names(contexts)) {
    candidates<-contexts[[key]];context<-candidates[[1L]];rows<-brohn_default(groups[[key]],list())
    scopes<-unique(vapply(candidates,function(c) brohn_default(c$scope,""),character(1)))
    identity_variants<-unique(vapply(candidates,function(c) brohn_json(list(c$scope,c$stimulus_id,c$condition_id,c$assessment_exposure_id,c$origin)),character(1)))
    context_reason<-if(length(identity_variants)>1L) "conflicting_assessment_context" else NULL
    if(context$scope=="after_each") {
      stimulus<-brohn_find(design$stimuli,context$stimulus_id)
      if(is.null(stimulus)||!identical(stimulus$condition_id,context$condition_id)) context_reason<-"invalid_assessment_stimulus_condition"
    } else if(!is.null(context$stimulus_id)||!is.null(context$condition_id)) context_reason<-"unexpected_stimulus_for_whole_study_assessment"
    for(s in Filter(function(s) s$scope %in% scopes,scales)) {
      items<-lapply(s$items,function(item) {
        found<-Filter(function(r) identical(r$question_id,item$question_id),rows)
        reason<-NULL;raw<-NULL;keyed<-NULL;invalid<-FALSE
        if(!length(found)) reason<-"item_not_observed" else if(length(found)>1L) {reason<-"ambiguous_duplicate_item";invalid<-TRUE} else {
          raw<-found[[1L]]$value
          if(is.null(raw)) reason<-brohn_default(found[[1L]]$missing_reason,"missing_response") else {
            q<-brohn_find(design$questions,item$question_id)
            valid<-brohn_number(raw,item$min,item$max) && is.null(found[[1L]]$missing_reason)
            if(valid) valid<-tryCatch({.brohn_delivery_answer(q,list(value=raw));TRUE},error=function(e) FALSE)
            if(!valid) {reason<-"invalid_or_unsupported_response";invalid<-TRUE} else keyed<-if(item$reverse) item$min+item$max-raw else raw
          }
        }
        list(question_id=item$question_id,raw_value=raw,keyed_value=keyed,reverse=item$reverse,min=item$min,max=item$max,
          missing_reason=reason,invalid=invalid,source=lapply(found,function(r) list(input_row=r$input_row,source_row=r$source_row,
            step_id=r$step_id,source_exposure_id=r$exposure_id,sequence=r$sequence,event_id=r$event_id,response_hash=brohn_hash(r))))
      })
      answered<-sum(vapply(items,function(i) !is.null(i$keyed_value),logical(1)))
      invalid<-any(vapply(items,function(i) i$invalid,logical(1)))
      reason<-context_reason
      if(is.null(reason)&&invalid) reason<-"invalid_or_ambiguous_item"
      if(is.null(reason)&&answered<s$scoring$minimum_answered) reason<-"insufficient_answered_items"
      n<-length(s$items);aggregate<-NULL;converted<-NULL;prorated<-FALSE
      lower<-sum(vapply(s$items,function(i) i$min,numeric(1)));upper<-sum(vapply(s$items,function(i) i$max,numeric(1)))
      if(s$scoring$aggregation=="mean") {lower<-lower/n;upper<-upper/n}
      if(is.null(reason)) {
        values<-vapply(Filter(function(i) !is.null(i$keyed_value),items),function(i) i$keyed_value,numeric(1))
        if(s$scoring$aggregation=="mean") aggregate<-mean(values) else if(answered<n) {aggregate<-mean(values)*n;prorated<-TRUE} else aggregate<-sum(values)
        converted<-if(is.null(s$conversion)) aggregate else s$conversion$min+(aggregate-lower)/(upper-lower)*(s$conversion$max-s$conversion$min)
      }
      score_id<-paste0("scale-score-",substr(brohn_hash(list(key,s$id)),1,32))
      common<-context[c("participant_id","session_id","assessment_id","scope","stimulus_id","condition_id","assessment_exposure_id","origin")]
      scores[[length(scores)+1L]]<-c(list(id=score_id,scale_id=s$id,label=s$label,scale_version=s$version,scale_hash=brohn_hash(s)),common,
        list(status=if(is.null(reason)) "scored" else "not_scoreable",missing_reason=reason,value=converted,raw_aggregate=aggregate,
          raw_min=lower,raw_max=upper,unit=if(is.null(s$conversion)) "scale points" else "converted scale points",answered_items=answered,total_items=n,
          minimum_answered=s$scoring$minimum_answered,prorated=prorated,participant_linkage=all(vapply(candidates,function(c) isTRUE(c$participant_linkage),logical(1)))))
      item_evidence[[length(item_evidence)+1L]]<-list(score_id=score_id,items=items)
      brohn_require(length(scores)<=100000L,"This scale report exceeds 100,000 assessment scores. Select a smaller explicit cohort.")
    }
  }
  features<-lapply(scales,function(s) {
    rows<-Filter(function(r) identical(r$scale_id,s$id),scores);usable<-Filter(function(r) identical(r$status,"scored"),rows)
    list(scale_id=s$id,label=s$label,assessment_count=length(rows),scored_assessment_count=length(usable),not_scoreable_count=length(rows)-length(usable),
      session_count=length(unique(vapply(rows,function(r) brohn_json(list(r$participant_id,r$session_id)),character(1)))),
      participant_count=if(length(rows)&&all(vapply(rows,function(r) isTRUE(r$participant_linkage),logical(1)))) length(unique(vapply(rows,`[[`,character(1),"participant_id"))) else NULL)
  })
  question_ids<-unique(unlist(lapply(scales,function(s) vapply(s$items,`[[`,character(1),"question_id")),use.names=FALSE))
  list(schema="brohn-questionnaire-scale-results/1.0",recipe=brohn_scale_recipe,features=features,observations=scores,item_evidence=item_evidence,
    quality=list(source_response_count=length(responses),assessment_count=length(contexts),unassigned_response_count=length(unassigned),unassigned=unassigned),
    provenance=list(design_hash=brohn_hash(design),scales=scales,scales_hash=brohn_hash(scales),
      questionnaire=Filter(function(q) q$id %in% question_ids,design$questions),responses_hash=brohn_hash(responses),source=source),
    limitations=list("Scores implement the researcher's declared arithmetic; naming a scale does not validate its items, adaptation, language or target population.",
      "Each assessment is scored separately. Sessions and repeated stimuli are never pooled to fill missing items.",
      "Prorated scores are estimates under the declared missing-item rule. No missing response becomes zero.",
      "No reliability estimate, clinical cutoff, latent-trait inference or universal usability benchmark is calculated."))
}
brohn_scale_run_responses <- function(input) {
  responses<-list();assessments<-list();sources<-list()
  for(run in input$runs) {
    protocol<-run$protocol;events<-input$events[[run$id]]
    brohn_require(identical(protocol$design_hash,brohn_hash(protocol$design)) && identical(brohn_hash(input$design),protocol$design_hash),"Scale scoring requires one unchanged frozen questionnaire design.")
    participant<-if(isTRUE(run$participant_alias_supplied)) paste0("alias:",run$participant_alias) else paste0("unlinked:",run$id)
    if (!is.null(protocol$design$questionnaire_navigation)) {
      projection <- brohn_questionnaire_run_projection(run, events)
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
brohn_score_run_scales <- function(input) {
  if(!length(input$design$scales)) return(NULL)
  prepared<-brohn_scale_run_responses(input)
  brohn_score_scales(prepared$responses,input$design,prepared$assessments,prepared$source)
}
brohn_scale_scores_csv <- function(result, path) {
  brohn_require(identical(result$schema,"brohn-questionnaire-scale-results/1.0") && brohn_array(result$observations),"Choose a saved questionnaire scale result.")
  columns<-c("id","scale_id","label","scale_version","scale_hash","participant_id","session_id","assessment_id","scope",
    "stimulus_id","condition_id","assessment_exposure_id","origin","participant_linkage","status","missing_reason","value","unit",
    "raw_aggregate","raw_min","raw_max","answered_items","total_items","minimum_answered","prorated",
    "design_hash","scales_hash","responses_hash","score_record_json")
  encode<-function(x) if(is.null(x)) "" else if(is.character(x)&&length(x)==1) x else brohn_json(x)
  rows<-lapply(result$observations,function(r) c(r,list(design_hash=result$provenance$design_hash,scales_hash=result$provenance$scales_hash,
    responses_hash=result$provenance$responses_hash,score_record_json=brohn_json(r))))
  table<-as.data.frame(stats::setNames(lapply(columns,function(col) vapply(rows,function(r) encode(r[[col]]),character(1))),columns),stringsAsFactors=FALSE)
  # Visible text cells cannot trigger spreadsheet formulas. The canonical JSON
  # score record retains exact original typed labels/identities alongside them.
  for(col in names(table)) {
    unsafe<-grepl("^[[:space:]]*[=+@]|^[[:space:]]*-[^0-9.]",table[[col]],perl=TRUE)
    table[[col]][unsafe]<-paste0("'",table[[col]][unsafe])
  }
  utils::write.csv(table,path,row.names=FALSE,na="",fileEncoding="UTF-8");invisible(path)
}

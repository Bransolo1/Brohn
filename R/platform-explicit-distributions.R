# Descriptive complete-source questionnaire/scale distributions; no new scoring.
.brohn_ed_recipe <- "explicit-saved-distributions/1.0"
.brohn_ed_loaded <- setNames(list(digest::digest(file="R/platform-explicit-distributions.R",algo="sha256")),"R/platform-explicit-distributions.R")
.brohn_ed_same <- function(a,b) identical(brohn_hash(a),brohn_hash(b))
.brohn_ed_kind <- function(x) if(is.null(x)) "null" else if(is.logical(x)) "boolean" else if(is.numeric(x)) "number" else if(is.character(x)) "text" else if(is.null(names(x))) "array" else "object"
.brohn_ed_key <- function(row) if(all(vapply(row[c("participant_id","session_id","assessment_id")],brohn_text,logical(1),max=1024)) && all(c("participant_id","session_id","assessment_id") %in% names(row))) brohn_hash(row[c("participant_id","session_id","assessment_id")]) else NA_character_
.brohn_ed_state <- function(row,family) {
  if(family=="scale") return(if(identical(row$status,"scored")&&is.null(row$missing_reason)) "scored" else brohn_default(row$missing_reason,"not_scoreable"))
  if(isTRUE(row$information)) return(brohn_default(row$status,"information"))
  if(!is.null(row$status)) return(row$status)
  if(!is.null(row$missing_reason)) return(row$missing_reason)
  if(is.null(row$value)) "missing_response" else "answered"
}
.brohn_ed_validate_scales <- function(scales,design) {
  if(is.null(scales))return(invisible(TRUE))
  brohn_require(identical(scales$schema,"brohn-questionnaire-scale-results/1.0")&&identical(scales$recipe,brohn_scale_recipe)&&
    identical(scales$provenance$design_hash,brohn_hash(design))&&.brohn_ed_same(scales$provenance$scales,design$scales)&&
    identical(scales$provenance$scales_hash,brohn_hash(design$scales)),"Saved scale distributions require the original supported recipe and frozen scoring keys.")
  brohn_validate_scales(design$scales,design)
  brohn_require(brohn_array(scales$observations),"Saved scale assessments must be a complete source array.")
  for(row in scales$observations){
    key<-brohn_find(design$scales,row$scale_id)
    brohn_require(!is.null(key)&&identical(row$scale_hash,brohn_hash(key))&&identical(row$scale_version,key$version)&&
      identical(row$unit,if(is.null(key$conversion))"scale points"else"converted scale points")&&
      row$status %in% c("scored","not_scoreable"),"A saved scale assessment differs from its declared scoring key, units or supported state.")
    brohn_require(if(row$status=="scored")brohn_number(row$value)&&is.null(row$missing_reason)else is.null(row$value)&&brohn_text(row$missing_reason,1024),
      "A saved scale assessment has inconsistent score eligibility; no new score was inferred.")
  }
  invisible(TRUE)
}
brohn_explicit_distribution_group <- function(rows,family,item,condition_id,condition_label) {
  brohn_require(length(rows)>0L && family %in% c("question","scale"),"Choose a nonempty saved response group.")
  quantitative <- family=="scale" || (!is.null(item) && item$type %in% c("number","slider","rating"))
  if(quantitative && family=="question" && item$type=="rating") quantitative <- length(item$options)>0L && all(vapply(item$options,function(o)brohn_number(o$value),logical(1)))
  states <- vapply(rows,.brohn_ed_state,character(1),family=family)
  brohn_require(all(vapply(as.list(states),brohn_text,logical(1),max=128)),"Saved response states are not supported bounded labels.")
  eligible <- vapply(seq_along(rows),function(i) {
    r<-rows[[i]]
    if(!identical(states[[i]],if(family=="scale")"scored"else"answered")||is.null(r$value)||!is.null(r$missing_reason)||isTRUE(r$information))return(FALSE)
    if(family=="scale")return(brohn_number(r$value))
    if(is.null(item))return(TRUE)
    tryCatch({.brohn_delivery_answer(item,list(value=r$value));TRUE},error=function(e)FALSE)
  },logical(1))
  invalid <- sum(states %in% c("answered","scored") & !eligible)
  usable<-rows[eligible]; values<-lapply(usable,`[[`,"value")
  codes<-vapply(values,brohn_json,character(1)); levels<-sort(unique(codes),method="radix")
  brohn_require(length(levels)<=10000L,"This group has more than 10,000 distinct values. Use a smaller explicit report cohort; no distribution was truncated.")
  counts<-tabulate(match(codes,levels),nbins=length(levels))
  categories<-lapply(seq_along(levels),function(i){v<-brohn_parse(levels[[i]]);label<-levels[[i]]
    if(family=="question"&&!is.null(item)){option<-Filter(function(o).brohn_ed_same(o$value,v),brohn_default(item$options,list()));if(length(option))label<-option[[1L]]$label}
    list(value_kind=.brohn_ed_kind(v),value_json=levels[[i]],label=label,count=counts[[i]])})
  numbers<-if(quantitative)vapply(values,function(v)if(brohn_number(v))v else NA_real_,numeric(1))else numeric()
  brohn_require(!anyNA(numbers),"A declared quantitative distribution contains unsupported saved values.")
  bins<-list(); summary<-NULL
  if(length(numbers)){
    lo<-min(numbers);hi<-max(numbers)
    if(lo==hi)bins<-list(list(lower=lo,upper=hi,upper_inclusive=TRUE,count=length(numbers)))else{
      breaks<-seq(lo,hi,length.out=11L);brohn_require(all(is.finite(breaks))&&all(diff(breaks)>0),"The saved numeric range cannot be represented by this histogram profile.")
      at<-pmin(10L,findInterval(numbers,breaks,rightmost.closed=TRUE));n<-tabulate(at,10L)
      bins<-lapply(1:10,function(i)list(lower=breaks[[i]],upper=breaks[[i+1L]],upper_inclusive=i==10L,count=n[[i]]))
    }
    summary<-list(n=length(numbers),mean=mean(numbers),median=stats::median(numbers),minimum=lo,maximum=hi)
    brohn_require(all(vapply(summary,brohn_number,logical(1))),"The numeric summary exceeds finite arithmetic support.")
  }
  assessments<-vapply(rows,.brohn_ed_key,character(1)); known<-assessments[!is.na(assessments)]
  linked<-vapply(rows,function(r)isTRUE(r$participant_linkage)&&brohn_text(r$participant_id,1024)&&!startsWith(r$participant_id,"unlinked:"),logical(1))
  ids<-vapply(rows,function(r)brohn_default(r$participant_id,""),character(1))
  if(family=="scale")brohn_require(length(unique(vapply(rows,function(r)brohn_default(r$scale_hash,""),character(1))))==1L && length(unique(vapply(rows,function(r)brohn_default(r$unit,""),character(1))))==1L,"Different scale keys or units cannot be pooled in a distribution.")
  item_id<-if(family=="scale")rows[[1]]$scale_id else rows[[1]]$question_id
  label<-if(family=="scale")rows[[1]]$label else if(!is.null(item))item$prompt else brohn_default(rows[[1]]$prompt,item_id)
  unit<-if(family=="scale")rows[[1]]$unit else if(quantitative)"declared response units"else"typed response categories"
  state_levels<-sort(unique(states),method="radix")
  list(id=paste0("distribution-",substr(brohn_hash(list(family,item_id,condition_id)),1,32)),family=family,item_id=item_id,label=label,
    condition_id=condition_id,condition_label=condition_label,unit=unit,quantitative=quantitative,
    source_records=length(rows),usable_records=sum(eligible),invalid_or_unsupported=invalid,
    states=lapply(state_levels,function(s)list(state=s,count=sum(states==s))),
    assessment_count=if(anyNA(assessments))NULL else length(unique(known)),known_assessments=length(unique(known)),
    unassigned_records=sum(is.na(assessments)),repeated_assessment_records=length(known)-length(unique(known)),
    participant_count=if(all(linked))length(unique(ids))else NULL,participant_linkage_complete=all(linked),
    descriptive_unit=if(family=="scale")"saved scale assessment scores"else"saved effective question records",
    summary=summary,categories=categories,bins=bins,
    scale_key=if(family=="scale")rows[[1]][c("scale_id","scale_version","scale_hash")]else NULL)
}
brohn_build_explicit_distributions <- function(answers,scales,design=NULL) {
  brohn_require(brohn_array(answers)&&brohn_array(scales)&&length(answers)+length(scales)<=250000L,"Distribution review supports at most 250,000 complete saved records; no preview or partial cohort is substituted.")
  groups<-list()
  for(family in c("question","scale")) {
    rows<-if(family=="question")answers else scales;field<-if(family=="question")"question_id"else"scale_id"
    brohn_require(all(vapply(rows,function(r)brohn_text(r[[field]],1024),logical(1))),"Every response needs its original question or scale identity.")
    keys<-vapply(rows,function(r)brohn_json(list(r[[field]],r$condition_id)),character(1))
    for(key in unique(keys)){
      selected<-rows[keys==key];first<-selected[[1]];item<-if(family=="question")brohn_find(design$questions,first$question_id)else NULL
      condition<-brohn_find(design$conditions,first$condition_id)
      groups[[length(groups)+1L]]<-brohn_explicit_distribution_group(selected,family,item,first$condition_id,
        if(is.null(first$condition_id))"No condition supplied"else if(is.null(condition))first$condition_id else condition$label)
    }
  }
  result<-list(schema="brohn-explicit-distributions/1.0",recipe=.brohn_ed_recipe,groups=groups,
    source_counts=list(question_records=length(answers),scale_records=length(scales)),
    policy=list(denominator="Each table/plot counts eligible saved records in one item and exact condition, never independent people.",
      numeric="Only frozen quantitative item types or eligible saved scale scores; no coercion, rescoring or normative interpretation.",
      missing="Missing, omitted, not-displayed, invalidated and unsubmitted source states stay separate; absent expected records are not invented.",
      histogram="Ten equal-width bins across eligible saved values; left closed, right open except final upper bound. Constant values form one bin."))
  brohn_require(nchar(brohn_json(result),type="bytes")<=8*1024^2,"The complete distribution exceeds the 8 MiB saved-result profile; select a smaller explicit cohort. Nothing was truncated.")
  result
}
.brohn_ed_source <- function(store,request,verify=TRUE) {
  source<-.brohn_questionnaire_index_source(store,request$report_id,request$report_revision,request$report_hash,request$project_id,verify_bytes=verify)
  brohn_require(identical(source$catalog_hash,request$catalog_hash)&&.brohn_ed_same(source$artifact,request$artifact)&&.brohn_ed_same(source$result_object,request$result_object),"The distribution's source authority or retained objects changed.")
  source
}
brohn_queue_explicit_distributions <- function(store,report_id,report_hash,retry=FALSE) {
  report<-brohn_get_entity(store,"report",report_id);brohn_require(!is.null(report)&&identical(brohn_hash(report$body),report_hash),"Reopen the exact saved questionnaire report.")
  source<-.brohn_questionnaire_index_source(store,report$id,report$revision,report_hash,report$project_id,verify_bytes=FALSE)
  request<-list(report_id=report$id,report_revision=report$revision,report_hash=report_hash,project_id=report$project_id,
    catalog_hash=source$catalog_hash,artifact=source$artifact,result_object=source$result_object,binding=source$binding,implementation=.brohn_ed_loaded)
  brohn_enqueue_job(store,"explicit_distributions",request,paste0("explicit-distributions:",brohn_hash(request),if(retry)paste0(":",brohn_id("retry"))else""))
}
brohn_explicit_distribution_input <- function(store,job,verify=TRUE) {
  r<-job$request;brohn_require(identical(job$operation,"explicit_distributions")&&.brohn_ed_same(r$implementation,.brohn_ed_loaded),"Rebuild distributions using the current reader implementation.")
  source<-.brohn_ed_source(store,r,verify)
  brohn_require(.brohn_ed_same(source$binding,r$binding),"The complete analysis binding changed.")
  list(schema="brohn-analysis-input/1.0",operation="explicit_distributions",project_id=r$project_id,
    index_input=list(schema="brohn-questionnaire-index-input/1.0",binding=source$binding,report=source$report$body,artifact_path=source$artifact_path))
}
brohn_analyse_explicit_distributions <- function(input,scratch) {
  # The existing complete index builder verifies revisions, commits and effective
  # observations before exposing all final states, including hidden questions.
  index<-brohn_build_questionnaire_index(input$index_input,file.path(scratch,"distribution-source.sqlite"))
  con<-DBI::dbConnect(RSQLite::SQLite(),index$index$path,flags=RSQLite::SQLITE_RO);on.exit(DBI::dbDisconnect(con))
  answers<-lapply(DBI::dbGetQuery(con,"SELECT row_json FROM records WHERE collection='answers' ORDER BY ordinal")$row_json,brohn_parse)
  report<-input$index_input$report
  full<-if(brohn_questionnaire_is_artifact(report$analysis))brohn_read_questionnaire_artifact(input$index_input$artifact_path,brohn_questionnaire_report_artifact(report),brohn_questionnaire_artifact_source(report))else report$analysis
  .brohn_ed_validate_scales(full$scales,report$provenance$design)
  result<-brohn_build_explicit_distributions(answers,brohn_default(full$scales$observations,list()),report$provenance$design)
  result$binding<-input$index_input$binding;result$answer_source<-index$index$counts
  list(explicit_distributions=result)
}
brohn_publish_explicit_distributions <- function(store,output,scratch,job,input,output_path) {
  .brohn_publication_output_identity(output,.brohn_ed_loaded);.brohn_publication_job(store,job)
  guards<-.brohn_qexplorer_source_guards(store,job$request);on.exit(for(g in guards).brohn_qexplorer_release(g),add=TRUE)
  brohn_require(.brohn_ed_same(input,brohn_explicit_distribution_input(store,job))&&.brohn_ed_same(brohn_read_json_file(output_path),output),"Distribution publication changed its pinned source or output.")
  result<-output$report$explicit_distributions
  brohn_require(identical(result$schema,"brohn-explicit-distributions/1.0")&&.brohn_ed_same(result$binding,input$index_input$binding)&&nchar(brohn_json(result),type="bytes")<=8*1024^2,"The complete distribution result or source binding is invalid.")
  id<-paste0("explicit-distributions-",sub("^job[_-]","",job$id))
  body<-list(schema="brohn-saved-explicit-distributions/1.0",id=id,report_id=job$request$report_id,origin=input$index_input$binding$origin,
    request=job$request,result=result,created_at=brohn_now(),processing=list(job_id=job$id,attempt=job$attempt,code_hashes=output$code_identity))
  document<-.brohn_publication_stage_json(store,job,body,file.path(scratch,"published-distributions.json"));committed<-FALSE
  on.exit(brohn_close_publication(document$guard,committed),add=TRUE)
  receipt<-brohn_store_batch(store,function(){
    brohn_require(identical(.brohn_qexplorer_catalog(store,"report",job$request$report_id,job$request$report_revision,input$project_id),job$request$catalog_hash),"Saved report authority changed before publication.")
    brohn_project(store,input$project_id);for(g in guards).Call(g$native$check,g$pointer);.brohn_publication_job(store,job)
    body$result_object<-.brohn_publication_register(store,document)[[1L]][c("hash","size","media_type")]
    brohn_put_entity(store,"explicit_distributions",id,body,expected_revision=0L,project_id=input$project_id)
    brohn_complete_job(store,job$id,job$worker,job$token,list(explicit_distributions_id=id,report_id=body$report_id,output_hash=body$result_object$hash))})
  committed<-TRUE;receipt
}
brohn_explicit_distribution_record <- function(store,id,expected_hash=NULL) {
  record<-brohn_get_entity(store,"explicit_distributions",id)
  brohn_require(!is.null(record)&&identical(record$body$schema,"brohn-saved-explicit-distributions/1.0")&&(is.null(expected_hash)||identical(brohn_hash(record$body),expected_hash)),"This saved distribution changed. Reopen the report.")
  .brohn_ed_source(store,record$body$request,verify=FALSE)
  original<-brohn_read_json_file(brohn_object_path(store,record$body$result_object$hash,verify=TRUE))
  brohn_require(.brohn_ed_same(original,record$body[setdiff(names(record$body),"result_object")]),"Saved distribution bytes differ from their retained publication.")
  record
}

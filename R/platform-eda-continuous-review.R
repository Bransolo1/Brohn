# Read-only candidate windows from complete original saved eda evidence.
.brohn_eda_continuous_review_loaded <- local({p<-c("R/platform-eda-continuous-review.R","scripts/workers/eda_continuous_review.py","scripts/workers/physiology_artifacts.py");stats::setNames(lapply(p,function(x)digest::digest(file=x,algo="sha256")),p)})
.brohn_ecr_same <- function(a,b)identical(.brohn_sv_hash(a),.brohn_sv_hash(b))
brohn_eda_continuous_review_supported <- function(report)identical(report$analysis$modality,"eda")&&length(report$analysis$recordings)>0L&&
  any(vapply(report$analysis$parameters,function(p)identical(p$recipe,"eda-neurokit-highpass/1.0"),logical(1)))
.brohn_ecr_decimal <- function(x)brohn_text(x,80)&&grepl("^-?[0-9]+(\\.[0-9]+)?([eE][+-]?[0-9]+)?$",x)&&is.finite(suppressWarnings(as.numeric(x)))&&abs(as.numeric(x))<=1e12
.brohn_ecr_shortest <- function(x) {
  for(n in 1:17){s<-sprintf(paste0("%.",n,"g"),x);if(identical(as.numeric(s),as.numeric(x)))return(s)}
  stop("Cannot retain this finite source-time representation.")
}
.brohn_ecr_decimal_compare <- function(a,b) {
  parts<-function(s){negative<-startsWith(s,"-");s<-sub("^-","",tolower(s));pair<-strsplit(s,"e",fixed=TRUE)[[1L]]
    exponent<-if(length(pair)>1L)as.numeric(pair[[2L]])else 0;brohn_require(is.finite(exponent)&&abs(exponent)<=1000,"Decimal source-time exponent exceeds the review profile.")
    mantissa<-strsplit(pair[[1L]],".",fixed=TRUE)[[1L]];fraction<-if(length(mantissa)>1L)nchar(mantissa[[2L]])else 0
    digits<-sub("^0+","",paste(mantissa,collapse=""));if(!nzchar(digits))return(list(sign=0,order=0,digits="0"))
    list(sign=if(negative)-1 else 1,order=exponent-fraction+nchar(digits),digits=digits)}
  x<-parts(a);y<-parts(b);if(x$sign!=y$sign)return(sign(x$sign-y$sign));if(x$sign==0)return(0)
  if(x$order!=y$order)return(x$sign*sign(x$order-y$order))
  n<-max(nchar(x$digits),nchar(y$digits));left<-paste0(x$digits,strrep("0",n-nchar(x$digits)));right<-paste0(y$digits,strrep("0",n-nchar(y$digits)))
  if(identical(left,right))0 else if(left<right)-x$sign else x$sign
}
.brohn_ecr_in_window <- function(time,selection) {
  text<-.brohn_ecr_shortest(time)
  .brohn_ecr_decimal_compare(text,selection$start_s)>=0&&.brohn_ecr_decimal_compare(text,selection$end_s)<=0
}
brohn_eda_continuous_review_selection <- function(analysis,selection) {
  brohn_fields(selection,c("recording_id","segment_id","channel","start_s","end_s"),label="EDA candidate selection")
  identity<-selection[c("recording_id","segment_id","channel")]
  brohn_require(all(vapply(identity,brohn_text,logical(1),max=500)),"Choose one exact saved recording, continuous segment and channel.")
  brohn_require(.brohn_ecr_decimal(selection$start_s)&&.brohn_ecr_decimal(selection$end_s)&&as.numeric(selection$start_s)<as.numeric(selection$end_s),"Enter increasing decimal source-time bounds in seconds.")
  matches<-Filter(function(e)all(vapply(names(identity),function(k)identical(e[[k]],identity[[k]]),logical(1))),analysis$recordings)
  brohn_require(length(matches)==1L,"Choose one continuous segment from the complete saved result.")
  recording<-matches[[1L]];p<-analysis$parameters[[recording$recording_id]]
  brohn_require(identical(recording$status,"computed"),paste("This saved segment is unavailable:",brohn_default(recording$reason,"no supported processed samples")))
  brohn_require(identical(p$recipe,"eda-neurokit-highpass/1.0")&&identical(recording$unit,"uS")&&identical(p$cleaner,"neurokit")&&
    p$clean_lowpass_hz==3&&p$clean_order==4&&identical(p$decomposition,"highpass")&&p$phasic_cutoff_hz==.05&&p$recovery_fraction==.5&&
    identical(p$threshold_definition,"candidate_prominence_relative_to_maximum_prominence")&&isTRUE(p$no_missing_value_imputation),
    "This review requires saved continuous EDA conductance with its original decomposition and relative-prominence settings.")
  brohn_require(brohn_number(recording$start_time_s)&&brohn_number(recording$end_time_s,recording$start_time_s)&&brohn_number(recording$sampling_rate,8,100000)&&
    brohn_number(p$amplitude_min_relative_prominence,.001,1)&&brohn_number(p$edge_exclusion_s,10,120),"The saved EDA continuous support, sample rate or relative threshold is incomplete.")
  list(recording=recording,parameters=p)
}
.brohn_ecr_source <- function(store,r,verify=FALSE) {
  catalog<-.brohn_qexplorer_catalog(store,"report",r$report_id,r$report_revision,r$project_id);brohn_project(store,r$project_id)
  report<-brohn_get_entity(store,"report",r$report_id,r$report_revision)
  brohn_require(identical(.brohn_sv_hash(report$body),r$report_hash)&&identical(catalog,r$catalog_hash)&&brohn_eda_continuous_review_supported(report$body),"The exact saved eda report or its project authority changed.")
  a<-report$body$analysis;p<-report$body$provenance
  dataset_catalog<-.brohn_qexplorer_catalog(store,"dataset",p$dataset_id,p$dataset_revision,r$project_id)
  dataset<-brohn_get_entity(store,"dataset",p$dataset_id,p$dataset_revision)
  brohn_require(identical(p$dataset_id,report$body$dataset_id)&&identical(.brohn_sv_hash(dataset$body),p$dataset_hash)&&
    identical(dataset$body$modality,"eda")&&.brohn_ecr_same(dataset$body$metadata,p$mapping)&&.brohn_ecr_same(dataset$body$source,p$source)&&
    identical(a$source$sha256,p$source$hash)&&identical(report$body$origin,dataset$body$origin)&&identical(p$origin,report$body$origin)&&identical(r$origin,report$body$origin),
    "The eda report differs from its original dataset, mapping, source or origin.")
  if(!is.null(r$dataset_catalog_hash))brohn_require(identical(dataset_catalog,r$dataset_catalog_hash),"Original eda dataset authority changed.")
  brohn_require(identical(report$body$id,report$id)&&identical(dataset$body$study_id,report$body$study_id),"The eda source changed its study ownership.")
  if(is.null(report$body$study_id))brohn_require(is.null(p$design)&&is.null(p$design_hash)&&is.null(p$study_id)&&is.null(p$study_revision),"A standalone source cannot acquire an invented study.")else {
    brohn_require(identical(p$study_id,report$body$study_id)&&identical(p$design$id,report$body$study_id)&&identical(p$design$project_id,r$project_id)&&identical(brohn_hash(p$design),p$design_hash),"The saved study design differs from its source provenance.")
    .brohn_qexplorer_catalog(store,"study",p$study_id,p$study_revision,r$project_id)
    study<-brohn_get_entity(store,"study",p$study_id,p$study_revision)
    brohn_require(identical(brohn_hash(study$body),p$design_hash),"The original study revision changed.")
  }
  picked<-brohn_eda_continuous_review_selection(a,r$selection)
  artifacts<-lapply(Filter(function(k)any(vapply(a$artifacts,function(x)identical(x$kind,k),logical(1))),c("physiology-series","physiology-events")),function(k)brohn_signal_artifact(report,k))
  brohn_require(length(artifacts)==2L,"Complete saved continuous and candidate artifacts are required; display previews cannot replace them.")
  if(!is.null(r$artifacts))brohn_require(.brohn_ecr_same(artifacts,r$artifacts),"The original eda processed artifacts changed.")
  refs<-list(list(hash=p$source$hash,bytes=p$source$size))
  retained<-.brohn_sv_retained(store,report,"report",verify)
  brohn_require(!is.null(retained),"This review requires the original retained report envelope.")
  refs<-c(refs,list(retained),lapply(artifacts,function(x)list(hash=x$sha256,bytes=x$bytes)))
  for(ref in refs)brohn_require(file.info(brohn_object_path(store,ref$hash,verify=verify))$size==ref$bytes,"An original eda object differs from its retained byte count.")
  list(report=report,dataset=dataset,dataset_catalog_hash=dataset_catalog,artifacts=artifacts,retained=retained,source_objects=refs,picked=picked)
}
brohn_queue_eda_continuous_review <- function(store,report_id,report_revision,report_hash,selection,retry=FALSE) {
  report<-brohn_get_entity(store,"report",report_id,report_revision)
  brohn_require(!is.null(report)&&identical(.brohn_sv_hash(report$body),report_hash),"Reopen the exact eda report before choosing a candidate window.")
  r<-list(report_id=report_id,report_revision=report_revision,report_hash=report_hash,project_id=report$project_id,
    catalog_hash=.brohn_qexplorer_catalog(store,"report",report_id,report_revision,report$project_id),selection=selection,
    recipe="saved-continuous-eda-review/1.0",implementation=.brohn_eda_continuous_review_loaded,origin=report$body$origin)
  source<-.brohn_ecr_source(store,r);r$dataset_catalog_hash<-source$dataset_catalog_hash;r$artifacts<-source$artifacts;r$result_object<-source$retained
  brohn_enqueue_job(store,"eda_continuous_review",r,paste0("eda-continuous-review:",brohn_hash(r),if(retry)paste0(":",brohn_id("retry"))else""))
}
brohn_eda_continuous_review_input <- function(store,job,verify=TRUE) {
  r<-job$request
  brohn_fields(r,c("report_id","report_revision","report_hash","project_id","catalog_hash","selection","recipe","implementation","origin","dataset_catalog_hash","artifacts","result_object"),label="Saved eda review request")
  brohn_require(identical(job$operation,"eda_continuous_review")&&identical(r$recipe,"saved-continuous-eda-review/1.0")&&.brohn_ecr_same(r$implementation,.brohn_eda_continuous_review_loaded),"Rebuild this eda review with the current saved-result reader.")
  s<-.brohn_ecr_source(store,r,verify);pick<-s$picked
  brohn_require(.brohn_ecr_same(s$retained,r$result_object),"The retained report envelope changed.")
  features<-Filter(function(f)all(vapply(c("recording_id","segment_id","channel"),function(k)identical(f[[k]],pick$recording[[k]]),logical(1))),s$report$body$analysis$features)
  brohn_require(length(features)>0L&&!anyDuplicated(vapply(features,`[[`,character(1),"name")),"Saved whole-segment EDA features are incomplete or duplicated.")
  list(schema="brohn-analysis-input/1.0",operation="eda_continuous_review",project_id=r$project_id,binding=r,features=features,
    recording=pick$recording,parameters=pick$parameters,selection=r$selection,
    artifacts=lapply(s$artifacts,function(x)c(x,list(path=brohn_object_path(store,x$sha256,verify=FALSE)))),
    original_source=list(hash=s$dataset$body$source$hash,bytes=s$dataset$body$source$size,path=brohn_object_path(store,s$dataset$body$source$hash,verify=FALSE)),
    sealed_objects=list(c(s$retained,list(path=brohn_object_path(store,s$retained$hash,verify=FALSE)))),source_objects=s$source_objects)
}
brohn_validate_eda_continuous_review <- function(result,input) {
  brohn_require(identical(result$schema,"brohn-eda-continuous-review/1.0")&&result$status %in% c("available","no_processed_samples")&&
    .brohn_ecr_same(result$binding,input$binding)&&.brohn_ecr_same(result$selection,input$selection)&&.brohn_ecr_same(result$recording,input$recording)&&
    .brohn_ecr_same(result$parameters,input$parameters)&&.brohn_ecr_same(result$features,input$features)&&identical(result$unit,"uS")&&identical(result$raw_available,FALSE),
    "EDA review substituted its original source, support, parameters or whole-segment measurements.")
  c<-result$counts;lo<-as.numeric(input$selection$start_s);hi<-as.numeric(input$selection$end_s)
  samples<-Filter(function(a)identical(a$kind,"physiology-series"),input$artifacts)[[1L]];events<-Filter(function(a)identical(a$kind,"physiology-events"),input$artifacts)[[1L]]
  brohn_require(brohn_number(c$selected_samples,0,500000,TRUE)&&brohn_number(c$selected_candidates,0,5000,TRUE)&&
    c$retained_samples+c$excluded_samples==c$selected_samples&&brohn_number(c$retained_samples,0,c$selected_samples,TRUE)&&brohn_number(c$excluded_samples,0,c$selected_samples,TRUE)&&
    c$segment_samples==input$recording$samples&&c$segment_retained_samples==input$recording$retained_samples&&c$segment_samples>=c$selected_samples&&
    brohn_number(c$segment_candidates,c$selected_candidates,20000000,TRUE)&&brohn_number(c$segment_amplitude_available,0,c$segment_candidates,TRUE)&&
    brohn_number(c$segment_onset_missing,0,c$segment_candidates,TRUE)&&brohn_number(c$segment_recovery_missing,0,c$segment_candidates,TRUE)&&
    c$complete_sample_artifact_rows==samples$rows&&c$complete_event_artifact_rows==events$rows&&length(result$rows)==min(50,c$selected_samples)&&
    identical(result$status,if(c$selected_samples>0)"available"else"no_processed_samples"),"Complete EDA support and window counts do not reconcile.")
  feature<-function(name){xs<-Filter(function(f)identical(f$name,name),input$features);brohn_require(length(xs)==1L,"Saved EDA feature support is incomplete.");xs[[1]]}
  brohn_require(feature("scr_count")$value==c$segment_candidates&&feature("scr_amplitude_mean")$denominator==c$segment_amplitude_available&&
    feature("scr_amplitude_median")$denominator==c$segment_amplitude_available,"Saved candidate counts or conditional-amplitude denominators changed.")
  brohn_require(length(result$exports)==3L&&identical(vapply(result$exports,`[[`,character(1),"name"),c("eda-samples.csv","eda-candidates.csv","eda-markers.csv"))&&
    result$exports[[1]]$rows==c$selected_samples&&result$exports[[2]]$rows==c$selected_candidates&&result$exports[[3]]$rows==length(result$markers)&&
    length(result$candidates)==c$selected_candidates,"Complete EDA exports and candidate markers disagree.")
  for(x in result$exports)brohn_require(brohn_text(x$hash,64)&&grepl("^[a-f0-9]{64}$",x$hash)&&brohn_number(x$bytes,1,128*1024^2,TRUE),"EDA exports exceed their declared byte profile.")
  expected<-lapply(input$artifacts,function(a)list(kind=a$kind,sha256=a$sha256,rows=a$rows,tables=a$tables));arrange<-function(xs)xs[base::order(vapply(xs,`[[`,character(1),"kind"))]
  brohn_require(.brohn_ecr_same(arrange(result$verification),arrange(expected))&&length(result$source_tables)==2L,"EDA review omitted complete artifact verification.")
  for(t in result$source_tables)brohn_require(.brohn_ecr_same(t$support$source,input$recording)&&.brohn_ecr_same(t$support$method,input$parameters),"The complete table lost its source support or method.")
  brohn_require(identical(sort(names(result$series)),sort(c("clean_us","tonic_us","phasic_us"))),"EDA review changed the complete processed components.")
  index_ok<-function(i)brohn_number(i,input$recording$source_row_start,input$recording$source_row_end_exclusive-1,TRUE)
  for(component in names(result$series)) {
    groups<-result$series[[component]]
    brohn_require(brohn_array(groups)&&length(groups)<=200L&&sum(vapply(groups,function(g)length(g$points),integer(1)))<=2000L&&
      sum(vapply(groups,function(g)g$source_rows,numeric(1)))==c$selected_samples,"EDA display drops support runs or exceeds its bounded sample envelope.")
    for(g in groups) {
      brohn_require(is.logical(g$retained)&&length(g$retained)==1L&&!is.na(g$retained)&&brohn_number(g$source_rows,length(g$points),500000,TRUE),"The waveform lost its retained/excluded support flag.")
      for(pt in g$points)brohn_require(brohn_number(pt$time_s,lo,hi)&&.brohn_ecr_in_window(pt$time_s,input$selection)&&brohn_number(pt$value)&&index_ok(pt$source_sample_index),"EDA plot substituted a saved sample or source index.")
      if(length(g$points)>1L)brohn_require(all(diff(vapply(g$points,`[[`,numeric(1),"time_s"))>0),"A trace cannot cross a reset or reversed source time.")
    }
  }
  seen<-vapply(result$candidates,`[[`,numeric(1),"table_row_index")
  marker_groups<-split(result$markers,vapply(result$markers,function(m)as.character(m$candidate_table_row_index),character(1)))
  for(candidate in result$candidates) {
    brohn_require(identical(candidate$type,"scr")&&candidate$recovery_fraction==.5&&index_ok(candidate$source_peak_sample)&&
      candidate$source_peak_sample==input$recording$source_row_start+candidate$peak_sample&&brohn_number(candidate$time_s)&&brohn_number(candidate$peak_height_us),"Saved EDA peak identity changed.")
    m<-marker_groups[[as.character(candidate$table_row_index)]]
    expected_kinds<-c(if(!is.null(candidate$onset_time_s))"onset","peak",if(!is.null(candidate$recovery_time_s))"recovery")
    brohn_require(identical(vapply(m,`[[`,character(1),"kind"),expected_kinds),"Missing candidate endpoints cannot become fabricated markers.")
    for(x in m){field<-switch(x$kind,onset="onset_time_s",peak="time_s",recovery="recovery_time_s")
      brohn_require(isTRUE(x$retained)&&index_ok(x$source_sample_index)&&x$time_s==candidate[[field]]&&brohn_number(x$phasic_us)&&
        identical(x$in_view,.brohn_ecr_in_window(x$time_s,input$selection)),"Candidate marker lost its exact source position or retained support.")}
    peak<-m[[which(expected_kinds=="peak")]]
    brohn_require(peak$source_sample_index==candidate$source_peak_sample&&peak$phasic_us==candidate$peak_height_us,"Saved peak differs from its source sample.")
    if("onset"%in%expected_kinds){onset<-m[[1]];brohn_require(onset$time_s<=peak$time_s&&
      isTRUE(all.equal(candidate$rise_time_s,(peak$source_sample_index-onset$source_sample_index)/input$recording$sampling_rate,tolerance=1e-12))&&
      (is.null(candidate$amplitude_us)||isTRUE(all.equal(candidate$amplitude_us,peak$phasic_us-onset$phasic_us,tolerance=1e-12))),"Saved onset amplitude or timing changed.")}else
      brohn_require(is.null(candidate$amplitude_us)&&is.null(candidate$rise_time_s),"An unavailable onset cannot supply an amplitude or rise time.")
    if("recovery"%in%expected_kinds){recovery<-m[[length(m)]];brohn_require(recovery$time_s>=peak$time_s&&
      isTRUE(all.equal(candidate$recovery_time_from_peak_s,(recovery$source_sample_index-peak$source_sample_index)/input$recording$sampling_rate,tolerance=1e-12)),"Saved recovery timing changed.")}else
      brohn_require(is.null(candidate$recovery_time_from_peak_s),"An unavailable recovery cannot supply its duration.")
    complete<-length(expected_kinds)==3L
    brohn_require(identical(candidate$missing_reason,if(complete)NULL else"onset_or_recovery_outside_retained_support")&&
      .brohn_ecr_decimal_compare(.brohn_ecr_shortest(brohn_default(candidate$onset_time_s,candidate$time_s)),input$selection$end_s)<=0&&
      .brohn_ecr_decimal_compare(.brohn_ecr_shortest(brohn_default(candidate$recovery_time_s,candidate$time_s)),input$selection$start_s)>=0,"Candidate missingness or view intersection changed.")
  }
  brohn_require(!anyDuplicated(seen)&&all(vapply(result$markers,function(m)m$candidate_table_row_index%in%seen,logical(1))),"Candidate rows or marker parents are duplicated or substituted.")
  no_paths<-function(x)!is.list(x)||(!any(names(x)%in%c("path","source_path","output_path","export_path"))&&all(vapply(x,no_paths,logical(1))))
  brohn_require(no_paths(result),"The saved review contains a private filesystem path.")
  invisible(result)
}
brohn_analyse_eda_continuous_review <- function(input,scratch) {
  directory<-file.path(scratch,"artifacts");brohn_require(dir.create(directory),"Cannot prepare eda review exports.")
  request<-input[setdiff(names(input),c("schema","operation","project_id","source_objects"))]
  request$schema<-"brohn-eda-continuous-review-request/1.0";request$export_directory<-normalizePath(directory,winslash="/")
  request_path<-file.path(scratch,"eda-continuous-review-input.json");result_path<-file.path(scratch,"eda-continuous-review-output.json");brohn_write_json_file(request,request_path)
  child<-processx::run(.brohn_publication_python(),c("scripts/workers/eda_continuous_review.py","--request",request_path,"--output",result_path),timeout=15*60,error_on_status=FALSE,cleanup_tree=TRUE,windows_hide_window=TRUE)
  brohn_require(file.exists(result_path),paste("eda review returned no result.",substr(child$stderr,1,500)))
  result<-brohn_read_json_file(result_path);brohn_require(child$status==0&&!identical(result$status,"error"),paste("eda review needs attention:",result$error$message))
  brohn_validate_eda_continuous_review(result,input);list(eda_continuous_review=result)
}
brohn_publish_eda_continuous_review <- function(store,output,scratch,job,input,output_path) {
  .brohn_publication_output_identity(output,.brohn_eda_continuous_review_loaded);.brohn_publication_job(store,job)
  guards<-brohn_hold_signal_value_sources(store,input);on.exit(for(g in guards).brohn_qexplorer_release(g),add=TRUE)
  brohn_require(.brohn_ecr_same(input,brohn_eda_continuous_review_input(store,job))&&.brohn_ecr_same(output,brohn_read_json_file(output_path)),"eda review source or child output changed before publication.")
  result<-output$report$eda_continuous_review;brohn_validate_eda_continuous_review(result,input)
  csv<-document<-NULL;committed<-FALSE
  on.exit({if(!is.null(document))brohn_close_publication(document$guard,committed);if(!is.null(csv))brohn_close_publication(csv$guard,committed)},add=TRUE)
  expected<-c("eda-samples.csv","eda-candidates.csv","eda-markers.csv")
  brohn_require(identical(vapply(result$exports,`[[`,character(1),"name"),expected),"eda review changed its complete export identities.")
  csv<-.brohn_publication_stage(store,job,lapply(result$exports,function(x)list(key=x$name,kind="eda-continuous-review-csv",path=brohn_checked_artifact_path(store,file.path(scratch,"artifacts",x$name),scratch),sha256=x$hash,bytes=x$bytes,media_type="text/csv")))
  id<-paste0("eda-continuous-review-",sub("^job[_-]","",job$id))
  body<-list(schema="brohn-saved-eda-continuous-review/1.0",id=id,report_id=input$binding$report_id,origin=input$binding$origin,request=job$request,result=result,
    exports=stats::setNames(lapply(csv$descriptors,function(x)x[c("hash","size","media_type")]),expected),created_at=brohn_now(),
    processing=list(job_id=job$id,attempt=job$attempt,code_hashes=output$code_identity,worker_output_hash=digest::digest(file=output_path,algo="sha256")))
  document<-.brohn_publication_stage_json(store,job,body,file.path(scratch,"published-eda-continuous-review.json"))
  receipt<-brohn_store_batch(store,function(){
    brohn_require(.brohn_ecr_same(input,brohn_eda_continuous_review_input(store,job,verify=FALSE)),"eda source authority changed before publication.")
    for(g in guards).Call(g$native$check,g$pointer)
    .brohn_publication_register(store,csv);body$result_object<-.brohn_publication_register(store,document)[[1L]][c("hash","size","media_type")]
    brohn_put_entity(store,"eda_continuous_review",id,body,project_id=input$project_id)
    brohn_complete_job(store,job$id,job$worker,job$token,list(eda_continuous_review_id=id,report_id=body$report_id,output_hash=body$result_object$hash))})
  committed<-TRUE;receipt
}
.brohn_ecr_predicates <- new.env(parent=emptyenv())
.brohn_ecr_validate_cached <- function(result,input) {
  # Only the pure predicate is memoized. Authority, files and native guards are
  # checked separately on every access, including on a cache hit.
  key<-digest::digest(list(result=result,input=input,implementation=.brohn_eda_continuous_review_loaded),algo="sha256",serialize=TRUE)
  if(!exists(key,envir=.brohn_ecr_predicates,inherits=FALSE)) {
    brohn_validate_eda_continuous_review(result,input)
    keys<-ls(.brohn_ecr_predicates,all.names=TRUE)
    if(length(keys)>=8L)rm(list=keys[[1L]],envir=.brohn_ecr_predicates)
    assign(key,TRUE,envir=.brohn_ecr_predicates)
  }
  invisible(result)
}
.brohn_ecr_record_source <- function(store,id,report_id,project_id) {
  r<-brohn_get_entity(store,"eda_continuous_review",id)
  brohn_require(!is.null(r)&&identical(r$body$schema,"brohn-saved-eda-continuous-review/1.0")&&identical(r$body$report_id,report_id)&&identical(r$project_id,project_id),"Open a eda review belonging to this report and project.")
  input<-brohn_eda_continuous_review_input(store,list(operation="eda_continuous_review",request=r$body$request),verify=FALSE)
  list(record=r,input=input)
}
brohn_eda_continuous_review_record <- function(store,id,report_id,project_id) {
  s<-.brohn_ecr_record_source(store,id,report_id,project_id)
  .brohn_ecr_validate_cached(s$record$body$result,s$input);s$record
}
.brohn_ecr_verify_snapshot <- function(path) {
  snapshot<-readRDS(path)
  brohn_require(.brohn_ecr_same(snapshot$body$request$implementation,.brohn_eda_continuous_review_loaded),"The background reader implementation changed.")
  for(ref in snapshot$paths)brohn_require(file.exists(ref$path)&&identical(digest::digest(file=ref$path,algo="sha256"),ref$sha256),"An EDA source or complete export changed.")
  brohn_require(.brohn_ecr_same(snapshot$body,brohn_read_json_file(snapshot$retained_path)),"The retained EDA review differs from its catalog.")
  .brohn_ecr_validate_cached(snapshot$body$result,snapshot$input)
  invisible(TRUE)
}

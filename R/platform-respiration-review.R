# Read-only derived cycle windows from complete original saved respiration evidence.
.brohn_respiration_review_loaded <- local({p<-c("R/platform-respiration-review.R","scripts/workers/respiration_review.py","scripts/workers/physiology_artifacts.py");stats::setNames(lapply(p,function(x)digest::digest(file=x,algo="sha256")),p)})
.brohn_rr_same <- function(a,b)identical(.brohn_sv_hash(a),.brohn_sv_hash(b))
brohn_respiration_review_supported <- function(report)identical(report$analysis$modality,"respiration")&&length(report$analysis$recordings)>0L&&
  any(vapply(report$analysis$parameters,function(p)identical(p$recipe,"respiration-displacement-khodadad/1.0"),logical(1)))
.brohn_rr_decimal <- function(x)brohn_text(x,80)&&grepl("^-?[0-9]+(\\.[0-9]+)?([eE][+-]?[0-9]+)?$",x)&&is.finite(suppressWarnings(as.numeric(x)))&&abs(as.numeric(x))<=1e12
.brohn_rr_shortest <- function(x) {
  for(n in 1:17){s<-sprintf(paste0("%.",n,"g"),x);if(identical(as.numeric(s),as.numeric(x)))return(s)}
  stop("Cannot retain this finite source-time representation.")
}
.brohn_rr_decimal_compare <- function(a,b) {
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
.brohn_rr_in_window <- function(time,selection) {
  text<-.brohn_rr_shortest(time)
  .brohn_rr_decimal_compare(text,selection$start_s)>=0&&.brohn_rr_decimal_compare(text,selection$end_s)<=0
}
brohn_respiration_review_selection <- function(analysis,selection) {
  brohn_fields(selection,c("recording_id","segment_id","channel","start_s","end_s"),label="Respiration cycle selection")
  identity<-selection[c("recording_id","segment_id","channel")]
  brohn_require(all(vapply(identity,brohn_text,logical(1),max=500)),"Choose one exact saved recording, continuous segment and channel.")
  brohn_require(.brohn_rr_decimal(selection$start_s)&&.brohn_rr_decimal(selection$end_s)&&as.numeric(selection$start_s)<as.numeric(selection$end_s),"Enter increasing decimal source-time bounds in seconds.")
  matches<-Filter(function(e)all(vapply(names(identity),function(k)identical(e[[k]],identity[[k]]),logical(1))),analysis$recordings)
  brohn_require(length(matches)==1L,"Choose one continuous segment from the complete saved result.")
  recording<-matches[[1L]];p<-analysis$parameters[[recording$recording_id]]
  brohn_require(identical(recording$status,"computed"),paste("This saved segment is unavailable:",brohn_default(recording$reason,"no supported processed samples")))
  brohn_require(identical(p$recipe,"respiration-displacement-khodadad/1.0")&&p$source_quantity %in% c("belt_displacement","lung_volume")&&p$polarity %in% c("positive_inspiration","negative_inspiration")&&brohn_text(p$mapping_source,10000)&&
    p$source_polarity_multiplier==if(p$polarity=="positive_inspiration")1 else -1,"The saved quantity, inspiration direction or evidence is incomplete.")
  brohn_require((p$source_quantity=="lung_volume"&&recording$unit=="L")||(p$source_quantity=="belt_displacement"&&recording$unit %in% c("a.u.","V","mV")),"The saved quantity and processed amplitude unit disagree.")
  brohn_require(brohn_number(recording$start_time_s)&&brohn_number(recording$end_time_s,recording$start_time_s)&&brohn_number(recording$sampling_rate,10,100000),"The saved continuous support and sample rate are incomplete.")
  list(recording=recording,parameters=p)
}
.brohn_rr_source <- function(store,r,verify=FALSE) {
  catalog<-.brohn_qexplorer_catalog(store,"report",r$report_id,r$report_revision,r$project_id);brohn_project(store,r$project_id)
  report<-brohn_get_entity(store,"report",r$report_id,r$report_revision)
  brohn_require(identical(.brohn_sv_hash(report$body),r$report_hash)&&identical(catalog,r$catalog_hash)&&brohn_respiration_review_supported(report$body),"The exact saved respiration report or its project authority changed.")
  a<-report$body$analysis;p<-report$body$provenance
  dataset_catalog<-.brohn_qexplorer_catalog(store,"dataset",p$dataset_id,p$dataset_revision,r$project_id)
  dataset<-brohn_get_entity(store,"dataset",p$dataset_id,p$dataset_revision)
  brohn_require(identical(p$dataset_id,report$body$dataset_id)&&identical(.brohn_sv_hash(dataset$body),p$dataset_hash)&&
    identical(dataset$body$modality,"respiration")&&.brohn_rr_same(dataset$body$metadata,p$mapping)&&.brohn_rr_same(dataset$body$source,p$source)&&
    identical(a$source$sha256,p$source$hash)&&identical(report$body$origin,dataset$body$origin)&&identical(p$origin,report$body$origin)&&identical(r$origin,report$body$origin),
    "The respiration report differs from its original dataset, mapping, source or origin.")
  if(!is.null(r$dataset_catalog_hash))brohn_require(identical(dataset_catalog,r$dataset_catalog_hash),"Original respiration dataset authority changed.")
  brohn_require(identical(report$body$id,report$id)&&identical(dataset$body$study_id,report$body$study_id),"The respiration source changed its study ownership.")
  if(is.null(report$body$study_id))brohn_require(is.null(p$design)&&is.null(p$design_hash)&&is.null(p$study_id)&&is.null(p$study_revision),"A standalone source cannot acquire an invented study.")else {
    brohn_require(identical(p$study_id,report$body$study_id)&&identical(p$design$id,report$body$study_id)&&identical(p$design$project_id,r$project_id)&&identical(brohn_hash(p$design),p$design_hash),"The saved study design differs from its source provenance.")
    .brohn_qexplorer_catalog(store,"study",p$study_id,p$study_revision,r$project_id)
    study<-brohn_get_entity(store,"study",p$study_id,p$study_revision)
    brohn_require(identical(brohn_hash(study$body),p$design_hash),"The original study revision changed.")
  }
  picked<-brohn_respiration_review_selection(a,r$selection)
  artifacts<-lapply(Filter(function(k)any(vapply(a$artifacts,function(x)identical(x$kind,k),logical(1))),c("physiology-series","physiology-events")),function(k)brohn_signal_artifact(report,k))
  brohn_require(length(artifacts)==2L,"Complete saved continuous and cycle artifacts are required; display previews cannot replace them.")
  if(!is.null(r$artifacts))brohn_require(.brohn_rr_same(artifacts,r$artifacts),"The original respiration processed artifacts changed.")
  refs<-list(list(hash=p$source$hash,bytes=p$source$size))
  retained<-.brohn_sv_retained(store,report,"report",verify)
  brohn_require(!is.null(retained),"This review requires the original retained report envelope.")
  refs<-c(refs,list(retained),lapply(artifacts,function(x)list(hash=x$sha256,bytes=x$bytes)))
  for(ref in refs)brohn_require(file.info(brohn_object_path(store,ref$hash,verify=verify))$size==ref$bytes,"An original respiration object differs from its retained byte count.")
  list(report=report,dataset=dataset,dataset_catalog_hash=dataset_catalog,artifacts=artifacts,retained=retained,source_objects=refs,picked=picked)
}
brohn_queue_respiration_review <- function(store,report_id,report_revision,report_hash,selection,retry=FALSE) {
  report<-brohn_get_entity(store,"report",report_id,report_revision)
  brohn_require(!is.null(report)&&identical(.brohn_sv_hash(report$body),report_hash),"Reopen the exact respiration report before choosing a cycle window.")
  r<-list(report_id=report_id,report_revision=report_revision,report_hash=report_hash,project_id=report$project_id,
    catalog_hash=.brohn_qexplorer_catalog(store,"report",report_id,report_revision,report$project_id),selection=selection,
    recipe="saved-respiration-cycle-review/1.0",implementation=.brohn_respiration_review_loaded,origin=report$body$origin)
  source<-.brohn_rr_source(store,r);r$dataset_catalog_hash<-source$dataset_catalog_hash;r$artifacts<-source$artifacts;r$result_object<-source$retained
  brohn_enqueue_job(store,"respiration_review",r,paste0("respiration-review:",brohn_hash(r),if(retry)paste0(":",brohn_id("retry"))else""))
}
brohn_respiration_review_input <- function(store,job,verify=TRUE) {
  r<-job$request
  brohn_fields(r,c("report_id","report_revision","report_hash","project_id","catalog_hash","selection","recipe","implementation","origin","dataset_catalog_hash","artifacts","result_object"),label="Saved respiration review request")
  brohn_require(identical(job$operation,"respiration_review")&&identical(r$recipe,"saved-respiration-cycle-review/1.0")&&.brohn_rr_same(r$implementation,.brohn_respiration_review_loaded),"Rebuild this respiration review with the current saved-result reader.")
  s<-.brohn_rr_source(store,r,verify);pick<-s$picked
  brohn_require(.brohn_rr_same(s$retained,r$result_object),"The retained report envelope changed.")
  list(schema="brohn-analysis-input/1.0",operation="respiration_review",project_id=r$project_id,binding=r,
    recording=pick$recording,parameters=pick$parameters,selection=r$selection,
    artifacts=lapply(s$artifacts,function(x)c(x,list(path=brohn_object_path(store,x$sha256,verify=FALSE)))),
    original_source=list(hash=s$dataset$body$source$hash,bytes=s$dataset$body$source$size,path=brohn_object_path(store,s$dataset$body$source$hash,verify=FALSE)),
    sealed_objects=list(c(s$retained,list(path=brohn_object_path(store,s$retained$hash,verify=FALSE)))),source_objects=s$source_objects)
}
brohn_validate_respiration_review <- function(result,input) {
  brohn_require(identical(result$schema,"brohn-respiration-review/1.0")&&result$status %in% c("available","no_processed_samples")&&
    .brohn_rr_same(result$binding,input$binding)&&.brohn_rr_same(result$selection,input$selection)&&.brohn_rr_same(result$recording,input$recording)&&
    .brohn_rr_same(result$parameters,input$parameters)&&identical(result$unit,input$recording$unit),"Respiration review substituted its original source, support or parameters.")
  c<-result$counts;lo<-as.numeric(input$selection$start_s);hi<-as.numeric(input$selection$end_s)
  brohn_require(brohn_number(c$selected_samples,0,500000,TRUE)&&brohn_number(c$selected_cycles,0,5000,TRUE)&&
    c$retained_samples+c$excluded_samples==c$selected_samples&&brohn_number(c$retained_samples,0,c$selected_samples,TRUE)&&brohn_number(c$excluded_samples,0,c$selected_samples,TRUE)&&
    c$segment_samples==input$recording$samples&&c$segment_cycles==input$recording$complete_cycle_count&&c$segment_samples>=c$selected_samples&&c$segment_cycles>=c$selected_cycles&&
    c$complete_sample_artifact_rows>=c$segment_samples&&c$complete_event_artifact_rows>=c$segment_cycles&&length(result$rows)==min(50,c$selected_samples)&&
    identical(result$status,if(c$selected_samples>0)"available"else"no_processed_samples"),"Complete respiration support and window counts do not reconcile.")
  brohn_require(length(result$exports)==3L&&identical(vapply(result$exports,`[[`,character(1),"name"),c("respiration-samples.csv","respiration-cycles.csv","respiration-markers.csv"))&&
    result$exports[[1]]$rows==c$selected_samples&&result$exports[[2]]$rows==c$selected_cycles&&result$exports[[3]]$rows==length(result$markers)&&
    length(result$cycles)==c$selected_cycles&&length(result$markers)==3L*c$selected_cycles,"Complete respiration exports and saved boundary counts disagree.")
  for(x in result$exports)brohn_require(brohn_text(x$hash,64)&&grepl("^[a-f0-9]{64}$",x$hash)&&brohn_number(x$bytes,1,128*1024^2,TRUE),"Respiration exports exceed their declared byte profile.")
  expected<-lapply(input$artifacts,function(a)list(kind=a$kind,sha256=a$sha256,rows=a$rows,tables=a$tables));arrange<-function(xs)xs[base::order(vapply(xs,`[[`,character(1),"kind"))]
  brohn_require(.brohn_rr_same(arrange(result$verification),arrange(expected))&&length(result$source_tables)==2L,"Respiration review omitted complete artifact verification.")
  for(t in result$source_tables)brohn_require(.brohn_rr_same(t$support$source,input$recording)&&.brohn_rr_same(t$support$method,input$parameters),"The selected complete table lost its source support or method.")
  groups<-result$series
  brohn_require(brohn_array(groups)&&length(groups)<=200L&&sum(vapply(groups,function(g)length(g$points),integer(1)))<=2000L&&
    sum(vapply(groups,function(g)g$source_rows,numeric(1)))==c$selected_samples,"Respiration display drops support runs or exceeds its bounded sample envelope.")
  index_ok<-function(i)brohn_number(i,input$recording$source_row_start,input$recording$source_row_end_exclusive-1,TRUE)
  for(g in groups) {
    brohn_require(is.logical(g$retained)&&length(g$retained)==1L&&!is.na(g$retained)&&brohn_number(g$source_rows,length(g$points),500000,TRUE),"The waveform lost its retained/excluded support flag.")
    for(pt in g$points)brohn_require(brohn_number(pt$time_s,lo,hi)&&.brohn_rr_in_window(pt$time_s,input$selection)&&brohn_number(pt$clean)&&index_ok(pt$source_sample_index),"Respiration plot substituted a saved sample or index.")
    if(length(g$points)>1L)brohn_require(all(diff(vapply(g$points,`[[`,numeric(1),"time_s"))>0),"A trace cannot cross a reset or reversed source time.")
  }
  for(i in seq_along(result$cycles)) {
    cycle<-result$cycles[[i]];m<-result$markers[seq.int(3*i-2,3*i)];times<-vapply(m,`[[`,numeric(1),"time_s");indices<-vapply(m,`[[`,numeric(1),"source_sample_index")
    brohn_require(identical(vapply(m,`[[`,character(1),"kind"),c("inspiration_start","expiration_start","cycle_end"))&&
      identical(cycle$type,"respiration_cycle")&&all(diff(times)>0)&&all(diff(indices)>0)&&all(vapply(as.list(indices),index_ok,logical(1)))&&
      all(vapply(m,function(x)isTRUE(x$retained)&&x$cycle_table_row_index==cycle$table_row_index&&identical(x$in_view,.brohn_rr_in_window(x$time_s,input$selection)),logical(1)))&&
      isTRUE(all.equal(times,c(cycle$time_s,cycle$peak_time_s,cycle$end_time_s),tolerance=1e-12))&&cycle$time_s<=hi&&cycle$end_time_s>=lo,
      "Saved extrema lost exact source positions, order or retained support.")
    expected<-c((indices[[3]]-indices[[1]])/input$recording$sampling_rate,diff(indices)/input$recording$sampling_rate,m[[2]]$clean-m[[1]]$clean)
    brohn_require(isTRUE(all.equal(unlist(cycle[c("duration_s","inspiration_s","expiration_s","amplitude")]),expected,check.attributes=FALSE,tolerance=1e-12)),"Saved phase durations or amplitude differ from their original extrema.")
  }
  no_paths<-function(x)!is.list(x)||(!any(names(x)%in%c("path","source_path","output_path","export_path"))&&all(vapply(x,no_paths,logical(1))))
  brohn_require(no_paths(result),"The saved review contains a private filesystem path.")
  invisible(result)
}
brohn_analyse_respiration_review <- function(input,scratch) {
  directory<-file.path(scratch,"artifacts");brohn_require(dir.create(directory),"Cannot prepare respiration review exports.")
  request<-input[setdiff(names(input),c("schema","operation","project_id","source_objects"))]
  request$schema<-"brohn-respiration-review-request/1.0";request$export_directory<-normalizePath(directory,winslash="/")
  request_path<-file.path(scratch,"respiration-review-input.json");result_path<-file.path(scratch,"respiration-review-output.json");brohn_write_json_file(request,request_path)
  child<-processx::run(.brohn_publication_python(),c("scripts/workers/respiration_review.py","--request",request_path,"--output",result_path),timeout=15*60,error_on_status=FALSE,cleanup_tree=TRUE,windows_hide_window=TRUE)
  brohn_require(file.exists(result_path),paste("respiration review returned no result.",substr(child$stderr,1,500)))
  result<-brohn_read_json_file(result_path);brohn_require(child$status==0&&!identical(result$status,"error"),paste("respiration review needs attention:",result$error$message))
  brohn_validate_respiration_review(result,input);list(respiration_review=result)
}
brohn_publish_respiration_review <- function(store,output,scratch,job,input,output_path) {
  .brohn_publication_output_identity(output,.brohn_respiration_review_loaded);.brohn_publication_job(store,job)
  guards<-brohn_hold_signal_value_sources(store,input);on.exit(for(g in guards).brohn_qexplorer_release(g),add=TRUE)
  brohn_require(.brohn_rr_same(input,brohn_respiration_review_input(store,job))&&.brohn_rr_same(output,brohn_read_json_file(output_path)),"respiration review source or child output changed before publication.")
  result<-output$report$respiration_review;brohn_validate_respiration_review(result,input)
  csv<-document<-NULL;committed<-FALSE
  on.exit({if(!is.null(document))brohn_close_publication(document$guard,committed);if(!is.null(csv))brohn_close_publication(csv$guard,committed)},add=TRUE)
  expected<-c("respiration-samples.csv","respiration-cycles.csv","respiration-markers.csv")
  brohn_require(identical(vapply(result$exports,`[[`,character(1),"name"),expected),"respiration review changed its complete export identities.")
  csv<-.brohn_publication_stage(store,job,lapply(result$exports,function(x)list(key=x$name,kind="respiration-review-csv",path=brohn_checked_artifact_path(store,file.path(scratch,"artifacts",x$name),scratch),sha256=x$hash,bytes=x$bytes,media_type="text/csv")))
  id<-paste0("respiration-review-",sub("^job[_-]","",job$id))
  body<-list(schema="brohn-saved-respiration-review/1.0",id=id,report_id=input$binding$report_id,origin=input$binding$origin,request=job$request,result=result,
    exports=stats::setNames(lapply(csv$descriptors,function(x)x[c("hash","size","media_type")]),expected),created_at=brohn_now(),
    processing=list(job_id=job$id,attempt=job$attempt,code_hashes=output$code_identity,worker_output_hash=digest::digest(file=output_path,algo="sha256")))
  document<-.brohn_publication_stage_json(store,job,body,file.path(scratch,"published-respiration-review.json"))
  receipt<-brohn_store_batch(store,function(){
    brohn_require(.brohn_rr_same(input,brohn_respiration_review_input(store,job,verify=FALSE)),"respiration source authority changed before publication.")
    for(g in guards).Call(g$native$check,g$pointer)
    .brohn_publication_register(store,csv);body$result_object<-.brohn_publication_register(store,document)[[1L]][c("hash","size","media_type")]
    brohn_put_entity(store,"respiration_review",id,body,project_id=input$project_id)
    brohn_complete_job(store,job$id,job$worker,job$token,list(respiration_review_id=id,report_id=body$report_id,output_hash=body$result_object$hash))})
  committed<-TRUE;receipt
}
brohn_respiration_review_record <- function(store,id,report_id,project_id) {
  r<-brohn_get_entity(store,"respiration_review",id)
  brohn_require(!is.null(r)&&identical(r$body$schema,"brohn-saved-respiration-review/1.0")&&identical(r$body$report_id,report_id)&&identical(r$project_id,project_id),"Open a respiration review belonging to this report and project.")
  input<-brohn_respiration_review_input(store,list(operation="respiration_review",request=r$body$request),verify=FALSE)
  brohn_validate_respiration_review(r$body$result,input);r
}

# Actual source-bound exclusion jobs from retained, unchanged public-reference inputs.
args<-commandArgs(trailingOnly=TRUE);stopifnot(length(args)==2L)
source("R/platform-load.R",encoding="UTF-8");brohn_load()
local({
  reference<-normalizePath(args[[1]],winslash="/",mustWork=TRUE)
  root<-normalizePath(args[[2]],winslash="/",mustWork=FALSE)
  stopifnot(startsWith(basename(root),"brohn-cardiac-review-"),!dir.exists(root))
  dir.create(root,recursive=TRUE);dir.create(file.path(root,"workspace"))
  files<-list.files(file.path(reference,"workspace"),full.names=TRUE,all.files=TRUE,no..=TRUE)
  stopifnot(all(file.copy(files,file.path(root,"workspace"),recursive=TRUE)))
  original<-brohn_read_json_file(file.path(reference,"acceptance.json"))
  store<-brohn_open_store(file.path(root,"workspace"));on.exit(brohn_close_store(store),add=TRUE)
  checks<-character();jobs<-list();saved<-list()
  check<-function(name,value){if(!isTRUE(value))stop("Cardiac review QA: ",name,call.=FALSE);checks<<-c(checks,name);cat("PASS ",name,"\n",sep="")}
  rejects<-function(x)inherits(try(force(x),silent=TRUE),"try-error")
  run_job<-function(q,success=TRUE){force(q);claim<-brohn_claim_job(store,"cardiac-review-qa",180);stopifnot(claim$id==q$id)
    brohn_process_job(store,claim,timeout_seconds=300);done<-brohn_get_job(store,q$id);jobs[[length(jobs)+1L]]<<-done
    if(success&&done$status!="succeeded")stop(brohn_json(done$error))
    if(!success)return(done)
    type<-if(q$operation=="reanalyse_cardiac")"report"else"cardiac_review_preview"
    brohn_get_entity(store,type,done$result[[if(type=="report")"report_id"else"cardiac_preview_id"]])}
  for(modality in c("ecg","ppg")) {
    ref<-original$reports[[modality]];parent<-brohn_get_entity(store,"report",ref$report_id)
    catalog<-brohn_get_entity(store,"signal_view",ref$catalog_id);table<-catalog$body$view$tables[[1]]
    review<-brohn_create_cardiac_review(store,catalog$id,table$table_id,paste(toupper(modality),"reference artifact review"))
    check(paste(modality,"review pins exact original table, source and unqualified local attribution"),
      review$body$report_hash==ref$report_hash&&brohn_hash(review$body$table)==brohn_hash(table)&&grepl("no authenticated",review$body$review_attribution))
    q<-brohn_queue_cardiac_review(store,review$id,review$revision,brohn_hash(review$body))
    check(paste(modality,"preview request deduplicates exact frozen source"),brohn_queue_cardiac_review(store,review$id,review$revision,brohn_hash(review$body))$id==q$id)
    preview<-run_job(q)
    check(paste(modality,"actual preview includes all input edge support without recalculation"),
      preview$body$preview$input_preview$complete_samples==table$rows&&preview$body$preview$ledger$support$excluded_samples==0&&
      "parent_filter_edge"%in%vapply(preview$body$preview$input_preview$fragments,`[[`,character(1),"status"))
    check(paste(modality,"empty exclusion cannot calculate a report"),rejects(brohn_queue_cardiac_review(store,review$id,review$revision,brohn_hash(review$body),preview$id)))
    resolved<-run_job(brohn_queue_cardiac_resolution(store,review$id,review$revision,brohn_hash(review$body),"20.30001","22.70001","movement_or_distortion","Known regression interval, not a physiological annotation"))
    candidate<-resolved$body$preview$resolved_exclusion
    check(paste(modality,"typed time preview preserves decimal request and exact original samples"),candidate$candidate$start_time_s_text=="20.30001"&&
      candidate$samples==candidate$span$end_sample-candidate$span$start_sample&&candidate$first_time_s>=20.30001&&candidate$last_time_s<22.70001)
    check(paste(modality,"candidate preview cannot authorize an unsaved recalculation"),rejects(brohn_queue_cardiac_review(store,review$id,review$revision,brohn_hash(review$body),resolved$id)))
    old<-review;review<-brohn_accept_cardiac_resolution(store,resolved$id,review$revision)
    check(paste(modality,"saving preserves exact resolved identity and canonical membership"),brohn_hash(review$body$spans[[1]])==brohn_hash(candidate$span))
    check(paste(modality,"stale resolution and stale writes are refused"),rejects(brohn_accept_cardiac_resolution(store,resolved$id,old$revision))&&
      rejects(brohn_save_cardiac_span(store,review$id,old$revision,30,50,"clipping")))
    check(paste(modality,"fractional and out-of-range masks are refused"),rejects(brohn_save_cardiac_span(store,review$id,review$revision,30.5,50,"clipping"))&&
      rejects(brohn_save_cardiac_span(store,review$id,review$revision,0,table$rows+1,"clipping")))
    preview<-run_job(brohn_queue_cardiac_review(store,review$id,review$revision,brohn_hash(review$body)))
    check(paste(modality,"saved preview reconciles exact excluded support and separate runs"),preview$body$preview$ledger$support$excluded_samples==candidate$samples&&length(preview$body$preview$ledger$runs)==2L)
    # Independently attempt a write while the parent's native source read guards
    # are held throughout final publication. Permission denial is the expected
    # Windows guarantee, not a post-hoc hash comparison.
    original_prepare<-brohn_prepare_publication;blocked<-FALSE
    source_path<-brohn_object_path(store,parent$body$provenance$source$hash)
    # Registered files are ordinarily read-only. Clear that attribute only in
    # this isolated copied fixture, so denial proves the native source guard.
    Sys.chmod(source_path,"0666")
    open_without_writing<-function()processx::run(brohn_python_profile("ecg"),
      c("-c","import sys; f=open(sys.argv[1],'r+b'); f.close()",source_path),
      error_on_status=FALSE,windows_hide_window=TRUE)$status==0L
    check(paste(modality,"non-mutating write-open succeeds before the native guard"),open_without_writing())
    assign("brohn_prepare_publication",function(...) {
      probe<-processx::run(brohn_python_profile("ecg"),c("-c","import sys; f=open(sys.argv[1],'r+b'); f.close()",source_path),
        error_on_status=FALSE,windows_hide_window=TRUE)
      blocked<<-probe$status!=0L&&grepl("PermissionError",probe$stderr)
      original_prepare(...)
    },envir=.GlobalEnv)
    report<-tryCatch(run_job(brohn_queue_cardiac_review(store,review$id,review$revision,brohn_hash(review$body),preview$id)),
      error=function(e){Sys.chmod(source_path,"0444");stop(e)},
      finally=assign("brohn_prepare_publication",original_prepare,envir=.GlobalEnv))
    check(paste(modality,"original bytes are read-sealed through actual report publication"),blocked)
    released<-open_without_writing();Sys.chmod(source_path,"0444")
    check(paste(modality,"native guard releases after publication without changing bytes"),released&&
      digest::digest(file=source_path,algo="sha256")==parent$body$provenance$source$hash)
    a<-report$body$analysis
    check(paste(modality,"actual separate report retains parent and exact reviewed ledger"),brohn_hash(a$exclusion_review)==brohn_hash(preview$body$preview$ledger)&&
      report$body$provenance$cardiac_review$parent_report$hash==ref$report_hash&&length(a$recordings)==2L)
    check(paste(modality,"new report remains unqualified per-run detected intervals"),!a$quality$scientifically_qualified&&!a$quality$normal_to_normal_confirmed&&
      all(vapply(a$recordings,function(r)r$source_row_end_exclusive<=candidate$span$start_sample||r$source_row_start>=candidate$span$end_sample,logical(1))))
    check(paste(modality,"opening and recalculating preserve original report and input bytes"),brohn_hash(brohn_get_entity(store,"report",parent$id)$body)==ref$report_hash&&
      digest::digest(file=source_path,algo="sha256")==parent$body$provenance$source$hash)
    before<-review;review<-brohn_remove_cardiac_span(store,review$id,review$revision,candidate$span$id)
    review<-brohn_restore_cardiac_review(store,review$id,review$revision,before$revision,brohn_hash(before$body))
    check(paste(modality,"undo preserves history through a new version"),review$revision==before$revision+2L&&brohn_hash(review$body$spans)==brohn_hash(before$body$spans))
    q<-brohn_queue_cardiac_review(store,review$id,review$revision,brohn_hash(review$body));brohn_cancel_job(store,q$id)
    retry<-brohn_retry_processing(store,q$id);again<-run_job(retry)
    check(paste(modality,"cancel and retry preserve original frozen review"),brohn_get_job(store,q$id)$status=="cancelled"&&
      brohn_hash(retry$request)==brohn_hash(q$request)&&again$body$review_source$hash==brohn_hash(review$body))
    saved[[modality]]<-list(review_id=review$id,review_revision=review$revision,preview_id=again$id,report_id=report$id,report_hash=brohn_hash(report$body),
      parent_report_id=parent$id,catalog_id=catalog$id,table_id=table$table_id)
  }
  brohn_close_store(store);store<-brohn_open_store(file.path(root,"workspace"))
  for(m in names(saved))check(paste(m,"review and new report reopen exactly"),brohn_cardiac_review(store,saved[[m]]$review_id)$revision==saved[[m]]$review_revision&&
    brohn_hash(brohn_get_entity(store,"report",saved[[m]]$report_id)$body)==saved[[m]]$report_hash)
  brohn_write_json_file(list(checks=checks,jobs=jobs,workspace=store$root,saved=saved,reference_inputs=reference,
    interpretation="known regression sources; no detector accuracy, hardware or artifact-label qualification"),file.path(root,"acceptance.json"))
  cat(length(checks),"checks and",length(jobs),"supervised jobs passed\n")
})

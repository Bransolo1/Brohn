# Independent actual import -> curation -> cardiac exclusion authority acceptance.
# Explicit output retains evidence; no argument uses R's external session temp
# directory, which R removes at session exit. No existing workspace is reused.
args<-commandArgs(trailingOnly=TRUE);stopifnot(length(args)%in%c(0L,1L))
source("R/platform-load.R",encoding="UTF-8");brohn_load(ui=FALSE)
local({
  root<-normalizePath(if(length(args))args[[1]]else tempfile("brohn-cardiac-curation-"),winslash="/",mustWork=FALSE)
  stopifnot(startsWith(basename(root),"brohn-cardiac-curation-"),!dir.exists(root))
  dir.create(root,recursive=TRUE)
  store<-brohn_open_store(file.path(root,"workspace"));brohn_initialise_library(store)
  on.exit(brohn_close_store(store),add=TRUE)
  checks<-character();jobs<-list();write_denials<-list();test_writable_paths<-character();completed<-FALSE
  on.exit({for(p in test_writable_paths)if(file.exists(p))Sys.chmod(p,"0444")
    brohn_write_json_file(list(completed=completed,checks=checks,jobs=jobs,write_denials=write_denials),file.path(root,"progress.json"))},add=TRUE)
  check<-function(name,value){if(!isTRUE(value))stop("Curated cardiac QA: ",name,call.=FALSE);checks<<-c(checks,name);cat("PASS ",name,"\n",sep="")}
  rejects<-function(x)inherits(try(force(x),silent=TRUE),"try-error")
  run_job<-function(q,success=TRUE){force(q);claim<-brohn_claim_job(store,"curated-cardiac-peer",180);stopifnot(claim$id==q$id)
    brohn_process_job(store,claim,timeout_seconds=300);done<-brohn_get_job(store,q$id);jobs[[length(jobs)+1L]]<<-done
    if(success&&done$status!="succeeded")stop(brohn_json(done$error));done}
  code<-paste(c("import json,math,sys; from pathlib import Path",
    "rows=[]; missing={0,1,2,2003,2004,2105,8008}",
    "for i in range(8009):",
    " first=i<2003; local=i if first else i-2003; epoch=9007199254740993 if first else 999999999999999999123",
    " value=math.sin(2*math.pi*1.2*local/100)+.2*math.sin(2*math.pi*2.4*local/100)",
    " rows.append({'timestamp':str(epoch+local*10000000),'values':[None if i in missing else value],'clock_id':'clock-a' if first else 'clock-b','identity':{'participant_id':'person-a' if first else 'person-\\u03b2','session_id':'visit-a' if first else 'visit-b'}})",
    "stream={'id':'original-ppg','name':'Original pulse generator','type':'PPG','kind':'signal','source_id':'original-generator','uid':'original-generator-uid','clock':{'id':'clock-a','unit':'ns','kind':'device','representation':'decimal_string'},'nominal_srate':100,'channels':[{'id':'pulse','label':'Original pulse generator','type':'PPG','unit':'a.u.','value_type':'float64'}],'samples':rows}",
    "Path(sys.argv[1]).write_text(json.dumps({'schema':'brohn-stream-bundle/1.0','origin':'sample','streams':[stream]},ensure_ascii=True),encoding='utf-8')"),collapse="\n")
  raw_path<-file.path(root,"original-ppg.json")
  processx::run(.brohn_port_python(),c("-B","-c",code,raw_path),windows_hide_window=TRUE)
  raw<-brohn_ingest_dataset(store,raw_path,"Original omitted-row pulse fixture",modality="multimodal",origin="sample")
  raw<-brohn_curate_dataset(store,raw$id,list(origin_statement="Original synthetic waveform with two explicit people, clocks and missing rows; no acquired device.",clock_policy="preserve_only"),raw$revision)
  imported<-run_job(brohn_queue_multistream(store,raw$id))
  stream<-brohn_streams(store,import_id=imported$result$import_id)[[1L]]
  selection<-list(schema="brohn-stream-selection/1.0",channel_ids=list("pulse"),modality="ppg",unit="a.u.",sampling_rate=100,
    participant_id=NULL,session_id=NULL,origin_statement="Preserve the original generator person and session identities.",
    unit_rationale="The original generator explicitly declares arbitrary amplitude units.",confirm_source_units=TRUE,confirm_boundaries=TRUE,run_analysis=TRUE)
  extracted<-run_job(brohn_queue_stream_curation(store,stream$id,selection))
  curation<-brohn_get_entity(store,"stream_curation",extracted$result$curation_id)
  dataset<-brohn_get_entity(store,"dataset",extracted$result$dataset_id)
  check("real importer and extractor retain all 8009 decisions and exactly 8002 included rows",curation$body$extraction$quality$source_rows==8009&&
    curation$body$extraction$quality$included_rows==8002&&curation$body$extraction$quality$excluded_rows==7)
  analysed<-run_job(brohn_get_job(store,extracted$result$analysis_job_id))
  parent<-brohn_get_entity(store,"report",analysed$result$report_id);parent_hash<-brohn_hash(parent$body)
  catalog_done<-run_job(brohn_queue_signal_view(store,parent$id,"physiology-series"))
  catalog<-brohn_get_entity(store,"signal_view",catalog_done$result$signal_view_id)
  table<-Filter(function(t)t$support$source$source_row_start==2100,catalog$body$view$tables)[[1L]]
  check("catalog preserves selected person and nonzero derived-row table",table$support$source$source_row_end_exclusive==8002&&
    table$identity$group$participant_id=="person-\u03b2"&&table$identity$group$session_id=="visit-b")
  review<-brohn_create_cardiac_review(store,catalog$id,table$table_id,"Curated source review")
  review<-brohn_save_cardiac_span(store,review$id,review$revision,4100,4400,"researcher_exclusion","Original regression interval; no expert artifact classification.")
  q<-brohn_queue_cardiac_review(store,review$id,review$revision,brohn_hash(review$body))
  input<-brohn_cardiac_review_input(store,q)
  hashes<-unique(vapply(input$source_objects,`[[`,character(1),"hash"))
  check("guard list covers source CSV, complete parent, decisions and every original acquisition object",length(hashes)>=6L&&
    all(c(raw$body$source$hash,input$artifact$sha256,dataset$body$source$hash,input$curation$decisions$sha256,
      input$curation$lineage$canonical_hash,vapply(input$curation$lineage$original_stream_artifacts,`[[`,character(1),"hash"))%in%hashes))
  # Remove the ordinary read-only attribute in this isolated test workspace so a
  # denial actually demonstrates native sharing exclusion, not file permissions.
  test_writable_paths<-vapply(hashes,function(h)brohn_object_path(store,h),character(1))
  for(p in test_writable_paths)Sys.chmod(p,"0666")
  open_without_writing<-function()processx::run(.brohn_port_python(),c("-c",
    "import sys; handles=[open(p,'r+b') for p in sys.argv[1:]]; [h.close() for h in handles]",test_writable_paths),
    error_on_status=FALSE,windows_hide_window=TRUE)$status==0L
  check("all guarded objects allow non-mutating write-open before processing",open_without_writing())
  original_prepare<-brohn_prepare_publication
  assign("brohn_prepare_publication",function(...) {
    for(h in hashes){probe<-processx::run(.brohn_port_python(),c("-c","import sys; f=open(sys.argv[1],'r+b'); f.close()",brohn_object_path(store,h)),
      error_on_status=FALSE,windows_hide_window=TRUE);write_denials[[h]]<<-probe$status!=0L&&grepl("PermissionError",probe$stderr)}
    original_prepare(...)
  },envir=.GlobalEnv)
  preview_done<-tryCatch(run_job(q),finally=assign("brohn_prepare_publication",original_prepare,envir=.GlobalEnv))
  preview<-brohn_get_entity(store,"cardiac_review_preview",preview_done$result$cardiac_preview_id);ledger<-preview$body$preview$ledger
  check("all original, derived and parent objects reject concurrent write access during publication",length(write_denials)==length(hashes)&&all(unlist(write_denials)))
  check("all native source guards release when the actual job returns",open_without_writing())
  for(p in test_writable_paths)Sys.chmod(p,"0444")
  check("actual saved preview authenticates complete curation and exact original nanosecond endpoint",ledger$curation$curation_id==curation$id&&
    ledger$curation$curation_revision==curation$revision&&ledger$curation$curation_hash==brohn_hash(curation$body)&&
    ledger$curation$selected_first$source_sample_index==2100&&ledger$curation$selected_first$source_sequence==2107&&
    ledger$curation$selected_first$source_timestamp=="1000000000001029999123"&&ledger$curation$selected_first$source_clock_id=="clock-b"&&
    ledger$curation$selected_first$source_identity$participant_id=="person-\u03b2")
  rq<-brohn_queue_cardiac_review(store,review$id,review$revision,brohn_hash(review$body),preview$id)
  # Change only current project authority, retaining each original immutable version.
  # The surrounding transaction deliberately rolls each independent adversarial case back.
  authorities<-list(c("stream",stream$id),c("stream_import",imported$result$import_id),c("dataset",raw$id),
    c("stream_curation",curation$id),c("dataset",dataset$id),c("report",parent$id),c("signal_view",catalog$id),
    c("cardiac_review",review$id),c("cardiac_review_preview",preview$id))
  for(binding in authorities){refused<-FALSE
    try(brohn_store_batch(store,function(){current<-brohn_get_entity(store,binding[[1]],binding[[2]])
      brohn_put_entity(store,binding[[1]],binding[[2]],current$body,current$revision,project_id="foreign-project")
      refused<<-rejects(brohn_cardiac_review_input(store,rq));stop("Intentional isolated probe rollback")}),silent=TRUE)
    check(paste("current authority revocation refuses",binding[[1]],binding[[2]]),refused)}
  result_done<-run_job(rq);report<-brohn_get_entity(store,"report",result_done$result$report_id)
  check("actual recalculation preserves exact preview ledger and separate surviving source runs",brohn_hash(report$body$analysis$exclusion_review)==brohn_hash(ledger)&&
    length(report$body$analysis$recordings)==2L&&report$body$analysis$recordings[[1]]$source_row_start==2100&&
    report$body$analysis$recordings[[1]]$source_row_end_exclusive==4100&&report$body$analysis$recordings[[2]]$source_row_start==4400&&
    report$body$analysis$recordings[[2]]$source_row_end_exclusive==8002&&!report$body$analysis$quality$normal_to_normal_confirmed)
  old_review<-review;review<-brohn_save_cardiac_span(store,review$id,review$revision,4200,4500,"clipping","",review$body$spans[[1]]$id)
  check("old preview cannot authorize newly saved exclusion bounds",rejects(brohn_queue_cardiac_review(store,review$id,review$revision,brohn_hash(review$body),preview$id)))
  q<-brohn_queue_cardiac_review(store,review$id,review$revision,brohn_hash(review$body))
  before_count<-length(brohn_list_entities(store,"cardiac_review_preview"));before_objects<-DBI::dbGetQuery(store$con,"SELECT COUNT(*) AS n FROM objects")$n[[1L]]
  changed<-FALSE
  assign("brohn_prepare_publication",function(...) {
    prepared<-original_prepare(...);current<-brohn_get_entity(store,"stream",stream$id)
    brohn_put_entity(store,"stream",stream$id,current$body,current$revision,project_id="foreign-project");changed<<-TRUE;prepared
  },envir=.GlobalEnv)
  failed<-tryCatch(run_job(q,FALSE),finally=assign("brohn_prepare_publication",original_prepare,envir=.GlobalEnv))
  check("authority revoked after preparation refuses final commit and completion receipt",changed&&failed$status=="failed"&&is.null(failed$result)&&
    grepl("curation lineage.*changed project",failed$error$message)&&
    length(brohn_list_entities(store,"cardiac_review_preview"))==before_count&&DBI::dbGetQuery(store$con,"SELECT COUNT(*) AS n FROM objects")$n[[1L]]==before_objects)
  current<-brohn_get_entity(store,"stream",stream$id)
  brohn_put_entity(store,"stream",stream$id,current$body,current$revision,project_id="default")
  retried<-run_job(brohn_retry_processing(store,q$id))
  check("restored authority permits retry of the exact frozen review",brohn_hash(brohn_get_entity(store,"cardiac_review_preview",retried$result$cardiac_preview_id)$body$review_source)==
    brohn_hash(list(id=review$id,revision=review$revision,hash=brohn_hash(review$body))))
  # Same-size corruption probes run only after every guard is closed, in this owned workspace.
  for(h in unique(c(input$curation$decisions$sha256,input$curation$lineage$canonical_hash))) {
    path<-brohn_object_path(store,h);bytes<-readBin(path,"raw",n=file.info(path)$size);bad<-bytes;bad[[1]]<-as.raw(bitwXor(as.integer(bad[[1]]),1L))
    Sys.chmod(path,"0666")
    con<-file(path,"wb");writeBin(bad,con);close(con)
    refused<-tryCatch(rejects(brohn_queue_cardiac_review(store,review$id,review$revision,brohn_hash(review$body))),finally={con<-file(path,"wb");writeBin(bytes,con);close(con);Sys.chmod(path,"0444")})
    check(paste("same-size original curation object corruption is refused",h),refused)
  }
  check("original report and every acquisition object remain byte-exact",brohn_hash(brohn_get_entity(store,"report",parent$id)$body)==parent_hash&&
    all(vapply(hashes,function(h)digest::digest(file=brohn_object_path(store,h),algo="sha256")==h,logical(1))))
  saved_hash<-brohn_hash(report$body);brohn_close_store(store);store<-brohn_open_store(file.path(root,"workspace"))
  check("source-bound review and separate report reopen unchanged",brohn_cardiac_review(store,review$id)$revision==review$revision&&
    brohn_hash(brohn_get_entity(store,"report",report$id)$body)==saved_hash)
  brohn_write_json_file(list(checks=checks,jobs=jobs,write_denials=write_denials,workspace=store$root,
    saved=list(review_id=review$id,review_revision=review$revision,parent_report_id=parent$id,report_id=report$id,preview_id=preview$id,
      dataset_id=dataset$id,curation_id=curation$id),interpretation="Synthetic source and authority acceptance only; no detector, expert artifact, hardware or NN qualification."),file.path(root,"acceptance.json"))
  completed<-TRUE;cat(length(checks),"checks across",length(jobs),"supervised jobs passed\n")
})

# Public reference bytes remain outside the source repository. This tests saved
# review/display fidelity, not detector accuracy (the comparison remains failed).
args<-commandArgs(trailingOnly=TRUE);stopifnot(length(args)==2L)
source("R/platform-load.R",encoding="UTF-8");brohn_load()
local({
  reference<-normalizePath(args[[1L]],winslash="/",mustWork=TRUE)
  evidence<-normalizePath(args[[2L]],winslash="/",mustWork=FALSE)
  repository<-normalizePath(".",winslash="/",mustWork=TRUE)
  stopifnot(!startsWith(tolower(evidence),paste0(tolower(repository),"/")),startsWith(basename(evidence),"brohn-cardiac-reference-"))
  dir.create(evidence,recursive=TRUE,showWarnings=FALSE);checks<-0L
  check<-function(name,value){if(!isTRUE(value))stop("Recorded ECG review: ",name,call.=FALSE);checks<<-checks+1L}
  store<-brohn_open_store(file.path(evidence,"workspace"));on.exit(brohn_close_store(store),add=TRUE);brohn_initialise_library(store)
  original<-file.path(reference,"108","reference-ecg.csv");comparison<-brohn_read_json_file(file.path(reference,"108","agreement.json"))
  stopifnot(identical(.brohn_store_hash(original,file=TRUE),comparison$prepared_csv_sha256),identical(.brohn_store_hash("scripts/workers/physiology.py",file=TRUE),comparison$worker_sha256))
  run_job<-function(queued,type){force(queued);claim<-brohn_claim_job(store,"recorded-cardiac-review",120);stopifnot(claim$id==queued$id)
    brohn_process_job(store,claim,timeout_seconds=120);job<-brohn_get_job(store,queued$id)
    if(job$status!="succeeded")stop(brohn_json(job$error))
    brohn_get_entity(store,type,job$result[[if(type=="report")"report_id"else"signal_view_id"]])}
  source<-brohn_ingest_dataset(store,original,"MIT-BIH record 108 - published reference ECG",modality="ecg",origin="imported")
  mapping<-list(time_column="seconds",time_unit="s",sampling_rate=360,value_columns=list("ecg_mv"),unit="mV",origin="imported",
    origin_statement="Published MIT-BIH Arrhythmia Database1.0.0 record108 first300s MLII. Moody/Mark2001, PhysioNet DOI10.13026/C2F305, ODC Attribution1.0. Original reference data, not a new participant or device test.",
    parameters=list(powerline_hz=60,edge_exclusion_s=2))
  dataset<-brohn_curate_dataset(store,source$id,mapping,source$revision)
  report<-run_job(brohn_queue_dataset(store,dataset$id),"report");before<-brohn_hash(report$body)
  check("actual imported report preserves reference source",report$body$origin=="imported"&&brohn_get_entity(store,"dataset",dataset$id)$body$source$hash==comparison$prepared_csv_sha256)
  check("production detector and unqualified status unchanged",report$body$analysis$engine$worker_sha256==comparison$worker_sha256&&!report$body$analysis$quality$scientifically_qualified&&report$body$analysis$quality$requires_research_review)
  catalog<-run_job(brohn_queue_signal_view(store,report$id,"physiology-series"),"signal_view")
  table<-catalog$body$view$tables[[1L]]
  selection<-list(table_ids=list(table$table_id),recording_id=table$identity$recording_id,channel=table$identity$channel,value_column="clean",range=list(10,18))
  view<-run_job(brohn_queue_signal_view(store,report$id,"physiology-series",selection,max_bins=200L),"signal_view")
  markers<-view$body$view$marker_overlay$markers
  expected<-Filter(function(e)identical(e$type,"r_peak")&&e$time_s>=10&&e$time_s<=18,
    brohn_read_json_file(file.path(reference,"108","worker-result.json"))$events)
  check("display markers match the original failing detector run exactly",length(markers)==length(expected)&&length(markers)>0&&
    all(vapply(seq_along(markers),function(i)identical(markers[[i]]$source_sample_index,expected[[i]]$source_sample_index)&&
      identical(markers[[i]]$time_s,expected[[i]]$time_s)&&identical(markers[[i]]$previous_interval_ms,expected[[i]]$previous_interval_ms)&&
      identical(markers[[i]]$previous_interval_plausible,expected[[i]]$previous_interval_plausible),logical(1))))
  check("public source remains original and display cannot qualify it",identical(.brohn_store_hash(original,file=TRUE),comparison$prepared_csv_sha256)&&
    identical(brohn_hash(brohn_get_entity(store,"report",report$id)$body),before)&&view$body$view$marker_overlay$review_status=="unreviewed_algorithm_detections")
  brohn_write_json_file(view$body$view,file.path(evidence,"reference108-view.json"))
  brohn_close_store(store);store<-brohn_open_store(file.path(evidence,"workspace"))
  check("recorded-data report and view reopen unchanged",identical(brohn_hash(brohn_get_entity(store,"report",report$id)$body),before)&&
    identical(brohn_hash(brohn_get_entity(store,"signal_view",view$id)$body),brohn_hash(view$body)))
  brohn_write_json_file(list(checks=checks,workspace=store$root,report_id=report$id,report_hash=before,view_id=view$id,catalog_id=catalog$id,
    origin="published_reference_recording",dataset_url="https://physionet.org/content/mitdb/1.0.0/",detector_accuracy_qualified=FALSE),file.path(evidence,"acceptance.json"))
  cat(checks," recorded ECG import/analysis/display checks passed; evidence ",evidence,"\n",sep="")
})

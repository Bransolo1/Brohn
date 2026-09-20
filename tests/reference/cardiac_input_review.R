# Reanalysis/display regression against retained public-reference outputs.
# No tuning, new accuracy study or physical-device qualification is implied.
args<-commandArgs(trailingOnly=TRUE);stopifnot(length(args)==3L)
source("R/platform-load.R",encoding="UTF-8");brohn_load()
local({
  roots<-list(ecg=normalizePath(args[[1]],winslash="/",mustWork=TRUE),ppg=normalizePath(args[[2]],winslash="/",mustWork=TRUE))
  evidence<-normalizePath(args[[3]],winslash="/",mustWork=FALSE)
  stopifnot(startsWith(basename(evidence),"brohn-cardiac-input-"),!dir.exists(evidence))
  dir.create(evidence,recursive=TRUE);checks<-character();saved<-list()
  check<-function(name,value){if(!isTRUE(value))stop("Cardiac input review: ",name,call.=FALSE);checks<<-c(checks,name)}
  store<-brohn_open_store(file.path(evidence,"workspace"));brohn_initialise_library(store);on.exit(brohn_close_store(store))
  run_job<-function(queued,type){force(queued);claim<-brohn_claim_job(store,"cardiac-input-reference",180);stopifnot(claim$id==queued$id)
    brohn_process_job(store,claim,timeout_seconds=180);done<-brohn_get_job(store,queued$id)
    if(done$status!="succeeded")stop(brohn_json(done$error))
    brohn_get_entity(store,type,done$result[[if(type=="report")"report_id"else"signal_view_id"]])}
  for(modality in c("ecg","ppg")){
    ref<-file.path(roots[[modality]],if(modality=="ecg")"108"else"0123")
    original<-brohn_read_json_file(file.path(ref,"request.json"));before<-brohn_read_json_file(file.path(ref,"worker-result.json"))
    agreement<-brohn_read_json_file(file.path(ref,"agreement.json"));path<-file.path(ref,paste0("reference-",modality,".csv"))
    stopifnot(identical(.brohn_store_hash(path,file=TRUE),agreement$prepared_csv_sha256))
    title<-if(modality=="ecg")"MIT-BIH 108 input review regression"else"CapnoBase 0123 input review regression"
    source<-brohn_ingest_dataset(store,path,title,modality=modality,origin="imported")
    mapping<-original$metadata;mapping$origin<-"imported";mapping$parameters<-original$parameters
    mapping$origin_statement<-if(modality=="ecg")"MIT-BIH Arrhythmia Database1.0.0 record108,first300s MLII. DOI10.13026/C2F305; ODC Attribution1.0. Reprocessing unchanged reference bytes for display regression; no new accuracy claim."else"CapnoBase IEEE TBME Benchmark record0123,8min PPG. DOI10.5683/SP2/NLB8IT; direct expert annotations retained in prior evaluation. Display regression only; no tuning or new accuracy claim."
    dataset<-brohn_curate_dataset(store,source$id,mapping,source$revision)
    report<-run_job(brohn_queue_dataset(store,dataset$id),"report");a<-report$body$analysis;report_hash<-brohn_hash(report$body)
    check(paste(modality,"automatic report retains original source bytes"),brohn_get_entity(store,"dataset",dataset$id)$body$source$hash==agreement$prepared_csv_sha256)
    check(paste(modality,"all features exactly match prior reference execution"),identical(brohn_hash(a$features),brohn_hash(before$features)))
    check(paste(modality,"all saved event coordinates and intervals remain unchanged"),identical(brohn_hash(a$events),brohn_hash(before$events)))
    check(paste(modality,"new report admits preserved input while quality stays unqualified"),isTRUE(a$quality$raw_source_duplicated)&&!isTRUE(a$quality$scientifically_qualified)&&isTRUE(a$quality$requires_research_review))
    catalog<-run_job(brohn_queue_signal_view(store,report$id,"physiology-series"),"signal_view");table<-catalog$body$view$tables[[1]]
    check(paste(modality,"actual catalog offers both exact waveform columns"),all(c("raw","clean")%in%vapply(table$value_columns,`[[`,character(1),"name"))&&table$support$input_waveform$detection_basis=="clean")
    selection<-list(table_ids=list(table$table_id),recording_id=table$identity$recording_id,channel=table$identity$channel,value_column="clean",range=if(modality=="ecg")list(10,18)else list(220,235))
    clean<-run_job(brohn_queue_signal_view(store,report$id,"physiology-series",selection,max_bins=200L),"signal_view")
    selection$value_column<-"raw";raw<-run_job(brohn_queue_signal_view(store,report$id,"physiology-series",selection,max_bins=200L),"signal_view")
    strip_value<-function(x)lapply(x$body$view$marker_overlay$markers,function(p){p$value<-NULL;p})
    check(paste(modality,"waveform choice keeps exact same event records"),identical(brohn_hash(strip_value(clean)),brohn_hash(strip_value(raw))))
    csv<-read.csv(path,check.names=FALSE);factor<-if(modality=="ecg")1000 else 1;values<-csv[[original$metadata$value_columns[[1]]]]*factor
    points<-unlist(lapply(raw$body$view$envelopes,`[[`,"points"),recursive=FALSE);markers<-raw$body$view$marker_overlay$markers
    # JSON integer-valued coordinates may decode as R integer while read.csv
    # returns double. Normalize storage type, never round or use a tolerance.
    exact<-function(x,y)identical(as.numeric(x),as.numeric(y))
    check(paste(modality,"all plotted input points equal original CSV with declared conversion"),length(points)>0&&all(vapply(points,function(p)exact(p$y,values[[p$source_sample_index+1]])&&exact(p$x,csv[[original$metadata$time_column]][[p$source_sample_index+1]]),logical(1))))
    check(paste(modality,"all marker amplitudes equal exact input samples"),length(markers)>0&&all(vapply(markers,function(p)exact(p$value,values[[p$source_sample_index+1]]),logical(1))))
    check(paste(modality,"both waveforms have identical retention and missing support"),identical(brohn_hash(clean$body$view$selected_range[c("rows","eligible_value_rows","excluded_retention_rows","missing_value_rows")]),brohn_hash(raw$body$view$selected_range[c("rows","eligible_value_rows","excluded_retention_rows","missing_value_rows")])) )
    for(name in c("clean","raw")){
      view<-get(name)$body$view;brohn_write_json_file(view,file.path(evidence,paste0(modality,"-",name,"-view.json")))
      writeLines(as.character(brohn_signal_svg(view)),file.path(evidence,paste0(modality,"-",name,".svg")),useBytes=TRUE)
    }
    check(paste(modality,"display preserves full report and original file"),brohn_hash(brohn_get_entity(store,"report",report$id)$body)==report_hash&&.brohn_store_hash(path,file=TRUE)==agreement$prepared_csv_sha256)
    saved[[modality]]<-list(report_id=report$id,report_hash=report_hash,dataset_id=dataset$id,title=title,raw_view_id=raw$id,raw_view_hash=brohn_hash(raw$body),clean_view_id=clean$id,catalog_id=catalog$id,prior_reference_result_hash=.brohn_store_hash(file.path(ref,"worker-result.json"),file=TRUE))
  }
  brohn_close_store(store);store<-brohn_open_store(file.path(evidence,"workspace"))
  for(modality in names(saved)){s<-saved[[modality]];check(paste(modality,"saved input view and report reopen exactly"),brohn_hash(brohn_get_entity(store,"signal_view",s$raw_view_id)$body)==s$raw_view_hash&&brohn_hash(brohn_get_entity(store,"report",s$report_id)$body)==s$report_hash)}
  brohn_write_json_file(list(checks=checks,workspace=store$root,reports=saved,origin="public_reference_display_regression",accuracy_qualified=FALSE),file.path(evidence,"acceptance.json"))
  cat(length(checks)," cardiac input reference checks passed; ",evidence,"\n",sep="")
})

# Actual saved jobs over the independently solved fNIRS software phantom.
args<-commandArgs(trailingOnly=TRUE);stopifnot(length(args)==2L)
source("R/platform-load.R",encoding="UTF-8");brohn_load()
local({
  reference<-normalizePath(args[[1]],winslash="/",mustWork=TRUE)
  folder<-normalizePath(args[[2]],winslash="/",mustWork=FALSE)
  stopifnot(!file.exists(folder),startsWith(basename(folder),"brohn-fnirs-saved-"));dir.create(folder,recursive=TRUE)
  proof<-brohn_read_json_file(file.path(reference,"acceptance.json"));stopifnot(isTRUE(proof$passed))
  store<-brohn_open_store(file.path(folder,"workspace"));brohn_initialise_library(store);on.exit(brohn_close_store(store))
  checks<-character();reports<-list()
  check<-function(name,value){stopifnot(isTRUE(value));checks<<-c(checks,name);cat("PASS ",name,"\n",sep="")}
  job<-function(queued,kind){force(queued);claim<-brohn_claim_job(store,"fnirs-phantom-saved",240);stopifnot(identical(claim$id,queued$id))
    brohn_process_job(store,claim,timeout_seconds=240);done<-brohn_get_job(store,queued$id)
    if(done$status!="succeeded")stop(brohn_json(done$error))
    brohn_get_entity(store,kind,done$result[[switch(kind,report="report_id",signal_view="signal_view_id",signal_values="signal_values_id")]])}
  for(name in c("unequal-pathlength","nonpositive-splits")) {
    path<-file.path(reference,name,"source.snirf");original<-brohn_read_json_file(file.path(reference,name,"result.json"))
    expected<-Filter(function(x)identical(x$name,name),proof$cases)[[1]]
    check(paste(name,"independent source bytes match"),identical(digest::digest(file=path,algo="sha256"),expected$source_sha256))
    title<-paste("Original fNIRS software phantom",name)
    imported<-brohn_ingest_dataset(store,path,title,"fnirs",origin="sample")
    mapping<-list(unit="native",value_columns=list("S1_D1 760","S1_D1 850"),sampling_rate=10,
      participant_id="software-phantom",session_id=name,origin="sample",origin_statement="Original two-wavelength software phantom with independent scalar conversion oracle; no physical or neural qualification.",parameters=list(ppf=list(6,5)))
    dataset<-brohn_curate_dataset(store,imported$id,mapping,imported$revision)
    report<-job(brohn_queue_dataset(store,dataset$id),"report");hash<-brohn_hash(report$body)
    check(paste(name,"actual automatic features equal independently checked CLI output"),identical(brohn_hash(report$body$analysis$features),brohn_hash(original$features)))
    check(paste(name,"origin and qualification remain explicit"),identical(report$body$origin,"sample")&&!isTRUE(report$body$analysis$quality$scientifically_qualified))
    catalog<-job(brohn_queue_signal_view(store,report$id,"physiology-series"),"signal_view")
    check(paste(name,"all full source channel segments are discoverable"),length(catalog$body$view$tables)==expected$tables)
    t<-catalog$body$view$tables[[1L]]
    check(paste(name,"units and wavelength pairing are explicit"),t$identity$optical_density_source_channel=="S1_D1 760"&&all(c("optical_density","haemoglobin_um")%in%vapply(t$value_columns,`[[`,character(1),"name")))
    selected<-list(table_ids=list(t$table_id),recording_id=t$identity$recording_id,channel=t$identity$channel,value_column="haemoglobin_um",range=NULL)
    view<-job(brohn_queue_signal_view(store,report$id,"physiology-series",selected,max_bins=100L),"signal_view")
    check(paste(name,"saved haemoglobin figure has eligible full-source support"),view$body$view$selected_range$eligible_value_rows==t$rows&&length(view$body$view$envelopes)>0)
    values<-list(table_id=t$table_id,recording_id=t$identity$recording_id,channel=t$identity$channel,value_column="haemoglobin_um",range=NULL,row_policy="all_source_rows")
    exact<-job(brohn_queue_signal_values(store,catalog$id,values,mode="export"),"signal_values")
    check(paste(name,"complete CSV has every selected source sample"),exact$body$result$csv$rows==t$rows&&exact$body$result$full_source$rows==t$rows)
    check(paste(name,"views do not change original report or source"),identical(brohn_hash(brohn_get_entity(store,"report",report$id)$body),hash)&&identical(digest::digest(file=path,algo="sha256"),expected$source_sha256))
    reports[[name]]<-list(report_id=report$id,report_hash=hash,dataset_id=dataset$id,title=title,catalog_id=catalog$id,view_id=view$id,values_id=exact$id)
  }
  brohn_close_store(store);store<-brohn_open_store(file.path(folder,"workspace"))
  for(r in reports)check(paste(r$title,"reopens unchanged"),identical(brohn_hash(brohn_get_entity(store,"report",r$report_id)$body),r$report_hash))
  brohn_write_json_file(list(checks=checks,reports=reports,workspace=store$root,jobs=brohn_list_jobs(store,limit=100L),reference=reference,
    scope="Original software phantom; no hardware, neural interpretation or human usability qualification."),file.path(folder,"acceptance.json"))
  cat(length(checks)," checks passed\n")
})

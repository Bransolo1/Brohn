args<-commandArgs(trailingOnly=TRUE);mode<-args[[1]];folder<-normalizePath(args[[2]],winslash="/",mustWork=TRUE)
stopifnot(startsWith(basename(folder),"brohn-signal-values-browser-"))
source("R/platform-load.R",encoding="UTF-8");brohn_load()
config_path<-file.path(folder,"fixture.json")
if(mode=="setup")local({
  reference<-brohn_read_json_file(file.path(args[[3]],"acceptance.json"))
  stopifnot(!file.exists(config_path),!dir.exists(file.path(folder,"workspace")),file.copy(reference$workspace,folder,recursive=TRUE))
  store<-brohn_open_store(file.path(folder,"workspace"));on.exit(brohn_close_store(store))
  processx::run(brohn_python_profile("eda"),c("-B","tests/fixtures/signal-values-source.py",folder),windows_hide_window=TRUE)
  proof<-brohn_read_json_file(file.path(folder,"source.json"));source<-file.path(folder,"original-software-fixture.csv");writeLines(c("time,value","0,0","1,1"),source)
  dataset<-brohn_ingest_dataset(store,source,"Exact processed values - original software fixture","eda",origin="sample")
  artifacts<-lapply(proof$artifacts,function(a)c(list(kind=a$kind),brohn_store_object(store,path=a$path,media_type="application/x-ndjson"),a[c("schema","tables","rows","provenance_sha256","complete")]))
  id<-"report-exact-values-fixture";body<-list(id=id,title="Exact processed values - original software fixture",dataset_id=dataset$id,origin="sample",status="Available",created_at=brohn_now(),
    provenance=list(fixture_kind="original typed schema edge cases, not a scientific analysis"),analysis=list(kind="fixture",status="ok",artifacts=artifacts,artifact_verification=proof$artifact_verification,
    quality=list(scientifically_qualified=FALSE),features=list(),observations=list(),limitations=list("Original schema-shaped fixture; no measured or inferred physiology.")))
  path<-file.path(folder,"fixture-report.json");brohn_write_json_file(list(schema="brohn-analysis-output/1.0",report=body),path);body$result_object<-brohn_store_object(store,path=path,media_type="application/json")
  brohn_put_entity(store,"report",id,body,expected_revision=0L,project_id="default")
  config<-list(workspace=store$root,port=httpuv::randomPort(min=21000L,max=49000L),reports=c(list(fixture=list(report_id=id,dataset_id=dataset$id,title=body$title)),reference$reports),oracle=proof$oracle)
  brohn_write_json_file(config,config_path)
})else if(mode=="serve"){
  config<-brohn_read_json_file(config_path);Sys.setenv(BROHN_WORKSPACE=config$workspace,BROHN_APP_MODE="platform")
  stop_owned<-function()if(file.exists(file.path(folder,"stop.request")))shiny::stopApp()else later::later(stop_owned,.2)
  later::later(stop_owned,.2);shiny::runApp(".",host="127.0.0.1",port=config$port,launch.browser=FALSE)
}else if(mode=="worker")local({
  config<-brohn_read_json_file(config_path);store<-brohn_open_store(config$workspace);on.exit(brohn_close_store(store))
  repeat{if(file.exists(file.path(folder,"stop.request")))break
    if(file.exists(file.path(folder,"worker.pause"))){Sys.sleep(.2);next}
    job<-brohn_claim_job(store,"exact-values-browser",300);if(is.null(job))Sys.sleep(.2)else brohn_process_job(store,job,timeout_seconds=300)}
})else if(mode=="inspect")local({
  config<-brohn_read_json_file(config_path);store<-brohn_open_store(config$workspace);on.exit(brohn_close_store(store))
  brohn_write_json_file(list(values=brohn_list_entities(store,"signal_values",limit=100L),catalogs=brohn_list_entities(store,"signal_view",limit=100L),jobs=brohn_list_jobs(store,limit=500L),reports=brohn_list_entities(store,"report",limit=100L)),file.path(folder,"inspection.json"))
})else stop("Unknown fixture mode")

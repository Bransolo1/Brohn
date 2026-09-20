# Original six-row numerical fixture; never represents biological observations.
args <- commandArgs(trailingOnly=TRUE); mode<-args[[1]];folder<-normalizePath(args[[2]],winslash="/",mustWork=TRUE)
stopifnot(startsWith(basename(folder),"brohn-intervals-"))
source("R/platform-load.R",encoding="UTF-8");brohn_load()
config_path<-file.path(folder,"fixture.json")
if(mode=="setup")local({
  stopifnot(!file.exists(config_path));store<-brohn_open_store(file.path(folder,"workspace"));on.exit(brohn_close_store(store));brohn_initialise_library(store)
  study<-brohn_create_study(store,"Independent recording interval fixture","survey")
  script<-paste("import importlib.util,json,sys;from pathlib import Path",
    "s=importlib.util.spec_from_file_location('fixture','tests/workers/signal_windows.py');m=importlib.util.module_from_spec(s);s.loader.exec_module(m)",
    "p=m.Windows();p.root=Path(sys.argv[1]);p.builder=m.fixtures.Preview();p.builder.root=p.root;request=p.request()",
    "(p.root/'source.json').write_text(json.dumps(request),encoding='utf-8')",sep="\n")
  processx::run(brohn_python_profile("eda"),c("-c",script,folder),windows_hide_window=TRUE)
  fixture<-brohn_read_json_file(file.path(folder,"source.json"));a<-fixture$artifact
  object<-brohn_store_object(store,path=a$path,media_type="application/x-ndjson");id<-brohn_id("report")
  report<-brohn_put_entity(store,"report",id,list(id=id,title="Six known values for interval comparison",study_id=study$id,origin="sample",status="Available",created_at=brohn_now(),
    analysis=list(kind="original-numerical-fixture",quality=list(source_rows=6),limitations=list("Original synthetic numbers; no physiological inference."),parameters=list(),
      artifacts=list(c(list(kind=a$kind),object,a[c("schema","tables","rows","provenance_sha256","complete")])),artifact_verification=fixture$verification_receipt)))
  brohn_write_json_file(list(schema="brohn-intervals-qa/1.0",workspace=store$root,study_id=study$id,report_id=id,report_hash=brohn_hash(report$body),port=httpuv::randomPort(min=20000L,max=49000L)),config_path)
}) else if(mode=="serve") {
  config<-brohn_read_json_file(config_path);Sys.setenv(BROHN_WORKSPACE=config$workspace,BROHN_APP_MODE="platform")
  stop_owned<-function()if(file.exists(file.path(folder,"stop.request")))shiny::stopApp()else later::later(stop_owned,.2)
  later::later(stop_owned,.2);shiny::runApp(".",host="127.0.0.1",port=config$port,launch.browser=FALSE)
} else if(mode=="worker")local({
  config<-brohn_read_json_file(config_path);store<-brohn_open_store(config$workspace);on.exit(brohn_close_store(store))
  repeat{if(file.exists(file.path(folder,"stop.request")))break
    if(file.exists(file.path(folder,"worker.pause"))){Sys.sleep(.1);next}
    job<-brohn_claim_job(store,"interval-browser",90)
    if(is.null(job))Sys.sleep(.2)else brohn_process_job(store,job,timeout_seconds=90)
  }
}) else if(mode=="inspect")local({
  config<-brohn_read_json_file(config_path);store<-brohn_open_store(config$workspace);on.exit(brohn_close_store(store))
  brohn_write_json_file(list(annotations=brohn_list_entities(store,"signal_annotations"),summaries=brohn_list_entities(store,"signal_windows"),
    jobs=brohn_list_jobs(store),report=brohn_get_entity(store,"report",config$report_id)),file.path(folder,"snapshot.json"))
}) else stop("Unknown mode")

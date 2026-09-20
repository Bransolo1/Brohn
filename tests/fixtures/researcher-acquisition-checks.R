# Metadata-only synthetic discovery -> actual researcher queue -> production
# Writer replay. No outlet, manager subscription, hardware or person is used.
args<-commandArgs(trailingOnly=TRUE);mode<-args[[1L]]
source("R/platform-load.R",encoding="UTF-8");brohn_load(ui=TRUE)
folder<-normalizePath(args[[2L]],winslash="/",mustWork=TRUE);stopifnot(startsWith(basename(folder),"brohn-acquisition-checks-"))
config_path<-file.path(folder,"fixture.json")
if(mode=="serve"){
  cfg<-brohn_read_json_file(config_path);Sys.setenv(BROHN_WORKSPACE=cfg$workspace,BROHN_APP_MODE="platform")
  stop_owned<-function()if(file.exists(file.path(folder,"stop.request")))shiny::stopApp()else later::later(stop_owned,.2)
  later::later(stop_owned,.2);shiny::runApp(".",host="127.0.0.1",port=cfg$port,launch.browser=FALSE)
}else local({
  if(mode=="setup")stopifnot(!file.exists(config_path))
  store<-brohn_open_store(file.path(folder,"w"));on.exit(brohn_close_store(store),add=TRUE);brohn_initialise_library(store)
  if(mode=="setup"){
    study<-brohn_create_study(store,"Original acquisition criteria review","survey")
    d<-brohn_queue_lsl_discovery(store,study$id,"original-checks",c("original-conductance","original-contact"),TRUE)
    stream<-function(id,name,type,value_type,unit)list(uid=id,source_id=id,name=name,type=type,value_type=value_type,channel_count=1L,
      nominal_srate=100,source_origin="synthetic",supported=TRUE,support_reason=NULL,metadata_sha256=brohn_hash(list(id,type,value_type)),
      channels=list(list(label=name,type=type,unit=unit)))
    b<-d$body;b$status<-"ready";b$result<-list(schema="brohn-lsl-discovery/1.0",metadata_only=TRUE,
      streams=list(stream("original-conductance","Original conductance source","EDA","float64","uS"),stream("original-contact","Original contact codes","EEG","string","code")))
    b$result_hash<-brohn_hash(b$result);b$result_object<-brohn_store_object(store,bytes=charToRaw(enc2utf8(brohn_json(b$result))),media_type="application/json")
    brohn_put_entity(store,"acquisition_discovery",d$id,b,d$revision,d$project_id)
    brohn_write_json_file(list(workspace=store$root,study_id=study$id,study_title=study$body$title,discovery_id=d$id,
      port=httpuv::randomPort(min=21000L,max=49000L)),config_path)
  }else if(mode=="inspect"){
    cfg<-brohn_read_json_file(config_path);records<-brohn_acquisitions(store,cfg$study_id)
    brohn_write_json_file(list(recordings=records,jobs=brohn_list_jobs(store)),file.path(folder,"snapshot.json"))
  }else if(mode %in% c("replay","render")){
    if(mode=="replay"){
    cfg<-brohn_read_json_file(config_path);records<-brohn_acquisitions(store,cfg$study_id);stopifnot(length(records)==1L)
    request<-records[[1L]]$body$request;brohn_write_json_file(request,file.path(folder,"frozen-request.json"))
    script<-file.path(folder,"replay-selected.py")
    writeLines(c("import importlib.util,json,sys", "from pathlib import Path",
      "spec=importlib.util.spec_from_file_location('brohn_recorder','scripts/acquisition/lsl_recorder.py')",
      "m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)",
      "root=Path(sys.argv[1]); request=json.loads((root/'frozen-request.json').read_text());m.validate_request(request)",
      "directory=root/'replayed';directory.mkdir();(directory/'chunks').mkdir()",
      "writer=m.Writer(directory,request,{'engine':{'script_sha256':m.file_sha(spec.origin)},'streams':[]})",
      "for stream in request['streams']:",
      "    writer.monitor[stream['id']]['connection']='subscribed'",
      "    values=[[('001' if i%10 else 'LOOSE') if stream['channels'][0]['value_type']=='string' else (20.0 if i%10==0 else 2+(i%9)/10)] for i in range(600)]",
      "    for start in range(0,600,100):writer.chunk(stream,values[start:start+100],[(i+1)/100 for i in range(start,start+100)],100.0,100.1)",
      "live=m.load(directory/'status.json',2*1024**2);writer.finish('completed','original_authored_criteria_replay')",
      "(root/'replay.json').write_bytes(m.encoded({'live':live,'closed':m.load(directory/'status.json',2*1024**2),'inspection':m.inspect_recording(directory)}))"),script,useBytes=TRUE)
    result<-processx::run(.brohn_acq_python(),c(script,folder),error_on_status=FALSE,timeout=90,windows_hide_window=TRUE)
    if(result$status!=0L)stop(result$stderr)
    observed<-brohn_read_json_file(file.path(folder,"replay.json"),16*1024^2)
    record<-list(id=request$recording_id,body=list(request=request,status="recording",origin="sample",python_request_hash=observed$live$request_sha256),live_snapshot=observed$live)
    now<-observed$live$monitoring$updated_epoch
    models<-list(current=brohn_acquisition_quality(record,now),stale=brohn_acquisition_quality(record,now+30))
    record$live_snapshot<-observed$closed;models$closed<-brohn_acquisition_quality(record,observed$closed$monitoring$updated_epoch)
    brohn_write_json_file(models,file.path(folder,"models.json"))
    }else models<-brohn_read_json_file(file.path(folder,"models.json"),16*1024^2)
    for(name in names(models)){
      content<-shiny::tags$main(class="brohn-main",shiny::h1("Authored acquisition checks: original software replay"),
        shiny::p("Exact researcher-authored request replayed through the production Writer. No hardware or person."),
        shiny::tags$section(id=paste0("case-",name),shiny::h2(paste("Replay state:",name)),shiny::h3("Source observations"),brohn_acquisition_quality_ui(models[[name]])))
      # The standalone renderer uses the same border-box reset as Bootstrap.
      # Each page contains one recording state, as in the actual application.
      writeLines(paste0('<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><title>Brohn authored acquisition checks replay</title><style>*,*::before,*::after{box-sizing:border-box}body{margin:0}</style></head><body><div class="container-fluid" style="padding-inline:12px"><div class="brohn-app">',as.character(content),'</div></div></body></html>'),file.path(folder,paste0("replay-",name,".html")),useBytes=TRUE)
    }
  }else stop("Unknown authored acquisition fixture mode")
})

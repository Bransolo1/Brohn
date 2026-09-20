# Original metadata-only equipment sources. No manager or outlet is launched.
args<-commandArgs(trailingOnly=TRUE);mode<-args[[1L]]
source("R/platform-load.R",encoding="UTF-8");brohn_load()
folder<-normalizePath(args[[2L]],winslash="/",mustWork=TRUE);stopifnot(startsWith(basename(folder),"brohn-equipment-setups-"))
config_path<-file.path(folder,"fixture.json")
if(mode=="serve") {
  cfg<-brohn_read_json_file(config_path);Sys.setenv(BROHN_WORKSPACE=cfg$workspace,BROHN_APP_MODE="platform")
  stop_owned<-function()if(file.exists(file.path(folder,"stop.request")))shiny::stopApp()else later::later(stop_owned,.2)
  later::later(stop_owned,.2);shiny::runApp(".",host="127.0.0.1",port=cfg$port,launch.browser=FALSE)
}else local({
  if(mode=="setup")stopifnot(!file.exists(config_path))
  store<-brohn_open_store(file.path(folder,"w"));on.exit(brohn_close_store(store),add=TRUE);brohn_initialise_library(store)
  if(mode=="setup") {
    path<-file.path(folder,"metadata.json")
    processx::run(.brohn_acq_python(),c("tests/acquisition/equipment_metadata.py","--fixture",path),error_on_status=TRUE,windows_hide_window=TRUE)
    metadata<-brohn_read_json_file(path)
    studies<-lapply(seq_len(3L),function(i)brohn_create_study(store,paste("Original equipment reuse study",i),"survey"))
    discoveries<-lapply(seq_along(studies),function(i) {
      stream<-metadata[[c("original","restarted","unit")[[i]]]]
      d<-brohn_queue_lsl_discovery(store,studies[[i]]$id,"original-equipment-reuse",stream$source_id,TRUE)
      b<-d$body;b$status<-"ready";b$result<-list(schema="brohn-lsl-discovery/1.0",metadata_only=TRUE,streams=list(stream));b$result_hash<-brohn_hash(b$result)
      b$result_object<-brohn_store_object(store,bytes=charToRaw(enc2utf8(brohn_json(b$result))),media_type="application/json")
      brohn_put_entity(store,"acquisition_discovery",d$id,b,d$revision,d$project_id)
    })
    brohn_write_json_file(list(workspace=store$root,studies=lapply(studies,function(s)list(id=s$id,title=s$body$title)),
      discoveries=lapply(discoveries,function(d)list(id=d$id,uid=d$body$result$streams[[1L]]$uid)),port=httpuv::randomPort(min=21000L,max=49000L)),config_path)
  }else if(mode=="inspect") {
    brohn_write_json_file(list(setups=brohn_equipment_setups(store),recordings=brohn_acquisitions(store),jobs=brohn_list_jobs(store)),file.path(folder,"snapshot.json"))
  }else if(mode=="revise") {
    cfg<-brohn_read_json_file(config_path);setup<-brohn_equipment_setups(store)[[1L]]
    brohn_save_equipment_setup(store,paste(setup$body$title,"updated"),cfg$discoveries[[1L]]$id,cfg$discoveries[[1L]]$uid,setup$body$configuration,setup$id,setup$revision)
  }else if(mode=="replay") {
    cfg<-brohn_read_json_file(config_path);records<-brohn_acquisitions(store,cfg$studies[[2L]]$id);stopifnot(length(records)==1L)
    brohn_write_json_file(records[[1L]]$body$request,file.path(folder,"frozen-request.json"))
    script<-file.path(folder,"replay.py")
    writeLines(c("import importlib.util,json,sys","from pathlib import Path",
      "spec=importlib.util.spec_from_file_location('recorder','scripts/acquisition/lsl_recorder.py');m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)",
      "root=Path(sys.argv[1]);request=json.loads((root/'frozen-request.json').read_text());m.validate_request(request)",
      "out=root/'replay';out.mkdir();(out/'chunks').mkdir();writer=m.Writer(out,request,{'engine':{'script_sha256':m.file_sha(spec.origin)},'streams':[]})",
      "stream=request['streams'][0];writer.monitor[stream['id']]['connection']='subscribed'",
      "for start in range(0,600,100):writer.chunk(stream,[['001','001'] for i in range(100)],[(i+1)/100 for i in range(start,start+100)],100,100.01)",
      "live=m.load(out/'status.json',2*1024**2);writer.finish('completed','original_equipment_reuse_replay')",
      "(root/'replay-result.json').write_bytes(m.encoded({'live':live,'inspection':m.inspect_recording(out)}))"),script,useBytes=TRUE)
    result<-processx::run(.brohn_acq_python(),c(script,folder),error_on_status=TRUE,windows_hide_window=TRUE)
    original<-brohn_read_json_file(file.path(folder,"replay-result.json"),16*1024^2)
    record<-records[[1L]];record$body$status<-"recording";record$body$python_request_hash<-original$live$request_sha256;record$live_snapshot<-original$live
    brohn_write_json_file(brohn_acquisition_quality(record,original$live$monitoring$updated_epoch),file.path(folder,"replay-model.json"))
  }else stop("Unknown equipment setup fixture mode")
})

# Two original numerical recordings with different people, clocks and values.
args<-commandArgs(trailingOnly=TRUE);mode<-args[[1L]];folder<-normalizePath(args[[2L]],winslash="/",mustWork=TRUE)
stopifnot(startsWith(basename(folder),"brohn-interval-reuse-"))
source("R/platform-load.R",encoding="UTF-8");brohn_load();config_path<-file.path(folder,"fixture.json")
if(mode=="setup")local({
  stopifnot(!file.exists(config_path));store<-brohn_open_store(file.path(folder,"workspace"));on.exit(brohn_close_store(store));brohn_initialise_library(store)
  study<-brohn_create_study(store,"Original interval reuse fixture","survey")
  names<-c("original","target",if("unknown" %in% args)"unknown")
  code<-paste("import importlib.util,json,sys;from pathlib import Path",
    "s=importlib.util.spec_from_file_location('fixture','tests/workers/signal_preview.py');m=importlib.util.module_from_spec(s);s.loader.exec_module(m)",
    "root=Path(sys.argv[1]);builder=m.Preview()",
    "for name in sys.argv[2:]:",
    " folder=root/name;folder.mkdir(exist_ok=True);builder.root=folder;target=name!='original'",
    " table=builder.table(values=[0,None,100,20,40,60] if target else [2,4,6,8,10,12],times=list(range(10,16)) if target else list(range(6)),retained=[True,True,False,True,True,True] if target else None,origin='10000000000000003' if target else '99999999999999999')",
    " table['identity']={'recording_id':'recording-'+name,'channel':'eda','group':{'participant_id':'target-person' if target else 'original-person','session_id':'target-session' if target else 'original-session'}}",
    " if name=='unknown':table['arrays']['time_s']=[None]*6;table['specification'][0]['nullable']=True",
    " p={'source_sha256':('c' if target else 'a')*64,'engine':{'name':'original-numerical-fixture','worker_sha256':'b'*64},'operation':'physiology','origin':'imported' if target else 'sample','parameters':{'recipe':'fixture/1'}}",
    " with m.worker.artifacts.TableWriter(folder,'physiology-series',p,chunk_rows=17) as writer:",
    "  writer.write_arrays(**table);a=writer.finish()",
    " request={'artifact':a,'verification_receipt':m.worker.artifacts.verify_manifest([a])}",
    " (folder/'source.json').write_text(json.dumps(request),encoding='utf-8')",sep="\n")
  processx::run(brohn_python_profile("eda"),c("-B","-c",code,folder,names),windows_hide_window=TRUE)
  records<-list()
  for(name in names){
    fixture<-brohn_read_json_file(file.path(folder,name,"source.json"));a<-fixture$artifact
    object<-brohn_store_object(store,path=a$path,media_type="application/x-ndjson");id<-brohn_id("report")
    report<-brohn_put_entity(store,"report",id,list(id=id,title=paste(name,"recording: six known numbers"),study_id=study$id,
      origin=if(name!="original")"imported"else"sample",status="Available",created_at=brohn_now(),
      analysis=list(kind="original-numerical-fixture",quality=list(source_rows=6),parameters=list(),
        limitations=list("Original synthetic numerical fixture; no physiological inference."),
        artifacts=list(c(list(kind=a$kind),object,a[c("schema","tables","rows","provenance_sha256","complete")])),artifact_verification=fixture$verification_receipt)))
    queued<-brohn_queue_signal_view(store,id,"physiology-series");claimed<-brohn_claim_job(store,"interval-reuse-setup",90)
    stopifnot(identical(queued$id,claimed$id));brohn_process_job(store,claimed,timeout_seconds=90);done<-brohn_get_job(store,queued$id)
    if(done$status!="succeeded")stop(brohn_json(done$error))
    records[[name]]<-list(report_id=id,report_hash=brohn_hash(report$body),catalog_id=done$result$signal_view_id)
  }
  original<-brohn_create_signal_annotations(store,records$original$catalog_id,"segment-1","Before and during")
  original<-brohn_save_signal_interval(store,original$id,1L,"Before","baseline",0,3,"Original baseline label")
  original<-brohn_save_signal_interval(store,original$id,2L,"During","task",3,6,"")
  records$original$annotations_id<-original$id;records$original$annotations_hash<-brohn_hash(original$body)
  brohn_write_json_file(list(schema="brohn-interval-reuse-qa/1.0",workspace=store$root,study_id=study$id,records=records,
    port=httpuv::randomPort(min=20000L,max=49000L)),config_path)
})else if(mode=="serve"){
  config<-brohn_read_json_file(config_path);Sys.setenv(BROHN_WORKSPACE=config$workspace,BROHN_APP_MODE="platform")
  stop_owned<-function()if(file.exists(file.path(folder,"stop.request")))shiny::stopApp()else later::later(stop_owned,.2)
  later::later(stop_owned,.2);shiny::runApp(".",host="127.0.0.1",port=config$port,launch.browser=FALSE)
}else if(mode=="worker")local({
  config<-brohn_read_json_file(config_path);store<-brohn_open_store(config$workspace);on.exit(brohn_close_store(store))
  repeat{if(file.exists(file.path(folder,"stop.request")))break
    job<-brohn_claim_job(store,"interval-reuse-browser",90);if(is.null(job))Sys.sleep(.2)else brohn_process_job(store,job,timeout_seconds=90)
  }
})else if(mode=="inspect")local({
  config<-brohn_read_json_file(config_path);store<-brohn_open_store(config$workspace);on.exit(brohn_close_store(store))
  brohn_write_json_file(list(annotations=brohn_list_entities(store,"signal_annotations"),summaries=brohn_list_entities(store,"signal_windows"),
    original_annotation_hash=brohn_hash(brohn_signal_annotations(store,config$records$original$annotations_id)$body),
    original_report_hash=brohn_hash(brohn_get_entity(store,"report",config$records$original$report_id)$body),
    target_report_hash=brohn_hash(brohn_get_entity(store,"report",config$records$target$report_id)$body),
    original_report=brohn_get_entity(store,"report",config$records$original$report_id),target_report=brohn_get_entity(store,"report",config$records$target$report_id)),file.path(folder,"snapshot.json"))
})else stop("Unknown fixture mode")

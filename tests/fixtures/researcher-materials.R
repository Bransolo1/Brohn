# Original material fixtures. Real authoring, release, media and package routes.
args<-commandArgs(trailingOnly=TRUE);mode<-args[[1L]]
source("R/platform-load.R",encoding="UTF-8");brohn_load(ui=TRUE)
folder<-normalizePath(args[[2L]],winslash="/",mustWork=TRUE);stopifnot(startsWith(basename(folder),"brohn-materials-"));config_path<-file.path(folder,"fixture.json")
if(mode %in% c("researcher","participant")){
  config<-brohn_read_json_file(config_path)
  if(mode=="researcher"){
    Sys.setenv(BROHN_WORKSPACE=config$workspace,BROHN_APP_MODE="platform",BROHN_PARTICIPANT_PORT=config$participant_port)
    stop_owned<-function()if(file.exists(file.path(folder,"stop.researcher")))shiny::stopApp()else later::later(stop_owned,.2)
    later::later(stop_owned,.2);shiny::runApp(".",host="127.0.0.1",port=config$researcher_port,launch.browser=FALSE)
  }else{
    store<-brohn_open_store(config$workspace);server<-httpuv::startServer("127.0.0.1",config$participant_port,brohn_delivery_app(store))
    while(!file.exists(file.path(folder,"stop.participant")))httpuv::service(50)
    httpuv::stopServer(server);brohn_close_store(store)
  }
}else local({
  store<-brohn_open_store(file.path(folder,"workspace"));on.exit(brohn_close_store(store),add=TRUE);brohn_initialise_library(store)
  if(mode=="setup"){
    stopifnot(!file.exists(config_path));file.copy("examples/stimuli/sample-design-a.png",file.path(folder,"first.png"));file.copy("examples/stimuli/sample-design-b.png",file.path(folder,"second.png"))
    writeBin(charToRaw("Original deliberately invalid PNG"),file.path(folder,"bad.png"))
    d<-brohn_new_design("Original material authoring");for(i in seq_along(d$stimuli)){d$stimuli[[i]]$content<-paste("Original comparison",i);d$stimuli[[i]]$duration_ms<-1500}
    d$baseline_ms<-0;d$fixation_ms<-0;d$order<-"fixed";d$instructions<-"Review the original comparison materials.";d$questions<-list(brohn_question("Original material response","text","end"))
    study<-brohn_put_entity(store,"study",d$id,d)
    profiles<-names(brohn_task_profiles());tasks<-lapply(seq_along(profiles),function(i){
      x<-brohn_new_design(paste("Original material task",i),"blank");x$instructions<-"";x$blocks<-list(brohn_task_new(profiles[[i]]));x$blocks[[1]]$settings$intertrial_ms<-100L
      brohn_put_entity(store,"study",x$id,x)
    })
    ffmpeg<-Sys.which("ffmpeg");stopifnot(nzchar(ffmpeg));run<-function(arguments){p<-processx::run(ffmpeg,c("-hide_banner","-loglevel","error","-nostdin",arguments),error_on_status=FALSE,timeout=30,windows_hide_window=TRUE);if(p$status!=0L)stop(p$stderr)}
    run(c("-i",file.path(folder,"first.png"),"-vf","scale=160:100","-frames:v","1",file.path(folder,"original.webp")))
    run(c("-i",file.path(folder,"first.png"),"-vf","scale=160:100","-frames:v","1",file.path(folder,"original.gif")))
    run(c("-f","lavfi","-i","sine=frequency=440:duration=1","-c:a","pcm_s16le",file.path(folder,"original.wav")))
    run(c("-f","lavfi","-i","color=c=0x264f38:s=160x100:r=10:d=1","-c:v","libx264","-pix_fmt","yuv420p",file.path(folder,"original.mp4")))
    media<-brohn_new_design("Original permitted media","blank");media$conditions<-list(list(id="condition-original",label="Original source",role="test"));media$stimuli<-lapply(c("webp","wav","mp4"),function(ext){
      type<-switch(ext,webp="image",wav="audio",mp4="video");asset<-brohn_store_object(store,path=file.path(folder,paste0("original.",ext)),media_type=switch(ext,webp="image/webp",wav="audio/wav",mp4="video/mp4"));asset$filename<-paste0("original.",ext)
      list(id=paste0("material-",ext),title=paste("Original",ext),condition_id=media$conditions[[1]]$id,type=type,content="",asset=asset,duration_ms=1000,aois=list())
    });original<-brohn_put_entity(store,"study",media$id,media);package<-brohn_export_design(store,original$id,file.path(folder,"original-media.brohn-study.zip"));imported<-brohn_import_design(store,package)
    gif<-brohn_new_design("Original retained GIF","blank");gif$conditions<-media$conditions;gif$stimuli<-list(list(id="material-gif",title="Original GIF",condition_id=gif$conditions[[1]]$id,type="image",content="",asset=c(brohn_store_object(store,path=file.path(folder,"original.gif"),media_type="image/gif"),list(filename="original.gif")),duration_ms=1000,aois=list()));gif<-brohn_put_entity(store,"study",gif$id,gif)
    brohn_write_json_file(list(workspace=store$root,researcher_port=httpuv::randomPort(min=20000L,max=34000L),participant_port=httpuv::randomPort(min=35000L,max=49000L),
      study=study,tasks=tasks,media=imported,gif=gif,first_hash=digest::digest(file=file.path(folder,"first.png"),algo="sha256"),second_hash=digest::digest(file=file.path(folder,"second.png"),algo="sha256")),config_path)
  }else if(mode=="inspect")brohn_write_json_file(list(studies=brohn_studies(store),templates=brohn_list_entities(store,"template"),releases=brohn_deployments(store),runs=brohn_runs(store),jobs=brohn_list_jobs(store)),file.path(folder,"snapshot.json"))
  else if(mode=="analyse"){
    reports<-list()
    repeat {
      claimed<-brohn_claim_job(store,"material-automatic-qa",120)
      if(is.null(claimed))break
      stopifnot(identical(claimed$operation,"analyse_run"))
      brohn_process_job(store,claimed,timeout_seconds=150)
    }
    for(job in brohn_list_jobs(store))if(job$operation=="analyse_run"){
      finished<-brohn_get_job(store,job$id);if(finished$status!="succeeded")stop(brohn_json(finished$error))
      report<-brohn_get_entity(store,"report",finished$result$report_id);run<-brohn_run(store,job$request$run_id)
      stopifnot(identical(brohn_hash(report$body$provenance$design),run$protocol$design_hash),identical(report$body$origin,"sample"),identical(run$completion_status,"completed"))
      reports[[length(reports)+1L]]<-list(id=report$id,run_id=run$id,design_hash=brohn_hash(report$body$provenance$design),origin=report$body$origin)
    }
    stopifnot(length(reports)==2L);brohn_write_json_file(list(passed=TRUE,reports=reports),file.path(folder,"worker-results.json"))
  }else stop("Unknown material fixture mode")
})

args<-commandArgs(trailingOnly=TRUE);mode<-args[[1]];source("R/platform-load.R",encoding="UTF-8");brohn_load(ui=TRUE)
folder<-normalizePath(args[[2]],winslash="/",mustWork=TRUE);stopifnot(startsWith(basename(folder),"brohn-maxdiff-materials-"));config_path<-file.path(folder,"fixture.json")
if(mode %in% c("researcher","participant")){
  config<-brohn_read_json_file(config_path)
  if(mode=="researcher"){
    Sys.setenv(BROHN_WORKSPACE=config$workspace,BROHN_APP_MODE="platform",BROHN_PARTICIPANT_PORT=config$participant_port)
    stop_owned<-function()if(file.exists(file.path(folder,"stop.researcher")))shiny::stopApp()else later::later(stop_owned,.2)
    later::later(stop_owned,.2);shiny::runApp(".",host="127.0.0.1",port=config$researcher_port,launch.browser=FALSE)
  }else{store<-brohn_open_store(config$workspace);server<-httpuv::startServer("127.0.0.1",config$participant_port,brohn_delivery_app(store));while(!file.exists(file.path(folder,"stop.participant")))httpuv::service(50);httpuv::stopServer(server);brohn_close_store(store)}
}else local({store<-brohn_open_store(file.path(folder,"workspace"));on.exit(brohn_close_store(store),add=TRUE);brohn_initialise_library(store)
  if(mode=="setup"){
    stopifnot(!file.exists(config_path));file.copy("examples/stimuli/sample-design-a.png",file.path(folder,"first.png"));file.copy("examples/stimuli/sample-design-b.png",file.path(folder,"second.png"));writeBin(charToRaw(paste(rep("Invalid original PNG",5),collapse=" ")),file.path(folder,"bad.png"))
    d<-brohn_new_design("Original illustrated MaxDiff study","survey");d$instructions<-"";d$questions<-list(brohn_question("Original opening question","single_choice","before","q-driver"),brohn_question("Original conditional detail","text","before","q-detail"),brohn_question("Original final question","number","end","q-final"))
    d$questions[[1]]$options<-list(list(id="yes",label="Show detail",value=1),list(id="no",label="Skip detail",value=0));d$questions[[2]]$show_if<-list(op="equals",question_id="q-driver",value=1);d$questionnaire_navigation<-brohn_questionnaire_navigation()
    first<-brohn_maxdiff_new("Original required image choices","md-required");first$sets<-first$sets[1:2];first$settings$prompt<-"Which original material is most and least useful?"
    optional<-brohn_maxdiff_new("Original optional image choices","md-optional");optional$items<-optional$items[1:3];optional$sets<-list(list(id="optional-set",item_ids=as.list(brohn_ids(optional$items))));optional$settings$required<-FALSE;optional$settings$prompt<-"Choose an optional original pair or skip."
    d$maxdiff<-list(first,optional);for(id in c("item-2","item-4"))d<-brohn_material_attach_png(store,d,"maxdiff_item",id,"md-required",path=file.path(folder,"first.png"),image_alt=paste("Original required",id,"illustration"))
    d<-brohn_material_attach_png(store,d,"maxdiff_item","item-1","md-optional",path=file.path(folder,"first.png"),image_alt="Original optional item-1 illustration")
    for(id in c("q-detail","q-final"))d<-brohn_material_attach_png(store,d,"question",id,path=file.path(folder,"first.png"),image_alt=paste("Original",id,"illustration"))
    study<-brohn_put_entity(store,"study",d$id,d);brohn_write_json_file(list(workspace=store$root,researcher_port=httpuv::randomPort(min=20000L,max=34000L),participant_port=httpuv::randomPort(min=35000L,max=49000L),study=study,first_hash=digest::digest(file=file.path(folder,"first.png"),algo="sha256"),second_hash=digest::digest(file=file.path(folder,"second.png"),algo="sha256")),config_path)
  }else if(mode=="inspect"){runs<-brohn_runs(store);brohn_write_json_file(list(studies=brohn_studies(store),releases=brohn_deployments(store),runs=runs,events=setNames(lapply(runs,function(r)brohn_run_events(store,r$id)),vapply(runs,function(r)r$id,character(1))),jobs=brohn_list_jobs(store)),file.path(folder,"snapshot.json"))}
  else if(mode=="analyse"){
    repeat{claimed<-brohn_claim_job(store,"maxdiff-material-qa",120);if(is.null(claimed))break;stopifnot(claimed$operation=="analyse_run");brohn_process_job(store,claimed,timeout_seconds=180)}
    jobs<-brohn_list_jobs(store);stopifnot(length(jobs)==1L,jobs[[1]]$status=="succeeded");report<-brohn_get_entity(store,"report",jobs[[1]]$result$report_id);run<-brohn_run(store,jobs[[1]]$request$run_id)
    stopifnot(run$completion_status=="completed",identical(brohn_hash(report$body$provenance$design),run$protocol$design_hash),length(report$body$analysis$choice_tasks)==2L)
    results<-report$body$analysis$choice_tasks;stopifnot(all(vapply(results,function(r)identical(brohn_hash(r$design),r$design_hash),logical(1))),results[[1]]$quality$answered_exposures==2L,results[[2]]$exposures[[1]]$status=="missing",results[[2]]$exposures[[1]]$missing_reason=="explicit_optional_omission")
    brohn_write_json_file(list(passed=TRUE,run_id=run$id,report_id=report$id,design_hash=run$protocol$design_hash,analysis=report$body$analysis),file.path(folder,"worker-results.json"))
  }else stop("Unknown MaxDiff material fixture mode")
})

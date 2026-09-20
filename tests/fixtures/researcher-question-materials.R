# Original synthetic illustrations; real authoring, receiver and analysis routes.
args<-commandArgs(trailingOnly=TRUE);mode<-args[[1L]]
source("R/platform-load.R",encoding="UTF-8");brohn_load(ui=TRUE)
folder<-normalizePath(args[[2L]],winslash="/",mustWork=TRUE);stopifnot(startsWith(basename(folder),"brohn-question-materials-"));config_path<-file.path(folder,"fixture.json")
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
    stopifnot(!file.exists(config_path));file.copy("examples/stimuli/sample-design-a.png",file.path(folder,"first.png"));file.copy("examples/stimuli/sample-design-b.png",file.path(folder,"second.png"));writeBin(charToRaw("Original invalid PNG"),file.path(folder,"bad.png"))
    d<-brohn_new_design("Original illustrated branching survey","survey");d$instructions<-"";d$questions<-list(
      brohn_question("Original branch choice","single_choice","end","q-driver"),brohn_question("Original dependent detail","text","end","q-detail"),brohn_question("Original dependent child","text","end","q-child"),brohn_question("Original information","information","end","q-info"),brohn_question("Original independent number","number","end","q-final"))
    d$questions[[1]]$options<-list(list(id="yes",label="Show detail",value=1),list(id="no",label="Skip detail",value=0));d$questions[[2]]$show_if<-list(op="equals",question_id="q-driver",value=1);d$questions[[3]]$show_if<-list(op="answered",question_id="q-detail")
    d$questionnaire_navigation<-brohn_questionnaire_navigation();d$questionnaire_sections<-brohn_question_sections_new(d)
    for(i in 2:5)d<-brohn_material_attach_png(store,d,"question",d$questions[[i]]$id,path=file.path(folder,"first.png"),image_alt=paste("Original illustration for",d$questions[[i]]$id))
    study<-brohn_put_entity(store,"study",d$id,d)
    legacy<-brohn_new_design("Original twelve illustrated question types","survey");legacy$instructions<-"";types<-c("rating","single_choice","multiple_choice","dropdown","text","long_text","number","slider","matrix","ranking","allocation","information")
    legacy$questions<-lapply(types,function(type){q<-brohn_question(paste("Original",type,"question"),type,"end",paste0("q-",gsub("_","-",type)));if(type=="matrix")q$rows<-list(list(id="row-one",label="Original row"));if(type=="allocation")q$options<-q$options[1:2];q})
    for(q in legacy$questions)legacy<-brohn_material_attach_png(store,legacy,"question",q$id,path=file.path(folder,"first.png"),image_alt=paste("Original",q$type,"illustration"))
    legacy<-brohn_put_entity(store,"study",legacy$id,legacy);legacy_release<-brohn_publish(store,legacy$id,"sample")
    repeated<-brohn_new_design("Original repeated illustrated occurrences");repeated$instructions<-"";repeated$baseline_ms<-0;repeated$fixation_ms<-0;repeated$order<-"fixed";for(i in seq_along(repeated$stimuli)){repeated$stimuli[[i]]$content<-paste("Original short context",i);repeated$stimuli[[i]]$duration_ms<-100}
    repeated$questions<-list(brohn_question("Original repeated question","text","after_each","q-repeated"));repeated<-brohn_material_attach_png(store,repeated,"question","q-repeated",path=file.path(folder,"first.png"),image_alt="Original repeated illustration");repeated<-brohn_put_entity(store,"study",repeated$id,repeated);repeated_release<-brohn_publish(store,repeated$id,"sample")
    brohn_write_json_file(list(workspace=store$root,researcher_port=httpuv::randomPort(min=20000L,max=34000L),participant_port=httpuv::randomPort(min=35000L,max=49000L),study=study,legacy=legacy,legacy_release=legacy_release,repeated=repeated,repeated_release=repeated_release,first_hash=digest::digest(file=file.path(folder,"first.png"),algo="sha256"),second_hash=digest::digest(file=file.path(folder,"second.png"),algo="sha256")),config_path)
  }else if(mode=="inspect"){runs<-brohn_runs(store);brohn_write_json_file(list(studies=brohn_studies(store),releases=brohn_deployments(store),runs=runs,events=setNames(lapply(runs,function(r)brohn_run_events(store,r$id)),vapply(runs,function(r)r$id,character(1))),jobs=brohn_list_jobs(store)),file.path(folder,"snapshot.json"))}
  else if(mode=="analyse"){
    reports<-list();repeat{claimed<-brohn_claim_job(store,"question-illustration-qa",120);if(is.null(claimed))break;stopifnot(identical(claimed$operation,"analyse_run"));brohn_process_job(store,claimed,timeout_seconds=180)}
    for(job in brohn_list_jobs(store))if(job$operation=="analyse_run"){
      finished<-brohn_get_job(store,job$id);if(finished$status!="succeeded")stop(brohn_json(finished$error));report<-brohn_get_entity(store,"report",finished$result$report_id);run<-brohn_run(store,job$request$run_id)
      stopifnot(identical(brohn_hash(report$body$provenance$design),run$protocol$design_hash),identical(report$body$origin,"sample"),identical(run$completion_status,"completed"),brohn_has_question_illustrations(report$body$provenance$design))
      if(!is.null(report$body$analysis$questionnaire_revision)){
        records<-report$body$analysis$questionnaire_revision$runs[[1]]$effective_records
        answer<-function(id)Filter(function(x)x$question_id==id,records)[[1]]
        stopifnot(answer("q-driver")$value==1,answer("q-detail")$value=="Original reopened branch draft",isTRUE(answer("q-detail")$resumed),answer("q-child")$value=="Original revised child answer",answer("q-final")$value==3,answer("q-info")$status=="information_acknowledged",is.null(answer("q-info")$value))
      }
      reports[[length(reports)+1L]]<-list(id=report$id,run_id=run$id,design_hash=brohn_hash(report$body$provenance$design),origin=report$body$origin,questionnaire=report$body$analysis)
    };stopifnot(length(reports)==3L);brohn_write_json_file(list(passed=TRUE,reports=reports),file.path(folder,"worker-results.json"))
  }else stop("Unknown question material fixture mode")
})

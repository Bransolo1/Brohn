# Fresh original synthetic content for an actual researcher/participant journey.
args <- commandArgs(trailingOnly = TRUE); mode <- args[[1L]]
source("R/platform-load.R", encoding = "UTF-8"); brohn_load(ui = TRUE)
folder <- normalizePath(args[[2L]], winslash = "/", mustWork = TRUE)
stopifnot(startsWith(basename(folder), "brohn-welcome-"))
config_path <- file.path(folder, "fixture.json")
if (mode %in% c("researcher","participant")) {
  config <- brohn_read_json_file(config_path)
  if (mode == "researcher") {
    Sys.setenv(BROHN_WORKSPACE=config$workspace,BROHN_APP_MODE="platform",BROHN_PARTICIPANT_PORT=config$participant_port)
    stop_owned <- function() if(file.exists(file.path(folder,"stop.researcher")))shiny::stopApp() else later::later(stop_owned,.2)
    later::later(stop_owned,.2)
    shiny::runApp(".",host="127.0.0.1",port=config$researcher_port,launch.browser=FALSE)
  } else {
    store <- brohn_open_store(config$workspace)
    server <- httpuv::startServer("127.0.0.1",config$participant_port,brohn_delivery_app(store))
    while(!file.exists(file.path(folder,"stop.participant")))httpuv::service(50)
    httpuv::stopServer(server);brohn_close_store(store)
  }
} else local({
  store <- brohn_open_store(file.path(folder,"workspace"));on.exit(brohn_close_store(store),add=TRUE)
  if(mode=="setup"){
    stopifnot(!file.exists(config_path));brohn_initialise_library(store)
    stopifnot(file.copy("examples/stimuli/sample-design-a.png",file.path(folder,"original-welcome.png")),
      file.copy("examples/stimuli/sample-design-b.png",file.path(folder,"replacement-welcome.png")))
    writeBin(charToRaw("Original deliberately invalid image fixture"),file.path(folder,"invalid.png"))
    brohn_write_json_file(list(schema="brohn-welcome-qa/1.0",workspace=store$root,
      researcher_port=httpuv::randomPort(min=20000L,max=35000L),participant_port=httpuv::randomPort(min=35001L,max=49000L),
      original_image_hash=digest::digest(file=file.path(folder,"original-welcome.png"),algo="sha256"),
      replacement_image_hash=digest::digest(file=file.path(folder,"replacement-welcome.png"),algo="sha256")),config_path)
  } else if(mode=="inspect") {
    brohn_write_json_file(list(studies=brohn_studies(store),templates=brohn_list_entities(store,"template"),
      releases=brohn_deployments(store),runs=brohn_runs(store)),file.path(folder,"snapshot.json"))
  } else if(mode=="analyse"){
    runs<-brohn_runs(store);stopifnot(length(runs)==1L,runs[[1L]]$completion_status=="completed",!is.null(runs[[1L]]$protocol$design$welcome))
    run<-runs[[1L]];source_hash<-brohn_hash(run$protocol$design)
    jobs<-Filter(function(j)j$operation=="analyse_run"&&identical(j$request$run_id,run$id),brohn_list_jobs(store));stopifnot(length(jobs)==1L)
    job<-jobs[[1L]]
    if(job$status=="queued"){
      claimed<-brohn_claim_job(store,"welcome-automatic-qa",90);stopifnot(identical(claimed$id,job$id));brohn_process_job(store,claimed,timeout_seconds=120)
    }
    finished<-brohn_get_job(store,job$id);if(finished$status!="succeeded")stop(brohn_json(finished$error))
    report<-brohn_get_entity(store,"report",finished$result$report_id);config<-brohn_read_json_file(config_path)
    stopifnot(identical(report$body$provenance$design$welcome$asset$hash,config$original_image_hash),identical(brohn_hash(report$body$provenance$design),source_hash),
      "R/platform-welcome.R" %in% names(report$body$processing$code_hashes),report$body$origin=="sample",
      any(vapply(report$body$analysis$observations,function(o)identical(o$value,"Synthetic browser response about the original pack."),logical(1))))
    brohn_write_json_file(list(passed=TRUE,run_id=run$id,job_id=job$id,report_id=report$id,report_hash=brohn_hash(report$body),frozen_design_hash=source_hash),file.path(folder,"welcome-worker-acceptance.json"))
  } else if(mode=="legacy"){
    d <- brohn_new_design("Original legacy entry","survey","study-welcome-legacy")
    d$questions<-list(brohn_question("Original legacy response","text","end","question-legacy"))
    s<-brohn_put_entity(store,"study",d$id,d);release<-brohn_publish(store,s$id,"sample")
    brohn_write_json_file(release,file.path(folder,"legacy.json"))
  } else stop("Unknown welcome fixture mode")
})

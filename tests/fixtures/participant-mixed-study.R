# One mixed frozen protocol: welcome, equipment, images, questions, RT and choices.
args<-commandArgs(trailingOnly=TRUE);stopifnot(length(args)==2L)
mode<-args[[1]];folder<-normalizePath(args[[2]],winslash="/",mustWork=TRUE)
stopifnot(startsWith(basename(folder),"brohn-mixed-study-"))
source("R/platform-load.R",encoding="UTF-8");brohn_load(ui=FALSE)
local({
  store<-brohn_open_store(file.path(folder,"workspace"));on.exit(brohn_close_store(store),add=TRUE)
  config_path<-file.path(folder,"fixture.json")
  if(mode=="setup") {
    stopifnot(!file.exists(config_path));brohn_initialise_library(store)
    d<-brohn_new_design("Original complete mixed study","comparison")
    d$instructions<-"Complete the original sample activities in order. This is software QA, not a participant study."
    d$welcome<-brohn_new_welcome("Welcome to the original mixed study")
    d$welcome$text<-"Two original pictures, short questions, a key task and image choices."
    d$participant_equipment$controls<-TRUE;d$fixation_ms<-100L
    for(i in seq_along(d$stimuli))d$stimuli[[i]]$duration_ms<-600L
    d$questions<-list(brohn_question("Original opening rating",scope="before",id="q-opening"),
      brohn_question("Original picture rating",scope="after_each",id="q-picture"),
      brohn_question("Original final rating",scope="end",id="q-final"))
    d$blocks<-list(brohn_task_new("rt-deary-liewald-simple/1.0","Original mixed key task","task-mixed"))
    d$blocks[[1]]$settings$intertrial_ms<-100L
    d$maxdiff<-list(brohn_maxdiff_new("Original mixed image choices","md-mixed"))
    d$camera<-list(schema="brohn-camera-policy/1.0",required=TRUE,audio=FALSE,
      consent_text="Record the original generated software QA frames throughout this mixed study.",
      retention_text="Generated QA data stay in this isolated local test workspace.",
      width=320L,height=240L,frame_rate=15L,max_duration_s=600,max_bytes=32*1024^2,analysis_profile="none")
    picture<-"examples/stimuli/sample-design-a.png"
    d<-brohn_attach_welcome_png(store,d,picture,image_alt="Original shared welcome picture")
    d<-brohn_material_attach_png(store,d,"question","q-opening",path=picture,image_alt="Original opening question picture")
    d<-brohn_material_attach_png(store,d,"question","q-final",path=picture,image_alt="Original final question picture")
    d<-brohn_material_attach_png(store,d,"stimulus","stimulus-a",path=picture,image_alt="Original passive picture A")
    d<-brohn_material_attach_png(store,d,"stimulus","stimulus-b",path="examples/stimuli/sample-design-b.png",image_alt="Original passive picture B")
    for(id in brohn_ids(d$maxdiff[[1]]$items))d<-brohn_material_attach_png(store,d,"maxdiff_item",id,"md-mixed",path=picture,image_alt=paste("Original choice picture",id))
    study<-brohn_put_entity(store,"study",d$id,d)
    release<-brohn_publish(store,d$id,origin="sample",quota=1L,alias_required=TRUE)
    brohn_write_json_file(list(workspace=store$root,study=study,release=release,
      port=httpuv::randomPort(min=20000L,max=49000L)),config_path)
  } else if(mode=="serve") {
    config<-brohn_read_json_file(config_path)
    server<-httpuv::startServer("127.0.0.1",config$port,brohn_delivery_app(store))
    on.exit(httpuv::stopServer(server),add=TRUE)
    while(!file.exists(file.path(folder,"stop.request")))httpuv::service(50)
  } else if(mode=="analyse") {
    jobs<-list()
    repeat {
      job<-brohn_claim_job(store,"mixed-study-qa",180);if(is.null(job))break
      brohn_process_job(store,job,timeout_seconds=300);done<-brohn_get_job(store,job$id)
      stopifnot(done$status=="succeeded");jobs[[length(jobs)+1L]]<-done
    }
    runs<-brohn_runs(store);stopifnot(length(runs)==1L,runs[[1]]$completion_status=="completed",runs[[1]]$transfer_status=="saved")
    run<-runs[[1]];reports<-brohn_list_entities(store,"report",limit=100L)
    report<-Filter(function(r)identical(r$body$kind,"session")||identical(r$body$processing$operation,"analyse_run"),reports)
    if(!length(report))report<-Filter(function(r)length(r$body$analysis$choice_tasks)>0,reports)
    stopifnot(length(report)==1L);report<-report[[1]]
    capture<-brohn_capture(store,run_id=run$id);published<-brohn_get_entity(store,"camera_capture",capture$id)
    events<-brohn_run_events(store,run$id);equipment<-brohn_equipment_evidence(store,run$id)
    stopifnot(identical(brohn_hash(report$body$provenance$design),run$protocol$design_hash),
      length(report$body$analysis$choice_tasks)==1L,length(equipment$checks)==3L,
      capture$status=="completed",published$body$assembly$decoder$video_frames>0)
    brohn_write_json_file(list(passed=TRUE,run=run,report=report,events=events,equipment=equipment,
      capture=published,jobs=jobs),file.path(folder,"acceptance.json"))
  } else stop("Unknown mixed-study fixture mode")
})

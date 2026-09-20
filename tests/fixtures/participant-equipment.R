args <- commandArgs(trailingOnly = TRUE)
arg <- function(name) {i<-match(name,args);stopifnot(!is.na(i));args[[i+1L]]}
mode<-args[[1L]];folder<-normalizePath(arg("--folder"),winslash="/",mustWork=TRUE)
stopifnot(grepl("^brohn-participant-equipment-",basename(folder)))
if(mode=="serve"){
  check_stop<-function(){if(file.exists(file.path(folder,"stop.request")))httpuv::interrupt() else later::later(check_stop,.2)}
  later::later(check_stop,.2);source("scripts/run-participant.R",encoding="UTF-8")
} else {
  source("R/platform-load.R");brohn_load(ui=TRUE)
  local({store<-brohn_open_store(arg("--root"));on.exit(brohn_close_store(store),add=TRUE)
    if(mode=="prepare"){
      releases<-list()
      for(name in c("camera","optional","audio","keyboard","controls","legacy")){
        d<-brohn_new_design(paste("Original participant equipment",name),"survey");d$instructions<-"Original untimed study instructions."
        d$questions<-list(brohn_question("Original final equipment rating",scope="end"))
        if(name %in% c("camera","optional","audio"))d$camera<-list(schema="brohn-camera-policy/1.0",required=name!="optional",audio=name=="audio",
          consent_text="Original generated QA video and optional audio, with explicit recording agreement.",retention_text="Only synthetic software QA in this isolated workspace.",
          width=320L,height=240L,frame_rate=15L,max_duration_s=90,max_bytes=16*1024^2,analysis_profile=if(name=="camera")"face_geometry_v1" else "none")
        if(name=="keyboard")d$blocks<-list(brohn_task_new("rt-deary-liewald-simple/1.0","Original key check task"))
        if(name=="controls")d$participant_equipment$controls<-TRUE
        if(name=="legacy")d$participant_equipment<-NULL
        brohn_put_entity(store,"study",d$id,d);releases[[name]]<-brohn_publish(store,d$id,origin="sample",quota=30L,alias_required=TRUE)
      }
      brohn_write_json_file(releases,file.path(folder,"fixture.json"))
    }else if(mode=="work"){
      for(i in 1:20){j<-brohn_claim_job(store,"original-equipment-worker",lease_seconds=120);if(is.null(j))break
        brohn_process_job(store,j,timeout_seconds=120);done<-brohn_get_job(store,j$id);if(done$status!="succeeded")stop(brohn_json(done$error))}
    }else if(mode=="inspect"){
      runs<-lapply(brohn_runs(store),function(r){c<-brohn_capture(store,run_id=r$id);list(run=r,events=brohn_run_events(store,r$id),equipment=brohn_equipment_evidence(store,r$id),capture=c,
        publication=if(is.null(c))NULL else brohn_get_entity(store,"camera_capture",c$id),jobs=brohn_list_jobs(store,1000L,list(run_id=r$id)))})
      reports<-brohn_list_entities(store,"report",limit=1000L)
      brohn_write_json_file(list(runs=runs,jobs=brohn_list_jobs(store,1000L),reports=lapply(reports,function(x)brohn_get_entity(store,"report",x$id))),file.path(folder,"inspection.json"))
    }else stop("Unknown original equipment fixture mode")
  })
}

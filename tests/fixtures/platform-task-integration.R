source("R/platform-participant-equipment.R") # Registered optional new-draft policy.
# Original synthetic task studies; CLI fixture creates/inspects actual persistence.
args<-commandArgs(trailingOnly=TRUE);stopifnot(length(args)==3L)
for(module in c("platform-core","platform-methods","platform-store","platform-delivery","platform-task-delivery"))source(paste0("R/",module,".R"))
local({
  store<-brohn_open_store(args[2]);on.exit(brohn_close_store(store))
  if(args[1]=="prepare") {
    result<-list()
    profiles<-c(simple="rt-deary-liewald-simple/1.0",iat="iat-gnb2003-d1/1.0",interruption="rt-deary-liewald-simple/1.0")
    for(name in names(profiles)) {
      design<-brohn_new_design(paste("Original synthetic",name,"integration"),"blank",id=paste0("task-integration-",name))
      design$participant_equipment<-NULL # Historical task renderer/receiver regression; modern checks have their own journey.
      design$instructions<-"";design$blocks<-list(brohn_task_new(profiles[[name]],paste("Synthetic",name),id=paste0("task-",name)))
      design$blocks[[1]]$settings$intertrial_ms<-100L
      if(name=="iat") {
        # Original fixture image is authorized only through this release.
        file<-tempfile(fileext=".png");png::writePNG(array(rep(c(.1,.4,.8),each=16*16),c(16,16,3)),file)
        asset<-brohn_store_object(store,path=file,media_type="image/png");unlink(file)
        design$blocks[[1]]$materials[[1]]$type<-"image";design$blocks[[1]]$materials[[1]]$asset<-asset
      }
      brohn_put_entity(store,"study",design$id,design)
      result[[name]]<-brohn_publish(store,design$id,origin="pilot",quota=10L,alias_required=TRUE)
    }
  } else if(args[1]=="inspect") {
    result<-lapply(brohn_runs(store),function(r)list(id=r$id,study_id=r$study_id,completion=r$completion_status,
      transfer=r$transfer_status,design_hash=r$protocol$design_hash,events=brohn_run_events(store,r$id),protocol=r$protocol))
  } else stop("Unknown fixture action")
  writeBin(charToRaw(enc2utf8(brohn_json(result))),args[3])
})

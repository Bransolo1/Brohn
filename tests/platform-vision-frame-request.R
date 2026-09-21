source("R/platform-load.R",encoding="UTF-8");brohn_load(ui=FALSE);source("R/platform-vision-frame.R",encoding="UTF-8")
local({
  checks<-0L;expect<-function(request,label){error<-tryCatch({brohn_vision_frame_input(NULL,list(operation="vision_frame",request=request));NULL},error=identity)
    stopifnot(inherits(error,"error"));checks<<-checks+1L;cat("PASS",label,":",conditionMessage(error),"\n")}
  r<-list(schema="brohn-vision-frame-job/1.0",recipe=.brohn_vframe_recipe,index_id="vision-index-test",index_hash=paste(rep("a",64),collapse=""),
    report_id="report-test",report_revision=1L,report_hash=paste(rep("b",64),collapse=""),project_id="default",frame=list(frame_index=0L),implementation=.brohn_vframe_loaded)
  wrong<-r;wrong$recipe<-"other-extraction/1.0";expect(wrong,"Mismatched extraction recipe rejects before store access")
  wrong<-r;wrong$source_path<-"untrusted path";expect(wrong,"Extra browser-supplied path rejects before store access")
  wrong<-r;wrong$frame<-NULL;expect(wrong,"Missing exact frame rejects before store access")
  wrong<-r;wrong$implementation[["R/platform-vision-explorer.R"]]<-paste(rep("c",64),collapse="");expect(wrong,"Changed index authority implementation rejects before store access")
  stopifnot(identical(.brohn_vframe_loaded[["R/platform-vision-explorer.R"]],digest::digest(file="R/platform-vision-explorer.R",algo="sha256")));checks<-checks+1L
  cat("PASS",checks,"recorded frame request checks\n")
})

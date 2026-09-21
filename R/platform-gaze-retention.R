# Original source ownership for newly retained sampled pupil/blink evidence.
brohn_check_gaze_analysis_source <- function(store,input,verify_bytes=TRUE) {
  brohn_require(brohn_gaze_retention_enabled(input),"Choose a sampled gaze source with mapped pupil or source blink labels.")
  d<-input$dataset
  .brohn_qexplorer_catalog(store,"dataset",d$id,input$dataset_revision,input$project_id)
  brohn_project(store,input$project_id)
  pinned<-brohn_get_entity(store,"dataset",d$id,input$dataset_revision)
  brohn_require(identical(brohn_hash(pinned$body),brohn_hash(d)),"The pinned gaze source or mapping changed.")
  if(!is.null(input$design)) {
    .brohn_qexplorer_catalog(store,"study",input$design$id,input$design_revision,input$project_id)
    design<-brohn_study(store,input$design$id,input$design_revision)
    brohn_require(identical(brohn_hash(design$body),brohn_hash(input$design)),"The pinned gaze study changed.")
  }
  path<-brohn_object_path(store,d$source$hash,verify=verify_bytes)
  brohn_require(identical(normalizePath(path,winslash="/",mustWork=TRUE),normalizePath(input$source_path,winslash="/",mustWork=TRUE))&&
    identical(as.numeric(file.info(path)$size),as.numeric(d$source$size)),"The original gaze source path or byte count changed.")
  invisible(TRUE)
}

brohn_hold_gaze_analysis_source <- function(store,input) {
  brohn_require(.Platform$OS.type=="windows","Complete pupil/blink retention requires the qualified native Windows source guard.")
  brohn_check_gaze_analysis_source(store,input,verify_bytes=FALSE)
  guard<-.brohn_qexplorer_hold(input$source_path,input$dataset$source$size)
  success<-FALSE;on.exit(if(!success).brohn_qexplorer_release(guard),add=TRUE)
  brohn_check_gaze_analysis_source(store,input,verify_bytes=TRUE)
  success<-TRUE;guard
}

brohn_analyse_gaze_retained <- function(data,metadata,design,input,scratch) {
  brohn_require(brohn_gaze_retention_enabled(input),"This source does not declare a pupil/blink trace.")
  brohn_require(identical(digest::digest(file=input$source_path,algo="sha256"),input$dataset$source$hash),"Original gaze bytes changed before trace retention.")
  sink<-brohn_gaze_trace_sink(scratch,data,metadata);on.exit(sink$abort(),add=TRUE)
  analysis<-brohn_raw_gaze_analysis(data,metadata,design,sink)
  paths<-c("R/platform-gaze.R","R/platform-gaze-retention.R","R/platform-gaze-traces.R","scripts/workers/gaze_trace.py","scripts/workers/physiology_artifacts.py")
  hashes<-stats::setNames(lapply(paths,function(path)digest::digest(file=path,algo="sha256")),paths)
  provenance<-list(source_sha256=input$dataset$source$hash,
    engine=list(name="Brohn sampled gaze with complete pupil and source-labelled blink retention",worker_sha256=hashes[["R/platform-gaze.R"]],
      r_version=as.character(getRversion()),code_hashes=hashes),operation="gaze",origin=input$dataset$origin,
    parameters=list(mapping=metadata,analysis=analysis$parameters,dataset_id=input$dataset$id,dataset_revision=input$dataset_revision,
      design_hash=if(is.null(design))NULL else brohn_hash(design),design_revision=input$design_revision))
  sink$finish(analysis,provenance)
}

# Focused current-source continuation over the already generated/assembled fixture.
source("R/platform-load.R",encoding="UTF-8");brohn_load(ui=FALSE)
source("R/platform-camera-analysis.R",encoding="UTF-8");source("R/platform-camera-analysis-store.R",encoding="UTF-8")
local({
  args<-commandArgs(trailingOnly=TRUE);stopifnot(length(args)==2L,dir.exists(args[[1L]]),!dir.exists(args[[2L]]));dir.create(args[[2L]],recursive=TRUE)
  parent<-brohn_read_json_file(file.path(args[[1L]],"results.json"));stopifnot(parent$status=="passed",parent$count==19L)
  store<-brohn_open_store(file.path(args[[1L]],"workspace"));on.exit(brohn_close_store(store),add=TRUE)
  checks<-character();check<-function(label,value){stopifnot(isTRUE(value));checks<<-c(checks,label);cat("PASS",label,"\n")}
  read_original<-function()lapply(c("camera_captures","camera_chunks","delivery_runs","delivery_events","delivery_receipts","entities","entity_versions","jobs"),function(name)DBI::dbReadTable(store$con,name))
  before<-read_original();source_objects<-DBI::dbGetQuery(store$con,"SELECT hash,size FROM objects ORDER BY hash")
  a<-brohn_get_entity(store,"dataset",parent$authority$dataset_id,parent$authority$dataset_revision)
  check("Current resolver preserves prior exact completed-source authority",identical(brohn_hash(parent$authority),brohn_hash(brohn_camera_analysis_resolve(store,a,"manual",TRUE))))
  sidecars<-brohn_list_entities(store,"session_resolution",project_id="default")
  for(record in sidecars){r<-brohn_get_entity(store,"session_resolution",record$id);run_id<-r$body$run_id;capture<-brohn_capture(store,run_id=run_id)
    d<-brohn_get_entity(store,"dataset",paste0("dataset-",capture$id));resolved<-try(brohn_camera_analysis_resolve(store,d,"manual",TRUE),silent=TRUE)
    if(identical(r$body$participant_ending$outcome,"withdrawn"))check("Current resolver still refuses actual received-withdrawal sidecar",inherits(resolved,"try-error"))else
      check("Current resolver retains exact original interruption-resolution reference",!inherits(resolved,"try-error")&&identical(resolved$session_resolution$hash,brohn_hash(r$body)))
  }
  # Temporarily bypass one immutable trigger inside a rollback-only fixture
  # transaction to prove refusal of mismatched source identities, not just bytes.
  original<-DBI::dbGetQuery(store$con,"SELECT * FROM camera_chunks WHERE capture_id=?",params=list(parent$authority$capture_id))
  other<-DBI::dbGetQuery(store$con,"SELECT observation_hash FROM camera_chunks WHERE capture_id<>? LIMIT 1",params=list(parent$authority$capture_id))
  stopifnot(nrow(original)==1L,nrow(other)==1L)
  DBI::dbBegin(store$con)
  failure<-tryCatch({DBI::dbExecute(store$con,"DROP TRIGGER camera_chunks_no_update");DBI::dbExecute(store$con,"UPDATE camera_chunks SET observation_hash=? WHERE capture_id=?",params=list(other$observation_hash[[1L]],parent$authority$capture_id));
    tryCatch({brohn_camera_analysis_resolve(store,a,"manual",TRUE);NULL},error=function(e)conditionMessage(e))},finally=DBI::dbRollback(store$con))
  check("Actual substituted SQLite observation identity is refused against complete assembly manifest",is.character(failure)&&grepl("chunk identities differ",failure,fixed=TRUE))
  check("Rollback restores every original SQL row and the immutable chunk trigger",identical(before,read_original())&&nrow(DBI::dbGetQuery(store$con,"SELECT name FROM sqlite_master WHERE type='trigger' AND name='camera_chunks_no_update'"))==1L)
  check("Every retained original object still has its exact registered hash and byte count",all(vapply(seq_len(nrow(source_objects)),function(i){path<-brohn_object_path(store,source_objects$hash[[i]],verify=TRUE);file.info(path)$size==source_objects$size[[i]]},logical(1))))
  brohn_write_json_file(list(status="passed",count=length(checks),checks=as.list(checks),parent_receipt_hash=digest::digest(file=file.path(args[[1L]],"results.json"),algo="sha256"),
    source_hash=digest::digest(file="R/platform-camera-analysis-store.R",algo="sha256"),test_hash=digest::digest(file="tests/platform-camera-analysis-store-retained.R",algo="sha256"),
    scope="Focused continuation on three retained actual camera assemblies. No child jobs or inference repeated; previous19-check receipt remains unchanged. Added exact SQLite chunk-to-manifest identity guard, source records restored after rollback-only fault injection."),file.path(args[[2L]],"results.json"));cat("TOTAL",length(checks),"\n")
})

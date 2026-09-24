# Paged researcher metadata, never a substitute for brohn_run's verified protocol
# or a participant authorization check. No schema writes occur during retrieval.
# SQLite >= 3.35 with JSON1 supports the explicit materialization boundary;
# qualification uses the pinned RSQLite SQLite 3.53.3 build. JSON CASE guards:
# https://www.sqlite.org/json1.html and https://www.sqlite.org/lang_expr.html
.brohn_run_catalog_scalar <- function(path, type="text", maximum=96L) {
  # Paths and types are fixed by this module, never read from a UI request.
  value<-paste0("json_extract(p.protocol_json,'",path,"')")
  predicate<-if(type=="boolean")paste0("json_type(p.protocol_json,'",path,"') IN ('true','false')")else
    paste0("json_type(p.protocol_json,'",path,"')='text' AND length(",value,")<=",maximum)
  paste0("CASE WHEN json_valid(p.protocol_json) THEN CASE WHEN ",predicate," THEN ",value," END END")
}
.brohn_run_catalog_type <- function(path) paste0("CASE WHEN json_valid(p.protocol_json) THEN json_type(p.protocol_json,'",path,"') END")
.brohn_run_catalog_cell <- function(row, field) {
  value<-row[[field]][[1L]]
  if(is.na(value))NULL else unname(value)
}
.brohn_run_catalog_camera <- function(row) {
  cell<-function(field).brohn_run_catalog_cell(row,field)
  status<-"unavailable";reason<-NULL
  if(!isTRUE(cell("protocol_json_valid")==1L))reason<-"The stored protocol JSON is unavailable or malformed. Open its assigned protocol to inspect the integrity issue."
  else if(!identical(cell("protocol_type"),"object")||!identical(cell("protocol_schema"),"brohn-protocol/1.0.0")||!identical(cell("design_type"),"object"))
    reason<-"This protocol version or design structure has no supported camera metadata projection."
  else if(is.null(cell("camera_type"))||identical(cell("camera_type"),"null"))status<-"not_requested"
  else if(!identical(cell("camera_type"),"object")||
    !(identical(cell("camera_schema"),"brohn-camera-policy/1.0")&&isTRUE(cell("camera_analysis")%in%c("none","face_geometry_v1"))||
      identical(cell("camera_schema"),"brohn-camera-policy/1.1")&&identical(cell("camera_analysis"),"facial_au_expression_pyfeat_v1"))||
    is.null(cell("camera_required"))||is.null(cell("camera_audio")))
    reason<-"The frozen camera policy version or its displayed fields are unavailable or invalid."
  else status<-"requested"
  list(status=status,schema=if(status=="requested")cell("camera_schema")else NULL,
    required=if(status=="requested")as.logical(cell("camera_required"))else NULL,
    audio=if(status=="requested")as.logical(cell("camera_audio"))else NULL,
    analysis_profile=if(status=="requested")cell("camera_analysis")else NULL,
    reason=reason,evidence="catalog_projection_not_protocol_hash_verified")
}
.brohn_run_catalog_record <- function(row) {
  cell<-function(field).brohn_run_catalog_cell(row,field)
  supplied<-cell("participant_alias_supplied")
  if(!is.null(supplied)&&!supplied %in% c(0L,1L))supplied<-NULL
  protocol_hash<-cell("protocol_hash")
  if(!is.null(protocol_hash)&&!grepl("^[a-f0-9]{64}$",protocol_hash))protocol_hash<-NULL
  list(id=cell("id"),run_id=cell("id"),study_id=cell("study_id"),project_id=cell("project_id"),
    deployment_id=cell("deployment_id"),origin=cell("origin"),participant_alias=cell("participant_alias"),
    participant_alias_supplied=if(is.null(supplied))NULL else as.logical(supplied),
    allocation_index=cell("allocation_index"),completion_status=cell("completion_status"),
    transfer_status=cell("transfer_status"),acked_sequence=cell("acked_sequence"),
    created_at=cell("created_at"),updated_at=cell("updated_at"),finalized_at=cell("finalized_at"),
    protocol_hash=protocol_hash,protocol_schema=cell("protocol_schema"),
    camera_policy_summary=.brohn_run_catalog_camera(row),
    metadata_evidence="catalog_projection_not_protocol_hash_verified")
}

brohn_search_runs <- function(store, study_id, project_id=NULL, limit=40L, offset=0L) {
  .brohn_store_ready(store)
  brohn_require(brohn_valid_id(study_id)&&brohn_number(limit,1,100,TRUE)&&brohn_number(offset,0,1e8,TRUE),
    "Choose a valid study and participant-session page.")
  if(!is.null(project_id))brohn_require(brohn_valid_id(project_id),"Choose a valid project for participant sessions.")
  read<-function() {
    # Parent/project validation is part of the same read snapshot as count/page.
    # Archived studies remain retrievable; a missing/foreign parent has one error.
    parent_sql<-"SELECT id,project_id FROM entities WHERE kind='study' AND id=?"
    parameters<-list(study_id)
    if(!is.null(project_id)){parent_sql<-paste(parent_sql,"AND project_id=?");parameters<-c(parameters,list(project_id))}
    parent<-DBI::dbGetQuery(store$con,parent_sql,params=parameters)
    brohn_require(nrow(parent)==1L,"This study is unavailable in the selected project.")
    selected_project<-parent$project_id[[1L]]
    empty<-function()list(relation="study_runs",parent_id=study_id,project_id=selected_project,records=list(),
      total=0L,limit=limit,offset=0L,has_previous=FALSE,has_next=FALSE,label="participant sessions")
    has_runs<-DBI::dbExistsTable(store$con,"delivery_runs")
    has_deployments<-DBI::dbExistsTable(store$con,"delivery_deployments")
    if(!has_runs&&!has_deployments)return(empty())
    brohn_require(has_runs&&has_deployments,"Participant storage is incomplete. Reopen Brohn to check its workspace migration.")
    from<-paste("FROM delivery_runs r JOIN delivery_deployments d ON d.id=r.deployment_id AND d.study_id=r.study_id",
      "JOIN entities e ON e.kind='study' AND e.id=r.study_id AND e.project_id=d.project_id",
      "WHERE r.study_id=? AND d.project_id=? AND e.project_id=?")
    parameters<-list(study_id,selected_project,selected_project)
    total<-as.numeric(DBI::dbGetQuery(store$con,paste("SELECT count(*) AS n",from),params=parameters)$n[[1L]])
    actual<-if(total)min(offset,floor((total-1)/limit)*limit)else 0L
    # Only the selected page enters the JSON projection. Neither protocol_json
    # nor any credential/client/receipt field crosses the DBI result boundary.
    columns<-c("id","study_id","deployment_id","origin","participant_alias","allocation_index","completion_status",
      "transfer_status","acked_sequence","created_at","updated_at","finalized_at")
    alias_column<-if("participant_alias_supplied" %in% DBI::dbListFields(store$con,"delivery_runs"))
      "r.participant_alias_supplied"else"NULL AS participant_alias_supplied"
    inner_columns<-paste(c(paste0("r.",columns),alias_column,"r.protocol_json",
      "CASE WHEN length(r.protocol_hash)=64 THEN r.protocol_hash END AS protocol_hash","d.project_id"),collapse=",")
    projection<-paste(c(paste0("p.",columns),"p.participant_alias_supplied","p.protocol_hash","p.project_id",
      "json_valid(p.protocol_json) AS protocol_json_valid",
      paste(.brohn_run_catalog_type("$"),"AS protocol_type"),
      paste(.brohn_run_catalog_scalar("$.schema_version"),"AS protocol_schema"),
      paste(.brohn_run_catalog_type("$.design"),"AS design_type"),
      paste(.brohn_run_catalog_type("$.design.camera"),"AS camera_type"),
      paste(.brohn_run_catalog_scalar("$.design.camera.schema"),"AS camera_schema"),
      paste(.brohn_run_catalog_scalar("$.design.camera.required","boolean"),"AS camera_required"),
      paste(.brohn_run_catalog_scalar("$.design.camera.audio","boolean"),"AS camera_audio"),
      paste(.brohn_run_catalog_scalar("$.design.camera.analysis_profile"),"AS camera_analysis")),collapse=",")
    sql<-paste("WITH page AS MATERIALIZED (SELECT",inner_columns,from,"ORDER BY r.created_at DESC,r.id ASC LIMIT ? OFFSET ?)",
      "SELECT",projection,"FROM page p ORDER BY p.created_at DESC,p.id ASC")
    rows<-DBI::dbGetQuery(store$con,sql,params=c(parameters,list(limit,actual)))
    records<-lapply(seq_len(nrow(rows)),function(i).brohn_run_catalog_record(rows[i,,drop=FALSE]))
    list(relation="study_runs",parent_id=study_id,project_id=selected_project,records=records,total=total,
      limit=limit,offset=actual,has_previous=actual>0,has_next=actual+nrow(rows)<total,label="participant sessions")
  }
  if(RSQLite::sqliteIsTransacting(store$con))read()else DBI::dbWithTransaction(store$con,read())
}

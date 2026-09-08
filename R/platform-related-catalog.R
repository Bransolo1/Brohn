# Related records are filtered in SQL before pagination. A busy workspace must
# not hide an older study's evidence behind a global recent-record limit.
brohn_source_report_choices <- function(store, study_id) {
  study <- brohn_study(store, study_id)
  rows <- DBI::dbGetQuery(store$con, paste("SELECT e.id,json_extract(v.body_json,'$.title') AS title,",
    "json_extract(v.body_json,'$.origin') AS origin,v.created_at FROM entities e JOIN entity_versions v",
    "ON e.kind=v.kind AND e.id=v.id AND e.revision=v.revision WHERE e.kind='report' AND e.project_id=?",
    "AND json_extract(v.body_json,'$.study_id')=? AND coalesce(json_extract(v.body_json,'$.analysis.kind'),'')!='multimodal'",
    "AND json_type(v.body_json,'$.provenance.design')='object' ORDER BY e.updated_at DESC,e.id ASC"), params = list(study$project_id, study_id))
  labels <- if (nrow(rows)) paste(rows$title, rows$origin, rows$created_at, substr(rows$id,pmax(1,nchar(rows$id)-5L),nchar(rows$id)),sep=" \u00b7 ") else character()
  stats::setNames(rows$id, labels)
}
brohn_related_spec <- function(relation) {
  specs <- list(study_runs=list(parent="study",kind="run",field="study_id",label="participant sessions"),
    study_datasets=list(parent="study",kind="dataset",field="study_id",label="datasets"),
    study_reports=list(parent="study",kind="report",field="study_id",label="reports"),
    study_migrations=list(parent="study",kind="migration",field="study_id",label="earlier imports"),
    dataset_reports=list(parent="dataset",kind="report",field="dataset_id",label="reports"),
    dataset_jobs=list(parent="dataset",kind="job",field="dataset_id",label="processing attempts"))
  brohn_require(brohn_text(relation,64) && relation %in% names(specs),"Choose a supported related-record view.")
  specs[[relation]]
}
brohn_search_related <- function(store, relation, parent_id, limit=40L, offset=0L) {
  if (identical(relation,"study_runs")) return(brohn_search_runs(store,parent_id,limit=limit,offset=offset))
  .brohn_store_ready(store);spec<-brohn_related_spec(relation)
  brohn_require(brohn_valid_id(parent_id) && brohn_number(limit,1,100,TRUE) && brohn_number(offset,0,1e8,TRUE),"Choose a valid related-record page.")
  parent<-brohn_get_entity(store,spec$parent,parent_id)
  brohn_require(!is.null(parent),"The source study or dataset is unavailable.")
  if(spec$kind=="job") {
    from<-"FROM jobs WHERE json_extract(request_json,'$.dataset_id')=?"
    parameters<-list(parent_id);columns<-"*";ordering<-"updated_at DESC,id ASC"
  } else {
    # spec$field is selected above from fixed literals, never supplied as SQL.
    from<-paste0("FROM entity_versions v JOIN entities e ON v.kind=e.kind AND v.id=e.id AND v.revision=e.revision ",
      "WHERE e.kind=? AND e.project_id=? AND json_extract(v.body_json,'$.",spec$field,"')=?")
    parameters<-list(spec$kind,parent$project_id,parent_id);columns<-"v.*";ordering<-"e.updated_at DESC,e.id ASC"
  }
  read<-function() {
    total<-as.integer(DBI::dbGetQuery(store$con,paste("SELECT count(*) AS n",from),params=parameters)$n[[1]])
    # A removed record can shorten the last page. Keep its remaining evidence
    # visible instead of rendering an empty page with an out-of-range offset.
    actual<-if(total) min(offset,floor((total-1)/limit)*limit) else 0L
    rows<-DBI::dbGetQuery(store$con,paste("SELECT",columns,from,"ORDER BY",ordering,"LIMIT ? OFFSET ?"),params=c(parameters,list(limit,actual)))
    records<-lapply(seq_len(nrow(rows)),function(i) if(spec$kind=="job") .brohn_store_job(rows[i,,drop=FALSE]) else .brohn_store_entity(rows[i,,drop=FALSE]))
    list(relation=relation,parent_id=parent_id,records=records,total=total,limit=limit,offset=actual,
      has_previous=actual>0,has_next=actual+nrow(rows)<total,label=spec$label)
  }
  if(RSQLite::sqliteIsTransacting(store$con)) read() else DBI::dbWithTransaction(store$con,read())
}
brohn_related_offset <- function(state,relation,parent_id) {
  if(is.null(state)) return(0L)
  brohn_default(state$related_offsets[[paste(relation,parent_id,sep=":")]],0L)
}
brohn_related_page_ui <- function(result) shiny::tagList(
  shiny::p(role="status",if(result$total) paste("Showing",result$offset+1L,"to",result$offset+length(result$records),"of",result$total,result$label) else paste("No saved",result$label)),
  if(result$has_previous || result$has_next) shiny::div(class="brohn-toolbar",
    if(result$has_previous) brohn_command(paste("Previous",result$label),"related_page",list(relation=result$relation,parent_id=result$parent_id,offset=result$offset,limit=result$limit,direction=-1L)),
    shiny::span(paste("Page",floor(result$offset/result$limit)+1L,"of",ceiling(result$total/result$limit))),
    if(result$has_next) brohn_command(paste("Next",result$label),"related_page",list(relation=result$relation,parent_id=result$parent_id,offset=result$offset,limit=result$limit,direction=1L))))
brohn_related_page_command <- function(store,state,command) {
  brohn_require(is.list(command),"Choose a related-record page.")
  brohn_fields(command,c("relation","parent_id","offset","limit","direction"),label="Related page")
  spec<-brohn_related_spec(command$relation)
  visible<-if(spec$parent=="dataset") identical(state$page,"dataset") && identical(state$dataset_id,command$parent_id) else
    identical(state$page,"study") && identical(state$study_id,command$parent_id) && state$stage %in% switch(command$relation,
      study_runs=c("Collect","Review"),study_datasets="Review",study_reports=c("Results","History"),study_migrations="History")
  brohn_require(isTRUE(visible) && brohn_number(command$offset,0,1e8,TRUE) && brohn_number(command$limit,40,40,TRUE) &&
    brohn_number(command$direction,-1,1,TRUE) && abs(command$direction)==1,
    "Return to this study or dataset before changing its page.")
  current<-brohn_search_related(store,command$relation,command$parent_id,offset=brohn_related_offset(state,command$relation,command$parent_id))
  brohn_require(identical(as.numeric(current$offset),as.numeric(command$offset)),"This list changed. Use its current page controls.")
  if((command$direction<0 && !current$has_previous) || (command$direction>0 && !current$has_next))return(invisible(FALSE))
  offsets<-brohn_default(state$related_offsets,list())
  offsets[[paste(command$relation,command$parent_id,sep=":")]]<-max(0,current$offset+command$direction*current$limit)
  state$related_offsets<-offsets;invisible(TRUE)
}

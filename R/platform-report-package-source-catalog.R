# UI catalogue descriptors are not source admission or scientific metadata.
# Existing complete report-choice, preparation, readers and workers are unchanged.
.brohn_rpk_choice_descriptor <- function(store,ref,study_id,project_id,allow_unavailable=FALSE) {
  .brohn_rpk_ref_valid(ref,"report")
  brohn_require(identical(ref$project_id,project_id),"Choose saved findings in this study's project.")
  .brohn_rpk_study(store,study_id,project_id)
  .brohn_rpk_ref_catalog(store,ref,"report")
  row<-DBI::dbGetQuery(store$con,paste(
    "SELECT json_extract(v.body_json,'$.id') AS body_id,json_extract(v.body_json,'$.study_id') AS study_id,",
    "json_extract(v.body_json,'$.title') AS title,json_type(v.body_json,'$.title') AS title_type,",
    "json_extract(v.body_json,'$.origin') AS origin,json_type(v.body_json,'$.origin') AS origin_type",
    "FROM entity_versions v JOIN entities e ON e.kind=v.kind AND e.id=v.id",
    "WHERE v.kind='report' AND v.id=? AND v.revision=? AND v.project_id=? AND e.project_id=? AND v.body_hash=?"),
    params=list(ref$id,ref$revision,project_id,project_id,ref$body_hash))
  brohn_require(nrow(row)==1L&&identical(row$body_id[[1L]],ref$id)&&identical(row$study_id[[1L]],study_id),
    "The exact saved findings are unavailable in this study; no different version was selected.")
  label<-function(name,fallback,maximum){value<-row[[name]][[1L]];type<-row[[paste0(name,"_type")]][[1L]]
    if(is.null(type)||is.na(type)||identical(type,"null"))return(list(valid=TRUE,value=fallback))
    valid<-isTRUE(identical(type,"text")&&brohn_text(value,maximum,TRUE))
    list(valid=valid,value=if(valid)value else fallback)}
  title<-label("title",ref$id,512L);origin<-label("origin","saved",256L)
  valid<-title$valid&&origin$valid
  reason<-if(valid)NULL else "These saved findings have an invalid or oversized label. Review the original saved report before adding them."
  # Only label validation has a per-row unavailable state. Scope/authority/hash
  # errors above remain fatal; strict Add admission never accepts this state.
  brohn_require(valid||isTRUE(allow_unavailable),reason)
  list(schema="brohn-report-package-choice-descriptor/0.1",ref=ref,
    title=title$value,origin=origin$value,availability=if(valid)"unchecked"else"unavailable",reason=reason)
}

brohn_report_package_choice_descriptors <- function(store,study_id,project_id,cursor=NULL,limit=25L) {
  study<-.brohn_rpk_study(store,study_id,project_id)
  brohn_require(brohn_number(limit,1,100,TRUE),"Choose a report page of 1 to 100 items.")
  scope<-brohn_hash(list("report_package_choice_descriptors/0.1",study_id,project_id))
  cursor<-.brohn_rpk_cursor(cursor,scope)
  sql<-paste("SELECT v.id,v.revision,v.body_hash,e.updated_at FROM entities e JOIN entity_versions v",
    "ON v.kind=e.kind AND v.id=e.id AND v.revision=e.revision WHERE e.kind='report'",
    "AND e.project_id=? AND v.project_id=? AND json_extract(v.body_json,'$.study_id')=?")
  params<-list(project_id,project_id,study_id)
  if(!is.null(cursor)){sql<-paste(sql,"AND (e.updated_at<? OR (e.updated_at=? AND e.id>?))");params<-c(params,list(cursor$updated_at,cursor$updated_at,cursor$id))}
  rows<-DBI::dbGetQuery(store$con,paste(sql,"ORDER BY e.updated_at DESC,e.id ASC LIMIT ?"),params=c(params,list(limit+1L)))
  more<-nrow(rows)>limit;rows<-head(rows,limit)
  reports<-lapply(seq_len(nrow(rows)),function(i).brohn_rpk_choice_descriptor(store,
    list(kind="report",id=rows$id[[i]],revision=rows$revision[[i]],body_hash=rows$body_hash[[i]],project_id=project_id),study_id,project_id,allow_unavailable=TRUE))
  next_cursor<-if(more)list(scope=scope,updated_at=tail(rows$updated_at,1),id=tail(rows$id,1))else NULL
  list(schema="brohn-report-package-choice-page/0.1",study=list(id=study$id,title=study$body$title,project_id=project_id),
    reports=reports,cursor=cursor,next_cursor=next_cursor,recommended_refs=list(),needs_choice=TRUE)
}

brohn_report_package_admit_catalog_choice <- function(store,ref,study_id,project_id) {
  # The original complete choice has no study_id. Check the held exact row's
  # study/project before and after its original source/adapters/validity checks.
  .brohn_rpk_choice_descriptor(store,ref,study_id,project_id)
  choice<-brohn_report_package_report_choice(store,ref)
  .brohn_rpk_choice_descriptor(store,ref,study_id,project_id)
  brohn_require(is.list(choice)&&.brohn_rpk_same(choice$ref,ref),"The admitted findings differ from the selected saved version.")
  choice
}

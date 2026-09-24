# External candidate. Metadata discovery only; exact opening delegates to the
# qualified linked reader. No source rows, object bytes or jobs are rewritten.
.brohn_lh_ref <- function(ref) {
  brohn_fields(ref,c("id","revision","hash"),label="Saved linked reference")
  brohn_require(brohn_valid_id(ref$id)&&brohn_number(ref$revision,1,1e9,TRUE)&&
    brohn_text(ref$hash,64)&&grepl("^[0-9a-f]{64}$",ref$hash),"Choose an exact saved linked reference.")
  ref
}
.brohn_lh_read <- function(store,fn) {
  .brohn_store_ready(store)
  if(RSQLite::sqliteIsTransacting(store$con))return(fn())
  DBI::dbWithTransaction(store$con,fn())
}
.brohn_lh_scope <- function(store,dataset_ref,project_id,import_ref=NULL) {
  dataset_ref<-.brohn_lh_ref(dataset_ref)
  brohn_require(brohn_valid_id(project_id),"Choose an available linked-review project.")
  brohn_hosted_require_session(store);brohn_hosted_require_project(store,project_id);brohn_project(store,project_id)
  brohn_require(identical(.brohn_qexplorer_catalog(store,"dataset",dataset_ref$id,dataset_ref$revision,project_id),dataset_ref$hash),
    "This recording revision changed. Reopen the recording before browsing saved reviews.")
  d<-DBI::dbGetQuery(store$con,paste("SELECT json_extract(v.body_json,'$.modality') AS modality,",
    "COALESCE(json_extract(v.body_json,'$.archived'),0) AS archived FROM entities e JOIN entity_versions v",
    "ON v.kind=e.kind AND v.id=e.id AND v.revision=e.revision WHERE e.kind='dataset' AND e.id=? AND e.project_id=? AND v.project_id=?"),
    params=list(dataset_ref$id,project_id,project_id))
  brohn_require(nrow(d)==1L&&identical(d$modality[[1L]],"multimodal")&&d$archived[[1L]]==0,
    "Open an available preserved multistream recording before browsing its saved reviews.")
  where<-paste("e.kind='linked_review' AND e.project_id=? AND v.project_id=?",
    "AND json_extract(v.body_json,'$.schema')='brohn-saved-linked-review/1.0'",
    "AND COALESCE(json_extract(v.body_json,'$.archived'),0)=0",
    "AND json_extract(v.body_json,'$.dataset_id')=? AND json_extract(v.body_json,'$.request.dataset_id')=?",
    "AND json_extract(v.body_json,'$.request.source.id')=? AND json_extract(v.body_json,'$.request.project_id')=?")
  params<-list(project_id,project_id,dataset_ref$id,dataset_ref$id,dataset_ref$id,project_id)
  # A current project move cannot expose metadata from an old allowed revision.
  # Exact sample/artifact integrity is still checked by the original reader.
  for(item in list(c("dataset","source"),c("stream_import","imported"))) {
    kind<-item[[1L]];field<-item[[2L]]
    where<-paste(where,sprintf(paste("AND EXISTS (SELECT 1 FROM entities se JOIN entity_versions sv ON se.kind=sv.kind AND se.id=sv.id",
      "WHERE se.kind='%s' AND se.id=json_extract(v.body_json,'$.request.%s.id')",
      "AND sv.revision=json_extract(v.body_json,'$.request.%s.revision') AND sv.body_hash=json_extract(v.body_json,'$.request.%s.hash')",
      "AND se.project_id=e.project_id AND sv.project_id=v.project_id)"),kind,field,field,field))
  }
  where<-paste(where,paste("AND json_array_length(v.body_json,'$.request.tracks') BETWEEN 2 AND 4",
    "AND NOT EXISTS (SELECT 1 FROM json_each(v.body_json,'$.request.tracks') t",
    "LEFT JOIN entities te ON te.kind='stream' AND te.id=json_extract(t.value,'$.stream.id')",
    "LEFT JOIN entity_versions tv ON tv.kind=te.kind AND tv.id=te.id AND tv.revision=json_extract(t.value,'$.stream.revision')",
    "WHERE te.id IS NULL OR tv.id IS NULL OR te.project_id<>e.project_id OR tv.project_id<>v.project_id",
    "OR tv.body_hash<>json_extract(t.value,'$.stream.hash') OR json_extract(t.value,'$.stream.hash') IS NULL)"))
  if(!is.null(import_ref)) {
    import_ref<-.brohn_lh_ref(import_ref)
    brohn_require(identical(.brohn_qexplorer_catalog(store,"stream_import",import_ref$id,import_ref$revision,project_id),import_ref$hash),
      "This preserved import changed. Reopen the recording before browsing its saved reviews.")
    belongs<-DBI::dbGetQuery(store$con,"SELECT json_extract(body_json,'$.dataset_id') AS dataset_id FROM entity_versions WHERE kind='stream_import' AND id=? AND revision=?",
      params=list(import_ref$id,import_ref$revision))
    brohn_require(nrow(belongs)==1L&&identical(belongs$dataset_id[[1L]],dataset_ref$id),"Choose a preserved import belonging to this recording.")
    where<-paste(where,"AND json_extract(v.body_json,'$.request.imported.id')=? AND json_extract(v.body_json,'$.request.imported.revision')=? AND json_extract(v.body_json,'$.request.imported.hash')=?")
    params<-c(params,list(import_ref$id,import_ref$revision,import_ref$hash))
  }
  list(context=brohn_hash(list(workspace_id=store$workspace_id,workspace=store$root,project_id=project_id,dataset_ref=dataset_ref,import_ref=import_ref)),where=where,params=params)
}
.brohn_lh_from <- paste("FROM entities e JOIN entity_versions v ON v.kind=e.kind AND v.id=e.id AND v.revision=e.revision")
.brohn_lh_projection <- paste("v.id,v.revision,v.body_hash,v.created_at,",
  "json_extract(v.body_json,'$.request.imported.id') AS import_id,json_extract(v.body_json,'$.request.imported.revision') AS import_revision,",
  "json_extract(v.body_json,'$.request.selection.start_s') AS start_s,json_extract(v.body_json,'$.request.selection.end_s') AS end_s,",
  "json_extract(v.body_json,'$.request.selection.cursor_s') AS cursor_s,json_extract(v.body_json,'$.request.selection.offset') AS exact_row_offset,",
  "json_extract(v.body_json,'$.result.status') AS status,json_extract(v.body_json,'$.result.selected_rows') AS selected_rows,",
  "json_extract(v.body_json,'$.origin') AS origin,json_array_length(v.body_json,'$.request.tracks') AS tracks,",
  "json_extract(v.body_json,'$.request.tracks[0].clock.id') AS clock_id")
brohn_linked_history_page <- function(store,dataset_ref,project_id,import_ref=NULL,cursor=NULL,limit=20L) {
  limit<-.brohn_store_integer(limit,"Saved linked reviews per page",1L,20L)
  .brohn_lh_read(store,function(){
    scope<-.brohn_lh_scope(store,dataset_ref,project_id,import_ref)
    if(is.null(cursor))cursor<-list(schema="brohn-linked-history-cursor/1.0",context=scope$context,
      watermark=as.numeric(DBI::dbGetQuery(store$con,"SELECT COALESCE(MAX(rowid),0) AS n FROM entity_versions")$n[[1L]]),after=NULL)
    brohn_fields(cursor,c("schema","context","watermark","after"),label="Saved linked page")
    brohn_require(identical(cursor$schema,"brohn-linked-history-cursor/1.0")&&identical(cursor$context,scope$context)&&
      brohn_number(cursor$watermark,0,2^53-1,TRUE),"This saved-review page belongs to another source. Show latest reviews.")
    after<-cursor$after
    if(!is.null(after)) {
      brohn_fields(after,c("created_at","id"),label="Saved linked page boundary")
      brohn_require(brohn_valid_id(after$id)&&brohn_text(after$created_at,40)&&
        grepl("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}\\.[0-9]{6}Z$",after$created_at),"Invalid saved-review page boundary. Show latest reviews.")
    }
    base<-paste(.brohn_lh_from,"WHERE",scope$where,"AND v.rowid<=?");params<-c(scope$params,list(cursor$watermark))
    total<-DBI::dbGetQuery(store$con,paste("SELECT COUNT(*) AS n",base),params=params)$n[[1L]]
    skipped<-0L;page_where<-"";page_params<-params
    if(!is.null(after)) {
      skipped<-DBI::dbGetQuery(store$con,paste("SELECT COUNT(*) AS n",base,"AND (v.created_at>? OR (v.created_at=? AND v.id<=?))"),
        params=c(params,list(after$created_at,after$created_at,after$id)))$n[[1L]]
      page_where<-"AND (v.created_at<? OR (v.created_at=? AND v.id>?))";page_params<-c(params,list(after$created_at,after$created_at,after$id))
    }
    rows<-DBI::dbGetQuery(store$con,paste("SELECT",.brohn_lh_projection,base,page_where,"ORDER BY v.created_at DESC,v.id ASC LIMIT ?"),params=c(page_params,list(limit+1L)))
    has_next<-nrow(rows)>limit;rows<-head(rows,limit);next_cursor<-NULL
    if(has_next){last<-rows[nrow(rows),,drop=FALSE];next_cursor<-cursor;next_cursor$after<-list(created_at=last$created_at[[1L]],id=last$id[[1L]])}
    records<-lapply(seq_len(nrow(rows)),function(i){x<-lapply(rows,function(col){v<-col[[i]];if(is.na(v))NULL else v})
      c(list(reference=list(id=x$id,revision=x$revision,hash=x$body_hash)),x[setdiff(names(x),c("id","revision","body_hash"))])})
    list(records=records,total=total,first=if(nrow(rows))skipped+1L else 0L,last=if(nrow(rows))skipped+nrow(rows)else 0L,
      cursor=cursor,next_cursor=next_cursor,has_next=has_next,
      count_scope="Currently accessible saved views within this snapshot. Later additions and revisions appear after Show latest; withdrawn access may remove rows.")
  })
}
brohn_linked_history_open <- function(store,reference,dataset_ref,project_id,import_ref=NULL) {
  reference<-.brohn_lh_ref(reference)
  .brohn_lh_read(store,function(){
    scope<-.brohn_lh_scope(store,dataset_ref,project_id,import_ref)
    row<-DBI::dbGetQuery(store$con,paste("SELECT v.body_hash",.brohn_lh_from,"WHERE",scope$where,"AND v.id=? AND v.revision=? AND v.body_hash=?"),
      params=c(scope$params,list(reference$id,reference$revision,reference$hash)))
    brohn_require(nrow(row)==1L,"This saved review changed or is no longer available. Show latest before opening it.")
    saved<-brohn_linked_review_record(store,reference$id,dataset_ref$id,project_id)
    brohn_require(identical(brohn_hash(saved$body),reference$hash)&&saved$revision==reference$revision,"The selected saved review changed while opening.")
    saved
  })
}

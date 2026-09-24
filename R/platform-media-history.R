# Candidate: bounded current-head metadata only. Opening a row still uses the
# complete saved-media reader and its fresh source/object authority checks.
.brohn_mh_ref <- function(x) {
  brohn_fields(x,c("id","revision","hash"),label="Saved review reference")
  brohn_require(brohn_valid_id(x$id)&&brohn_number(x$revision,1,1e9,TRUE)&&.brohn_mr_sha(x$hash),"Choose an exact saved review reference.")
  x
}
.brohn_mh_read <- function(store,fn) {
  .brohn_store_ready(store)
  if(RSQLite::sqliteIsTransacting(store$con))return(fn())
  DBI::dbWithTransaction(store$con,fn())
}
.brohn_mh_scope <- function(store,audio_ref,report_ref,project_id) {
  audio_ref<-.brohn_mh_ref(audio_ref);report_ref<-.brohn_mh_ref(report_ref)
  brohn_require(brohn_valid_id(project_id),"Choose an available review project.")
  brohn_hosted_require_session(store);brohn_hosted_require_project(store,project_id);brohn_project(store,project_id)
  brohn_require(identical(.brohn_qexplorer_catalog(store,"audio_review",audio_ref$id,audio_ref$revision,project_id),audio_ref$hash)&&
    identical(.brohn_qexplorer_catalog(store,"report",report_ref$id,report_ref$revision,project_id),report_ref$hash),"The saved audio window or report changed. Reopen its media review.")
  # Project only three small lineage references, not the full saved waveform.
  # A moved original/derived recording must also revoke its history metadata.
  lineage<-DBI::dbGetQuery(store$con,paste("SELECT json_extract(body_json,'$.request.dataset') AS derived,",
    "json_extract(body_json,'$.request.extraction_lineage.parent_dataset') AS parent,",
    "json_extract(body_json,'$.request.extraction_lineage.extraction') AS extraction,",
    "json_extract(body_json,'$.request.report') AS report FROM entity_versions WHERE kind='audio_review' AND id=? AND revision=?"),params=list(audio_ref$id,audio_ref$revision))
  brohn_require(nrow(lineage)==1L&&!anyNA(lineage),"This saved audio window needs its original video lineage.")
  refs<-lapply(lineage,function(x).brohn_mh_ref(jsonlite::fromJSON(x[[1L]],simplifyVector=FALSE)))
  brohn_require(.brohn_mr_same(refs$report,report_ref),"Choose the original report for this saved audio window.")
  for(name in c("derived","parent","extraction"))brohn_require(identical(.brohn_qexplorer_catalog(store,
    if(name=="extraction")"audio_extraction"else"dataset",refs[[name]]$id,refs[[name]]$revision,project_id),refs[[name]]$hash),"The saved media lineage changed. Reopen its original report.")
  where<-paste("e.kind='media_review' AND e.project_id=? AND v.project_id=?",
    "AND json_extract(v.body_json,'$.schema')='brohn-saved-media-review/1.0'",
    "AND COALESCE(json_extract(v.body_json,'$.archived'),0)=0",
    "AND json_extract(v.body_json,'$.audio_review_id')=?",
    "AND json_extract(v.body_json,'$.report_id')=?",
    "AND json_extract(v.body_json,'$.request.audio_review.id')=?",
    "AND json_extract(v.body_json,'$.request.audio_review.revision')=?",
    "AND json_extract(v.body_json,'$.request.audio_review.hash')=?",
    "AND json_extract(v.body_json,'$.request.report.id')=?",
    "AND json_extract(v.body_json,'$.request.report.revision')=?",
    "AND json_extract(v.body_json,'$.request.report.hash')=?",
    "AND json_extract(v.body_json,'$.request.operation') IN ('media_tracks','media_review')")
  list(context=brohn_hash(list(workspace=store$root,project_id=project_id,audio_ref=audio_ref,report_ref=report_ref)),
    where=where,params=list(project_id,project_id,audio_ref$id,report_ref$id,audio_ref$id,audio_ref$revision,audio_ref$hash,report_ref$id,report_ref$revision,report_ref$hash))
}
.brohn_mh_from <- paste("FROM entities e JOIN entity_versions v ON",
  "v.kind=e.kind AND v.id=e.id AND v.revision=e.revision")
.brohn_mh_projection <- paste("v.id,v.revision,v.body_hash,v.created_at,",
  "json_extract(v.body_json,'$.request.operation') AS operation,",
  "json_extract(v.body_json,'$.request.selection.cursor_sample') AS cursor_sample,",
  "json_extract(v.body_json,'$.request.selection.video_stream_index') AS video_stream_index,",
  "json_extract(v.body_json,'$.result.mapping.sampling_rate') AS sampling_rate,",
  "json_extract(v.body_json,'$.result.coverage.status') AS coverage,",
  "json_extract(v.body_json,'$.result.coverage.frame.frame_index') AS frame_index,",
  "json_extract(v.body_json,'$.result.coverage.frame.pts_ticks') AS pts_ticks,",
  "json_extract(v.body_json,'$.result.coverage.frame.pts_s') AS pts_s,",
  "json_extract(v.body_json,'$.result.coverage.frame.duration_ticks') AS duration_ticks,",
  "json_extract(v.body_json,'$.result.coverage.frame.precision_crosses_frame_boundary') AS boundary,",
  "json_extract(v.body_json,'$.result.coverage.gaps') AS gaps,",
  "json_array_length(v.body_json,'$.result.tracks') AS tracks")
.brohn_mh_rows <- function(rows) lapply(seq_len(nrow(rows)),function(i) {
  x<-lapply(rows,function(col){v<-col[[i]];if(is.na(v))NULL else v})
  ref<-list(id=x$id,revision=x$revision,hash=x$body_hash)
  c(list(reference=ref,created_at=x$created_at),x[setdiff(names(x),c("id","revision","body_hash","created_at"))])
})
brohn_media_history_page <- function(store,audio_ref,report_ref,project_id,cursor=NULL,limit=20L) {
  limit<-.brohn_store_integer(limit,"Saved reviews per page",1L,20L)
  .brohn_mh_read(store,function(){
    scope<-.brohn_mh_scope(store,audio_ref,report_ref,project_id)
    if(is.null(cursor)) {
      watermark<-DBI::dbGetQuery(store$con,"SELECT COALESCE(MAX(rowid),0) AS watermark FROM entity_versions")$watermark[[1L]]
      cursor<-list(schema="brohn-media-history-cursor/1.0",context=scope$context,watermark=as.numeric(watermark),after=NULL)
    }
    brohn_fields(cursor,c("schema","context","watermark","after"),label="Saved review page")
    brohn_require(identical(cursor$schema,"brohn-media-history-cursor/1.0")&&identical(cursor$context,scope$context)&&
      brohn_number(cursor$watermark,0,2^53-1,TRUE),"This saved-review page belongs to another source. Show latest reviews.")
    after<-cursor$after
    if(!is.null(after)) {
      brohn_fields(after,c("created_at","id"),label="Saved review page boundary")
      brohn_require(brohn_valid_id(after$id)&&brohn_text(after$created_at,40)&&
        grepl("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}\\.[0-9]{6}Z$",after$created_at),"This saved-review page boundary is invalid. Show latest reviews.")
    }
    base<-paste(.brohn_mh_from,"WHERE",scope$where,"AND v.rowid<=?")
    params<-c(scope$params,list(cursor$watermark))
    total<-DBI::dbGetQuery(store$con,paste("SELECT COUNT(*) AS n",base),params=params)$n[[1L]]
    skipped<-0L;page_where<-"";page_params<-params
    if(!is.null(after)) {
      skipped<-DBI::dbGetQuery(store$con,paste("SELECT COUNT(*) AS n",base,
        "AND (v.created_at>? OR (v.created_at=? AND v.id<=?))"),params=c(params,list(after$created_at,after$created_at,after$id)))$n[[1L]]
      page_where<-"AND (v.created_at<? OR (v.created_at=? AND v.id>?))"
      page_params<-c(params,list(after$created_at,after$created_at,after$id))
    }
    rows<-DBI::dbGetQuery(store$con,paste("SELECT",.brohn_mh_projection,base,page_where,"ORDER BY v.created_at DESC,v.id ASC LIMIT ?"),params=c(page_params,list(limit+1L)))
    has_next<-nrow(rows)>limit;rows<-head(rows,limit);next_cursor<-NULL
    if(has_next){last<-rows[nrow(rows),,drop=FALSE];next_cursor<-cursor;next_cursor$after<-list(created_at=last$created_at[[1L]],id=last$id[[1L]])}
    list(records=.brohn_mh_rows(rows),total=total,first=if(nrow(rows))skipped+1L else 0L,last=if(nrow(rows))skipped+nrow(rows)else 0L,
      cursor=cursor,next_cursor=next_cursor,has_next=has_next,
      count_scope="Currently accessible saved reviews and inventories within this snapshot; later additions and revisions appear after Show latest.")
  })
}
brohn_media_history_inventory <- function(store,audio_ref,report_ref,project_id) {
  .brohn_mh_read(store,function(){
    scope<-.brohn_mh_scope(store,audio_ref,report_ref,project_id)
    rows<-DBI::dbGetQuery(store$con,paste("SELECT v.id,v.revision,v.body_hash",.brohn_mh_from,"WHERE",scope$where,
      "AND json_extract(v.body_json,'$.request.operation')='media_tracks' ORDER BY v.created_at DESC,v.id ASC LIMIT 1"),params=scope$params)
    if(!nrow(rows))NULL else list(id=rows$id[[1L]],revision=rows$revision[[1L]],hash=rows$body_hash[[1L]])
  })
}

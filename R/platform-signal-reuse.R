# Reuse labels and boundaries only. All new measurements read the target source.
.brohn_interval_record_ref <- function(record) list(id=record$id,revision=record$revision,hash=brohn_hash(record$body))
.brohn_interval_target <- function(store,catalog_id,catalog_revision,catalog_hash,table_id,project_id) {
  latest<-brohn_get_entity(store,"signal_view",catalog_id)
  catalog<-brohn_get_entity(store,"signal_view",catalog_id,catalog_revision)
  brohn_require(!is.null(latest)&&!is.null(catalog)&&identical(latest$project_id,project_id)&&identical(catalog$project_id,project_id)&&
    identical(brohn_hash(catalog$body),catalog_hash)&&identical(catalog$body$operation,"signal_catalog"),
    "Reopen the exact target signal catalog in this project.")
  source<-.brohn_annotations_source(store,catalog$body,project_id)
  tables<-Filter(function(t)identical(t$table_id,table_id),catalog$body$view$tables)
  brohn_require(length(tables)==1L&&identical(tables[[1L]]$coordinates$axis,"time")&&identical(tables[[1L]]$coordinate_column$unit,"s"),
    "Choose a target time-series table in seconds.")
  list(catalog=catalog,latest=latest,report=source$report,artifact=source$artifact,table=tables[[1L]])
}
brohn_preview_signal_interval_reuse <- function(store,source_id,source_revision,source_hash,
    target_catalog_id,target_catalog_revision,target_catalog_hash,target_table_id,title,source_anchor_s,target_anchor_s,rationale) {
  source<-brohn_signal_annotations(store,source_id,source_revision,source_hash)
  brohn_validate_signal_intervals(source$body$intervals,FALSE)
  target<-.brohn_interval_target(store,target_catalog_id,target_catalog_revision,target_catalog_hash,target_table_id,source$project_id)
  brohn_require(brohn_text(title,240)&&nzchar(trimws(title)),"Name the new interval set.")
  brohn_require(brohn_text(rationale,4000)&&nzchar(trimws(rationale)),"Explain why these two recording times correspond.")
  brohn_require(brohn_number(source_anchor_s)&&brohn_number(target_anchor_s),"Enter a finite anchor in each recording's own seconds.")
  offset<-target_anchor_s-source_anchor_s
  brohn_require(brohn_number(offset),"These anchor values exceed the supported time range.")
  # Error-free sum residual for finite binary64 inputs. Computing the offset
  # first preserves identical anchors instead of subtracting a huge anchor
  # from every small boundary and then adding it back.
  residual<-function(a,b,sum){part<-sum-a;(a-(sum-part))+(b-part)}
  offset_error<-residual(target_anchor_s,-source_anchor_s,offset)
  bounds<-target$table$coordinate_range
  has_bounds<-length(bounds)==2L&&all(vapply(bounds,brohn_number,logical(1)))&&bounds[[1L]]<=bounds[[2L]]
  intervals<-lapply(source$body$intervals,function(i){
    start<-i$start_s+offset;end<-i$end_s+offset
    duration<-i$end_s-i$start_s
    tolerance<-max(abs(duration),1)*1e-12
    brohn_require(brohn_number(start)&&brohn_number(end)&&start<end&&
      brohn_number(duration)&&abs(offset_error)<=tolerance&&
      abs(residual(i$start_s,offset,start))<=tolerance&&abs(residual(i$end_s,offset,end))<=tolerance&&
      abs((end-start)-duration)<=tolerance,
      "This translation loses interval precision. Use recording-relative seconds with nearer anchors.")
    list(source_interval_id=i$id,label=i$label,category=i$category,note=i$note,
      source_start_s=i$start_s,source_end_s=i$end_s,start_s=start,end_s=end,
      extent=if(!has_bounds)"unknown_target_extent"else if(end<=bounds[[1L]]||start>bounds[[2L]])"outside_observed_extent"else
        if(start<bounds[[1L]]||end>bounds[[2L]])"extends_beyond_observed_extent"else"within_observed_extent")
  })
  list(schema="brohn-signal-interval-reuse-preview/1.0",project_id=source$project_id,title=title,
    source=list(annotation=.brohn_interval_record_ref(source),latest=.brohn_interval_record_ref(brohn_get_entity(store,"signal_annotations",source$id)),
      report_id=source$body$report_id,report_revision=source$body$report_revision,report_hash=source$body$report_hash,
      artifact_hash=source$body$artifact_hash,origin=source$body$origin,table=source$body$table),
    target=list(catalog=.brohn_interval_record_ref(target$catalog),latest=.brohn_interval_record_ref(target$latest),
      report_id=target$report$id,report_revision=target$report$revision,report_hash=brohn_hash(target$report$body),
      artifact_hash=target$artifact$sha256,origin=target$report$body$origin,table=target$table),
    mapping=list(method="declared_translation/1.0",source_anchor_s=source_anchor_s,target_anchor_s=target_anchor_s,
      offset_s=offset,rationale=rationale,synchronization_verified=FALSE),
    boundary="start inclusive, end exclusive",intervals=intervals)
}
brohn_apply_signal_interval_reuse <- function(store,preview,preview_hash) {
  brohn_require(is.list(preview)&&identical(preview$schema,"brohn-signal-interval-reuse-preview/1.0")&&
    identical(brohn_hash(preview),preview_hash),"Review the exact interval mapping before applying it.")
  # Check both authorities and create the new set within one short catalog lock.
  brohn_store_batch(store,function(){
    s<-preview$source$annotation;t<-preview$target$catalog;m<-preview$mapping
    current<-brohn_preview_signal_interval_reuse(store,s$id,s$revision,s$hash,t$id,t$revision,t$hash,
      preview$target$table$table_id,preview$title,m$source_anchor_s,m$target_anchor_s,m$rationale)
    brohn_require(identical(brohn_hash(current),preview_hash),"The source or target changed after preview. Review the mapping again.")
    id<-brohn_id("intervals")
    intervals<-lapply(current$intervals,function(i)list(id=brohn_id("interval"),label=i$label,category=i$category,
      start_s=i$start_s,end_s=i$end_s,note=i$note))
    brohn_validate_signal_intervals(intervals,FALSE)
    provenance<-list(schema="brohn-signal-interval-reuse/1.0",preview_hash=preview_hash,
      source=current$source,target=current$target,mapping=current$mapping,
      intervals=lapply(seq_along(intervals),function(k)list(source_interval_id=current$intervals[[k]]$source_interval_id,
        target_interval_id=intervals[[k]]$id,extent_at_reuse=current$intervals[[k]]$extent)))
    body<-list(schema_version="brohn-signal-annotations/1.0",id=id,title=current$title,
      report_id=current$target$report_id,report_revision=current$target$report_revision,report_hash=current$target$report_hash,
      artifact_hash=current$target$artifact_hash,origin=current$target$origin,
      catalog_id=t$id,catalog_revision=t$revision,catalog_hash=t$hash,table=current$target$table,intervals=intervals,
      boundary=current$boundary,reuse=provenance,created_at=brohn_now())
    brohn_put_entity(store,"signal_annotations",id,body,project_id=current$project_id)
  })
}

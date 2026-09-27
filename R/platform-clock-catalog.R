# Metadata-only discovery for the clock workflow. Selection/opening still uses
# the exact domain reader; a displayed choice is never source authorization.
.brohn_cc_from <- "FROM entities e JOIN entity_versions v ON v.kind=e.kind AND v.id=e.id AND v.revision=e.revision"
.brohn_cc_read <- function(store,fn) {
  if(RSQLite::sqliteIsTransacting(store$con))return(fn())
  DBI::dbWithTransaction(store$con,fn())
}
brohn_clock_map_versions <- function(store,map_id,project_id,cursor=NULL,limit=20L) {
  limit<-.brohn_store_integer(limit,"Saved alignment versions per page",1L,20L)
  brohn_hosted_require_session(store);brohn_hosted_require_project(store,project_id);brohn_project(store,project_id)
  .brohn_cc_read(store,function(){
    head<-brohn_get_entity(store,"clock_map",map_id)
    brohn_require(!is.null(head),"Choose an available named alignment.")
    head<-.brohn_cm_record(store,"clock_map",.brohn_cm_ref(head),project_id,FALSE)
    # Historical versions share the same original recording family. Current
    # source membership/access is checked without hashing complete data files.
    brohn_clock_map_source_input(store,head$body$request,FALSE)
    context<-brohn_hash(list(workspace=store$root,workspace_id=store$workspace_id,map_id=map_id,project_id=project_id))
    if(is.null(cursor))cursor<-list(schema="brohn-clock-version-cursor/0.1",context=context,ceiling=head$revision,before=NULL)
    brohn_fields(cursor,c("schema","context","ceiling","before"),label="Saved alignment version page")
    brohn_require(identical(cursor$schema,"brohn-clock-version-cursor/0.1")&&identical(cursor$context,context)&&
      brohn_number(cursor$ceiling,1,head$revision,TRUE)&&
      (is.null(cursor$before)||brohn_number(cursor$before,1,cursor$ceiling,TRUE)),"Show latest versions for this named alignment.")
    where<-"kind='clock_map' AND id=? AND project_id=? AND revision<=? AND COALESCE(json_extract(body_json,'$.archived'),0)=0"
    params<-list(map_id,project_id,cursor$ceiling)
    total<-DBI::dbGetQuery(store$con,paste("SELECT COUNT(*) AS n FROM entity_versions WHERE",where),params=params)$n[[1L]]
    if(!is.null(cursor$before)){where<-paste(where,"AND revision<?");params<-c(params,list(cursor$before))}
    rows<-DBI::dbGetQuery(store$con,paste("SELECT id,revision,body_hash,created_at,json_extract(body_json,'$.title') AS title",
      "FROM entity_versions WHERE",where,"ORDER BY revision DESC LIMIT ?"),params=c(params,list(limit+1L)))
    has_next<-nrow(rows)>limit;rows<-head(rows,limit);next_cursor<-NULL
    if(has_next){next_cursor<-cursor;next_cursor$before<-tail(rows$revision,1L)}
    list(records=lapply(seq_len(nrow(rows)),function(i)list(reference=list(id=rows$id[[i]],revision=rows$revision[[i]],hash=rows$body_hash[[i]]),
      title=rows$title[[i]],created_at=rows$created_at[[i]])),total=total,cursor=cursor,next_cursor=next_cursor,has_next=has_next)
  })
}
brohn_clock_catalog_page <- function(store,project_id,kind=c("recordings","imports","maps","windows"),query="",map_ref=NULL,cursor=NULL,limit=20L,dataset_ref=NULL) {
  kind<-match.arg(kind);limit<-.brohn_store_integer(limit,"Clock choices per page",1L,20L)
  brohn_require(brohn_text(query,240,empty=TRUE),"Use a short recording or saved-map search.")
  brohn_hosted_require_session(store);brohn_hosted_require_project(store,project_id);brohn_project(store,project_id)
  if(!is.null(map_ref)){.brohn_cm_ref_valid(map_ref);.brohn_cm_record(store,"clock_map",map_ref,project_id,FALSE)}
  if(kind=="imports"){
    .brohn_cm_ref_valid(dataset_ref)
    dataset<-.brohn_cm_pin(store,"dataset",dataset_ref,project_id)
    brohn_require(identical(dataset$body$modality,"multimodal"),"Choose an original multistream recording before its preserved imports.")
  }else brohn_require(is.null(dataset_ref),"A recording filter applies to preserved import choices.")
  .brohn_cc_read(store,function(){
    entity_kind<-switch(kind,recordings="dataset",imports="stream_import",maps="clock_map",windows="clock_window")
    where<-paste("e.kind=? AND e.project_id=? AND v.project_id=? AND json_extract(v.body_json,'$.id')=v.id",
      "AND COALESCE(json_extract(v.body_json,'$.archived'),0)=0")
    params<-list(entity_kind,project_id,project_id)
    if(kind=="recordings") {
      where<-paste(where,"AND json_extract(v.body_json,'$.modality')='multimodal' AND EXISTS",
        "(SELECT 1 FROM entities ie JOIN entity_versions iv ON iv.kind=ie.kind AND iv.id=ie.id AND iv.revision=ie.revision",
        "WHERE ie.kind='stream_import' AND ie.project_id=e.project_id AND iv.project_id=v.project_id",
        "AND json_extract(iv.body_json,'$.dataset_id')=v.id AND COALESCE(json_extract(iv.body_json,'$.archived'),0)=0)")
    }else if(kind=="imports") {
      where<-paste(where,"AND json_extract(v.body_json,'$.dataset_id')=?")
      params<-c(params,list(dataset_ref$id))
    }else {
      schema<-if(kind=="maps")"brohn-saved-clock-map/0.1"else"brohn-saved-clock-window/0.1"
      where<-paste(where,"AND json_extract(v.body_json,'$.schema')=? AND json_extract(v.body_json,'$.request.project_id')=?")
      params<-c(params,list(schema,project_id))
      # Source ownership is checked before showing history metadata. The exact
      # selected revision and original bytes are rechecked only on opening.
      if(kind=="windows") {
        where<-paste(where,"AND EXISTS (SELECT 1 FROM entities me JOIN entity_versions mv ON mv.kind=me.kind AND mv.id=me.id",
          "AND mv.revision=json_extract(v.body_json,'$.map.revision') JOIN entity_versions mh ON mh.kind=me.kind AND mh.id=me.id AND mh.revision=me.revision",
          "WHERE me.kind='clock_map' AND me.id=json_extract(v.body_json,'$.map.id')",
          "AND me.project_id=e.project_id AND mv.project_id=v.project_id AND mv.body_hash=json_extract(v.body_json,'$.map.hash')",
          "AND mh.project_id=e.project_id AND COALESCE(json_extract(mh.body_json,'$.archived'),0)=0)")
      }
      binding_body<-if(kind=="maps")"v.body_json"else paste("(SELECT mb.body_json FROM entity_versions mb WHERE mb.kind='clock_map'",
          "AND mb.id=json_extract(v.body_json,'$.map.id') AND mb.revision=json_extract(v.body_json,'$.map.revision')",
          "AND mb.body_hash=json_extract(v.body_json,'$.map.hash') AND mb.project_id=v.project_id)")
      for(side in c("source","reference")) {
        source_id<-if(kind=="maps")sprintf("json_extract(v.body_json,'$.request.selections.%s.dataset_id')",side)else
          sprintf("json_extract(v.body_json,'$.result.result.source_request.%s.dataset.id')",side)
        where<-paste(where,sprintf(paste("AND EXISTS (SELECT 1 FROM entities de JOIN entity_versions dv ON dv.kind=de.kind AND dv.id=de.id AND dv.revision=de.revision WHERE de.kind='dataset' AND de.id=%s",
          "AND de.project_id=e.project_id AND dv.project_id=v.project_id AND COALESCE(json_extract(dv.body_json,'$.archived'),0)=0)"),source_id))
        import_id<-if(kind=="maps")sprintf("json_extract(v.body_json,'$.request.selections.%s.import_id')",side)else
          sprintf("json_extract(v.body_json,'$.result.result.source_request.%s.imported.id')",side)
        where<-paste(where,sprintf(paste("AND EXISTS (SELECT 1 FROM entities ie JOIN entity_versions iv ON iv.kind=ie.kind AND iv.id=ie.id AND iv.revision=ie.revision WHERE ie.kind='stream_import' AND ie.id=%s",
          "AND ie.project_id=e.project_id AND iv.project_id=v.project_id AND COALESCE(json_extract(iv.body_json,'$.archived'),0)=0)"),import_id))
        # A current head does not replace the original revision's authority.
        # Match pinned dataset/import ownership, hash and archive state too.
        for(source_kind in c("dataset","stream_import")) {
          field<-if(source_kind=="dataset")"dataset"else"imported"
          pin<-sprintf("json_extract(%s,'$.request.recordings.%s.%s')",binding_body,side,field)
          where<-paste(where,sprintf(paste(
            "AND EXISTS (SELECT 1 FROM entity_versions pv WHERE pv.kind='%s' AND pv.id=json_extract(%s,'$.id')",
            "AND pv.revision=json_extract(%s,'$.revision') AND pv.project_id=v.project_id",
            "AND pv.body_hash=json_extract(%s,'$.hash') AND json_extract(pv.body_json,'$.id')=pv.id",
            "AND COALESCE(json_extract(pv.body_json,'$.archived'),0)=0)"),source_kind,pin,pin,pin))
        }
        selected<-sprintf("json_insert(json_extract(%s,'$.request.recordings.%s.tracks'),'$[#]',json_extract(%s,'$.request.recordings.%s.marker'))",binding_body,side,binding_body,side)
        where<-paste(where,sprintf("AND json_array_length(%s) BETWEEN 2 AND 3",selected),sprintf(paste(
          "AND NOT EXISTS (SELECT 1 FROM json_each(%s) t LEFT JOIN entities se ON se.kind='stream' AND se.id=json_extract(t.value,'$.stream.id')",
          "LEFT JOIN entity_versions sh ON sh.kind=se.kind AND sh.id=se.id AND sh.revision=se.revision",
          "LEFT JOIN entity_versions sp ON sp.kind=se.kind AND sp.id=se.id AND sp.revision=json_extract(t.value,'$.stream.revision')",
          "WHERE se.id IS NULL OR sh.id IS NULL OR sp.id IS NULL OR se.project_id<>e.project_id OR sh.project_id<>v.project_id OR sp.project_id<>v.project_id",
          "OR sp.body_hash<>json_extract(t.value,'$.stream.hash') OR json_extract(t.value,'$.stream.hash') IS NULL",
          "OR COALESCE(json_extract(sh.body_json,'$.archived'),0)<>0)"),selected))
      }
    }
    if(nzchar(query)){where<-paste(where,"AND instr(lower(COALESCE(json_extract(v.body_json,'$.title'),v.id)),lower(?))>0");params<-c(params,list(query))}
    if(!is.null(map_ref)) {
      brohn_require(kind=="windows","An exact map filter applies to saved windows.")
      where<-paste(where,"AND json_extract(v.body_json,'$.map.id')=? AND json_extract(v.body_json,'$.map.revision')=? AND json_extract(v.body_json,'$.map.hash')=?")
      params<-c(params,list(map_ref$id,map_ref$revision,map_ref$hash))
    }
    context<-brohn_hash(list(workspace_id=store$workspace_id,workspace=store$root,project_id=project_id,kind=kind,query=query,map=map_ref,dataset=dataset_ref))
    if(is.null(cursor))cursor<-list(schema="brohn-clock-catalog-cursor/0.1",context=context,
      watermark=DBI::dbGetQuery(store$con,"SELECT COALESCE(MAX(rowid),0) AS n FROM entity_versions")$n[[1L]],after=NULL)
    brohn_fields(cursor,c("schema","context","watermark","after"),label="Clock catalog page")
    brohn_require(identical(cursor$schema,"brohn-clock-catalog-cursor/0.1")&&identical(cursor$context,context)&&brohn_number(cursor$watermark,0,2^53-1,TRUE),
      "This catalog page belongs to a different selection. Show latest choices.")
    base<-paste(.brohn_cc_from,"WHERE",where,"AND v.rowid<=?");params<-c(params,list(cursor$watermark));after<-cursor$after;boundary<-"";page_params<-params;skipped<-0L
    if(!is.null(after)) {
      brohn_fields(after,c("created_at","id"),label="Clock page boundary")
      brohn_require(brohn_valid_id(after$id)&&brohn_text(after$created_at,40)&&
        grepl("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}\\.[0-9]{6}Z$",after$created_at),"Invalid clock page boundary.")
      page_params<-c(params,list(after$created_at,after$created_at,after$id))
      boundary<-"AND (v.created_at<? OR (v.created_at=? AND v.id>?))"
      skipped<-DBI::dbGetQuery(store$con,paste("SELECT COUNT(*) AS n",base,"AND (v.created_at>? OR (v.created_at=? AND v.id<=?))"),params=page_params)$n[[1L]]
    }
    total<-DBI::dbGetQuery(store$con,paste("SELECT COUNT(*) AS n",base),params=params)$n[[1L]]
    rows<-DBI::dbGetQuery(store$con,paste("SELECT v.id,v.revision,v.body_hash,v.created_at,json_extract(v.body_json,'$.title') AS title,",
      "COALESCE(json_extract(v.body_json,'$.origin'),json_extract(v.body_json,'$.result.origin')) AS origin,json_extract(v.body_json,'$.map.id') AS map_id,",
      "json_extract(v.body_json,'$.map.revision') AS map_revision,json_extract(v.body_json,'$.request.selection.start_s') AS start_s,",
      "json_extract(v.body_json,'$.request.selection.end_s') AS end_s",base,boundary,"ORDER BY v.created_at DESC,v.id ASC LIMIT ?"),params=c(page_params,list(limit+1L)))
    has_next<-nrow(rows)>limit;rows<-head(rows,limit);next_cursor<-NULL
    if(has_next){last<-rows[nrow(rows),,drop=FALSE];next_cursor<-cursor;next_cursor$after<-list(created_at=last$created_at[[1L]],id=last$id[[1L]])}
    nullable<-function(x)if(length(x)==0L||is.na(x))NULL else x
    records<-lapply(seq_len(nrow(rows)),function(i){r<-lapply(rows,function(x)nullable(x[[i]]));r$reference<-list(id=r$id,revision=r$revision,hash=r$body_hash);r$body_hash<-NULL;r})
    list(records=records,total=total,first=if(nrow(rows))skipped+1L else 0L,last=if(nrow(rows))skipped+nrow(rows)else 0L,
      cursor=cursor,next_cursor=next_cursor,has_next=has_next,scope="Currently accessible metadata within this snapshot; Show latest includes later additions and revisions.")
  })
}

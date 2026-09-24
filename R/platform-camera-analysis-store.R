# Resolve original SQLite/source authority; never manufacture participant permission.
.brohn_camera_analysis_loaded <- setNames(lapply(c("R/platform-camera-analysis.R","R/platform-camera-analysis-store.R"),function(p)digest::digest(file=p,algo="sha256")),c("R/platform-camera-analysis.R","R/platform-camera-analysis-store.R"))
.brohn_camera_analysis_ref <- function(record)list(id=record$id,revision=record$revision,hash=brohn_hash(record$body))
.brohn_camera_analysis_journal <- function(store,run,assigned,verify=TRUE) {
  sizes<-DBI::dbGetQuery(store$con,"SELECT count(*) AS n,coalesce(sum(length(CAST(event_json AS BLOB))),0) AS bytes FROM delivery_events WHERE run_id=?",params=list(run$id))
  brohn_require(sizes$n[[1L]]<=100000L&&sizes$bytes[[1L]]<=64*1024^2,"The original participant journal exceeds this authority review's complete-source bound. No preview or partial ending is substituted.")
  rows<-DBI::dbGetQuery(store$con,paste("SELECT sequence,event_id,event_hash",if(verify)",event_json"else "","FROM delivery_events WHERE run_id=? ORDER BY sequence"),params=list(run$id))
  brohn_require(nrow(rows)==run$acked_sequence&&identical(as.numeric(rows$sequence),as.numeric(seq_len(nrow(rows)))),"Original participant journal acknowledgements or sequence changed.")
  decode<-function(table)lapply(seq_len(nrow(table)),function(i){
    e<-.brohn_store_decode(table$event_json[[i]],table$event_hash[[i]])
    brohn_require(identical(e$id,table$event_id[[i]])&&e$sequence==table$sequence[[i]],"An original participant event changed its identity or sequence.");e
  })
  if(verify){
    events<-decode(rows)
    context<-if(!is.null(run$protocol$design$questionnaire_navigation)).brohn_delivery_revision_context(run$protocol,assigned$hash)else NULL
    state<-.brohn_delivery_replay(run$protocol,events,context);ending<-state$ending_outcome
    terminals<-which(vapply(events,function(e)e$type%in%c("run_finished","withdrawal"),logical(1)))
    terminal<-if(length(terminals))tail(terminals,1L)else NULL
  }else{
    # Receiving/finalization transactions pin all headers and inspect only the
    # immutable ending. Full bounded replay and byte checks run in supervised input.
    endings<-DBI::dbGetQuery(store$con,"SELECT sequence,event_id,event_hash,event_json FROM delivery_events WHERE run_id=? AND json_extract(event_json,'$.type') IN ('run_finished','withdrawal') ORDER BY sequence",params=list(run$id))
    brohn_require(nrow(endings)<=1L,"The original journal contains conflicting participant endings.")
    events<-decode(endings);terminal<-if(nrow(endings))as.integer(endings$sequence[[1L]])else NULL
    ending<-if(!length(events))NULL else if(identical(events[[1L]]$type,"withdrawal"))"withdrawn"else brohn_default(events[[1L]]$payload$outcome,"completed")
    brohn_require(is.null(ending)||(ending%in%c("completed","interrupted","withdrawn")&&terminal==nrow(rows)),"The original participant ending is invalid or is followed by new events.")
  }
  if(run$completion_status!="in_progress"&&!is.null(ending))brohn_require(identical(run$completion_status,ending),"The original final participant receipt disagrees with the received ending.")
  brohn_require(!identical(ending,"withdrawn")&&!identical(run$completion_status,"withdrawn"),
    "The original participant journal records withdrawal. A missing final acknowledgement or later researcher statement does not permit facial processing.")
  list(received_sequence=run$acked_sequence,event_bytes=sizes$bytes[[1L]],event_headers_hash=brohn_hash(brohn_rows(rows[c("sequence","event_id","event_hash")])),
    participant_ending=if(is.null(ending))NULL else list(outcome=ending,source="received_participant_event",sequence=rows$sequence[[terminal]],event_id=rows$event_id[[terminal]],event_hash=rows$event_hash[[terminal]]),
    original_receipt=list(completion_status=run$completion_status,transfer_status=run$transfer_status,finalized_at=run$finalized_at))
}
brohn_camera_analysis_resolve <- function(store,dataset,mode=c("manual","automatic"),verify=TRUE) {
  mode<-match.arg(mode)
  brohn_require(is.list(dataset)&&is.list(dataset$body),"Choose a saved dataset revision before resolving camera permission.")
  if(!identical(dataset$body$metadata$profile,.brohn_facial_profile))return(NULL)
  read<-function(){
    brohn_require(brohn_valid_id(dataset$id)&&brohn_valid_id(dataset$project_id)&&brohn_number(dataset$revision,1,2^53-1,TRUE),"Choose a saved facial dataset in its current project.")
    project<-dataset$project_id;brohn_project(store,project)
    .brohn_qexplorer_catalog(store,"dataset",dataset$id,dataset$revision,project)
    .brohn_qexplorer_catalog(store,"dataset",dataset$id,1L,project)
    current<-brohn_get_entity(store,"dataset",dataset$id,dataset$revision)
    original<-brohn_get_entity(store,"dataset",dataset$id,1L);head<-brohn_get_entity(store,"dataset",dataset$id)
    brohn_require(!is.null(current)&&!is.null(original)&&!is.null(head)&&.brohn_facial_same(current,dataset),"The selected facial dataset revision changed before permission review.")
    records<-list(original,head,current)
    camera<-vapply(records,function(x){p<-x$body$source_provenance;identical(p$acquisition,"browser_camera")||!is.null(p$capture_id)||!is.null(p$capture_policy)||!is.null(p$run_id)},logical(1))
    if(!any(camera))return(NULL)
    brohn_require(all(vapply(records,function(x)identical(x$body$source_provenance$acquisition,"browser_camera"),logical(1))),
      "A camera recording cannot discard or replace its original acquisition lineage through a new mapping revision.")
    b<-current$body;p<-b$source_provenance
    brohn_require(all(vapply(records,function(x)identical(x$project_id,project)&&identical(x$body$modality,"video")&&
      .brohn_facial_same(x$body$source,original$body$source)&&.brohn_facial_same(x$body$source_provenance,original$body$source_provenance)&&
      identical(x$body$study_id,original$body$study_id)&&identical(x$body$study_revision,original$body$study_revision)&&identical(x$body$origin,original$body$origin),logical(1))),
      "Current or historical camera source, study, project or original permission lineage changed.")
    brohn_require(all(c("camera_captures","camera_chunks","delivery_runs","delivery_events","delivery_deployments")%in%DBI::dbListTables(store$con))&&
      all(vapply(list(p$capture_id,p$run_id,b$study_id),brohn_valid_id,logical(1))),"The original camera receipt and participant session are unavailable.")
    .brohn_qexplorer_catalog(store,"study",b$study_id,b$study_revision,project)
    study<-brohn_get_entity(store,"study",b$study_id,b$study_revision)
    capture<-.brohn_camera_decode(.brohn_camera_row(store,id=p$capture_id))
    publication<-brohn_get_entity(store,"camera_capture",p$capture_id)
    brohn_require(!is.null(publication)&&publication$revision==1L,"The original immutable camera publication is unavailable or was superseded.")
    .brohn_qexplorer_catalog(store,"camera_capture",publication$id,publication$revision,project)
    run<-brohn_run(store,p$run_id);assigned<-brohn_run_protocol(store,p$run_id,b$study_id,project)
    brohn_require(!is.null(run)&&!is.null(capture)&&identical(assigned$hash,brohn_hash(run$protocol))&&
      .brohn_facial_same(study$body,run$protocol$design),"The original camera study revision differs from its assigned protocol.")
    authority<-brohn_camera_analysis_source(run,capture,publication,current,mode)
    journal<-.brohn_camera_analysis_journal(store,run,assigned,verify)
    resolution<-brohn_session_resolution(store,run$id);resolution_ref<-NULL
    if(!is.null(resolution)){
      .brohn_qexplorer_catalog(store,"session_resolution",resolution$id,resolution$revision,project)
      z<-resolution$body
      brohn_require(identical(resolution$project_id,project)&&identical(z$run_id,run$id)&&identical(z$release_id,run$deployment_id)&&identical(z$study_id,run$study_id),"The researcher resolution belongs to a different original session.")
      snapshot<-.brohn_sr_snapshot(store,run$deployment_id,run$id,run$study_id,project,verify_bytes=verify)
      brohn_require(identical(z$source_hash,snapshot$hash)&&.brohn_facial_same(z$source,snapshot$source)&&
        .brohn_facial_same(z$participant_ending,snapshot$source$participant_ending)&&!identical(z$participant_ending$outcome,"withdrawn"),
        "The researcher resolution no longer matches original received evidence or preserves a withdrawal.")
      resolution_ref<-.brohn_camera_analysis_ref(resolution)
    }
    # Bind original chunk objects too. The assembled video alone is not the full
    # retained participant source; byte and observation receipts remain immutable.
    chunks<-DBI::dbGetQuery(store$con,"SELECT sequence,content_hash,object_hash,observation_hash,byte_count FROM camera_chunks WHERE capture_id=? ORDER BY sequence",params=list(capture$id))
    brohn_require(nrow(chunks)==capture$acked_sequence&&nrow(chunks)<=4096L&&identical(as.numeric(chunks$sequence),as.numeric(seq_len(nrow(chunks))))&&sum(chunks$byte_count)==capture$total_bytes,
      "Original camera chunk acknowledgements or byte totals changed.")
    chunk_manifest<-lapply(seq_len(nrow(chunks)),function(i)list(sequence=chunks$sequence[[i]],hash=chunks$object_hash[[i]],bytes=chunks$byte_count[[i]],observation_hash=chunks$observation_hash[[i]]))
    brohn_require(.brohn_facial_same(chunk_manifest,publication$body$assembly$chunks),"Original camera chunk identities differ from the saved complete assembly manifest.")
    refs<-authority$source_refs
    for(i in seq_len(nrow(chunks))){
      object<-DBI::dbGetQuery(store$con,"SELECT hash,size,media_type FROM objects WHERE hash=? OR hash=?",params=list(chunks$object_hash[[i]],chunks$observation_hash[[i]]))
      raw<-object[object$hash==chunks$object_hash[[i]],,drop=FALSE];observation<-object[object$hash==chunks$observation_hash[[i]],,drop=FALSE]
      brohn_require(nrow(raw)==1L&&nrow(observation)==1L&&raw$size[[1L]]==chunks$byte_count[[i]]&&identical(observation$media_type[[1L]],"application/json")&&.brohn_facial_sha(chunks$content_hash[[i]]),
        "An original camera chunk or observation object is unavailable or changed.")
      refs<-c(refs,list(list(hash=raw$hash[[1L]],bytes=raw$size[[1L]]),list(hash=observation$hash[[1L]],bytes=observation$size[[1L]])))
    }
    unique_refs<-list()
    for(ref in refs){
      prior<-Filter(function(x)identical(x$hash,ref$hash),unique_refs)
      brohn_require(!length(prior)||as.numeric(prior[[1L]]$bytes)==as.numeric(ref$bytes),"Original camera object byte references disagree.")
      if(!length(prior))unique_refs[[length(unique_refs)+1L]]<-ref
    }
    for(ref in unique_refs){path<-brohn_object_path(store,ref$hash,verify=verify);brohn_require(file.info(path)$size==ref$bytes,"An original camera evidence object changed its byte count.")}
    # When retained, compare the complete immutable publication envelope as well
    # as its individual artifact bytes. Legacy publications without this object
    # remain source-bound through the catalog and complete camera manifest.
    if(!is.null(publication$body$result_object)).brohn_sv_retained(store,publication,"camera_capture",verify)
    if(verify){
      manifest<-Filter(function(x)identical(x$kind,"camera-manifest"),publication$body$artifacts)[[1L]]
      brohn_require(.brohn_facial_same(brohn_read_json_file(brohn_object_path(store,manifest$hash,verify=TRUE)),publication$body$assembly),"The retained camera manifest differs from its original assembly authority.")
    }
    authority$source_refs<-unique_refs
    authority$original_dataset<-.brohn_camera_analysis_ref(original)
    authority$received_journal<-journal
    authority$original_chunks_hash<-brohn_hash(brohn_rows(chunks))
    authority$session_resolution<-resolution_ref
    authority
  }
  if(RSQLite::sqliteIsTransacting(store$con))read()else DBI::dbWithTransaction(store$con,read())
}
brohn_camera_analysis_report_source <- function(store,record,verify=FALSE) {
  b<-record$body;p<-b$provenance;pin<-p$camera_analysis_authority
  if(!brohn_facial_supported(b$analysis)&&is.null(pin))return(NULL)
  brohn_require(brohn_facial_supported(b$analysis),"Camera facial authority belongs to a native facial report.")
  brohn_project(store,record$project_id);.brohn_qexplorer_catalog(store,"report",record$id,record$revision,record$project_id)
  id<-p$dataset_id
  brohn_require(brohn_valid_id(id)&&identical(id,b$dataset_id)&&brohn_number(p$dataset_revision,1,2^53-1,TRUE),"The facial report lacks its original saved dataset revision.")
  .brohn_qexplorer_catalog(store,"dataset",id,p$dataset_revision,record$project_id)
  dataset<-brohn_get_entity(store,"dataset",id,p$dataset_revision)
  brohn_require(identical(brohn_hash(dataset$body),p$dataset_hash)&&.brohn_facial_same(dataset$body$source,p$source)&&.brohn_facial_same(dataset$body$metadata,p$mapping)&&
    identical(dataset$body$origin,b$origin)&&identical(dataset$body$study_id,b$study_id),"The facial report changed its original recording, mapping or study provenance.")
  authority<-brohn_camera_analysis_resolve(store,dataset,brohn_default(pin$mode,"manual"),verify)
  if(is.null(authority)){brohn_require(is.null(pin),"A pinned camera report cannot discard its source authority.");return(NULL)}
  if(is.null(pin)) {
    brohn_require(identical(authority$original_camera_policy_schema,"brohn-camera-policy/1.0"),"This named automatic camera report lacks its original permission authority.")
    authority$review_evidence<-"Current original-source check for a historical manual report without a saved camera-authority pin; original report remains unchanged."
  }else brohn_require(.brohn_facial_same(authority,pin),"The facial report's original participant decision, source or processing authority changed. Open its retained recording and session history.")
  brohn_require(!is.null(b$result_object),"The facial report lacks its retained original worker envelope.")
  .brohn_sv_retained(store,record,"report",verify)
  authority
}

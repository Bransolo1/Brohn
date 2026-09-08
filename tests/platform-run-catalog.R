# Original catalog fixtures and real saved participant starts. No scientific jobs
# or hardware collection; deliberately damaged rows live only in this temp store.
source("R/platform-load.R",encoding="UTF-8");brohn_load(ui=FALSE)
source("R/platform-run-catalog.R")
local({
  checks<-0L
  check<-function(label,value){if(!isTRUE(value))stop("Run catalog: ",label,call.=FALSE);checks<<-checks+1L}
  failure<-function(expr)tryCatch({force(expr);NULL},error=function(e)conditionMessage(e))
  directory<-tempfile("brohn-run-catalog-");dir.create(directory)
  directory<-normalizePath(directory,winslash="/",mustWork=TRUE)
  store<-brohn_open_store(file.path(directory,"workspace"));second<-NULL
  on.exit({if(!is.null(second))brohn_close_store(second);brohn_close_store(store)
    actual<-normalizePath(directory,winslash="/",mustWork=TRUE)
    stopifnot(identical(actual,directory),startsWith(tolower(actual),paste0(tolower(normalizePath(tempdir(),winslash="/")),"/")),startsWith(basename(actual),"brohn-run-catalog-"))
    unlink(actual,recursive=TRUE,force=TRUE)},add=TRUE)
  brohn_initialise_library(store)
  study<-brohn_create_study(store,"Original catalog target","survey")
  before_tables<-DBI::dbListTables(store$con)
  empty<-brohn_search_runs(store,study$id)
  check("fresh study has an explicit empty page",empty$total==0&&length(empty$records)==0&&!empty$has_previous&&!empty$has_next&&empty$offset==0)
  check("metadata read does not create delivery tables",identical(before_tables,DBI::dbListTables(store$con)))
  policy<-list(schema="brohn-camera-policy/1.0",required=TRUE,audio=FALSE,consent_text="ORIGINAL_PRIVATE_CONSENT",
    retention_text="ORIGINAL_PRIVATE_RETENTION",width=640,height=480,frame_rate=15,max_duration_s=10,max_bytes=1024^2,analysis_profile="none")
  d<-study$body;d$camera<-policy;d$questions<-list(brohn_question("Original catalog fixture rating","rating","end","catalog-rating"))
  study<-brohn_save_study(store,d,study$revision)
  release<-brohn_publish(store,study$id,"sample",quota=1000)
  start<-.brohn_delivery_start(store,release$token,list(consented=TRUE,participant_alias="001",client_id="ORIGINAL_PRIVATE_CLIENT",operation_id="original-start"))
  page<-brohn_search_runs(store,study$id,project_id="default")
  one<-page$records[[1L]]
  check("real saved run has flat researcher identity",one$id==start$run_id&&one$study_id==study$id&&one$project_id=="default"&&one$participant_alias=="001"&&one$participant_alias_supplied)
  check("camera summary retains exact frozen typed choices",one$camera_policy_summary$status=="requested"&&one$camera_policy_summary$required&&!one$camera_policy_summary$audio&&one$camera_policy_summary$analysis_profile=="none")
  check("metadata integrity limitation is explicit",one$metadata_evidence=="catalog_projection_not_protocol_hash_verified"&&one$camera_policy_summary$evidence==one$metadata_evidence)
  check("no protocol or credential fields are returned",!any(c("protocol","protocol_json","access_token","token","client_id","start_hash","events") %in% names(one)))
  serialized<-brohn_json(page)
  check("private protocol text and actual bearer/release tokens do not cross query boundary",!any(vapply(c("ORIGINAL_PRIVATE_CONSENT","ORIGINAL_PRIVATE_RETENTION","ORIGINAL_PRIVATE_CLIENT",start$access_token,release$token),grepl,logical(1),x=serialized,fixed=TRUE)))
  check("protocol hash remains a reference rather than full protocol",identical(one$protocol_hash,DBI::dbGetQuery(store$con,"SELECT protocol_hash FROM delivery_runs WHERE id=?",params=list(start$run_id))$protocol_hash[[1L]]))

  # Editing the current draft cannot change the saved run's camera requirement.
  d<-study$body;d$camera<-NULL;study<-brohn_save_study(store,d,study$revision)
  next_release<-brohn_publish(store,study$id,"sample",quota=1000)
  next_start<-.brohn_delivery_start(store,next_release$token,list(consented=TRUE,participant_alias="",client_id="second-client",operation_id="second-start"))
  page<-brohn_search_runs(store,study$id)
  old<-Filter(function(r)r$id==start$run_id,page$records)[[1L]]
  new<-Filter(function(r)r$id==next_start$run_id,page$records)[[1L]]
  check("camera display follows each frozen release after current draft edit",old$camera_policy_summary$required&&new$camera_policy_summary$status=="not_requested")
  check("generated alias remains unlinked metadata",!new$participant_alias_supplied&&startsWith(new$participant_alias,"Participant "))

  protocol<-brohn_run(store,start$run_id)$protocol
  insert_run<-function(con,id,deployment=release$id,parent=study$id,p=protocol,created="2024-01-01T00:00:00Z",index=1000L,raw=NULL,hash=NULL) {
    json<-if(is.null(raw)).brohn_store_json(p)else raw
    if(is.null(hash))hash<-.brohn_delivery_hash(json)
    DBI::dbExecute(con,paste("INSERT INTO delivery_runs",
      "(id,deployment_id,study_id,origin,participant_alias,client_id,start_hash,protocol_json,protocol_hash,allocation_index,completion_status,transfer_status,acked_sequence,created_at,updated_at,finalized_at,participant_alias_supplied)",
      "VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)"),params=list(id,deployment,parent,"sample",paste0("Alias ",id),paste0("PRIVATE_CLIENT_",id),paste(rep("c",64),collapse=""),json,hash,index,"completed","saved",17L,created,created,created,0L))
  }
  other<-brohn_create_study(store,"Newer unrelated study","survey")
  d<-other$body;d$questions<-list(brohn_question("Original other fixture rating","rating","end","other-rating"));other<-brohn_save_study(store,d,other$revision)
  other_release<-brohn_publish(store,other$id,"sample",quota=1000)
  brohn_put_entity(store,"project","private-project",list(id="private-project",title="Other project",archived=FALSE),project_id="private-project")
  private<-brohn_create_study(store,"Private other project study","survey",project_id="private-project")
  d<-private$body;d$questions<-list(brohn_question("Original private fixture rating","rating","end","private-rating"));private<-brohn_save_study(store,d,private$revision)
  private_release<-brohn_publish(store,private$id,"sample",quota=1000)
  brohn_store_batch(store,function(){
    for(i in 1:85)insert_run(store$con,sprintf("target-%03d",i),index=1000L+i)
    for(i in 1:91)insert_run(store$con,sprintf("newer-other-%03d",i),other_release$id,other$id,created="2027-01-01T00:00:00Z",index=1000L+i)
    insert_run(store$con,"private-valid",private_release$id,private$id,created="2028-01-01T00:00:00Z")
    # This intentionally inconsistent row is allowed by the legacy FK layout;
    # the metadata join must not leak a different project's deployment.
    insert_run(store$con,"private-forged-parent",private_release$id,study$id,created="2028-01-01T00:00:00Z",index=1001L)
  })
  pages<-lapply(c(0L,40L,80L),function(offset)brohn_search_runs(store,study$id,limit=40L,offset=offset))
  ids<-unlist(lapply(pages,function(p)brohn_ids(p$records)),use.names=FALSE)
  check("parent selection precedes page bound despite 91 newer unrelated runs",identical(vapply(pages,function(p)length(p$records),integer(1)),c(40L,40L,7L))&&all(vapply(pages,function(p)p$total==87,logical(1))))
  check("three pages retain every target exactly once",length(ids)==87L&&!anyDuplicated(ids)&&all(sprintf("target-%03d",1:85)%in%ids))
  check("foreign study and project never enter page or total",!any(grepl("other|private",ids))&&all(vapply(pages,function(p)p$project_id=="default",logical(1))))
  check("tied timestamps use exact stable ID order",identical(ids[grepl("^target-",ids)],sprintf("target-%03d",1:85)))
  check("navigation indicators describe all pages",!pages[[1]]$has_previous&&pages[[1]]$has_next&&pages[[2]]$has_previous&&pages[[2]]$has_next&&pages[[3]]$has_previous&&!pages[[3]]$has_next)
  tail<-brohn_search_runs(store,study$id,offset=999L)
  check("out-of-range page clamps to last populated page",tail$offset==80&&length(tail$records)==7&&tail$total==87)
  check("explicit foreign project and missing study return identical generic error",identical(failure(brohn_search_runs(store,study$id,"private-project")),failure(brohn_search_runs(store,"missing-study","private-project"))))
  check("other project can be selected only with its actual parent",brohn_search_runs(store,private$id,"private-project")$total==1)
  check("page arguments reject SQL-like identifiers and invalid bounds",!is.null(failure(brohn_search_runs(store,"' OR 1=1 --")))&&!is.null(failure(brohn_search_runs(store,study$id,limit=101)))&&!is.null(failure(brohn_search_runs(store,study$id,offset=-1)))&&!is.null(failure(brohn_search_runs(store,study$id,limit=1.5))))

  # No full decoder or brohn_run call is needed to show even large protocols.
  large<-protocol;large$private_original<-paste(rep("ORIGINAL_FULL_PROTOCOL_SECRET",40000),collapse="")
  insert_run(store$con,"large-protocol",p=large,index=2000L)
  full_decoder<-.brohn_store_decode
  assign(".brohn_store_decode",function(...)stop("Full JSON decode was forbidden in this catalog probe"),envir=.GlobalEnv)
  large_page<-tryCatch(brohn_search_runs(store,study$id,limit=100L),finally=assign(".brohn_store_decode",full_decoder,envir=.GlobalEnv))
  check("catalog runs without whole-document decode",large_page$total==88&&"large-protocol"%in%brohn_ids(large_page$records))
  check("full protocol payload is not materialized in result",!grepl("ORIGINAL_FULL_PROTOCOL_SECRET",brohn_json(large_page),fixed=TRUE)&&as.numeric(object.size(large_page))<1024^2)

  variants<-list(malformed="{broken",scalar='"scalar protocol"',array='[]')
  add_variant<-function(name,change){p<-protocol;p<-change(p);variants[[name]]<<-.brohn_store_json(p)}
  add_variant("unknown_protocol",function(p){p$schema_version<-"brohn-protocol/9.0";p})
  add_variant("missing_design",function(p){p$design<-NULL;p})
  add_variant("camera_array",function(p){p$design$camera<-list();p})
  add_variant("unknown_camera",function(p){p$design$camera$schema<-"brohn-camera-policy/9.0";p})
  add_variant("string_required",function(p){p$design$camera$required<-"false";p})
  add_variant("integer_required",function(p){p$design$camera$required<-1L;p})
  add_variant("string_audio",function(p){p$design$camera$audio<-"false";p})
  add_variant("missing_analysis",function(p){p$design$camera$analysis_profile<-NULL;p})
  add_variant("object_analysis",function(p){p$design$camera$analysis_profile<-list(value="none");p})
  add_variant("unknown_analysis",function(p){p$design$camera$analysis_profile<-"imagined_emotion";p})
  for(i in seq_along(variants))insert_run(store$con,paste0("damaged-",names(variants)[i]),raw=variants[[i]],index=3000L+i)
  bad_page<-brohn_search_runs(store,study$id,limit=100L)
  bad_records<-Filter(function(r)startsWith(r$id,"damaged-"),bad_page$records)
  # Use the second page if the intentional damaged rows cross the first bound.
  if(length(bad_records)<length(variants))bad_records<-c(bad_records,Filter(function(r)startsWith(r$id,"damaged-"),brohn_search_runs(store,study$id,limit=100L,offset=100L)$records))
  check("malformed protocols never crash an otherwise usable page",length(bad_records)==length(variants))
  check("unknown schemas or non-boolean policy fields never claim not-requested",all(vapply(bad_records,function(r)r$camera_policy_summary$status=="unavailable"&&!is.null(r$camera_policy_summary$reason)&&is.null(r$camera_policy_summary$required),logical(1))))
  check("full explicit protocol read still rejects malformed source",!is.null(failure(brohn_run(store,"damaged-malformed"))))
  insert_run(store$con,"wrong-hash",index=4000L,hash=paste(rep("0",64),collapse=""))
  hash_record<-Filter(function(r)r$id=="wrong-hash",brohn_search_runs(store,study$id,limit=100L,offset=100L)$records)
  if(!length(hash_record))hash_record<-Filter(function(r)r$id=="wrong-hash",brohn_search_runs(store,study$id,limit=100L)$records)
  check("projected fields explicitly do not assert whole-protocol hash verification",hash_record[[1L]]$camera_policy_summary$evidence=="catalog_projection_not_protocol_hash_verified"&&!is.null(failure(brohn_run(store,"wrong-hash"))))

  DBI::dbExecute(store$con,"PRAGMA query_only=ON")
  readonly<-brohn_search_runs(store,study$id)
  DBI::dbExecute(store$con,"PRAGMA query_only=OFF")
  check("query succeeds on a read-only connection with no migration writes",readonly$total==102&&length(readonly$records)==40)
  brohn_deployment_state(store,release$id,"closed");brohn_deployment_state(store,next_release$id,"closed")
  saved<-brohn_search_runs(store,study$id,limit=40L,offset=80L)
  study<-brohn_archive_study(store,study$id,TRUE)
  archived<-brohn_search_runs(store,study$id,limit=40L,offset=80L)
  check("archiving study preserves session pages and frozen camera choices",identical(saved,archived))
  brohn_close_store(store);store<-brohn_open_store(file.path(directory,"workspace"))
  reopened<-brohn_search_runs(store,study$id,limit=40L,offset=80L)
  check("workspace reopen preserves exact archived session metadata",identical(archived,reopened))
  brohn_archive_study(store,study$id,FALSE)
  check("restoring study preserves metadata and does not reopen recruitment",identical(reopened,brohn_search_runs(store,study$id,limit=40L,offset=80L))&&brohn_deployment(store,release$id,FALSE)$status=="closed")

  # A concurrent writer inserts between count and page. WAL permits its commit,
  # while both reads retain the same snapshot and the next query sees the row.
  second<-brohn_open_store(store$root)
  scalar<-.brohn_run_catalog_scalar;inserted<-FALSE
  assign(".brohn_run_catalog_scalar",function(...) {
    if(!inserted){inserted<<-TRUE;insert_run(second$con,"concurrent-row",index=5000L)}
    scalar(...)
  },envir=.GlobalEnv)
  concurrent<-tryCatch(brohn_search_runs(store,study$id,limit=100L),finally=assign(".brohn_run_catalog_scalar",scalar,envir=.GlobalEnv))
  check("concurrent metadata writer can commit during read transaction",inserted)
  check("count and page share one snapshot",concurrent$total==102&&length(concurrent$records)==100&&!"concurrent-row"%in%brohn_ids(concurrent$records))
  after<-brohn_search_runs(store,study$id,limit=100L)
  check("next catalog snapshot includes newly committed run",after$total==103&&"concurrent-row"%in%brohn_ids(after$records))
  check("catalog did not enqueue scientific work",length(brohn_list_jobs(store))==0)
  cat(sprintf("Participant run catalog: %d checks passed; SQLite %s, 103 target sessions, isolated read/concurrent-write and malformed-policy evidence.\n",checks,DBI::dbGetQuery(store$con,"SELECT sqlite_version() AS v")$v[[1L]]))
})

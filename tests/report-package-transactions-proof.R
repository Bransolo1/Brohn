# Engineering-only small stores. These exercise the transaction proof mechanism,
# not admission of a native scientific report. No analysis worker is launched.
# Rscript proof-controls.R <prepared-checkout> <new-output>
args<-commandArgs(TRUE);stopifnot(length(args)==2L)
checkout<-normalizePath(args[[1L]],winslash="/",mustWork=TRUE);out<-args[[2L]]
stopifnot(!file.exists(out));dir.create(out,recursive=TRUE);out<-normalizePath(out,winslash="/",mustWork=TRUE)
setwd(checkout);source("R/platform-load.R",encoding="UTF-8");brohn_load(ui=FALSE)
source("R/platform-report-package-transactions.R",encoding="UTF-8")
checks<-list();failure<-NULL;store<-NULL;peer<-NULL
check<-function(label,ok){checks[[length(checks)+1L]]<<-list(label=label,passed=isTRUE(ok));cat(if(isTRUE(ok))"PASS"else"FAIL",label,"\n");stopifnot(isTRUE(ok))}
error_of<-function(expr)tryCatch({force(expr);NULL},error=function(e)e)
stale<-function(expr)inherits(error_of(expr),"brohn_report_preflight_stale")
tryCatch({
  store<-brohn_open_store(file.path(out,"workspace"));peer<-brohn_open_store(file.path(out,"workspace"))
  project<-brohn_put_entity(store,"project","default",list(id="default",title="Synthetic transaction controls",archived=FALSE))
  study<-brohn_put_entity(store,"study","study-transaction-fixture",list(id="study-transaction-fixture",title="Synthetic",project_id="default"))
  report<-brohn_put_entity(store,"report","report-transaction-fixture",list(id="report-transaction-fixture",value=17),0L,"default")
  ref<-.brohn_rpk_ref(report)
  object<-brohn_store_object(store,bytes=charToRaw("synthetic object bytes"),media_type="application/octet-stream")
  object<-.brohn_rpk_object(store,object)
  producer<-brohn_enqueue_job(store,"synthetic_proof",list(schema="synthetic-only"),"synthetic-original-producer")
  producer<-brohn_claim_job(store,"proof-control",60)
  brohn_complete_job(store,producer$id,producer$worker,producer$token,list(synthetic=TRUE))
  proof<-function().brohn_rptx_snapshot(store,function().brohn_rptx_capture(store,
    list(list(ref=ref,processing=list(job_id=producer$id))),list(object),study$id,"default"))
  query_only<-function()DBI::dbGetQuery(store$con,"PRAGMA query_only")[[1L]][[1L]]
  n<-DBI::dbGetQuery(store$con,"SELECT count(*) n FROM entities")$n[[1L]]
  e<-error_of(.brohn_rptx_snapshot(store,function()brohn_put_entity(store,"report","forbidden-read-phase-write",list(value=1))))
  check("Read snapshot physically refuses an attempted catalogue write",inherits(e,"error")&&is.null(brohn_get_entity(store,"report","forbidden-read-phase-write")))
  check("Read-phase failure restores query_only and ends only its own transaction",query_only()==0L&&!RSQLite::sqliteIsTransacting(store$con)&&DBI::dbGetQuery(store$con,"SELECT count(*) n FROM entities")$n[[1L]]==n)
  sentinel<-structure(list(message="Exact synthetic read error",call=NULL,marker=17),class=c("synthetic_read_error","error","condition"))
  e<-error_of(.brohn_rptx_snapshot(store,function()stop(sentinel)))
  check("Read exception identity is retained after cleanup",identical(e,sentinel)&&query_only()==0L&&!RSQLite::sqliteIsTransacting(store$con))
  interrupted<-tryCatch(.brohn_rptx_snapshot(store,function()stop(structure(list(message="Synthetic interrupt",call=NULL),class=c("interrupt","condition")))),interrupt=function(e)TRUE)
  check("Interrupt unwinding restores the connection and releases the snapshot",isTRUE(interrupted)&&query_only()==0L&&!RSQLite::sqliteIsTransacting(store$con))
  DBI::dbExecute(store$con,"PRAGMA query_only=ON")
  value<-.brohn_rptx_snapshot(store,function()17L)
  check("A caller's existing read-only setting is preserved",identical(value,17L)&&query_only()==1L)
  DBI::dbExecute(store$con,"PRAGMA query_only=OFF")
  brohn_store_batch(store,function(){
    brohn_put_entity(store,"report","caller-owned-write",list(value=3))
    e<-error_of(.brohn_rptx_snapshot(store,function()stop("must not enter")))
    check("Nested snapshot refuses without releasing or rolling back caller writer",inherits(e,"error")&&RSQLite::sqliteIsTransacting(store$con)&&!is.null(brohn_get_entity(store,"report","caller-owned-write")))
  })
  check("Caller retains control over its own commit",!is.null(brohn_get_entity(store,"report","caller-owned-write")))
  p<-proof();check("Unchanged exact source proof is accepted",isTRUE(brohn_store_batch(store,function()p(store))))
  raw<-DBI::dbGetQuery(store$con,"SELECT body_json FROM entity_versions WHERE kind='report' AND id=? AND revision=1",params=list(ref$id))$body_json[[1L]]
  # Corruption controls are deliberately synthetic. First prove the normal
  # schema refuses them, then temporarily remove ONLY the named update trigger
  # on this fresh owned fixture. Exact SQL and the full trigger catalogue are
  # restored after success, error or interrupt. No production connection enters.
  trigger_rows<-function()DBI::dbGetQuery(peer$con,
    "SELECT name,tbl_name,sql FROM sqlite_master WHERE type='trigger' ORDER BY name")
  original_triggers<-trigger_rows()
  fixture_root<-normalizePath(file.path(out,"workspace"),winslash="/",mustWork=TRUE)
  fixture_connection<-peer$con
  corrupt_synthetic_row<-function(name,fn){
    allowed<-c(versions_no_update="entity_versions",objects_no_update="objects")
    stopifnot(length(name)==1L,name %in% names(allowed),is.function(fn),
      identical(peer$con,fixture_connection),
      identical(normalizePath(peer$root,winslash="/",mustWork=TRUE),fixture_root),
      !RSQLite::sqliteIsTransacting(peer$con),!RSQLite::sqliteIsTransacting(store$con),
      identical(trigger_rows(),original_triggers))
    row<-original_triggers[original_triggers$name==name,,drop=FALSE]
    stopifnot(nrow(row)==1L,identical(row$tbl_name[[1L]],unname(allowed[[name]])))
    # Register cleanup before the drop. The saved SQL is read from this fresh
    # fixture's sqlite_master; the trigger name comes only from the allowlist.
    dropped<-FALSE
    on.exit({
      if(dropped)DBI::dbExecute(peer$con,row$sql[[1L]])
      stopifnot(identical(trigger_rows(),original_triggers))
    },add=TRUE)
    DBI::dbExecute(peer$con,paste("DROP TRIGGER",DBI::dbQuoteIdentifier(peer$con,name)))
    dropped<-TRUE
    remaining<-original_triggers[original_triggers$name!=name,,drop=FALSE];rownames(remaining)<-NULL
    stopifnot(identical(trigger_rows(),remaining))
    fn()
  }
  original_body<-function()DBI::dbGetQuery(peer$con,
    "SELECT body_json FROM entity_versions WHERE kind='report' AND id=? AND revision=1",params=list(ref$id))$body_json[[1L]]
  e<-error_of(DBI::dbExecute(peer$con,"UPDATE entity_versions SET body_json=? WHERE kind='report' AND id=? AND revision=1",params=list(sub("17","18",raw,fixed=TRUE),ref$id)))
  check("Normal immutable revision trigger refuses direct updates without changing bytes",
    inherits(e,"error")&&grepl("Entity revisions are immutable",conditionMessage(e),fixed=TRUE)&&
    identical(charToRaw(original_body()),charToRaw(raw))&&identical(trigger_rows(),original_triggers))
  media_type<-function()DBI::dbGetQuery(peer$con,"SELECT media_type FROM objects WHERE hash=?",params=list(object$hash))$media_type[[1L]]
  original_media_type<-media_type()
  e<-error_of(DBI::dbExecute(peer$con,"UPDATE objects SET media_type='text/plain' WHERE hash=?",params=list(object$hash)))
  check("Normal immutable object trigger refuses direct updates without changing metadata",
    inherits(e,"error")&&grepl("Object metadata is immutable",conditionMessage(e),fixed=TRUE)&&
    identical(media_type(),original_media_type)&&identical(trigger_rows(),original_triggers))
  sentinel_trigger<-structure(list(message="Synthetic corruption callback error",call=NULL,marker=29),class=c("synthetic_corruption_error","error","condition"))
  e<-error_of(corrupt_synthetic_row("versions_no_update",function()stop(sentinel_trigger)))
  check("Synthetic corruption helper restores exact trigger SQL after callback error",
    identical(e,sentinel_trigger)&&identical(trigger_rows(),original_triggers))
  interrupted_trigger<-tryCatch(corrupt_synthetic_row("objects_no_update",function()
    stop(structure(list(message="Synthetic corruption interrupt",call=NULL),class=c("interrupt","condition")))),interrupt=function(e)TRUE)
  check("Synthetic corruption helper restores exact trigger SQL during interrupt unwinding",
    isTRUE(interrupted_trigger)&&identical(trigger_rows(),original_triggers))
  check("Synthetic helper refuses any trigger outside its two-item update allowlist",
    inherits(error_of(corrupt_synthetic_row("versions_no_delete",function()NULL)),"error")&&identical(trigger_rows(),original_triggers))
  corrupt_synthetic_row("versions_no_update",function(){
    on.exit(DBI::dbExecute(peer$con,"UPDATE entity_versions SET body_json=? WHERE kind='report' AND id=? AND revision=1",params=list(raw,ref$id)),add=TRUE)
    DBI::dbExecute(peer$con,"UPDATE entity_versions SET body_json=? WHERE kind='report' AND id=? AND revision=1",params=list(sub("17","18",raw,fixed=TRUE),ref$id))
    check("Raw body edit with unchanged body_hash invalidates proof",stale(brohn_store_batch(store,function()p(store))))
  })
  check("Raw-body corruption scope restores original bytes and all trigger SQL",
    identical(charToRaw(original_body()),charToRaw(raw))&&identical(trigger_rows(),original_triggers))
  p<-proof();DBI::dbExecute(peer$con,"UPDATE entities SET project_id='other' WHERE kind='report' AND id=?",params=list(ref$id))
  check("Fresh source owner revocation refuses before mutation",inherits(error_of(brohn_store_batch(store,function()p(store))),"error"))
  DBI::dbExecute(peer$con,"UPDATE entities SET project_id='default' WHERE kind='report' AND id=?",params=list(ref$id))
  p<-proof();old<-DBI::dbGetQuery(store$con,"SELECT result_json FROM jobs WHERE id=?",params=list(producer$id))$result_json[[1L]]
  DBI::dbExecute(peer$con,"UPDATE jobs SET result_json=? WHERE id=?",params=list('{"synthetic":false}',producer$id))
  check("Original successful producer result change invalidates proof",stale(brohn_store_batch(store,function()p(store))))
  DBI::dbExecute(peer$con,"UPDATE jobs SET result_json=? WHERE id=?",params=list(old,producer$id))
  # The real store publishes objects read-only. Deliberate corruption must
  # explicitly scope both permission and byte restoration to this one fixture.
  fixture_object_path<-normalizePath(object$path,winslash="/",mustWork=TRUE)
  fixture_object_bytes<-readBin(fixture_object_path,"raw",n=file.info(fixture_object_path)$size)
  fixture_object_mode<-as.character(file.info(fixture_object_path)$mode)
  object_exact<-function()identical(readBin(fixture_object_path,"raw",n=file.info(fixture_object_path)$size),fixture_object_bytes)&&
    identical(as.character(file.info(fixture_object_path)$mode),fixture_object_mode)
  check("Synthetic object starts with exact source bytes and the store's read-only mode",
    identical(fixture_object_bytes,charToRaw("synthetic object bytes"))&&
    bitwAnd(as.integer(file.info(fixture_object_path)$mode),as.integer(as.octmode("0222")))==0L)
  corrupt_synthetic_object<-function(fn){
    stopifnot(is.function(fn),identical(peer$con,fixture_connection),
      identical(normalizePath(store$root,winslash="/",mustWork=TRUE),fixture_root),
      identical(normalizePath(brohn_object_path(store,object$hash,TRUE),winslash="/",mustWork=TRUE),fixture_object_path),
      startsWith(fixture_object_path,paste0(fixture_root,"/objects/sha256/")),object_exact())
    # No path argument or general chmod helper: exactly this owned file only.
    # Restore bytes before read-only mode; even a byte-restore error still runs
    # the finally permission restoration. This is not a crash-recovery claim.
    on.exit({
      tryCatch({
        stopifnot(Sys.chmod(fixture_object_path,"0644"))
        writeBin(fixture_object_bytes,fixture_object_path)
      },finally=stopifnot(Sys.chmod(fixture_object_path,fixture_object_mode)))
      stopifnot(object_exact())
    },add=TRUE)
    stopifnot(Sys.chmod(fixture_object_path,"0644"))
    fn()
  }
  physical_error<-structure(list(message="Synthetic physical callback error",call=NULL,marker=41),class=c("synthetic_physical_error","error","condition"))
  e<-error_of(corrupt_synthetic_object(function(){
    writeBin(c(fixture_object_bytes,as.raw(0)),fixture_object_path)
    stop(physical_error)
  }))
  check("Synthetic physical helper restores original bytes and mode after callback error",
    identical(e,physical_error)&&object_exact())
  p<-proof()
  corrupt_synthetic_object(function(){
    writeBin(c(fixture_object_bytes,as.raw(0)),fixture_object_path)
    check("Current physical object size is checked inside commit",inherits(error_of(brohn_store_batch(store,function()p(store))),"error"))
  })
  check("Synthetic physical corruption success restores exact bytes and read-only mode",object_exact())
  p<-proof()
  corrupt_synthetic_row("objects_no_update",function(){
    on.exit(DBI::dbExecute(peer$con,"UPDATE objects SET media_type=? WHERE hash=?",params=list(original_media_type,object$hash)),add=TRUE)
    DBI::dbExecute(peer$con,"UPDATE objects SET media_type='text/plain' WHERE hash=?",params=list(object$hash))
    check("Registered object row change invalidates proof",stale(brohn_store_batch(store,function()p(store))))
  })
  check("Object corruption scope restores original metadata and all trigger SQL",
    identical(media_type(),original_media_type)&&identical(trigger_rows(),original_triggers))
  p<-proof();substituted<-store;substituted$workspace_id<-"other"
  check("Private proof refuses a different workspace",inherits(error_of(p(substituted)),"error"))
  check("Private proof refuses a different connection even to the same workspace",inherits(error_of(p(peer)),"error"))
  original_authority<-brohn_report_package_queue_authority
  brohn_report_package_queue_authority<-function(...)stop("Synthetic current authority revoked")
  check("Fresh authority is required after valid preflight",inherits(error_of(brohn_store_batch(store,function()p(store))),"error"))
  brohn_report_package_queue_authority<-original_authority
  active<-brohn_enqueue_job(store,"synthetic_progress",list(value=1),"synthetic-heartbeat")
  running<-brohn_claim_job(peer,"second-connection",60)
  check("Queued-to-running progress remains eligible without rebuilding immutable proof",identical(.brohn_rptx_pending_current(store,active)$id,running$id))
  brohn_renew_job(peer,running$id,running$worker,running$token,60)
  check("Ordinary heartbeat fields do not invalidate active dependency state",identical(.brohn_rptx_pending_current(store,running)$status,"running"))
  brohn_complete_job(peer,running$id,running$worker,running$token,list(synthetic=TRUE))
  check("Concurrent successful terminal transition requests fresh preflight",stale(.brohn_rptx_pending_current(store,running)))
  # A WAL read snapshot can coexist with a real writer on a different connection.
  active<-brohn_enqueue_job(store,"synthetic_progress",list(value=2),"synthetic-heartbeat-two")
  running<-brohn_claim_job(peer,"second-connection",60)
  .brohn_rptx_snapshot(store,function(){
    DBI::dbGetQuery(store$con,"SELECT count(*) FROM entities")
    start<-proc.time()[["elapsed"]]
    brohn_renew_job(peer,running$id,running$worker,running$token,60)
    check("Real second-connection heartbeat commits while read snapshot remains open",RSQLite::sqliteIsTransacting(store$con)&&proc.time()[["elapsed"]]-start<5)
  })
  brohn_cancel_job(store,running$id)
  check("Concurrent cancellation requests fresh preflight",stale(.brohn_rptx_pending_current(store,running)))
  check("All read snapshots leave the connection nontransacting and writable",query_only()==0L&&!RSQLite::sqliteIsTransacting(store$con))
  check("Synthetic fixture finishes with every original trigger exact",identical(trigger_rows(),original_triggers))
},error=function(e){failure<<-conditionMessage(e)})
if(!is.null(peer))brohn_close_store(peer)
if(!is.null(store))brohn_close_store(store)
result<-list(schema="brohn-transaction-proof-controls/1.0",status=if(is.null(failure))"passed"else"failed",scope="synthetic stores and real SQLite connections; no scientific or native display qualification",checks=checks,error=failure,store_closed=TRUE)
writeLines(jsonlite::toJSON(result,auto_unbox=TRUE,null="null",pretty=TRUE),file.path(out,"RESULTS.json"),useBytes=TRUE)
if(!is.null(failure))stop(failure,call.=FALSE)

# Engineering-only delivery-domain regression. Actual store/schema/metadata,
# upstream questionnaire provenance validation and private capture are used.
# Task/choice metadata rows below are declared capture-boundary fixtures, not
# native task/choice scientific reports. No workers, services or analysis run.
# Rscript delivery-domains.R <joined-checkout> <new-output>
args<-commandArgs(TRUE);stopifnot(length(args)==2L)
checkout<-normalizePath(args[[1L]],winslash="/",mustWork=TRUE);out<-args[[2L]]
stopifnot(!file.exists(out));dir.create(out,recursive=TRUE);out<-normalizePath(out,winslash="/",mustWork=TRUE)
setwd(checkout);source("R/platform-load.R",encoding="UTF-8");brohn_load(ui=FALSE)
checks<-list();failure<-NULL;nd<-store<-NULL
check<-function(label,ok){checks[[length(checks)+1L]]<<-list(label=label,passed=isTRUE(ok));cat(if(isTRUE(ok))"PASS"else"FAIL",label,"\n");stopifnot(isTRUE(ok))}
error_of<-function(expr)tryCatch({force(expr);NULL},error=function(e)e)
stale<-function(expr)inherits(error_of(expr),"brohn_report_preflight_stale")
delivery_rows<-function(p)Filter(function(r)grepl("FROM delivery_runs r",r$sql,fixed=TRUE),environment(p)$rows)
tables<-function(s)sort(DBI::dbListTables(s$con))
init<-function(path){s<-brohn_open_store(path)
  brohn_put_entity(s,"project","default",list(id="default",title="Synthetic delivery-domain controls",archived=FALSE))
  d<-brohn_new_design("Synthetic delivery-domain controls","survey","study-delivery-domains");d$project_id<-"default"
  brohn_put_entity(s,"study",d$id,d,0L,"default");s}
tryCatch({
  nd<-init(file.path(out,"no-delivery-workspace"));before_tables<-tables(nd)
  check("A normal fresh core store has no delivery tables",!any(grepl("^delivery_",before_tables)))
  # These two literal analytical labels occur in the genuine child ECG report
  # body.analysis.exclusion_review.runs. The new test does not alter that report.
  analytical<-list(record=list(body=list(analysis=list(exclusion_review=list(runs=list(
    list(run_id="review-run-1"),list(run_id="review-run-2")))))),
    descriptive=list(run_id="imported-run-description"),
    nested=list(run_sources=list(list(run_id="not-admitted-delivery"))))
  p<-.brohn_rptx_snapshot(nd,function().brohn_rptx_capture(nd,list(analytical),list(),"study-delivery-domains","default"))
  check("Nested analytical and imported run labels cause zero delivery lookup",length(delivery_rows(p))==0L&&length(environment(p)$runs)==0L)
  check("Analytical-only proof remains current without initializing delivery",isTRUE(brohn_store_batch(nd,function()p(nd)))&&identical(tables(nd),before_tables))
  p<-.brohn_rptx_snapshot(nd,function().brohn_rptx_capture(nd,list(analytical),list(),"study-delivery-domains","default",
    delivery_sources=list(list(run_sources_extra=list(list(run_id="not-exact-field"))))))
  check("Plural or prefixed metadata field names are not delivery provenance",length(delivery_rows(p))==0L&&identical(tables(nd),before_tables))
  e<-error_of(.brohn_rptx_snapshot(nd,function().brohn_rptx_capture(nd,list(),list(),"study-delivery-domains","default",
    delivery_sources=list(list(run_sources=list(list(run_ids="not-exact-id")))))))
  check("An admitted run entry needs the exact run_id field",inherits(e,"error")&&grepl("exact run identity",conditionMessage(e),fixed=TRUE))
  e<-error_of(.brohn_rptx_snapshot(nd,function().brohn_rptx_capture(nd,list(),list(),"study-delivery-domains","default",
    delivery_sources=list(list(run_sources=list(list(run_id="real-delivery-id",final_sequence=2L)))))))
  check("Explicit delivery dependency still refuses absent delivery tables",inherits(e,"error")&&grepl("no such table: delivery_runs",conditionMessage(e),fixed=TRUE)&&identical(tables(nd),before_tables))
  check("No-delivery refusals restore read-only state and close the snapshot",!RSQLite::sqliteIsTransacting(nd$con)&&DBI::dbGetQuery(nd$con,"PRAGMA query_only")[[1L]][[1L]]==0L)

  # A separate, expressly synthetic fixture intentionally initializes the real
  # delivery schema. The analytical-only workspace above remains untouched.
  store<-init(file.path(out,"delivery-workspace"));.brohn_delivery_schema(store)
  design<-brohn_get_entity(store,"study","study-delivery-domains")$body
  stamp<-brohn_now();hash<-brohn_hash(list(synthetic=TRUE))
  for(i in seq_len(3L)){
    DBI::dbAppendTable(store$con,"delivery_deployments",data.frame(id=paste0("deployment-",i),study_id=design$id,project_id="default",
      title="Synthetic provenance fence",origin="sample",status="closed",quota=1L,alias_required=0L,design_revision=1L,
      design_json=brohn_json(design),design_hash=brohn_hash(design),created_at=stamp,updated_at=stamp,stringsAsFactors=FALSE))
    DBI::dbAppendTable(store$con,"delivery_runs",data.frame(id=paste0("delivery-run-",i),deployment_id=paste0("deployment-",i),study_id=design$id,
      origin="sample",participant_alias=paste0("participant-",i),client_id=paste0("client-",i),start_hash=hash,protocol_json="{}",protocol_hash=hash,
      allocation_index=1L,completion_status="completed",transfer_status="saved",acked_sequence=2L,created_at=stamp,updated_at=stamp,
      finalized_at=stamp,participant_alias_supplied=0L,stringsAsFactors=FALSE))
  }
  result_object<-brohn_store_object(store,bytes=charToRaw("{}"),media_type="application/json")
  body<-list(id="report-delivery-questionnaire",title="Synthetic original questionnaire",study_id=design$id,origin="sample",
    analysis=list(kind="questionnaire"),result_object=result_object,
    provenance=list(design=design,design_hash=brohn_hash(design),run_evidence=list(runs=list(list(run_id="delivery-run-1",final_sequence=2L)))))
  ref<-.brohn_rpk_ref(brohn_put_entity(store,"report",body$id,body,0L,"default"))
  m<-.brohn_rpk_report_metadata(store,ref)
  check("Ordinary metadata extracts only saved run_evidence.runs",.brohn_rpk_same(m$run_sources,body$provenance$run_evidence$runs))
  object<-.brohn_rpk_report_proof(store,m,require_job=FALSE)
  check("Existing questionnaire provenance validator admits the exact completed receipt",identical(object$hash,result_object$hash))
  # The additional two entries model the shared already-admitted run_sources
  # shape of native task/choice report metadata. Their science is not fabricated
  # or passed through a scientific validator; only the capture seam is tested.
  admitted<-list(m,list(ref=ref,source_family="native_questionnaire",run_sources=list(list(run_id="delivery-run-2",final_sequence=2L))),
    list(ref=ref,choice_source_family="native_questionnaire",run_sources=list(list(run_id="delivery-run-3",final_sequence=2L))))
  proof<-function().brohn_rptx_snapshot(store,function().brohn_rptx_capture(store,list(analytical,m),list(object),design$id,"default",delivery_sources=admitted))
  p<-proof();dr<-delivery_rows(p)
  check("Questionnaire, task and choice admitted delivery IDs are all retained",identical(sort(unname(vapply(dr,function(r)r$params[[1L]],character(1)))),paste0("delivery-run-",1:3)))
  check("Each delivery fence captures the full current row plus deployment owner",length(dr)==3L&&all(vapply(dr,function(r)
    nrow(r$value)==1L&&all(c("completion_status","transfer_status","acked_sequence","owner_project_id","study_id","protocol_hash") %in% names(r$value)),logical(1))))
  check("Mixed analytical plus explicit delivery proof accepts unchanged state",isTRUE(brohn_store_batch(store,function()p(store))))
  deployments<-DBI::dbGetQuery(store$con,"SELECT * FROM delivery_deployments ORDER BY id")
  runs<-DBI::dbGetQuery(store$con,"SELECT * FROM delivery_runs ORDER BY id")
  triggers<-function()DBI::dbGetQuery(store$con,"SELECT name,tbl_name,sql FROM sqlite_master WHERE type='trigger' ORDER BY name")
  trigger_before<-triggers()
  e<-error_of(DBI::dbExecute(store$con,"UPDATE delivery_runs SET acked_sequence=3 WHERE id='delivery-run-1'"))
  check("Real schema refuses direct mutation of a terminal delivery receipt",inherits(e,"error")&&grepl("Terminal run outcomes are immutable",conditionMessage(e),fixed=TRUE)&&identical(triggers(),trigger_before))
  # Controlled replacement is restricted to these two fresh synthetic tables
  # and always rolled back. No trigger is removed or weakened; this is an
  # adversarial current-state fixture, not a public withdrawal API exercise.
  with_rows<-function(rs=runs,ds=deployments,fn){
    stopifnot(!RSQLite::sqliteIsTransacting(store$con),identical(triggers(),trigger_before))
    .brohn_store_transaction_statement(store,"BEGIN IMMEDIATE")
    on.exit(.brohn_store_transaction_statement(store,"ROLLBACK"),add=TRUE)
    DBI::dbExecute(store$con,"DELETE FROM delivery_runs");DBI::dbExecute(store$con,"DELETE FROM delivery_deployments")
    if(nrow(ds))DBI::dbAppendTable(store$con,"delivery_deployments",ds)
    if(nrow(rs))DBI::dbAppendTable(store$con,"delivery_runs",rs)
    fn()
  }
  for(field in c("completion_status","transfer_status","acked_sequence","study_id")){
    changed<-runs
    changed[[field]][[1L]]<-switch(field,completion_status="withdrawn",transfer_status="receiving",acked_sequence=3L,study_id="study-another")
    with_rows(changed,fn=function(){
      check(paste("Current delivery",field,"drift invalidates the raw proof"),stale(p(store)))
      check(paste("Original provenance validator also refuses",field,"drift"),inherits(error_of(.brohn_rpk_report_proof(store,m,require_job=FALSE)),"error"))
    })
  }
  changed_owner<-deployments;changed_owner$project_id[[1L]]<-"other"
  with_rows(ds=changed_owner,fn=function(){
    check("Current deployment owner change invalidates the proof",stale(p(store)))
    check("Original provenance validator refuses changed owner",inherits(error_of(.brohn_rpk_report_proof(store,m,require_job=FALSE)),"error"))
  })
  with_rows(rs=runs[-1L,,drop=FALSE],fn=function(){
    check("Missing original delivery row invalidates the proof",stale(p(store)))
    check("Original provenance validator refuses missing original delivery",inherits(error_of(.brohn_rpk_report_proof(store,m,require_job=FALSE)),"error"))
  })
  # Real-shaped task/choice boundaries must also carry their own current row.
  for(i in 2:3){changed<-runs;changed$acked_sequence[[i]]<-3L
    with_rows(changed,fn=function()check(paste("Admitted task or choice row",i,"also invalidates on final sequence drift"),stale(p(store))))}
  check("Synthetic replacements restore exact rows, triggers and current proof",identical(DBI::dbGetQuery(store$con,"SELECT * FROM delivery_runs ORDER BY id"),runs)&&
    identical(DBI::dbGetQuery(store$con,"SELECT * FROM delivery_deployments ORDER BY id"),deployments)&&identical(triggers(),trigger_before)&&isTRUE(brohn_store_batch(store,function()p(store))))
  check("Analytical workspace still has no delivery schema",identical(tables(nd),before_tables))
  check("Both fixtures have zero jobs",DBI::dbGetQuery(store$con,"SELECT count(*) n FROM jobs")$n[[1L]]==0L&&DBI::dbGetQuery(nd$con,"SELECT count(*) n FROM jobs")$n[[1L]]==0L)
},error=function(e){failure<<-conditionMessage(e)})
if(!is.null(store))brohn_close_store(store)
if(!is.null(nd))brohn_close_store(nd)
result<-list(schema="brohn-transaction-delivery-domain-controls/1.0",status=if(is.null(failure))"passed"else"failed",
  scope="Synthetic SQLite/schema and actual metadata/proof boundaries; not native participant/scientific qualification",checks=checks,error=failure,stores_closed=TRUE)
writeLines(jsonlite::toJSON(result,auto_unbox=TRUE,null="null",pretty=TRUE),file.path(out,"RESULTS.json"),useBytes=TRUE)
if(!is.null(failure))stop(failure,call.=FALSE)

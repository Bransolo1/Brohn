# Focused prospective-selection regression. Actual SQLite orchestration and
# transaction fences; source admission and saved-science metadata are synthetic.
# No workers, scientific analysis, subprocesses, services or real source fixtures.
# Rscript <this-file> <checkout> <overlay-or-checkout> <fresh-output> <baseline|fixed>
args<-commandArgs(TRUE);stopifnot(length(args)==4L,args[[4L]] %in% c("baseline","fixed"))
checkout<-normalizePath(args[[1L]],winslash="/",mustWork=TRUE)
overlay<-normalizePath(args[[2L]],winslash="/",mustWork=TRUE)
out<-args[[3L]];stopifnot(!file.exists(out));dir.create(out,recursive=TRUE)
out<-normalizePath(out,winslash="/",mustWork=TRUE);fixed<-args[[4L]]=="fixed"
setwd(checkout);source("R/platform-load.R",encoding="UTF-8");brohn_load(ui=FALSE)
if(fixed)for(p in c("platform-report-package.R","platform-report-package-preparation.R"))
  source(file.path(overlay,"R",p),encoding="UTF-8")
source(file.path(overlay,"R","platform-report-package-transactions.R"),encoding="UTF-8")
checks<-list();failure<-NULL;store<-NULL
check<-function(label,value){ok<-isTRUE(value);checks[[length(checks)+1L]]<<-list(label=label,passed=ok)
  cat(if(ok)"PASS"else"FAIL",label,"\n");if(!ok)stop(label,call.=FALSE)}
reject<-function(expr)tryCatch({force(expr);FALSE},error=function(e)TRUE)
identity_files<-list(report=.brohn_rpk_files,task=.brohn_td_files,choice=.brohn_cd_files,eda=.brohn_edd_files,cardiac=.brohn_cdd_files)
changed<-c("R/platform-report-package.R","R/platform-report-package-preparation.R")
check("Both orchestration modules remain bound by report identity",all(changed %in% identity_files$report))
check("Four dedicated display source lists exclude both modules",all(vapply(identity_files[-1L],function(x)!any(changed %in% x),logical(1))))
queue_names<-c("brohn_queue_task_display","brohn_queue_choice_display","brohn_queue_eda_display","brohn_queue_cardiac_display","brohn_queue_explicit_distributions_ref")
queue_bodies<-lapply(queue_names,function(n)deparse(body(get(n))))

spy<-new.env(parent=emptyenv());spy$kind<-"task_display";spy$authority<-TRUE;spy$source<-TRUE
spy$renderer<-"one";spy$implementation<-"one";spy$ready<-list();spy$calls<-0L;spy$closure_checks<-0L
profiles<-c(task_display="saved-task-display/0.1",choice_display="saved-choice-display/0.1",eda_display="saved-eda-display/0.2",cardiac_display="saved-cardiac-display/0.1",explicit_distributions="saved-explicit-distribution/0.1")
implementation<-function(kind=spy$kind)list(profile=unname(profiles[[kind]]),fixture=spy$implementation)
implref<-function(kind=spy$kind).brohn_td_implementation_ref(implementation(kind))
renderer<-function()list(profile="fixture-renderer",hash=brohn_hash(spy$renderer))
brohn_task_display_implementation_ref<-function(...)implref("task_display")
brohn_choice_display_implementation_ref<-function(...)implref("choice_display")
brohn_eda_display_implementation_ref<-function(...)implref("eda_display")
brohn_cardiac_display_implementation_ref<-function(...)implref("cardiac_display")
.brohn_rpk_distribution_implementation_ref<-function(...)implref("explicit_distributions")
.brohn_rpk_renderer_implementation_ref<-renderer
brohn_report_package_queue_authority<-function(store,operation,project_id){
  brohn_require(spy$authority,"Synthetic current authority revoked.");list(fixture="current",project_id=project_id)}
.brohn_rpk_request<-function(store,request){
  brohn_report_package_queue_authority(store,"report_package",request$project_id)
  brohn_require(spy$source,"Synthetic original source closure changed.");invisible(request)}
.brohn_rpk_execution_plan<-function(request)list(schema="synthetic-plan",renderer_implementation_ref=renderer(),display_implementation_ref=implref())
.brohn_rpk_plan_valid<-function(plan,request){brohn_require(identical(plan$schema,"synthetic-plan"),"Synthetic plan changed.");invisible(TRUE)}
.brohn_rpk_eda_requirements<-function(...)list(fixture="original-source")
.brohn_rpcc_requirements<-function(...)list(fixture="original-source")
.brohn_rpk_eda_requirements_current<-.brohn_rpcc_requirements_current<-function(store,b){
  spy$closure_checks<-spy$closure_checks+1L;brohn_require(spy$source,"Synthetic original source closure changed.");invisible(TRUE)}
.brohn_rpk_task_dependency_specs<-function(store,request,plan,requirements=NULL)lapply(request$report_refs,function(ref)
  list(slot=brohn_hash(list(kind=spy$kind,ref=ref)),kind=spy$kind,report_ref=ref,
       implementation_ref=plan$display_implementation_ref,display_request=list(fixture="exact-display")))
found<-function(store,report_ref,...)spy$ready[[report_ref$id]]
brohn_find_task_display<-brohn_find_choice_display<-brohn_find_eda_display<-brohn_find_cardiac_display<-found
.brohn_rpk_find_pinned_distribution<-.brohn_rpk_find_distribution<-found
request_for<-function(store,report_ref,implementation_ref=NULL,kind=spy$kind,fingerprint=TRUE){
  spy$calls<-spy$calls+1L;authority<-brohn_report_package_queue_authority(store,kind,report_ref$project_id)
  brohn_require(spy$source,"Synthetic original source closure changed.")
  if(!is.null(implementation_ref))brohn_require(.brohn_rpk_same(implementation_ref,implref(kind)),"Synthetic current implementation differs.")
  r<-list(schema=if(kind=="cardiac_display")"brohn-cardiac-display-job/0.1"else"synthetic-display-job",
    report_ref=report_ref,project_id=report_ref$project_id,display_request=list(fixture="exact-display"),
    implementation=implementation(kind),authority=authority)
  if(fingerprint)r$content_fingerprint<-brohn_hash(r[setdiff(names(r),"authority")]);r
}
.brohn_task_display_request<-function(store,report_ref,implementation_ref=NULL)request_for(store,report_ref,implementation_ref,"task_display")
.brohn_choice_display_request<-function(store,report_ref,implementation_ref=NULL)request_for(store,report_ref,implementation_ref,"choice_display")
.brohn_eda_display_request<-function(store,report_ref,display_request=NULL,implementation_ref=NULL,preparation_profile=NULL)request_for(store,report_ref,implementation_ref,"eda_display")
.brohn_cdd_queue_request<-function(store,report_ref,display_request=NULL,implementation_ref=NULL)request_for(store,report_ref,implementation_ref,"cardiac_display")
.brohn_rpk_distribution_request<-function(store,report_ref,implementation_ref=NULL,source_admission=NULL)request_for(store,report_ref,implementation_ref,"explicit_distributions",FALSE)
# Additional metadata seam used by the new read phase: this is deliberately
# synthetic, just like the existing successful-discovery fixture below.
brohn_cardiac_display_metadata<-function(store,ref)list(ref=ref,
  record=brohn_get_entity(store,ref$kind,ref$id,ref$revision),objects=list())
# Stop before assembly in the saved-result reuse control, without inventing
# a prepared model. All display lookup and queue behavior before this is actual.
.brohn_rpk_resolve_sections<-function(...)stop("Synthetic test ends after saved-result reuse.")

tryCatch({
store<-brohn_open_store(file.path(out,"workspace"))
invisible(brohn_put_entity(store,"project","default",list(id="default",title="Synthetic cancellation test",archived=FALSE)))
design<-brohn_new_design("Synthetic cancellation test","survey","study-cancellation-fixture")
invisible(brohn_put_entity(store,"study",design$id,design))
source_refs<-list()
source_ref<-function(id){r<-.brohn_rpk_ref(brohn_put_entity(store,"report",id,list(id=id,study_id=design$id,origin="sample",analysis=list(kind="synthetic",value=17)),0L,"default"))
  source_refs[[id]]<<-r;r}
make_request<-function(ref,title,classic=FALSE){
  renderer_profile<-if(classic)"controlled-gaze-explicit-paired/0.1"else switch(spy$kind,
    cardiac_display="controlled-gaze-explicit-task-choice-eda-cardiac-paired/0.2",
    eda_display="controlled-gaze-explicit-task-choice-eda-paired/0.3",
    choice_display="controlled-gaze-explicit-task-choice-paired/0.1",
    "controlled-gaze-explicit-task-paired/0.1")
  list(schema="brohn-report-package-intent-request/0.1",study_id=design$id,project_id="default",title=title,
    report_refs=list(ref),requested_sections=if(classic)list(list(adapter="explicit-distribution",source_report_ref=ref))else list(),
    contents_policy=list(fixture=TRUE),limits_profile="synthetic-test",renderer_profile=renderer_profile)
}
create<-function(id,ref,classic=FALSE){req<-make_request(ref,id,classic);brohn_save_report_package_intent(store,id,req)}
count<-function()DBI::dbGetQuery(store$con,"SELECT count(*) n FROM jobs")$n[[1L]]
jobrow<-function(id)DBI::dbGetQuery(store$con,"SELECT * FROM jobs WHERE id=?",params=list(id))
headbody<-function(v)brohn_get_entity(store,"report_package_intent",v$intent_ref$id)$body
advance<-function(v,action="advance")brohn_continue_report_package_intent(store,v$intent_ref,action)
cancel<-function(v)brohn_cancel_report_package_intent(store,v$intent_ref)
drain<-function(){for(id in DBI::dbGetQuery(store$con,"SELECT id FROM jobs WHERE status IN ('queued','running')")$id)invisible(brohn_cancel_job(store,id))}
queue_direct<-function(ref,retry=FALSE){switch(spy$kind,
  task_display=brohn_queue_task_display(store,ref,retry,implref()),
  choice_display=brohn_queue_choice_display(store,ref,retry,implref()),
  eda_display=brohn_queue_eda_display(store,ref,list(fixture="exact-display"),retry,implref(),implref()$profile),
  cardiac_display=brohn_queue_cardiac_display(store,ref,list(fixture="exact-display"),retry,implref()),
  explicit_distributions=brohn_queue_explicit_distributions_ref(store,ref,retry,if(classic)NULL else implref()))}

# This block is assembled below the explicit synthetic recovery fixture setup.
# Actual SQLite rows, private read snapshot/capture/commit, cancellation and
# queue writes are used. Saved science and source admission are deliberate spies.
spy$kind<-"cardiac_display";drain()
error_of<-function(expr)tryCatch({force(expr);NULL},error=function(e)e)
db_state<-function()lapply(c("jobs","entities","entity_versions","objects"),function(n)
  DBI::dbGetQuery(store$con,paste("SELECT * FROM",n,"ORDER BY rowid")))
read_phase<-function(store)check("Synthetic source callback runs in enforced read phase",
  RSQLite::sqliteIsTransacting(store$con)&&DBI::dbGetQuery(store$con,"PRAGMA query_only")[[1L]][[1L]]==1L)
ref<-source_ref("report-prospective-source")
saved<-.brohn_rpk_ref(brohn_put_entity(store,"cardiac_display","saved-prospective-display",
  list(schema="synthetic-saved-display",source_ref=ref),0L,"default"))
spy$ready[[ref$id]]<-saved
object<-.brohn_rpk_object(store,brohn_store_object(store,bytes=charToRaw("synthetic prospective object"),media_type="application/octet-stream"))
producer<-brohn_enqueue_job(store,"synthetic_prospective_producer",list(synthetic=TRUE),"prospective-producer")
producer<-brohn_claim_job(store,"synthetic-prospective",60)
brohn_complete_job(store,producer$id,producer$worker,producer$token,list(synthetic=TRUE))
brohn_cardiac_display_metadata<-function(store,ref)list(ref=ref,
  record=brohn_get_entity(store,ref$kind,ref$id,ref$revision),objects=list(object),producer=list(job_id=producer$id))
.brohn_rpk_resolve_sections<-function(store,request,deps){read_phase(store);list(sections=list(),panel_count=0L,known_panel_count=0L)}
spy$legacy<-NULL
.brohn_rpk_selection_sources<-function(store,selection,pulse=NULL){
  read_phase(store)
  m<-list(schema="brohn-combined-cardiac-source-metadata/0.1",selection=selection,
    report_refs=selection$report_refs,reports=list(list(ref=ref)),
    cardiac_displays=list(brohn_cardiac_display_metadata(store,saved)),objects=list(object),legacy=spy$legacy)
  spy$last_metadata<-m;m
}
.brohn_rpk_implementation<-function()list(profile="synthetic-package-implementation",version=1L)
view<-create("prospective-package",ref);before<-db_state()
plan<-.brohn_rptx_snapshot(store,function().brohn_rptx_prepare(store,view$intent_ref,"advance"))
check("New-package preflight performs no catalogue mutation",identical(before,db_state())&&plan$mode=="package")
s<-plan$selection;m<-spy$last_metadata
check("Fixture retains the real returned selection envelope with a not-yet-persisted intent revision",
  .brohn_rptx_equal(m$selection,s)&&is.null(brohn_get_entity(store,"report_package_intent",s$intent_ref$id,s$intent_ref$revision))&&
  s$intent_ref$revision==view$intent_ref$revision+1L)
capture<-function(value).brohn_rptx_snapshot(store,function().brohn_rptx_capture(store,list(value),list(object),design$id,"default",list(view$intent_ref)))
raw_error<-error_of(capture(m))
check("Unprojected genuine-shaped envelope reproduces unavailable prospective revision refusal",
  inherits(raw_error,"error")&&grepl("saved source revision is unavailable",conditionMessage(raw_error),fixed=TRUE)&&identical(before,db_state()))
original_m<-serialize(m,NULL);original_s<-serialize(s,NULL)
evidence<-.brohn_rptx_prospective_evidence(m,s)
expected<-m;expected[["selection"]][["intent_ref"]]<-NULL
check("Projection removes exactly one root intent leaf and leaves both inputs unchanged",
  .brohn_rptx_equal(evidence,expected)&&identical(serialize(m,NULL),original_m)&&identical(serialize(s,NULL),original_s))
check("Current persisted intent remains an explicit read-set dependency",
  any(vapply(environment(plan$fence)$refs,function(r).brohn_rpk_same(r,view$intent_ref),logical(1))))
check("Every real selected report and saved preparation ref remains in the read set",
  all(vapply(list(ref,saved),function(want)any(vapply(environment(plan$fence)$refs,function(r).brohn_rpk_same(r,want),logical(1))),logical(1))))
for(mode in c("absent","near_match","different_title","different_intent","null_intent")){
  bad<-m;local_s<-s
  if(mode=="absent")bad[["selection"]]<-NULL
  if(mode=="near_match"){bad[["selection_extra"]]<-bad[["selection"]];bad[["selection"]]<-NULL}
  if(mode=="different_title")bad[["selection"]]$title<-"mismatched source admission"
  if(mode=="different_intent")bad[["selection"]]$intent_ref<-view$intent_ref
  if(mode=="null_intent"){local_s[["intent_ref"]]<-NULL;bad[["selection"]]<-local_s}
  check(paste("Exact prospective projection refuses",mode),inherits(error_of(.brohn_rptx_prospective_evidence(bad,local_s)),"error")&&identical(before,db_state()))
}
for(mode in c("misplaced_root","misplaced_nested","missing_report","changed_report_hash","missing_prepared","changed_prepared_hash")){
  bad<-m;local_s<-s
  if(mode=="misplaced_root")bad$other_ref<-s$intent_ref
  if(mode=="misplaced_nested")local_s$sections<-list(list(retained_ref=s$intent_ref))
  if(mode=="missing_report")local_s$report_refs[[1L]]$id<-"missing-report"
  if(mode=="changed_report_hash"){bad$other_ref<-ref;bad$other_ref$body_hash<-paste(rep("0",64),collapse="")}
  if(mode=="missing_prepared")local_s$prepared_sources[[1L]]$prepared_ref$id<-"missing-prepared"
  if(mode=="changed_prepared_hash"){bad$other_ref<-saved;bad$other_ref$body_hash<-paste(rep("0",64),collapse="")}
  bad[["selection"]]<-local_s
  err<-error_of(capture(.brohn_rptx_prospective_evidence(bad,local_s)))
  check(paste("Projection preserves refusal for",mode),inherits(err,"error")&&identical(before,db_state()))
}
# A new-package context may already have the exact ready body. It still checks
# the returned selection and strips only that explicitly prospective leaf.
unchanged<-.brohn_rptx_virtual(plan$ready,plan$ready$body)
same_s<-s;same_s$intent_ref<-.brohn_rpk_ref(unchanged);same_m<-m;same_m$selection<-same_s
check("Unchanged virtual ready body needs no artificial revision increment",
  .brohn_rptx_equal(unchanged,plan$ready)&&is.null(.brohn_rptx_prospective_evidence(same_m,same_s)$selection$intent_ref))

commit_refuses_without_write<-function(label,fn){
  prior<-db_state();err<-error_of(fn())
  check(label,inherits(err,"error")&&identical(prior,db_state()))
}
spy$authority<-FALSE
commit_refuses_without_write("Revoked current authority still refuses final admission without writes",
  function()brohn_store_batch(store,function().brohn_rptx_commit(store,plan)))
spy$authority<-TRUE
old_result<-DBI::dbGetQuery(store$con,"SELECT result_json FROM jobs WHERE id=?",params=list(producer$id))$result_json[[1L]]
DBI::dbExecute(store$con,"UPDATE jobs SET result_json=? WHERE id=?",params=list('{"synthetic":"changed"}',producer$id))
commit_refuses_without_write("Changed saved producer still refuses final admission without writes",
  function()brohn_store_batch(store,function().brohn_rptx_commit(store,plan)))
DBI::dbExecute(store$con,"UPDATE jobs SET result_json=? WHERE id=?",params=list(old_result,producer$id))
DBI::dbExecute(store$con,"UPDATE entities SET project_id='other' WHERE kind='report' AND id=?",params=list(ref$id))
commit_refuses_without_write("Changed source owner still refuses final admission without writes",
  function()brohn_store_batch(store,function().brohn_rptx_commit(store,plan)))
DBI::dbExecute(store$con,"UPDATE entities SET project_id='default' WHERE kind='report' AND id=?",params=list(ref$id))
# One owned object only; no schema trigger or immutable catalogue row bypass.
object_bytes<-readBin(object$path,"raw",n=file.info(object$path)$size);object_mode<-as.character(file.info(object$path)$mode)
with_larger_object<-function(fn){
  stopifnot(startsWith(normalizePath(object$path,winslash="/"),paste0(normalizePath(store$root,winslash="/"),"/objects/sha256/")))
  on.exit({tryCatch({stopifnot(Sys.chmod(object$path,"0644"));writeBin(object_bytes,object$path)},
    finally=stopifnot(Sys.chmod(object$path,object_mode)))},add=TRUE)
  stopifnot(Sys.chmod(object$path,"0644"));writeBin(c(object_bytes,as.raw(0)),object$path);fn()
}
with_larger_object(function()commit_refuses_without_write("Changed physical object still refuses final admission without writes",
  function()brohn_store_batch(store,function().brohn_rptx_commit(store,plan))))
check("Physical fixture bytes and original mode restored",identical(readBin(object$path,"raw",n=file.info(object$path)$size),object_bytes)&&identical(as.character(file.info(object$path)$mode),object_mode))
# Failure after the new ready/selection writes must roll back the entire batch.
enqueue_original<-brohn_enqueue_job
brohn_enqueue_job<-function(store,operation,request,idempotency_key,...){
  if(operation=="report_package")stop("Synthetic final enqueue interruption")
  enqueue_original(store,operation,request,idempotency_key,...)
}
commit_refuses_without_write("Final queue exception rolls back ready intent and selection atomically",
  function()brohn_store_batch(store,function().brohn_rptx_commit(store,plan)))
brohn_enqueue_job<-enqueue_original
ready<-brohn_store_batch(store,function().brohn_rptx_commit(store,plan))
selection_record<-brohn_get_entity(store,"report_package_selection",ready$selection_ref$id,ready$selection_ref$revision)
ready_record<-brohn_get_entity(store,"report_package_intent",s$intent_ref$id,s$intent_ref$revision)
package_job<-brohn_get_job(store,ready$job_ref$id)
check("Final admission persists exactly the prospective ready identity and selection",
  ready$status=="assembly_queued"&&.brohn_rpk_same(.brohn_rpk_ref(ready_record),s$intent_ref)&&
  .brohn_rpk_same(selection_record$body,s)&&.brohn_rpk_same(package_job$request$selection_ref,ready$selection_ref))
check("Final admission queues exactly one package through ordinary storage",
  package_job$operation=="report_package"&&package_job$status=="queued"&&DBI::dbGetQuery(store$con,"SELECT count(*) n FROM jobs WHERE operation='report_package'")$n[[1L]]==1L)
# Persisted Retry must never call the prospective projection helper.
cancelled<-cancel(ready);old_selection<-cancelled$selection_ref;old_job<-jobrow(package_job$id)
projection_original<-.brohn_rptx_prospective_evidence
.brohn_rptx_prospective_evidence<-function(...)stop("Persisted Retry wrongly projected evidence")
before_retry<-db_state();retry_plan<-.brohn_rptx_snapshot(store,function().brohn_rptx_prepare(store,cancelled$intent_ref,"retry"))
check("Persisted Retry remains unprojected and read-only",retry_plan$mode=="retry_package"&&identical(before_retry,db_state())&&
  any(vapply(environment(retry_plan$fence)$refs,function(r).brohn_rpk_same(r,s$intent_ref),logical(1)))&&
  any(vapply(environment(retry_plan$fence)$refs,function(r).brohn_rpk_same(r,old_selection),logical(1))))
retried<-brohn_store_batch(store,function().brohn_rptx_commit(store,retry_plan))
.brohn_rptx_prospective_evidence<-projection_original
check("Persisted Retry preserves original selection and cancelled job",
  retried$status=="assembly_queued"&&.brohn_rpk_same(retried$selection_ref,old_selection)&&retried$job_ref$id!=package_job$id&&identical(jobrow(package_job$id),old_job))

# A separate new intent proves the captured current head still prevents stale
# prospective output after cancellation. No stale refusal persists a failed state.
fresh<-create("prospective-current-head",ref)
fresh_plan<-.brohn_rptx_snapshot(store,function().brohn_rptx_prepare(store,fresh$intent_ref,"advance"))
fresh_cancelled<-cancel(fresh)
commit_refuses_without_write("Concurrent current intent cancellation fences prospective output",
  function()brohn_store_batch(store,function().brohn_rptx_commit(store,fresh_plan)))
check("Stale final admission preserves the current cancelled intent",headbody(fresh_cancelled)$status=="cancelled")

# Explicitly synthetic mixed delivery boundary: actual delivery schema and raw
# row fence, but no claim to task/questionnaire scientific admission.
.brohn_delivery_schema(store);stamp<-brohn_now();hash<-brohn_hash(list(synthetic=TRUE))
DBI::dbAppendTable(store$con,"delivery_deployments",data.frame(id="prospective-deployment",study_id=design$id,project_id="default",
  title="Synthetic mixed prospective fence",origin="sample",status="closed",quota=1L,alias_required=0L,design_revision=1L,
  design_json=brohn_json(design),design_hash=brohn_hash(design),created_at=stamp,updated_at=stamp,stringsAsFactors=FALSE))
DBI::dbAppendTable(store$con,"delivery_runs",data.frame(id="prospective-delivery",deployment_id="prospective-deployment",study_id=design$id,
  origin="sample",participant_alias="synthetic",client_id="synthetic",start_hash=hash,protocol_json="{}",protocol_hash=hash,
  allocation_index=1L,completion_status="completed",transfer_status="saved",acked_sequence=2L,created_at=stamp,updated_at=stamp,
  finalized_at=stamp,participant_alias_supplied=0L,stringsAsFactors=FALSE))
mixed_ref<-source_ref("report-prospective-mixed-legacy")
spy$legacy<-list(reports=list(list(ref=mixed_ref,run_sources=list(list(run_id="prospective-delivery",final_sequence=2L)))),objects=list())
legacy_original<-.brohn_rptx_legacy_metadata
.brohn_rptx_legacy_metadata<-function(store,request,requirements)spy$legacy
mixed<-create("prospective-mixed",ref)
mixed_plan<-.brohn_rptx_snapshot(store,function().brohn_rptx_prepare(store,mixed$intent_ref,"advance"))
mixed_rows<-Filter(function(x)grepl("FROM delivery_runs r",x$sql,fixed=TRUE),environment(mixed_plan$fence)$rows)
check("Mixed legacy metadata has no extra selection and keeps exact admitted delivery row",
  is.null(spy$last_metadata$legacy[["selection",exact=TRUE]])&&length(mixed_rows)==1L&&
  mixed_rows[[1L]]$params[[1L]]=="prospective-delivery"&&mixed_rows[[1L]]$value$acked_sequence[[1L]]==2L&&
  any(vapply(environment(mixed_plan$fence)$refs,function(r).brohn_rpk_same(r,mixed_ref),logical(1))))
deployments<-DBI::dbGetQuery(store$con,"SELECT * FROM delivery_deployments ORDER BY id")
runs<-DBI::dbGetQuery(store$con,"SELECT * FROM delivery_runs ORDER BY id")
triggers<-DBI::dbGetQuery(store$con,"SELECT name,sql FROM sqlite_master WHERE type='trigger' ORDER BY name")
# Terminal rows are immutable. Use the existing synthetic replacement pattern:
# retain real triggers, replace only these fixture rows, and always roll back.
.brohn_store_transaction_statement(store,"BEGIN IMMEDIATE")
tryCatch({
  DBI::dbExecute(store$con,"DELETE FROM delivery_runs");DBI::dbExecute(store$con,"DELETE FROM delivery_deployments")
  changed<-deployments;changed$project_id[[1L]]<-"other"
  DBI::dbAppendTable(store$con,"delivery_deployments",changed);DBI::dbAppendTable(store$con,"delivery_runs",runs)
  before_mixed<-db_state();mixed_error<-error_of(.brohn_rptx_commit(store,mixed_plan))
  check("Mixed delivery owner drift remains fenced with zero publication writes",
    inherits(mixed_error,"brohn_report_preflight_stale")&&identical(before_mixed,db_state()))
},finally=.brohn_store_transaction_statement(store,"ROLLBACK"))
check("Mixed fixture restores exact delivery rows and keeps all triggers",
  identical(deployments,DBI::dbGetQuery(store$con,"SELECT * FROM delivery_deployments ORDER BY id"))&&
  identical(runs,DBI::dbGetQuery(store$con,"SELECT * FROM delivery_runs ORDER BY id"))&&
  identical(triggers,DBI::dbGetQuery(store$con,"SELECT name,sql FROM sqlite_master WHERE type='trigger' ORDER BY name")))
.brohn_rptx_legacy_metadata<-legacy_original
check("All original real ref descriptors remain unchanged",.brohn_rpk_same(.brohn_rpk_ref(brohn_get_entity(store,"report",ref$id)),ref)&&
  .brohn_rpk_same(.brohn_rpk_ref(brohn_get_entity(store,"cardiac_display",saved$id)),saved))
drain()
check("Synthetic fixture closes with no queued or running jobs",DBI::dbGetQuery(store$con,"SELECT count(*) n FROM jobs WHERE status IN ('queued','running')")$n[[1L]]==0L)

},error=function(e){failure<<-conditionMessage(e);cat("ERROR",failure,"\n")})
if(!is.null(store)){brohn_close_store(store);store<-NULL}
result<-list(schema="brohn-prospective-selection-controls/1.0",status=if(is.null(failure))"passed"else"failed",
 checks=checks,failure=failure,closed=TRUE,
 scope="Synthetic metadata/admission/authority; real SQLite refs, read snapshots, freshness fences, atomic selection/queue and Retry; no workers or native scientific qualification")
writeLines(jsonlite::toJSON(result,auto_unbox=TRUE,null="null",pretty=TRUE),file.path(out,"RESULTS.json"),useBytes=TRUE)
if(!is.null(failure))quit(status=1L)
cat("COMPLETE",length(checks),"checks\n")

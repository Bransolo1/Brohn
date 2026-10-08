# Portable orchestration regression. Real SQLite intents/jobs and unchanged five
# queue wrappers; source/request/implementation discovery is synthetic and explicit.
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

for(family in c("task_display","choice_display","eda_display","cardiac_display","explicit_distributions","classic_explicit")){
  classic<-family=="classic_explicit";spy$kind<-if(classic)"explicit_distributions"else family
  ref<-source_ref(paste0("report-",family,"-fresh"));label<-function(x)paste(family,x)
  a<-create(paste0(family,"-old"),ref,classic);a<-advance(a);id<-a$dependencies[[1L]]$job_id
  check(label("original Prepare creates one owned queued prerequisite"),a$status=="waiting_for_display"&&isTRUE(a$dependencies[[1L]]$created_for_intent)&&brohn_get_job(store,id)$status=="queued")
  a<-cancel(a);retained<-headbody(a);oldrow<-jobrow(id);n<-count()
  check(label("cancellation stops the last-owned prerequisite"),brohn_get_job(store,id)$status=="cancelled")
  duplicate<-create(paste0(family,"-old"),ref,classic)
  check(label("duplicate cancelled command remains same cancelled intent"),identical(duplicate$intent_ref,a$intent_ref)&&duplicate$status=="cancelled"&&count()==n)
  check(label("polling cancelled intent refuses without resurrection"),reject(advance(a))&&count()==n&&identical(headbody(a),retained))
  fresh<-create(paste0(family,"-new"),ref,classic);fresh<-advance(fresh)
  if(!fixed){
    check(label("baseline reproduces fresh Prepare inheriting cancelled job"),fresh$status %in% c("cancelled","failed")&&fresh$dependencies[[1L]]$job_id==id&&count()==n)
    next
  }
  newid<-fresh$dependencies[[1L]]$job_id
  check(label("fresh Prepare replaces cancelled dependency in its first advance"),fresh$status=="waiting_for_display"&&newid!=id&&count()==n+1L&&isTRUE(fresh$dependencies[[1L]]$created_for_intent)&&brohn_get_job(store,newid)$attempt==0L)
  check(label("old cancelled job and intent remain exact"),identical(jobrow(id),oldrow)&&identical(headbody(a),retained))
  n<-count();duplicate<-create(paste0(family,"-new"),ref,classic);fresh<-advance(duplicate)
  check(label("duplicate command plus polling reuses replacement"),fresh$dependencies[[1L]]$job_id==newid&&count()==n&&isTRUE(fresh$dependencies[[1L]]$created_for_intent))
  running<-brohn_claim_job(store,"synthetic-sharing-test",60);stopifnot(running$id==newid)
  shared<-create(paste0(family,"-shared"),ref,classic);shared<-advance(shared)
  check(label("another intent shares running replacement without claiming creation"),shared$dependencies[[1L]]$job_id==newid&&!shared$dependencies[[1L]]$created_for_intent&&count()==n&&brohn_get_job(store,newid)$status=="running")
  fresh<-cancel(fresh)
  check(label("owner cancellation preserves another active intent's running job"),brohn_get_job(store,newid)$status=="running")
  shared<-cancel(shared)
  check(label("last shared intent cancels durably intent-owned replacement"),brohn_get_job(store,newid)$status=="cancelled")
  check(label("cancelled running attempt cannot later publish"),reject(brohn_complete_job(store,running$id,running$worker,running$token,list(synthetic=TRUE)))&&brohn_get_job(store,newid)$status=="cancelled")

  ref2<-source_ref(paste0("report-",family,"-attached"));attached<-advance(create(paste0(family,"-attached"),ref2,classic));attached_id<-attached$dependencies[[1L]]$job_id
  invisible(brohn_cancel_job(store,attached_id));n<-count();attached<-advance(attached)
  check(label("already attached external cancellation does not auto-retry"),attached$status %in% c("cancelled","failed")&&attached$dependencies[[1L]]$job_id==attached_id&&count()==n)
  attached<-advance(attached,"retry")
  check(label("explicit Retry still replaces this intent's cancelled job"),attached$status=="waiting_for_display"&&attached$dependencies[[1L]]$job_id!=attached_id&&count()==n+1L)
  attached<-cancel(attached)

  ref3<-source_ref(paste0("report-",family,"-standalone"));external<-queue_direct(ref3)
  user<-advance(create(paste0(family,"-uses-standalone"),ref3,classic));user<-cancel(user)
  check(label("cancelling an intent does not claim standalone queue ownership"),brohn_get_job(store,external$id)$status=="queued"&&!user$dependencies[[1L]]$created_for_intent)
  invisible(brohn_cancel_job(store,external$id));n<-count();again<-queue_direct(ref3)
  check(label("direct queue default still returns cancelled job without retry"),again$id==external$id&&again$status=="cancelled"&&count()==n)

  drain();ref4<-source_ref(paste0("report-",family,"-failure"));failed<-advance(create(paste0(family,"-failure"),ref4,classic));failid<-failed$dependencies[[1L]]$job_id
  leased<-brohn_claim_job(store,"synthetic-test",60);stopifnot(leased$id==failid)
  invisible(brohn_fail_job(store,failid,leased$worker,leased$token,list(message="Synthetic display failure; never a scientific worker.")))
  failedrow<-jobrow(failid);failed<-advance(failed);n<-count()
  freshfail<-advance(create(paste0(family,"-failure-new"),ref4,classic))
  check(label("fresh Prepare preserves failure and never silently retries"),freshfail$status=="failed"&&freshfail$dependencies[[1L]]$job_id==failid&&count()==n&&identical(jobrow(failid),failedrow))
  freshfail<-advance(freshfail,"retry")
  check(label("explicit Retry replaces failed display and preserves failure record"),freshfail$status=="waiting_for_display"&&freshfail$dependencies[[1L]]$job_id!=failid&&count()==n+1L&&identical(jobrow(failid),failedrow))
  freshfail<-cancel(freshfail)

  ref5<-source_ref(paste0("report-",family,"-authority"));guarded<-create(paste0(family,"-guarded"),ref5,classic);original<-headbody(guarded);n<-count()
  spy$authority<-FALSE;denied<-reject(advance(guarded));spy$authority<-TRUE
  check(label("revoked current authority refuses before queue or intent mutation"),denied&&count()==n&&identical(headbody(guarded),original))
  spy$source<-FALSE;denied<-reject(advance(guarded));spy$source<-TRUE
  check(label("changed current source refuses before queue or intent mutation"),denied&&count()==n&&identical(headbody(guarded),original))
  if(!classic){
    spy$renderer<-"changed";changedplan<-advance(guarded);spy$renderer<-"one"
    check(label("renderer drift retains original plan and requires new intent"),changedplan$status=="needs_attention"&&changedplan$preparation$reason_code=="implementation_changed"&&count()==n&&identical(headbody(changedplan)$execution_plan,original$execution_plan))
    guarded2<-create(paste0(family,"-impl-guard"),ref5,classic);original2<-headbody(guarded2)
    spy$implementation<-"changed";changedimpl<-advance(guarded2);spy$implementation<-"one"
    check(label("display implementation drift never substitutes new code"),changedimpl$status=="needs_attention"&&count()==n&&identical(headbody(changedimpl)$execution_plan,original2$execution_plan))
    # Saved successful lookup remains preferred even if latest prior job is cancelled.
    saved<-.brohn_rpk_ref(brohn_put_entity(store,spy$kind,paste0("saved-",family),list(schema="synthetic-saved-display",source_ref=ref),0L,"default"))
    spy$ready[[ref$id]]<-saved;reuse<-advance(create(paste0(family,"-reuse-saved"),ref,classic))
    check(label("saved successful result is reused without queuing"),reuse$status=="needs_attention"&&reuse$preparation$reason_code=="selection_review"&&count()==n&&.brohn_rpk_same(reuse$dependencies[[1L]]$result_ref,saved))
  }
}
# Descriptor-shaped synthetic saved metadata, observed at the actual private
# capture seam. The wrapper only records its inputs and forwards unchanged.
spy$kind<-"cardiac_display";drain()
spy$metadata_descriptors<-list()
for(n in c("plural","singular","document"))spy$metadata_descriptors[[n]]<-.brohn_rpk_object(store,
  brohn_store_object(store,bytes=charToRaw(paste("Synthetic saved metadata",n)),media_type="application/octet-stream"))
metadata_original_tx<-brohn_cardiac_display_metadata;capture_original_tx<-.brohn_rptx_capture
brohn_cardiac_display_metadata<-function(store,ref){
  m<-list(ref=ref,record=brohn_get_entity(store,ref$kind,ref$id,ref$revision),objects=list(spy$metadata_descriptors$plural))
  if(spy$metadata_mode=="plural_names_only")m$documents<-list(spy$metadata_descriptors$document)
  else m$document<-spy$metadata_descriptors$document
  if(spy$metadata_mode=="exact_singular")m$object<-spy$metadata_descriptors$singular
  m
}
.brohn_rptx_capture<-function(store,values,objects,study_id,project_id,extra_refs=list(),delivery_sources=list()){
  spy$captured_metadata_objects<-objects
  capture_original_tx(store,values,objects,study_id,project_id,extra_refs,delivery_sources=delivery_sources)
}
spy$metadata_hash_vectors<-list()
for(mode in c("no_singular_object","exact_singular","plural_names_only")){
  spy$metadata_mode<-mode
  metadata_ref<-source_ref(paste0("report-metadata-",mode))
  metadata_saved<-.brohn_rpk_ref(brohn_put_entity(store,"cardiac_display",paste0("saved-metadata-",mode),
    list(schema="synthetic-saved-display",source_ref=metadata_ref),0L,"default"))
  spy$ready[[metadata_ref$id]]<-metadata_saved
  metadata_view<-create(paste0("metadata-",mode),metadata_ref);metadata_jobs<-count()
  spy$captured_metadata_objects<-NULL
  metadata_view<-advance(metadata_view)
  check(paste(mode,"retains exact saved success and reaches the ordinary selection-review boundary"),
    metadata_view$status=="needs_attention"&&metadata_view$preparation$reason_code=="selection_review"&&
    .brohn_rpk_same(metadata_view$dependencies[[1L]]$result_ref,metadata_saved)&&count()==metadata_jobs)
  observed<-spy$captured_metadata_objects
  check(paste(mode,"passes only complete descriptors into the real capture and physical guard"),
    length(observed)>0L&&all(vapply(observed,function(o)is.list(o)&&brohn_text(o$hash,64)&&
      all(c("hash","bytes","path") %in% names(o)),logical(1))))
  expected<-if(mode=="plural_names_only")c("plural")else if(mode=="exact_singular")c("plural","singular","document")else c("plural","document")
  observed_hashes<-vapply(observed,`[[`,character(1),"hash")
  expected_hashes<-vapply(spy$metadata_descriptors[expected],`[[`,character(1),"hash")
  retain_vector<-function(x)list(values=unname(as.list(x)),names=if(is.null(names(x)))NULL else as.list(names(x)))
  spy$metadata_hash_vectors<-c(spy$metadata_hash_vectors,list(list(mode=mode,
    observed=retain_vector(observed_hashes),expected=retain_vector(expected_hashes),
    observed_set=unname(as.list(sort(unique(observed_hashes)))),
    expected_set=unname(as.list(sort(unique(expected_hashes)))))))
  writeLines(jsonlite::toJSON(spy$metadata_hash_vectors,auto_unbox=TRUE,null="null",pretty=TRUE),
    file.path(out,"METADATA-HASH-VECTORS.json"),useBytes=TRUE)
  check(paste(mode,"includes exact optional descriptors and never treats plural names as singular"),
    identical(unname(sort(unique(observed_hashes))),unname(sort(unique(expected_hashes)))))
}
brohn_cardiac_display_metadata<-metadata_original_tx;.brohn_rptx_capture<-capture_original_tx


# Appended to the existing synthetic 135-control recovery harness. The source,
# metadata, renderer and authority fixtures remain explicit synthetic spies.
spy$kind<-"cardiac_display";drain()
ref_tx<-source_ref("report-cardiac-transaction-controls")
view_tx<-advance(create("cardiac-transaction-controls",ref_tx))
plan_tx<-.brohn_rptx_snapshot(store,function().brohn_rptx_prepare(store,view_tx$intent_ref,"advance"))
cancelled_tx<-cancel(view_tx);rows_tx<-count()
e_tx<-tryCatch({brohn_store_batch(store,function().brohn_rptx_commit(store,plan_tx));NULL},error=function(e)e)
check("cardiac stale preflight cannot resurrect a cancelled current intent",inherits(e_tx,"brohn_report_preflight_stale")&&headbody(cancelled_tx)$status=="cancelled"&&count()==rows_tx)

view_tx<-advance(create("cardiac-terminal-transition",ref_tx))
plan_tx<-.brohn_rptx_snapshot(store,function().brohn_rptx_prepare(store,view_tx$intent_ref,"advance"))
running_tx<-brohn_claim_job(store,"synthetic-transition",60)
stopifnot(identical(running_tx$id,view_tx$dependencies[[1L]]$job_id))
brohn_complete_job(store,running_tx$id,running_tx$worker,running_tx$token,list(synthetic=TRUE))
before_tx<-headbody(view_tx)
e_tx<-tryCatch({brohn_store_batch(store,function().brohn_rptx_commit(store,plan_tx));NULL},error=function(e)e)
check("cardiac completion during preflight is transient and never a durable failed intent",inherits(e_tx,"brohn_report_preflight_stale")&&identical(headbody(view_tx),before_tx))

# Deliberate scheduling spy: mutate only after the real read snapshot ended.
snapshot_tx<-.brohn_rptx_snapshot
ref_tx2<-source_ref("report-cardiac-stale-public-view")
view_tx2<-advance(create("cardiac-stale-public-view",ref_tx2))
.brohn_rptx_snapshot<-function(store,fn){
  p<-snapshot_tx(store,fn)
  brohn_cancel_report_package_intent(store,view_tx2$intent_ref)
  p
}
current_tx<-advance(view_tx2)
.brohn_rptx_snapshot<-snapshot_tx
check("public cardiac continuation returns concurrent cancellation without Retry or writes",current_tx$status=="cancelled"&&current_tx$intent_ref$revision>view_tx2$intent_ref$revision)

drain();ref_a<-source_ref("report-cardiac-atomic-a");ref_b<-source_ref("report-cardiac-atomic-b")
q_tx<-make_request(ref_a,"Two synthetic prerequisites");q_tx$report_refs<-list(ref_a,ref_b)
view_atomic<-brohn_save_report_package_intent(store,"cardiac-atomic",q_tx)
before_tx<-headbody(view_atomic);rows_tx<-count();enqueue_tx<-brohn_enqueue_job;calls_tx<-0L
brohn_enqueue_job<-function(store,operation,request,idempotency_key,...){
  if(operation=="cardiac_display"){
    calls_tx<<-calls_tx+1L
    if(calls_tx==2L)stop("Synthetic second enqueue failure")
  }
  enqueue_tx(store,operation,request,idempotency_key,...)
}
refused_tx<-reject(advance(view_atomic));brohn_enqueue_job<-enqueue_tx
check("second enqueue error rolls back first job and all intent mutation",refused_tx&&calls_tx==2L&&count()==rows_tx&&identical(headbody(view_atomic),before_tx))

# Enforce the expensive callback placement, independently of elapsed timing.
assert_read_tx<-function(store){
  brohn_require(RSQLite::sqliteIsTransacting(store$con)&&DBI::dbGetQuery(store$con,"PRAGMA query_only")[[1L]][[1L]]==1L,
    "Expensive synthetic validator entered a writer or lacked its read snapshot")
  spy$read_phase_checks<-spy$read_phase_checks+1L
}
spy$read_phase_checks<-0L
requirements_tx<-.brohn_rpcc_requirements
requirements_current_tx<-.brohn_rpcc_requirements_current
request_tx<-.brohn_cdd_queue_request
.brohn_rpcc_requirements<-function(store,request){assert_read_tx(store);requirements_tx(store,request)}
.brohn_rpcc_requirements_current<-function(store,b){assert_read_tx(store);requirements_current_tx(store,b)}
.brohn_cdd_queue_request<-function(store,report_ref,display_request=NULL,implementation_ref=NULL){
  assert_read_tx(store);request_tx(store,report_ref,display_request,implementation_ref)
}
ref_phase<-source_ref("report-cardiac-phase-proof")
view_phase<-create("cardiac-phase-proof",ref_phase);view_phase<-advance(view_phase)
check("cardiac Save source proof and queued request construction occur in enforced read phase",spy$read_phase_checks>=3L&&view_phase$status=="waiting_for_display")

# Final admission and retry use a synthetic saved display, with genuine store,
# selection, job idempotency and cancellation. No model or science is invented.
drain();ref_package<-source_ref("report-cardiac-package-proof")
saved_package<-.brohn_rpk_ref(brohn_put_entity(store,"cardiac_display","synthetic-package-display",list(schema="synthetic-saved-display",source_ref=ref_package),0L,"default"))
spy$ready[[ref_package$id]]<-saved_package
resolve_tx<-.brohn_rpk_resolve_sections;selection_tx<-.brohn_rpk_selection_sources;implementation_tx<-.brohn_rpk_implementation
.brohn_rpk_resolve_sections<-function(store,request,deps){assert_read_tx(store);list(sections=list(),panel_count=0L,known_panel_count=0L)}
.brohn_rpk_selection_sources<-function(store,selection,pulse=NULL){assert_read_tx(store);list(selection=selection,objects=list(),synthetic=TRUE)}
.brohn_rpk_implementation<-function()list(profile="synthetic-package-implementation",version=1L)
view_package<-advance(create("cardiac-package-proof",ref_package))
job_package<-brohn_get_job(store,view_package$job_ref$id)
check("final cardiac selection and package admission completes with enforced read validators",view_package$status=="assembly_queued"&&job_package$operation=="report_package"&&job_package$status=="queued")
rows_tx<-count();.brohn_rpk_selection_sources<-function(store,selection,pulse=NULL)list(selection=selection,objects=list(),synthetic=TRUE)
same_job<-brohn_queue_report_package(store,view_package$selection_ref,FALSE)
check("private package request matches unchanged public queue idempotency and stored request",same_job$id==job_package$id&&count()==rows_tx&&.brohn_rpk_same(same_job$request,job_package$request))
.brohn_rpk_selection_sources<-function(store,selection,pulse=NULL){assert_read_tx(store);list(selection=selection,objects=list(),synthetic=TRUE)}
view_cancelled<-cancel(view_package);old_selection<-view_cancelled$selection_ref;old_job<-jobrow(job_package$id)
view_retry<-advance(view_cancelled,"retry")
check("existing frozen selection Retry preserves selection and prior cancelled job",view_retry$status=="assembly_queued"&&.brohn_rpk_same(view_retry$selection_ref,old_selection)&&view_retry$job_ref$id!=job_package$id&&identical(jobrow(job_package$id),old_job))
check("read-phase placement remains enforced on final admission and existing-selection Retry",spy$read_phase_checks>=7L)
.brohn_rpk_resolve_sections<-resolve_tx;.brohn_rpk_selection_sources<-selection_tx;.brohn_rpk_implementation<-implementation_tx
.brohn_rpcc_requirements<-requirements_tx;.brohn_rpcc_requirements_current<-requirements_current_tx;.brohn_cdd_queue_request<-request_tx

check("All five actual queue function bodies remain unchanged",identical(queue_bodies,lapply(queue_names,function(n)deparse(body(get(n))))))
check("Every synthetic source reference and original body remains exact",all(vapply(source_refs,function(ref).brohn_rpk_same(ref,.brohn_rpk_ref(brohn_get_entity(store,"report",ref$id)))&&brohn_get_entity(store,"report",ref$id)$body$analysis$value==17,logical(1))))
check("Only requested display and package operations were enqueued",all(DBI::dbGetQuery(store$con,"SELECT DISTINCT operation FROM jobs")$operation %in% c("task_display","choice_display","eda_display","cardiac_display","explicit_distributions","report_package")))
if(fixed)check("Actual EDA and cardiac current-source paths were exercised",spy$closure_checks>0L)
},error=function(e){failure<<-conditionMessage(e);cat("ERROR",failure,"\n")})
if(!is.null(store)){brohn_close_store(store);store<-NULL}
result<-list(schema="brohn-prepare-cancel-recovery-test/0.1",mode=args[[4L]],status=if(is.null(failure))"passed"else"failed",checks=checks,failure=failure,
  scope="synthetic source/authority/implementation fixtures; actual SQLite orchestration, queue, lease and cancellation; no workers or science",closed=TRUE)
writeLines(jsonlite::toJSON(result,auto_unbox=TRUE,null="null",pretty=TRUE),file.path(out,"RESULTS.json"),useBytes=TRUE)
if(!is.null(failure))quit(status=1L)
cat("COMPLETE",length(checks),"checks\n")

# Narrow authority for new saved-report display/export jobs. Historical reads
# use the current reader, never the original producer's expired login.
.brohn_rpa_operations <- c("report_package", "explicit_distributions")
.brohn_rpa_same <- function(a,b) identical(brohn_json(a),brohn_json(b))
.brohn_rpa_scope <- function(store,operation,project_id) {
  brohn_require(is.character(operation)&&length(operation)==1L&&operation %in% .brohn_rpa_operations&&brohn_valid_id(project_id),
    "Choose a supported saved-report operation and its exact project.")
  brohn_project(store,project_id);invisible(TRUE)
}
.brohn_rpa_profile <- function() {
  path<-Sys.getenv("BROHN_HOSTED_PROFILE","")
  if(!nzchar(path))return(NULL)
  brohn_validate_hosted_profile(.brohn_hosted_read(path))
}
.brohn_rpa_bind <- function(store,profile,context,project_id) {
  brohn_require(identical(store$workspace_id,profile$workspace_id)&&
    identical(normalizePath(store$root,winslash="/",mustWork=TRUE),profile$workspace_root)&&
    identical(project_id,profile$project_id),"This saved-report actor belongs to another workspace or project.")
  rows<-DBI::dbGetQuery(store$con,"SELECT project_id FROM entities UNION SELECT project_id FROM entity_versions")
  brohn_require(all(rows$project_id==profile$project_id),"This hosted saved-report operation requires its isolated configured project.")
  .brohn_hosted_context_valid(context,profile)
  store$hosted_profile<-profile;store$hosted_context<-context;store$hosted_participant<-FALSE
  brohn_hosted_require_session(store);brohn_hosted_require_project(store,project_id);store
}
brohn_report_package_queue_authority <- function(store,operation,project_id) {
  .brohn_rpa_scope(store,operation,project_id);profile<-.brohn_rpa_profile()
  if(is.null(profile)) {
    brohn_require(is.null(store$hosted_profile)&&is.null(store$hosted_context),
      "Hosted saved-report work cannot fall back to local mode when its profile is unavailable.")
    context<-NULL;mode<-"local";profile_id<-NULL
  }else{
    brohn_require(!is.null(store$hosted_profile)&&!isTRUE(store$hosted_participant)&&
      identical(store$hosted_profile$identity,profile$identity),"Saved-report work requires a current verified researcher session.")
    context<-store$hosted_context
    brohn_fields(context,c("schema","issuer","subject","profile_identity","started","expires"),label="Verified saved-report actor")
    .brohn_rpa_bind(store,profile,context,project_id);mode<-"hosted";profile_id<-profile$id
  }
  list(schema="brohn-report-package-authority/0.1",mode=mode,workspace_id=store$workspace_id,
    project_id=project_id,operation=operation,profile_id=profile_id,context=context)
}
brohn_report_package_job_authorize <- function(store,job,stage=c("execute","publish")) {
  stage<-match.arg(stage);r<-job$request;a<-r$authority
  .brohn_rpa_scope(store,job$operation,r$project_id)
  brohn_fields(a,c("schema","mode","workspace_id","project_id","operation","profile_id","context"),label="Queued saved-report authority")
  brohn_require(nchar(brohn_json(a),type="bytes")<=8192L&&identical(a$schema,"brohn-report-package-authority/0.1")&&
    a$mode %in% c("local","hosted")&&identical(a$operation,job$operation)&&identical(a$workspace_id,store$workspace_id)&&
    identical(a$project_id,r$project_id),"This job does not retain its exact original saved-report authorization.")
  profile<-.brohn_rpa_profile()
  if(a$mode=="local") {
    brohn_require(is.null(profile)&&is.null(store$hosted_profile)&&is.null(store$hosted_context)&&is.null(a$profile_id)&&is.null(a$context),
      "Previously local saved-report work cannot run after hosted policy is enabled or with substituted authority.")
    return(store)
  }
  brohn_require(!is.null(profile)&&identical(a$profile_id,profile$id),"The queued hosted profile was removed or replaced. Sign in and explicitly retry.")
  brohn_fields(a$context,c("schema","issuer","subject","profile_identity","started","expires"),label="Original verified saved-report actor")
  .brohn_rpa_bind(store,profile,a$context,r$project_id)
}
brohn_report_package_job_fence <- function(store,job) {
  .brohn_publication_job(store,job)
  brohn_report_package_job_authorize(store,job,"publish")
}
.brohn_rpa_retry_request <- function(store,job) {
  current<-brohn_get_job(store,job$id)
  brohn_require(!is.null(current)&&current$status %in% c("failed","cancelled")&&identical(current$operation,job$operation)&&
    .brohn_rpa_same(current$request,job$request),"Only a known failed or cancelled saved-report job can receive renewed authority.")
  r<-current$request;r$authority<-brohn_report_package_queue_authority(store,current$operation,r$project_id);r
}

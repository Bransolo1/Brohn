# Scoped background authorization for new clock operations. No credentials or
# protected configuration paths are written into a queue authority envelope.
.brohn_clock_authority_operations <- c("preview_clock_alignment","clock_event_page","save_clock_map","clock_window","clock_plot")
.brohn_ca_profile <- function() {
  path<-Sys.getenv("BROHN_HOSTED_PROFILE","")
  if(!nzchar(path))return(NULL)
  # Deliberately reread the protected profile instead of the session cache.
  # A policy/grant edit must invalidate work before the background commit.
  brohn_validate_hosted_profile(.brohn_hosted_read(path))
}
.brohn_ca_scope <- function(store,operation,project_id) {
  brohn_require(brohn_text(operation,100)&&operation %in% .brohn_clock_authority_operations&&brohn_valid_id(project_id),
    "Choose a supported clock operation and its exact project.")
  brohn_project(store,project_id);invisible(TRUE)
}
.brohn_ca_bind <- function(store,profile,context,project_id) {
  brohn_require(identical(store$workspace_id,profile$workspace_id)&&identical(normalizePath(store$root,winslash="/",mustWork=TRUE),profile$workspace_root)&&
    identical(project_id,profile$project_id),"The queued clock actor belongs to another workspace or project.")
  rows<-DBI::dbGetQuery(store$con,"SELECT project_id FROM entities UNION SELECT project_id FROM entity_versions")
  brohn_require(all(rows$project_id==profile$project_id),"This hosted clock operation requires its isolated configured project.")
  .brohn_hosted_context_valid(context,profile)
  # Bind current authorization without creating tables or changing the store.
  store$hosted_profile<-profile;store$hosted_context<-context;store$hosted_participant<-FALSE
  brohn_hosted_require_session(store);brohn_hosted_require_project(store,project_id);store
}
brohn_clock_queue_authority <- function(store,operation,project_id) {
  .brohn_ca_scope(store,operation,project_id);profile<-.brohn_ca_profile()
  if(is.null(profile)) {
    brohn_require(is.null(store$hosted_profile)&&is.null(store$hosted_context),"Hosted clock work cannot fall back to local mode when its profile is unavailable.")
    context<-NULL;mode<-"local";profile_id<-NULL
  }else {
    brohn_require(!is.null(store$hosted_profile)&&!isTRUE(store$hosted_participant)&&
      identical(store$hosted_profile$identity,profile$identity),"Clock work requires a current verified researcher session for this configured hosted profile.")
    context<-store$hosted_context
    brohn_fields(context,c("schema","issuer","subject","profile_identity","started","expires"),label="Verified queue actor")
    store<-.brohn_ca_bind(store,profile,context,project_id)
    mode<-"hosted";profile_id<-profile$id
  }
  list(schema="brohn-clock-job-authority/0.1",mode=mode,workspace_id=store$workspace_id,project_id=project_id,
    operation=operation,profile_id=profile_id,context=context)
}
brohn_clock_job_authorize <- function(store,job,stage=c("execute","publish")) {
  stage<-match.arg(stage);r<-job$request;a<-r$authority
  .brohn_ca_scope(store,job$operation,r$project_id)
  brohn_fields(a,c("schema","mode","workspace_id","project_id","operation","profile_id","context"),label="Queued clock authority")
  brohn_require(nchar(brohn_json(a),type="bytes")<=8192L&&identical(a$schema,"brohn-clock-job-authority/0.1")&&
    a$mode %in% c("local","hosted")&&identical(a$operation,job$operation)&&identical(a$workspace_id,store$workspace_id)&&
    identical(a$project_id,r$project_id),"The clock job does not retain its exact original authorization scope.")
  profile<-.brohn_ca_profile()
  if(a$mode=="local") {
    brohn_require(is.null(profile)&&is.null(store$hosted_profile)&&is.null(store$hosted_context)&&is.null(a$profile_id)&&is.null(a$context),
      "Previously local clock work cannot run after hosted policy is enabled or with substituted authority.")
    return(store)
  }
  brohn_require(!is.null(profile)&&identical(a$profile_id,profile$id),"The queued hosted profile was removed or replaced; sign in and explicitly retry.")
  brohn_fields(a$context,c("schema","issuer","subject","profile_identity","started","expires"),label="Original verified clock actor")
  .brohn_ca_bind(store,profile,a$context,r$project_id)
}
brohn_clock_job_fence <- function(store,job) {
  .brohn_publication_job(store,job)
  brohn_clock_job_authorize(store,job,"publish")
}
brohn_clock_retry_request <- function(store,job) {
  current<-brohn_get_job(store,job$id)
  brohn_require(!is.null(current)&&current$status %in% c("failed","cancelled")&&identical(current$operation,job$operation)&&
    .brohn_cm_same(current$request,job$request),"Only a known failed or cancelled clock operation can receive renewed authority. Recover uncertain work by its original job identity.")
  r<-current$request;r$authority<-brohn_clock_queue_authority(store,current$operation,r$project_id)
  r
}

brohn_guard_hosted_http <- function(session,store) {
  if(is.null(store$hosted_profile))return(invisible(NULL))
  # Shiny's sessionHandler delegates file/upload/download/dataobj requests to
  # this per-session method. Cached dataobj filters bypass store operations.
  # Guard before dispatch, not after a callback has read data or upload bytes.
  brohn_require(is.environment(session)&&exists("handleRequest",session,inherits=FALSE)&&
    is.function(session$handleRequest)&&identical(names(formals(session$handleRequest)),"req"),
    "This Shiny version does not support the required hosted HTTP session guard.")
  if(isTRUE(session$userData$brohn_hosted_http_guard))return(invisible(NULL))
  original<-session$handleRequest
  guarded<-function(req) {
    valid<-tryCatch({brohn_hosted_require_session(store);TRUE},error=function(e)FALSE)
    if(!valid)return(structure(list(status=403L,content_type="text/plain; charset=UTF-8",
      content="Researcher access ended. Sign in again or contact the workspace operator.",
      headers=list("Cache-Control"="no-store","X-Content-Type-Options"="nosniff")),class="httpResponse"))
    original(req)
  }
  # R6 locks existing method bindings. Replace only this instance's verified
  # method, restore its lock, and leave the Shiny generator/namespace unchanged.
  locked<-bindingIsLocked("handleRequest",session)
  if(locked)unlockBinding("handleRequest",session)
  on.exit(if(locked)lockBinding("handleRequest",session),add=TRUE)
  assign("handleRequest",guarded,envir=session)
  session$userData$brohn_hosted_http_guard<-TRUE
  invisible(NULL)
}
brohn_install_hosted_session <- function(session,store) {
  if(is.null(store$hosted_profile))return(invisible(NULL))
  brohn_guard_hosted_http(session,store)
  active<-TRUE;session$onSessionEnded(function()active<<-FALSE)
  check<-function() {
    if(!active)return(invisible(NULL))
    valid<-tryCatch({brohn_hosted_require_session(store);TRUE},error=function(e)FALSE)
    if(!valid){active<<-FALSE;session$close();return(invisible(NULL))}
    later::later(check,2)
  }
  later::later(check,2)
  invisible(NULL)
}
brohn_hosted_profile_ui <- function(store) {
  p<-store$hosted_profile;if(is.null(p))return(NULL)
  shiny::div(class="brohn-alert",role="status",shiny::strong("Team workspace"),
    shiny::p("Researcher access uses your organization's sign-in. This workspace is isolated for one team."),
    shiny::p(sprintf("Sign in again after %s minutes. Access may end earlier if revoked by the workspace operator.",format(p$session_seconds/60,trim=TRUE))),
    shiny::p("Folder imports, host backups and restored-workspace activation require the workspace operator."),
    shiny::tags$a(href="/oauth2/sign_out",class="btn btn-outline-secondary","Sign out"))
}
brohn_hosted_release_ui <- function(store,release) {
  if(is.null(store$hosted_profile))return(NULL)
  p<-tryCatch(brohn_hosted_release_policy(store,release$id),error=function(e)NULL)
  if(is.null(p))return(shiny::p(class="brohn-muted","This older local release cannot be used for hosted recruitment. Publish a new release."))
  date<-function(t)format(as.POSIXct(t,origin="1970-01-01",tz="UTC"),"%d %b %Y %H:%M UTC",tz="UTC")
  shiny::div(shiny::p(paste("New participants can join until",date(p$enrollment_expires[[1L]]),". Admitted sessions retain their separate upload window.")),
    shiny::p(paste("Shared study material access ends",date(p$resource_expires[[1L]]),". Material links contain a release capability; they are not individual participant authentication.")),
    shiny::p("Revoking the hosted link also stops its shared study materials. An admitted participant may still upload saved responses until their own deadline, but may be unable to continue presentations that need those materials."),
    if(is.na(p$revoked[[1L]]))brohn_command("Revoke hosted link","brohn_hosted_revoke_release",list(id=release$id),class="btn btn-outline-secondary")else shiny::p("Hosted link and shared materials revoked. Original responses and admitted upload deadlines are preserved."))
}
brohn_hosted_run_ui <- function(store,run) {
  if(is.null(store$hosted_profile))return(NULL)
  row<-DBI::dbGetQuery(store$con,"SELECT upload_expires,revoked FROM hosted_run_policy WHERE run_id=?",params=list(run$id))
  if(!nrow(row))return(shiny::span("Local session; no hosted capability"))
  until<-format(as.POSIXct(row$upload_expires[[1L]],origin="1970-01-01",tz="UTC"),"%d %b %Y %H:%M UTC",tz="UTC")
  shiny::div(shiny::p(paste("Upload access until",until)),
    if(is.na(row$revoked[[1L]]))brohn_command("Revoke session access","brohn_hosted_revoke_run",list(id=run$id))else shiny::p("Session access revoked; received data retained"))
}
.brohn_hosted_control_target <- function(store,kind,id,study_id) {
  brohn_hosted_require_session(store)
  .brohn_hosted_require(kind %in% c("release","run")&&brohn_valid_id(id)&&brohn_valid_id(study_id),"Open this study before changing its hosted access.")
  release_id<-id
  if(kind=="run") {
    row<-DBI::dbGetQuery(store$con,"SELECT deployment_id FROM delivery_runs WHERE id=?",params=list(id))
    .brohn_hosted_require(nrow(row)==1L,"This session was not found.");release_id<-row$deployment_id[[1L]]
  }
  release<-DBI::dbGetQuery(store$con,"SELECT id,study_id,project_id,design_hash FROM delivery_deployments WHERE id=?",params=list(release_id))
  .brohn_hosted_require(nrow(release)==1L&&identical(release$study_id[[1L]],study_id),"The hosted capability belongs to another study.")
  brohn_hosted_require_project(store,release$project_id[[1L]])
  table<-if(kind=="release")"hosted_release_policy"else"hosted_run_policy";column<-if(kind=="release")"deployment_id"else"run_id"
  policy<-DBI::dbGetQuery(store$con,paste0("SELECT * FROM ",table," WHERE ",column,"=?"),params=list(id))
  .brohn_hosted_require(nrow(policy)==1L&&is.na(policy$revoked[[1L]]),"This access is unavailable or has already been revoked.")
  brohn_hosted_release_policy(store,release_id)
  policy$revoked<-NULL
  list(kind=kind,id=id,study_id=study_id,hash=brohn_hash(list(release=as.list(release[1L,]),policy=as.list(policy[1L,]))))
}
brohn_install_hosted_controls <- function(input,output,session,store,state,attempt,message,refresh) {
  if(is.null(store$hosted_profile))return(invisible(NULL))
  pending<-shiny::reactiveVal(NULL)
  open<-function(value,kind)attempt(function() {
    .brohn_hosted_require(is.list(value)&&identical(names(value),"id"),"Choose one exact hosted capability.")
    target<-.brohn_hosted_control_target(store,kind,value$id,state$study_id);pending(target)
    shiny::showModal(shiny::modalDialog(title=if(kind=="release")"Revoke this hosted study link?"else"Revoke this session's access?",easyClose=FALSE,
      if(kind=="release")shiny::p("This stops new entry and shared study material access. Already admitted sessions may still upload saved responses until their own deadline. A presentation that needs those materials may no longer continue.")else
        shiny::p("This stops further uploads and server resume for this session. Responses and recording bytes already received remain unchanged; unsent data remain in the participant's browser."),
      shiny::p("This capability cannot be reopened. Publish a new study link or start a new admitted session when appropriate."),
      footer=shiny::tagList(shiny::modalButton("Keep access"),shiny::actionButton("brohn_hosted_confirm_revoke","Revoke access",class="btn-primary"))))
  })
  shiny::observeEvent(input$brohn_hosted_revoke_release,open(input$brohn_hosted_revoke_release,"release"),ignoreInit=TRUE)
  shiny::observeEvent(input$brohn_hosted_revoke_run,open(input$brohn_hosted_revoke_run,"run"),ignoreInit=TRUE)
  shiny::observeEvent(input$brohn_hosted_confirm_revoke,attempt(function() {
    target<-pending();.brohn_hosted_require(!is.null(target)&&identical(state$study_id,target$study_id),"Review this study's access again before revoking it.")
    current<-.brohn_hosted_control_target(store,target$kind,target$id,target$study_id)
    .brohn_hosted_require(identical(current$hash,target$hash),"The access policy changed. Review it again before revoking.")
    brohn_hosted_revoke(store,target$kind,target$id);pending(NULL);shiny::removeModal();message("Hosted access revoked. Original research data have been retained.");refresh()
  }),ignoreInit=TRUE)
  invisible(NULL)
}

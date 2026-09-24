# Wired storage and participant HTTP-handler checks. The identities here are
# fixtures; actual OIDC/proxy/browser evidence belongs to the separate journey.
source("R/platform-load.R",encoding="UTF-8");brohn_load(ui=FALSE)
local({
  args<-commandArgs(trailingOnly=TRUE)
  folder<-if(length(args))args[[1L]]else tempfile("brohn-hosted-hooks-")
  stopifnot(startsWith(basename(folder),"brohn-hosted-hooks-"),!dir.exists(folder))
  dir.create(folder,recursive=TRUE);folder<-normalizePath(folder,winslash="/",mustWork=TRUE)
  store<-brohn_open_store(file.path(folder,"workspace"));on.exit(brohn_close_store(store),add=TRUE)
  brohn_initialise_library(store)
  checks<-character();check<-function(label,ok){if(!isTRUE(ok))stop(label);checks<<-c(checks,label);cat("PASS",label,"\n")}
  rejected<-function(expr,code=NULL){e<-tryCatch({force(expr);NULL},error=identity);inherits(e,"error")&&(is.null(code)||identical(e$code,code))}
  secret_file<-file.path(folder,"edge.secret");writeChar(brohn_token(),secret_file,eos=NULL,useBytes=TRUE)
  rev_file<-file.path(folder,"revocations.json")
  brohn_write_json_file(list(schema="brohn-hosted-revocations/1.0",subjects=list(),not_before=0),rev_file)
  profile<-brohn_validate_hosted_profile(list(schema="brohn-hosted-profile/1.0",id="original-hooks",mode="local_oidc_fixture",
    workspace_root=store$root,workspace_id=store$workspace_id,project_id="default",researcher_origin="https://localhost:3991",
    participant_origin="https://localhost:3992",issuer="http://127.0.0.1:3993/realms/brohn",allowed_groups=list("researchers"),
    edge_secret_file=secret_file,revocations_file=rev_file,session_seconds=600,enrollment_seconds=60,upload_seconds=120,
    resource_seconds=120,researcher_port=3994,participant_port=3995,oauth_port=3996))
  ctx<-brohn_hosted_context(list(HTTP_HOST="localhost:3991",HTTP_X_FORWARDED_PROTO="https",HTTP_X_BROHN_EDGE=profile$edge_secret,
    HTTP_X_FORWARDED_USER="original-verified-subject",HTTP_X_FORWARDED_GROUPS="researchers"),profile)
  researcher<-brohn_hosted_bind_store(store,profile,ctx)
  participant<-brohn_hosted_bind_store(store,profile,participant=TRUE)
  study<-brohn_create_study(researcher,"Original hosted policy fixture","survey")
  d<-study$body;d$questions<-list(brohn_question("Original preference","rating","end","q-original"))
  study<-brohn_save_study(researcher,d,study$revision)
  release<-brohn_publish(researcher,study$id,"sample")
  app<-brohn_delivery_app(participant)
  call<-function(path,payload=NULL,bearer=NULL,edge=profile$edge_secret,host="localhost:3992",origin=profile$participant_origin) {
    bytes<-if(is.null(payload))raw()else charToRaw(.brohn_store_json(payload))
    req<-list(PATH_INFO=path,REQUEST_METHOD=if(is.null(payload))"GET"else"POST",HTTP_HOST=host,HTTP_ORIGIN=origin,
      HTTP_X_FORWARDED_PROTO="https",HTTP_X_BROHN_EDGE=edge,REMOTE_ADDR="127.0.0.1",
      CONTENT_TYPE="application/json",CONTENT_LENGTH=as.character(length(bytes)),rook.input=list(read=function(n=-1L)bytes))
    if(!is.null(bearer))req$HTTP_AUTHORIZATION<-paste("Bearer",bearer)
    if(identical(path,paste0("/api/start/",release$token)))req$HTTP_X_BROHN_PARTICIPANT_RUNTIME<-release$participant_runtime$manifest_hash
    result<-app$call(req)
    if(is.character(result$body)&&grepl("^application/json",result$headers[["Content-Type"]]))result$value<-brohn_parse(result$body)
    result
  }
  entry<-paste0("/api/entry/",release$token);start_path<-paste0("/api/start/",release$token)
  request<-list(consented=TRUE,client_id="original-client",operation_id="original-start")
  check("Publish atomically creates a hosted release policy",nrow(brohn_hosted_release_policy(researcher,release$id))==1L)
  check("Trusted participant entry works through the wired HTTP handler",call(entry)$status==200L)
  check("Forged edge proof is rejected before study entry",call(entry,edge=paste(rep("0",64),collapse=""))$status==403L)
  check("Researcher origin cannot reach participant entry",call(entry,origin=profile$researcher_origin)$status==403L)
  check("Public participant health remains behind edge routing and origin guard",call("/api/health",edge=NULL)$status==403L)
  started<-call(start_path,request);check("Admission creates an actual run and scoped policy",started$status==200L)
  run<-started$value;run_id<-run$run_id;bearer<-run$access_token
  check("Admitted session policy binds exact release",identical(DBI::dbGetQuery(store$con,"SELECT deployment_id FROM hosted_run_policy WHERE run_id=?",params=list(run_id))$deployment_id[[1L]],release$id))
  status_path<-paste0("/api/session_status/",run_id)
  check("Existing bearer authenticates session status",call(status_path,bearer=bearer)$status==200L&&call(status_path)$status==401L)
  DBI::dbExecute(store$con,"UPDATE hosted_release_policy SET enrollment_expires=? WHERE deployment_id=?",params=list(as.numeric(Sys.time())-1,release$id))
  repeat_start<-call(start_path,request)
  new_request<-request;new_request$client_id<-"late-client";new_request$operation_id<-"late-start"
  check("Enrollment expiry preserves exact prior start retry",repeat_start$status==200L&&identical(repeat_start$value$run_id,run_id)&&identical(repeat_start$value$access_token,bearer))
  check("Enrollment expiry rejects a new participant without creating rows",call(start_path,new_request)$status==403L&&DBI::dbGetQuery(store$con,"SELECT count(*) n FROM delivery_runs")$n[[1L]]==1L)
  check("Existing authenticated run survives enrollment expiry",call(status_path,bearer=bearer)$status==200L)
  original_run<-DBI::dbGetQuery(store$con,"SELECT * FROM delivery_runs WHERE id=?",params=list(run_id))
  original_receipts<-DBI::dbGetQuery(store$con,"SELECT * FROM delivery_receipts")
  DBI::dbExecute(store$con,"UPDATE hosted_run_policy SET upload_expires=? WHERE run_id=?",params=list(as.numeric(Sys.time())-1,run_id))
  check("Expired admitted uploads reject status and start retry",identical(call(status_path,bearer=bearer)$value$error$code,"upload_expired")&&identical(call(start_path,request)$value$error$code,"upload_expired"))
  check("Expiry does not fabricate participant endings or receipts",identical(original_run,DBI::dbGetQuery(store$con,"SELECT * FROM delivery_runs WHERE id=?",params=list(run_id)))&&identical(original_receipts,DBI::dbGetQuery(store$con,"SELECT * FROM delivery_receipts")))
  DBI::dbExecute(store$con,"UPDATE hosted_run_policy SET upload_expires=? WHERE run_id=?",params=list(as.numeric(Sys.time())+120,run_id))
  brohn_hosted_revoke(researcher,"release",release$id)
  check("Revoked release blocks entry but retains admitted access",identical(call(entry)$value$error$code,"release_revoked")&&call(status_path,bearer=bearer)$status==200L)
  brohn_hosted_revoke(researcher,"run",run_id)
  check("Run revocation rejects authenticated access without modifying original data",identical(call(status_path,bearer=bearer)$value$error$code,"run_revoked")&&identical(original_run,DBI::dbGetQuery(store$con,"SELECT * FROM delivery_runs WHERE id=?",params=list(run_id))))
  local_release<-brohn_publish(store,study$id,"sample")
  check("Existing local release does not inherit hosted recruitment authority",identical(call(paste0("/api/entry/",local_release$token))$value$error$code,"release_access"))
  foreign<-brohn_put_entity(store,"fixture","foreign",list(value="foreign"),project_id="other")
  check("Foreign project reads and writes rejected after binding",rejected(brohn_get_entity(researcher,"fixture","foreign"),"foreign_project")&&rejected(brohn_put_entity(researcher,"fixture","new",list(),project_id="other"),"foreign_project"))
  check("Default catalog only lists the isolated project",length(brohn_list_entities(researcher,"fixture"))==0L&&rejected(brohn_list_entities(researcher,"fixture",project_id="other"),"foreign_project"))
  check("Hosted callers cannot take over a foreign head",rejected(brohn_put_entity(researcher,"fixture","foreign",list(value="takeover"),1L),"foreign_project"))
  brohn_put_entity(store,"fixture","foreign",list(value="moved by operator"),1L)
  check("Historical foreign revisions cannot be read via history",rejected(brohn_entity_history(researcher,"fixture","foreign"),"foreign_project")&&rejected(brohn_get_entity(researcher,"fixture","foreign",1L),"foreign_project"))
  check("Rebinding refuses historical mixed-project workspace",rejected(brohn_hosted_bind_store(store,profile,ctx),"workspace"))
  check("Direct backup job enqueue cannot bypass operator-only UI",rejected(brohn_enqueue_job(researcher,"backup_workspace",list(destination=file.path(folder,"blocked")),"blocked-backup"),"operator_required")&&!dir.exists(file.path(folder,"blocked")))
  check("Folder import and resume rejected at domain boundary",rejected(brohn_import_legacy(researcher,"C:/not-a-source"),"operator_required")&&rejected(brohn_resume_workspace(researcher),"operator_required"))
  logs<-DBI::dbGetQuery(store$con,"SELECT detail_json FROM audit_log WHERE action='entity.saved' AND target=?",params=list(paste0("study/",study$id)))
  actors<-lapply(logs$detail_json,function(x)brohn_parse(x)$actor)
  check("Real study writes retain stable actor without edge credentials",length(actors)>=2L&&all(vapply(actors,function(x)identical(x$subject,ctx$subject)&&identical(x$issuer,profile$issuer),logical(1)))&&!any(grepl(profile$edge_secret,logs$detail_json,fixed=TRUE)))
  expired<-researcher;expired$hosted_context$expires<-as.numeric(Sys.time())-1
  check("Expired researcher reads and writes rejected by shared store",rejected(brohn_get_entity(expired,"study",study$id),"session_expired")&&rejected(brohn_put_entity(expired,"fixture","expired",list()),"session_expired"))
  check("Trusted native operator access remains independent of browser lease",!is.null(brohn_get_entity(store,"study",study$id)))
  brohn_write_json_file(list(status="passed",checks=as.list(checks),scope="Wired HTTP-handler and durable-store fixture; not OIDC browser qualification."),file.path(folder,"results.json"))
  cat("PASS",length(checks),"hosted integration checks\n")
})

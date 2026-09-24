args<-commandArgs(trailingOnly=TRUE);mode<-args[[1L]];folder<-normalizePath(args[[2L]],winslash="/",mustWork=TRUE)
stopifnot(startsWith(basename(folder),"brohn-hosted-browser-"))
source("R/platform-load.R",encoding="UTF-8");brohn_load(ui=TRUE)
if(!exists("brohn_hosted_profile",mode="function"))source("R/platform-hosted-profile.R",encoding="UTF-8")
if(!exists("brohn_install_hosted_session",mode="function"))source("R/platform-hosted-profile-views.R",encoding="UTF-8")
profile_path<-file.path(folder,"profile.json")
if(mode=="setup")local({
  stopifnot(!file.exists(profile_path));store<-brohn_open_store(file.path(folder,"workspace"));on.exit(brohn_close_store(store),add=TRUE);brohn_initialise_library(store)
  profile<-list(schema="brohn-hosted-profile/1.0",id="original-local-oidc",mode="local_oidc_fixture",workspace_root=store$root,workspace_id=store$workspace_id,project_id="default",
    researcher_origin="https://localhost:3911",participant_origin="https://localhost:3912",issuer="http://127.0.0.1:3913/realms/brohn",allowed_groups=list("researchers"),
    edge_secret_file=file.path(folder,"edge.secret"),revocations_file=file.path(folder,"revocations.json"),session_seconds=1200L,enrollment_seconds=900L,upload_seconds=900L,resource_seconds=900L,researcher_port=3914L,participant_port=3915L,oauth_port=3916L)
  brohn_write_json_file(profile,profile_path)
  brohn_hosted_write_proxy_config(brohn_validate_hosted_profile(profile),folder,"brohn-fixture",file.path(folder,"client.secret"),file.path(folder,"cookie.secret"))
  other<-brohn_open_store(file.path(folder,"other-workspace"));on.exit(brohn_close_store(other),add=TRUE);brohn_initialise_library(other)
  foreign<-brohn_create_study(other,"Synthetic other team private design","survey")
  brohn_write_json_file(list(study_id=foreign$id,workspace_id=other$workspace_id,body_hash=brohn_hash(foreign$body)),file.path(folder,"foreign.json"))
}) else if(mode %in% c("researcher","participant")) {
  Sys.setenv(BROHN_HOSTED_PROFILE=profile_path,BROHN_WORKSPACE=file.path(folder,"workspace"),BROHN_APP_MODE="platform",BROHN_PARTICIPANT_PORT="3915")
  p<-brohn_hosted_profile()
  if(mode=="researcher") {
    stop_owned<-function()if(file.exists(file.path(folder,"stop.researcher")))shiny::stopApp()else later::later(stop_owned,.2)
    later::later(stop_owned,.2);shiny::runApp(".",host="127.0.0.1",port=p$researcher_port,launch.browser=FALSE)
  } else {
    store<-brohn_open_store(p$workspace_root);store<-brohn_hosted_bind_store(store,p,participant=TRUE)
    server<-httpuv::startServer("127.0.0.1",p$participant_port,brohn_delivery_app(store))
    while(!file.exists(file.path(folder,"stop.participant")))httpuv::service(50)
    httpuv::stopServer(server);brohn_close_store(store)
  }
} else local({
  store<-brohn_open_store(file.path(folder,"workspace"));on.exit(brohn_close_store(store),add=TRUE)
  if(mode=="inspect") {
    runs<-brohn_runs(store)
    detail<-lapply(runs,function(run){capture<-brohn_capture(store,run_id=run$id);list(run=run,events=brohn_run_events(store,run$id),capture=capture,chunks=if(is.null(capture))list()else brohn_rows(DBI::dbGetQuery(store$con,"SELECT sequence,object_hash,byte_count FROM camera_chunks WHERE capture_id=? ORDER BY sequence",params=list(capture$id))))})
    brohn_write_json_file(list(studies=brohn_list_entities(store,"study"),releases=brohn_deployments(store),runs=runs,sessions=detail,reports=brohn_list_entities(store,"report"),collections=brohn_list_entities(store,"collection"),jobs=brohn_list_jobs(store),audit=brohn_rows(DBI::dbGetQuery(store$con,"SELECT * FROM audit_log"))),file.path(folder,"snapshot.json"))
  } else if(mode=="analyse") {
    job<-brohn_claim_job(store,"hosted-browser-worker",90);stopifnot(!is.null(job),job$operation=="analyse_run")
    brohn_process_job(store,job,timeout_seconds=180);result<-brohn_get_job(store,job$id);stopifnot(result$status=="succeeded")
    brohn_write_json_file(result,file.path(folder,"worker-result.json"))
  } else if(mode=="backup") {
    backup<-brohn_backup_workspace(store,file.path(folder,"backup"));brohn_restore_workspace(backup$path,file.path(folder,"restored"))
    restored<-brohn_open_store(file.path(folder,"restored"));on.exit(brohn_close_store(restored),add=TRUE)
    p<-brohn_validate_hosted_profile(brohn_read_json_file(profile_path))
    rejected<-inherits(try(brohn_hosted_bind_store(restored,p,participant=TRUE),silent=TRUE),"try-error")
    original<-brohn_deployments(store);copy<-brohn_deployments(restored)
    stopifnot(rejected,brohn_workspace_execution_status(restored)$paused,all(vapply(copy,function(x)x$status=="closed",logical(1))),all(vapply(seq_along(original),function(i)original[[i]]$token!=copy[[i]]$token,logical(1))))
    brohn_write_json_file(list(passed=TRUE,old_profile_refused=rejected,paused=TRUE,closed_and_rotated=length(copy),workspace_changed=store$workspace_id!=restored$workspace_id),file.path(folder,"restore-result.json"))
  } else if(mode=="short-policy") {
    p<-brohn_read_json_file(profile_path);p$session_seconds<-30L;p$upload_seconds<-30L;p$resource_seconds<-30L
    brohn_write_json_file(p,profile_path);target<-file.path(folder,"edge-short");dir.create(target)
    generated<-brohn_hosted_write_proxy_config(brohn_validate_hosted_profile(p),target,"brohn-fixture",file.path(folder,"client.secret"),file.path(folder,"cookie.secret"))
    for(name in c("oauth2-proxy.cfg","Caddyfile")){file.copy(file.path(folder,name),file.path(folder,paste0(name,".original")));file.copy(file.path(target,name),file.path(folder,name),overwrite=TRUE)}
  } else stop("Unknown hosted fixture mode")
})

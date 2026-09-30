args<-commandArgs(TRUE);stopifnot(length(args)==3L)
checkout<-normalizePath(args[[1L]],winslash="/",mustWork=TRUE);source<-normalizePath(args[[2L]],winslash="/",mustWork=TRUE);out<-normalizePath(args[[3L]],winslash="/",mustWork=TRUE)
setwd(checkout);source("R/platform-load.R",encoding="UTF-8");brohn_load(ui=FALSE)
local({
  checks<-list();passed<-FALSE;failure<-NULL
  check<-function(n,x){if(!isTRUE(x))stop(n,call.=FALSE);checks[[length(checks)+1L]]<<-n;cat("PASS",n,"\n")}
  reject<-function(f)inherits(tryCatch({f();NULL},error=function(e)e),"error")
  store<-brohn_open_store(file.path(out,"workspace"));handles<-list()
  on.exit({for(h in handles)brohn_release_task_display_resources(h);for(j in brohn_list_jobs(store,limit=100L))if(j$status %in% c("queued","running"))brohn_cancel_job(store,j$id)
    Sys.unsetenv("BROHN_HOSTED_PROFILE");brohn_write_json_file(list(passed=passed,checks=checks,failure=failure,scope="Copied original task-display store; real Windows native read guards and SQLite authority transitions. Trusted-edge fixtures are local-only, not public hosting or real OIDC. No original corpus mutation."),file.path(out,"results.json"));brohn_close_store(store)},add=TRUE)
  tryCatch({
    original<-brohn_read_json_file(file.path(source,"profile-01-import-report.json"));native<-brohn_read_json_file(file.path(source,"profile-01-native-report.json"));project<-original$report$ref$project_id
    for(item in list(original,native)){meta<-.brohn_rpk_source_metadata(store,list(item$report$ref),task_refs=list(item$task_display$ref),task_enabled=TRUE);for(object in meta$objects)Sys.chmod(object$path,"0666")}
    o<-brohn_open_task_display_resources(store,original$task_display$ref,project);handles<-c(handles,list(o$handle))
    n<-brohn_open_task_display_resources(store,native$task_display$ref,project);handles<-c(handles,list(n$handle))
    check("different currently loaded implementation reads exact historical artifact",!identical(brohn_hash(o$record$body$implementation),brohn_hash(brohn_task_display_implementation())))
    objects<-o$handle$source_handle$metadata$objects
    check("every original and prepared object denies concurrent writers",all(vapply(objects,function(a)suppressWarnings(reject(function(){con<-file(a$path,"r+b");close(con)})),logical(1))))
    oldread<-brohn_read_json_file;oldpath<-brohn_object_path
    brohn_read_json_file<<-function(...)stop("full JSON forbidden in current")
    brohn_object_path<<-function(store,hash,verify=TRUE){if(isTRUE(verify))stop("rehash forbidden in current");oldpath(store,hash,FALSE)}
    tryCatch(check("current reader performs no original decode or full hash",is.list(brohn_task_display_resources_current(store,o$handle))),finally={brohn_read_json_file<<-oldread;brohn_object_path<<-oldpath})
    r<-brohn_get_entity(store,"report",original$report$ref$id);changed<-r$body;changed$title<-"Newer metadata revision"
    brohn_put_entity(store,"report",r$id,changed,r$revision,r$project_id)
    check("new source head preserves exact historical saved display",is.list(brohn_task_display_resources_current(store,o$handle)))
    wrong<-original$task_display$ref;wrong$body_hash<-paste(rep("0",64),collapse="")
    check("wrong pinned artifact identity refuses",reject(function()brohn_open_task_display_resources(store,wrong,project)))
    d<-brohn_get_entity(store,"dataset",original$report$saved_body$dataset_id);prior<-d$body;d$body$archived<-TRUE
    archived<-brohn_put_entity(store,"dataset",d$id,d$body,d$revision,d$project_id)
    check("archived source invalidates an already-open exact display",reject(function()brohn_task_display_resources_current(store,o$handle)))
    brohn_put_entity(store,"dataset",d$id,prior,archived$revision,d$project_id)
    check("restored source restores historical display",is.list(brohn_task_display_resources_current(store,o$handle)))
    DBI::dbBegin(store$con);tryCatch({DBI::dbExecute(store$con,"UPDATE jobs SET status='failed' WHERE id=?",params=list(o$record$body$producer$job_id))
      check("saved display producer proof is refreshed",reject(function()brohn_task_display_resources_current(store,o$handle)))},finally=DBI::dbRollback(store$con))
    runid<-native$report$saved_body$provenance$runs[[1L]]$run_id
    DBI::dbBegin(store$con);tryCatch({DBI::dbExecute(store$con,"DROP TRIGGER delivery_terminal_run");DBI::dbExecute(store$con,"UPDATE delivery_runs SET completion_status='withdrawn' WHERE id=?",params=list(runid))
      check("withdrawn native administration invalidates held display",reject(function()brohn_task_display_resources_current(store,n$handle)))},finally=DBI::dbRollback(store$con))
    DBI::dbBegin(store$con);tryCatch({DBI::dbExecute(store$con,"UPDATE entities SET project_id='different-project' WHERE kind='report' AND id=?",params=list(original$report$ref$id))
      check("current source project reassignment refuses",reject(function()brohn_task_display_resources_current(store,o$handle)))},finally=DBI::dbRollback(store$con))
    brohn_release_task_display_resources(o$handle)
    path<-o$artifact$path;bytes<-readBin(path,"raw",n=file.info(path)$size);bad<-bytes;bad[[1L]]<-as.raw(bitwXor(as.integer(bad[[1L]]),1L));writeBin(bad,path)
    tryCatch(check("corrupt saved evidence refuses before decode",reject(function()brohn_open_task_display_resources(store,original$task_display$ref,project))),finally=writeBin(bytes,path))
    o<-brohn_open_task_display_resources(store,original$task_display$ref,project);handles<-c(handles,list(o$handle))
    # Bind a real local trusted-edge policy to test fresh-reader/original-actor gates.
    secret<-brohn_token();writeChar(secret,file.path(out,"edge.secret"),eos=NULL,useBytes=TRUE)
    revoke<-function(subjects=list())brohn_write_json_file(list(schema="brohn-hosted-revocations/1.0",subjects=subjects,not_before=0),file.path(out,"revocations.json"));revoke()
    profile<-list(schema="brohn-hosted-profile/1.0",id="task-display-boundary",mode="local_oidc_fixture",workspace_root=store$root,workspace_id=store$workspace_id,project_id=project,
      researcher_origin="https://research.example.test",participant_origin="https://participant.example.test",issuer="http://127.0.0.1:3900/realms/brohn",allowed_groups=list("researchers"),edge_secret_file=file.path(out,"edge.secret"),revocations_file=file.path(out,"revocations.json"),session_seconds=3600L,enrollment_seconds=3600L,upload_seconds=3600L,resource_seconds=3600L,researcher_port=3911L,participant_port=3912L,oauth_port=3913L)
    profilepath<-file.path(out,"profile.json");brohn_write_json_file(profile,profilepath);Sys.setenv(BROHN_HOSTED_PROFILE=profilepath);profile<-.brohn_rpa_profile()
    bind<-function(subject){headers<-list(HTTP_HOST="research.example.test",HTTP_X_FORWARDED_PROTO="https",HTTP_X_BROHN_EDGE=secret,HTTP_X_FORWARDED_USER=subject,HTTP_X_FORWARDED_GROUPS="researchers",HTTP_ORIGIN=profile$researcher_origin);brohn_hosted_bind_store(store,profile,brohn_hosted_context(headers,profile))}
    reader<-bind("fresh-task-reader");producer<-bind("original-task-producer")
    check("unbound service cannot serve old held display under hosted policy",reject(function()brohn_task_display_resources_current(store,o$handle)))
    check("fresh authorized reader reads successful local producer history",is.list(brohn_task_display_resources_current(reader,o$handle)))
    revoke(list("fresh-task-reader"));check("current reader revocation blocks held history",reject(function()brohn_task_display_resources_current(reader,o$handle)));revoke()
    expired<-reader;expired$hosted_context$expires<-as.numeric(Sys.time())-1
    check("expired current reader cannot reuse native holds",reject(function()brohn_task_display_resources_current(expired,o$handle)))
    job<-brohn_queue_task_display(producer,original$report$ref);revoke(list("original-task-producer"))
    check("fresh service cannot replace original revoked queued actor",reject(function()brohn_report_package_job_authorize(reader,job)))
    claim<-brohn_claim_job(store,"task-authority-worker",90L);brohn_process_job(store,claim,timeout_seconds=120)
    check("genuine revoked producer attempt refuses publication",brohn_get_job(store,job$id)$status=="failed")
    retry<-brohn_queue_task_display(reader,original$report$ref,retry=TRUE)
    check("explicit retry captures current authorized reader",identical(retry$request$authority$context$subject,"fresh-task-reader"))
    claim<-brohn_claim_job(store,"task-authority-worker",90L)
    DBI::dbBegin(store$con);tryCatch({DBI::dbExecute(store$con,"UPDATE jobs SET lease_until=0 WHERE id=?",params=list(claim$id));check("expired lease cannot cross publication fence",reject(function()brohn_report_package_job_fence(reader,claim)))},finally=DBI::dbRollback(store$con))
    brohn_cancel_job(store,claim$id);check("cancelled attempt cannot cross publication fence",reject(function()brohn_report_package_job_fence(reader,claim)))
    retry<-brohn_queue_task_display(reader,original$report$ref,retry=TRUE);claim<-brohn_claim_job(store,"task-authority-worker",120L);brohn_process_job(store,claim,timeout_seconds=180)
    done<-brohn_get_job(store,retry$id);check("authorized hosted fixture display genuinely publishes",identical(done$status,"succeeded"))
    saved<-brohn_get_entity(reader,"task_display",done$result$task_display_id);savedref<-.brohn_rpk_ref(saved)
    replacement<-bind("later-independent-reader");revoke(list("fresh-task-reader"))
    historical<-brohn_open_task_display_resources(replacement,savedref,project);handles<-c(handles,list(historical$handle))
    check("new current reader opens history after successful original producer is revoked",is.list(brohn_task_display_resources_current(replacement,historical$handle)))
    revoke()
    Sys.unsetenv("BROHN_HOSTED_PROFILE");check("removed hosted profile does not downgrade a bound reader",reject(function()brohn_task_display_resources_current(reader,o$handle)))
    check("restored local policy serves original exact artifact",is.list(brohn_task_display_resources_current(store,o$handle)))
    passed<-TRUE
  },error=function(e){failure<<-conditionMessage(e);stop(e)})
  cat(length(checks),"task-display boundary checks passed\n")
})

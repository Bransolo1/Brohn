# Native source-handle cleanup at actual cancellation checkpoints; no child/science.
args<-commandArgs(TRUE);stopifnot(length(args)==3L)
repo<-normalizePath(args[[1]],winslash="/",mustWork=TRUE);originals<-normalizePath(args[[2]],winslash="/",mustWork=TRUE)
out<-args[[3]];stopifnot(!file.exists(out));dir.create(out,recursive=TRUE);out<-normalizePath(out,winslash="/",mustWork=TRUE)
stopifnot(file.copy(file.path(originals,"workspace"),out,recursive=TRUE))
setwd(repo);source("R/platform-load.R",encoding="UTF-8");brohn_load(ui=FALSE)
local({s<-brohn_open_store(file.path(out,"workspace"));checks<-list();passed<-FALSE;failure<-NULL;guards<-list();captured<-NULL
 env<-environment(.brohn_rpk_hold_sources);hold<-get("brohn_hold_signal_value_sources",env);sourcehold<-get(".brohn_rpk_hold_sources",env)
 on.exit({assign("brohn_hold_signal_value_sources",hold,env);assign(".brohn_rpk_hold_sources",sourcehold,env);if(!is.null(captured)).brohn_rpk_release(captured)
  for(j in brohn_list_jobs(s,limit=1000L))if(j$status %in% c("queued","running"))brohn_cancel_job(s,j$id)
  brohn_write_json_file(list(passed=passed,checks=checks,failure=failure,scope="Two normal60s attempts cancelled through real API while native source handles are held. Wrappers only capture returned handles; no scientific child or altered lease clock."),file.path(out,"results.json"));brohn_close_store(s)},add=TRUE)
 check<-function(x,label){stopifnot(isTRUE(x));checks[[length(checks)+1L]]<<-label;cat("PASS",label,"\n")}
 refuse<-function(f)inherits(try(f(),silent=TRUE),"try-error")
 rows<-function(t)DBI::dbGetQuery(s$con,paste("SELECT * FROM",t,"ORDER BY rowid"));before<-lapply(c("jobs","entity_versions","objects"),rows)
 tryCatch({
  r<-brohn_eda_read_json_file(file.path(originals,"event-report.json"),16*1024^2);ref<-.brohn_rpk_ref(r);metadata<-.brohn_edd_context(s,ref)$metadata
  queue<-function(){j<-brohn_queue_eda_display(s,ref,retry=TRUE);claim<-brohn_claim_job(s,"eda-source-pulse-qa",lease_seconds=60L);stopifnot(j$id==claim$id);claim}
  assign("brohn_hold_signal_value_sources",function(...){x<-hold(...);guards<<-x;x},env)
  j<-queue();checkpoint<-.brohn_publication_checkpoint(s,j);calls<-0L
  pulse<-function(){calls<<-calls+1L;if(calls==2L){check(length(guards)>0L&&!refuse(function().brohn_cm_guard_check(guards)),"all original native guards are live before cancellation");brohn_cancel_job(s,j$id)};checkpoint(TRUE)}
  check(refuse(function().brohn_rpk_hold_sources(s,metadata,pulse)),"cancellation after sealing refuses before full source verification")
  check(length(guards)>0L&&all(vapply(guards,function(g)refuse(function().brohn_cm_guard_check(list(g))),logical(1))),"every acquired native pointer is closed on cancelled source acquisition")
  check(identical(brohn_get_job(s,j$id)$status,"cancelled"),"cancelled attempt is not revived by progress checkpoint")
  guards<-list();captured<-NULL;j<-queue();checkpoint<-.brohn_publication_checkpoint(s,j)
  assign(".brohn_rpk_hold_sources",function(...){x<-sourcehold(...);captured<<-x;x},env)
  pulse<-function(){if(!is.null(captured)){check(!isTRUE(captured$state$closed)&&!refuse(function().brohn_cm_guard_check(captured$guards)),"complete source handle remains sealed before hydration cancellation");brohn_cancel_job(s,j$id)};checkpoint(TRUE)}
  scratch<-file.path(out,"owned-empty-scratch");dir.create(scratch);input<-brohn_eda_display_input(s,j,FALSE)
  check(refuse(function()brohn_prepare_eda_display_execution(s,j,input,scratch,pulse)),"hydration checkpoint propagates genuine cancellation")
  check(!is.null(captured)&&isTRUE(captured$state$closed)&&all(vapply(captured$guards,function(g)refuse(function().brohn_cm_guard_check(list(g))),logical(1))),"parent prepare closes every held pointer after cancelled hydration")
  check(!length(list.files(scratch,all.files=TRUE,no..=TRUE)),"cancelled pre-child preparation writes no bundle or artifact")
  after<-lapply(c("jobs","entity_versions","objects"),rows)
  check(identical(before[[1]],after[[1]][match(before[[1]]$id,after[[1]]$id),,drop=FALSE]),"all original scientific jobs remain unchanged")
  check(identical(before[[2]],after[[2]])&&identical(before[[3]],after[[3]]),"all original revisions and object metadata remain unchanged")
  for(h in before[[3]]$hash)brohn_object_path(s,h,TRUE)
  check(TRUE,"all original object bytes remain exact")
  check(all(vapply(brohn_list_jobs(s,limit=1000L),function(j)j$status %in% c("succeeded","cancelled"),logical(1))),"both cancelled attempts and original jobs are terminal")
  passed<-TRUE
 },error=function(e){failure<<-conditionMessage(e);stop(e)})
})

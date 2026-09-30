# Registered original source schemas and refusal mutations; never calls a scorer.
args<-commandArgs(TRUE);stopifnot(length(args)==3L)
repo<-normalizePath(args[[1L]],winslash="/",mustWork=TRUE)
originals<-normalizePath(args[[2L]],winslash="/",mustWork=TRUE)
out<-args[[3L]];stopifnot(!file.exists(out));dir.create(out,recursive=TRUE);out<-normalizePath(out,winslash="/",mustWork=TRUE)
setwd(repo);source("R/platform-load.R",encoding="UTF-8");brohn_load(ui=FALSE)
local({checks<-list();passed<-FALSE;failure<-NULL
 on.exit(brohn_write_json_file(list(passed=passed,checks=checks,failure=failure),file.path(out,"results.json")),add=TRUE)
 check<-function(value,label){stopifnot(isTRUE(value));checks[[length(checks)+1L]]<<-label;cat("PASS",label,"\n")}
 tryCatch({
  sources<-list()
  for(name in c("event","continuous","controlled","cvxeda","unavailable")){
   if(!file.exists(file.path(originals,paste0(name,"-report.json")))){if(name %in% c("event","continuous"))stop("Required original event/continuous source absent");next}
   original<-brohn_eda_read_json_file(file.path(originals,paste0(name,"-report.json")),16*1024^2)
   report<-list(ref=.brohn_rpk_ref(original),saved_body=original$body,complete_analysis=original$body$analysis)
   .brohn_edd_validate_analysis(report);sources[[name]]<-report;check(TRUE,paste(name,"strict original semantic fields"))
  }
  mutations<-list(
   unknown_engine=function(a){a$engine$unregistered<-1;a},unknown_recipe=function(a){a$parameters[[1L]]$unregistered<-1;a},
   malformed_boolean=function(a){a$recordings[[1L]]$baseline_support$complete<-1;a},
   invented_support=function(a){a$recordings[[1L]]$baseline_support$unregistered<-1;a},
   changed_denominator=function(a){a$features[[6L]]$denominator<-"responder_only";a},
   changed_eligibility=function(a){a$features[[1L]]$eligible<-FALSE;a},
   unknown_series=function(a){a$series[[1L]]$emotion<-1;a},
   unknown_group=function(a){a$series[[1L]]$group$new_identity<-"x";a},
   unknown_mask=function(a){a$source_masks[[1L]]$confidence<-1;a},
   altered_quality=function(a){a$quality$computed_window_cells<-999;a},
   altered_cvx_defaults=function(a){a$parameters[[1L]]$effective$cvx_defaults<-list(tau0=2);a},
   null_as_zero=function(a){i<-which(vapply(a$features,function(x)is.null(x$value),logical(1)))[[1L]];a$features[[i]]$value<-0;a})
  for(label in names(mutations)){r<-sources$event;r$complete_analysis<-mutations[[label]](r$complete_analysis);r$saved_body$analysis<-r$complete_analysis;r$ref$body_hash<-brohn_hash(r$saved_body)
   check(inherits(try(.brohn_edd_validate_analysis(r),silent=TRUE),"try-error"),paste(label,"refused before projection"))}
  check(inherits(try(brohn_eda_value_hash(matrix(1,1,1)),silent=TRUE),"try-error"),"non-JSON dimensional scalar refused")
  passed<-TRUE
 },error=function(e){failure<<-conditionMessage(e);stop(e)})
})

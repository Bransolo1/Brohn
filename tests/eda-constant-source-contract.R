args<-commandArgs(trailingOnly=TRUE)
stopifnot(length(args)==4L)
repo<-normalizePath(args[[1L]],winslash="/",mustWork=TRUE)
components<-normalizePath(args[[2L]],winslash="/",mustWork=TRUE)
originals<-normalizePath(args[[3L]],winslash="/",mustWork=TRUE)
out<-args[[4L]];stopifnot(!file.exists(out));dir.create(out,recursive=TRUE);out<-normalizePath(out,winslash="/")
setwd(repo);source("R/platform-load.R",encoding="UTF-8");brohn_load(ui=FALSE)
checks<-list();evidence<-list();failure<-NULL
check<-function(ok,label){if(!isTRUE(ok))stop(label);checks[[length(checks)+1L]]<<-list(name=label,passed=TRUE)}
refuse<-function(fn,label)check(inherits(try(fn(),silent=TRUE),"try-error"),label)
old<-.brohn_edd_profile_spec();new<-.brohn_edd_profile_spec("saved-eda-display/0.2")
tryCatch({
 check(identical(old$profile,"saved-eda-display/0.1")&&identical(new$admission,"task-choice-eda-findings/0.2"),"closed profile dispatch preserves the legacy default")
 refuse(function().brohn_edd_profile_spec("saved-eda-display/latest"),"unknown profile refuses")
 refuse(function().brohn_edd_profile_from_admission("task-choice-findings/0.1"),"unrelated admission cannot acquire EDA grammar")
 check(identical(brohn_report_source_admission("controlled-gaze-explicit-task-choice-eda-paired/0.1"),old$admission)&&identical(brohn_report_source_admission("controlled-gaze-explicit-task-choice-eda-paired/0.2"),new$admission),"renderer admission versions remain distinct")
 check(!identical(brohn_eda_display_implementation_ref(old$profile),brohn_eda_display_implementation_ref(new$profile)),"new and legacy preparation implementations have distinct identities")
 # Original producer components are not native published report envelopes.
 # We validate their exact scientific vocabularies directly, without a scorer.
 for(name in c(paste0("constant-",1:6),"edge-399","edge-400","segmentation","legacy-flatline","legacy-ordinary")){
  path<-file.path(components,name,"result.json");if(!file.exists(path))next
  a<-brohn_eda_read_json_file(path,16*1024^2);evidence[[name]]<-digest::digest(file=path,algo="sha256")
  .brohn_edd_semantics(a,"continuous",new);check(TRUE,paste(name,"original producer semantic vocabulary accepted under new profile"))
  recipe11<-any(vapply(a$parameters,function(p)identical(p$recipe,"eda-neurokit-highpass/1.1"),logical(1)))
  if(recipe11)refuse(function().brohn_edd_semantics(a,"continuous",old),paste(name,"new recipe refuses under legacy profile"))else{.brohn_edd_semantics(a,"continuous",old);check(TRUE,paste(name,"old recipe retains old grammar"))}
  for(r in Filter(function(r)identical(r$status,"descriptive_only"),a$recordings)){
   fs<-Filter(function(f)identical(f$recording_id,r$recording_id)&&identical(f$segment_id,r$segment_id)&&identical(f$channel,r$channel),a$features)
   .brohn_edd_constant_features(fs,r,a$parameters[[r$recording_id]],a$series,a$events)
   check(TRUE,paste(name,r$segment_id,"ten features/nulls/raw preview and declared edge support reconcile"))
  }
 }
 a<-brohn_eda_read_json_file(file.path(components,"constant-1/result.json"),16*1024^2)
 mutate<-function(label,fn){x<-fn(a);refuse(function(){.brohn_edd_semantics(x,"continuous",new);r<-x$recordings[[1L]];.brohn_edd_constant_features(x$features,r,x$parameters[[r$recording_id]],x$series,x$events)},label)}
 mutate("new status under old scientific recipe refuses",function(x){x$parameters[[1L]]$recipe<-"eda-neurokit-highpass/1.0";x$parameters[[1L]]$exact_constant_policy<-NULL;x})
 mutate("missing constant policy refuses",function(x){x$parameters[[1L]]$exact_constant_policy<-NULL;x})
 mutate("invented epsilon policy refuses",function(x){x$parameters[[1L]]$exact_constant_policy<-"near_constant/1.0";x})
 mutate("nine withheld measures cannot become finite zero",function(x){x$features[[1L]]$value<-0;x})
 mutate("withheld response denominator cannot become zero",function(x){x$features[[7L]]$denominator<-0;x})
 mutate("absent amplitude denominator refuses",function(x){x$features[[7L]]$denominator<-NULL;x})
 mutate("fabricated denominator on raw mean refuses",function(x){x$features[[4L]]$denominator<-NULL;x$features[[4L]]["denominator"]<-list(NULL);x})
 mutate("raw description cannot become unavailable",function(x){x$features[[4L]]["value"]<-list(NULL);x})
 mutate("altered raw preview level refuses",function(x){x$series[[1L]]$raw_us<-1;x})
 mutate("finite substitute waveform refuses",function(x){x$series[[1L]]$clean_us<-0;x})
 mutate("descriptive quality count must reconcile",function(x){x$quality$descriptive_channel_segments<-0;x})
 mutate("all descriptive support remains usable",function(x){x$quality$usable<-FALSE;x})
 mutate("response denominator field remains explicitly null",function(x){x$recordings[[1L]]$response_denominator<-NULL;x})
 mutate("response availability cannot be inferred from raw level",function(x){x$recordings[[1L]]$response_status<-"computed";x})
 mutate("constant branch cannot accept an inexact-flatline flag",function(x){x$recordings[[1L]]$exact_flatline<-FALSE;x})
 mutate("complete feature order stays original",function(x){x$features<-rev(x$features);x})
 mutate("declared retained edge arithmetic remains exact",function(x){x$recordings[[1L]]$retained_samples<-x$recordings[[1L]]$retained_samples+1;x})
 r<-a$recordings[[1L]];sel<-c(r[c("recording_id","segment_id","channel")],list(start_s=.brohn_ecr_shortest(r$start_time_s),end_s=.brohn_ecr_shortest(r$end_time_s)))
 picked<-brohn_eda_continuous_review_selection(a,sel)
 check(identical(.brohn_ecr_recipe_spec(picked$parameters)$queued_recipe,"saved-continuous-eda-review/1.1"),"new source selects new standalone review recipe")
 refuse(function(){sel$start_s<-"1";brohn_eda_continuous_review_selection(a,sel)},"constant source cannot be narrowed as a response repair")
 for(name in c("event","continuous")){
  path<-file.path(originals,paste0(name,"-report.json"));r<-brohn_eda_read_json_file(path,16*1024^2)
  report<-list(ref=.brohn_rpk_ref(r),saved_body=r$body,complete_analysis=r$body$analysis)
  .brohn_edd_validate_analysis(report,old);.brohn_edd_validate_analysis(report,new)
  check(TRUE,paste(name,"exact historical report passes unchanged old grammar in either preparation"))
  evidence[[paste0("historical-",name)]]<-digest::digest(file=path,algo="sha256")
 }
},error=function(e)failure<<-conditionMessage(e))
result<-list(schema="brohn-constant-source-contract-tests/0.1",passed=is.null(failure),checks=checks,count=length(checks),error=failure,
 scope="Pure registered-vocabulary/version tests on original producer components and exact historical reports. No native publication, store mutation, scientific worker or stream decode.",
 original_files=evidence,source_hashes=stats::setNames(lapply(c("platform-eda-display.R","platform-eda-display-sources.R","platform-report-package-sources.R","platform-eda-continuous-review.R"),function(p)digest::digest(file=file.path("R",p),algo="sha256")),c("platform-eda-display.R","platform-eda-display-sources.R","platform-report-package-sources.R","platform-eda-continuous-review.R")))
brohn_write_json_file(result,file.path(out,"results.json"));if(!is.null(failure))stop(failure)
cat("Passed",length(checks),"scoped source checks\n")

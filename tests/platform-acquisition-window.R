source("R/platform-load.R",encoding="UTF-8");brohn_load()
local({
  root<-tempfile("brohn-window-quality-");dir.create(root);checks<-0L
  on.exit({actual<-normalizePath(root,winslash="/",mustWork=FALSE)
    stopifnot(startsWith(tolower(actual),paste0(tolower(normalizePath(tempdir(),winslash="/")),"/")),startsWith(basename(actual),"brohn-window-quality-"));unlink(actual,recursive=TRUE)},add=TRUE)
  check<-function(name,value){if(!isTRUE(value))stop("Window QA: ",name);checks<<-checks+1L}
  rejects<-function(expr)inherits(try(force(expr),silent=TRUE),"try-error")
  output<-file.path(root,"replay")
  processx::run(.brohn_acq_python(),c("tests/acquisition/monitoring_window.py","--fixture",output),timeout=60000,windows_hide_window=TRUE)
  results<-brohn_read_json_file(file.path(output,"results.json"),16*1024^2)
  record<-function(result)list(id=result$id,body=list(request=result$request,status="recording",origin="sample",python_request_hash=result$live$request_sha256),live_snapshot=result$live)
  model<-function(result)brohn_acquisition_quality(record(result),now_epoch=result$live$monitoring$updated_epoch)
  models<-lapply(results,model);ecg<-models[[1L]]$streams[[1L]];eda<-models[[2L]]$streams[[1L]];contact<-models[[3L]]$streams[[1L]]
  check("five-second support represents thousands of actual committed samples",ecg$window$committed_rows>4800&&ecg$window$actual_span_s>4.8&&ecg$window$actual_span_s<=5&&ecg$window$plotted_points<=512)
  check("short exact latest rows remain independent of decimated display",ecg$preview_rows==16L&&tail(ecg$preview,1L)[[1L]]$sequence==6000L)
  check("finite and source cadence checks pass independently",length(ecg$checks)==2L&&all(vapply(ecg$checks,function(x)x$status=="meets_selected_check",logical(1)))&&abs(ecg$checks[[2L]]$observed-1000)<1e-7)
  check("check denominator comes from every retained committed sample",ecg$checks[[1L]]$samples==ecg$window$committed_rows&&ecg$checks[[1L]]$observed==1)
  check("negative and unavailable EDA samples cause the declared check to fail",eda$checks[[1L]]$status=="unmet"&&eda$checks[[1L]]$samples==4L&&eda$checks[[1L]]$observed==.5)
  check("native contact text codes retain declared code units",contact$checks[[1L]]$status=="meets_selected_check"&&contact$checks[[1L]]$criterion$unit=="code"&&identical(contact$checks[[1L]]$criterion$accepted_values,list("contact")))
  check("categorical source does not fabricate a numeric waveform",length(contact$window$channels[[1L]]$points)==0L&&is.null(contact$observed_rate)==FALSE)
  check("passing acquisition criteria never qualify physiological signal",!models[[1L]]$quality_qualified&&!ecg$quality_qualified&&ecg$quality_status!="usable")
  rendered<-as.character(brohn_acquisition_quality_ui(models[[1L]]))
  check("visible criteria keep pass distinct from physiological validity",grepl("Meets selected acquisition check",rendered,fixed=TRUE)&&grepl("physiological validity is not established",rendered,fixed=TRUE)&&grepl("Measurement quality: not qualified",rendered,fixed=TRUE))
  check("actual waveform names time support and peak-preserving method",grepl("committed source-time waveform",rendered,fixed=TRUE)&&grepl("First/minimum/maximum/last",rendered,fixed=TRUE)&&!grepl("NaN|Inf",rendered))
  prior<-record(results[[1L]])
  stale<-brohn_acquisition_quality(prior,now_epoch=results[[1L]]$live$monitoring$updated_epoch+10)$streams[[1L]]
  check("stale current data stays unknown",all(vapply(stale$checks,function(x)x$status=="unknown",logical(1))))
  prior$live_snapshot<-results[[1L]]$closed
  check("closed recording never inherits a live passing check",all(vapply(brohn_acquisition_quality(prior)$streams[[1L]]$checks,function(x)x$status=="unknown",logical(1))))
  prior<-record(results[[1L]]);prior$live_snapshot$monitoring$streams$source$last_committed_monotonic_s<-prior$live_snapshot$monitoring$updated_monotonic_s-10
  check("recent receipt cannot renew an old committed check",all(vapply(brohn_acquisition_quality(prior,now_epoch=prior$live_snapshot$monitoring$updated_epoch)$streams[[1L]]$checks,function(x)x$status=="unknown",logical(1))))
  prior<-record(results[[1L]]);prior$body$request$streams[[1L]]$channels[[1L]]$unit<-"unknown"
  invalid<-brohn_acquisition_quality(prior,now_epoch=prior$live_snapshot$monitoring$updated_epoch)$streams[[1L]]
  check("missing original-unit metadata preserves named unknown checks",length(invalid$checks)==2L&&all(vapply(invalid$checks,function(x)x$status=="unknown",logical(1))))
  prior<-record(results[[1L]]);prior$live_snapshot$monitoring$streams$source$window$checks[[1L]]$criterion$source<-"substituted evidence"
  check("a substituted criterion cannot inherit its old passing result",brohn_acquisition_quality(prior,now_epoch=prior$live_snapshot$monitoring$updated_epoch)$streams[[1L]]$checks[[1L]]$status=="unknown")
  prior<-record(results[[1L]]);prior$live_snapshot$monitoring$streams$source$window$checks[[1L]]$samples<-2
  check("a mismatched complete denominator is unknown",brohn_acquisition_quality(prior,now_epoch=prior$live_snapshot$monitoring$updated_epoch)$streams[[1L]]$checks[[1L]]$status=="unknown")
  prior<-record(results[[1L]]);prior$live_snapshot$monitoring$streams$source$window$channels[[1L]]$points[[1L]]<-list("malformed")
  check("malformed window evidence fails closed without a renderer crash",all(vapply(brohn_acquisition_quality(prior,now_epoch=prior$live_snapshot$monitoring$updated_epoch)$streams[[1L]]$checks,function(x)x$status=="unknown",logical(1))))
  prior<-record(results[[1L]]);prior$live_snapshot$monitoring$streams$source$window$boundaries<-1
  check("interrupted cadence cannot meet a continuous cadence criterion",brohn_acquisition_quality(prior,now_epoch=prior$live_snapshot$monitoring$updated_epoch)$streams[[1L]]$checks[[2L]]$status=="unknown")
  s<-results[[3L]]$request$streams[[1L]];bad<-s$readiness;bad$acquisition_checks[[1L]]$accepted_values<-list(1)
  check("numeric codes cannot silently replace native categorical text",rejects(brohn_validate_acquisition_readiness(bad,s$channels)))
  for(field in c("source","rationale","version")) {
    bad<-s$readiness;bad$acquisition_checks[[1L]][[field]]<-""
    check(paste("review requires explicit",field),rejects(brohn_validate_acquisition_readiness(bad,s$channels)))
  }
  bad<-s$readiness;bad$preview_channels<-list("not-selected")
  check("a check cannot inspect an unselected channel",rejects(brohn_validate_acquisition_readiness(bad,s$channels)))
  bad<-s$readiness;bad$acquisition_checks[[1L]]$maximum_age_s<-NULL
  check("staleness threshold has no invented default",rejects(brohn_validate_acquisition_readiness(bad,s$channels)))
  bad<-s$readiness;bad$schema<-"brohn-acquisition-readiness/1.0"
  check("legacy readiness cannot silently acquire new checks",rejects(brohn_validate_acquisition_readiness(bad,s$channels)))
  cat(sprintf("PASS: %d acquisition window checks (actual durable replay, full support, native codes, stale/closed/tampered evidence and rendering)\n",checks))
})

# Real production Writer -> bounded snapshot -> readiness model and rendered UI.
source("R/platform-load.R",encoding="UTF-8");brohn_load(ui=FALSE)
source("R/platform-shell.R",encoding="UTF-8");source("R/platform-data-views.R",encoding="UTF-8");source("R/platform-acquisition-views.R",encoding="UTF-8")
local({
  root<-tempfile("brohn-monitoring-qa-");dir.create(root);root<-normalizePath(root,winslash="/");checks<-0L
  on.exit({actual<-normalizePath(root,winslash="/",mustWork=FALSE)
    stopifnot(identical(dirname(actual),normalizePath(tempdir(),winslash="/")),startsWith(basename(actual),"brohn-monitoring-qa-"));unlink(actual,recursive=TRUE,force=TRUE)},add=TRUE)
  check<-function(name,ok){if(!isTRUE(ok))stop("Monitoring QA: ",name);checks<<-checks+1L}
  rejects<-function(expr)inherits(try(force(expr),silent=TRUE),"try-error")
  case<-function(family,units="uV",roles="signal",values=list(list(1),list(2),list(3)),extra=list(),rails=NULL) {
    id<-paste0("original-",family);channels<-lapply(seq_along(units),function(i)list(id=paste0("c",i),label=paste(family,i),type=family,unit=units[[i]],value_type="float64"))
    declarations<-lapply(seq_along(channels),function(i)c(list(id=channels[[i]]$id,role=roles[[i]]),if(!is.null(rails))rails[[i]] else NULL))
    readiness<-c(list(schema="brohn-acquisition-readiness/1.0",modality=family,channels=declarations,
      preview_channels=as.list(vapply(channels,`[[`,character(1),"id"))),extra)
    brohn_validate_acquisition_readiness(readiness,channels)
    request<-list(schema="brohn-lsl-record-request/1.0",recording_id=id,output_root=root,lsl_session="original-monitoring",origin="sample",
      origin_statement="Original software replay only; no physical device or person.",identity=list(participant_id="original",session_id=id),
      streams=list(list(id="source",uid=id,source_id=id,metadata_sha256=strrep("0",64),clock_id="original-source-clock",clock_kind="monotonic",
        kind="signal",unit_provenance="Original synthetic unit declaration",channels=channels,readiness=readiness,gap_threshold_s=.5)),
      limits=list(max_duration_s=5,max_samples=1000,max_bytes=1024^2,chunk_samples=32,inlet_buffer=1))
    list(id=id,request=request,chunks=list(list(values=values,stamps=as.list(seq_along(values)/10))))
  }
  cases<-list(case("ecg"),case("ppg","counts",values=list(list(0),list(5),list(10)),rails=list(list(rail_min=0,rail_max=10))),
    case("eeg",c("uV","kOhm"),c("signal","impedance"),list(list(2,12),list(3,13),list(4,14))),
    case("eda","uS",values=list(list(-.2),list(1),list(1),list(list(nonfinite="nan")))),
    case("fnirs","counts","intensity",list(list(1),list(0),list(2))),case("respiration","a.u.",values=list(list(0),list(0),list(0))),
    case("emg"),case("eog"),case("temperature","degC"),
    case("movement",c("m/s^2","m/s^2","m/s^2"),c("axis_x","axis_y","axis_z"),list(list(3,4,0),list(0,0,0),list(-3,-4,0)),
      list(frame="Source right-handed XYZ",gravity_policy="Original source includes gravity")),
    case("audio","FS",values=list(list(1),list(-1),list(1))),
    case("camera",c("count","probability"),c("face_count","confidence"),list(list(0,.2),list(2,.7),list(1,.8))),
    case("implicit",c("index","ms"),c("trial_index","timing"),list(list(1,20),list(2,30),list(3,40))),
    case("gaze",c("normalized","normalized","code"),c("gaze_x","gaze_y","validity"),
      list(list(.2,.3,1),list(.4,.5,1),list(.7,.8,0)),
      list(gaze=list(eye="left",unit="normalized",frame="Source normalized display",origin="top_left",valid_value=1))),
    case("unclassified","unknown",values=list(list(-1e308),list(0),list(1e308))))
  # More than the preview capacity, with explicit source reversal and gap.
  cases[[1L]]$chunks<-list(list(values=lapply(seq_len(20L),function(i)list(i)),stamps=as.list(seq_len(20L)/10)),
    list(values=list(list(21),list(22)),stamps=list(1,2)))
  source<-file.path(root,"cases.json");brohn_write_json_file(cases,source);out<-file.path(root,"replay")
  process<-processx::run(.brohn_acq_python(),c("tests/fixtures/acquisition-monitoring-replay.py",source,out),
    error_on_status=FALSE,timeout=60,windows_hide_window=TRUE)
  check("all measurement families replay through the actual durable Writer",process$status==0L)
  if(process$status!=0L)stop(process$stderr)
  results<-brohn_read_json_file(file.path(out,"results.json"),16*1024^2)
  models<-stats::setNames(lapply(results,function(result)brohn_acquisition_quality(list(id=result$request$recording_id,
    body=list(request=result$request,status="recording",origin="sample",python_request_hash=result$live$request_sha256),live_snapshot=result$live),
    now_epoch=result$live$monitoring$updated_epoch)),vapply(results,`[[`,character(1),"id"))
  first<-function(family)models[[paste0("original-",family)]]$streams[[1L]]
  for(family in names(brohn_acquisition_quality_profiles())) {
    model<-models[[paste0("original-",family)]];stream<-model$streams[[1L]]
    check(paste(family,"keeps separate subscribed received committed and unqualified quality"),model$monitoring_available&&stream$connection=="subscribed"&&
      stream$received==stream$committed&&stream$received>0&&!model$quality_qualified&&!stream$quality_qualified)
    rendered<-as.character(brohn_acquisition_quality_ui(model))
    check(paste(family,"has measurement-specific accessible visible monitoring"),grepl(stream$label,rendered,fixed=TRUE)&&
      grepl("Measurement quality: not qualified",rendered,fixed=TRUE)&&grepl('role="img"',rendered,fixed=TRUE))
  }
  ecg<-first("ecg")
  check("bounded preview never replaces full committed population",ecg$preview_rows==16L&&ecg$committed==22L&&results[[1L]]$inspection$samples==22L)
  check("source reset and gap remain explicit in monitoring",ecg$resets==1L&&ecg$gaps==1L&&ecg$preview[[15L]]$segment==2L)
  check("finite extreme source values never overflow SVG coordinates",!grepl("NaN|Inf",as.character(brohn_acquisition_preview_svg(first("unclassified")$channels[[1L]],first("unclassified")$preview))))
  check("cadence excludes source segment reversal rather than resampling",abs(ecg$observed_rate$hz-10)<1e-8&&ecg$observed_rate$method=="inverse_median_positive_interval_within_source_segment")
  eda<-first("eda")
  check("nonfinite and negative declared conductance are observable",eda$channels[[1L]]$stats$nonfinite==1L&&
    any(grepl("Negative source conductance",unlist(eda$channels[[1L]]$warnings),fixed=TRUE))&&is.null(eda$channels[[1L]]$preview[[4L]]))
  check("bounded observation does not infer ECG peaks or a respiration diagnosis",is.null(ecg$derived$beats)&&
    !grepl("apnoea",as.character(brohn_acquisition_quality_ui(models[["original-respiration"]])),fixed=TRUE))
  check("PPG rails are based on explicit source limits",any(grepl("declared source rail",unlist(first("ppg")$channels[[1L]]$warnings),fixed=TRUE)))
  check("EEG impedance appears only as its supplied separate channel",first("eeg")$channels[[2L]]$role=="impedance"&&
    first("eeg")$channels[[2L]]$unit=="kOhm"&&first("eeg")$channels[[2L]]$stats$maximum==14&&is.null(ecg$impedance))
  check("fNIRS nonpositive raw intensity flagged without inferred coupling",any(grepl("Nonpositive optical intensity",unlist(first("fnirs")$channels[[1L]]$warnings),fixed=TRUE))&&is.null(first("fnirs")$derived$sci))
  check("explicit same-unit source XYZ norm keeps gravity declaration",identical(unlist(first("movement")$derived$vector_magnitude$values),c(5,0,5))&&
    first("movement")$derived$vector_magnitude$gravity_policy=="Original source includes gravity")
  check("audio RMS names its exact finite raw preview support",first("audio")$derived$window_rms[[1L]]$value==1&&
    first("audio")$derived$window_rms[[1L]]$finite_samples==3L&&first("audio")$derived$window_rms[[1L]]$window_rows==3L)
  gaze<-first("gaze")
  check("gaze requires original source-valid codes without substituting an earlier point",gaze$gaze$valid_samples==2L&&
    !tail(gaze$gaze$points,1L)[[1L]]$source_valid&&is.null(tail(gaze$gaze$points,1L)[[1L]]$x)&&
    !grepl("<circle",as.character(brohn_acquisition_gaze_svg(gaze$gaze)),fixed=TRUE))
  valid<-gaze$gaze;valid$points<-valid$points[1:2]
  check("source-valid gaze draws the actual declared coordinates",grepl('cx="0.4" cy="0.5"',as.character(brohn_acquisition_gaze_svg(valid)),fixed=TRUE))
  invalid_spec<-cases[[14L]]$request$streams[[1L]]$readiness;invalid_spec$gaze$unit<-"px";invalid_spec$gaze$width<-1920;invalid_spec$gaze$height<-1080
  check("display cannot relabel normalized source positions as pixels",rejects(brohn_validate_acquisition_readiness(invalid_spec,cases[[14L]]$request$streams[[1L]]$channels)))
  result<-results[[1L]];record<-list(id=result$request$recording_id,body=list(request=result$request,status="recording",origin="sample",python_request_hash=result$live$request_sha256),live_snapshot=result$live)
  delayed<-brohn_acquisition_quality(record,result$live$monitoring$updated_epoch+12)$streams[[1L]]
  check("sample age increases without declaring a universal stale threshold",delayed$last_sample_age_seconds>=12&&delayed$quality_status!="usable")
  record$live_snapshot$recording_id<-"other-recording"
  check("foreign telemetry never becomes healthy equipment",!brohn_acquisition_quality(record)$monitoring_available)
  record$live_snapshot<-NULL
  check("missing telemetry is unknown rather than zero or healthy",!brohn_acquisition_quality(record)$monitoring_available&&
    is.null(brohn_acquisition_quality(record)$streams[[1L]]$received))
  record$live_snapshot<-result$closed
  check("orderly source closure is distinct from a live subscription",brohn_acquisition_quality(record)$streams[[1L]]$connection=="closed")
  destination<-Sys.getenv("BROHN_MONITORING_EVIDENCE","")
  if(nzchar(destination)) {
    stopifnot(dir.exists(destination));brohn_write_json_file(list(checks=checks,models=models),file.path(destination,"monitoring-models.json"))
    page<-shiny::tags$body(style="margin:0",shiny::div(class="container-fluid",style="padding-inline:12px",shiny::div(class="brohn-app",shiny::tags$main(class="brohn-main",
      shiny::h1("Equipment checks - original software replay"),shiny::p("Synthetic signals only. No device or physical accuracy validation."),
      shiny::h2("Source observations"),shiny::h3("Replayed measurements"),lapply(models,brohn_acquisition_quality_ui)))))
    writeLines(paste0('<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">',
      '<title>Brohn original replay equipment checks</title></head>',as.character(page),'</html>'),file.path(destination,"monitoring-replay.html"),useBytes=TRUE)
  }
  cat(sprintf("Acquisition monitoring: %d scoped checks passed across %d replayed measurement families.\n",checks,length(models)))
})

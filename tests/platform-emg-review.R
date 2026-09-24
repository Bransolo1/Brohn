# Original hand-authored saved-value contract; no scientific scorer is called.
source("R/platform-load.R",encoding="UTF-8");brohn_load(ui=TRUE)
source("R/platform-emg-review.R",encoding="UTF-8");source("R/platform-emg-review-views.R",encoding="UTF-8")
args<-commandArgs(trailingOnly=TRUE);folder<-if(length(args))normalizePath(args[[1]],winslash="/",mustWork=FALSE)else tempfile("brohn-emg-review-domain-")
stopifnot(!dir.exists(folder));dir.create(folder,recursive=TRUE)
checks<-character();check<-function(label,value){stopifnot(isTRUE(value));checks<<-c(checks,label);cat("PASS",label,"\n")}
rejects<-function(expr)inherits(try(force(expr),silent=TRUE),"try-error")
local({
  generated<-processx::run(.brohn_publication_python(),c("tests/workers/emg_review.py","--fixture",file.path(folder,"hand")),error_on_status=FALSE)
  stopifnot(generated$status==0);f<-brohn_read_json_file(file.path(folder,"hand/fixture.json"))
  store<-brohn_open_store(file.path(folder,"workspace"));on.exit(brohn_close_store(store),add=TRUE);brohn_initialise_library(store)
  d<-brohn_ingest_dataset(store,f$original_source$path,"Original hand-value emg contract","emg",origin="sample")
  d$body$metadata<-list(time_column="time",time_unit="s",sampling_rate=500,value_columns=list("voltage"),unit="mV",parameters=f$parameters,origin_statement="Independent saved-value software fixture; no decomposition or human recording.")
  d<-brohn_put_entity(store,"dataset",d$id,d$body,project_id=d$project_id,expected_revision=d$revision)
  artifacts<-lapply(f$artifacts,function(a){o<-brohn_store_object(store,path=a$path,media_type="application/x-ndjson");c(o,a[c("kind","schema","tables","rows","provenance_sha256","complete")])})
  receipt<-list(schema="brohn-physiology-artifact-receipt/1.0",status="verified",artifacts=lapply(f$artifacts,function(a)c(a[c("kind","sha256","bytes","schema","tables","rows","provenance_sha256")],list(verified=TRUE))))
  body<-list(id="report-emg-hand",dataset_id=d$id,study_id=NULL,origin="sample",title="Original hand-value emg report",provenance=brohn_analysis_provenance(d$body,d$revision),
    analysis=list(kind="emg",modality="emg",source=list(sha256=d$body$source$hash),parameters=list(`recording-1`=f$parameters),
      recordings=list(f$recording),features=f$features,events=list(),artifacts=artifacts,artifact_verification=receipt))
  body$result_object<-brohn_store_object(store,bytes=charToRaw(enc2utf8(brohn_json(list(report=body)))),media_type="application/json")
  r<-brohn_put_entity(store,"report",body$id,body,project_id=d$project_id);original<-brohn_hash(r$body)
  j<-brohn_queue_emg_review(store,r$id,r$revision,original,f$selection);i<-brohn_emg_review_input(store,j)
  check("Exact original report, dataset, continuous segment and all four source objects are bound",length(i$source_objects)==4&&identical(i$binding$selection,f$selection)&&.brohn_mr_same(i$recording,f$recording))
  duplicate<-brohn_queue_emg_review(store,r$id,r$revision,original,f$selection)
  check("Identical source-bound burst window request is idempotent",identical(j$id,duplicate$id))
  for(k in c("report_hash","catalog_hash","dataset_catalog_hash","origin","project_id")){bad<-j;bad$request[[k]]<-"different";check(paste("Changed",k,"is refused"),rejects(brohn_emg_review_input(store,bad)))}
  bad<-j;bad$request$selection$segment_id<-"other";check("Unknown segment cannot borrow another saved cell",rejects(brohn_emg_review_input(store,bad)))
  bad<-j;bad$request$artifacts[[1]]$rows<-9;check("Changed complete artifact support is refused",rejects(brohn_emg_review_input(store,bad)))
  scratch<-file.path(folder,"direct-reader");dir.create(scratch);b<-brohn_analyse_emg_review(i,scratch)$emg_review
  csv<-utils::read.csv(file.path(scratch,"artifacts/emg-samples.csv"))
  check("Complete CSV preserves all10001 input clean RMS and exact source indices",nrow(csv)==10001&&identical(csv$source_sample_index,1000:11000)&&b$counts$complete_sample_artifact_rows==10004&&all(c("raw_uv","clean_uv","rms_uv")%in%names(csv)))
  check("Independent saved bursts retain exact durations and boundary flags",all(vapply(b$bursts,function(x)x$peak_rms_uv==1,logical(1)))&&identical(vapply(b$bursts,`[[`,numeric(1),"duration_s"),c(.75,.4,.75))&&identical(vapply(b$bursts,`[[`,logical(1),"boundary_truncated"),c(TRUE,FALSE,TRUE)))
  check("Unit conversion remains explicit and end boundary is not a fabricated sample",b$recording$source_unit=="mV"&&b$recording$scale_factor==1000&&b$unit=="uV"&&b$raw_available&&is.null(b$markers[[3]]$source_sample_index)&&is.null(b$markers[[3]]$rms_uv))
  for(k in c("recording","parameters","selection","features")){bad<-b;bad[[k]]<-list();check(paste("Altered returned",k,"is refused"),rejects(brohn_validate_emg_review(bad,i)))}
  bad<-b;bad$series$raw_uv[[1]]$points[[1]]$time_s<-999;check("SVG cannot accept a point beyond its source window",rejects(brohn_validate_emg_review(bad,i)))
  bad<-b;bad$verification<-list();check("Complete source verification cannot be omitted",rejects(brohn_validate_emg_review(bad,i)))
  bad<-b;bad$bursts[[1]]$duration_s<-.8;check("Burst duration cannot drift from exact active samples",rejects(brohn_validate_emg_review(bad,i)))
  bad<-b;bad$markers[[1]]$retained<-FALSE;check("An excluded boundary cannot become a supported burst",rejects(brohn_validate_emg_review(bad,i)))
  bad<-j;bad$request$selection$start_s<-"120";bad$request$selection$end_s<-"2";check("Reversed bounds refused before queue work",rejects(brohn_emg_review_input(store,bad)))
  for(width in c(900L,320L)) {
    svg<-brohn_emg_review_svg(b,width)
    check(paste(width,"SVG retains exact source and distinct accessibility identity"),grepl(original,svg,fixed=TRUE)&&grepl(paste0("mr-",width,"-title"),svg,fixed=TRUE)&&!grepl("NaN|Inf",svg))
    check(paste(width,"SVG exposes all input clean RMS components and excluded samples"),all(vapply(c('data-component="raw_uv"','data-component="clean_uv"','data-component="rms_uv"','data-retained="false"','data-threshold="0.5"'),function(x)grepl(x,svg,fixed=TRUE),logical(1))))
    writeLines(svg,file.path(folder,paste0("emg-",width,".svg")),useBytes=TRUE)
  }
  narrow<-f$selection;narrow$start_s<-"2.100000000000000001";narrow$end_s<-"2.2"
  nj<-brohn_queue_emg_review(store,r$id,r$revision,original,narrow);ni<-brohn_emg_review_input(store,nj);ns<-file.path(folder,"narrow");dir.create(ns);nb<-brohn_analyse_emg_review(ni,ns)$emg_review
  check("Clipped viewport keeps full half-open saved burst and metrics",nb$bursts[[1]]$time_s==2&&nb$bursts[[1]]$duration_s==.4&&!any(vapply(nb$markers,`[[`,logical(1),"in_view")))
  check("Decimal boundary beyond machine precision excludes exact2.1s sample",nb$rows[[1]]$time_s==2.102&&!.brohn_mr_in_window(2.1,narrow))
  base<-list(map_emg_highpass=20,map_emg_lowpass=NA_real_,map_emg_rms_window=.05,map_emg_edge=.25,map_emg_burst_enabled=FALSE,map_emg_threshold=NA_real_,map_emg_burst_duration=.1)
  check("Researcher mapping leaves absent threshold unconfigured",is.null(brohn_emg_input(base)$burst_threshold_uv)&&is.null(brohn_emg_input(base)$lowpass_hz))
  base$map_emg_burst_enabled<-TRUE
  check("Enabling a threshold requires an explicit value",rejects(brohn_emg_input(base)))
  base$map_emg_threshold<-2.5
  check("Researcher mapping preserves exact threshold and duration",brohn_emg_input(base)$burst_threshold_uv==2.5&&brohn_emg_input(base)$burst_min_duration_s==.1)
  brohn_cancel_job(store,nj$id)
  check("Original report and scientific results remain byte-identical",identical(original,brohn_hash(brohn_get_entity(store,"report",r$id)$body)))
  brohn_cancel_job(store,j$id)
  brohn_write_json_file(list(passed=TRUE,checks=as.list(checks),scope="Original hand-written software contract. Two cancelled queue guards; no scientific worker, detection or rescoring.",report_hash=original),file.path(folder,"results.json"))
  cat(length(checks),"emg saved-review domain checks passed\n")
})

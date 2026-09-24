# Original hand-authored saved-value contract; no scientific scorer is called.
source("R/platform-load.R",encoding="UTF-8");brohn_load(ui=TRUE)
source("R/platform-eda-continuous-review.R",encoding="UTF-8");source("R/platform-eda-continuous-review-views.R",encoding="UTF-8")
args<-commandArgs(trailingOnly=TRUE);folder<-if(length(args))normalizePath(args[[1]],winslash="/",mustWork=FALSE)else tempfile("brohn-eda-continuous-review-domain-")
stopifnot(!dir.exists(folder));dir.create(folder,recursive=TRUE)
checks<-character();check<-function(label,value){stopifnot(isTRUE(value));checks<<-c(checks,label);cat("PASS",label,"\n")}
rejects<-function(expr)inherits(try(force(expr),silent=TRUE),"try-error")
local({
  generated<-processx::run(.brohn_publication_python(),c("tests/workers/eda_continuous_review.py","--fixture",file.path(folder,"hand")),error_on_status=FALSE)
  stopifnot(generated$status==0);f<-brohn_read_json_file(file.path(folder,"hand/fixture.json"))
  store<-brohn_open_store(file.path(folder,"workspace"));on.exit(brohn_close_store(store),add=TRUE);brohn_initialise_library(store)
  d<-brohn_ingest_dataset(store,f$original_source$path,"Original hand-value eda contract","eda",origin="sample")
  d$body$metadata<-list(time_column="time",time_unit="s",sampling_rate=10,value_columns=list("conductance"),unit="S",parameters=f$parameters,origin_statement="Independent saved-value software fixture; no decomposition or human recording.")
  d<-brohn_put_entity(store,"dataset",d$id,d$body,project_id=d$project_id,expected_revision=d$revision)
  artifacts<-lapply(f$artifacts,function(a){o<-brohn_store_object(store,path=a$path,media_type="application/x-ndjson");c(o,a[c("kind","schema","tables","rows","provenance_sha256","complete")])})
  receipt<-list(schema="brohn-physiology-artifact-receipt/1.0",status="verified",artifacts=lapply(f$artifacts,function(a)c(a[c("kind","sha256","bytes","schema","tables","rows","provenance_sha256")],list(verified=TRUE))))
  body<-list(id="report-eda-continuous-hand",dataset_id=d$id,study_id=NULL,origin="sample",title="Original hand-value eda report",provenance=brohn_analysis_provenance(d$body,d$revision),
    analysis=list(kind="eda",modality="eda",source=list(sha256=d$body$source$hash),parameters=list(`recording-1`=f$parameters),
      recordings=list(f$recording),features=f$features,events=list(),artifacts=artifacts,artifact_verification=receipt))
  body$result_object<-brohn_store_object(store,bytes=charToRaw(enc2utf8(brohn_json(list(report=body)))),media_type="application/json")
  r<-brohn_put_entity(store,"report",body$id,body,project_id=d$project_id);original<-brohn_hash(r$body)
  j<-brohn_queue_eda_continuous_review(store,r$id,r$revision,original,f$selection);i<-brohn_eda_continuous_review_input(store,j)
  check("Exact original report, dataset, continuous segment and all four source objects are bound",length(i$source_objects)==4&&identical(i$binding$selection,f$selection)&&.brohn_ecr_same(i$recording,f$recording))
  duplicate<-brohn_queue_eda_continuous_review(store,r$id,r$revision,original,f$selection)
  check("Identical source-bound candidate window request is idempotent",identical(j$id,duplicate$id))
  for(k in c("report_hash","catalog_hash","dataset_catalog_hash","origin","project_id")){bad<-j;bad$request[[k]]<-"different";check(paste("Changed",k,"is refused"),rejects(brohn_eda_continuous_review_input(store,bad)))}
  bad<-j;bad$request$selection$segment_id<-"other";check("Unknown segment cannot borrow another saved cell",rejects(brohn_eda_continuous_review_input(store,bad)))
  bad<-j;bad$request$artifacts[[1]]$rows<-9;check("Changed complete artifact support is refused",rejects(brohn_eda_continuous_review_input(store,bad)))
  scratch<-file.path(folder,"direct-reader");dir.create(scratch);b<-brohn_analyse_eda_continuous_review(i,scratch)$eda_continuous_review
  csv<-utils::read.csv(file.path(scratch,"artifacts/eda-samples.csv"))
  check("Complete CSV preserves every clean tonic phasic value and exact source index",nrow(csv)==601&&identical(csv$source_sample_index,1000:1600)&&b$counts$complete_sample_artifact_rows==604&&all(c("clean_us","tonic_us","phasic_us")%in%names(csv)))
  check("Independent candidates retain exact peaks and nullable endpoints",identical(vapply(b$candidates,`[[`,numeric(1),"time_s"),c(11,21,49))&&is.null(b$candidates[[1]]$onset_time_s)&&is.null(b$candidates[[3]]$recovery_time_s)&&length(b$markers)==7)
  check("Unit conversion and conditional-amplitude denominator remain explicit",b$recording$source_unit=="S"&&b$recording$scale_factor==1e6&&b$unit=="uS"&&!b$raw_available&&b$counts$segment_amplitude_available==2)
  for(k in c("recording","parameters","selection","features")){bad<-b;bad[[k]]<-list();check(paste("Altered returned",k,"is refused"),rejects(brohn_validate_eda_continuous_review(bad,i)))}
  bad<-b;bad$series$clean_us[[1]]$points[[1]]$time_s<-999;check("SVG cannot accept a point beyond its source window",rejects(brohn_validate_eda_continuous_review(bad,i)))
  bad<-b;bad$verification<-list();check("Complete source verification cannot be omitted",rejects(brohn_validate_eda_continuous_review(bad,i)))
  bad<-b;bad$candidates[[2]]$rise_time_s<-9;check("Candidate timing cannot drift from exact source sample indices",rejects(brohn_validate_eda_continuous_review(bad,i)))
  bad<-b;bad$markers[[1]]$retained<-FALSE;check("An excluded endpoint cannot become a supported candidate",rejects(brohn_validate_eda_continuous_review(bad,i)))
  bad<-j;bad$request$selection$start_s<-"120";bad$request$selection$end_s<-"2";check("Reversed bounds refused before queue work",rejects(brohn_eda_continuous_review_input(store,bad)))
  for(width in c(900L,320L)) {
    svg<-brohn_eda_continuous_review_svg(b,width)
    check(paste(width,"SVG retains exact source and distinct accessibility identity"),grepl(original,svg,fixed=TRUE)&&grepl(paste0("ecr-",width,"-title"),svg,fixed=TRUE)&&!grepl("NaN|Inf",svg))
    check(paste(width,"SVG exposes all clean tonic phasic components and excluded samples"),all(vapply(c('data-component="clean_us"','data-component="tonic_us"','data-component="phasic_us"','data-retained="false"','data-marker="recovery"'),function(x)grepl(x,svg,fixed=TRUE),logical(1))))
    writeLines(svg,file.path(folder,paste0("eda-continuous-",width,".svg")),useBytes=TRUE)
  }
  narrow<-f$selection;narrow$start_s<-"20.100000000000000001";narrow$end_s<-"20.2"
  nj<-brohn_queue_eda_continuous_review(store,r$id,r$revision,original,narrow);ni<-brohn_eda_continuous_review_input(store,nj);ns<-file.path(folder,"narrow");dir.create(ns);nb<-brohn_analyse_eda_continuous_review(ni,ns)$eda_continuous_review
  check("Clipped viewport keeps complete saved candidate and nullable support",nb$candidates[[1]]$time_s==21&&nb$candidates[[1]]$amplitude_us==1.5&&!any(vapply(nb$markers,`[[`,logical(1),"in_view")))
  check("Decimal boundary beyond machine precision excludes exact20.1s sample",nb$rows[[1]]$time_s==20.2&&!.brohn_ecr_in_window(20.1,narrow))
  check("No absolute threshold line is invented",!grepl("data-threshold",brohn_eda_continuous_review_svg(b),fixed=TRUE))
  for(span in list(c(100,101),c(100000000000,.01+100000000000)))for(compact in c(FALSE,TRUE)) {
    ticks<-.brohn_ecr_axis_ticks(span[[1]],span[[2]],compact)
    check(paste("Distinct source-time labels",span[[1]],compact),!anyDuplicated(ticks$labels)&&identical(ticks$values,unique(seq(span[[1]],span[[2]],length.out=if(compact)3 else 5))))
    if(!is.null(ticks$offset))check("Long source time has an explicit unmodified base",identical(ticks$offset,span[[1]]))
  }
  brohn_cancel_job(store,nj$id)
  check("Original report and scientific results remain byte-identical",identical(original,brohn_hash(brohn_get_entity(store,"report",r$id)$body)))
  brohn_cancel_job(store,j$id)
  brohn_write_json_file(list(passed=TRUE,checks=as.list(checks),scope="Original hand-written software contract. Two cancelled queue guards; no scientific scoring worker, detection or rescoring.",report_hash=original),file.path(folder,"results.json"))
  cat(length(checks),"eda saved-review domain checks passed\n")
})

# Original hand-authored saved-value contract; no scientific scorer is called.
source("R/platform-load.R",encoding="UTF-8");brohn_load(ui=TRUE)
source("R/platform-eda-review.R",encoding="UTF-8");source("R/platform-eda-review-views.R",encoding="UTF-8")
args<-commandArgs(trailingOnly=TRUE);folder<-if(length(args))normalizePath(args[[1]],winslash="/",mustWork=TRUE)else tempfile("brohn-eda-review-domain-")
dir.create(folder,recursive=TRUE,showWarnings=FALSE)
checks<-character();check<-function(label,value){stopifnot(isTRUE(value));checks<<-c(checks,label);cat("PASS",label,"\n")}
rejects<-function(expr)inherits(try(force(expr),silent=TRUE),"try-error")
local({
  generated<-processx::run(brohn_python_profile("eda"),c("tests/workers/eda_review.py","--fixture",file.path(folder,"hand")),error_on_status=FALSE)
  stopifnot(generated$status==0);f<-brohn_read_json_file(file.path(folder,"hand/fixture.json"))
  store<-brohn_open_store(file.path(folder,"workspace"));on.exit(brohn_close_store(store),add=TRUE);brohn_initialise_library(store)
  d<-brohn_ingest_dataset(store,f$original_source$path,"Original hand-value EDA contract","eda",origin="sample")
  d$body$metadata<-list(time_column="time",time_unit="s",sampling_rate=25,value_columns=list("conductance"),unit="uS",parameters=f$parameters,origin_statement="Independent saved-value software fixture; no decomposition or human recording.")
  d<-brohn_put_entity(store,"dataset",d$id,d$body,project_id=d$project_id,expected_revision=d$revision)
  artifacts<-lapply(f$artifacts,function(a){o<-brohn_store_object(store,path=a$path,media_type="application/x-ndjson");c(o,a[c("kind","schema","tables","rows","provenance_sha256","complete")])})
  receipt<-list(schema="brohn-physiology-artifact-receipt/1.0",status="verified",artifacts=lapply(f$artifacts,function(a)c(a[c("kind","sha256","bytes","schema","tables","rows","provenance_sha256")],list(verified=TRUE))))
  body<-list(id="report-eda-hand",dataset_id=d$id,study_id=NULL,origin="sample",title="Original hand-value EDA report",provenance=brohn_analysis_provenance(d$body,d$revision),
    analysis=list(kind="eda",operation="eda_events",modality="eda",source=list(sha256=d$body$source$hash),parameters=list(`recording-1`=f$parameters),
      recordings=list(f$event),features=f$features,events=f$source_events,segments=list(list(status="computed")),source_masks=list(),artifacts=artifacts,artifact_verification=receipt))
  body$result_object<-brohn_store_object(store,bytes=charToRaw(enc2utf8(brohn_json(list(report=body)))),media_type="application/json")
  r<-brohn_put_entity(store,"report",body$id,body,project_id=d$project_id);original<-brohn_hash(r$body)
  j<-brohn_queue_eda_review(store,r$id,r$revision,original,f$binding$selection);i<-brohn_eda_review_input(store,j)
  check("Exact original report, dataset, measured event and all four source objects are bound",length(i$source_objects)==4&&identical(i$binding$selection,f$binding$selection)&&.brohn_er_same(i$event,f$event))
  duplicate<-brohn_queue_eda_review(store,r$id,r$revision,original,f$binding$selection)
  check("Identical source-bound event request is idempotent",identical(j$id,duplicate$id))
  for(k in c("report_hash","catalog_hash","dataset_catalog_hash","origin","project_id")){bad<-j;bad$request[[k]]<-"different";check(paste("Changed",k,"is refused"),rejects(brohn_eda_review_input(store,bad)))}
  bad<-j;bad$request$selection$event_id<-"other";check("Unknown event cannot borrow another saved cell",rejects(brohn_eda_review_input(store,bad)))
  bad<-j;bad$request$artifacts[[1]]$rows<-9;check("Changed complete artifact support is refused",rejects(brohn_eda_review_input(store,bad)))
  scratch<-file.path(folder,"direct-reader");dir.create(scratch);b<-brohn_analyse_eda_review(i,scratch)$eda_review
  csv<-utils::read.csv(file.path(scratch,"artifacts/eda-window-samples.csv"))
  check("Complete selected CSV preserves all 301 original indices and exact hand tonic values",nrow(csv)==301&&identical(csv$source_sample_index,450:750)&&all(csv$tonic_us==1+2*(450:750/25)))
  check("Original event feature values and denominators survive unchanged",.brohn_er_same(b$features,f$features)&&b$counts$complete_artifact_rows==1001)
  check("Onset, peak and half recovery use exact saved phasic values",identical(vapply(b$markers,`[[`,numeric(1),"phasic_us"),c(0,2,1)))
  for(k in c("event","features","parameters","range_s")){bad<-b;bad[[k]]<-list();check(paste("Altered returned",k,"is refused"),rejects(brohn_validate_eda_review(bad,i)))}
  bad<-b;bad$series$phasic_us[[1]]$points[[1]]$time_s<-999;check("SVG cannot accept a point beyond its source window",rejects(brohn_validate_eda_review(bad,i)))
  bad<-b;bad$verification<-list();check("Complete original artifacts cannot be omitted from verification",rejects(brohn_validate_eda_review(bad,i)))
  for(component in c("phasic_us","tonic_us","clean_us"))for(width in c(900L,320L)) {
    svg<-brohn_eda_review_svg(b,component,width)
    check(paste(component,width,"SVG retains exact source and distinct accessibility identity"),grepl(original,svg,fixed=TRUE)&&grepl(paste0("er-",component,"-",width,"-title"),svg,fixed=TRUE)&&!grepl("NaN|Inf",svg))
    writeLines(svg,file.path(folder,paste0(component,"-",width,".svg")),useBytes=TRUE)
  }
  bad<-b;bad$event$baseline_support$complete<-FALSE;svg<-brohn_eda_review_svg(bad)
  check("Incomplete baseline appears hatched without replacing saved measures",grepl('data-window="baseline" data-complete="false"',svg,fixed=TRUE)&&grepl("(incomplete)",svg,fixed=TRUE))
  bad<-b;bad$markers[[3]]$event_measure_usable<-FALSE;svg<-brohn_eda_review_svg(bad)
  check("Unavailable event recovery cannot appear as a valid selected marker",!grepl('data-marker="recovery" data-selected="true"',svg,fixed=TRUE))
  check("Original report and scientific results remain byte-identical",identical(original,brohn_hash(brohn_get_entity(store,"report",r$id)$body)))
  brohn_cancel_job(store,j$id)
  brohn_write_json_file(list(passed=TRUE,checks=as.list(checks),scope="Original hand-written software contract. One cancelled queue guard; no scientific worker, detection or rescoring.",report_hash=original),file.path(folder,"results.json"))
  cat(length(checks),"EDA saved-review domain checks passed\n")
})

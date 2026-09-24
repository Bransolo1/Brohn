# Original hand-authored saved-value contract; no scientific scorer is called.
source("R/platform-load.R",encoding="UTF-8");brohn_load(ui=TRUE)
source("R/platform-respiration-review.R",encoding="UTF-8");source("R/platform-respiration-review-views.R",encoding="UTF-8")
args<-commandArgs(trailingOnly=TRUE);folder<-if(length(args))normalizePath(args[[1]],winslash="/",mustWork=FALSE)else tempfile("brohn-respiration-review-domain-")
stopifnot(!dir.exists(folder));dir.create(folder,recursive=TRUE)
checks<-character();check<-function(label,value){stopifnot(isTRUE(value));checks<<-c(checks,label);cat("PASS",label,"\n")}
rejects<-function(expr)inherits(try(force(expr),silent=TRUE),"try-error")
local({
  generated<-processx::run(.brohn_publication_python(),c("tests/workers/respiration_review.py","--fixture",file.path(folder,"hand")),error_on_status=FALSE)
  stopifnot(generated$status==0);f<-brohn_read_json_file(file.path(folder,"hand/fixture.json"))
  store<-brohn_open_store(file.path(folder,"workspace"));on.exit(brohn_close_store(store),add=TRUE);brohn_initialise_library(store)
  d<-brohn_ingest_dataset(store,f$original_source$path,"Original hand-value respiration contract","respiration",origin="sample")
  d$body$metadata<-list(time_column="time",time_unit="s",sampling_rate=50,value_columns=list("signed_original_volume"),unit="L",parameters=f$parameters,origin_statement="Independent saved-value software fixture; no decomposition or human recording.")
  d<-brohn_put_entity(store,"dataset",d$id,d$body,project_id=d$project_id,expected_revision=d$revision)
  artifacts<-lapply(f$artifacts,function(a){o<-brohn_store_object(store,path=a$path,media_type="application/x-ndjson");c(o,a[c("kind","schema","tables","rows","provenance_sha256","complete")])})
  receipt<-list(schema="brohn-physiology-artifact-receipt/1.0",status="verified",artifacts=lapply(f$artifacts,function(a)c(a[c("kind","sha256","bytes","schema","tables","rows","provenance_sha256")],list(verified=TRUE))))
  body<-list(id="report-eda-hand",dataset_id=d$id,study_id=NULL,origin="sample",title="Original hand-value respiration report",provenance=brohn_analysis_provenance(d$body,d$revision),
    analysis=list(kind="respiration",modality="respiration",source=list(sha256=d$body$source$hash),parameters=list(`recording-1`=f$parameters),
      recordings=list(f$recording),features=list(),events=list(),artifacts=artifacts,artifact_verification=receipt))
  body$result_object<-brohn_store_object(store,bytes=charToRaw(enc2utf8(brohn_json(list(report=body)))),media_type="application/json")
  r<-brohn_put_entity(store,"report",body$id,body,project_id=d$project_id);original<-brohn_hash(r$body)
  j<-brohn_queue_respiration_review(store,r$id,r$revision,original,f$selection);i<-brohn_respiration_review_input(store,j)
  check("Exact original report, dataset, continuous segment and all four source objects are bound",length(i$source_objects)==4&&identical(i$binding$selection,f$selection)&&.brohn_rr_same(i$recording,f$recording))
  duplicate<-brohn_queue_respiration_review(store,r$id,r$revision,original,f$selection)
  check("Identical source-bound cycle window request is idempotent",identical(j$id,duplicate$id))
  for(k in c("report_hash","catalog_hash","dataset_catalog_hash","origin","project_id")){bad<-j;bad$request[[k]]<-"different";check(paste("Changed",k,"is refused"),rejects(brohn_respiration_review_input(store,bad)))}
  bad<-j;bad$request$selection$segment_id<-"other";check("Unknown segment cannot borrow another saved cell",rejects(brohn_respiration_review_input(store,bad)))
  bad<-j;bad$request$artifacts[[1]]$rows<-9;check("Changed complete artifact support is refused",rejects(brohn_respiration_review_input(store,bad)))
  scratch<-file.path(folder,"direct-reader");dir.create(scratch);b<-brohn_analyse_respiration_review(i,scratch)$respiration_review
  csv<-utils::read.csv(file.path(scratch,"artifacts/respiration-samples.csv"))
  check("Complete selected CSV preserves all6001 exact source indices",nrow(csv)==6001&&identical(csv$source_sample_index,1000:7000)&&b$counts$complete_sample_artifact_rows==6004)
  check("Independent saved phases retain2s inspiration3s expiration and1L amplitude",all(vapply(b$cycles,function(x)x$inspiration_s==2&&x$expiration_s==3&&x$duration_s==5&&x$amplitude==1,logical(1))))
  check("Source negative polarity and original unit remain explicit",b$parameters$polarity=="negative_inspiration"&&b$parameters$source_polarity_multiplier==-1&&b$recording$source_unit=="L")
  for(k in c("recording","parameters","selection")){bad<-b;bad[[k]]<-list();check(paste("Altered returned",k,"is refused"),rejects(brohn_validate_respiration_review(bad,i)))}
  bad<-b;bad$series[[1]]$points[[1]]$time_s<-999;check("SVG cannot accept a point beyond its source window",rejects(brohn_validate_respiration_review(bad,i)))
  bad<-b;bad$verification<-list();check("Complete source verification cannot be omitted",rejects(brohn_validate_respiration_review(bad,i)))
  bad<-b;bad$cycles[[1]]$inspiration_s<-2.2;check("Phase values cannot drift from exact extrema samples",rejects(brohn_validate_respiration_review(bad,i)))
  bad<-b;bad$markers[[1]]$retained<-FALSE;check("An excluded boundary cannot become a supported cycle",rejects(brohn_validate_respiration_review(bad,i)))
  bad<-j;bad$request$selection$start_s<-"120";bad$request$selection$end_s<-"2";check("Reversed bounds refused before queue work",rejects(brohn_respiration_review_input(store,bad)))
  for(width in c(900L,320L)) {
    svg<-brohn_respiration_review_svg(b,width)
    check(paste(width,"SVG retains exact source and distinct accessibility identity"),grepl(original,svg,fixed=TRUE)&&grepl(paste0("rr-",width,"-title"),svg,fixed=TRUE)&&!grepl("NaN|Inf",svg))
    check(paste(width,"SVG exposes saved inspiration/expiration and excluded samples"),all(vapply(c('data-phase="inspiration"','data-phase="expiration"','data-retained="false"'),function(x)grepl(x,svg,fixed=TRUE),logical(1))))
    writeLines(svg,file.path(folder,paste0("respiration-",width,".svg")),useBytes=TRUE)
  }
  narrow<-f$selection;narrow$start_s<-"10.000000000000000001";narrow$end_s<-"13"
  nj<-brohn_queue_respiration_review(store,r$id,r$revision,original,narrow);ni<-brohn_respiration_review_input(store,nj);ns<-file.path(folder,"narrow");dir.create(ns);nb<-brohn_analyse_respiration_review(ni,ns)$respiration_review
  check("Clipped viewport keeps full saved cycle boundaries and metrics",nb$cycles[[1]]$time_s==10&&nb$cycles[[1]]$end_time_s==15&&nb$cycles[[1]]$inspiration_s==2&&sum(vapply(nb$markers,`[[`,logical(1),"in_view"))==1L)
  check("Decimal boundary beyond machine precision excludes exact10s marker",!nb$markers[[1]]$in_view&&nb$rows[[1]]$time_s==10.02&&!.brohn_rr_in_window(.1,list(start_s="0.100000000000000001",end_s="1")))
  brohn_cancel_job(store,nj$id)
  check("Original report and scientific results remain byte-identical",identical(original,brohn_hash(brohn_get_entity(store,"report",r$id)$body)))
  brohn_cancel_job(store,j$id)
  brohn_write_json_file(list(passed=TRUE,checks=as.list(checks),scope="Original hand-written software contract. Two cancelled queue guards; no scientific worker, detection or rescoring.",report_hash=original),file.path(folder,"results.json"))
  cat(length(checks),"respiration saved-review domain checks passed\n")
})

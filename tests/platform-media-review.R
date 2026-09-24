# Real supervised derivation/review jobs plus independent authority failures.
source("R/platform-load.R",encoding="UTF-8");brohn_load(ui=TRUE)
args<-commandArgs(trailingOnly=TRUE);stopifnot(length(args)%in%c(2L,3L));resume<-length(args)==3L&&identical(args[[3]],"--resume-upstream")
folder<-normalizePath(args[[1]],winslash="/",mustWork=TRUE);media<-normalizePath(args[[2]],winslash="/",mustWork=TRUE)
stopifnot(startsWith(basename(folder),"brohn-media-review-domain-"),resume||!file.exists(file.path(folder,"workspace","catalog.sqlite")))
checks<-character();check<-function(label,value){if(!isTRUE(value))stop(label,call.=FALSE);checks<<-c(checks,label);cat("PASS",label,"\n")}
rejects<-function(expr)inherits(try(force(expr),silent=TRUE),"try-error")
local({
  store<-brohn_open_store(file.path(folder,"workspace"));on.exit(brohn_close_store(store),add=TRUE);brohn_initialise_library(store)
  run<-function(queued){force(queued);job<-brohn_claim_job(store,"media-domain",120);stopifnot(identical(job$id,queued$id));brohn_process_job(store,job,timeout_seconds=300)
    done<-brohn_get_job(store,job$id);if(done$status!="succeeded"){brohn_write_json_file(done,file.path(folder,paste0(job$id,"-failure.json")));stop(brohn_json(done$error),call.=FALSE)};done}
  if(!resume){
  parent<-brohn_ingest_dataset(store,media,"Original container media QA","video",origin="sample")
  parent_hash<-brohn_hash(parent$body);bytes_hash<-digest::digest(file=media,algo="sha256")
  job<-run(brohn_queue_audio_extraction(store,parent$id,parent$revision,parent_hash,parent$project_id))
  inventory<-brohn_audio_extraction_record(store,job$result$audio_extraction_id,parent$project_id)
  job<-run(brohn_queue_audio_extraction(store,parent$id,parent$revision,parent_hash,parent$project_id,"audio_extract",.brohn_ax_ref(inventory),1L))
  derived<-brohn_get_entity(store,"dataset",job$result$dataset_id)
  mapping<-list(unit="FS",channel_index=0L,origin_statement="Original generated software fixture; no human observations.",parameters=list(recipe="audio-praat-acoustics/1.0",pitch_floor_hz=75,pitch_ceiling_hz=600,frame_step_s=.01,spectral_frame_s=.025))
  derived<-brohn_curate_dataset(store,derived$id,mapping,derived$revision)
  job<-run(brohn_queue_dataset(store,derived$id));report<-brohn_get_entity(store,"report",job$result$report_id)
  job<-run(brohn_queue_audio_review(store,report$id,report$revision,brohn_hash(report$body),report$project_id,"0","4"))
  review<-brohn_audio_review_record(store,job$result$audio_review_id,report$id,report$project_id)
  }else{
    parents<-Filter(function(x)identical(x$body$modality,"video"),brohn_list_entities(store,"dataset"));stopifnot(length(parents)==1L);parent<-parents[[1L]]
    reports<-brohn_list_entities(store,"report");stopifnot(length(reports)==1L);report<-reports[[1L]]
    reviews<-brohn_list_entities(store,"audio_review");stopifnot(length(reviews)==1L);review<-brohn_audio_review_record(store,reviews[[1L]]$id,report$id,report$project_id)
    parent_hash<-brohn_hash(parent$body);bytes_hash<-digest::digest(file=media,algo="sha256")
  }
  original_report<-brohn_hash(report$body);original_review<-brohn_hash(review$body)
  source<-brohn_media_review_source(store,.brohn_mr_ref(review),review$project_id)
  check("Actual saved waveform retains exact parent video extraction and scientific report",identical(source$parent$id,parent$id)&&identical(source$report$id,report$id)&&identical(source$review$id,review$id)&&!is.null(source$ledger$hash))
  catalogs<-Filter(function(r)identical(r$body$request$operation,"media_tracks"),brohn_list_entities(store,"media_review"))
  if(!length(catalogs)){job<-run(brohn_queue_media_review(store,review$id,review$revision,original_review,review$project_id));catalog<-brohn_media_review_record(store,job$result$media_review_id,review$id,review$project_id)}else catalog<-brohn_media_review_record(store,catalogs[[1L]]$id,review$id,review$project_id)
  check("Actual supervised video inventory publishes without an invented frame",identical(catalog$body$request$operation,"media_tracks")&&length(catalog$body$result$tracks)==1L&&is.null(catalog$body$result$mapping))
  queued<-brohn_queue_media_review(store,review$id,review$revision,original_review,review$project_id,"media_review",.brohn_mr_ref(catalog),0L,8000L)
  input<-brohn_media_review_input(store,queued)
  roundtrip<-brohn_read_json_file(local({p<-file.path(folder,"canonical-request.json");brohn_write_json_file(queued,p);p}))
  check("Canonical JSON reordered implementation keys preserve exact named identity",.brohn_mr_same(input,brohn_media_review_input(store,roundtrip)))
  for(field in c("source","audio_ledger","audio_review","extraction","report")){bad<-queued;bad$request[[field]]$hash<-strrep("0",64);check(paste("Substituted",field,"source is refused"),rejects(brohn_media_review_input(store,bad)))}
  check("Cursor outside the original saved interval is refused",rejects(brohn_prepare_media_review(store,review$id,review$revision,original_review,review$project_id,"media_review",.brohn_mr_ref(catalog),0L,32000L)))
  check("Foreign project cannot borrow a saved waveform or media source",rejects(brohn_media_review_source(store,.brohn_mr_ref(review),"other-project")))
  job<-run(queued);saved<-brohn_media_review_record(store,job$result$media_review_id,review$id,review$project_id,TRUE)
  check("Actual native guarded publication preserves frame40 and complete160frame ledger",saved$body$result$coverage$frame$frame_index==40L&&saved$body$result$coverage$frame_count==160L&&length(saved$body$artifacts)==2L)
  ledger<-read.csv(brohn_object_path(store,saved$body$artifacts[[1L]]$hash),colClasses="character")
  check("Published complete ledger retains independent index PTS arithmetic",nrow(ledger)==160L&&identical(ledger$frame_index,as.character(0:159))&&all(as.numeric(ledger$pts_ticks)/1000==(0:159)/40))
  g<-brohn_begin_media_review_open(store,saved);on.exit(brohn_close_media_review(g),add=TRUE)
  opened<-NULL;for(i in 1:400){opened<-brohn_poll_media_review_open(store,g);if(!is.null(opened))break;Sys.sleep(.025)}
  check("Asynchronous complete byte verification opens exact original artifacts under native seals",!is.null(opened)&&identical(opened$id,saved$id)&&length(g$guards)>=5L)
  brohn_close_media_review(g);brohn_close_media_review(g);check("Idempotently closed native media handles cannot be reused",rejects(brohn_poll_media_review_open(store,g)))
  old_impl<-.brohn_media_review_loaded;assign(".brohn_media_review_loaded",lapply(old_impl,function(x)strrep("f",64)),envir=.GlobalEnv)
  historical<-brohn_media_review_record(store,saved$id,review$id,review$project_id,FALSE)
  check("Saved mapping remains readable after implementation update without rewriting its receipt",identical(brohn_hash(historical$body),brohn_hash(saved$body)))
  check("New worker request cannot execute under a substituted implementation",rejects(brohn_media_review_input(store,queued)))
  assign(".brohn_media_review_loaded",old_impl,envir=.GlobalEnv)
  retained_count<-length(brohn_list_entities(store,"media_review"))
  cancelled<-brohn_queue_media_review(store,review$id,review$revision,original_review,review$project_id,"media_review",.brohn_mr_ref(catalog),0L,8100L)
  brohn_cancel_job(store,cancelled$id)
  check("Cancelled media preparation publishes no cursor or image",identical(brohn_get_job(store,cancelled$id)$status,"cancelled")&&length(brohn_list_entities(store,"media_review"))==retained_count)
  original_input<-brohn_media_review_input;fired<-FALSE
  assign("brohn_media_review_input",function(store,job,verify=TRUE,require_current=TRUE){
    if(!verify&&RSQLite::sqliteIsTransacting(store$con)&&identical(job$operation,"media_review")&&!fired){fired<<-TRUE;DBI::dbExecute(store$con,"UPDATE entities SET project_id='media-qa-foreign' WHERE kind='dataset' AND id=?",params=list(parent$id))}
    original_input(store,job,verify,require_current)
  },envir=.GlobalEnv)
  on.exit(assign("brohn_media_review_input",original_input,envir=.GlobalEnv),add=TRUE)
  bad<-brohn_queue_media_review(store,review$id,review$revision,original_review,review$project_id,"media_review",.brohn_mr_ref(catalog),0L,8200L)
  claimed<-brohn_claim_job(store,"media-domain-revocation",120);stopifnot(identical(claimed$id,bad$id));brohn_process_job(store,claimed,timeout_seconds=300)
  failed<-brohn_get_job(store,bad$id);assign("brohn_media_review_input",original_input,envir=.GlobalEnv)
  check("Actual worker result refuses authority changed immediately before commit",fired&&identical(failed$status,"failed")&&length(brohn_list_entities(store,"media_review"))==retained_count)
  check("Failed publication rolls back ownership and preserves every original scientific source",identical(brohn_get_entity(store,"dataset",parent$id)$project_id,parent$project_id)&&
    identical(brohn_hash(brohn_get_entity(store,"dataset",parent$id,parent$revision)$body),parent_hash)&&identical(brohn_hash(brohn_get_entity(store,"report",report$id)$body),original_report)&&
    identical(brohn_hash(brohn_get_entity(store,"audio_review",review$id)$body),original_review)&&identical(digest::digest(file=media,algo="sha256"),bytes_hash))
  svg<-brohn_media_review_waveform_svg(review$body$result,saved$body$result,320L)
  check("Media SVG retains exact mapping and source without colliding with original waveform IDs",grepl('data-media-cursor-sample="8000"',svg,fixed=TRUE)&&grepl("mr-waveform-320-title",svg,fixed=TRUE)&&grepl(saved$body$request$source$hash,svg,fixed=TRUE))
  jobs<-lapply(brohn_list_jobs(store),function(j)j[c("id","operation","status","attempt","error")])
  brohn_write_json_file(list(passed=TRUE,checks=as.list(checks),jobs=jobs,source_hashes=.brohn_media_review_loaded,report_id=report$id,audio_review_id=review$id,media_review_id=saved$id,
    scope="Original generated pixels/audio and real workers; deliberate cancelled and publication-refusal jobs retained. No physical synchronization or scientific validity qualification."),file.path(folder,"results.json"))
  cat(length(checks),"media domain checks passed\n")
})

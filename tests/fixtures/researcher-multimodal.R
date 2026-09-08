# Original independent repeated-person data; only source reports are seeded.
# Selection, crosswalk review, contrasts, queueing and synthesis use the real UI.
args <- commandArgs(trailingOnly=TRUE)
stopifnot(length(args)==2L)
for (module in c("platform-core","platform-store","platform-methods","platform-delivery","platform-library","platform-analysis","platform-gaze","platform-vision","platform-neural","platform-multimodal","platform-jobs")) source(paste0("R/",module,".R"),encoding="UTF-8")
for (module in c("questionnaire-artifacts", "questionnaire-artifact-storage")) source(paste0("R/platform-",module,".R"),encoding="UTF-8")
source("tests/fixtures/platform-analysis-fixture.R")
local({
 store <- brohn_open_store(args[[1]]);on.exit(brohn_close_store(store),add=TRUE)
 output <- normalizePath(args[[2]],winslash="/",mustWork=TRUE)
 f <- researcher_analysis_fixture();f$design$id <- brohn_id("qa-mm-study");f$design$title <- paste("Original multimodal UI",format(Sys.time(),"%Y%m%d-%H%M%S"))
 brohn_put_entity(store,"study",f$design$id,f$design)
 results <- list()
 for (family in c("gaze","questionnaire")) {
   data <- if(family=="gaze")f$gaze else f$responses
   prefix <- if(family=="gaze")"gaze-" else "liking-"
   data$participant <- paste0(prefix,data$participant);data$session <- paste0(prefix,data$session)
   file <- file.path(output,paste0("original-",family,".csv"));utils::write.csv(data,file,row.names=FALSE,na="",fileEncoding="UTF-8")
   ingested <- brohn_ingest_dataset(store,file,paste(f$design$title,family),modality=family,study_id=f$design$id,origin="sample")
   accepted <- brohn_curate_dataset(store,ingested$id,if(family=="gaze")f$gaze_mapping else f$response_mapping,ingested$revision)
   job <- brohn_queue_dataset(store,accepted$id)
   # The integrated runtime's worker owns execution; do not steal other jobs.
   deadline <- Sys.time()+90
   repeat {
     job <- brohn_get_job(store,job$id)
     if(job$status%in%c("succeeded","failed","cancelled"))break
     if(Sys.time()>deadline)stop("Source analysis did not finish within90 seconds")
     Sys.sleep(.2)
   }
   if(job$status!="succeeded")stop(paste("Source worker failed",brohn_json(job$error)))
   report <- brohn_get_entity(store,"report",job$result$report_id)
   expected <- if(family=="gaze")10.833333333333334 else 1.375
   stopifnot(abs(report$body$analysis$contrasts[[1]]$estimate-expected)<1e-9)
   results[[family]] <- list(id=report$id,title=report$body$title,hash=brohn_hash(report$body),source_hash=accepted$body$source$hash)
 }
 writeLines(enc2utf8(brohn_json(list(origin="original_synthetic",study_id=f$design$id,title=f$design$title,reports=results),TRUE)),file.path(output,"fixture.json"),useBytes=TRUE)
 cat("PASS: two actual source worker reports match independent gaze/liking oracles\n")
})

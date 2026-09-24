# Reanalyse unchanged synthetic source revisions in a fresh external copy.
# The accepted paired browser fixture and its reports are never modified.
args<-commandArgs(trailingOnly=TRUE);stopifnot(length(args)==2L)
source("R/platform-load.R",encoding="UTF-8");brohn_load(ui=FALSE)
reference<-brohn_read_json_file(file.path(normalizePath(args[[1]],winslash="/",mustWork=TRUE),"fixture.json"))
folder<-normalizePath(args[[2]],winslash="/",mustWork=TRUE)
stopifnot(startsWith(basename(folder),"brohn-paired-aggregation-worker-"),!dir.exists(file.path(folder,"workspace")))
stopifnot(file.copy(reference$workspace,folder,recursive=TRUE))
local({
  store<-brohn_open_store(file.path(folder,"workspace"));on.exit(brohn_close_store(store))
  checks<-list();source_sha<-digest::digest(file="R/platform-analysis.R",algo="sha256")
  for(kind in c("questionnaire","gaze","stress","multimodal")) {
    ref<-reference$reports[[kind]];stopifnot(!is.null(ref))
    original<-brohn_get_entity(store,"report",ref$id);stopifnot(identical(brohn_hash(original$body),ref$hash))
    old_job<-brohn_get_job(store,sub("^report-","",original$id))
    before_source<-original$body$provenance$source$hash;before_design<-original$body$provenance$design_hash
    job<-if(kind=="multimodal")brohn_enqueue_job(store,"analyse_multimodal",old_job$request,paste0("paired-aggregation-review:",brohn_id("rerun")))else
      brohn_queue_dataset(store,original$body$provenance$dataset_id,original$body$provenance$dataset_revision,force=TRUE)
    claimed<-brohn_claim_job(store,"paired-aggregation-regression",300);stopifnot(identical(claimed$id,job$id))
    duration<-system.time(brohn_process_job(store,claimed,timeout_seconds=300))
    finished<-brohn_get_job(store,job$id);stopifnot(identical(finished$status,"succeeded"))
    result<-brohn_get_entity(store,"report",finished$result$report_id)
    # Compare every retained observation, parameter, contrast, p-value, interval,
    # quality field and limitation as canonical bytes, not an epsilon-only score.
    stopifnot(identical(brohn_json(result$body$analysis),brohn_json(original$body$analysis)),
      identical(brohn_json(result$body$provenance),brohn_json(original$body$provenance)),
      identical(result$body$origin,original$body$origin),
      identical(result$body$processing$code_hashes$`R/platform-analysis.R`,source_sha),
      identical(brohn_hash(brohn_get_entity(store,"report",ref$id)$body),ref$hash),
      identical(source_sha,digest::digest(file="R/platform-analysis.R",algo="sha256")))
    checks[[kind]]<-list(original_report=ref$id,original_report_hash=ref$hash,new_report=result$id,new_report_hash=brohn_hash(result$body),
      analysis_hash=brohn_hash(result$body$analysis),provenance_hash=brohn_hash(result$body$provenance),
      source_hash=before_source,design_hash=before_design,analysis_exact=TRUE,provenance_exact=TRUE,original_report_unchanged=TRUE,
      elapsed_s=unname(duration[["elapsed"]]),job_id=job$id)
    brohn_write_json_file(list(schema="brohn-paired-aggregation-worker-review/1.0",origin="original_synthetic",source_sha256=source_sha,reviews=checks),file.path(folder,"acceptance.json"))
    cat("PASS",kind,"actual worker preserves complete analysis/provenance in",duration[["elapsed"]],"seconds\n")
  }
})

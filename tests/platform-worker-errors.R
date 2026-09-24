# Exercise the actual Python error envelope through the R research-job adapter.
source("R/platform-load.R",encoding="UTF-8");brohn_load(ui=FALSE)
local({
  args<-commandArgs(trailingOnly=TRUE)
  folder<-if(length(args))args[[1L]]else tempfile("brohn-worker-errors-")
  stopifnot(startsWith(basename(folder),"brohn-worker-errors-"),!dir.exists(folder))
  dir.create(folder,recursive=TRUE);folder<-normalizePath(folder,winslash="/",mustWork=TRUE)
  source_path<-file.path(folder,"original-duplicate-clock.csv")
  writeLines(c("time,conductance","0,1","0,1.1","0.02,1.2"),source_path,useBytes=TRUE)
  sha<-digest::digest(file=source_path,algo="sha256")
  dataset<-list(id="dataset-duplicate-clock",title="Original invalid clock fixture",modality="eda",origin="sample",
    source=list(hash=sha,format="csv"),columns=list("time","conductance"),
    metadata=list(time_column="time",value_columns=list("conductance"),sampling_rate=100,time_unit="s",unit="uS",
      origin_statement="Original synthetic invalid-clock fixture; no participant recording."))
  scratch<-file.path(folder,"scratch");dir.create(scratch)
  error<-tryCatch({brohn_analyse_input(list(schema="brohn-analysis-input/1.0",operation="analyse_dataset",dataset=dataset,dataset_revision=1L,
    source_path=source_path,project_id="default"),scratch);NULL},error=identity)
  if (!file.exists(file.path(scratch,"physiology-result.json"))) stop("No Python error envelope: ",if(inherits(error,"error"))conditionMessage(error)else"analysis unexpectedly returned")
  envelope<-brohn_read_json_file(file.path(scratch,"physiology-result.json"))
  checks<-character();check<-function(label,ok){stopifnot(isTRUE(ok));checks<<-c(checks,label);cat("PASS",label,"\n")}
  check("Actual worker rejects duplicate timestamps with a structured error",identical(envelope$status,"error")&&is.null(envelope$modality)&&nzchar(envelope$error$message))
  check("Researcher receives the concrete scientific reason without a modality requirement",inherits(error,"error")&&
    identical(conditionMessage(error),paste("Scientific analysis needs attention:",envelope$error$message)))
  check("Worker error cannot become a scientific report",!file.exists(file.path(scratch,"published-result.json"))&&length(envelope$features)==0L&&length(envelope$artifacts)==0L)
  check("Original invalid source is preserved exactly",identical(digest::digest(file=source_path,algo="sha256"),sha))
  brohn_write_json_file(list(status="passed",checks=as.list(checks),worker_error=envelope$error,original_sha256=sha,
    source_hashes=stats::setNames(lapply(c("R/platform-jobs.R","scripts/workers/physiology.py"),function(p)digest::digest(file=p,algo="sha256")),c("R/platform-jobs.R","scripts/workers/physiology.py"))),file.path(folder,"results.json"))
})

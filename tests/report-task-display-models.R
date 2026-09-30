args<-commandArgs(TRUE);stopifnot(length(args)==3L)
packet<-normalizePath(args[[1L]],winslash="/",mustWork=TRUE);corpus<-normalizePath(args[[2L]],winslash="/",mustWork=TRUE);out<-args[[3L]]
stopifnot(!file.exists(out));dir.create(out,recursive=TRUE);out<-normalizePath(out,winslash="/")
config<-jsonlite::fromJSON(file.path(corpus,"config.json"),simplifyVector=FALSE);setwd(config$checkout)
source("R/platform-load.R",encoding="UTF-8");brohn_load(ui=FALSE)
source("R/platform-task-plots.R",encoding="UTF-8");source("R/platform-paired-plots.R",encoding="UTF-8")

local({
  checks<-list();passed<-FALSE;failure<-NULL
  on.exit(brohn_write_json_file(list(passed=passed,checks=checks,failure=failure,scope="Pure source-bound evidence builder/validator fixture, no store mutation/worker/publication/new scientific scoring/replay. Original native terminal exports were produced in the earlier corpus phase.",source_sha256=digest::digest(file=file.path(config$checkout,"R/platform-task-display.R"),algo="sha256")),file.path(out,"results.json")),add=TRUE)
  check<-function(label,x){if(!isTRUE(x))stop(label,call.=FALSE);checks[[length(checks)+1L]]<<-label}
  reject<-function(x)inherits(try(force(x),silent=TRUE),"try-error")
  implementation<-list(schema="brohn-task-display-implementation/0.1",profile="saved-task-display/0.1",
    sources=stats::setNames(list(digest::digest(file=file.path(config$checkout,"R/platform-task-display.R"),algo="sha256")),"R/platform-task-display.R"),
    runtime=list(R=as.character(getRversion()),jsonlite=as.character(utils::packageVersion("jsonlite")),digest=as.character(utils::packageVersion("digest"))))
  original_files<-list.files(corpus,recursive=TRUE,full.names=TRUE);original_files<-original_files[!dir.exists(original_files)]
  before<-stats::setNames(lapply(original_files,function(p)digest::digest(file=p,algo="sha256")),original_files)
  # Fail loudly if any builder/validator tries a scientific or journal operation.
  for(fn in c("brohn_task_score","brohn_gnat_score","brohn_sciat_window_score","brohn_import_task_trials","brohn_task_cohort","brohn_task_evidence_from_run",".brohn_delivery_replay"))if(exists(fn,mode="function"))assign(fn,function(...)stop("Forbidden scientific/replay call in pure artifact fixture"),envir=.GlobalEnv)
  tryCatch({
    sources<-list.files(corpus,pattern="^(native|import|repeat-import|cohort)-report[.]json$",recursive=TRUE,full.names=TRUE)
    for(file in sources){
      record<-brohn_read_json_file(file);report<-list(ref=list(kind="report",id=record$id,revision=record$revision,body_hash=brohn_hash(record$body),project_id=record$project_id),saved_body=record$body,complete_analysis=record$body$analysis)
      native<-if(basename(file)=="native-report.json")list(brohn_read_json_file(file.path(dirname(file),"native-terminal-evidence.json")))else list()
      evidence<-.brohn_td_build_evidence(report,native,implementation);catalog<-.brohn_td_catalog(evidence,report)
      check(paste("complete pure model validates",basename(dirname(file)),basename(file)),isTRUE(brohn_validate_task_display_evidence(evidence,report)))
      check(paste("bounded catalog hashes match exact models",basename(dirname(file)),basename(file)),length(catalog)==length(evidence$administrations)+length(evidence$cohort_models)&&all(vapply(catalog,function(c).brohn_td_sha(c$model_hash),logical(1))))
      key<-paste(basename(dirname(file)),sub("[.]json$","",basename(file)),sep="-")
      brohn_write_json_file(list(report=report,evidence=evidence,catalog=catalog,companion_catalog=.brohn_td_companion_catalog(report),qualification="Pure prepared-shape fixture only, not a published task_display entity."),file.path(out,paste0(key,".json")))
      bad<-evidence;bad$source$analysis_hash<-paste(rep("0",64),collapse="");check(paste("changed analysis binding refuses",key),reject(brohn_validate_task_display_evidence(bad,report)))
      if(length(evidence$administrations)){
        bad<-evidence;bad$administrations[[1L]]$plot_model$rows[[1L]]$profile_scored<-"true"
        check(paste("nonboolean profile flag refuses",key),reject(brohn_validate_task_display_evidence(bad,report)))
        bad<-evidence;bad$administrations[[1L]]$score_binding$hash<-paste(rep("0",64),collapse="")
        check(paste("changed original score refuses",key),reject(brohn_validate_task_display_evidence(bad,report)))
        score<-report$complete_analysis$task_scores[[1L]];score$counts$unregistered_science<-1L
        check(paste("unknown nested scientific field refuses",key),reject(.brohn_td_score(score)))
      }
    }
    after<-stats::setNames(lapply(original_files,function(p)digest::digest(file=p,algo="sha256")),original_files)
    check("every complete source/corpus byte is unchanged",identical(before,after));passed<-TRUE
  },error=function(e){failure<<-conditionMessage(e);stop(e)})
  cat(length(checks),"pure task display shape checks passed\n")
})

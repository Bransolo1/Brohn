# Independent R receiver replay of unchanged JavaScript-generated observations.
args<-commandArgs(trailingOnly=TRUE);stopifnot(length(args)%in%c(2L,3L))
source("R/platform-load.R",encoding="UTF-8");brohn_load(ui=FALSE)
source("R/platform-gnat.R",encoding="UTF-8")
compiled<-brohn_read_json_file(args[[1L]]);folder<-normalizePath(args[[2L]],winslash="/",mustWork=TRUE)
component_folder<-if(length(args)==3L)normalizePath(args[[3L]],winslash="/",mustWork=TRUE)else folder
checks<-character();check<-function(name,value){stopifnot(isTRUE(value));checks<<-c(checks,name);cat("PASS",name,"\n")}
fullpath<-file.path(folder,"complete-replay-events.json")
if(file.exists(fullpath)){
  events<-brohn_read_json_file(fullpath);result<-brohn_gnat_replay(compiled,events)
  check("All 384 JavaScript pure-state results pass independent R server replay",result$complete&&length(result$state$responses)==384L)
  outcomes<-vapply(result$state$responses,`[[`,character(1),"outcome")
  check("Independent replay preserves all four outcomes across full quotas",setequal(outcomes,c("hit","miss","false_alarm","correct_rejection")))
  check("Pure fixture is not qualified as a consented received session",!result$outer_session_qualified)
}else{
  complete<-brohn_read_json_file(file.path(folder,"complete-384.json"));replayed<-brohn_gnat_replay(compiled,complete$events)
  check("All actual 384 browser receipts pass unchanged independent R replay",replayed$complete&&length(replayed$state$responses)==384L)
  check("Actual browser result remains unqualified for outer consent/session authority",!replayed$outer_session_qualified)
  browser<-complete$result$responses
  check("All browser outcome and latency summaries equal independent R replay",all(vapply(seq_along(browser),function(i){
    r<-browser[[i]];s<-replayed$state$responses[[i]]
    identical(r$outcome,s$outcome)&&identical(r$response_code,s$response_code)&&.brohn_gnat_same(r$response_ms,s$response_ms)&&identical(r$correct,s$correct)
  },logical(1))))
  if(!identical(component_folder,folder)){
    prior<-brohn_read_json_file(file.path(folder,"late-after-seal.json"))
    old_error<-tryCatch({brohn_gnat_replay(compiled,prior$events);""},error=function(e)conditionMessage(e))
    check("Initial delayed-key receipt remains refused for its inconsistent interruption step identity",grepl("retained contradiction",old_error,fixed=TRUE))
  }
  labels<-c("held-and-first-response","late-after-seal","focus-loss")
  if(file.exists(file.path(component_folder,"release-wait-interruption.json")))labels<-c(labels,"release-wait-interruption")
  for(label in labels){
    evidence<-brohn_read_json_file(file.path(component_folder,paste0(label,".json")));result<-brohn_gnat_replay(compiled,evidence$events)
    check(paste(label,"preserves actual interrupted evidence without full eligibility"),!result$complete&&result$state$interrupted)
    if(label=="late-after-seal")check("Delayed contradictory key remains in separate interruption side evidence",!is.null(result$state$interruption$contradiction))
    if(label=="release-wait-interruption")check("Failed pre-onset wait preserves its original typed observations",!is.null(result$state$interruption$release_wait)&&length(result$state$responses)==0L)
  }
  for(label in c("durable-write-failure","refresh-refusal")){
    evidence<-brohn_read_json_file(file.path(component_folder,paste0(label,".json")))
    check(paste(label,"cannot provide a completed browser result"),is.null(evidence$result)&&brohn_text(evidence$error,1000))
  }
}
brohn_write_json_file(list(passed=TRUE,checks=as.list(checks),complete_folder=folder,component_folder=component_folder,domain_sha256=digest::digest(file="R/platform-gnat.R",algo="sha256"),
  scope="Independent existing R replay of original JavaScript evidence; no consent/server delivery or physical timing qualification."),file.path(component_folder,"independent-r-replay.json"))
cat(brohn_json(list(passed=TRUE,checks=length(checks))),"\n")

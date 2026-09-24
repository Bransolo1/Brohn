source("R/platform-core.R",encoding="UTF-8");source("R/platform-sciat-window.R",encoding="UTF-8");source("R/platform-sciat-window-delivery.R",encoding="UTF-8")
local({
  args<-commandArgs(trailingOnly=TRUE);folder<-args[[1L]];browser<-args[[2L]]
  compiled<-brohn_parse(paste(readLines(file.path(folder,"compiled.json"),warn=FALSE),collapse="\n"))
  data<-brohn_parse(paste(readLines(file.path(browser,"browser-journals.json"),warn=FALSE),collapse="\n"))
  checks<-character();check<-function(n,x){stopifnot(isTRUE(x));checks<<-c(checks,n);cat("PASS",n,"\n")}
  for(name in c("A","B","held-focus"))if(!is.null(data[[name]])){
    c<-compiled[[if(name=="B")"B"else"A"]];events<-data[[name]]$events;replayed<-brohn_sciat_window_replay(c,events)
    check(paste("Independent R replays actual Chrome received task evidence",name),identical(replayed$complete,data[[name]]$result$outcome=="completed"))
      check(paste("Exact first-response summaries preserved",name),length(replayed$state$responses)==length(data[[name]]$result$responses))
  }
  if(!is.null(data$reload))check("Actual reload retains a noncomplete original-clock journal and no new task events",
    !brohn_sciat_window_replay(compiled$A,data$reload$prior_events)$complete&&length(data$reload$events)==0L)
  writeLines(brohn_json(list(passed=TRUE,checks=as.list(checks),session_consent_service_scoring_qualification=FALSE),TRUE),file.path(browser,"independent-browser-replay.json"),useBytes=TRUE)
})

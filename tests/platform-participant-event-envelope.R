# Bounded fresh parse/replay proof of a previously generated original envelope.
source("R/platform-load.R",encoding="UTF-8");brohn_load()
local({
  args<-commandArgs(trailingOnly=TRUE);stopifnot(length(args)==2L)
  source_folder<-normalizePath(args[[1L]],winslash="/",mustWork=TRUE);output<-args[[2L]]
  stopifnot(!dir.exists(output));dir.create(output,recursive=TRUE)
  files<-c("R/platform-store.R","R/platform-delivery.R","R/platform-sciat-window-delivery.R","www/participant/event-batch.js",
    "tests/platform-participant-event-envelope.R")
  hashes<-function()setNames(lapply(files,function(f)digest::digest(file=f,algo="sha256")),files)
  before<-hashes();path<-file.path(source_folder,"selected-envelope.json");source_hash<-digest::digest(file=path,algo="sha256")
  selection<-brohn_read_json_file(file.path(source_folder,"envelope-selection.json"));bytes<-readBin(path,"raw",n=file.info(path)$size)
  req<-list(CONTENT_LENGTH=as.character(length(bytes)),CONTENT_TYPE="application/json",rook.input=list(read=function(n=-1L)bytes))
  elapsed<-function()unname(proc.time()[["elapsed"]]);start<-elapsed();parsed<-.brohn_delivery_request(req);parse_s<-elapsed()-start
  cat("Actual request parse/canonical check",parse_s,"seconds\n")
  start<-elapsed();canonical<-.brohn_store_json(parsed,maximum=4*1024^2);canonical_s<-elapsed()-start
  cat("Canonical encoder alone",canonical_s,"seconds\n")
  checks<-character();check<-function(label,value){stopifnot(isTRUE(value));checks<<-c(checks,label);cat("PASS",label,"\n")}
  check("Actual JS wire and R canonical envelopes fit their respective3MiB/4MiB bounds",length(bytes)==selection$wire_bytes&&length(bytes)<=3*1024^2&&nchar(canonical,type="bytes")<=4*1024^2)
  check("All selected original events preserve all5000 key observations",length(parsed$events)==selection$batch$last&&all(vapply(parsed$events,function(e)length(e$payload$data$keys)==5000L,logical(1))))
  registry<-brohn_read_json_file(file.path(source_folder,"original-A-registry.json"));compiled<-registry$protocols[[1L]]$compiled
  trial<-Filter(function(t)t$type=="task_trial",compiled$timeline)[[1L]];d<-parsed$events[[1L]]$payload$data
  start<-elapsed();replay<-.brohn_sciat_window_trial_replay(d,list(time=d$onset_ms,held=list()),trial,as.numeric(d$clock$value));replay_s<-elapsed()-start
  check("Maximum-key original first trial passes native key/response/phase replay",identical(replay$response_outcome,"response")&&replay$latency_ms==d$response_ms&&identical(replay$correct,d$correct))
  check("Original source bytes and loaded implementation sources are unchanged",identical(source_hash,digest::digest(file=path,algo="sha256"))&&identical(before,hashes()))
  brohn_write_json_file(list(passed=TRUE,checks=as.list(checks),wire_bytes=length(bytes),canonical_bytes=nchar(canonical,type="bytes"),
    request_parse_s=parse_s,canonical_encode_s=canonical_s,first_trial_replay_s=replay_s,exceeds_current_15s_runner_timeout=parse_s>15,
    source_hash=source_hash,source_hashes=before,scope="Exact existing synthetic3MiB envelope; actual R parser and single-trial native replay. No network round trip, full receiver publication, person or physical timing claim."),file.path(output,"results.json"))
})

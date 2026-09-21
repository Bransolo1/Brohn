# Diagnostic timings, not hardware-independent performance assertions.
args<-commandArgs(trailingOnly=TRUE);stopifnot(length(args)==2L)
source("R/platform-load.R",encoding="UTF-8");brohn_load()
store<-brohn_open_store(file.path(args[[1]],"workspace"));on.exit(brohn_close_store(store))
config<-brohn_read_json_file(file.path(args[[1]],"fixture.json"));report<-brohn_get_entity(store,"report",config$reports$ecg$report_id)
value<-Filter(function(x)identical(x$body$request$report_id,report$id)&&identical(x$body$operation,"signal_values_export"),brohn_list_entities(store,"signal_values",limit=100L))[[1L]]
measure<-function(fn){elapsed<-system.time(fn())[["elapsed"]];cat(elapsed,"seconds\n");elapsed}
timing<-list(report_hash_s=measure(function()brohn_hash(report$body)),
  current_context_s=measure(function()brohn_signal_values_input(store,list(operation=value$body$operation,request=value$body$request),verify=FALSE)),
  exact_record_s=measure(function()brohn_signal_values_record(store,value$id,verify=FALSE)),
  report_body_bytes=nchar(brohn_json(report$body),type="bytes"),report_id=report$id)
brohn_write_json_file(timing,args[[2]])

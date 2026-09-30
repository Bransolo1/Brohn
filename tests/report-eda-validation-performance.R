args<-commandArgs(TRUE);stopifnot(length(args)==3L)
checkout<-normalizePath(args[[1L]],winslash="/",mustWork=TRUE);bundle_path<-normalizePath(args[[2L]],winslash="/",mustWork=TRUE)
out<-args[[3L]];stopifnot(!file.exists(out));dir.create(out,recursive=TRUE);out<-normalizePath(out,winslash="/",mustWork=TRUE)
setwd(checkout);source("R/platform-load.R",encoding="UTF-8");brohn_load(ui=FALSE)
local({
 checks<-list();ok<-function(value,label){stopifnot(isTRUE(value));checks[[length(checks)+1L]]<<-label}
 outcome<-function(fn,a,b)tryCatch(list(value=fn(a,b)),error=function(e)list(error=conditionMessage(e)))
 old_source<-function(a,b)identical(brohn_json(a),brohn_json(b))
 old_render<-function(a,b)identical(brohn_hash(a),brohn_hash(b))
 values<-list(NULL,TRUE,FALSE,0,-0.0,1,1L,1.25,1e307,.Machine$double.xmin,list(),structure(list(),names=character()),
   list(a=1,b=list(TRUE,NULL)),list(b=list(TRUE,NULL),a=1),"0",enc2utf8("caf\u00e9"),I(c(1,2)),list(x="\\\"\n"))
 for(i in seq_along(values))for(j in seq_along(values)){
  ok(identical(outcome(.brohn_rpk_same,values[[i]],values[[j]]),outcome(old_source,values[[i]],values[[j]])),paste("source equality",i,j))
  ok(identical(outcome(.brohn_rp_same,values[[i]],values[[j]]),outcome(old_render,values[[i]],values[[j]])),paste("render equality",i,j))
 }
 invalid<-list(NA,NaN,Inf,-Inf,NA_character_,setNames(list(1,2),c("a","a")),setNames(list(1),""),matrix(1,1),structure(1,class="unsupported"),new.env())
 deep<-list(1);for(i in seq_len(65))deep<-list(deep);invalid[[length(invalid)+1L]]<-deep
 for(i in seq_along(invalid))for(pair in list(list(.brohn_rpk_same,old_source),list(.brohn_rp_same,old_render))){
  actual<-outcome(pair[[1L]],invalid[[i]],invalid[[i]]);expected<-outcome(pair[[2L]],invalid[[i]],invalid[[i]])
  ok(!is.null(actual$error)&&identical(actual,expected),paste("invalid JSON still refused",i,length(checks)))
 }
 bundle<-brohn_eda_read_json_file(bundle_path,128*1024^2)
 item<-Filter(function(x)identical(x$complete_analysis$kind,"eda"),bundle$reports)[[1L]]
 index<-which(vapply(bundle$eda_displays,function(x).brohn_rp_same(x$body$source$report_ref,item$ref),logical(1)))
 stopifnot(length(index)==1L)
 original_path<-bundle$eda_displays[[index]]$evidence$path;test_path<-file.path(out,"held-evidence.json")
 stopifnot(file.copy(original_path,test_path));Sys.chmod(test_path,"0600")
 bundle$eda_displays[[index]]$evidence$path<-test_path
 original_find<-.brohn_rpe_find;calls<-0L
 assign(".brohn_rpe_find",function(bundle,item){calls<<-calls+1L;original_find(bundle,item)},envir=.GlobalEnv)
 on.exit(assign(".brohn_rpe_find",original_find,envir=.GlobalEnv),add=TRUE)
 lookup<-.brohn_rpe_lookup(bundle);first<-lookup(item);second<-lookup(item)
 ok(calls==1L&&identical(first,second),"One full validation for repeated exact source within a render")
 bytes<-readBin(test_path,"raw",n=file.info(test_path)$size);mutated<-bytes;mutated[[length(mutated)-1L]]<-as.raw(32L)
 con<-file(test_path,"wb");writeBin(mutated,con);close(con)
 failure<-tryCatch({lookup(item);NULL},error=conditionMessage)
 ok(!is.null(failure)&&grepl("evidence bytes changed",failure),"Same-size evidence tampering refused on cache hit")
 con<-file(test_path,"wb");writeBin(bytes,con);close(con)
 ok(identical(first,lookup(item)),"Restored exact bytes retain exact validated evidence")
 other<-.brohn_rpe_lookup(bundle);ok(identical(first,other(item))&&calls==2L,"Separate render starts with full validation")
 changed<-item;changed$complete_analysis$features[[1L]]$value<-12345
 failure<-tryCatch({lookup(changed);NULL},error=conditionMessage)
 ok(!is.null(failure)&&calls==3L,"Changed scientific input cannot reuse cached validation")
 original_hash<-brohn_hash;analysis_hash_calls<-0L
 assign("brohn_hash",function(value){
  if(identical(value,item$complete_analysis,num.eq=FALSE,attrib.as.set=FALSE))analysis_hash_calls<<-analysis_hash_calls+1L
  original_hash(value)
 },envir=.GlobalEnv)
 on.exit(assign("brohn_hash",original_hash,envir=.GlobalEnv),add=TRUE)
 brohn_validate_eda_display_evidence(first$complete_evidence,item,first$body)
 ok(analysis_hash_calls==1L,"Complete analysis hashed once for all cell bindings in one validation")
 assign("brohn_hash",original_hash,envir=.GlobalEnv)
 evidence<-first$complete_evidence
 evidence$cells[[1L]]$model$binding$analysis_hash<-paste(rep("0",64),collapse="")
 evidence$cells[[1L]]$model_hash<-brohn_eda_value_hash(evidence$cells[[1L]]$model)
 failure<-tryCatch({brohn_validate_eda_display_evidence(evidence,item,first$body);NULL},error=conditionMessage)
 ok(!is.null(failure)&&grepl("original binding",failure),"Changed cell analysis binding rejected even with recomputed model hash")
 brohn_write_json_file(list(passed=TRUE,count=length(checks),checks=checks,scope="Exact equality regression and real saved model validation; declared call-count spy, no jobs/publication."),file.path(out,"results.json"))
 cat(length(checks),"checks passed\n")
})

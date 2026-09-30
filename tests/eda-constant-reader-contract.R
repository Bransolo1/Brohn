args<-commandArgs(trailingOnly=TRUE);stopifnot(length(args)==3L)
repo<-normalizePath(args[[1L]],winslash="/",mustWork=TRUE);fixtures<-normalizePath(args[[2L]],winslash="/",mustWork=TRUE)
out<-args[[3L]];stopifnot(!file.exists(out));dir.create(out,recursive=TRUE);out<-normalizePath(out,winslash="/")
setwd(repo);source("R/platform-load.R",encoding="UTF-8");brohn_load(ui=FALSE)
checks<-list();failure<-NULL;inputs<-list()
check<-function(ok,label){if(!isTRUE(ok))stop(label);checks[[length(checks)+1L]]<<-list(name=label,passed=TRUE)}
tryCatch({
 for(i in 1:6){
  directory<-file.path(fixtures,paste0("constant-",i));read<-function(n){p<-file.path(directory,paste0(n,".json"));inputs[[paste(i,n)]]<<-digest::digest(file=p,algo="sha256");brohn_eda_read_json_file(p,48*1024^2)}
  model<-read("model");request<-read("request");evidence<-read("evidence");catalog<-read("catalog");prepared_request<-read("prepared-request")
  brohn_validate_eda_continuous_review(model,request);check(TRUE,paste(i,"actual Python direct model passes R original bindings/coordinate/null/export validation"))
  check(identical(brohn_eda_value_hash(evidence$cells[[1L]]$model),evidence$cells[[1L]]$model_hash),paste(i,"Python model hash survives exact R JSON transport"))
  cell<-evidence$cells[[1L]]
  .brohn_ecr_validate_constant_model(cell$model,request$recording,request$parameters,request$features,request$artifacts,cell$selection,FALSE)
  check(TRUE,paste(i,"actual Python prepared model retains the frozen raw-description grammar"))
  check(.brohn_rpk_same(catalog,.brohn_edd_catalog(evidence)),paste(i,"Python catalog exactly matches R derivation"))
  check(evidence$coverage$coordinate_only_rows==request$recording$samples&&evidence$coverage$descriptive_only_cells==1&&evidence$coverage$unavailable_cells==0&&isTRUE(evidence$coverage$complete_coordinate_rows),paste(i,"coordinate-only coverage is structural without response inference"))
 }
},error=function(e)failure<<-conditionMessage(e))
brohn_write_json_file(list(schema="brohn-constant-reader-contract-tests/0.1",passed=is.null(failure),count=length(checks),checks=checks,error=failure,inputs=inputs,
 scope="Cross-language pure model/catalog validation of actual Python reader outputs over producer components. Minimal report bindings in supplied fixtures are synthetic. No native source/provenance/publication claim."),file.path(out,"results.json"))
if(!is.null(failure))stop(failure);cat("Passed",length(checks),"cross-language reader checks\n")

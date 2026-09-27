# Self-contained deterministic clock source/export/display checks.
# No research catalog, application service or device is opened by this suite.
source("R/platform-core.R",encoding="UTF-8")
project<-normalizePath(getwd(),winslash="/",mustWork=TRUE)
args<-commandArgs(trailingOnly=TRUE)
parent<-Sys.getenv("BROHN_QA_EVIDENCE_PARENT","")
if(length(args)>1L)stop("Supply at most one fresh external output directory.",call.=FALSE)
if(!length(args)&&(!nzchar(parent)||!dir.exists(parent)))stop("Run scripts/run-checks.R --test clock-python, or supply a fresh external output directory.",call.=FALSE)
folder<-if(length(args))args[[1L]]else tempfile("clock-python-",tmpdir=parent)
folder<-normalizePath(folder,winslash="/",mustWork=FALSE)
if(tolower(folder)==tolower(project)||startsWith(tolower(folder),paste0(tolower(project),"/")))stop("Choose evidence outside the source repository.",call.=FALSE)
if(file.exists(folder))stop("Choose a new evidence directory; existing evidence is never overwritten.",call.=FALSE)
dir.create(folder,recursive=TRUE,showWarnings=FALSE)
folder<-normalizePath(folder,winslash="/",mustWork=TRUE)
stopifnot(!startsWith(tolower(folder),paste0(tolower(project),"/")))
python<-Sys.getenv("BROHN_PYTHON_METHODS","")
if(!nzchar(python)||!file.exists(python))stop("Configure BROHN_PYTHON_METHODS with the installed methods Python executable; this suite has no local fallback path.",call.=FALSE)
python<-normalizePath(python,winslash="/",mustWork=TRUE)
rscript<-file.path(R.home("bin"),if(.Platform$OS.type=="windows")"Rscript.exe"else"Rscript")
tests<-c("affine","source","preview","events","window","window-worker","plot","plot-worker")
paths<-c(file.path("tests",paste0("clock-",tests,".py")),"tests/clock_test_support.py","tests/clock-json-roundtrip.R",
 "tests/fixtures/researcher-linked-review.py","tests/platform-clock-python.R","R/platform-core.R",
 list.files("scripts/workers",pattern="\\.py$",full.names=TRUE))
hashes<-function()setNames(lapply(paths,function(path)digest::digest(file=path,algo="sha256")),paths)
before<-hashes();ledger<-list(schema="brohn-clock-python-tests/0.1",passed=FALSE,
 scope="Synthetic arithmetic/source/event/preview/window/display and actual child/JSON interoperability only. No R catalog/publication, hosted authority, connected UI or physical device qualification.",
 implementation=before,results=list())
save<-function()writeLines(enc2utf8(brohn_json(ledger,TRUE)),file.path(folder,"results.json"),useBytes=TRUE)
save()
for(name in tests){
 stdout<-file.path(folder,paste0(name,"-stdout.log"));stderr<-file.path(folder,paste0(name,"-stderr.log"))
 began<-Sys.time()
 child<-tryCatch(processx::run(python,c("-B",file.path("tests",paste0("clock-",name,".py")),file.path(folder,name)),
   wd=project,timeout=240,stdout=stdout,stderr=stderr,error_on_status=FALSE,cleanup_tree=TRUE,windows_hide_window=TRUE,
   env=c("current",BROHN_TEST_RSCRIPT=rscript,PYTHONDONTWRITEBYTECODE="1")),error=function(e)list(status=NULL,error=conditionMessage(e)))
 receipt_path<-file.path(folder,name,"results.json")
 receipt<-if(file.exists(receipt_path))jsonlite::fromJSON(receipt_path,simplifyVector=FALSE)else NULL
 unchanged<-identical(before,hashes())
 passed<-!is.null(child$status)&&child$status==0L&&!is.null(receipt)&&isTRUE(receipt$passed)&&unchanged
 ledger$results[[length(ledger$results)+1L]]<-list(id=name,passed=passed,exit_code=child$status,error=child$error,
   tests=if(is.null(receipt))NULL else brohn_default(receipt$tests,brohn_default(receipt$groups,receipt$test_groups)),
   duration_s=as.numeric(difftime(Sys.time(),began,units="secs")),sources_unchanged=unchanged,
   receipt=if(is.null(receipt))NULL else list(path=paste0(name,"/results.json"),sha256=digest::digest(file=receipt_path,algo="sha256")))
 save();cat(if(passed)"PASS"else"FAIL",name,"\n");flush.console()
 if(!unchanged)stop("Source changed during qualification; choose a stable checkout.",call.=FALSE)
}
ledger$passed<-all(vapply(ledger$results,function(x)isTRUE(x$passed),logical(1)));save()
if(!ledger$passed)stop("Clock Python checks failed; retained evidence: ",folder,call.=FALSE)
cat("Clock Python suite passed; retained evidence:",folder,"\n")

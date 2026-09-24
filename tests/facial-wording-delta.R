# A labelled display-only continuation of the accepted researcher journey.
source("R/platform-load.R",encoding="UTF-8");brohn_load(ui=TRUE)
args<-commandArgs(trailingOnly=TRUE);stopifnot(length(args)==2L)
folder<-normalizePath(args[[1]],winslash="/",mustWork=TRUE);browser<-normalizePath(args[[2]],winslash="/",mustWork=TRUE)
before<-new.env(parent=globalenv());sys.source(file.path(folder,"before-views.R"),envir=before)
after<-new.env(parent=globalenv());sys.source("R/platform-facial-expression-views.R",envir=after)
old<-readLines(file.path(folder,"before-views.R"),warn=FALSE);new<-readLines("R/platform-facial-expression-views.R",warn=FALSE)
stopifnot(length(old)==length(new),sum(old!=new)==1L)
expected<-"Selected model and shared FFmpeg files, Py-Feat source files and dependency versions are checked before inference."
stopifnot(any(grepl(expected,new,fixed=TRUE)),!any(grepl("dependency and runtime bytes",new,fixed=TRUE)))
receipt<-brohn_read_json_file(file.path(browser,"results.json"));stopifnot(isTRUE(receipt$passed),identical(digest::digest(file=file.path(folder,"before-views.R"),algo="sha256"),receipt$code_hashes[["R/platform-facial-expression-views.R"]]))
variables<-c("BROHN_PYTHON_FACIAL_AU","BROHN_FACIAL_MODEL_DIR","BROHN_FACIAL_FFMPEG_DIR");previous<-Sys.getenv(variables,unset=NA_character_)
for(v in variables)do.call(Sys.setenv,stats::setNames(list(folder),v))
mapping<-as.character(after$brohn_facial_mapping_ui(list(profile=.brohn_facial_profile)))
stopifnot(grepl(expected,mapping,fixed=TRUE),grepl("Optional installation configured",mapping,fixed=TRUE))
Sys.unsetenv(variables);unconfigured<-as.character(after$brohn_facial_mapping_ui(list(profile=.brohn_facial_profile)))
stopifnot(grepl("Optional installation needs setup",unconfigured,fixed=TRUE))
for(v in variables)if(is.na(previous[[v]]))Sys.unsetenv(v)else do.call(Sys.setenv,stats::setNames(list(previous[[v]]),v))
a<-brohn_read_json_file(file.path(browser,"report-1.json"))$analysis
stopifnot(identical(as.character(before$brohn_facial_report_ui(a)),as.character(after$brohn_facial_report_ui(a))))
brohn_write_json_file(list(passed=TRUE,checks=list("Exactly one line changed from the browser-qualified view file","Setup wording distinguishes file-byte checks from dependency-version checks","Configured and missing-installation render paths retain their correct state","Saved native result rendering remains byte-identical"),
  joined_browser_sha256=digest::digest(file=file.path(browser,"results.json"),algo="sha256"),before_sha256=digest::digest(file=file.path(folder,"before-views.R"),algo="sha256"),after_sha256=digest::digest(file="R/platform-facial-expression-views.R",algo="sha256"),
  scope="Display text only; no worker, queue, new inference, report alteration or full browser rerun. Other team changes remain independently qualified."),file.path(folder,"results.json"))
cat("PASS4 focused wording/render continuation checks\n")

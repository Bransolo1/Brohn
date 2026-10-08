local({
# Actual brohn_load/ui and brohn_tasks_ui, no app service or scientific store.
args<-commandArgs(trailingOnly=TRUE);stopifnot(length(args)==2L)
checkout<-normalizePath(args[[1]],winslash="/",mustWork=TRUE)
out<-normalizePath(args[[2]],winslash="/",mustWork=FALSE)
stopifnot(!dir.exists(out));dir.create(out,recursive=TRUE)
stopifnot(!file.exists(file.path(out,"RESULTS.json")))
before<-getwd();setwd(checkout);on.exit(setwd(before),add=TRUE)
env<-new.env(parent=globalenv());start<-proc.time()[["elapsed"]]
source("R/platform-load.R",local=env,encoding="UTF-8")
env$brohn_load(env,ui=TRUE)
checks<-list()
save<-function(status)jsonlite::write_json(list(status=status,checks=checks,elapsed_s=proc.time()[["elapsed"]]-start,
  R=R.version.string,shiny=as.character(packageVersion("shiny")),htmltools=as.character(packageVersion("htmltools")),
  scope="Actual source-loaded Tasks UI serialization and host registry state only; no connected app/browser/science/store/service acceptance.",
  sources=lapply(c("R/platform-load.R","R/platform-task-views.R","R/platform-method-evidence.R","R/platform-method-evidence-host.R","R/platform-method-evidence-views.R","registry/method-evidence-0.2.json"),
    function(p)list(path=p,sha256=digest::digest(file=p,algo="sha256")))),file.path(out,"RESULTS.json"),auto_unbox=TRUE,pretty=TRUE,null="null")
ok<-function(name,value){checks[[length(checks)+1L]]<<-list(name=name,passed=isTRUE(value));save(if(isTRUE(value))"running"else"failed");if(!isTRUE(value))stop(name,call.=FALSE)}
refuse<-function(name,expr){caught<-tryCatch({force(expr);FALSE},error=function(e)TRUE);ok(name,caught)}
html<-function(x)as.character(htmltools::renderTags(x)$html)
state<-get(".brohn_method_evidence_app",envir=env)
ok("Full UI load registers exact pinned ready metadata",state$status=="ready"&&state$ref$sha256=="cd63ffb8eaa1a2c73b08dddd93573c5fedeb266f6cad8aadc22c5759b22dd9b0")
ok("Registry state bindings are locked",environmentIsLocked(state)&&bindingIsLocked("registry",state))
refuse("Captured registry cannot be edited through its state",state$registry$claims[[1]]$claim$title<-"changed")
profiles<-env$brohn_task_profiles();all_html<-character()
for(profile in names(profiles)){
  design<-env$brohn_new_design(template="blank")
  design$blocks<-list(env$brohn_task_new(profile))
  before_design<-env$brohn_json(design)
  result<-html(env$brohn_tasks_ui(design))
  stem<-gsub("[^a-zA-Z0-9_-]","_",profile)
  writeLines(enc2utf8(result),file.path(out,paste0(stem,".html")),useBytes=TRUE)
  all_html<-c(all_html,result)
  ok(paste(profile,"actual Tasks view has scoped evidence and original reference"),
     grepl("Method evidence is under review",result,fixed=TRUE)&&grepl("not an evidence snapshot saved with this study",result,fixed=TRUE)&&
     grepl(htmltools::htmlEscape(profiles[[profile]]$source,attribute=TRUE),result,fixed=TRUE)&&grepl("Original procedure reference",result,fixed=TRUE))
  ok(paste(profile,"view retains saved task and editable controls"),identical(before_design,env$brohn_json(design))&&grepl("task_title_1",result,fixed=TRUE)&&grepl("remove_task",result,fixed=TRUE))
}
ok("All seven registered profiles were rendered",length(all_html)==7L)
ok("No approved/validated badge is fabricated",!any(grepl('class="[^"]*(qualified|approved|validated)',all_html,perl=TRUE)))
ok("AAT retains keyboard and joystick interpretation boundary",grepl("not physical joystick AAT",all_html[[3]],fixed=TRUE))
ok("SC-IAT retains its original proceedings link",grepl("2007-proceedings.pdf#page=149",all_html[[6]],fixed=TRUE))
ok("Task headings and material content are escaped",{
 d<-env$brohn_new_design(template="blank");d$blocks<-list(env$brohn_task_new(names(profiles)[[1]]));d$blocks[[1]]$title<-'<script>alert("task")</script>'
 h<-html(env$brohn_tasks_ui(d));!grepl('<script>alert(',h,fixed=TRUE)&&grepl('&lt;script&gt;',h,fixed=TRUE)})
unknown<-html(env$brohn_method_evidence_task_ui("future-task/9.0","https://example.test/original",state))
ok("Valid registry unknown exact profile has explicit missing-entry state",grepl("No option-level evidence entry",unknown,fixed=TRUE)&&!grepl("reference_loading_failed",unknown,fixed=TRUE)&&grepl("https://example.test/original",unknown,fixed=TRUE))
ok("Unsupported exact option remains isolated",length(env$brohn_method_evidence_cards(state$registry,names(profiles)[[1]],"/unknown")$cards)==0L)
fixture<-file.path(out,"owned-fixtures");dir.create(fixture,showWarnings=FALSE)
missing<-env$brohn_method_evidence_host_load(fixture)
missing_html<-html(env$brohn_method_evidence_task_ui(names(profiles)[[1]],profiles[[1]]$source,missing))
ok("Missing packaged registry is a loading failure",missing$status=="reference_loading_failed"&&missing$error_code=="registry_missing"&&grepl("could not be loaded",missing_html,fixed=TRUE))
ok("Loading failure is not missing method evidence",!grepl("No option-level evidence entry",missing_html,fixed=TRUE)&&grepl("not a statement that this procedure has no evidence",missing_html,fixed=TRUE))
ok("Loading failure retains safe original source",grepl(htmltools::htmlEscape(profiles[[1]]$source,attribute=TRUE),missing_html,fixed=TRUE))
dir.create(file.path(fixture,"registry"),showWarnings=FALSE)
writeLines('{"schema":"corrupt"}',file.path(fixture,"registry","method-evidence-0.2.json"),useBytes=TRUE)
corrupt<-env$brohn_method_evidence_host_load(fixture)
ok("Corrupt/mismatched registry is refused without a fallback",corrupt$status=="reference_loading_failed"&&corrupt$error_code=="registry_rejected"&&is.null(corrupt$registry))
saved_state<-state$registry
ok("An independently rejected load cannot mutate pinned ready metadata",identical(state$registry,saved_state)&&state$status=="ready")
for(url in c("javascript:alert(1)","data:text/html,<script>alert(1)</script>","file:///private","http://example.test/plain",'https://example.test/<script>')){
  h1<-html(env$brohn_method_evidence_task_ui("future-task/9.0",url,state))
  h2<-html(env$brohn_method_evidence_task_ui(names(profiles)[[1]],url,missing))
  ok(paste("Unsafe original URL withheld",url),!grepl('href=',h1,fixed=TRUE)&&!grepl('href=',h2,fixed=TRUE))
}
ok("Unknown method string is escaped in missing evidence view",{h<-html(env$brohn_method_evidence_task_ui('<img src=x onerror=alert(1)>',NULL,state));!grepl('<img src=x',h,fixed=TRUE)&&grepl('&lt;img',h,fixed=TRUE)})
worker_env<-new.env(parent=globalenv())
env$brohn_load(worker_env,ui=FALSE)
ok("Worker-only load registers reader without loading app reference state",exists("brohn_method_evidence_read",envir=worker_env,inherits=FALSE)&&!exists(".brohn_method_evidence_app",envir=worker_env,inherits=FALSE))
task_text<-paste(readLines("R/platform-task-views.R",warn=FALSE),collapse="\n")
ok("General design view has no constructor evidence insertion",!grepl("comparison-starter-order",task_text,fixed=TRUE)&&!grepl("brohn-design/1.0.0",task_text,fixed=TRUE))
label_text<-paste(c(readLines("R/platform-views.R",warn=FALSE),readLines("R/platform-guidance-views.R",warn=FALSE)),collapse="\n")
ok("Three entry labels now say detected RR",!grepl('"ECG / HRV"',label_text,fixed=TRUE)&&length(regmatches(label_text,gregexpr('"ECG / detected RR"',label_text,fixed=TRUE))[[1]])==3L)
ok("Guidance modality value remains ecg",identical(env$.brohn_guidance_measure_labels[["ecg"]],"ECG / detected RR"))
ok("Registry Git rule preserves exact bytes",any(grepl('^/registry/\\*\\.json -text whitespace=cr-at-eol$',readLines(".gitattributes",warn=FALSE))))
save("passed")
cat(length(checks),"host checks passed in",round(proc.time()[["elapsed"]]-start,3),"seconds\n")

})

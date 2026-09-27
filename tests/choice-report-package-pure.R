# Pure rendering of generated prepared artifacts; scientific/replay entry points fail fast.
# Rscript tests/choice-report-package-pure.R REPO PREPARED_DIR FRESHOUT PYTHON
args<-commandArgs(TRUE);stopifnot(length(args)==4L)
repo<-normalizePath(args[[1L]],winslash="/",mustWork=TRUE)
fixtures<-normalizePath(args[[2L]],winslash="/",mustWork=TRUE);out<-args[[3L]];python<-normalizePath(args[[4L]],winslash="/",mustWork=TRUE)
stopifnot(!file.exists(out));dir.create(out,recursive=TRUE);out<-normalizePath(out,winslash="/");setwd(repo)
source("R/platform-load.R",encoding="UTF-8");brohn_load(ui=FALSE)
owned<-c("platform-report-package-tables.R","platform-report-package-tasks.R","platform-report-package-choice.R","platform-report-package-render.R")
paths<-c(stats::setNames(file.path(repo,"R",owned),paste0("R/",owned)),stats::setNames(c("scripts/workers/report_package_archive.py","scripts/workers/report_package_raster.py"),c("scripts/workers/report_package_archive.py","scripts/workers/report_package_raster.py")))
hashes<-lapply(paths,function(p)digest::digest(file=p,algo="sha256"))
implementation<-list(schema="brohn-report-package-implementation/0.1",profile="static-complete-findings/0.1",sources=hashes,
 runtime=list(R=as.character(getRversion()),jsonlite=as.character(packageVersion("jsonlite")),htmltools=as.character(packageVersion("htmltools")),Python=brohn_parse(processx::run(python,c("-c","import json,platform; print(json.dumps(dict(implementation=platform.python_implementation(),version=platform.python_version())))"))$stdout),Pillow=trimws(processx::run(python,c("-c","import PIL; print(PIL.__version__)"))$stdout)),
 archive_python=python,archive_script=normalizePath("scripts/workers/report_package_archive.py",winslash="/"),raster_script=normalizePath("scripts/workers/report_package_raster.py",winslash="/"))
for(fn in c("brohn_maxdiff_fit","brohn_maxdiff_analysis","brohn_import_maxdiff_analysis","brohn_analyse_runs","brohn_score_run_maxdiff","brohn_task_score","brohn_gnat_score","brohn_sciat_window_score","brohn_import_task_trials","brohn_task_cohort","brohn_task_evidence_from_run",".brohn_delivery_replay","brohn_score_scales","brohn_build_explicit_distributions"))assign(fn,function(...)stop("Scientific or journal replay forbidden in pure assembly"),envir=.GlobalEnv)
make_bundle<-function(f,task=NULL,distribution=NULL,mode="package_aliases"){
 choice<-f$choice_display;report<-f$report;sections<-list();prepared<-list()
 add<-function(adapter,ref,selector,display,resolve=NULL){s<-list(id=paste0("section-",length(sections)+1L),adapter=adapter,adapter_version="0.1",source_report_ref=report$ref,source_ref=ref,selector=selector,display=display,order=length(sections)+1L)
  if(!is.null(resolve))s<-resolve(s)$section
  if(adapter=="explicit-distribution")s$resolved_group_ids<-lapply(distribution$body$result$groups,`[[`,"id")
  sections[[length(sections)+1L]]<<-s
 }
 if(!is.null(distribution)){
  add("explicit-distribution",distribution$ref,list(scope="all_groups"),list(pages="all"))
  prepared[[length(prepared)+1L]]<-list(adapter="explicit-distribution",source_report_ref=report$ref,prepared_ref=distribution$ref,implementation_ref=distribution$body$preparation_implementation_ref)
 }
 if(!is.null(task)){
  for(adapter in c("task-scores","task-trials"))add(adapter,task$ref,list(scope="all_administrations"),if(adapter=="task-scores")list(pages="all")else list(pages="all",measure="profile_default",trial_scope="all",charts="profile_default"),function(s)brohn_resolve_task_report_section(s,task$body$catalog))
  prepared[[length(prepared)+1L]]<-list(adapter="task-display",source_report_ref=report$ref,prepared_ref=task$ref,implementation_ref=list(profile=task$body$implementation$profile,hash=brohn_hash(task$body$implementation)))
 }
 for(adapter in c("choice-counts","choice-utilities"))add(adapter,choice$ref,list(scope="all_exercises"),list(pages="all",page_numbers=list()),function(s)brohn_resolve_choice_report_section(s,choice$body$catalog))
 prepared[[length(prepared)+1L]]<-list(adapter="choice-display",source_report_ref=report$ref,prepared_ref=choice$ref,implementation_ref=list(profile=choice$body$implementation$profile,hash=brohn_hash(choice$body$implementation)))
 selection<-list(schema="brohn-report-package-selection/0.2",id="selection-published-pure",intent_ref=list(kind="report_package_intent",id="pure-published-intent",revision=1L,body_hash=brohn_hash("pure selection fixture"),project_id=report$ref$project_id),study_id=report$saved_body$study_id,project_id=report$ref$project_id,title="Saved mixed task, liking and choice findings",report_refs=list(report$ref),prepared_sources=prepared,sections=sections,
  contents_policy=list(profile="complete-findings/0.1",audience="research_team",identifier_mode=mode,stimulus_images="excluded_by_choice",complete_selected_numerical_evidence=TRUE,include_original_evidence=FALSE,include_raw_recordings=FALSE),limits_profile="controlled-task-choice-report-package/0.1",renderer_profile="controlled-gaze-explicit-task-choice-paired/0.1",frozen_at="2026-09-27T00:00:00Z",coverage=list(source_phase="Exact genuine original saved report and genuinely published preparations. Detached pure selection fixture; no current authority or connected UI claim."))
 list(schema="brohn-report-package-render-input/0.1",selection=selection,reports=list(report),distributions=if(is.null(distribution))list()else list(distribution),task_displays=if(is.null(task))list()else list(task),choice_displays=list(choice),assets=list(),implementation=implementation,limits=brohn_report_package_choice_limits())
}
local({checks<-list();passed<-FALSE;failure<-NULL;outputs<-list()
 check<-function(name,value){if(!isTRUE(value))stop(name,call.=FALSE);checks[[length(checks)+1L]]<<-name;cat("PASS",name,"\n")}
 on.exit(brohn_write_json_file(list(schema="brohn-choice-published-pure-checks/0.1",passed=passed,checks=checks,failure=failure,source_hashes=hashes,outputs=outputs,scope="Complete genuine original and published prepared sources, with pure frozen-selection fixture. Scientific/replay functions fail-fast. No current reader/worker/publication/browser claim for these newly rendered packages."),file.path(out,"results.json")),add=TRUE)
 tryCatch({
  f<-brohn_read_json_file(file.path(fixtures,"native-prepared.json"));t<-brohn_read_json_file(file.path(fixtures,"native-task-prepared.json"))
  check("native choice/task share exact complete original report",.brohn_rp_same(f$report,t$report))
  distribution<-NULL
  distribution_path<-file.path(fixtures,"native-distribution-prepared.json")
  if(file.exists(distribution_path))distribution<-brohn_read_json_file(distribution_path)
  bundle<-make_bundle(f,t$task_display,distribution);before<-brohn_hash(bundle)
  result<-brohn_render_report_package(bundle,file.path(out,"native-default"));outputs$default<-result$files;brohn_write_json_file(bundle,file.path(out,"native-default-bundle.json"))
  check("native mixed original remains unchanged by full pure render",identical(before,brohn_hash(bundle)))
  check("native task and all three choice states coexist in one report",length(result$coverage)==4L+as.integer(!is.null(distribution))&&sum(vapply(result$coverage,`[[`,numeric(1),"selected_figures"))>=8L)
  check("native utility unavailable/not-requested are explanatory panels",utils::tail(result$coverage,1L)[[1L]]$explanatory_panels==2L)
  original<-make_bundle(f,t$task_display,distribution,"source_identifiers");brohn_render_report_package(original,file.path(out,"native-original"));brohn_write_json_file(original,file.path(out,"native-original-bundle.json"))
  check("native original-identifier analysis is completely equal",.brohn_rp_same(brohn_read_json_file(file.path(out,"native-original/evidence/report-01.json"))$analysis,f$report$complete_analysis))
  focus<-bundle;focus$selection$sections<-Filter(function(s)!s$adapter%in%c("task-scores","choice-counts"),focus$selection$sections)
  result_focus<-brohn_render_report_package(focus,file.path(out,"native-focused"));outputs$focused<-result_focus$files;brohn_write_json_file(focus,file.path(out,"native-focused-bundle.json"))
  fixed<-function(files)Filter(function(d)grepl("^evidence/report-|^evidence/tasks/|^evidence/choices/|^data/choices/|^data/tasks/report-|^data/explicit/report-",d$path),files)
  check("hiding score/count figures retains all mixed complete companions",.brohn_rp_same(fixed(result$files),fixed(result_focus$files)))
  imported<-brohn_read_json_file(file.path(fixtures,"import-prepared.json"));ib<-make_bundle(imported)
  ib_before<-brohn_hash(ib);ir<-brohn_render_report_package(ib,file.path(out,"import-default"));brohn_write_json_file(ib,file.path(out,"import-default-bundle.json"));outputs$import_default<-ir$files
  check("import complete original remains unchanged by rendering",identical(ib_before,brohn_hash(ib)))
  ip<-brohn_read_json_file(file.path(out,"import-default/evidence/report-01.json"))$analysis
  check("original import row count and excluded null response retained",length(ip$source_rows)==length(imported$report$complete_analysis$source_rows)&&is.null(utils::tail(ip$source_rows,1L)[[1L]]$response_id)&&!"mapped_cells"%in%names(utils::tail(ip$source_rows,1L)[[1L]]))
  check("opaque choice response identities and exposure order unchanged",.brohn_rp_same(lapply(ip$observations,`[[`,"id"),lapply(imported$report$complete_analysis$observations,`[[`,"id"))&&.brohn_rp_same(ip$observations,ip$choice_tasks[[1L]]$exposures))
  ioriginal<-make_bundle(imported,mode="source_identifiers");brohn_render_report_package(ioriginal,file.path(out,"import-original"));brohn_write_json_file(ioriginal,file.path(out,"import-original-bundle.json"))
  check("original identifier mode preserves the whole import source",.brohn_rp_same(brohn_read_json_file(file.path(out,"import-original/evidence/report-01.json"))$analysis,imported$report$complete_analysis))
  repeated<-brohn_render_report_package(ib,file.path(out,"import-repeat"));check("repeated identical bundle yields byte-identical complete files",.brohn_rp_same(ir$files,repeated$files))
  focused<-ib;focused$selection$sections<-Filter(function(s)s$adapter=="choice-utilities",focused$selection$sections)
  fr<-brohn_render_report_package(focused,file.path(out,"import-focused"));brohn_write_json_file(focused,file.path(out,"import-focused-bundle.json"));outputs$import_focused<-fr$files
  check("import figure removal preserves exact complete companions",.brohn_rp_same(fixed(ir$files),fixed(fr$files)))
  html<-paste(readLines(file.path(out,"native-default/report.html"),encoding="UTF-8",warn=FALSE),collapse="\n")
  check("task and choice outputs retain keyboard accessible contained regions",grepl('tabindex="0"',html,fixed=TRUE)&&grepl('role="region"',html,fixed=TRUE)&&grepl('data-saved-field="correct_test_rt_mean"',html,fixed=TRUE))
  check("unavailable and unrequested utilities are explained in plain text",grepl("Choice utilities were not requested",html,fixed=TRUE)&&grepl("No complete best-worst pair was recorded",html,fixed=TRUE)&&grepl("This is an explanatory panel, with no utility marks or numerical values",html,fixed=TRUE))
  passed<-TRUE
 },error=function(e){failure<<-conditionMessage(e);stop(e)})
 cat(length(checks),"genuine prepared mixed pure checks passed\n")
})


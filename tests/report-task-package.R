# Run from the repository root after the public report-task-display.py models phase.
# Arguments: generated-models-directory fresh-evidence-directory qualified-python.
# Uses no participant corpus, source workspace, service or scientific worker.
args<-commandArgs(TRUE);stopifnot(length(args)==3L)
models<-normalizePath(args[[1L]],winslash="/",mustWork=TRUE);out<-args[[2L]];python<-normalizePath(args[[3L]],winslash="/",mustWork=TRUE)
stopifnot(!file.exists(out));dir.create(out,recursive=TRUE);out<-normalizePath(out,winslash="/")
source("R/platform-load.R",encoding="UTF-8");brohn_load(ui=FALSE)
for(f in c("platform-task-plot-views.R","platform-gaze-report-views.R","platform-explicit-distribution-views.R","platform-paired-plot-views.R"))source(file.path("R",f),encoding="UTF-8")
checks<-list();check<-function(label,x){stopifnot(isTRUE(x));checks[[length(checks)+1L]]<<-label;cat("PASS",label,"\n")}
ref<-function(b,kind="report")list(kind=kind,id=b$id,revision=1L,body_hash=brohn_hash(b),project_id="default")
names_needed<-c("profile-05-native-report","profile-05-import-report","profile-05-repeat-import-report","profile-05-cohort-report")
input_paths<-file.path(models,paste0(names_needed,".json"));stopifnot(all(file.exists(input_paths)))
input_hashes<-stats::setNames(lapply(input_paths,function(p)digest::digest(file=p,algo="sha256")),basename(input_paths))
fixtures<-lapply(input_paths,brohn_read_json_file);names(fixtures)<-names_needed
check("four public generated model fixtures are exact typed sources",all(vapply(fixtures,function(f)isTRUE(brohn_validate_task_display_evidence(f$evidence,f$report)),logical(1))))

# This extra synthetic null fixture is constructed before any export. It is not
# represented as a published report or as a new genuine scientific-worker witness.
attempts<-c(fixtures[[2L]]$report$complete_analysis$task_attempts,fixtures[[3L]]$report$complete_analysis$task_attempts)
unlinked<-fixtures[[4L]];body<-unlinked$report$saved_body
identity<-brohn_task_cohort_identity_rows(attempts)
body$analysis<-brohn_task_cohort(attempts,body$provenance$plan,identity)
# The worker envelope adds this terminal status to the pure producer result.
# It is declared here only for the synthetic saved-result shape.
body$analysis$status<-"completed"
body$id<-"synthetic-unlinked-task-package";body$title<-"Synthetic unavailable person support"
body$provenance$identity_map<-identity
object_bytes<-charToRaw(enc2utf8(brohn_json(list(schema="brohn-analysis-output/1.0",report=body))))
body$result_object<-list(hash=digest::digest(object_bytes,algo="sha256",serialize=FALSE),size=length(object_bytes),media_type="application/json")
unlinked$report<-list(ref=ref(body),saved_body=body,complete_analysis=body$analysis)
unlinked$evidence<-.brohn_td_build_evidence(unlinked$report,list(),unlinked$evidence$implementation)
unlinked$catalog<-.brohn_td_catalog(unlinked$evidence,unlinked$report)
check("unlinked fixture has explicit unknown membership and no invented people",all(vapply(body$analysis$membership,function(m)all(c("person_id","session_id")%in%names(m))&&is.null(m$person_id)&&is.null(m$session_id),logical(1)))&&length(body$analysis$per_person)==0L)

owned<-c("R/platform-report-package-tables.R","R/platform-report-package-tasks.R","R/platform-report-package-render.R","R/platform-task-display.R","R/platform-task-plots.R","R/platform-task-plot-views.R","scripts/workers/report_package_archive.py","scripts/workers/report_package_raster.py")
implementation<-list(schema="brohn-report-package-implementation/0.1",profile="static-complete-findings/0.1",
  sources=stats::setNames(lapply(owned,function(p)digest::digest(file=p,algo="sha256")),owned),
  runtime=list(R=as.character(getRversion()),jsonlite=as.character(packageVersion("jsonlite")),htmltools=as.character(packageVersion("htmltools")),
    Python=brohn_parse(processx::run(python,c("-c","import json,platform; print(json.dumps(dict(implementation=platform.python_implementation(),version=platform.python_version())))"))$stdout),
    Pillow=trimws(processx::run(python,c("-c","import PIL; print(PIL.__version__)"))$stdout)),
  archive_python=python,archive_script=normalizePath("scripts/workers/report_package_archive.py",winslash="/"),raster_script=normalizePath("scripts/workers/report_package_raster.py",winslash="/"))
make_bundle<-function(selected,mode="package_aliases"){
  selected<-unname(selected);reports<-lapply(selected,`[[`,"report")
  displays<-lapply(seq_along(selected),function(i){f<-selected[[i]]
    b<-list(id=paste0("synthetic-display-",i),schema="brohn-saved-task-display/0.1",source_family=f$evidence$source_family,source=f$evidence$source,implementation=f$evidence$implementation,catalog=f$catalog,coverage=f$evidence$coverage,
      artifact=list(hash=brohn_hash(f$evidence),bytes=nchar(brohn_json(f$evidence),type="bytes"),media_type="application/json"))
    list(ref=ref(b,"task_display"),body=b,evidence=f$evidence)})
  sections<-list()
  for(i in seq_along(selected)){
    f<-selected[[i]];people<-identical(f$evidence$source_family,"saved_task_cohort")
    for(adapter in if(people)"task-people"else c("task-scores","task-trials")){
      s<-list(id=paste0("section-",length(sections)+1L),adapter=adapter,adapter_version="0.1",source_report_ref=reports[[i]]$ref,source_ref=displays[[i]]$ref,
        selector=list(scope=if(people)"all_metrics"else"all_administrations"),display=if(people)list(charts=list("people"),pages="all")else if(adapter=="task-scores")list(pages="all")else
          list(measure="profile_default",trial_scope="all",charts="profile_default",pages="all"),order=length(sections)+1L)
      sections[[length(sections)+1L]]<-brohn_resolve_task_report_section(s,f$catalog)$section
    }
  }
  selection<-list(schema="brohn-report-package-selection/0.2",id="synthetic-selection",intent_ref=list(kind="report_package_intent",id="synthetic-intent",revision=1L,body_hash=brohn_hash("synthetic"),project_id="default"),
    study_id=reports[[1L]]$saved_body$study_id,project_id="default",title="Portable complete task findings",report_refs=lapply(reports,`[[`,"ref"),
    prepared_sources=lapply(seq_along(displays),function(i)list(adapter="task-display",source_report_ref=reports[[i]]$ref,prepared_ref=displays[[i]]$ref,implementation_ref=list(profile=displays[[i]]$body$implementation$profile,hash=brohn_hash(displays[[i]]$body$implementation)))),
    sections=sections,contents_policy=list(profile="complete-findings/0.1",audience="research_team",identifier_mode=mode,stimulus_images="excluded_by_choice",complete_selected_numerical_evidence=TRUE,include_original_evidence=FALSE,include_raw_recordings=FALSE),
    limits_profile="controlled-task-report-package/0.1",renderer_profile="controlled-gaze-explicit-task-paired/0.1",frozen_at="2026-09-27T00:00:00Z",coverage=list(fixture="Public generated task sources; pure synthetic prepared envelopes, no publication claim."))
  list(schema="brohn-report-package-render-input/0.1",selection=selection,reports=reports,distributions=list(),task_displays=displays,assets=list(),implementation=implementation,limits=brohn_report_package_task_limits())
}
for(fn in c("brohn_task_score","brohn_gnat_score","brohn_sciat_window_score","brohn_import_task_trials","brohn_task_cohort","brohn_task_evidence_from_run",".brohn_delivery_replay","brohn_score_scales","brohn_build_explicit_distributions"))assign(fn,function(...)stop("Scientific operation forbidden during pure report qualification"),envir=.GlobalEnv)
metric<-function(a,name)Filter(function(m)m$name==name,a$task_scores[[1L]]$metrics)[[1L]]
check("independent partial source oracle500ms39of40omissions and null SD",metric(fixtures[[1L]]$report$complete_analysis,"correct_test_rt_mean")$value==500&&metric(fixtures[[1L]]$report$complete_analysis,"test_omission_rate")$value==39/40&&is.null(metric(fixtures[[1L]]$report$complete_analysis,"correct_test_rt_sd")$value))
render<-function(bundle,name){before<-brohn_hash(bundle);result<-brohn_render_report_package(bundle,file.path(out,name));brohn_write_json_file(bundle,file.path(out,paste0(name,"-bundle.json")))
  check(paste(name,"full input immutable and exact panel count"),identical(before,brohn_hash(bundle))&&brohn_report_package_panel_preflight(bundle)$resolved_panel_count==sum(vapply(result$coverage,`[[`,numeric(1),"selected_figures")));result}
bundle<-make_bundle(fixtures);first<-render(bundle,"default")
check("zero-panel task score table remains an intentional section",first$coverage[[1L]]$selected_figures==0L&&first$coverage[[1L]]$selected_models==1L)
again<-brohn_render_report_package(bundle,file.path(out,"repeat"));check("frozen input produces identical HTML ZIP and companions",.brohn_rp_same(first$files,again$files))
focused<-bundle
for(i in seq_along(focused$selection$sections))if(focused$selection$sections[[i]]$adapter=="task-trials"){
  s<-focused$selection$sections[[i]];s$display$trial_scope<-"scored";s$display$pages<-"selected";s$display$page_numbers<-list(1L);s$display$charts<-list("distribution")
  at<-which(vapply(focused$task_displays,function(d).brohn_rp_same(d$ref,s$source_ref),logical(1)))
  focused$selection$sections[[i]]<-brohn_resolve_task_report_section(s,focused$task_displays[[at]]$body$catalog)$section
}
second<-render(focused,"focused")
complete<-Filter(function(f)startsWith(f$path,"evidence/")||grepl("^data/(tasks|explicit)/report-",f$path),first$manifest$files)
check("focused figures preserve every complete numerical companion byte",all(vapply(complete,function(f)identical(f$sha256,digest::digest(file=file.path(out,"focused",f$path),algo="sha256")),logical(1))))
for(mode in c("package_aliases","source_identifiers")){
  b<-make_bundle(list(unlinked),mode);render(b,mode)
  p<-brohn_read_json_file(file.path(out,mode,"evidence/report-01.json"))
  for(field in c("membership","attempt_metrics"))check(paste(mode,field,"all explicit null identity fields preserved"),all(vapply(p$analysis[[field]],function(r)all(c("person_id","session_id")%in%names(r))&&is.null(r$person_id)&&is.null(r$session_id),logical(1))))
  check(paste(mode,"all unavailable metrics remain exact"),.brohn_rp_same(p$analysis$summaries,unlinked$report$complete_analysis$summaries))
  if(mode=="source_identifiers")check("whole original identifier analysis unchanged",.brohn_rp_same(p$analysis,unlinked$report$complete_analysis))
}
low<-bundle;low$limits$max_panels<-1L;refusal<-brohn_render_report_package(low,file.path(out,"refused"))
check("panel excess refuses with no artifact directory",identical(refusal$schema,"brohn-report-package-refusal/0.1")&&refusal$resolved_panel_count>1&&!file.exists(file.path(out,"refused")))
after<-stats::setNames(lapply(input_paths,function(p)digest::digest(file=p,algo="sha256")),basename(input_paths));check("all generated original model bytes unchanged",identical(input_hashes,after))
brohn_write_json_file(list(passed=TRUE,checks=checks,inputs=input_hashes,source_hashes=implementation$sources,
  scope="Public generated source models plus separately declared pure unlinked fixture. Scientific routes disabled during rendering. No worker, browser, authority or physical timing claim."),file.path(out,"results.json"))
cat(length(checks),"portable pure task-package checks passed\n")

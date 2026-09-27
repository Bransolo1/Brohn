# Pure rendering over explicit generated original/prepared fixtures, no store.
args<-commandArgs(TRUE);stopifnot(length(args)==4L)
repo<-normalizePath(args[[1]],winslash="/",mustWork=TRUE);originals<-normalizePath(args[[2]],winslash="/",mustWork=TRUE);prepared_dir<-normalizePath(args[[3]],winslash="/",mustWork=TRUE)
out<-args[[4]];stopifnot(!file.exists(out));dir.create(out,recursive=TRUE);out<-normalizePath(out,winslash="/",mustWork=TRUE)
setwd(repo);source("R/platform-load.R");brohn_load(ui=FALSE)
for(fn in c("brohn_process_job","brohn_analyse_runs","brohn_maxdiff_fit","brohn_maxdiff_analysis","brohn_task_score","brohn_task_cohort","brohn_task_evidence_from_run",".brohn_delivery_replay","brohn_score_scales","brohn_build_explicit_distributions"))assign(fn,function(...)stop("Scientific job/scoring/replay forbidden during pure EDA assembly"),envir=.GlobalEnv)
read<-brohn_eda_read_json_file;write<-brohn_eda_write_json_file
reports<-entries<-sections<-requests<-nodes<-prepared<-list()
for(i in 1:2){
  family<-c("event","continuous")[[i]];original<-read(file.path(originals,paste0(family,"-report.json")));p<-read(file.path(prepared_dir,paste0(family,"-prepared.json")))
  d<-p$eda_display;body<-d$body;ref<-d$ref;e<-d$evidence;r<-list(catalog=body$catalog);q<-list(report=p$report)
  stopifnot(.brohn_rp_same(original$body,p$report$saved_body));reports[[i]]<-p$report
  q$streams<-lapply(original$body$analysis$artifacts,function(a){v<-Filter(function(v)identical(v$kind,a$kind),original$body$analysis$artifact_verification$artifacts);stopifnot(length(v)==1L)
    list(original=a,original_verification=v[[1L]],path=file.path(originals,family,paste0(a$kind,".ndjson")))})
  path<-file.path(prepared_dir,paste0(family,"-evidence.json"))
  stopifnot(file.exists(path),identical(digest::digest(file=path,algo="sha256"),body$artifact$hash),file.info(path)$size==body$artifact$bytes)
  entries[[i]]<-list(ref=ref,body=body,evidence=c(body$artifact,list(path=path)),streams=q$streams)
  section<-list(id=paste0("section-",family),adapter=paste0("eda-",if(family=="event")"events"else"continuous"),adapter_version="0.1",source_report_ref=q$report$ref,source_ref=ref,selector=list(scope="all_cells"),
    display=list(components=if(family=="event")list("phasic_us")else list("tonic_us","phasic_us"),pages="all",page_numbers=list(),marker_pages=list(pages="all",page_numbers=list())),order=i)
  sections[[i]]<-brohn_resolve_eda_report_section(section,r$catalog)$section
  prepared[[i]]<-list(adapter="eda-display",source_report_ref=q$report$ref,prepared_ref=ref,implementation_ref=list(profile=body$implementation$profile,hash=brohn_hash(body$implementation)))
  requests[[i]]<-list(report_ref=q$report$ref,display_request=e$display_request)
  context<-structure(list(),names=character());sourcefile<-file.path(originals,paste0(family,"-report.json"))
  nodes[[i]]<-list(ref=q$report$ref,analysis_kind="eda",source_ordinal=i,retained_report=list(hash=digest::digest(file=sourcefile,algo="sha256"),bytes=as.numeric(file.info(sourcefile)$size),media_type="application/json"),provenance_context=context,context_hash=brohn_hash(context))
}
cat("Build frozen fixture",format(Sys.time()),"\n");flush.console()
graph<-list(schema="brohn-report-source-identity-graph/0.1",root_refs=lapply(reports,`[[`,"ref"),nodes=nodes,edges=list());binding<-graph;binding$nodes<-lapply(nodes,function(n)n[setdiff(names(n),c("provenance_context","context_hash"))])
selection<-list(schema="brohn-report-package-selection/0.3",id="selection-eda-pure",intent_ref=list(kind="report_package_intent",id="intent-eda-pure",revision=1L,body_hash=paste(rep("a",64),collapse=""),project_id="default"),study_id=reports[[1L]]$saved_body$study_id,project_id="default",title="Saved EDA findings \u2014 complete source fixture",report_refs=lapply(reports,`[[`,"ref"),prepared_sources=prepared,sections=sections,
  contents_policy=list(profile="complete-findings/0.1",audience="research_team",identifier_mode="package_aliases",stimulus_images="excluded_by_choice",complete_selected_numerical_evidence=TRUE,include_original_evidence=FALSE,include_raw_recordings=FALSE),
  limits_profile="controlled-task-choice-eda-report-package/0.1",renderer_profile="controlled-gaze-explicit-task-choice-eda-paired/0.1",frozen_at="2026-09-28T00:00:00Z",coverage=list(scope="Pure assembly over genuine generated originals and saved preparation bytes; selection/graph fixture is external, no new store/authority claim"),eda_display_requests=requests,related_eda_refs=list(),source_identity_graph_binding=binding)
bundle<-list(schema="brohn-report-package-render-input/0.1",selection=selection,reports=reports,distributions=list(),assets=list(),task_displays=list(),choice_displays=list(),eda_displays=entries,related_eda_sources=list(),source_identity_graph=graph,limits=brohn_report_package_eda_limits(),implementation=.brohn_rpk_implementation())
write(bundle,file.path(out,"original-bundle.json"),128*1024^2)
cat("Render",format(Sys.time()),"\n");flush.console()
result<-brohn_render_report_package(bundle,file.path(out,"render"))
write(result,file.path(out,"render-result.json"),128*1024^2)
stopifnot(identical(result$schema,"brohn-report-package-render-result/0.1"),sum(vapply(result$coverage,`[[`,numeric(1),"selected_figures"))==12L)
checks<-c("complete default12-panel actual-source package renders","exact complete typed streams and display models inventoried")
check<-function(ok,label){stopifnot(isTRUE(ok));checks<<-c(checks,label)}
refuse<-function(fn,label)check(inherits(tryCatch({fn();NULL},error=identity),"error"),label)
bad<-bundle;bad$eda_displays[[1]]$body$artifact$hash<-paste(rep("f",64),collapse="");bad$eda_displays[[1]]$ref$body_hash<-brohn_hash(bad$eda_displays[[1]]$body)
refuse(function().brohn_rpe_find(bad,bad$reports[[1]]),"saved artifact mismatch refuses")
bad<-bundle;bad$eda_displays[[1]]$streams<-rev(bad$eda_displays[[1]]$streams)
refuse(function().brohn_rpe_find(bad,bad$reports[[1]]),"source stream order mismatch refuses")
bad<-bundle;bad$source_identity_graph$nodes<-c(bad$source_identity_graph$nodes,bad$source_identity_graph$nodes[1])
refuse(function().brohn_rpe_prepared_bindings(bad),"duplicate source graph node refuses")
html<-paste(readLines(file.path(out,"render/report.html"),warn=FALSE,encoding="UTF-8"),collapse="\n")
check(grepl("brohn-eda-scroll-help",html,fixed=TRUE)&&grepl("Keyboard: focus this area",html,fixed=TRUE),"visible scrolling instructions preserved")
check(grepl("aria-describedby",html,fixed=TRUE)&&grepl("tabindex=\"0\"",html,fixed=TRUE),"keyboard labelled regions rendered")
check(grepl("@media print",html,fixed=TRUE)&&grepl("min-width:0!important",html,fixed=TRUE),"EDA print sizing rules included, not a PDF-layout claim")
bad<-sections[[1]];bad$display$pages<-"selected";bad$display$page_numbers<-list(99999L)
refuse(function()brohn_resolve_eda_report_section(bad,entries[[1]]$body$catalog),"nonexistent numerical page refuses")
write(list(passed=TRUE,checks=as.list(checks),count=length(checks),scope="Pure package assembly over generated complete originals and saved preparation artifacts; malformed copies and section semantics tested, no native publication/browser/PDF or scientific-validity claim"),file.path(out,"results.json"))
cat(length(checks),"pure EDA package checks passed\n")

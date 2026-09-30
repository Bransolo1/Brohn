# Usage: Rscript tests/choice-display-backend.R <repo-root> <fresh-evidence-dir>
# Requires the configured R library, methods Python and native publication manifest.
args<-commandArgs(TRUE);stopifnot(length(args)==2L)
root<-normalizePath(args[[1L]],winslash="/",mustWork=TRUE)
out<-normalizePath(args[[2L]],winslash="/",mustWork=FALSE)
stopifnot(dir.exists(root),!file.exists(out),!dir.exists(out))
manifest<-Sys.getenv("BROHN_PUBLICATION_NATIVE_MANIFEST","")
if(!nzchar(manifest)||!file.exists(manifest))stop("Set BROHN_PUBLICATION_NATIVE_MANIFEST to the installed native publication-guard manifest.",call.=FALSE)
if(!nzchar(Sys.getenv("BROHN_PUBLICATION_PYTHON","")))stop("Set BROHN_PUBLICATION_PYTHON to the installed methods Python executable.",call.=FALSE)
dir.create(out,recursive=TRUE);out<-normalizePath(out,winslash="/",mustWork=TRUE)
oldwd<-getwd();setwd(root)
source_files<-unlist(lapply(c("R","scripts","tests"),function(d)list.files(d,recursive=TRUE,full.names=TRUE)),use.names=FALSE)
source_hashes<-stats::setNames(lapply(source_files,function(f)digest::digest(file=f,algo="sha256")),source_files)
source(file.path(root,"tests/fixtures/choice-report-originals.R"),encoding="UTF-8")
dir.create(file.path(out,"originals"));brohn_choice_report_originals(root,file.path(out,"originals"),manifest)
dir.create(file.path(out,"backend"));original_workspace<-file.path(out,"originals/workspace")
stopifnot(file.copy(original_workspace,file.path(out,"backend"),recursive=TRUE,copy.mode=TRUE,copy.date=TRUE))
cfg<-list(checkout=root,out=file.path(out,"backend"),originals=file.path(out,"originals"),native_manifest=manifest)
brohn_choice_display_qualify <- function(cfg) {
 oldwd<-getwd();on.exit(setwd(oldwd),add=TRUE);setwd(cfg$checkout)
Sys.setenv(BROHN_PUBLICATION_NATIVE_MANIFEST=cfg$native_manifest)
source("R/platform-load.R",encoding="UTF-8");brohn_load(ui=FALSE)
local({
 checks<-list();passed<-FALSE;failure<-NULL;out<-cfg$out
 check<-function(name,x){if(!isTRUE(x))stop(name,call.=FALSE);checks[[length(checks)+1L]]<<-name;cat("PASS",name,"\n")}
 reject<-function(expr)inherits(try(force(expr),silent=TRUE),"try-error")
 store<-brohn_open_store(file.path(out,"workspace"));objects<-DBI::dbGetQuery(store$con,"SELECT * FROM objects ORDER BY hash");jobs<-brohn_list_jobs(store)
 on.exit({for(j in brohn_list_jobs(store))if(j$status %in% c("queued","running"))brohn_cancel_job(store,j$id)
  brohn_write_json_file(list(schema="brohn-choice-backend-acceptance/0.1",passed=passed,checks=checks,failure=failure,jobs=lapply(brohn_list_jobs(store),function(j)list(id=j$id,operation=j$operation,status=j$status,error=j$error,result=j$result)),scope="Actual local API/worker/sealed-source qualification on an owned copy. No browser, human, device, hosted-user or scientific-estimator validation."),file.path(out,"results.json"));brohn_close_store(store)},add=TRUE)
 tryCatch({
  runjob<-function(j){force(j);claim<-brohn_claim_job(store,"choice-preparation-qa",lease_seconds=120L);stopifnot(!is.null(claim),identical(claim$id,j$id));brohn_process_job(store,claim,timeout_seconds=180L);done<-brohn_get_job(store,j$id);if(done$status!="succeeded")stop("Preparation failed: ",brohn_json(done$error));done}
  originals<-lapply(c("import","native"),function(f)brohn_read_json_file(file.path(cfg$originals,paste0(f,"-report.json"))));names(originals)<-c("import","native")
  for(family in names(originals)){
   report<-originals[[family]];ref<-.brohn_rpk_ref(report);choice<-brohn_report_package_report_choice(store,ref)
   check(paste(family,"metadata advertises both choice adapters"),all(c("choice-counts","choice-utilities") %in% unlist(choice$adapters))&&"choice" %in% unlist(choice$source_components))
   check(paste(family,"old source admission refuses complete choice source"),reject(.brohn_rpk_source_metadata(store,list(ref),task_enabled=TRUE)))
   n<-length(brohn_list_jobs(store));catalog<-brohn_report_package_selector_catalog(store,ref,"choice-counts")
   check(paste(family,"unprepared discovery starts no job"),catalog$state=="needs_preparation"&&length(brohn_list_jobs(store))==n)
   job<-brohn_queue_choice_display(store,ref);check(paste(family,"duplicate queue reuses exact request"),identical(brohn_queue_choice_display(store,ref)$id,job$id));done<-runjob(job)
   saved<-brohn_get_entity(store,"choice_display",done$result$choice_display_id);dref<-.brohn_rpk_ref(saved)
   opened<-brohn_open_choice_display_resources(store,dref,ref$project_id)
   check(paste(family,"actual complete choice artifact validates"),isTRUE(brohn_validate_choice_display_evidence(opened$evidence,list(ref=ref,saved_body=report$body,complete_analysis=report$body$analysis))))
   check(paste(family,"current reader exact descriptor"),.brohn_td_same(brohn_choice_display_resources_current(store,opened$handle)$artifact,opened$artifact))
   check(paste(family,"metadata catalog preserves exact source"),.brohn_td_same(brohn_choice_display_catalog(store,dref)$report_ref,ref)&&identical(brohn_find_choice_display(store,ref)$id,dref$id))
   fixture<-list(report=list(ref=ref,saved_body=report$body,complete_analysis=report$body$analysis),choice_display=list(ref=dref,body=saved$body,evidence=opened$evidence))
   brohn_write_json_file(fixture,file.path(out,paste0(family,"-prepared.json")),maximum=128*1024^2)
   brohn_release_choice_display_resources(opened$handle);brohn_release_choice_display_resources(opened$handle)
   check(paste(family,"released read refuses idempotently"),reject(brohn_choice_display_resources_current(store,opened$handle)))
   if(family=="native"){
    check("old task profile refuses mixed choice source",reject(brohn_queue_task_display(store,ref)))
    td<-runjob(brohn_queue_task_display(store,ref,implementation_ref=brohn_task_display_implementation_ref("saved-task-display/0.2")))
    tr<-brohn_get_entity(store,"task_display",td$result$task_display_id);th<-brohn_open_task_display_resources(store,.brohn_rpk_ref(tr),ref$project_id)
    check("genuine mixed task0.2 preserves full analysis hash",th$evidence$schema=="brohn-task-display-evidence/0.2"&&th$evidence$source$analysis_hash==brohn_hash(report$body$analysis))
    brohn_write_json_file(list(report=fixture$report,task_display=list(ref=.brohn_rpk_ref(tr),body=tr$body,evidence=th$evidence)),file.path(out,"native-task-prepared.json"),maximum=128*1024^2)
    brohn_release_task_display_resources(th$handle)
    dj<-runjob(brohn_queue_explicit_distributions_ref(store,ref,implementation_ref=.brohn_rpk_distribution_implementation_ref("task-choice-findings/0.1"),source_admission="task-choice-findings/0.1"))
    dr<-brohn_get_entity(store,"explicit_distributions",dj$result$explicit_distributions_id);dm<-.brohn_rpk_distribution_metadata(store,.brohn_rpk_ref(dr))
    check("genuine mixed distribution0.2 retains admission and producer",identical(dr$body$source_admission,"task-choice-findings/0.1")&&identical(dm$preparation_implementation_ref$profile,"saved-explicit-distribution/0.2"))
    brohn_write_json_file(list(ref=.brohn_rpk_ref(dr),body=dr$body),file.path(out,"native-distribution-prepared.json"))
   }
  }
  current<-DBI::dbGetQuery(store$con,"SELECT * FROM objects ORDER BY hash");check("all original object metadata and bytes unchanged",all(vapply(seq_len(nrow(objects)),function(i){r<-objects[i,,drop=FALSE];n<-current[current$hash==r$hash,,drop=FALSE];identical(as.list(r),as.list(n))&&identical(digest::digest(file=brohn_object_path(store,r$hash,FALSE),algo="sha256"),r$hash)},logical(1))))
  check("only preparation jobs added; original science unchanged",all(vapply(jobs,function(j).brohn_td_same(j,brohn_get_job(store,j$id)),logical(1)))&&all(vapply(Filter(function(j)!j$id %in% vapply(jobs,`[[`,character(1),"id"),brohn_list_jobs(store)),function(j)j$operation %in% c("choice_display","task_display","explicit_distributions")&&j$status=="succeeded",logical(1))))
  passed<-TRUE
 },error=function(e){failure<<-conditionMessage(e);stop(e)})
 cat("Choice backend:",length(checks),"checks passed\n")
})

 invisible(cfg$out)
}

brohn_choice_display_qualify(cfg)
setwd(root);source("R/platform-load.R",encoding="UTF-8");brohn_load(ui=FALSE)
fixture<-brohn_read_json_file(file.path(out,"backend/import-prepared.json"));original<-fixture$report$complete_analysis$choice_tasks[[1L]]
for(fn in c("brohn_maxdiff_fit","brohn_maxdiff_likelihood",".brohn_md_evaluate","brohn_maxdiff_analysis","brohn_import_maxdiff_analysis","brohn_analyse_runs","brohn_score_run_maxdiff"))assign(fn,function(...)stop("Scientific replay is forbidden in pure export validation"),envir=.GlobalEnv)
mutations<-list(
 iterations_text=function(x){x$model$parameters$maximum_iterations<-"five hundred";x},
 weights_changed=function(x){x$model$parameters$weights<-"two per complete observed pair";x},
 negative_tolerance=function(x){x$model$parameters$relative_tolerance<--1;x},
 missing_item_coverage=function(x){x$design_review$item_coverage<-list();x},
 missing_pair_coverage=function(x){x$design_review$pair_coverage<-list();x},
 zero_probability_mass=function(x){x$model$probabilities[[1L]]$alternatives<-lapply(x$model$probabilities[[1L]]$alternatives,function(a){a$probability<-0;a});x},
 invented_probability_support=function(x){x$model$probabilities[[1L]]$answered_exposures<-999L;x})
stopifnot(isTRUE(brohn_validate_choice_result(original)))
refusals<-lapply(mutations,function(f)inherits(try(brohn_validate_choice_result(f(original)),silent=TRUE),"try-error"));stopifnot(all(unlist(refusals)))
stopifnot(all(vapply(names(source_hashes),function(f)identical(digest::digest(file=f,algo="sha256"),source_hashes[[f]]),logical(1))))
initial<-brohn_read_json_file(file.path(out,"originals/results.json"));backend_result<-brohn_read_json_file(file.path(out,"backend/results.json"))
brohn_write_json_file(list(schema="brohn-portable-choice-source-preparation-tests/0.1",passed=TRUE,original_checks=length(initial$checks),backend_checks=length(backend_result$checks),malformed_refusals=refusals,source_hashes=source_hashes,scope="Generated synthetic receiver/import sources and actual scientific/preparation workers; pure malformed-field refusals execute no fitting/scoring/likelihood. No browser, real participant/device or hosted identity claim."),file.path(out,"results.json"))
cat("Portable choice source/backend passed:",length(initial$checks),"original,",length(backend_result$checks),"preparation,",length(refusals),"malformed cases.\n")
setwd(oldwd)

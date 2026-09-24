# Actual app presentation only; copies terminal original synthetic workspaces.
# No workers, scoring, new studies or new reports. Run only after source freeze.
args<-commandArgs(TRUE);stopifnot(length(args)>=2L)
mode<-args[[1L]];folder<-normalizePath(args[[2L]],winslash="/",mustWork=FALSE)
stopifnot(startsWith(basename(folder),"brohn-results-first-"))
source("R/platform-load.R",encoding="UTF-8");brohn_load(ui=TRUE)
cp<-file.path(folder,"fixture.json");workspace<-file.path(folder,"workspace")
file_hashes<-function(root){files<-list.files(root,recursive=TRUE,full.names=TRUE,all.files=TRUE,no..=TRUE)
  stats::setNames(vapply(files,function(p)digest::digest(file=p,algo="sha256"),character(1)),substring(files,nchar(root)+2L))}
if(mode=="prepare"){
  stopifnot(length(args)==5L,!dir.exists(folder));dir.create(folder,recursive=TRUE)
  source_folder<-normalizePath(args[[3L]],winslash="/",mustWork=TRUE);kind<-args[[4L]];port<-as.integer(args[[5L]])
  stopifnot(kind %in% c("gnat","audio","combined"),port>=1024L,port<=65534L)
  original_workspace<-file.path(source_folder,"workspace");stopifnot(dir.exists(original_workspace))
  before<-file_hashes(original_workspace)
  stopifnot(file.copy(original_workspace,folder,recursive=TRUE),identical(before,file_hashes(original_workspace)))
  brohn_write_json_file(as.list(before),file.path(folder,"original-workspace-hashes.json"))
}
if(mode=="serve"){
  cfg<-brohn_read_json_file(cp)
  Sys.setenv(BROHN_WORKSPACE=workspace,BROHN_APP_MODE="platform",BROHN_PARTICIPANT_PORT=as.character(cfg$port+1L))
  stop_owned<-function()if(file.exists(file.path(folder,"stop.request")))shiny::stopApp()else later::later(stop_owned,.15)
  later::later(stop_owned,.15);shiny::runApp(".",host="127.0.0.1",port=cfg$port,launch.browser=FALSE)
}else local({
  store<-brohn_open_store(workspace);on.exit(brohn_close_store(store),add=TRUE)
  inventory<-function(){reports<-brohn_list_entities(store,"report",limit=10000L)
    list(reports=lapply(reports,function(r)list(id=r$id,revision=r$revision,project_id=r$project_id,hash=brohn_hash(r$body))),
      jobs=brohn_list_jobs(store,limit=10000L),objects=as.list(file_hashes(file.path(workspace,"objects"))))}
  if(mode=="prepare"){
    initial<-inventory();stopifnot(!any(vapply(initial$jobs,function(j)j$status %in% c("queued","running"),logical(1))))
    reports<-brohn_list_entities(store,"report",limit=10000L);prior<-list()
    if(kind=="gnat"){
      prior_json<-file.path(source_folder,"ORIGINAL-GNAT-002-native-report.json");saved<-brohn_read_json_file(prior_json)
      r<-brohn_get_entity(store,"report",saved$id);stopifnot(identical(brohn_hash(saved),brohn_hash(r$body)))
      prior<-list(report_download=prior_json,report_html=file.path(source_folder,"ORIGINAL-GNAT-002-report.html"),report_task_csv=file.path(source_folder,"ORIGINAL-GNAT-002-scores.csv"))
    }else if(kind=="audio"){
      selected<-Filter(function(r)!is.null(r$body$provenance$derived_audio_lineage),reports);stopifnot(length(selected)==1L);r<-selected[[1L]]
    }else{
      selected<-Filter(function(r)identical(r$body$analysis$kind,"multimodal"),reports);stopifnot(length(selected)==1L);r<-selected[[1L]]
      prior<-list(report_download=file.path(source_folder,"evidence","combined-peripheral-liking-report.json"),report_csv=file.path(source_folder,"evidence","combined-peripheral-observations.csv"))
    }
    stopifnot(!is.null(r),all(vapply(prior,file.exists,logical(1))))
    report<-brohn_report_for_review(store,r$id);stopifnot(identical(brohn_hash(report$body),brohn_hash(r$body)))
    dataset<-if(!is.null(r$body$dataset_id))brohn_get_entity(store,"dataset",r$body$dataset_id)else NULL
    study<-if(!is.null(r$body$study_id))brohn_get_entity(store,"study",r$body$study_id)else NULL
    parent_id<-r$body$provenance$derived_audio_lineage$binding$parent_dataset$id
    parent<-if(!is.null(parent_id))brohn_get_entity(store,"dataset",parent_id)else NULL
    brohn_write_json_file(r$body,file.path(folder,"original-report.json"))
    brohn_export_report_html(r$body,file.path(folder,"expected-report.html"),store)
    brohn_export_report_csv(brohn_complete_questionnaire_report(store,r$body),file.path(folder,"expected-observations.csv"))
    if(kind=="gnat")brohn_export_task_scores_csv(brohn_complete_questionnaire_report(store,r$body),file.path(folder,"expected-task-scores.csv"))
    brohn_write_json_file(initial,file.path(folder,"before.json"))
    brohn_write_json_file(list(schema="brohn-results-first-browser/1.0",kind=kind,port=port,source_folder=source_folder,
      source_workspace=original_workspace,report_id=r$id,report_title=r$body$title,report_hash=brohn_hash(r$body),
      saved_metadata=paste("Saved",r$created_at,"\u00b7","Immutable analysis"),
      dataset_id=dataset$id,dataset_title=dataset$body$title,study_id=study$id,study_title=study$body$title,
      parent_id=parent_id,parent_project=parent$project_id,prior_exports=prior,
      prior_export_hashes=lapply(prior,function(p)digest::digest(file=p,algo="sha256"))),cp)
    cat("PREPARED unchanged saved",kind,"report",r$id,"\n")
  }else{
    cfg<-brohn_read_json_file(cp)
    if(mode %in% c("revoke","restore")){
      stopifnot(identical(cfg$kind,"audio"),!is.null(cfg$parent_id))
      DBI::dbExecute(store$con,"UPDATE entities SET project_id=? WHERE kind='dataset' AND id=?",params=list(if(mode=="revoke")"results-first-deliberate-foreign"else cfg$parent_project,cfg$parent_id))
    }else if(mode=="verify"){
      stopifnot(identical(brohn_hash(inventory()),brohn_hash(brohn_read_json_file(file.path(folder,"before.json")))),
        identical(brohn_hash(as.list(file_hashes(cfg$source_workspace))),brohn_hash(brohn_read_json_file(file.path(folder,"original-workspace-hashes.json")))))
      r<-brohn_report_for_review(store,cfg$report_id);stopifnot(identical(brohn_hash(r$body),cfg$report_hash))
      for(key in names(cfg$prior_exports))stopifnot(identical(digest::digest(file=cfg$prior_exports[[key]],algo="sha256"),cfg$prior_export_hashes[[key]]))
      brohn_write_json_file(list(passed=TRUE,original_workspace_unchanged=TRUE,reports_objects_jobs_unchanged=TRUE,new_jobs=0L,report_hash=cfg$report_hash),file.path(folder,"verified.json"))
      cat("VERIFIED exact original body/objects/jobs/source fixture\n")
    }else stop("Unknown results-first fixture mode")
  }
})

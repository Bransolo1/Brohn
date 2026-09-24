# Read-only reconstruction of the people behind an existing saved contrast.
# No scorer, hypothesis test, synchronization or replacement estimate runs here.
.brohn_pp_supported <- function(report) report$analysis$kind %in% c("gaze","questionnaire","multimodal") &&
  (length(report$analysis$contrasts)>0L || brohn_questionnaire_is_artifact(report$analysis))
.brohn_pp_num <- function(x) if(is.null(x)) "Unavailable" else if(is.numeric(x)) sprintf("%.17g",x) else as.character(x)
.brohn_pp_key <- function(...) brohn_json(list(...))
.brohn_pp_near <- function(x,y) brohn_number(x)&&brohn_number(y)&&abs(x-y)<=64*.Machine$double.eps*max(1,abs(x),abs(y))
.brohn_pp_catalog <- function(report) lapply(seq_along(report$analysis$contrasts),function(i) {
  c<-report$analysis$contrasts[[i]]
  list(id=paste0("comparison-",i),index=i,source_id=brohn_hash(list(c$report_ids,c$metric,c$outcome_id,c$unit)),
    source_label=paste(brohn_default(c$modality,report$analysis$kind),brohn_default(c$outcome_label,c$outcome_id),gsub("_"," ",c$metric),c$unit,sep=" | "),
    condition_label=paste(c$test_label,"minus",c$control_label),source_report_ids=brohn_default(c$report_ids,list(report$id)))
})
brohn_paired_plot_report <- function(store,report_id,revision,report_hash,project_id) {
  study_owner<-DBI::dbGetQuery(store$con,"SELECT project_id FROM entities WHERE kind='report' AND id=?",params=list(report_id))
  brohn_require(nrow(study_owner)==1L&&identical(study_owner$project_id[[1L]],project_id),"This saved comparison is unavailable in this project.")
  r<-brohn_get_entity(store,"report",report_id,revision)
  brohn_require(!is.null(r)&&identical(brohn_hash(r$body),report_hash),"The saved report changed. Reopen its paired results.")
  verified<-.brohn_tc_report(store,.brohn_tc_study(store,r$body$study_id,project_id),report_id)
  brohn_require(identical(as.numeric(verified$record$revision),as.numeric(revision))&&identical(brohn_hash(verified$record$body),report_hash),"A newer saved report cannot replace the opened source.")
  brohn_require(.brohn_pp_supported(r$body),"This report has no supported saved paired comparison.")
  body<-r$body;artifact<-NULL
  if(brohn_questionnaire_is_artifact(body$analysis)) {
    artifact<-brohn_questionnaire_report_artifact(body)
    # Typed artifact hydration is deliberately bounded before decoding. Never use
    # presentation previews when a complete source is larger or unavailable.
    bytes<-brohn_default(artifact$size,artifact$bytes)
    brohn_require(brohn_number(bytes,1,12*1024^2,TRUE),"The complete questionnaire evidence exceeds the 12 MiB paired-review profile. Its complete artifact remains downloadable; a bounded preview cannot supply paired observations.")
    body<-brohn_complete_questionnaire_report(store,body)
  }
  brohn_require(length(body$analysis$observations)<=100000L&&length(body$analysis$scales$observations)<=100000L,
    "This complete source exceeds the 100,000-observation paired-review profile. No partial source is plotted.")
  list(record=r,report_hash=report_hash,body=body,artifact=artifact,catalog=.brohn_pp_catalog(body),
    catalog_hash=.brohn_qexplorer_catalog(store,"report",r$id,r$revision,project_id))
}
brohn_paired_plot_check <- function(store,opened) {
  r<-opened$record;brohn_project(store,r$project_id)
  current<-DBI::dbGetQuery(store$con,"SELECT revision,project_id FROM entities WHERE kind='report' AND id=?",params=list(r$id))
  brohn_require(nrow(current)==1L&&current$revision[[1L]]==r$revision&&identical(current$project_id[[1L]],r$project_id)&&
    identical(.brohn_qexplorer_catalog(store,"report",r$id,r$revision,r$project_id),opened$catalog_hash),"This report changed or is no longer available. Reopen its current paired results.")
  .brohn_tc_study(store,r$body$study_id,r$project_id)
  brohn_object_path(store,r$body$result_object$hash,verify=TRUE)
  if(!is.null(opened$artifact))brohn_object_path(store,brohn_default(opened$artifact$hash,opened$artifact$sha256),verify=TRUE)
  invisible(TRUE)
}
.brohn_pp_observations <- function(report,contrast) {
  a<-report$analysis;c<-contrast;scale<-identical(c$metric,"assessment_scale_score");mm<-identical(a$kind,"multimodal")
  planned<-!is.null(a$parameters$analysis_plan)
  if(scale) {
    adapted<-brohn_scale_comparison_source(a,report$provenance$design,c)
    if(!is.null(adapted$reason))return(list(rows=list(),reason=adapted$reason))
    brohn_require(identical(brohn_hash(adapted$evidence),brohn_hash(c$scale_source)),"The saved scale comparison and complete assessment evidence disagree.")
    original<-adapted$observations
  } else original<-a$observations
  supported<-mm || (a$kind=="gaze"&&c$metric %in% c("valid_gaze_share","fixation_dwell")) ||
    (a$kind=="questionnaire"&&c$metric %in% c("explicit_response","assessment_scale_score"))
  if(!supported)return(list(rows=list(),reason="unsupported_saved_comparison_recipe"))
  indices<-which(vapply(original,function(r) {
    match<-if(mm)r$source_report_id %in% unlist(c$report_ids)&&identical(r$modality,c$modality)&&identical(r$metric,c$metric)&&identical(r$outcome_id,c$outcome_id)&&identical(r$unit,c$unit) else
      if(scale)TRUE else identical(if(a$kind=="gaze")r$aoi_label else r$question_id,c$outcome_id)
    isTRUE(match)&&(!(mm||planned||scale)||isTRUE(r$condition_id %in% c(c$control_id,c$test_id)))
  },logical(1)))
  field<-if(a$kind=="gaze")switch(c$metric,valid_gaze_share="valid_share_percent",fixation_dwell="fixation_dwell_ms")else"value"
  rows<-lapply(indices,function(i) {
    r<-original[[i]];value<-r[[field]];inside<-isTRUE(r$condition_id %in% c(c$control_id,c$test_id))
    eligible<-inside&&brohn_number(value)&&(if(mm)isTRUE(r$eligible)else if(a$kind=="questionnaire")is.null(r$missing_reason)&&(!scale||identical(r$status,"scored"))else TRUE)
    reason<-if(!inside)"outside_selected_conditions"else if(eligible)NULL else brohn_default(r$missing_reason,if(!brohn_number(value))"value_unavailable"else"source_ineligible")
    list(source_index=i,source_container=if(scale)"analysis.scales.observations"else"analysis.observations",source_row_hash=brohn_hash(r),
      participant_id=r$participant_id,session_id=r$session_id,condition_id=r$condition_id,
      observation_id=if(scale)r$assessment_id else r$exposure_id,value=if(brohn_number(value))value else NULL,unit=c$unit,
      eligible=eligible,missing_reason=reason,source_report_id=brohn_default(r$source_report_id,report$id),
      original_source_report_hash=r$source_report_hash,original_source_row_hash=r$source_row_hash,original_source_row=r$source_row,
      definition_hash=r$definition_hash,source_record=r)
  })
  list(rows=rows,reason=NULL)
}
# Reconstruction verifies the saved weighting; saved inference is copied intact.
brohn_paired_plot_model <- function(report,comparison_id,report_hash=brohn_hash(report)) {
  catalog<-.brohn_pp_catalog(report);selection<-brohn_find(catalog,comparison_id)
  brohn_require(!is.null(selection),"Choose one of this report's saved condition comparisons.")
  c<-report$analysis$contrasts[[selection$index]]
  model<-list(schema="brohn-paired-review/1.0",report_id=report$id,report_hash=report_hash,study_id=report$study_id,origin=report$origin,
    id=comparison_id,source_id=selection$source_id,label=selection$source_label,condition_label=selection$condition_label,
    saved_contrast=c,source_report_ids=selection$source_report_ids,source_hash=brohn_hash(list(report$analysis,report$provenance)),
    observations=list(),sessions=list(),people=list(),status="unavailable",reason=NULL,
    interpretation="Paired condition summaries only. Lines connect the same person's condition means across paired visits, not sensor timestamps. No new inference is calculated.")
  unavailable<-function(reason){model$reason<-reason;model}
  source<-.brohn_pp_observations(report,c);model$observations<-source$rows
  if(!is.null(source$reason))return(unavailable(source$reason))
  if(!brohn_number(c$estimate)||identical(c$status,"unavailable"))return(unavailable(brohn_default(c$reason,"saved_estimate_unavailable")))
  if(!length(source$rows))return(unavailable("complete_observations_unavailable"))
  rows<-source$rows
  valid_identity<-vapply(rows,function(r)brohn_text(r$participant_id,500)&&brohn_text(r$session_id,500),logical(1))
  if(any(!valid_identity & vapply(rows,`[[`,logical(1),"eligible")))return(unavailable("paired_person_or_visit_identity_unavailable"))
  eligible<-Filter(function(r)isTRUE(r$eligible),rows)
  if(any(!vapply(eligible,function(r)brohn_text(r$observation_id,1000),logical(1))))return(unavailable("complete_observation_identity_unavailable"))
  identities<-vapply(eligible,function(r).brohn_pp_key(r$participant_id,r$session_id,r$condition_id,r$observation_id),character(1))
  if(anyDuplicated(identities))return(unavailable("duplicate_or_ambiguous_observation_identity"))
  if(report$analysis$kind=="multimodal"&&length(unique(vapply(eligible,function(r)brohn_default(r$definition_hash,""),character(1))))!=1L)
    return(unavailable("source_measure_definitions_disagree"))
  linked<-rows[valid_identity];keys<-vapply(linked,function(r).brohn_pp_key(r$participant_id,r$session_id),character(1))
  groups<-split(seq_along(linked),factor(keys,levels=unique(keys)))
  sessions<-lapply(groups,function(ix) {
    group<-linked[ix];a<-Filter(function(r)r$eligible&&identical(r$condition_id,c$control_id),group);b<-Filter(function(r)r$eligible&&identical(r$condition_id,c$test_id),group)
    complete<-length(a)>0L&&length(b)>0L;av<-if(length(a))mean(vapply(a,`[[`,numeric(1),"value"))else NULL;bv<-if(length(b))mean(vapply(b,`[[`,numeric(1),"value"))else NULL
    list(participant_id=group[[1L]]$participant_id,session_id=group[[1L]]$session_id,control_mean=av,test_mean=bv,
      difference=if(complete)bv-av else NULL,unit=c$unit,control_observations=length(a),test_observations=length(b),
      unavailable_observations=sum(!vapply(group,`[[`,logical(1),"eligible")),paired=complete,reason=if(complete)NULL else"condition_pair_unavailable")
  });names(sessions)<-NULL
  paired<-Filter(function(r)r$paired,sessions);saved<-c$participant_differences
  if(!length(paired)||!length(saved))return(unavailable("saved_person_differences_unavailable"))
  ids<-vapply(paired,`[[`,character(1),"participant_id");groups<-split(seq_along(paired),factor(ids,levels=unique(ids)))
  people<-lapply(groups,function(ix){s<-paired[ix];list(participant_id=s[[1L]]$participant_id,
    control_mean=mean(vapply(s,`[[`,numeric(1),"control_mean")),test_mean=mean(vapply(s,`[[`,numeric(1),"test_mean")),
    difference=mean(vapply(s,`[[`,numeric(1),"difference")),unit=c$unit,paired_sessions=length(s))});names(people)<-NULL
  saved_ids<-vapply(saved,`[[`,character(1),"participant_id");person_ids<-vapply(people,`[[`,character(1),"participant_id")
  agreement<-!anyDuplicated(saved_ids)&&setequal(saved_ids,person_ids)&&length(people)==c$participant_count&&length(paired)==c$paired_session_count&&
    .brohn_pp_near(mean(vapply(people,`[[`,numeric(1),"difference")),c$estimate)
  if(agreement)for(i in seq_along(people)) {
    retained<-saved[[match(people[[i]]$participant_id,saved_ids)]]
    if(!.brohn_pp_near(people[[i]]$difference,retained$value)||(!is.null(retained$session_count)&&retained$session_count!=people[[i]]$paired_sessions)){agreement<-FALSE;break}
    people[[i]]$difference<-retained$value
  }
  # Combined results also retain explicit visit differences and row counts.
  if(agreement&&!is.null(c$session_differences)) {
    saved_sessions<-c$session_differences;sk<-vapply(saved_sessions,function(r).brohn_pp_key(r$participant_id,r$session_id),character(1))
    pk<-vapply(paired,function(r).brohn_pp_key(r$participant_id,r$session_id),character(1))
    agreement<-!anyDuplicated(sk)&&setequal(sk,pk)
    if(agreement)for(i in seq_along(paired)){s<-saved_sessions[[match(pk[[i]],sk)]];p<-paired[[i]]
      if(!.brohn_pp_near(s$value,p$difference)||s$control_observations!=p$control_observations||s$test_observations!=p$test_observations){agreement<-FALSE;break}}
  }
  if(!agreement)return(unavailable("complete_source_disagrees_with_saved_comparison"))
  model$people<-people;model$sessions<-sessions;model$status<-"verified";model$reason<-NULL;model
}
brohn_paired_plot_load <- function(store,opened,comparison_id) {
  brohn_paired_plot_check(store,opened)
  result<-brohn_paired_plot_model(opened$body,comparison_id,opened$report_hash)
  result$report_revision<-opened$record$revision;result$result_object<-opened$record$body$result_object;result$artifact<-opened$artifact
  result
}
brohn_paired_plot_page <- function(model,page=1L,kind="people") {
  brohn_require(kind %in% c("people","sessions","observations"),"Choose paired people, visits or source observations.")
  rows<-model[[kind]];pages<-max(1L,ceiling(length(rows)/50L))
  brohn_require(brohn_number(page,1,pages,TRUE),"Choose an available paired-evidence page.")
  list(rows=if(length(rows))rows[seq.int((page-1L)*50L+1L,min(length(rows),page*50L))]else list(),page=page,pages=pages,total=length(rows),kind=kind)
}
brohn_paired_plot_csv <- function(model,path) {
  rows<-c(list(c(list(record_type="saved_comparison"),model$saved_contrast)),
    lapply(model$people,function(r)c(list(record_type="person"),r)),lapply(model$sessions,function(r)c(list(record_type="session"),r)),
    lapply(model$observations,function(r)c(list(record_type="source_observation"),r)))
  fields<-unique(c("record_type","report_id","report_revision","report_hash","source_hash","comparison_id",unlist(lapply(rows,names),use.names=FALSE)))
  con<-file(path,"wb");on.exit(close(con),add=TRUE)
  write_row<-function(cells)writeBin(charToRaw(enc2utf8(paste0(paste(paste0('"',gsub('"','""',cells,fixed=TRUE),'"'),collapse=","),"\r\n"))),con)
  write_row(fields)
  for(r in rows) {
    r$report_id<-model$report_id;r$report_revision<-model$report_revision;r$report_hash<-model$report_hash;r$source_hash<-model$source_hash;r$comparison_id<-model$id
    write_row(vapply(fields,function(f){v<-r[[f]];s<-if(is.null(v))""else if(is.numeric(v)&&length(v)==1L).brohn_pp_num(v)else if(is.character(v))v else brohn_json(v)
      if(is.character(v)&&grepl("^[=+@\\t\\r]|^-[^0-9.]",s))paste0("'",s)else s},character(1)))
  }
  invisible(path)
}

# Supervised read-only preparation. Source hydration and reconstruction can be
# expensive even inside the explicit size bound; they never run in Shiny's loop.
.brohn_pp_async_start <- function(store,operation,arguments) {
  brohn_require(operation %in% c("open","load"),"Choose a supported paired preparation.")
  folder<-tempfile("brohn-paired-review-");brohn_require(dir.create(folder),"Cannot prepare a private paired-review directory.")
  folder<-normalizePath(folder,winslash="/",mustWork=TRUE)
  request<-list(root=store$root,operation=operation,arguments=arguments,
    source_hash=digest::digest(file="R/platform-paired-plots.R",algo="sha256"))
  saveRDS(request,file.path(folder,"request.rds"),compress=FALSE)
  brohn_require(file.info(file.path(folder,"request.rds"))$size<=128*1024^2,"The paired-review request exceeds its explicit preparation bound.")
  code<-'source("R/platform-load.R",encoding="UTF-8");brohn_load(ui=FALSE);.brohn_pp_async_worker(commandArgs(TRUE)[[1L]])'
  process<-tryCatch(processx::process$new(brohn_rscript(),c("--vanilla","-e",code,folder),
    stdout=file.path(folder,"stdout.log"),stderr=file.path(folder,"stderr.log"),env=c("current",R_LIBS_USER=paste(.libPaths(),collapse=.Platform$path.sep)),cleanup_tree=TRUE,windows_hide_window=TRUE),
    error=function(e){unlink(folder,recursive=TRUE);stop(e)})
  list(process=process,folder=folder,operation=operation,started=Sys.time(),source_hash=request$source_hash)
}
.brohn_pp_async_worker <- function(folder) {
  folder<-normalizePath(folder,winslash="/",mustWork=TRUE)
  brohn_require(startsWith(basename(folder),"brohn-paired-review-"),"Use an owned paired-review directory.")
  request<-readRDS(file.path(folder,"request.rds"));store<-brohn_open_store(request$root);on.exit(brohn_close_store(store),add=TRUE)
  result<-tryCatch({
    brohn_require(identical(request$source_hash,digest::digest(file="R/platform-paired-plots.R",algo="sha256")),"The paired-review implementation changed. Reopen the saved report.")
    value<-if(request$operation=="open")do.call(brohn_paired_plot_report,c(list(store=store),request$arguments))else
      do.call(brohn_paired_plot_load,c(list(store=store),request$arguments))
    exports<-NULL
    if(request$operation=="load") {
      json<-file.path(folder,"paired-source.json");csv<-file.path(folder,"paired-evidence.csv")
      brohn_write_json_file(value,json,maximum=256*1024^2);brohn_paired_plot_csv(value,csv)
      exports<-lapply(c(json=json,csv=csv),function(path)list(path=path,size=as.numeric(file.info(path)$size),hash=digest::digest(file=path,algo="sha256")))
    }
    brohn_require(identical(request$source_hash,digest::digest(file="R/platform-paired-plots.R",algo="sha256")),"The paired-review implementation changed during preparation.")
    list(ok=TRUE,value=value,exports=exports)
  },error=function(e)list(ok=FALSE,error=conditionMessage(e)))
  saveRDS(result,file.path(folder,"result.rds"),compress=FALSE)
  invisible(NULL)
}
.brohn_pp_async_poll <- function(handle) {
  brohn_require(identical(handle$source_hash,digest::digest(file="R/platform-paired-plots.R",algo="sha256")),"The paired-review implementation changed. Reopen the report.")
  brohn_require(as.numeric(difftime(Sys.time(),handle$started,units="secs"))<300,"Paired review exceeded its five-minute preparation profile. Preserve the complete source and choose a smaller report.")
  if(handle$process$is_alive())return(NULL)
  brohn_require(identical(handle$process$get_exit_status(),0L),"Complete paired-evidence preparation failed. The saved report is unchanged; reopen and retry.")
  file<-file.path(handle$folder,"result.rds")
  brohn_require(file.exists(file)&&file.info(file)$size<=128*1024^2,"The complete paired-review result is unavailable or exceeds its explicit 128 MiB preparation profile.")
  result<-readRDS(file);brohn_require(isTRUE(result$ok),brohn_default(result$error,"Paired preparation failed."))
  for(ref in result$exports)brohn_require(ref$size<=256*1024^2&&identical(dirname(ref$path),handle$folder)&&file.exists(ref$path)&&
    identical(as.numeric(file.info(ref$path)$size),ref$size)&&identical(digest::digest(file=ref$path,algo="sha256"),ref$hash),"A prepared paired export changed or exceeds its explicit 256 MiB profile.")
  result
}
.brohn_pp_async_release <- function(handle) {
  if(is.null(handle))return(invisible(NULL))
  if(handle$process$is_alive()){handle$process$kill_tree();handle$process$wait(timeout=1000)}
  # Validate the exact absolute target before recursive cleanup on Windows.
  folder<-normalizePath(handle$folder,winslash="/",mustWork=FALSE);parent<-normalizePath(tempdir(),winslash="/",mustWork=TRUE)
  brohn_require(identical(tolower(dirname(folder)),tolower(parent))&&startsWith(basename(folder),"brohn-paired-review-"),"Private paired-review cleanup escaped its owned temporary directory.")
  unlink(folder,recursive=TRUE,force=TRUE);invisible(NULL)
}

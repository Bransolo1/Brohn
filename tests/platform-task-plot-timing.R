source("R/platform-load.R",encoding="UTF-8");brohn_load(ui=TRUE)
candidate<-Sys.getenv("BROHN_TIMING_PLOT_CANDIDATE","R/platform-task-plots.R")
source(candidate,encoding="UTF-8")
local({
  args<-commandArgs(TRUE);folder<-if(length(args))args[[1L]]else tempfile("timing-label-")
  dir.create(folder,recursive=TRUE,showWarnings=FALSE);stopifnot(!file.exists(file.path(folder,"results.json")))
  checks<-character();check<-function(label,ok){if(!isTRUE(ok))stop(label,call.=FALSE);checks<<-c(checks,label);cat("PASS",label,"\n")}
  fixture<-function(profile,known) {
    task<-brohn_task_new(profile,id=paste0("timing-",if(startsWith(profile,"gnat"))"gnat"else"legacy"));compiled<-brohn_task_compile(task)
    trials<-Filter(function(t)t$type=="task_trial",compiled$timeline);gnat<-startsWith(profile,"gnat")
    scalar<-function(x)if(is.null(x))""else if(is.character(x))x else brohn_json(x)
    identity<-list(participant_id="synthetic-person",participant_linkage=TRUE,session_id="visit",attempt_id="attempt",protocol_id="original-table",origin="sample",source_collection_id="timing-fixture")
    rows<-lapply(seq_along(trials),function(i){t<-trials[[i]];if(gnat){go<-t$expected_action=="go";outcome<-if(go)"hit"else"correct_rejection"
      return(.brohn_gnat_native_row(t,list(trial_id=t$id,outcome=outcome,response_outcome=outcome,response_code=if(go)"Space"else NULL,response_ms=if(go)200 else NULL,correct=TRUE),identity,i))}
      list(participant_id=identity$participant_id,participant_linkage="true",session_id="visit",attempt_id="attempt",protocol_id="original-table",presentation_index=as.character(i),trial_id=t$id,
        presented="true",outcome="correct",first_code=t$correct_code,final_code=t$correct_code,first_correct="true",first_response_ms="200",final_correct_ms="200",missing_reason="")})
    columns<-names(rows[[1L]]);table<-as.data.frame(stats::setNames(lapply(columns,function(c)vapply(rows,`[[`,character(1),c)),columns),stringsAsFactors=FALSE)
    prefix<-paste0(if(gnat)"gnat"else"legacy","-",if(known)"known"else"unknown")
    path<-file.path(folder,paste0(prefix,".csv"));utils::write.csv(table,path,row.names=FALSE,na="")
    data<-brohn_read_table(path,"csv",20000L)
    registry<-list(schema="brohn-implicit-protocol-registry/1.0",task=task,protocols=list(list(id="original-table",compiled_hash=brohn_hash(compiled),compiled=compiled)))
    regpath<-file.path(folder,paste0(prefix,".json"));brohn_write_json_file(registry,regpath)
    metadata<-list(task_id=task$id,source_collection_id="timing-fixture",origin_statement="Original authored software fixture; no participant timing claim.",source_software=NULL,
      source_rt_definition=if(!known)"unknown"else if(gnat)"space_ms_from_onset_no_rt_for_withholding"else"first_and_final_correct_ms_from_target_onset",
      terminal_response_rule=if(!known)"unknown"else if(gnat)"space_or_visible_deadline"else"first_response_or_fixed_deadline",evidence_level="declared_trial_summary")
    if(gnat)metadata$adapter<-.brohn_gnat_import_adapter
    aliases<-c(participant="participant_id",session="session_id",attempt="attempt_id",protocol="protocol_id",trial="trial_id")
    for(field in .brohn_task_import_columns(metadata$adapter)){base<-sub("_column$","",field);metadata[[field]]<-if(base %in% names(aliases))aliases[[base]]else base}
    original<-list(id=paste0("source-",prefix),revision=1L,hash=digest::digest(file=path,algo="sha256"),origin="sample",registry_object_hash=digest::digest(file=regpath,algo="sha256"))
    a<-brohn_import_task_trials(data,metadata,list(id="timing-study",blocks=list(task)),original,registry)$task_attempts[[1L]]
    list(attempt=a,rows=rows,task=task,compiled=compiled,registry=registry)
  }
  before_production<-digest::digest(file="R/platform-task-plots.R",algo="sha256")
  for(profile in c("gnat-brohn-single-target/1.0","rt-deary-liewald-simple/1.0"))for(known in c(TRUE,FALSE)){
    f<-fixture(profile,known);a<-f$attempt;before<-brohn_hash(a);m<-brohn_task_plot_attempt(a);v<-brohn_task_plot_selection(m)
    h<-as.character(.brohn_tp_view_ui(v));label<-paste(if(startsWith(profile,"gnat"))"GNAT"else"Legacy RT",if(known)"known"else"unknown")
    check(paste(label,"normalizes only display flag"),identical(m$timing$definition_known,known)&&identical(m$timing$definitions_known,known))
    raw<-m$timing;raw$definition_known<-NULL
    check(paste(label,"preserves original timing declaration and source hash"),identical(brohn_hash(raw),brohn_hash(a$timing_quality))&&identical(m$source_hash,before)&&identical(brohn_hash(a),before))
    check(paste(label,"visible warning matches actual declaration"),identical(grepl("The source timing or terminal-response definition is unknown.",h,fixed=TRUE),!known))
    check(paste(label,"exports keep original rows and immutable score"),identical(brohn_hash(brohn_task_plot_export(v)$complete_source$rows),brohn_hash(m$rows))&&identical(brohn_hash(m$saved_score),brohn_hash(a$score)))
    # A native-contract model is separate from these declared-summary imports.
    # Actual receiver/browser qualification is covered by the connected harness.
    ref<-list(run_id="native-contract-only",events_hash=brohn_hash("authored-contract"))
    evidence<-list(schema="brohn-native-task-export/1.0",run_id=ref$run_id,registry=f$registry,rows=f$rows,collection_origin="sample",material_origin="synthetic",
      evidence=list(events_hash=ref$events_hash,level="brohn_journal_replayed"),declarations=list(source_rt_definition=if(startsWith(profile,"gnat"))"space_ms_from_onset_no_rt_for_withholding"else"first_and_final_correct_ms_from_target_onset"))
    native<-brohn_task_plot_native(evidence,list(provenance=list(design=list(blocks=list(f$task)))),ref)
    check(paste(label,"native known model remains unchanged"),identical(native$timing$definition_known,TRUE)&&!grepl("The source timing or terminal-response definition is unknown.",as.character(.brohn_tp_view_ui(brohn_task_plot_selection(native))),fixed=TRUE))
    native$timing$definition_known<-FALSE
    check(paste(label,"explicit unknown native-model view remains unavailable"),grepl("The source timing or terminal-response definition is unknown.",as.character(.brohn_tp_view_ui(brohn_task_plot_selection(native))),fixed=TRUE))
  }
  check("Production plot file remained unchanged",identical(before_production,digest::digest(file="R/platform-task-plots.R",algo="sha256")))
  result<-list(passed=TRUE,count=length(checks),scope=if(nzchar(Sys.getenv("BROHN_TIMING_PLOT_CANDIDATE")))"External candidate"else"Current-tree original authored import and native-contract models; not browser or native receiver qualification",checks=as.list(checks),
    production_sha256=before_production,candidate_sha256=digest::digest(file=candidate,algo="sha256"))
  brohn_write_json_file(result,file.path(folder,"results.json"));cat(brohn_json(list(passed=TRUE,count=length(checks))),"\n")
})

source("R/platform-load.R",encoding="UTF-8");brohn_load(ui=TRUE)
source("tests/fixtures/gnat-journal.R")
local({
  args<-commandArgs(TRUE);folder<-if(length(args))args[[1L]]else tempfile("gnat-plots-")
  dir.create(folder,recursive=TRUE,showWarnings=FALSE);stopifnot(!file.exists(file.path(folder,"results.json")))
  checks<-character();check<-function(label,ok){if(!isTRUE(ok))stop(label,call.=FALSE);checks<<-c(checks,label);cat("PASS",label,"\n")}
  refuses<-function(expr)inherits(try(force(expr),silent=TRUE),"try-error")
  task<-brohn_gnat_new(id="original-gnat-plot");compiled<-brohn_gnat_compile(task);journal<-original_gnat_journal(compiled)
  replay<-brohn_gnat_replay(compiled,journal);trials<-Filter(function(t)t$type=="task_trial",compiled$timeline)
  identity<-list(participant_id="synthetic-person",session_id="original-session",attempt_id="one",protocol_id="original-protocol",origin="synthetic",source_collection_id="original-study")
  source_rows<-lapply(seq_along(trials),function(i).brohn_gnat_native_row(trials[[i]],replay$state$responses[[i]],identity,i))
  evidence<-list(schema="brohn-native-task-export/1.0",run_id="original-run",collection_origin="synthetic",material_origin="synthetic",
    registry=list(task=task,protocols=list(list(compiled=compiled))),rows=source_rows,
    evidence=list(events_hash=brohn_hash(journal),level="brohn_journal_replayed",compiled_hash=brohn_hash(compiled)),
    declarations=list(source_rt_definition="space_ms_from_onset_no_rt_for_withholding"))
  reference<-list(run_id=evidence$run_id,events_hash=evidence$evidence$events_hash)
  report<-list(provenance=list(design=list(blocks=list(task))))
  model<-brohn_task_plot_native(evidence,report,reference);model$report_id<-"original-report";model$report_revision<-1L;model$report_hash<-brohn_hash(report)
  v<-brohn_task_plot_selection(model);scored<-brohn_task_plot_selection(model,scope="scored")
  count<-function(view,name)Filter(function(c)c$outcome==name,view$outcome_counts)[[1L]]$count
  check("Complete native export opens all384 exact source positions",length(v$rows)==384L&&identical(vapply(v$rows,`[[`,character(1),"trial_id"),brohn_ids(trials)))
  check("Actual192 responses and192 withholding are distinct from zero missing",v$available==192L&&v$withheld==192L&&v$missing==0L)
  check("Four selected test outcome counts match independent expected totals",length(scored$rows)==240L&&identical(vapply(c("hit","miss","false_alarm","correct_rejection"),function(s)count(scored,s),numeric(1)),c(hit=87,miss=33,false_alarm=33,correct_rejection=87)))
  check("Both withholding outcomes preserve null response with actual Boolean accuracy",all(vapply(Filter(function(r)r$withholding_observed,v$rows),function(r)is.null(r$response_ms)&&is.null(r$response_code)&&identical(r$correct,r$outcome=="correct_rejection"),logical(1))))
  check("GNAT cannot select invented final-correct latency",refuses(brohn_task_plot_selection(model,"final_correct_ms")))
  check("Histogram counts only actual120 test responses",sum(vapply(scored$bins,`[[`,numeric(1),"count"))==120L&&scored$withheld==120L)
  check("Phase round cell and action remain source-bound",all(vapply(seq_along(v$rows),function(i){r<-v$rows[[i]];t<-trials[[i]];identical(r$phase,t$phase)&&identical(r$round_id,t$round_id)&&identical(r$cell_id,t$cell_id)&&identical(r$expected_action,t$expected_action)},logical(1))))
  bad<-evidence;bad$rows[[1L]]$expected_action<-if(trials[[1L]]$expected_action=="go")"nogo"else"go"
  check("False native expected action is refused",refuses(brohn_task_plot_native(bad,report,reference)))
  bad<-reference;bad$events_hash<-brohn_hash("other")
  check("Different journal identity is refused",refuses(brohn_task_plot_native(evidence,report,bad)))
  bad<-evidence;bad$rows<-head(bad$rows,50L)
  check("Native preview cannot replace complete384 source",refuses(brohn_task_plot_native(bad,report,reference)))
  bad<-evidence;at<-which(vapply(bad$rows,function(r)r$response_code=="Space",logical(1)))[1L]
  bad$rows[[at]]$response_ms<-"250.00000000000001";exact<-brohn_task_plot_native(bad,report,reference)
  check("Original decimal response lexeme survives numeric rendering",identical(exact$rows[[at]]$response_ms_source,"250.00000000000001"))
  for(width in c(320L,680L)){
    svg<-as.character(brohn_task_plot_svg(v,"outcomes",width));writeLines(svg,file.path(folder,paste0("outcomes-",width,".svg")),useBytes=TRUE)
    check(paste("Every selected outcome represented at width",width),length(gregexpr("<circle",svg,fixed=TRUE)[[1L]])==384L&&grepl("Correct rejection",svg,fixed=TRUE)&&grepl("Absent source",svg,fixed=TRUE))
    latency<-as.character(brohn_task_plot_svg(v,"chronology",width));writeLines(latency,file.path(folder,paste0("latency-",width,".svg")),useBytes=TRUE)
    check(paste("Withholding is named without fabricated zero or missing marker at width",width),length(gregexpr("withheld; no response time",latency,fixed=TRUE)[[1L]])==192L&&grepl("Dash = withheld",latency,fixed=TRUE))
  }
  html<-as.character(.brohn_tp_view_ui(v,page=8L));writeLines(html,file.path(folder,"view.html"),useBytes=TRUE)
  check("Last numerical page preserves complete384 chart with GNAT fields",grepl("Page 8 of 8",html,fixed=TRUE)&&grepl("expected action",html,fixed=TRUE)&&grepl("correct_rejection",html,fixed=TRUE)&&!grepl("distinct first and final-correct latency",html,fixed=TRUE))
  check("Complete valid source is not described as192 unavailable latencies",grepl("192 observed withheld responses with no latency; 0 unavailable",html,fixed=TRUE)&&!grepl("192 unavailable",html,fixed=TRUE))
  brohn_task_plot_csv(v,file.path(folder,"complete.csv"));csv<-brohn_read_table(file.path(folder,"complete.csv"),"csv",20000L)
  check("Complete CSV preserves all384 typed rows and original last value",nrow(csv)==384L&&identical(brohn_hash(brohn_parse(csv$exact_record_json[[384L]])),brohn_hash(v$rows[[384L]])))
  exported<-brohn_task_plot_export(scored);brohn_write_json_file(exported,file.path(folder,"scored-export.json"))
  check("Selected export retains384 original rows and240 selection plus four outcomes",length(exported$complete_source$rows)==384L&&length(exported$selected_rows)==240L&&exported$withholding_without_latency==120L&&length(exported$outcome_counts)==7L)
  # Distinct incomplete source positions use original expected trial identities.
  responses<-lapply(v$rows,function(r)list(trial_id=r$trial_id,presented=r$presented,outcome=r$outcome,response_outcome=r$response_outcome,response_code=r$response_code,
    response_ms=r$response_ms,correct=r$correct,first_correct=r$first_correct,first_response_ms=r$first_response_ms,first_response_ms_source=r$response_ms_source))
  responses[[383L]]<-list(trial_id=trials[[383L]]$id,presented=FALSE,outcome="not_presented",missing_reason="Original source says not presented.")
  responses[[382L]]$outcome<-"interrupted";responses[[382L]]$correct<-NULL;responses[[382L]]$missing_reason<-"Original focus loss."
  responses<-responses[-384L]
  audits<-lapply(seq_along(trials),function(i).brohn_gnat_import_trial_audit(trials[[i]],if(i<=length(responses))responses[[i]]else NULL,i,TRUE))
  partial<-model;partial$completion<-"incomplete";partial$rows<-.brohn_tp_trial_rows(audits,responses);p<-brohn_task_plot_selection(partial)
  check("Interrupted unpresented and absent source each keep a separate outcome lane",all(vapply(c("interrupted","not_presented","absent_source"),function(s)count(p,s)==1L,logical(1))))
  check("No incomplete-support row is counted as successful withholding",!any(vapply(tail(p$rows,3L),function(r)isTRUE(r$withholding_observed),logical(1)))&&is.null(p$rows[[384L]]$correct))
  unknown<-model;unknown$timing$definition_known<-FALSE;unknown$rows[[at]]$response_ms<-unknown$rows[[at]]$first_response_ms<-2000
  unknown$rows[[at]]$response_ms_source<-"2000";u<-brohn_task_plot_selection(unknown)
  check("Unknown timing keeps original declared numbers visibly unqualified",2000 %in% u$values&&grepl("declared numbers",as.character(.brohn_tp_view_ui(u)),fixed=TRUE))
  score<-brohn_gnat_score(compiled,replay$state$responses);score_html<-as.character(brohn_gnat_score_ui(score))
  check("Saved score supports available cells with target and context rationale",grepl("Complete cell",score_html,fixed=TRUE)&&grepl("Writing tools",score_html,fixed=TRUE)&&grepl(score$scoring_audit$context$rationale,score_html,fixed=TRUE))
  unknown_score<-brohn_gnat_score(compiled,replay$state$responses,timing_known=FALSE);unknown_html<-as.character(brohn_gnat_score_ui(unknown_score))
  check("Unknown timing saved score visibly explains unavailable sensitivity",grepl("Timing definition unknown",unknown_html,fixed=TRUE)&&grepl("Unavailable",unknown_html,fixed=TRUE))
  check("All ten GNAT cohort measures have comprehensible labels",all(vapply(score$metrics,function(m)!startsWith(.brohn_tp_label(m$name),"GNAT_"),logical(1))))
  isolated<-new.env(parent=baseenv());sys.source("R/platform-task-plots.R",isolated)
  check("Cohort catalog labels do not depend on GUI-only helpers",all(vapply(score$metrics,function(m)identical(isolated$.brohn_tp_label(m$name),.brohn_gnat_metric_label(m$name)),logical(1))))
  source_paths<-c("R/platform-gnat.R","R/platform-gnat-import.R","R/platform-gnat-views.R","R/platform-task-plots.R","R/platform-task-plot-views.R")
  result<-list(passed=TRUE,status="current_tree_component_not_browser",count=length(checks),checks=as.list(checks),source_sha256=stats::setNames(lapply(source_paths,function(p)digest::digest(file=p,algo="sha256")),source_paths))
  brohn_write_json_file(result,file.path(folder,"results.json"));cat(brohn_json(list(passed=TRUE,count=length(checks),folder=folder)),"\n")
})

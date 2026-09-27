# Complete saved choice evidence. These validators never fit, replay, or mutate
# the original scientific result. Source identity is captured at module load.
.brohn_cd_profile <- "saved-choice-display/0.1"
.brohn_cd_files <- c("R/platform-choice-display.R","R/platform-choice-display-sources.R",
 "R/platform-core.R","R/platform-store.R","R/platform-maxdiff.R","R/platform-maxdiff-import.R",
 "R/platform-maxdiff-plots.R","R/platform-maxdiff-platform.R","R/platform-question-materials.R","R/platform-report-package-sources.R",
 "R/platform-task-display.R","R/platform-task-display-sources.R","R/platform-report-package-authority.R",
 "R/platform-run-evidence.R","R/platform-questionnaire-artifacts.R","R/platform-questionnaire-artifact-storage.R",
 "R/platform-questionnaire-index.R","R/platform-questionnaire-explorer.R","R/platform-publication.R",
 "R/platform-paired-plots.R","R/platform-scales.R","R/platform-scale-comparisons.R")
.brohn_cd_loaded <- stats::setNames(lapply(.brohn_cd_files,function(p)if(file.exists(p))digest::digest(file=p,algo="sha256")else NULL),.brohn_cd_files)
.brohn_cd_runtime <- list(R=as.character(getRversion()),jsonlite=as.character(utils::packageVersion("jsonlite")),digest=as.character(utils::packageVersion("digest")))
brohn_choice_display_implementation <- function() {
 brohn_require(all(vapply(.brohn_cd_loaded,.brohn_td_sha,logical(1))),"The saved-choice preparation installation is incomplete. Restart with its exact source files.")
 list(schema="brohn-choice-display-implementation/0.1",profile=.brohn_cd_profile,sources=.brohn_cd_loaded,runtime=.brohn_cd_runtime)
}
brohn_choice_display_implementation_ref <- function() .brohn_td_implementation_ref(brohn_choice_display_implementation())
.brohn_cd_check_code <- function(x) {
 brohn_require(.brohn_td_same(x,brohn_choice_display_implementation())&&all(vapply(names(x$sources),function(p)file.exists(p)&&identical(digest::digest(file=p,algo="sha256"),x$sources[[p]]),logical(1))),"The choice preparation installation changed. Restart and prepare a new report version.")
 invisible(TRUE)
}
.brohn_cd_family <- function(a) {
 if(identical(a$kind,"questionnaire")&&length(a$choice_tasks))return("native_questionnaire")
 if(identical(a$kind,"explicit_choice")&&identical(a$parameters$schema,"brohn-maxdiff-csv-import/1.0"))return("imported_choice")
 stop("This exact report has no complete registered choice source family.",call.=FALSE)
}
.brohn_cd_array <- function(x,label,maximum=20000L)brohn_require(brohn_array(x)&&length(x)<=maximum,paste(label,"must remain a bounded original array."))
.brohn_cd_count <- function(x)brohn_number(x,0,1e9,TRUE)
.brohn_cd_strings <- function(x,maximum=100000L)brohn_array(x)&&length(x)<=maximum&&all(vapply(x,brohn_text,logical(1),max=100000))
.brohn_cd_model_identity <- function(x) {
 brohn_fields(x,c("schema","profile","sources","runtime"),label="Choice preparation identity")
 brohn_fields(x$runtime,c("R","jsonlite","digest"),label="Choice preparation runtime")
 brohn_require(identical(x$schema,"brohn-choice-display-implementation/0.1")&&identical(x$profile,.brohn_cd_profile)&&
  is.list(x$sources)&&length(x$sources)>0L&&!is.null(names(x$sources))&&!anyDuplicated(names(x$sources))&&
  all(vapply(x$sources,.brohn_td_sha,logical(1)))&&all(vapply(x$runtime,brohn_text,logical(1),max=80)),"Saved choice implementation identity is invalid.")
 invisible(TRUE)
}
brohn_validate_choice_result <- function(result) {
 r<-result
 brohn_fields(r,c("schema","kind","profile","design","design_hash","design_review","source","responses_hash","items","exposures","model","quality","limitations"),c("collection_evidence","collection_evidence_hash"),"Complete saved choice result")
 brohn_require(identical(r$schema,"brohn-maxdiff-result/1.0")&&identical(r$kind,"maxdiff")&&identical(r$profile,"object-case-paired-maxdiff/1.0"),"Unsupported complete choice result profile.")
 brohn_maxdiff_validate_responses(r$design,r$exposures)
 brohn_require(identical(r$design_hash,brohn_hash(r$design))&&identical(r$responses_hash,brohn_hash(r$exposures))&&.brohn_cd_strings(r$limitations),"Saved choice design, response hash or limitations changed.")
 brohn_fields(r$source,c("hash","origin"),c("id","revision"),"Original choice source")
 brohn_require(.brohn_td_sha(r$source$hash)&&brohn_text(r$source$origin,30)&&all(c("id","revision") %in% names(r$source))==any(c("id","revision") %in% names(r$source)),"Choice source identity is incomplete.")
 if("id" %in% names(r$source))brohn_require(brohn_text(r$source$id,240)&&brohn_number(r$source$revision,1,1e9,TRUE),"Choice source revision is invalid.")
 dr<-r$design_review
 brohn_fields(dr,c("schema","design_hash","item_count","set_count","set_sizes","item_coverage","pair_coverage","connected","all_items_present","equal_item_frequency","equal_pair_frequency","declared_positions_only","optimality_qualified","warnings"),label="Saved choice design review")
 brohn_require(identical(dr$schema,"brohn-maxdiff-design-review/1.0")&&identical(dr$design_hash,r$design_hash)&&dr$item_count==length(r$design$items)&&dr$set_count==length(r$design$sets)&&
  .brohn_cd_strings(dr$warnings)&&all(vapply(dr[c("connected","all_items_present","equal_item_frequency","equal_pair_frequency","declared_positions_only","optimality_qualified")],.brohn_td_bool,logical(1))),"Choice design review identity/counts changed.")
 .brohn_cd_array(dr$item_coverage,"Design item coverage",60L);.brohn_cd_array(dr$pair_coverage,"Design pair coverage",1770L);.brohn_cd_array(dr$set_sizes,"Design set sizes",200L)
 for(x in dr$item_coverage){brohn_fields(x,c("item_id","positions","presentations"),label="Design item coverage");brohn_require(x$item_id %in% brohn_ids(r$design$items)&&.brohn_cd_count(x$presentations)&&length(x$positions)==8L&&all(vapply(x$positions,.brohn_cd_count,logical(1))),"Invalid design item coverage.")}
 for(x in dr$pair_coverage){brohn_fields(x,c("first_id","second_id","cooccurrences"),label="Design pair coverage");brohn_require(all(c(x$first_id,x$second_id) %in% brohn_ids(r$design$items))&&.brohn_cd_count(x$cooccurrences),"Invalid design pair coverage.")}
 brohn_require(length(dr$set_sizes)==length(r$design$sets)&&all(vapply(dr$set_sizes,function(n)brohn_number(n,3,8,TRUE),logical(1))),"Saved choice set sizes are invalid.")
 # This is finite declaration-count validation, not an outcome estimator. It
 # verifies every saved item/pair/position, including zero co-occurrences.
 declared<-brohn_maxdiff_design_review(r$design)
 brohn_require(.brohn_td_same(dr,declared),"Saved design coverage does not conserve the exact declared items, pairs and positions.")
 .brohn_cd_array(r$items,"Complete choice items",60L);brohn_require(length(r$items)==length(r$design$items),"A choice result omitted declared items.")
 answered<-Filter(function(x)identical(x$status,"answered"),r$exposures);presented<-Filter(function(x)isTRUE(x$presented),r$exposures)
 for(i in seq_along(r$items)){
  x<-r$items[[i]];d<-r$design$items[[i]]
  brohn_fields(x,c("item_id","label","presented_exposures","answered_exposures","missing_exposures","best_count","worst_count","best_minus_worst","exposure_adjusted_score","denominator","observed_positions"),label="Complete choice item")
  brohn_require(identical(x$item_id,d$id)&&identical(x$label,d$label)&&identical(x$denominator,"complete_pair_exposures_containing_this_item")&&all(vapply(x[c("presented_exposures","answered_exposures","missing_exposures","best_count","worst_count")],.brohn_cd_count,logical(1)))&&length(x$observed_positions)==8L&&all(vapply(x$observed_positions,.brohn_cd_count,logical(1))),"Saved choice item identity or counts are invalid.")
  p<-Filter(function(y)d$id %in% unlist(y$item_order),presented);a<-Filter(function(y)d$id %in% unlist(y$item_order),answered)
  best<-sum(vapply(a,function(y)identical(y$best_id,d$id),logical(1)));worst<-sum(vapply(a,function(y)identical(y$worst_id,d$id),logical(1)))
  positions<-lapply(1:8,function(k)sum(vapply(p,function(y)length(y$item_order)>=k&&identical(y$item_order[[k]],d$id),logical(1))))
  brohn_require(x$presented_exposures==length(p)&&x$answered_exposures==length(a)&&x$missing_exposures==length(p)-length(a)&&x$best_count==best&&x$worst_count==worst&&x$best_minus_worst==best-worst&&
   .brohn_td_same(x$observed_positions,positions)&&.brohn_td_same(x$exposure_adjusted_score,if(length(a))(best-worst)/length(a)else NULL),"Saved choice support or adjusted value differs from its original response counts.")
 }
 q<-r$quality
 brohn_fields(q,c("exposure_records","presented_exposures","answered_exposures","missing_exposures","participant_count","participant_linkage","session_count","session_identity_policy","repeated_set_exposures","utility_estimated","individual_utilities","participant_inference_performed","scientifically_qualified"),label="Choice source quality")
 brohn_require(q$exposure_records==length(r$exposures)&&q$presented_exposures==length(presented)&&q$answered_exposures==length(answered)&&q$missing_exposures==length(presented)-length(answered)&&
  (is.null(q$participant_count)||.brohn_cd_count(q$participant_count))&&.brohn_cd_count(q$session_count)&&.brohn_cd_count(q$repeated_set_exposures)&&q$participant_linkage %in% c("all_declared","mixed","unavailable")&&
  brohn_text(q$session_identity_policy,1000)&&all(vapply(q[c("utility_estimated","individual_utilities","participant_inference_performed","scientifically_qualified")],.brohn_td_bool,logical(1)))&&
  identical(q$individual_utilities,FALSE)&&identical(q$participant_inference_performed,FALSE)&&identical(q$scientifically_qualified,FALSE),"Saved choice quality is inconsistent or claims unsupported inference.")
 m<-r$model;brohn_require(is.list(m)&&m$status %in% c("estimated","not_requested","unavailable"),"Unsupported saved choice model status.")
 fields<-c("status","utilities","reason");if(m$status!="not_requested")fields<-c(fields,"parameters","diagnostics");if(m$status=="estimated")fields<-c(fields,"probabilities")
 brohn_fields(m,fields,label="Exact saved choice model variant");.brohn_cd_array(m$utilities,"Choice utilities",60L)
 brohn_require((is.null(m$reason)||brohn_text(m$reason,10000))&&identical(q$utility_estimated,m$status=="estimated"),"Choice model status/reason is inconsistent.")
 if(m$status=="not_requested")brohn_require(!isTRUE(r$design$settings$analysis$fit_aggregate)&&!length(m$utilities)&&identical(m$reason,"aggregate_fit_disabled"),"A no-fit source cannot acquire fitted values.")
 else {
  brohn_fields(m$parameters,c("model","likelihood","reference_item","output_constraint","optimiser","maximum_iterations","relative_tolerance","mean_gradient_tolerance","maximum_information_condition","weights","uncertainty"),label="Saved choice model parameters")
  p<-m$parameters
  expected<-list(model="paired_best_worst_mnl",likelihood="exp(u_best-u_worst) divided by sum over all distinct ordered pairs in the actually offered set",reference_item=tail(brohn_ids(r$design$items),1L),output_constraint="sum_zero",optimiser="R stats::optim BFGS analytic gradient",maximum_iterations=p$maximum_iterations,relative_tolerance=1e-12,mean_gradient_tolerance=1e-6,maximum_information_condition=1e10,weights="one per complete observed pair",uncertainty="not_estimated; repeated choices and sessions are not independent participants")
  brohn_require(isTRUE(r$design$settings$analysis$fit_aggregate)&&brohn_number(p$maximum_iterations,1,5000,TRUE)&&.brohn_td_same(p,expected),"Unsupported saved choice model parameter types or registered semantics.")
  diag<-m$diagnostics;brohn_fields(diag,c("answered_exposures","connected_answered_design","finite_mle_graph"),c("message","convergence_code","evaluations","information_condition","mean_gradient_maximum","minimum_information_eigenvalue","negative_log_likelihood","null_negative_log_likelihood"),"Saved fit diagnostics")
  brohn_require(diag$answered_exposures==length(answered)&&.brohn_td_bool(diag$connected_answered_design)&&.brohn_td_bool(diag$finite_mle_graph),"Saved fit diagnostic counts changed.")
  for(k in intersect(names(diag),c("convergence_code","information_condition","mean_gradient_maximum","minimum_information_eigenvalue","negative_log_likelihood","null_negative_log_likelihood")))brohn_require(is.null(diag[[k]])||brohn_number(diag[[k]]),"Saved fit diagnostics must remain finite or explicit null.")
  if("evaluations" %in% names(diag)){brohn_fields(diag$evaluations,c("function","gradient"),label="Fit evaluation counts");brohn_require(all(vapply(diag$evaluations,.brohn_cd_count,logical(1))),"Invalid saved fit evaluation counts.")}
  if("message" %in% names(diag))brohn_require(brohn_text(diag$message,10000),"Invalid saved fit diagnostic message.")
  if(m$status=="unavailable")brohn_require(!length(m$utilities)&&!is.null(m$reason),"Unavailable choice fit must preserve its reason and empty utility array.")
  else {
   brohn_require(is.null(m$reason)&&length(m$utilities)==length(r$items),"An estimated choice fit must cover every item.")
   for(i in seq_along(m$utilities)){u<-m$utilities[[i]];brohn_fields(u,c("item_id","utility","standard_error","unit","scope"),label="Saved item utility");brohn_require(identical(u$item_id,r$items[[i]]$item_id)&&brohn_number(u$utility)&&is.null(u$standard_error)&&identical(u$unit,"relative_logit_utility")&&identical(u$scope,"aggregate_observed_complete_pairs"),"Saved utility identity, value or inference scope changed.")}
   observed_sets<-brohn_ids(r$design$sets);observed_sets<-observed_sets[observed_sets %in% vapply(answered,`[[`,character(1),"set_id")]
   .brohn_cd_array(m$probabilities,"Saved set probabilities",200L);brohn_require(identical(vapply(m$probabilities,`[[`,character(1),"set_id"),observed_sets),"Saved probability sets do not cover their actually answered sets in original design order.")
   for(i in seq_along(m$probabilities)){v<-m$probabilities[[i]];set<-brohn_find(r$design$sets,v$set_id);brohn_fields(v,c("set_id","answered_exposures","alternatives"),label="Saved set probabilities")
    brohn_require(identical(v$set_id,set$id)&&.brohn_cd_count(v$answered_exposures)&&v$answered_exposures==sum(vapply(answered,function(x)identical(x$set_id,set$id),logical(1)))&&length(v$alternatives)==length(set$item_ids)*(length(set$item_ids)-1L),"Saved set alternative coverage/support is incomplete.")
    keys<-vapply(v$alternatives,function(x){brohn_fields(x,c("best_id","worst_id","probability"),label="Saved pair probability");brohn_require(all(c(x$best_id,x$worst_id) %in% unlist(set$item_ids))&&!identical(x$best_id,x$worst_id)&&brohn_number(x$probability,0,1),"Invalid saved pair probability.");paste(x$best_id,x$worst_id,sep="|")},character(1));brohn_require(!anyDuplicated(keys),"Saved pair probabilities repeat an alternative.")
    expected_pairs<-unlist(lapply(set$item_ids,function(w)lapply(Filter(function(b)!identical(b,w),set$item_ids),function(b)paste(b,w,sep="|"))),use.names=FALSE)
    brohn_require(identical(keys,expected_pairs)&&abs(sum(vapply(v$alternatives,`[[`,numeric(1),"probability"))-1)<=1e-10,"Saved probabilities do not preserve all ordered alternatives and unit total.")
   }
  }
 }
 native<-"collection_evidence" %in% names(r)
 brohn_require(identical(native,"collection_evidence_hash" %in% names(r)),"Native choice timing and its hash must appear together.")
 if(native){.brohn_cd_array(r$collection_evidence,"Native choice timing");brohn_require(identical(r$collection_evidence_hash,brohn_hash(r$collection_evidence))&&length(r$collection_evidence)==length(r$exposures),"Native choice timing omits or changes original responses.")
  seen<-character()
  for(t in r$collection_evidence){brohn_fields(t,c("response_id","run_id","step_id","sequence","event_hash","onset_hashes","clock","response_time_ms","active_segment_response_ms","resumed"),label="Original native choice timing")
   e<-Filter(function(x)identical(x$id,t$response_id),r$exposures)
   brohn_fields(t$clock,c("id","unit","value","instance_id","time_origin_ms"),label="Original choice response clock")
   brohn_require(length(e)==1L&&identical(t$run_id,e[[1L]]$session_id)&&identical(t$response_id,paste0("md-response-",brohn_hash(list(t$run_id,t$step_id))))&&
    brohn_number(t$sequence,1,1e9,TRUE)&&.brohn_td_sha(t$event_hash)&&brohn_array(t$onset_hashes)&&length(t$onset_hashes)>=1L&&all(vapply(t$onset_hashes,.brohn_td_sha,logical(1)))&&
    .brohn_td_bool(t$resumed)&&(is.null(t$response_time_ms)||brohn_number(t$response_time_ms,0))&&(is.null(t$active_segment_response_ms)||brohn_number(t$active_segment_response_ms,0))&&
    (!isTRUE(t$resumed)||is.null(t$response_time_ms))&&all(vapply(t$clock,brohn_text,logical(1),max=240)),"Native response timing lost its exact original identity or availability.")
   seen<-c(seen,t$response_id)
  };brohn_require(!anyDuplicated(seen)&&identical(seen,vapply(r$exposures,`[[`,character(1),"id")),"Native timing must preserve complete original response order.")
 }
 invisible(TRUE)
}
.brohn_cd_source_binding <- function(report)list(report_ref=report$ref,analysis_hash=brohn_hash(report$complete_analysis),result_object=.brohn_td_object_ref(report$saved_body$result_object))
.brohn_cd_plot <- function(r,kind) {
 rows<-brohn_maxdiff_plot_rows(r,kind)
 if(kind=="adjusted"){available<-any(vapply(rows,function(x)!is.null(x$value),logical(1)));status<-if(available)"available"else"no_complete_pairs";reason<-if(available)NULL else"no_complete_pair_exposures"}
 else{status<-r$model$status;reason<-r$model$reason}
 list(schema="brohn-choice-plot-model/0.1",kind=kind,status=status,reason=reason,rows=rows)
}
.brohn_cd_evidence <- function(report,implementation) {
 a<-report$complete_analysis;family<-.brohn_cd_family(a)
 brohn_validate_complete_report_analysis(report,"task-choice-findings/0.1");.brohn_cd_model_identity(implementation)
 source<-.brohn_cd_source_binding(report)
 exercises<-lapply(seq_along(a$choice_tasks),function(i){r<-a$choice_tasks[[i]];binding<-list(index=i,hash=brohn_hash(r),exercise_id=r$design$id,profile=r$profile,design_hash=r$design_hash,responses_hash=r$responses_hash,collection_evidence_hash=r$collection_evidence_hash)
  list(key=brohn_hash(list(report_ref=report$ref,index=i,exercise_id=r$design$id,result_hash=brohn_hash(r))),result_binding=binding,original_result=r,counts_model=.brohn_cd_plot(r,"adjusted"),utilities_model=.brohn_cd_plot(r,"utility"))})
 coverage<-list(saved_analysis=list(state="complete",analysis_hash=brohn_hash(a)),exercise_count=length(exercises),exposure_count=sum(vapply(a$choice_tasks,function(r)length(r$exposures),integer(1))),item_count=sum(vapply(a$choice_tasks,function(r)length(r$items),integer(1))),
  source_rows=list(state=if(family=="imported_choice")"complete"else"not_applicable",count=if(family=="imported_choice")length(a$source_rows)else NULL),raw_cells=if(family=="imported_choice")"selected_mapped_cells_only"else"not_applicable",
  native_timing=list(state=if(family=="native_questionnaire")"complete"else"not_applicable",count=if(family=="native_questionnaire")sum(vapply(a$choice_tasks,function(r)length(r$collection_evidence),integer(1)))else NULL),
  choice_materials=list(definitions="complete",image_bytes="unsupported"),original_journal_bytes_included=FALSE,raw_recordings_included=FALSE)
 list(schema="brohn-choice-display-evidence/0.1",source_family=family,source=source,implementation=implementation,exercises=exercises,coverage=coverage)
}
brohn_validate_choice_display_evidence <- function(evidence,report) {
 brohn_fields(evidence,c("schema","source_family","source","implementation","exercises","coverage"),label="Complete saved choice display")
 brohn_require(identical(evidence$schema,"brohn-choice-display-evidence/0.1"),"Unsupported saved choice evidence schema.")
 expected<-.brohn_cd_evidence(report,evidence$implementation)
 brohn_require(.brohn_td_same(evidence,expected),"Saved choice display differs from its exact complete original source or prepared model contract.")
 invisible(TRUE)
}
.brohn_cd_catalog <- function(evidence)lapply(evidence$exercises,function(x){
 model<-function(m)list(model_hash=brohn_hash(m),status=m$status,reason=m$reason,row_count=length(m$rows),available_count=sum(vapply(m$rows,function(r)!is.null(r$value),logical(1))),unavailable_count=sum(vapply(m$rows,function(r)is.null(r$value),logical(1))),panel_cost=1L)
 r<-x$original_result
 list(kind="exercise",key=x$key,index=x$result_binding$index,exercise_id=r$design$id,title=r$design$title,profile=r$profile,result_hash=x$result_binding$hash,design_hash=r$design_hash,responses_hash=r$responses_hash,item_count=length(r$items),exposure_count=length(r$exposures),counts=model(x$counts_model),utilities=model(x$utilities_model),compatible_adapters=list("choice-counts","choice-utilities"))
})
.brohn_cd_validate_native <- function(report) {
 a<-report$complete_analysis;b<-report$saved_body
 .brohn_cd_array(a$choice_tasks,"Native choice exercises",20L);brohn_require(length(a$choice_tasks)>0L,"Complete native choice evidence is empty.")
 ids<-character()
 for(r in a$choice_tasks){brohn_validate_choice_result(r);ids<-c(ids,r$design$id)
  d<-brohn_find(b$provenance$design$maxdiff,r$design$id)
  brohn_require(!is.null(d)&&.brohn_td_same(d,r$design)&&"collection_evidence" %in% names(r)&&identical(r$source$origin,b$origin),"Native choice evidence lost its exact original design/origin/timing.")
  for(t in r$collection_evidence){run<-Filter(function(x)identical(x$run_id,t$run_id),b$provenance$runs)
   brohn_require(length(run)==1L,"Native choice timing names a run outside the original scientific membership.")}
 }
 brohn_require(!anyDuplicated(ids)&&identical(ids,brohn_ids(b$provenance$design$maxdiff)),"Native choice output omitted or reordered an original exercise.")
 invisible(TRUE)
}
.brohn_cd_validate_import <- function(report) {
 a<-report$complete_analysis;b<-report$saved_body
 brohn_fields(a,c("kind","title","choice_tasks","observations","source_rows","source_rows_hash","quality","parameters","limitations"),label="Complete imported choice analysis")
 brohn_require(identical(a$kind,"explicit_choice")&&length(a$choice_tasks)==1L&&brohn_array(a$choice_tasks)&&brohn_text(a$title,1000)&&.brohn_cd_strings(a$limitations),"Imported choice source must contain its exact selected exercise.")
 r<-a$choice_tasks[[1L]];brohn_validate_choice_result(r)
 brohn_require(!"collection_evidence" %in% names(r)&&.brohn_td_same(a$observations,r$exposures)&&identical(a$source_rows_hash,brohn_hash(a$source_rows)),"Imported choice evidence cannot invent native timing or alter duplicated exposure records.")
 p<-a$parameters;brohn_fields(p,c("schema","mapping","source","selected_exercise_hash","row_limit","identity_policy","position_policy","boolean_tokens","missing_cell_policy","origin_verification"),label="Original choice import parameters")
 brohn_require(identical(p$schema,"brohn-maxdiff-csv-import/1.0")&&identical(p$selected_exercise_hash,r$design_hash)&&.brohn_td_same(p$source,r$source)&&.brohn_td_same(p$mapping,b$provenance$mapping)&&
  identical(p$source$hash,b$provenance$source$hash)&&identical(p$source$id,b$provenance$dataset_id)&&p$source$revision==b$provenance$dataset_revision&&p$row_limit==20000L,"Imported choice source/mapping/provenance changed.")
 m<-p$mapping;columns<-unlist(m[.brohn_maxdiff_import_columns()],use.names=FALSE)
 all_columns<-unique(c(columns,unlist(m[intersect(names(m),c("exercise_column","origin_column"))],use.names=FALSE)))
 .brohn_maxdiff_import_mapping(m,all_columns)
 brohn_require(identical(m$exercise_id,r$design$id)&&.brohn_td_same(brohn_find(b$provenance$design$maxdiff,m$exercise_id),r$design),"Imported choice selected design differs from its frozen study.")
 .brohn_cd_array(a$source_rows,"Complete original choice rows");brohn_require(length(a$source_rows)>0L,"Imported choice source rows are absent.")
 selected<-list();boolean<-function(x){brohn_require(x %in% c("true","false","TRUE","FALSE","1","0"),"Original mapped boolean is invalid.");x %in% c("true","TRUE","1")};nullable<-function(x)if(identical(x,""))NULL else x
 for(i in seq_along(a$source_rows)){
  row<-a$source_rows[[i]];brohn_fields(row,c("source_row","source_row_hash","selected","response_id","reason","declared_exercise_id","declared_origin"),if(isTRUE(row$selected))"mapped_cells"else character(),"Original choice source row")
  brohn_require(row$source_row==i&&.brohn_td_sha(row$source_row_hash)&&.brohn_td_bool(row$selected)&&brohn_text(row$declared_exercise_id,240)&&(is.null(row$declared_origin)||brohn_text(row$declared_origin,30)),"Original source-row identity/type/order changed.")
  if(!row$selected){brohn_require(is.null(row$response_id)&&identical(row$reason,"different_exercise")&&!identical(row$declared_exercise_id,m$exercise_id),"Excluded choice row lost its original reason/null response.");next}
  cells<-row$mapped_cells;brohn_require(is.list(cells)&&!is.null(names(cells))&&!anyDuplicated(names(cells))&&setequal(names(cells),columns)&&all(vapply(cells,function(x)is.character(x)&&length(x)==1L&&!is.na(x),logical(1))),"Selected original mapped cells must preserve every exact text field.")
  cell<-function(k)cells[[m[[k]]]]
  identity<-paste0("md-source-row-",brohn_hash(list(source_hash=p$source$hash,source_row=i)))
  expected<-list(id=identity,participant_id=cell("participant_column"),participant_linkage=boolean(cell("participant_linkage_column")),session_id=cell("session_column"),exposure_id=cell("exposure_column"),design_hash=cell("design_hash_column"),set_id=cell("set_column"),item_order=brohn_parse(cell("item_order_column"),8192L),presented=boolean(cell("presented_column")),status=cell("status_column"),best_id=nullable(cell("best_column")),worst_id=nullable(cell("worst_column")),missing_reason=nullable(cell("missing_reason_column")))
  brohn_require(identical(row$response_id,identity)&&identical(row$reason,"selected_exercise")&&identical(row$declared_exercise_id,m$exercise_id),"Selected choice row lost its exact source identity.")
  selected[[length(selected)+1L]]<-expected
 }
 brohn_require(.brohn_td_same(selected,a$observations),"Original selected mapped rows no longer match every saved exposure in order.")
 q<-a$quality;brohn_fields(q,c("source_row_count","selected_row_count","excluded_row_count","complete_pairs","missing_pairs","unpresented_exposures","participant_count","participant_linkage","session_count","usable","scientifically_qualified"),label="Imported choice quality")
 brohn_require(q$source_row_count==length(a$source_rows)&&q$selected_row_count==length(selected)&&q$excluded_row_count==length(a$source_rows)-length(selected)&&q$complete_pairs==r$quality$answered_exposures&&q$missing_pairs==r$quality$missing_exposures&&q$unpresented_exposures==r$quality$exposure_records-r$quality$presented_exposures&&
  .brohn_td_same(q$participant_count,r$quality$participant_count)&&identical(q$participant_linkage,r$quality$participant_linkage)&&q$session_count==r$quality$session_count&&identical(q$usable,q$complete_pairs>0L)&&identical(q$scientifically_qualified,FALSE),"Original imported choice support counts are inconsistent.")
 invisible(TRUE)
}

# Supervised preparation: queue and catalog use metadata; source bytes are held
# before the parent opens a complete report or takes an original native snapshot.
.brohn_cd_context <- function(store,report_ref) {
 m<-.brohn_rpk_source_metadata(store,list(report_ref),source_admission="task-choice-findings/0.1")
 selected<-Filter(function(x).brohn_td_same(x$ref,report_ref),m$reports)
 brohn_require(length(selected)==1L&&!is.null(selected[[1L]]$choice_source_family),"Choose an exact supported choice report.")
 fields<-c("ref","study_id","origin","design_hash","source_family","choice_source_family","source_components","result_object","questionnaire_artifact","native_runs","run_sources","import_source","registry","cohort_sources","cohort_administrations")
 list(metadata=m,selected=selected[[1L]],closure=list(reports=lapply(m$reports,function(x)stats::setNames(lapply(fields,function(k)x[[k]]),fields)),objects=lapply(m$objects,.brohn_td_object_ref)))
}
.brohn_choice_display_request <- function(store,report_ref,implementation_ref=NULL) {
 authority<-brohn_report_package_queue_authority(store,"choice_display",report_ref$project_id)
 implementation<-brohn_choice_display_implementation();actual<-.brohn_td_implementation_ref(implementation)
 if(!is.null(implementation_ref))brohn_require(.brohn_td_same(actual,implementation_ref),"Choice preparation code changed. Review and prepare a new report intent explicitly.")
 c<-.brohn_cd_context(store,report_ref);m<-c$selected
 r<-list(schema="brohn-choice-display-job/0.1",project_id=report_ref$project_id,study_id=m$study_id,report_ref=report_ref,source_family=m$choice_source_family,
  analysis_descriptor=list(result_object=.brohn_td_object_ref(m$result_object),packed=m$questionnaire_artifact),original_closure=c$closure,preparation_profile=.brohn_cd_profile,implementation=implementation,authority=authority)
 r$content_fingerprint<-brohn_hash(r[setdiff(names(r),"authority")]);r
}
brohn_queue_choice_display <- function(store,report_ref,retry=FALSE,implementation_ref=NULL) {
 r<-.brohn_choice_display_request(store,report_ref,implementation_ref)
 brohn_store_batch(store,function(){old<-.brohn_rpk_latest_job(store,"choice_display",r$content_fingerprint)
  if(!is.null(old)&&(!isTRUE(retry)||old$status %in% c("queued","running","succeeded")))return(old)
  brohn_enqueue_job(store,"choice_display",r,paste0("choice-display:",r$content_fingerprint,if(isTRUE(retry))paste0(":",brohn_id("retry"))else""))})
}
brohn_choice_display_input <- function(store,job,verify=FALSE) {
 store<-brohn_report_package_job_authorize(store,job);r<-job$request
 brohn_fields(r,c("schema","project_id","study_id","report_ref","source_family","analysis_descriptor","original_closure","preparation_profile","implementation","authority","content_fingerprint"),label="Choice display request")
 brohn_require(identical(job$operation,"choice_display")&&identical(r$schema,"brohn-choice-display-job/0.1")&&identical(r$preparation_profile,.brohn_cd_profile)&&.brohn_td_same(r$implementation,brohn_choice_display_implementation())&&identical(r$content_fingerprint,brohn_hash(r[setdiff(names(r),c("authority","content_fingerprint"))])),"Choice preparation source/code identity changed.")
 c<-.brohn_cd_context(store,r$report_ref)
 brohn_require(.brohn_td_same(c$closure,r$original_closure)&&identical(r$source_family,c$selected$choice_source_family)&&identical(r$study_id,c$selected$study_id)&&identical(r$project_id,r$report_ref$project_id)&&.brohn_td_same(r$analysis_descriptor,list(result_object=.brohn_td_object_ref(c$selected$result_object),packed=c$selected$questionnaire_artifact)),"Exact original choice sources or current permission changed.")
 list(schema="brohn-analysis-input/1.0",operation="choice_display",project_id=r$project_id,report_ref=r$report_ref,content_fingerprint=r$content_fingerprint)
}
.brohn_cd_native_proof <- function(proof,report,request_hash) {
 family<-.brohn_cd_family(report$complete_analysis)
 if(family=="imported_choice"){brohn_require(is.null(proof),"Imported choice evidence cannot claim a native journal snapshot.");return(invisible(TRUE))}
 brohn_fields(proof,c("schema","report_ref","request_hash","scope","source_membership_hash","source_receipts_hash","transport_binding_hash","runs"),label="Original native choice source proof")
 b<-report$saved_body;refs<-b$provenance$runs;receipts<-b$provenance$run_evidence$runs
 first<-refs[[1L]];scope<-list(study_id=b$study_id,project_id=report$ref$project_id,deployment_id=first$deployment_id,design_hash=first$design_hash,origin=b$origin)
 brohn_fields(proof$scope,c("study_id","project_id","deployment_id","design_hash","origin"),label="Native choice source scope")
 brohn_require(identical(proof$schema,"brohn-choice-native-source-proof/0.1")&&.brohn_td_same(proof$report_ref,report$ref)&&identical(proof$request_hash,request_hash)&&.brohn_td_same(proof$scope,scope)&&identical(proof$source_membership_hash,brohn_hash(refs))&&identical(proof$source_receipts_hash,brohn_hash(receipts))&&.brohn_td_sha(proof$transport_binding_hash)&&.brohn_td_same(proof$runs,receipts)&&length(receipts)==length(refs)&&length(refs)>0L,"Native choice proof differs from the exact original scientific membership/receipts.")
 brohn_require(identical(vapply(receipts,`[[`,character(1),"run_id"),vapply(refs,`[[`,character(1),"run_id"))&&!anyDuplicated(vapply(refs,`[[`,character(1),"run_id")),"Native choice proof membership order is invalid.")
 for(i in seq_along(receipts)){r<-receipts[[i]];ref<-refs[[i]]
  brohn_fields(r,c("run_id","protocol_sha256","protocol_bytes","journal_sha256","journal_bytes","journal_rows_hash","event_count","final_sequence"),label="Original native receipt")
  brohn_require(all(vapply(r[c("protocol_sha256","journal_sha256","journal_rows_hash")],.brohn_td_sha,logical(1)))&&brohn_number(r$protocol_bytes,1,16*1024^2,TRUE)&&brohn_number(r$journal_bytes,1,64*1024^2,TRUE)&&brohn_number(r$event_count,1,1e9,TRUE)&&identical(r$event_count,r$final_sequence)&&r$final_sequence==ref$final_sequence&&identical(ref$deployment_id,scope$deployment_id)&&identical(ref$design_hash,scope$design_hash),"Native choice receipt counts/scope are invalid.")
 }
 brohn_require(sum(vapply(receipts,`[[`,numeric(1),"journal_bytes"))<=256*1024^2,"Original native journals exceed the complete preparation bound.");invisible(TRUE)
}
brohn_prepare_choice_display_execution <- function(store,job,input,scratch) {
 store<-brohn_report_package_job_authorize(store,job);.brohn_cd_check_code(job$request$implementation)
 brohn_require(.brohn_td_same(input,brohn_choice_display_input(store,job,FALSE)),"Choice input changed before preparation.")
 c<-.brohn_cd_context(store,job$request$report_ref);handle<-.brohn_rpk_hold_sources(store,c$metadata);ok<-FALSE;on.exit(if(!ok).brohn_rpk_release(handle),add=TRUE)
 all<-.brohn_rpk_complete_sources(store,handle,TRUE)$reports
 for(report in all)brohn_validate_complete_report_analysis(report,"task-choice-findings/0.1")
 report<-Filter(function(x).brohn_td_same(x$ref,job$request$report_ref),all)[[1L]];proof<-NULL
 if(.brohn_cd_family(report$complete_analysis)=="native_questionnaire"){
  refs<-report$saved_body$provenance$runs;first<-refs[[1L]];scope<-list(study_id=job$request$study_id,project_id=job$request$project_id,deployment_id=first$deployment_id,design_hash=first$design_hash,origin=report$saved_body$origin)
  original<-brohn_prepare_run_evidence_transport(store,job,scratch,lapply(refs,`[[`,"run_id"),scope);.brohn_td_transport_receipts(original,report)
  for(item in original$run_evidence$runs)for(descriptor in list(item$protocol,item$journal)){state<-handle$state;state$extra_guards<-c(state$extra_guards,list(.brohn_qexplorer_hold(file.path(scratch,descriptor$path),descriptor$bytes)))}
  proof<-list(schema="brohn-choice-native-source-proof/0.1",report_ref=report$ref,request_hash=brohn_hash(job$request),scope=scope,source_membership_hash=brohn_hash(refs),source_receipts_hash=brohn_hash(report$saved_body$provenance$run_evidence$runs),transport_binding_hash=original$run_evidence$binding_hash,runs=report$saved_body$provenance$run_evidence$runs)
 }
 .brohn_cd_native_proof(proof,report,brohn_hash(job$request))
 bundle<-list(schema="brohn-choice-display-input-bundle/0.1",report=report,guarded_reports=all,native_source_proof=proof,implementation=job$request$implementation,request_hash=brohn_hash(job$request))
 path<-file.path(scratch,"choice-display-input.json");brohn_require(!file.exists(path),"The choice bundle already exists.");brohn_write_json_file(bundle,path,maximum=128*1024^2)
 state<-handle$state;state$extra_guards<-c(state$extra_guards,list(.brohn_qexplorer_hold(path,file.info(path)$size)))
 input$choice_display<-list(schema="brohn-choice-display-prepared-input/0.1",bundle=list(file="choice-display-input.json",sha256=digest::digest(file=path,algo="sha256"),bytes=as.numeric(file.info(path)$size)))
 brohn_report_package_sources_current(store,handle);brohn_report_package_job_authorize(store,job);ok<-TRUE;list(input=input,handle=handle)
}
.brohn_cd_bundle <- function(input,scratch) {
 x<-input$choice_display;brohn_fields(x,c("schema","bundle"),label="Prepared choice input");d<-x$bundle;brohn_fields(d,c("file","sha256","bytes"),label="Sealed choice bundle")
 brohn_require(identical(x$schema,"brohn-choice-display-prepared-input/0.1")&&identical(d$file,"choice-display-input.json")&&.brohn_td_sha(d$sha256)&&brohn_number(d$bytes,1,128*1024^2,TRUE),"Prepared choice bundle descriptor is invalid.")
 path<-normalizePath(file.path(scratch,d$file),winslash="/",mustWork=TRUE);root<-normalizePath(scratch,winslash="/",mustWork=TRUE);link<-Sys.readlink(path)
 brohn_require(identical(dirname(path),root)&&(is.na(link)||!nzchar(link))&&file.info(path)$size==d$bytes&&identical(digest::digest(file=path,algo="sha256"),d$sha256),"Prepared choice bundle changed or left owned scratch.")
 b<-brohn_read_json_file(path,maximum=128*1024^2);brohn_fields(b,c("schema","report","guarded_reports","native_source_proof","implementation","request_hash"),label="Complete choice input bundle")
 brohn_require(identical(b$schema,"brohn-choice-display-input-bundle/0.1")&&.brohn_td_same(b$report$ref,input$report_ref),"Prepared choice bundle belongs to another exact source.")
 .brohn_cd_native_proof(b$native_source_proof,b$report,b$request_hash);b
}
brohn_analyse_choice_display <- function(input,scratch) {
 b<-.brohn_cd_bundle(input,scratch);.brohn_cd_check_code(b$implementation)
 for(report in b$guarded_reports)brohn_validate_complete_report_analysis(report,"task-choice-findings/0.1")
 e<-.brohn_cd_evidence(b$report,b$implementation);brohn_validate_choice_display_evidence(e,b$report)
 directory<-file.path(scratch,"artifacts");dir.create(directory,showWarnings=FALSE);path<-file.path(directory,"choice-display.json");brohn_write_json_file(e,path,maximum=64*1024^2)
 list(choice_display=list(schema="brohn-choice-display-worker-result/0.1",source_family=e$source_family,source=e$source,implementation=b$implementation,coverage=e$coverage,catalog=.brohn_cd_catalog(e),companion_catalog=.brohn_td_companion_catalog(b$report),input_binding_hash=input$content_fingerprint,
  artifact=list(file="choice-display.json",sha256=digest::digest(file=path,algo="sha256"),bytes=as.numeric(file.info(path)$size),media_type="application/json")))
}
brohn_publish_choice_display <- function(store,output,scratch,job,input,output_path) {
  store<-brohn_report_package_job_authorize(store,job,"publish");.brohn_publication_job(store,job)
  .brohn_cd_check_code(job$request$implementation)
  .brohn_publication_output_identity(output,job$request$implementation$sources)
  brohn_choice_display_input(store,job,FALSE);bundle<-.brohn_cd_bundle(input,scratch)
  brohn_require(identical(bundle$request_hash,brohn_hash(job$request))&&.brohn_td_same(bundle$implementation,job$request$implementation),"Prepared task input lost the original queued request identity.")
  m<-.brohn_cd_context(store,job$request$report_ref);sources<-.brohn_rpk_hold_sources(store,m$metadata)
  on.exit(.brohn_rpk_release(sources),add=TRUE)
  reports<-.brohn_rpk_complete_sources(store,sources,TRUE)$reports;for(source in reports)brohn_validate_complete_report_analysis(source,"task-choice-findings/0.1")
  report<-Filter(function(x).brohn_td_same(x$ref,job$request$report_ref),reports)[[1L]]
  brohn_require(.brohn_td_same(report,bundle$report),"Choice artifact source differs from its sealed original report.")
  output_guard<-.brohn_qexplorer_hold(output_path,file.info(output_path)$size);on.exit(.brohn_qexplorer_release(output_guard),add=TRUE)
  brohn_require(.brohn_td_same(brohn_read_json_file(output_path),output),"Choice worker result changed before publication.")
  result<-output$report$choice_display;brohn_fields(result,c("schema","source_family","source","implementation","coverage","catalog","companion_catalog","input_binding_hash","artifact"),label="Choice worker result")
  brohn_require(identical(result$schema,"brohn-choice-display-worker-result/0.1")&&identical(result$input_binding_hash,job$request$content_fingerprint)&&
    .brohn_td_same(result$implementation,job$request$implementation),"Choice worker result has a foreign source/preparation identity.")
  a<-result$artifact;brohn_fields(a,c("file","sha256","bytes","media_type"),label="Complete choice artifact")
  brohn_require(identical(a$file,"choice-display.json")&&identical(a$media_type,"application/json")&&brohn_number(a$bytes,1,64*1024^2,TRUE)&&.brohn_td_sha(a$sha256),"Complete choice artifact exceeds its bound or has an invalid identity.")
  path<-brohn_checked_artifact_path(store,file.path(scratch,"artifacts",a$file),scratch)
  guard<-.brohn_qexplorer_hold(path,a$bytes);on.exit(.brohn_qexplorer_release(guard),add=TRUE)
  brohn_require(file.info(path)$size==a$bytes&&identical(digest::digest(file=path,algo="sha256"),a$sha256),"Complete choice artifact failed its exact byte identity.")
  evidence<-brohn_read_json_file(path,maximum=64*1024^2);brohn_validate_choice_display_evidence(evidence,report)
  brohn_require(.brohn_td_same(evidence$source,result$source)&&identical(evidence$source_family,result$source_family)&&.brohn_td_same(evidence$implementation,result$implementation)&&
    .brohn_td_same(evidence$coverage,result$coverage)&&.brohn_td_same(.brohn_cd_catalog(evidence),result$catalog)&&.brohn_td_same(.brohn_td_companion_catalog(report),result$companion_catalog),"Choice worker metadata differs from its full verified artifact.")
  staged<-document<-NULL;committed<-FALSE
  on.exit({if(!is.null(document))brohn_close_publication(document$guard,committed);if(!is.null(staged))brohn_close_publication(staged$guard,committed)},add=TRUE)
  staged<-.brohn_publication_stage(store,job,list(list(key="choice-display",kind="choice-display",path=path,sha256=a$sha256,bytes=a$bytes,media_type=a$media_type)))
  id<-paste0("choice-display-",sub("^job[_-]","",job$id));object<-staged$descriptors[[1L]]
  body<-list(schema="brohn-saved-choice-display/0.1",study_id=job$request$study_id,project_id=job$request$project_id,source_family=result$source_family,source=result$source,
    preparation_profile=job$request$preparation_profile,implementation=result$implementation,implementation_hash=brohn_hash(result$implementation),input_binding_hash=job$request$content_fingerprint,
    artifact=.brohn_td_object_ref(object),artifact_schema="brohn-choice-display-evidence/0.1",catalog=result$catalog,companion_catalog=result$companion_catalog,coverage=result$coverage,
    producer=list(job_id=job$id,attempt=job$attempt,request_hash=brohn_hash(job$request),worker_result_hash=digest::digest(file=output_path,algo="sha256")))
  brohn_require(nchar(brohn_json(body),type="bytes")<=2*1024^2,"Choice catalog exceeds its complete metadata bound.")
  document<-.brohn_publication_stage_json(store,job,body,file.path(scratch,"published-choice-display.json"))
  receipt<-brohn_store_batch(store,function(){
    brohn_report_package_sources_current(store,sources);brohn_report_package_job_fence(store,job)
    brohn_require(.brohn_td_same(.brohn_cd_context(store,job$request$report_ref)$closure,job$request$original_closure),"Choice source authority changed before commit.")
    .brohn_cm_guard_check(list(output_guard,guard));.brohn_publication_register(store,staged)
    body$retained_document<-.brohn_td_object_ref(.brohn_publication_register(store,document)[[1L]])
    brohn_put_entity(store,"choice_display",id,body,0L,job$request$project_id)
    brohn_complete_job(store,job$id,job$worker,job$token,list(choice_display_id=id,report_id=job$request$report_ref$id,output_hash=body$retained_document$hash))
  });committed<-TRUE;receipt
}


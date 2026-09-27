# Pure task projections and saved-result sections. No store, replay or scorer.
.brohn_rpt_profiles <- c("iat-gnb2003-d1/1.0","biat-nosek2014-goodfocal/1.0","aat-keyboard-cue-balanced/1.0",
  "rt-deary-liewald-simple/1.0","rt-deary-liewald-choice/1.0","sciat-brohn-response-window-im100/1.0","gnat-brohn-single-target/1.0")
.brohn_rpt_pages <- function(display,n) {
  brohn_require(display$pages%in%c("all","selected"),"Choose all or selected numerical table pages.")
  maximum<-max(1L,ceiling(n/50L))
  if(identical(display$pages,"all")){
    brohn_require(is.null(display$page_numbers)||identical(display$page_numbers,list()),"All numerical pages cannot include a conflicting selected-page list.")
    return(as.list(seq_len(maximum)))
  }
  pages<-display$page_numbers
  brohn_require(brohn_array(pages)&&length(pages)>0L&&!anyDuplicated(unlist(pages))&&
    all(vapply(pages,function(x)brohn_number(x,1,maximum,TRUE),logical(1))),"Choose actual saved numerical table pages.")
  pages
}
brohn_resolve_task_report_section <- function(section,catalog) {
  s<-section;brohn_require(s$adapter%in%c("task-scores","task-trials","task-people")&&brohn_array(catalog),"Choose a task section and its exact prepared catalog.")
  people<-identical(s$adapter,"task-people");scores<-identical(s$adapter,"task-scores")
  expected<-if(people)"cohort_metric"else"administration"
  brohn_require(length(catalog)>0L&&!anyDuplicated(vapply(catalog,`[[`,character(1),"key")),"Prepared task catalog keys must be complete and unique.")
  choices<-Filter(function(x)identical(x$kind,expected),catalog)
  all_scope<-if(people)"all_metrics"else"all_administrations";exact_scope<-if(people)"exact_metrics"else"exact_administrations"
  exact_field<-if(people)"metrics"else"keys"
  brohn_fields(s$selector,"scope",if(identical(s$selector$scope,exact_scope))exact_field else character(),"Task section selector")
  brohn_require(s$selector$scope%in%c(all_scope,exact_scope)&&length(choices)>0L,"This source has no matching saved task section.")
  if(identical(s$selector$scope,exact_scope)){
    requested<-s$selector[[exact_field]];actual<-vapply(choices,`[[`,character(1),if(people)"metric"else"key")
    brohn_require(brohn_array(requested)&&length(requested)>0L&&!anyDuplicated(unlist(requested))&&
      all(vapply(requested,brohn_text,logical(1),max=256))&&all(unlist(requested)%in%actual),"An exact task selection is absent from this saved catalog.")
    choices<-choices[actual%in%unlist(requested)]
  }
  brohn_fields(s$display,c("pages",if(people)"charts"else if(!scores)c("measure","trial_scope","charts")),"page_numbers","Task display choices")
  models<-list();panels<-0L
  for(c in choices){
    brohn_require(.brohn_rp_hash(c$model_hash)&&is.list(c$row_counts)&&brohn_number(c$row_counts$all,0,100000,TRUE),"Prepared task catalog lacks exact model/count metadata.")
    measure<-NULL;charts<-list();n<-c$row_counts$all
    if(scores){brohn_require(brohn_number(c$row_counts$score_rows,1,100000,TRUE),"Prepared score row count is unavailable.");n<-c$row_counts$score_rows}
    else if(people){
      brohn_require(identical(s$display$charts,list("people")),"A cohort section displays saved person values only.");charts<-list("people")
    }else{
      brohn_require(s$display$measure%in%c("profile_default","first_response_ms","final_correct_ms")&&s$display$trial_scope%in%c("all","scored"),"Choose a named recorded latency and trial scope.")
      measure<-if(identical(s$display$measure,"profile_default"))c$default_measure else s$display$measure
      brohn_require(measure%in%unlist(c$compatible_measures),"This recorded latency is unavailable for the selected procedure.")
      charts<-if(identical(s$display$charts,"profile_default"))as.list(c("chronology","distribution",if(identical(c$profile,"gnat-brohn-single-target/1.0"))"outcomes"))else s$display$charts
      brohn_require(brohn_array(charts)&&length(charts)>0L&&!anyDuplicated(unlist(charts))&&all(unlist(charts)%in%unlist(c$compatible_charts)),"Choose compatible saved task figures.")
      if(identical(s$display$trial_scope,"scored")){
        brohn_require(brohn_number(c$row_counts$scored,0,c$row_counts$all,TRUE),"Profile test/scoring position count is unavailable.");n<-c$row_counts$scored
      }
    }
    .brohn_rpt_pages(s$display,n)
    models[[length(models)+1L]]<-list(key=c$key,model_hash=c$model_hash,measure=measure,charts=charts)
    panels<-panels+length(charts)
  }
  s$resolved_models<-models;list(section=s,panel_count=panels)
}

.brohn_rpt_counts <- function(a) {
  base<-if(identical(a$kind,"questionnaire")) .brohn_questionnaire_counts(a)else list()
  fields<-c("task_scores","task_attempts","source_rows","membership","attempt_metrics","per_session","per_person","summaries")
  for(k in fields)if(k%in%names(a))base[k]<-list(length(a[[k]]))
  base
}
.brohn_rpt_assets <- function(x) {
  if(!is.list(x))return(x)
  if(is.null(names(x)))return(lapply(x,.brohn_rpt_assets))
  for(k in names(x))if(k%in%c("asset","protocol_registry")&&is.list(x[[k]]))x[k]<-list(x[[k]][setdiff(names(x[[k]]),c("filename","path"))])
    else if(!k%in%c("value","original_cells","content","prompt"))x[k]<-list(.brohn_rpt_assets(x[[k]]))
  x
}
.brohn_rpt_admin_id <- function(aliases,ns,id)aliases$label(ns,"administration",id)
.brohn_rpt_attempt <- function(a,aliases,ns) {
  out<-.brohn_rp_project(a,aliases,ns,"analysis/task_attempts/*")
  out$id<-.brohn_rpt_admin_id(aliases,ns,a$id)
  source<-aliases$label(ns,"source-attempt",a$source_attempt_id,a$participant_id,a$session_id)
  out$attempt_id<-source;out$source_attempt_id<-source
  out$score$attempt_id<-out$id
  out
}
.brohn_rpt_entry <- function(entry,item,choice_profile=FALSE) {
  brohn_fields(entry,c("ref","body","evidence"),label="Prepared task source")
  .brohn_rp_ref(entry$ref,"task_display")
  brohn_require(identical(entry$ref$body_hash,brohn_hash(entry$body))&&
    identical(entry$body$schema,if(choice_profile)"brohn-saved-task-display/0.2"else"brohn-saved-task-display/0.1")&&
    .brohn_rp_same(entry$body$source,entry$evidence$source)&&
    .brohn_rp_same(entry$body$implementation,entry$evidence$implementation)&&
    .brohn_rp_same(entry$body$coverage,entry$evidence$coverage),"Prepared task metadata differs from its complete original artifact.")
  brohn_validate_task_display_evidence(entry$evidence,item)
  e<-entry$evidence;models<-c(e$administrations,e$cohort_models);catalog<-entry$body$catalog
  brohn_require(brohn_array(catalog)&&length(catalog)==length(models)&&
    .brohn_rp_same(lapply(catalog,`[[`,"key"),lapply(models,`[[`,"key")),"Prepared task catalog does not cover every saved model in original order.")
  for(i in seq_along(models)){
    m<-models[[i]];c<-catalog[[i]];people<-identical(m$plot_model$kind,"people")
    expected<-list(all=length(m$plot_model$rows),scored=if(people)NULL else sum(vapply(m$plot_model$rows,`[[`,logical(1),"profile_scored")),
      score_rows=if(people)NULL else max(1L,length(item$complete_analysis$task_scores[[m$score_binding$index]]$metrics)))
    brohn_require(identical(c$model_hash,brohn_hash(m$plot_model))&&.brohn_rp_same(c$row_counts,expected)&&
      identical(c$kind,if(people)"cohort_metric"else"administration"),"Prepared task catalog hash, role or complete row count is inconsistent.")
    if(!people){
      profile<-m$plot_model$profile;gnat<-identical(profile,"gnat-brohn-single-target/1.0")
      default<-if(profile%in%.brohn_rpt_profiles[1:2])"final_correct_ms"else"first_response_ms"
      brohn_require(profile%in%.brohn_rpt_profiles&&identical(c$profile,profile)&&identical(c$default_measure,default)&&
        .brohn_rp_same(c$compatible_measures,as.list(if(gnat)"first_response_ms"else c("first_response_ms","final_correct_ms")))&&
        .brohn_rp_same(c$compatible_charts,as.list(c("chronology","distribution",if(gnat)"outcomes"))),"Prepared task display defaults do not match the named procedure.")
    }else brohn_require(identical(c$metric,m$metric)&&identical(c$compatible_charts,list("people"))&&is.null(c$default_measure),"Prepared cohort catalog does not match its saved measure.")
  };invisible(entry)
}
# Display vocabulary only. Never used to calculate, convert or filter a metric.
.brohn_rpt_metric_vocabulary <- list(
  "correct_test_rt_mean"=list(expected_unit="ms",administration_label="Mean retained correct test-response time",individual_label="Individual mean test response time",cohort_mean_label="Mean of individual mean test response times",support_note="Retained correct test responses within the saved response-time window. Preserve the original retained count and eligibility reason."),
  "correct_test_rt_median"=list(expected_unit="ms",administration_label="Median retained correct test-response time",individual_label="Individual median test response time",cohort_mean_label="Mean of individual median test response times",support_note="Retained correct test responses within the saved response-time window. The cohort value is a mean of individual medians, not a pooled median."),
  "correct_test_rt_sd"=list(expected_unit="ms",administration_label="Retained correct response-time standard deviation",individual_label="Individual response-time standard deviation",cohort_mean_label="Mean of individual response-time standard deviations",support_note="Saved sample standard deviation requires at least two retained correct test responses. This is not the cohort between-person standard deviation."),
  "test_first_response_error_rate"=list(expected_unit="proportion",administration_label="Wrong first-response proportion in answered test trials",individual_label="Individual first-response error proportion",cohort_mean_label="Mean individual first-response error proportion",support_note="Wrong first responses divided by answered scored test trials, including recorded responses outside the response-time window; practice and no-response timeouts are excluded. Retain the saved numerator and denominator."),
  "test_omission_rate"=list(expected_unit="proportion",administration_label="No-response proportion in test trials",individual_label="Individual no-response proportion",cohort_mean_label="Mean individual no-response proportion",support_note="No-response timeouts divided by all scored test trials in the complete frozen task; practice is excluded. Retain the saved numerator and denominator."),
  "IAT_D1"=list(expected_unit="D",administration_label="IAT D1 score",individual_label="Individual IAT D1 score",cohort_mean_label="Mean individual IAT D1 score",support_note="Retain the saved contrast direction, scoring eligibility, exclusions and support. A D score is not an explicit liking rating."),
  "BIAT_D"=list(expected_unit="D",administration_label="Brief IAT D score",individual_label="Individual Brief IAT D score",cohort_mean_label="Mean individual Brief IAT D score",support_note="Retain the saved focal-category contrast direction, eligibility and exclusions. Do not infer a favourable direction from the metric name."),
  "SCIAT_target_positive_D"=list(expected_unit="D",administration_label="SC-IAT target-positive D score",individual_label="Individual SC-IAT target-positive D score",cohort_mean_label="Mean individual SC-IAT target-positive D score",support_note="Use the exact saved target-positive contrast and response-window scoring audit. Replacement scoring latencies are not recorded response times."),
  "keyboard_aat_relative_approach_advantage"=list(expected_unit="ms",administration_label="Relative keyboard approach advantage",individual_label="Individual relative keyboard approach advantage",cohort_mean_label="Mean individual relative keyboard approach advantage",support_note="Saved contrast: (avoid minus approach) for target A minus (avoid minus approach) for target B. Keep the original target identities and scoring support; do not infer liking."),
  "GNAT_r1_positive_d_prime"=list(expected_unit="dimensionless",administration_label="750 ms: target + positive sensitivity (d-prime)",individual_label="Individual 750 ms: target + positive sensitivity (d-prime)",cohort_mean_label="Mean individual 750 ms: target + positive sensitivity (d-prime)",support_note="Keep the exact saved round, pairing, expected/observed cell support and eligibility. Correct withholding has no recorded response time. Preserve original unavailable reasons and avoid new interpretation."),
  "GNAT_r1_positive_criterion"=list(expected_unit="dimensionless",administration_label="750 ms: target + positive response criterion",individual_label="Individual 750 ms: target + positive response criterion",cohort_mean_label="Mean individual 750 ms: target + positive response criterion",support_note="Keep the exact saved round, pairing, expected/observed cell support and eligibility. Correct withholding has no recorded response time. Preserve original unavailable reasons and avoid new interpretation."),
  "GNAT_r1_negative_d_prime"=list(expected_unit="dimensionless",administration_label="750 ms: target + negative sensitivity (d-prime)",individual_label="Individual 750 ms: target + negative sensitivity (d-prime)",cohort_mean_label="Mean individual 750 ms: target + negative sensitivity (d-prime)",support_note="Keep the exact saved round, pairing, expected/observed cell support and eligibility. Correct withholding has no recorded response time. Preserve original unavailable reasons and avoid new interpretation."),
  "GNAT_r1_negative_criterion"=list(expected_unit="dimensionless",administration_label="750 ms: target + negative response criterion",individual_label="Individual 750 ms: target + negative response criterion",cohort_mean_label="Mean individual 750 ms: target + negative response criterion",support_note="Keep the exact saved round, pairing, expected/observed cell support and eligibility. Correct withholding has no recorded response time. Preserve original unavailable reasons and avoid new interpretation."),
  "GNAT_r1_target_positive_contrast"=list(expected_unit="dimensionless",administration_label="750 ms target-positive contrast",individual_label="Individual 750 ms target-positive contrast",cohort_mean_label="Mean individual 750 ms target-positive contrast",support_note="Keep the saved positive-versus-negative pairing contrast and both cell support records. Do not substitute another round or infer explicit liking."),
  "GNAT_r2_positive_d_prime"=list(expected_unit="dimensionless",administration_label="600 ms: target + positive sensitivity (d-prime)",individual_label="Individual 600 ms: target + positive sensitivity (d-prime)",cohort_mean_label="Mean individual 600 ms: target + positive sensitivity (d-prime)",support_note="Keep the exact saved round, pairing, expected/observed cell support and eligibility. Correct withholding has no recorded response time. Preserve original unavailable reasons and avoid new interpretation."),
  "GNAT_r2_positive_criterion"=list(expected_unit="dimensionless",administration_label="600 ms: target + positive response criterion",individual_label="Individual 600 ms: target + positive response criterion",cohort_mean_label="Mean individual 600 ms: target + positive response criterion",support_note="Keep the exact saved round, pairing, expected/observed cell support and eligibility. Correct withholding has no recorded response time. Preserve original unavailable reasons and avoid new interpretation."),
  "GNAT_r2_negative_d_prime"=list(expected_unit="dimensionless",administration_label="600 ms: target + negative sensitivity (d-prime)",individual_label="Individual 600 ms: target + negative sensitivity (d-prime)",cohort_mean_label="Mean individual 600 ms: target + negative sensitivity (d-prime)",support_note="Keep the exact saved round, pairing, expected/observed cell support and eligibility. Correct withholding has no recorded response time. Preserve original unavailable reasons and avoid new interpretation."),
  "GNAT_r2_negative_criterion"=list(expected_unit="dimensionless",administration_label="600 ms: target + negative response criterion",individual_label="Individual 600 ms: target + negative response criterion",cohort_mean_label="Mean individual 600 ms: target + negative response criterion",support_note="Keep the exact saved round, pairing, expected/observed cell support and eligibility. Correct withholding has no recorded response time. Preserve original unavailable reasons and avoid new interpretation."),
  "GNAT_r2_target_positive_contrast"=list(expected_unit="dimensionless",administration_label="600 ms target-positive contrast",individual_label="Individual 600 ms target-positive contrast",cohort_mean_label="Mean individual 600 ms target-positive contrast",support_note="Keep the saved positive-versus-negative pairing contrast and both cell support records. Do not substitute another round or infer explicit liking.")
)
.brohn_rpt_metric_label <- function(key,context="administration") {
  entry<-.brohn_rpt_metric_vocabulary[[key]]
  if(is.null(entry))key else entry[[paste0(context,"_label")]]
}
.brohn_rpt_score_rows <- function(score,key) {
  common<-score[intersect(c("participant_id","session_id","attempt_id","task_id","profile","schema_version","scoring_recipe","status","eligible","reason"),names(score))]
  names(common)[names(common)%in%c("status","eligible","reason")]<-paste0("task_",names(common)[names(common)%in%c("status","eligible","reason")])
  common<-c(list(administration_key=key),common)
  if(!length(score$metrics))return(list(c(common,list(name=NULL,value=NULL,unit=NULL,metric_state="no_saved_metrics"))))
  lapply(score$metrics,function(m)c(common,m))
}
.brohn_rpt_scroll <- function(content,key,label,kind) {
  # Presentation only: the original cells and complete SVG remain untouched.
  instruction<-paste0(key,"-scroll-help")
  shiny::tagList(
    shiny::p(id=instruction,class="muted",if(kind=="chart")
      "Full-size chart. On a narrow screen, swipe sideways or focus the chart and use the left and right arrow keys."
      else "Wide numerical table. On a narrow screen, swipe sideways or focus the table and use the left and right arrow keys."),
    shiny::div(class=paste("brohn-task-scroll",paste0("brohn-task-",kind,"-scroll")),role="region",tabindex="0",
      `aria-label`=paste(label,":",gsub("-"," ",key)),`aria-describedby`=instruction,content))
}
.brohn_rpt_table <- function(rows,title,key,columns=NULL,maximum=50L,friendly=FALSE,metric_context=NULL) {
  table<-.brohn_rp_table(rows,title,columns,maximum,friendly)
  if(!length(rows))return(table)
  if(is.null(columns))columns<-unique(unlist(lapply(rows,names),use.names=FALSE))
  if(!is.null(metric_context)){
    # Change only the registered name column, never an equal-valued identity or
    # free-text cell. This table has one non-spanning cell per declared column.
    cell_index<-0L
    display<-function(node){if(inherits(node,"shiny.tag")){
      metric_cell<-FALSE
      if(identical(node$name,"td")){cell_index<<-cell_index+1L;metric_cell<-identical(columns[[(cell_index-1L)%%length(columns)+1L]],"name")}
      if(metric_cell&&length(node$children)==1L&&is.character(node$children[[1L]])){
        field<-node$children[[1L]];entry<-.brohn_rpt_metric_vocabulary[[field]]
        if(!is.null(entry)){node$attribs[["data-saved-field"]]<-field
          node$children<-list(shiny::tags$span(.brohn_rpt_metric_label(field,metric_context)),shiny::tags$details(shiny::tags$summary("Saved field and support"),shiny::tags$code(field),shiny::p(entry$support_note)))
          return(node)
        }
      };node$children<-lapply(node$children,display)
    }else if(is.list(node))node<-lapply(node,display);node};table<-display(table)
  }
  # Remove only the shared scroll wrapper; all caption/header/cell nodes stay exact.
  inner<-table$children[[1L]]
  inner$attribs$style<-paste0("min-width:",max(40,length(columns)*8.5),"rem;table-layout:auto")
  .brohn_rpt_scroll(inner,key,title,"table")
}
.brohn_rpt_figure <- function(node,key,label) {
  # Keep one selected figure and one canonical SVG. Its viewport is never shrunk
  # below the renderer's 680px coordinate space, so 12px labels remain legible.
  svg<-node$children[[1L]]
  node$children[[1L]]<-.brohn_rpt_scroll(shiny::div(class="brohn-task-chart-canvas",svg),key,label,"chart")
  node
}
.brohn_rpt_scroll_style <- paste0(
  ".brohn-task-scroll{overflow-x:auto;max-width:100%;overscroll-behavior-x:contain;border:1px solid #52636c;border-radius:6px}",
  ".brohn-task-scroll:focus-visible{outline:3px solid #ade9d7;outline-offset:3px}",
  ".brohn-task-table-scroll th,.brohn-task-table-scroll td{min-width:8rem;overflow-wrap:normal;word-break:normal;white-space:normal}",
  ".brohn-task-table-scroll td{font-variant-numeric:tabular-nums}",
  ".brohn-task-chart-canvas{min-width:680px;width:100%}")
.brohn_rpt_empty_svg <- function(view,chart) {
  people<-identical(view$model$kind,"people")
  title<-if(people)"Person-level results unavailable"else"No recorded latency for this selection"
  reason<-if(people)brohn_default(view$model$summary$reason,"No saved person-level values are available.")else
    paste(length(view$rows),"selected positions;",view$withheld,"observed withholding without latency;",view$missing,"unavailable latencies. No bins were calculated.")
  lines<-strwrap(reason,width=72L)
  id<-paste0("task-empty-",substr(brohn_hash(list(view$model$source_hash,view$scope,chart)),1L,18L))
  shiny::tags$svg(xmlns="http://www.w3.org/2000/svg",viewBox="0 0 680 220",role="img",focusable="false",
    `aria-labelledby`=paste(id,paste0(id,"-description")),style="display:block;width:100%;height:auto;max-width:100%;background:#11171c;border-radius:8px;font-family:system-ui,sans-serif",
    shiny::tags$title(id=id,title),shiny::tags$desc(id=paste0(id,"-description"),paste(reason,"Unavailable support is not an observed zero. Complete saved evidence accompanies this panel.")),
    shiny::tags$text(x=24,y=48,fill="#edf2f2",`font-size`=20,title),
    lapply(seq_along(lines),function(i)shiny::tags$text(x=24,y=76+i*22,fill="#edf2f2",`font-size`=14,lines[[i]])),
    shiny::tags$text(x=24,y=194,fill="#b7c4c9",`font-size`=13,"Complete saved evidence remains in the numerical companions."))
}
.brohn_rpt_write_complete <- function(entry,item,projection,aliases,ns,json,csv) {
  projected<-.brohn_rpt_project_display(entry,item,aliases,ns)
  relationships<-if(identical(entry$evidence$source_family,"saved_task_cohort")) .brohn_rpt_cohort_context(item,aliases,ns)$relationships else list()
  portable<-list(schema="brohn-portable-task-display/0.1",source_ref=entry$ref,source_report_ref=item$ref,
    original_artifact=entry$body$artifact,identifier_mode=aliases$mode,evidence=projected,identity_relationships=relationships,material_coverage=.brohn_rpt_material_coverage(item),
    projection_policy="Full saved scientific/prepared evidence; named identity fields use package labels. Original hashes identify original bytes, not transformed projections. No scorer or inference was run.")
  json(portable,paste0("evidence/tasks/",ns,".json"),"complete_task_display_projection")
  a<-projection$analysis
  for(field in intersect(c("task_scores","task_attempts","source_rows","membership","attempt_metrics","per_session","per_person","summaries"),names(a)))
    csv(a[[field]],paste0("data/tasks/",ns,"-",gsub("_","-",field),".csv"),paste0("complete_",field))
  if(length(relationships))csv(relationships,paste0("data/tasks/",ns,"-identity-relationships.csv"),"complete_exact_source_identity_relationships")
  for(i in seq_along(projected$administrations)){
    adm<-projected$administrations[[i]];stem<-paste0("data/tasks/",ns,"-administration-",sprintf("%04d",i))
    csv(adm$plot_model$rows,paste0(stem,"-positions.csv"),"complete_expected_task_positions")
    csv(.brohn_rpt_score_rows(a$task_scores[[adm$score_binding$index]],adm$key),paste0(stem,"-metrics.csv"),"complete_saved_metric_support")
    if(!is.null(adm$terminal_evidence))csv(adm$terminal_evidence$rows,paste0(stem,"-terminal.csv"),"complete_native_terminal_records")
    if(identical(adm$source_kind,"imported")){
      attempt<-a$task_attempts[[adm$score_binding$attempt_index]]
      csv(attempt$responses,paste0(stem,"-responses.csv"),"complete_imported_response_records")
      csv(attempt$trial_audit,paste0(stem,"-audit.csv"),"complete_saved_scientific_trial_audit")
    }
  }
  for(i in seq_along(projected$cohort_models))csv(projected$cohort_models[[i]]$plot_model$rows,
    paste0("data/tasks/",ns,"-metric-",sprintf("%04d",i),"-people.csv"),"complete_saved_task_person_values")
  list(entry=entry,projected=projected)
}
.brohn_rpt_section <- function(s,p,prefix,figure,json,csv,friendly) {
  task<-p$task;brohn_require(!is.null(task)&&.brohn_rp_same(s$source_ref,task$entry$ref),"Task section is not bound to its exact prepared artifact.")
  resolved<-brohn_resolve_task_report_section(s,task$entry$body$catalog)
  brohn_require(.brohn_rp_same(s$resolved_models,resolved$section$resolved_models),"Frozen task models, defaults or selected scope changed.")
  models<-c(task$projected$administrations,task$projected$cohort_models);nodes<-list(shiny::tags$style(shiny::HTML(.brohn_rpt_scroll_style)));selected_positions<-0L
  for(index in seq_along(s$resolved_models)){
    r<-s$resolved_models[[index]];matches<-Filter(function(m)identical(m$key,r$key),models);brohn_require(length(matches)==1L,"Selected task key does not resolve uniquely.");m<-matches[[1L]]
    model<-m$plot_model;key<-paste0(prefix,"-task-",sprintf("%04d",index));people<-identical(s$adapter,"task-people");scores<-identical(s$adapter,"task-scores")
    title<-if(people).brohn_rpt_metric_label(model$metric,"individual")else{
      score<-p$projection$analysis$task_scores[[m$score_binding$index]]
      label<-if(friendly).brohn_rp_friendly(score$participant_id)else score$participant_id
      visit<-if(friendly).brohn_rp_friendly(score$session_id)else score$session_id
      paste(brohn_default(score$title,model$profile),label,visit,sep=" | ")
    }
    nodes<-c(nodes,list(shiny::h3(title)))
    if(scores){
      rows<-.brohn_rpt_score_rows(score,m$key);pages<-.brohn_rpt_pages(s$display,length(rows))
      nodes<-c(nodes,list(shiny::p(paste("Saved administration status:",score$status,".",brohn_default(score$reason,""))),
        shiny::p("Each metric retains its own saved support and eligibility. No score or interval is recalculated.")))
    }else{
      view<-brohn_task_plot_selection(model,if(people)"first_response_ms"else r$measure,if(people)"all"else s$display$trial_scope)
      brohn_require(view$missing>=0&&view$available+view$missing+view$withheld==length(view$rows),"Selected latency support must conserve every position.")
      rows<-view$rows;selected_positions<-selected_positions+length(rows);pages<-.brohn_rpt_pages(s$display,length(rows))
      json(list(schema="brohn-portable-task-selection/0.1",source_ref=task$entry$ref,source_report_ref=p$item$ref,
        model_key=m$key,original_model_hash=r$model_hash,measure=r$measure,trial_scope=if(people)NULL else s$display$trial_scope,
        selected_rows=rows,available=view$available,observed_withholding=view$withheld,unavailable=view$missing,
        distribution_bins=view$bins,outcome_counts=view$outcome_counts),paste0("data/tasks/",key,"-selection.json"),"complete_selected_task_display_values")
      if(length(view$bins))csv(view$bins,paste0("data/tasks/",key,"-bins.csv"),"complete_descriptive_latency_bins")
      if(!is.null(view$outcome_counts))csv(view$outcome_counts,paste0("data/tasks/",key,"-outcomes.csv"),"complete_selected_gnat_outcomes")
      nodes<-c(nodes,list(shiny::p(paste("Collection:",model$origin,"| materials:",model$material_origin,"| evidence:",gsub("_"," ",model$evidence_level))),
        shiny::p(if(people&&is.null(model$summary$selected_person_count))paste("Unique-person support is unavailable.",model$summary$reason)else
          paste(view$available,if(people)"available person values;"else"recorded latencies;",view$withheld,"observed withholding without latency;",view$missing,"unavailable among",length(rows),"selected positions.")),
        shiny::p(if(people)paste(.brohn_rpt_metric_label(model$metric,"cohort_mean"),"(saved equal-person mean; rounded display):",.brohn_rp_text(model$summary$mean),model$unit,".",brohn_default(model$summary$reason,""))else
          paste(view$label,".",if(s$display$trial_scope=="scored")"Profile test/scoring positions are selected; this does not mean every value was retained for scoring."else"All expected positions are selected, including practice, interruptions and unavailable responses.")),
        shiny::p("Charts use the complete selected scope. Numerical page choices affect tables only. Complete source collections remain in the evidence ZIP.")))
      if(!people)nodes<-c(nodes,list(shiny::p("Recorded values and saved scoring adjustments are separate. A visible response can still be excluded from scoring. Unavailable latency is never zero; GNAT observed withholding has no latency."),
        shiny::p("Distribution bins describe all finite selected recorded values, including provisional interrupted responses. The first bin includes both edges; later bins exclude the lower edge and include the upper edge.")))
      if(people)nodes<-c(nodes,list(shiny::p("Eligible administrations were averaged within session, then eligible sessions within person, before the saved equal-person mean. This is not pooled trial arithmetic."),
        shiny::tags$details(shiny::tags$summary("Saved metric field and support"),shiny::tags$code(model$metric),shiny::p(.brohn_rpt_metric_vocabulary[[model$metric]]$support_note))))
      for(chart in r$charts){
        renderer<-brohn_task_plot_svg;environment(renderer)<-list2env(list(.brohn_tp_num=.brohn_rp_number),parent=environment(brohn_task_plot_svg))
        display_view<-view;if(people)display_view$label<-.brohn_rpt_metric_label(model$metric,"individual")
        svg<-if((people&&!length(rows))||(chart=="distribution"&&!view$available)) .brohn_rpt_empty_svg(view,chart)else
          renderer(display_view,if(chart=="people")"chronology"else chart,680L)
        chart_key<-paste0(key,"-",chart)
        node<-figure(svg,chart_key,list(source_report=p$item$ref,source=task$entry$ref,model_key=m$key,
          original_model_hash=r$model_hash,chart=chart,measure=r$measure,scope=view$scope,selected_rows=rows,distribution_bins=view$bins,outcome_counts=view$outcome_counts))
        nodes<-c(nodes,list(.brohn_rpt_figure(node,chart_key,paste(if(people)"Person values"else gsub("_"," ",chart),view$label))))
      }
      if(length(view$bins))nodes<-c(nodes,list(shiny::tags$details(shiny::tags$summary("View every bin edge and count"),.brohn_rpt_table(view$bins,"Complete descriptive latency bins",paste0(key,"-bins"),maximum=20L))))
      if(!is.null(view$outcome_counts))nodes<-c(nodes,list(.brohn_rpt_table(view$outcome_counts,"Complete selected GNAT outcome counts",paste0(key,"-outcomes-table"),maximum=7L)))
    }
    columns<-if(scores)c("name","value","unit","eligible","reason","support","task_status","task_eligible")else if(people)c("position","person_id","value","unit","eligible_attempt_count","eligible_session_count","reason")else
      c("position","trial_id","profile_scored","outcome","first_correct","first_response_ms","final_correct_ms","disposition","missing_reason")
    if(!scores&&identical(model$profile,"gnat-brohn-single-target/1.0"))columns<-c("position","trial_id","phase","round_id","expected_action","outcome_state","correct","response_ms","disposition","missing_reason")
    for(page in pages){start<-(page-1L)*50L;page_rows<-utils::head(utils::tail(rows,max(0,length(rows)-start)),50L)
      nodes<-c(nodes,list(shiny::tags$details(shiny::tags$summary(paste("View numerical table page",page,"of",max(1L,ceiling(length(rows)/50L)))),
        .brohn_rpt_table(page_rows,paste("Saved",if(scores)"metric support"else if(people)"person values"else"trial records","in selected page",page),paste0(key,"-page-",page),columns,maximum=50L,friendly=friendly,metric_context=if(scores)"administration"else NULL))))
    }
  }
  list(nodes=nodes,coverage=list(full_models=length(models),selected_models=length(s$resolved_models),selected_positions=if(identical(s$adapter,"task-scores"))NULL else selected_positions,
    numerical_pages_only=TRUE,complete_source_trimmed=FALSE))
}
.brohn_rpt_find_entry <- function(bundle,item) {
  hits<-Filter(function(x).brohn_rp_same(x$evidence$source$report_ref,item$ref),bundle$task_displays)
  needed<-length(item$complete_analysis$task_scores)>0L||item$complete_analysis$kind%in%c("implicit","implicit_cohort")
  brohn_require(length(hits)==as.integer(needed),"Each selected task report needs exactly one complete prepared task source.")
  if(!needed)return(NULL)
  .brohn_rpt_entry(hits[[1L]],item,.brohn_rpc_profile(bundle$selection));hits[[1L]]
}
brohn_report_package_panel_preflight <- function(bundle) {
  # Full-bundle worker boundary. Deliberately does not open a store, write files,
  # render images, replay journals, run scorers or modify the frozen selection.
  selection<-bundle$selection;brohn_require(identical(selection$schema,"brohn-report-package-selection/0.2"),"Task panel preflight needs the explicit new selection profile.")
  limits<-.brohn_rp_limits(bundle$limits);aliases<-.brohn_rp_alias_context(selection$contents_policy$identifier_mode,bundle$reports)
  bodies<-lapply(seq_along(bundle$reports),function(i){item<-bundle$reports[[i]]
    brohn_require(identical(item$ref$body_hash,brohn_hash(item$saved_body))&&identical(item$saved_body$id,item$ref$id)&&
      identical(item$ref$project_id,selection$project_id)&&identical(item$saved_body$study_id,selection$study_id),"Panel source differs from its exact selected study/report.")
    if(!brohn_questionnaire_is_artifact(item$saved_body$analysis))brohn_require(.brohn_rp_same(item$saved_body$analysis,item$complete_analysis),"Inline analysis changed before panel preflight.")
    else brohn_validate_questionnaire_preview(item$saved_body$analysis,item$complete_analysis,brohn_questionnaire_artifact_source(item$saved_body))
    task<-.brohn_rpt_find_entry(bundle,item);choice<-if(.brohn_rpc_profile(selection)).brohn_rpc_find_entry(bundle,item)else NULL
    .brohn_rp_projection(item,aliases,sprintf("report-%02d",i),if(is.null(task))NULL else task$evidence,if(is.null(choice))NULL else choice$evidence)
    body<-item$saved_body;body$analysis<-item$complete_analysis;list(item=item,body=body,task=task,choice=choice)
  })
  counts<-lapply(selection$sections,function(s){
    at<-which(vapply(bodies,function(x).brohn_rp_same(x$item$ref,s$source_report_ref),logical(1)))
    brohn_require(length(at)==1L,"Panel source is not a selected exact report.");p<-bodies[[at]];n<-0L
    if(s$adapter%in%c("task-scores","task-trials","task-people")){
      brohn_require(!is.null(p$task)&&.brohn_rp_same(p$task$ref,s$source_ref),"Task panel source differs from its exact prepared artifact.")
      resolved<-brohn_resolve_task_report_section(s,p$task$body$catalog)
      brohn_require(.brohn_rp_same(s$resolved_models,resolved$section$resolved_models),"Frozen task panel resolution changed.");n<-resolved$panel_count
    }else if(s$adapter%in%c("choice-counts","choice-utilities")){
      brohn_require(.brohn_rpc_profile(selection)&&!is.null(p$choice)&&.brohn_rp_same(p$choice$ref,s$source_ref),"Choice panel source differs from the exact required preparation.")
      resolved<-brohn_resolve_choice_report_section(s,p$choice$body$catalog)
      brohn_require(.brohn_rp_same(s$resolved_models,resolved$section$resolved_models),"Frozen choice panel resolution changed.");n<-resolved$panel_count
    }else if(identical(s$adapter,"gaze-context")){
      brohn_require(.brohn_rp_same(s$source_ref,s$source_report_ref),"Gaze panel source changed.")
      model<-brohn_gaze_report_model(p$body);groups<-model$groups
      if(identical(s$selector$scope,"exact_exposure"))groups<-Filter(function(g)identical(g$key,s$selector$exposure_key),groups)
      brohn_require(s$selector$scope%in%c("all_exposures","exact_exposure")&&(s$selector$scope!="exact_exposure"||length(groups)==1L),"Choose an exact saved gaze exposure.");n<-length(groups)
    }else if(identical(s$adapter,"explicit-distribution")){
      hits<-Filter(function(x).brohn_rp_same(x$ref,s$source_ref),bundle$distributions);brohn_require(length(hits)==1L,"Saved distribution panel source is unavailable.");d<-hits[[1L]]
      brohn_require(identical(d$ref$body_hash,brohn_hash(d$body))&&identical(d$body$result$binding$report_id,p$item$ref$id)&&
        identical(d$body$result$binding$report_hash,p$item$ref$body_hash),"Distribution panel source binding changed.")
      groups<-d$body$result$groups
      if(s$selector$scope=="exact_item_condition")groups<-Filter(function(g)identical(g$family,s$selector$family)&&identical(g$item_id,s$selector$item_id)&&.brohn_rp_same(g$condition_id,s$selector$condition_id),groups)
      brohn_require(.brohn_rp_same(s$resolved_group_ids,lapply(groups,`[[`,"id")),"Frozen distribution groups changed before panel count.")
      for(g in groups){rows<-.brohn_ed_rows(g);offsets<-if(s$display$pages=="all")as.list(if(length(rows))seq(0L,length(rows)-1L,by=20L)else 0L)else s$display$offsets
        brohn_require(brohn_array(offsets)&&length(offsets)>0L&&!anyDuplicated(unlist(offsets))&&all(vapply(offsets,function(v)brohn_number(v,0,max(0,length(rows)-1L),TRUE)&&v%%20L==0L,logical(1))),"Choose actual distribution pages before panel count.")
        for(offset in offsets)if(!is.null(brohn_explicit_distribution_svg(g,offset,720L,binding=d$body$result$binding)))n<-n+1L
      }
    }else{
      brohn_require(identical(s$adapter,"paired-findings")&&.brohn_rp_same(s$source_ref,s$source_report_ref),"Unsupported panel source.")
      if(p$body$analysis$kind=="questionnaire")brohn_require(nchar(brohn_json(p$body$analysis),type="bytes")<=limits$max_paired_questionnaire_bytes,"Complete questionnaire exceeds the paired figure hydration profile.")
      choices<-.brohn_pp_catalog(p$body)
      if(s$selector$scope=="exact_comparison"){
        choices<-Filter(function(x)identical(x$id,s$selector$comparison_id),choices)
        brohn_require(length(choices)==1L&&identical(brohn_hash(p$body$analysis$contrasts[[choices[[1L]]$index]]),s$selector$contrast_hash),"Saved paired comparison changed before panel count.")
      }
      for(c in choices){m<-brohn_paired_plot_model(p$body,c$id,p$item$ref$body_hash)
        if(identical(m$status,"verified"))n<-n+length(.brohn_rpt_pages(s$display,length(m$people)))*length(s$display$charts)
      }
    }
    list(section_id=s$id,panel_count=n)
  })
  total<-sum(vapply(counts,`[[`,numeric(1),"panel_count"))
  if(total>limits$max_panels)return(list(schema="brohn-report-package-refusal/0.1",reason_code="panel_limit",resolved_panel_count=total,maximum_panels=limits$max_panels,section_counts=counts))
  list(schema="brohn-report-package-panel-preflight/0.1",passed=TRUE,resolved_panel_count=total,maximum_panels=limits$max_panels,section_counts=counts)
}
.brohn_rpt_original_cells <- function(row,mapping,aliases,ns) {
  out<-row;cells<-row$original_cells
  person<-cells[[mapping$participant_column]];session<-cells[[mapping$session_column]]
  for(role in c("participant","session","attempt")){
    column<-mapping[[paste0(role,"_column")]]
    # Blank identities in an excluded raw row remain blank, not new people.
    if(!is.null(column)&&column%in%names(cells)&&!identical(cells[[column]],""))out$original_cells[column]<-list(switch(role,
      participant=aliases$label(ns,"person",cells[[column]]),
      session=aliases$label(ns,"session",cells[[column]],person),
      attempt=aliases$label(ns,"source-attempt",cells[[column]],person,session)))
  };out
}
.brohn_rpt_material_coverage <- function(item) {
  materials<-unlist(lapply(item$saved_body$provenance$design$blocks,`[[`,"materials"),recursive=FALSE,use.names=FALSE)
  images<-Filter(function(m)identical(m$type,"image"),materials)
  list(source_report_ref=item$ref,definitions="complete",material_count=length(materials),image_material_count=length(images),
    image_bytes="unsupported_in_this_adapter",reason="Task material definitions and immutable image references are retained. Task material image bytes and context panels are not included; the optional image setting covers gaze stimuli only.")
}
.brohn_rpt_cohort_context <- function(item,aliases,ns) {
  a<-item$complete_analysis;p<-item$saved_body$provenance
  rows<-lapply(a$membership,function(m){
    binding<-Filter(function(b)identical(b$attempt_id,m$attempt_id)&&identical(b$attempt_hash,m$attempt_hash),p$source_administrations)
    brohn_require(length(binding)==1L,"A cohort member has no unique exact original report/administration binding.")
    refs<-Filter(function(r)identical(r$id,binding[[1L]]$report_id),p$source_reports)
    brohn_require(length(refs)==1L,"A cohort source reference is ambiguous.");ref<-refs[[1L]]
    source_ns<-aliases$resolve(ns,ref$id,ref$body_hash,ref$revision)
    list(original=m,source_namespace=source_ns,source_ref=list(kind="report",id=ref$id,revision=ref$revision,body_hash=ref$body_hash,project_id=item$ref$project_id))
  })
  member<-function(id){hits<-Filter(function(x)identical(x$original$attempt_id,id),rows);brohn_require(length(hits)==1L,"A cohort identity has no exact saved administration.");hits[[1L]]}
  # Reviewed identities and original collection codes have distinct roles.
  source_person<-function(collection,person)if(identical(aliases$mode,"source_identifiers"))person else aliases$label(ns,"source-person",brohn_json(list(collection,person)))
  source_session<-function(collection,person,session)if(identical(aliases$mode,"source_identifiers"))session else aliases$label(ns,"source-session",brohn_json(list(collection,person,session)))
  person<-function(id)aliases$label(ns,"person",id)
  session<-function(id,person_id)aliases$label(ns,"session",id,person_id)
  administration<-function(id){m<-member(id);.brohn_rpt_admin_id(aliases,m$source_namespace,id)}
  project_map<-function(map){out<-map
    out$participants<-lapply(map$participants,function(r){o<-r;o$participant_id<-source_person(r$source_collection_id,r$participant_id);o["person_id"]<-list(person(r$person_id));o})
    out$sessions<-lapply(map$sessions,function(r){o<-r;matching<-Filter(function(p)identical(p$source_collection_id,r$source_collection_id)&&identical(p$participant_id,r$participant_id),map$participants)
      brohn_require(length(matching)<=1L,"A reviewed original person code is ambiguous.");reviewed<-if(length(matching))matching[[1L]]$person_id else NULL
      o$participant_id<-source_person(r$source_collection_id,r$participant_id);o$source_session_id<-source_session(r$source_collection_id,r$participant_id,r$source_session_id)
      o["session_id"]<-list(session(r$session_id,reviewed));o});out}
  project_plan<-function(plan){out<-plan;out$membership<-lapply(plan$membership,function(r){r$attempt_id<-administration(r$attempt_id);r});out}
  relationships<-lapply(rows,function(x){m<-x$original;list(source_report_ref=x$source_ref,
    administration_id=administration(m$attempt_id),source_attempt_hash=m$attempt_hash,
    source_person_id=aliases$label(x$source_namespace,"person",m$source_participant_id),
    source_session_id=aliases$label(x$source_namespace,"session",m$source_session_id,m$source_participant_id),
    source_attempt_id=aliases$label(x$source_namespace,"source-attempt",m$source_attempt_id,m$source_participant_id,m$source_session_id),
    crosswalk_source_person_id=source_person(m$source_collection_id,m$source_participant_id),
    crosswalk_source_session_id=source_session(m$source_collection_id,m$source_participant_id,m$source_session_id),
    reviewed_person_id=person(m$person_id),reviewed_session_id=session(m$session_id,m$person_id),linked=m$linked)})
  list(rows=rows,member=member,person=person,session=session,administration=administration,source_person=source_person,source_session=source_session,
    project_map=project_map,project_plan=project_plan,relationships=relationships)
}
.brohn_rpt_cohort_analysis <- function(item,aliases,ns) {
  a<-item$complete_analysis;out<-a;c<-.brohn_rpt_cohort_context(item,aliases,ns)
  out$membership<-lapply(a$membership,function(m){o<-m;o$attempt_id<-c$administration(m$attempt_id);o["person_id"]<-list(c$person(m$person_id));o["session_id"]<-list(c$session(m$session_id,m$person_id))
    o$source_participant_id<-c$source_person(m$source_collection_id,m$source_participant_id);o$source_session_id<-c$source_session(m$source_collection_id,m$source_participant_id,m$source_session_id)
    original<-c$member(m$attempt_id);o$source_attempt_id<-aliases$label(original$source_namespace,"source-attempt",m$source_attempt_id,m$source_participant_id,m$source_session_id);o})
  out$attempt_metrics<-lapply(a$attempt_metrics,function(r){o<-r;o$attempt_id<-c$administration(r$attempt_id);o["person_id"]<-list(c$person(r$person_id));o["session_id"]<-list(c$session(r$session_id,r$person_id));o})
  out$per_session<-lapply(a$per_session,function(r){o<-r;o["person_id"]<-list(c$person(r$person_id));o["session_id"]<-list(c$session(r$session_id,r$person_id))
    o$attempt_ids<-lapply(r$attempt_ids,c$administration);o$contributing_attempt_ids<-lapply(r$contributing_attempt_ids,c$administration);o})
  out$per_person<-lapply(a$per_person,function(r){o<-r;o["person_id"]<-list(c$person(r$person_id));o$contributing_session_ids<-lapply(r$contributing_session_ids,c$session,person_id=r$person_id);o})
  out$provenance$plan<-c$project_plan(a$provenance$plan);out$provenance$identity_map<-c$project_map(a$provenance$identity_map);out
}
.brohn_rpt_analysis <- function(item,evidence,aliases,ns) {
  a<-item$complete_analysis
  if(identical(evidence$source_family,"saved_task_cohort"))return(.brohn_rpt_cohort_analysis(item,aliases,ns))
  out<-.brohn_rp_project(a,aliases,ns)
  if(identical(evidence$source_family,"imported_implicit")){
    out$task_attempts<-lapply(a$task_attempts,.brohn_rpt_attempt,aliases=aliases,ns=ns)
    out$task_scores<-lapply(a$task_scores,function(s){o<-.brohn_rp_project(s,aliases,ns);o$attempt_id<-.brohn_rpt_admin_id(aliases,ns,s$attempt_id);o})
    out$source_rows<-lapply(a$source_rows,.brohn_rpt_original_cells,mapping=a$parameters$mapping,aliases=aliases,ns=ns)
    out$parameters<-.brohn_rpt_assets(out$parameters)
  };out
}
.brohn_rpt_provenance <- function(p,item,evidence,aliases,ns) {
  out<-.brohn_rpt_assets(p)
  if(identical(evidence$source_family,"saved_task_cohort")){
    c<-.brohn_rpt_cohort_context(item,aliases,ns)
    out$plan<-c$project_plan(p$plan);out$identity_map<-c$project_map(p$identity_map)
    out$source_administrations<-lapply(p$source_administrations,function(r){r$attempt_id<-c$administration(r$attempt_id);r})
  };out
}
.brohn_rpt_evidence_aliases <- function(aliases,binding) {
  if(!identical(binding$kind,"native")||identical(aliases$mode,"source_identifiers"))return(aliases)
  result<-aliases;label<-aliases$label;owner<-aliases$owner
  canonical_person<-function(x)if(identical(x,binding$evidence_person_id))binding$score_person_id else x
  result$label<-function(namespace,kind,id,person=NULL,session=NULL){
    if(kind=="person")id<-canonical_person(id)
    person<-canonical_person(person);label(namespace,kind,id,person,session)
  }
  result$owner<-function(namespace,session,person=NULL)owner(namespace,session,canonical_person(person));result
}
.brohn_rpt_prepared_bindings <- function(bundle) {
  brohn_require(brohn_array(bundle$task_displays),"Prepared task sources must be an ordered array.")
  choice_profile<-.brohn_rpc_profile(bundle$selection)
  if(choice_profile)brohn_require(brohn_array(bundle$choice_displays),"Prepared choice sources must be an ordered array.")
  actual<-list()
  for(item in bundle$reports){
    distributions<-Filter(function(d)identical(d$body$result$binding$report_id,item$ref$id)&&identical(d$body$result$binding$report_hash,item$ref$body_hash),bundle$distributions)
    tasks<-Filter(function(d).brohn_rp_same(d$evidence$source$report_ref,item$ref),bundle$task_displays)
    brohn_require(length(distributions)<=1L&&length(tasks)<=1L,"An exact source report has duplicate preparations.")
    if(length(distributions)){
      d<-distributions[[1L]];ref<-d$body$preparation_implementation_ref
      brohn_require(is.list(ref)&&brohn_text(ref$profile,128)&&.brohn_rp_hash(ref$hash),"New-profile explicit distributions need their pinned preparation identity.")
      if(choice_profile)brohn_require(identical(ref$profile,"saved-explicit-distribution/0.2")&&identical(d$body$source_admission,"task-choice-findings/0.1"),"Choice-profile explicit distributions require the exact complete mixed-source admission.")
      actual[[length(actual)+1L]]<-list(adapter="explicit-distribution",source_report_ref=item$ref,prepared_ref=d$ref,implementation_ref=ref)
    }
    if(length(tasks)){d<-tasks[[1L]];actual[[length(actual)+1L]]<-list(adapter="task-display",source_report_ref=item$ref,prepared_ref=d$ref,
      implementation_ref=list(profile=d$body$implementation$profile,hash=brohn_hash(d$body$implementation)))}
    if(choice_profile){choices<-Filter(function(d).brohn_rp_same(d$evidence$source$report_ref,item$ref),bundle$choice_displays)
      brohn_require(length(choices)<=1L,"An exact source report has duplicate choice preparations.")
      if(length(choices)){d<-choices[[1L]];actual[[length(actual)+1L]]<-list(adapter="choice-display",source_report_ref=item$ref,prepared_ref=d$ref,
        implementation_ref=list(profile=d$body$implementation$profile,hash=brohn_hash(d$body$implementation)))}
    }
  }
  brohn_require(length(actual)==length(bundle$distributions)+length(bundle$task_displays)+(if(choice_profile)length(bundle$choice_displays)else 0L)&&
    .brohn_rp_same(actual,bundle$selection$prepared_sources),"Complete prepared sources differ from the frozen exact order or implementation.")
  invisible(TRUE)
}
.brohn_rpt_project_display <- function(entry,item,aliases,ns) {
  evidence<-entry$evidence;out<-evidence;projected_analysis<-.brohn_rpt_analysis(item,evidence,aliases,ns)
  out$administrations<-lapply(evidence$administrations,function(a){o<-a;b<-a$identity_binding;local<-.brohn_rpt_evidence_aliases(aliases,b)
    model<-.brohn_rp_project(a$plot_model,local,ns,"task/plot_model")
    score<-projected_analysis$task_scores[[a$score_binding$index]]
    if(identical(a$source_kind,"native")){
      o$identity_binding$score_person_id<-aliases$label(ns,"person",b$score_person_id)
      o$identity_binding$evidence_person_id<-local$label(ns,"person",b$evidence_person_id)
      for(k in c("run_id","score_session_id","evidence_session_id"))o$identity_binding[k]<-list(local$label(ns,"session",b[[k]],b$evidence_person_id))
      step<-local$label(ns,"step",b$task_step_id,b$evidence_person_id,b$evidence_session_id);o$identity_binding$task_step_id<-step
      terminal<-.brohn_rp_project(a$terminal_evidence,local,ns,"task/terminal_evidence",b$evidence_person_id,b$evidence_session_id)
      terminal$task_step_id<-step
      for(i in seq_along(terminal$rows))terminal$rows[[i]]$attempt_id<-step
      o$terminal_evidence<-.brohn_rpt_assets(terminal)
      model$label<-paste(score$participant_id,score$session_id,score$title,sep=" | ")
    }else{
      source<-item$complete_analysis$task_attempts[[a$score_binding$attempt_index]];attempt<-projected_analysis$task_attempts[[a$score_binding$attempt_index]]
      o$identity_binding$canonical_attempt_id<-attempt$id;o$identity_binding$source_attempt_id<-attempt$source_attempt_id
      o$identity_binding$participant_id<-attempt$participant_id;o$identity_binding$session_id<-attempt$session_id
      model$id<-attempt$id;model$identity$id<-attempt$id;model$identity$attempt_id<-attempt$source_attempt_id;model$saved_score<-score
      model$label<-paste(attempt$participant_id,attempt$session_id,attempt$profile,sep=" | ")
    }
    o$plot_model<-model;o
  })
  if(identical(evidence$source_family,"saved_task_cohort")){
    c<-.brohn_rpt_cohort_context(item,aliases,ns)
    out$cohort_models<-lapply(evidence$cohort_models,function(m){o<-m
      o$plot_model$rows<-lapply(m$plot_model$rows,function(r){v<-r;v["person_id"]<-list(c$person(r$person_id));v$contributing_session_ids<-lapply(r$contributing_session_ids,c$session,person_id=r$person_id);v})
      o$plot_model$source<-projected_analysis$provenance;o})
  }
  out
}

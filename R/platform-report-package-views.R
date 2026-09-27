# Researcher UI only. These functions render bounded metadata supplied by the
# package backend; they never open source objects or perform scientific work.
.brohn_rpv_key <- function(x) substr(brohn_hash(x),1L,24L)
.brohn_rpv_same <- function(a,b) identical(brohn_json(a),brohn_json(b))
.brohn_rpv_adapter_label <- function(adapter) switch(adapter,
  `gaze-context`="Gaze views",`explicit-distribution`="Response distributions",
  `paired-findings`="Saved comparisons",`task-scores`="Task scores",
  `task-trials`="Task response patterns",`task-people`="Saved task results by person",
  `choice-counts`="Best-worst results",`choice-utilities`="Saved choice model","Other findings")
.brohn_rpv_task_adapter <- function(adapter) adapter%in%c("task-scores","task-trials","task-people")
.brohn_rpv_choice_adapter <- function(adapter) adapter%in%c("choice-counts","choice-utilities")
.brohn_rpv_component <- function(row,component) {
  if(!is.null(row$source_components))return(component%in%unlist(row$source_components,use.names=FALSE))
  # Older catalog fixtures/metadata predate independent components. Their task
  # family retains its original meaning; choice admission requires new metadata.
  identical(component,"task")&&isTRUE(row$source_family%in%c("native_questionnaire","imported_implicit","saved_task_cohort"))
}
.brohn_rpv_has_component <- function(rows,component) any(vapply(rows,.brohn_rpv_component,logical(1),component=component))
.brohn_rpv_profiles <- function(rows) {
  choice<-.brohn_rpv_has_component(rows,"choice");task<-.brohn_rpv_has_component(rows,"task")
  list(renderer_profile=if(choice)"controlled-gaze-explicit-task-choice-paired/0.1"else if(task)"controlled-gaze-explicit-task-paired/0.1"else"controlled-gaze-explicit-paired/0.1",
    limits_profile=if(choice)"controlled-task-choice-report-package/0.1"else if(task)"controlled-task-report-package/0.1"else"controlled-report-package/0.1")
}
.brohn_rpv_waiting <- function(dependencies) {
  if(!length(dependencies))return("Preparing saved views")
  kinds<-unique(vapply(dependencies,function(d)brohn_default(d$kind,"explicit_distributions"),character(1)))
  paste(vapply(kinds,function(kind){ds<-Filter(function(d)identical(brohn_default(d$kind,"explicit_distributions"),kind),dependencies)
    label<-if(kind=="task_display")"Saved task views"else if(kind=="choice_display")"Saved best-worst views"else if(kind=="explicit_distributions")"Response distributions"else"Saved views"
    statuses<-vapply(ds,function(d)brohn_default(d$status,if(!is.null(d$result_ref))"succeeded"else"queued"),character(1))
    paste(label,if(all(statuses=="succeeded"))"ready"else if(any(statuses%in%c("failed","cancelled")))"need attention"else"preparing")
  },character(1)),collapse="; ")
}
.brohn_rpv_status <- function(status,dependencies=list()) switch(status,
  prepared="Choices saved",waiting_for_display=.brohn_rpv_waiting(dependencies),
  ready_to_freeze="Preparing report contents",assembly_queued="Building the report",
  succeeded="Report ready",needs_authority="Resume with current access",
  needs_attention="Check report contents",failed="Preparation needs attention",
  cancelled="Preparation cancelled",superseded="Replaced by newer choices","Saved preparation")
.brohn_rpv_policy <- function() list(profile="complete-findings/0.1",audience="research_team",
  identifier_mode="package_aliases",stimulus_images="excluded_by_choice",
  complete_selected_numerical_evidence=TRUE,include_original_evidence=FALSE,include_raw_recordings=FALSE)
.brohn_rpv_section <- function(ref,adapter,selector=NULL) {
  if(is.null(selector))selector<-list(scope=switch(adapter,`gaze-context`="all_exposures",
    `explicit-distribution`="all_groups",`paired-findings`="all_comparisons",
    `task-scores`="all_administrations",`task-trials`="all_administrations",`task-people`="all_metrics",
    `choice-counts`="all_exercises",`choice-utilities`="all_exercises"))
  display<-switch(adapter,`gaze-context`=list(candidate_limit=200L),
    `explicit-distribution`=list(pages="all"),
    `paired-findings`=list(charts=list("means","differences"),pages="all"),
    `task-scores`=list(pages="all"),
    `task-trials`=list(measure="profile_default",trial_scope="all",charts="profile_default",pages="all",page_numbers=list()),
    `task-people`=list(charts=list("people"),pages="all",page_numbers=list()),
    `choice-counts`=list(pages="all",page_numbers=list()),`choice-utilities`=list(pages="all",page_numbers=list()))
  list(id=paste0("section-",.brohn_rpv_key(list(ref,adapter,selector))),adapter=adapter,
    adapter_version="0.1",source_report_ref=ref,selector=selector,display=display,order=1L)
}
.brohn_rpv_default_sections <- function(rows) {
  result<-list()
  for(adapter in c("gaze-context","task-scores","task-trials","task-people","choice-counts","choice-utilities","explicit-distribution","paired-findings"))for(row in rows)
    if(adapter%in%unlist(row$adapters,use.names=FALSE))result[[length(result)+1L]]<-.brohn_rpv_section(row$ref,adapter)
  lapply(seq_along(result),function(i){s<-result[[i]];s$order<-as.integer(i);s})
}
brohn_report_package_entry_ui <- function(study_id,project_id,report_ref=NULL) {
  brohn_command("Prepare report","rpk_enter",list(study_id=study_id,project_id=project_id,report_ref=report_ref))
}
brohn_report_package_page_ui <- function() brohn_page("Prepare report",
  "Bring saved findings, selected figures and complete numerical evidence into a portable report.",
  actions=shiny::actionButton("rpk_back","Back to study"),
  shiny::tags$script(src="report-package-ui.js"),
  shiny::div(id="rpk_root",shiny::uiOutput("rpk_context"),shiny::uiOutput("rpk_feedback"),
    shiny::uiOutput("rpk_editor"),shiny::uiOutput("rpk_ready"),
    shiny::tags$section(`aria-labelledby`="rpk_history_heading",
      shiny::h2(id="rpk_history_heading","Saved report packages"),
      shiny::p("Earlier choices, unfinished preparations and completed reports remain here."),
      shiny::uiOutput("rpk_history"))))
brohn_report_package_editor_ui <- function(draft) {
  policy<-draft$contents_policy
  shiny::tagList(shiny::div(hidden=NA,shiny::textInput("rpk_form_identity",NULL,draft$form_identity)),
    shiny::textInput("rpk_title","Report title",draft$title),
    shiny::uiOutput("rpk_contents"),
    shiny::tags$details(shiny::tags$summary("Change contents"),
      shiny::h2("Saved findings"),shiny::p("Choose exact saved results. Different collections are kept separate."),
      shiny::uiOutput("rpk_sources"),shiny::uiOutput("rpk_selected"),
      shiny::h2("Figures"),shiny::p("Figure choices change what is illustrated. Complete numerical collections remain included."),
      shiny::uiOutput("rpk_figures"),shiny::uiOutput("rpk_selector"),
      shiny::h2("Labels and materials"),
      shiny::checkboxInput("rpk_source_identifiers","Use original participant and session identifiers",identical(policy$identifier_mode,"source_identifiers")),
      shiny::checkboxInput("rpk_images","Include gaze stimulus images",identical(policy$stimulus_images,"included")),
      shiny::uiOutput("rpk_material_scope"),
      shiny::p("Package-local labels are used by default. Free-text answers remain verbatim; this is not an anonymous report. Offline copies cannot be revoked."),
      shiny::p("Complete original byte evidence and raw recordings are not included in this report profile. Original scientific exports remain available from their saved reports.")),
    shiny::actionButton("rpk_prepare","Prepare report",class="btn-primary"))
}
brohn_report_package_sources_ui <- function(page,selected) shiny::tagList(
  lapply(page$reports,function(row){chosen<-any(vapply(selected,function(r).brohn_rpv_same(r$ref,row$ref),logical(1)))
    shiny::div(class="brohn-card",shiny::h3(row$title),
      shiny::p(paste(row$origin,"| saved version",row$ref$revision)),
      if(length(row$adapters))shiny::p(paste(vapply(row$adapters,.brohn_rpv_adapter_label,character(1)),collapse=", ")),
      if(!is.null(row$reason))shiny::p(row$reason),
      if(length(row$adapters))brohn_command(if(chosen)"Remove from report"else"Include findings","rpk_source_toggle",row$ref)else
        shiny::p(if(is.null(row$reason))"These saved findings need a report adapter. Their existing report and exports remain available."else
          "These saved findings cannot be included for the reason above. Their existing report and exports remain available."))}),
  shiny::div(class="brohn-toolbar",shiny::actionButton("rpk_sources_previous","Newer findings"),
    if(!is.null(page$next_cursor))shiny::actionButton("rpk_sources_next","Older findings")))
.brohn_rpv_task_controls <- function(s,options=NULL) {
  if(s$adapter!="task-trials")return(NULL)
  compatible<-!is.null(options)&&!startsWith(s$selector$scope,"all_")
  prefix<-function(x)paste0("rpk_task_",x,"_",s$id)
  chart_labels<-c(chronology="Recorded responses over trial order",distribution="Recorded-response distribution",outcomes="Response outcomes")
  measure_labels<-c(first_response_ms="First recorded response (ms)",final_correct_ms="Recorded correct response (ms)")
  if(!is.null(options$profile)&&grepl("^(iat-|biat-)",options$profile))measure_labels[["final_correct_ms"]]<-"Final-correct response (ms)"
  shiny::tagList(
    shiny::selectInput(prefix("scope"),"Trial positions",c("All expected positions"="all","Profile test/scoring positions"="scored"),selected=s$display$trial_scope),
    shiny::p("Profile test/scoring positions include errors, omissions and excluded or interrupted evidence; they are not the retained scoring population."),
    if(compatible)shiny::tagList(
      shiny::selectInput(prefix("measure"),"Recorded response",c("Use this task's default"="profile_default",
        stats::setNames(unlist(options$compatible_measures),unname(measure_labels[unlist(options$compatible_measures)]))),selected=s$display$measure),
      shiny::selectInput(prefix("mode"),"Task figures",c("Use this task's defaults"="profile_default","Choose figure types"="selected"),
        selected=if(identical(s$display$charts,"profile_default"))"profile_default"else"selected"),
      shiny::conditionalPanel(sprintf("input['%s'] === 'selected'",prefix("mode")),
        shiny::checkboxGroupInput(prefix("charts"),"Figure types",stats::setNames(unlist(options$compatible_charts),unname(chart_labels[unlist(options$compatible_charts)])),
          selected=if(identical(s$display$charts,"profile_default"))unlist(options$compatible_charts)else unlist(s$display$charts))))else
      shiny::p(if(startsWith(s$selector$scope,"all_"))"Each task uses its saved profile's recorded-response and figure defaults. Choose a specific administration to change these options."else
        "Saved recorded-response and figure choices are retained. Open the exact saved view to change these options."),
    if(!is.null(options$reason))shiny::p(options$reason))
}
brohn_report_package_figures_ui <- function(sections,labels=list(),task_options=list(),sources=list()) shiny::tagList(
  lapply(seq_along(sections),function(i){s<-sections[[i]];label<-labels[[s$id]]
    source<-Filter(function(row).brohn_rpv_same(row$ref,s$source_report_ref),sources)
    if(is.null(label))label<-switch(s$selector$scope,all_exposures="All exposures",all_groups="All response groups",
      all_comparisons="All saved comparisons",all_administrations="All applicable saved task administrations",
      all_metrics="All saved cohort metrics",all_exercises="All saved MaxDiff exercises","Selected saved view")
    shiny::div(class="brohn-card",shiny::h3(.brohn_rpv_adapter_label(s$adapter)),shiny::p(label),
      if(length(source)==1L)shiny::p(paste(source[[1]]$title,"| saved version",s$source_report_ref$revision)),
      if(s$adapter=="gaze-context")shiny::numericInput(paste0("rpk_limit_",s$id),"Maximum illustrated candidates per exposure",s$display$candidate_limit,min=1,max=1000,step=1),
      if(s$adapter=="paired-findings")shiny::checkboxGroupInput(paste0("rpk_charts_",s$id),"Paired figures",
        c("Condition means"="means","Person differences"="differences"),selected=unlist(s$display$charts)),
      .brohn_rpv_task_controls(s,task_options[[s$id]]),
      if(.brohn_rpv_choice_adapter(s$adapter))shiny::p(if(s$adapter=="choice-counts")
        "Saved adjusted results show best minus worst choices divided by complete-pair exposures containing each item. This is not a raw count or a percentage."else
        "Saved aggregate relative utilities use the original model's relative logit units. Unrequested or unavailable models have an explanation instead of a fitted chart; preparing this report does not fit a model."),
      if(s$adapter%in%c("paired-findings","explicit-distribution","task-scores","task-trials","task-people","choice-counts","choice-utilities"))shiny::textInput(paste0("rpk_pages_",s$id),
        if(s$adapter=="explicit-distribution")"Category pages (blank for all; 20 categories per page)"else if(.brohn_rpv_task_adapter(s$adapter)||.brohn_rpv_choice_adapter(s$adapter))"Numerical table pages (blank for all; 50 rows per page)"else"Figure pages (blank for all; for example 1, 2)",
        if(s$display$pages=="all")""else paste(if(s$adapter=="explicit-distribution")unlist(s$display$offsets)/20+1 else unlist(s$display$page_numbers),collapse=", ")),
      if(.brohn_rpv_task_adapter(s$adapter))shiny::p("Table pages change the rows illustrated here. Task charts still cover the whole selected scope; complete numerical companions retain every row."),
      if(.brohn_rpv_choice_adapter(s$adapter))shiny::p("Table pages change only the numerical alternative. Choice charts cover every saved item in the selected exercise; complete evidence remains included. An unavailable model has an explanation on page 1."),
      shiny::div(class="brohn-toolbar",
        brohn_command("Choose specific views","rpk_selector_open",list(ref=s$source_report_ref,adapter=s$adapter)),
        if(i>1L)brohn_command("Move earlier","rpk_section_move",list(id=s$id,direction=-1L)),
        if(i<length(sections))brohn_command("Move later","rpk_section_move",list(id=s$id,direction=1L)),
        brohn_command("Remove figure section","rpk_section_remove",s$id)))}))
.brohn_rpv_choice_details <- function(item,adapter) {
  d<-item$details;if(!is.list(d)||!.brohn_rpv_choice_adapter(adapter))return(NULL)
  model<-if(adapter=="choice-counts")d$counts else d$utilities
  label<-switch(brohn_default(model$status,"unknown"),available="Saved adjusted results are available.",
    no_complete_pairs="No complete best-worst pairs are available in these saved findings.",
    estimated="The saved aggregate choice model was estimated.",
    not_requested="Model fitting was not requested in the saved analysis.",
    unavailable="The saved choice model is unavailable.","Saved model status is not available from this metadata.")
  shiny::tagList(shiny::p(paste("Exercise",d$index,"|",d$item_count,"saved items |",d$exposure_count,"saved exposures")),
    shiny::p(label),if(!is.null(model$reason))shiny::p(model$reason))
}
brohn_report_package_selector_ui <- function(page) shiny::div(class="brohn-card",
  shiny::h3("Choose saved views",id="rpk_selector_heading",tabindex="-1"),
  if(!is.null(page$reason))shiny::p(page$reason),
  if(isTRUE(page$requires_display_preparation)&&!isTRUE(page$locked))shiny::p(if(.brohn_rpv_task_adapter(page$adapter))
    "Specific task choices become available after saved task views are prepared. Prepare report includes all applicable views."else if(.brohn_rpv_choice_adapter(page$adapter))
    "Specific saved exercises become available after preparation. Prepare report includes every saved exercise and its original model status."else if(page$adapter=="explicit-distribution")
    "Response distributions have not been prepared yet. Include all response groups first; saved groups then become available here."else
    "Specific comparison choices are not available from this report's compact metadata. All saved comparisons can still be included with their complete numerical evidence."),
  if(!length(page$items)&&!isTRUE(page$requires_display_preparation)&&!isTRUE(page$locked))shiny::p(if(identical(page$state,"unavailable_source")||identical(page$state,"needs_authority"))
    "These views are currently unavailable. Review the saved source and access reason."else"No specific views are available on this page."),
  lapply(page$items,function(item)shiny::div(class="brohn-stack",shiny::strong(item$label),
    .brohn_rpv_choice_details(item,page$adapter),
    if(is.character(item$details))shiny::p(paste(item$details,collapse=" "))else if(is.list(item$details))shiny::tagList(
      if(!is.null(item$details$completion))shiny::p(paste("Saved administration:",item$details$completion)),
      if(!is.null(item$details$reason))shiny::p(item$details$reason)),
    brohn_command("Include this view","rpk_selector_choose",list(ref=page$report_ref,adapter=page$adapter,selector=item$selector)))),
  shiny::div(class="brohn-toolbar",shiny::actionButton("rpk_selector_previous","Previous views"),
    if(!is.null(page$next_cursor))shiny::actionButton("rpk_selector_next","More views"),
    if(!isTRUE(page$locked)&&!isTRUE(page$state%in%c("unavailable_source","needs_authority")))brohn_command("Use all applicable views","rpk_selector_all",list(ref=page$report_ref,adapter=page$adapter)),
    shiny::actionButton("rpk_selector_close","Close view choices")))
brohn_report_package_history_ui <- function(page) shiny::tagList(
  if(!length(page$items))shiny::p("No report packages have been prepared for this study yet."),
  lapply(page$items,function(item)shiny::div(class="brohn-card",shiny::h3(item$title),
    shiny::p(paste(.brohn_rpv_status(item$status),"|",item$updated_at)),
    if(!is.null(item$reason))shiny::p(item$reason),
    brohn_command(if(item$status=="succeeded")"Open saved report"else"Review preparation","rpk_history_open",item$intent_ref))),
  shiny::div(class="brohn-toolbar",shiny::actionButton("rpk_history_latest","Show latest"),
    shiny::actionButton("rpk_history_previous","Newer packages"),
    if(!is.null(page$next_cursor))shiny::actionButton("rpk_history_next","Older packages")))

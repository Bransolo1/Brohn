# Researcher UI only. These functions render bounded metadata supplied by the
# package backend; they never open source objects or perform scientific work.
.brohn_rpv_key <- function(x) substr(brohn_hash(x),1L,24L)
.brohn_rpv_same <- function(a,b) identical(brohn_json(a),brohn_json(b))
.brohn_rpv_adapter_label <- function(adapter) switch(adapter,
  `gaze-context`="Gaze views",`explicit-distribution`="Response distributions",
  `paired-findings`="Paired findings","Other findings")
.brohn_rpv_status <- function(status) switch(status,
  prepared="Choices saved",waiting_for_display="Preparing response distributions",
  ready_to_freeze="Preparing report contents",assembly_queued="Building the report",
  succeeded="Report ready",needs_authority="Resume with current access",
  needs_attention="Check report contents",failed="Preparation needs attention",
  cancelled="Preparation cancelled",superseded="Replaced by newer choices","Saved preparation")
.brohn_rpv_policy <- function() list(profile="complete-findings/0.1",audience="research_team",
  identifier_mode="package_aliases",stimulus_images="excluded_by_choice",
  complete_selected_numerical_evidence=TRUE,include_original_evidence=FALSE,include_raw_recordings=FALSE)
.brohn_rpv_section <- function(ref,adapter,selector=NULL) {
  if(is.null(selector))selector<-list(scope=switch(adapter,`gaze-context`="all_exposures",
    `explicit-distribution`="all_groups",`paired-findings`="all_comparisons"))
  display<-switch(adapter,`gaze-context`=list(candidate_limit=200L),
    `explicit-distribution`=list(pages="all"),
    `paired-findings`=list(charts=list("means","differences"),pages="all"))
  list(id=paste0("section-",.brohn_rpv_key(list(ref,adapter,selector))),adapter=adapter,
    adapter_version="0.1",source_report_ref=ref,selector=selector,display=display,order=1L)
}
.brohn_rpv_default_sections <- function(rows) {
  result<-list()
  for(adapter in c("gaze-context","explicit-distribution","paired-findings"))for(row in rows)
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
      shiny::checkboxInput("rpk_images","Include stimulus images",identical(policy$stimulus_images,"included")),
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
        shiny::p("These saved findings need a report adapter. Their existing report and exports remain available."))}),
  shiny::div(class="brohn-toolbar",shiny::actionButton("rpk_sources_previous","Newer findings"),
    if(!is.null(page$next_cursor))shiny::actionButton("rpk_sources_next","Older findings")))
brohn_report_package_figures_ui <- function(sections,labels=list()) shiny::tagList(
  lapply(seq_along(sections),function(i){s<-sections[[i]];label<-labels[[s$id]]
    if(is.null(label))label<-switch(s$selector$scope,all_exposures="All exposures",all_groups="All response groups",
      all_comparisons="All saved comparisons","Selected saved view")
    shiny::div(class="brohn-card",shiny::h3(.brohn_rpv_adapter_label(s$adapter)),shiny::p(label),
      if(s$adapter=="gaze-context")shiny::numericInput(paste0("rpk_limit_",s$id),"Maximum illustrated candidates per exposure",s$display$candidate_limit,min=1,max=1000,step=1),
      if(s$adapter=="paired-findings")shiny::checkboxGroupInput(paste0("rpk_charts_",s$id),"Paired figures",
        c("Condition means"="means","Person differences"="differences"),selected=unlist(s$display$charts)),
      if(s$adapter%in%c("paired-findings","explicit-distribution"))shiny::textInput(paste0("rpk_pages_",s$id),
        if(s$adapter=="paired-findings")"Figure pages (blank for all; for example 1, 2)"else"Category pages (blank for all; 20 categories per page)",
        if(s$display$pages=="all")""else paste(if(s$adapter=="paired-findings")unlist(s$display$page_numbers)else unlist(s$display$offsets)/20+1,collapse=", ")),
      shiny::div(class="brohn-toolbar",
        brohn_command("Choose specific views","rpk_selector_open",list(ref=s$source_report_ref,adapter=s$adapter)),
        if(i>1L)brohn_command("Move earlier","rpk_section_move",list(id=s$id,direction=-1L)),
        if(i<length(sections))brohn_command("Move later","rpk_section_move",list(id=s$id,direction=1L)),
        brohn_command("Remove figure section","rpk_section_remove",s$id)))}))
brohn_report_package_selector_ui <- function(page) shiny::div(class="brohn-card",
  shiny::h3("Choose saved views",id="rpk_selector_heading",tabindex="-1"),
  if(isTRUE(page$requires_display_preparation))shiny::p(if(page$adapter=="explicit-distribution")
    "Response distributions have not been prepared yet. Include all response groups first; saved groups then become available here."else
    "Specific comparison choices are not available from this report's compact metadata. All saved comparisons can still be included with their complete numerical evidence."),
  if(!length(page$items))shiny::p("No specific views are available on this page. All applicable findings can still be requested."),
  lapply(page$items,function(item)shiny::div(class="brohn-stack",shiny::strong(item$label),
    if(is.character(item$details))shiny::p(paste(item$details,collapse=" ")),
    brohn_command("Include this view","rpk_selector_choose",list(ref=page$report_ref,adapter=page$adapter,selector=item$selector)))),
  shiny::div(class="brohn-toolbar",shiny::actionButton("rpk_selector_previous","Previous views"),
    if(!is.null(page$next_cursor))shiny::actionButton("rpk_selector_next","More views"),
    brohn_command("Use all applicable views","rpk_selector_all",list(ref=page$report_ref,adapter=page$adapter)),
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

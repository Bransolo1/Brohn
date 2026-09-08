.brohn_tc_field <- function(token,field) paste0("tc_",token,"_",field)
.brohn_tc_nullable <- function(value) if(is.null(value)||identical(value,""))NULL else value
brohn_task_cohort_identity_review_rows <- function(catalog) lapply(catalog$identities$participants,function(p) {
  selected<-Filter(function(a)identical(a$source_collection_id,p$source_collection_id)&&identical(a$participant_id,p$participant_id),catalog$attempts)
  unlinked<-sum(!vapply(selected,`[[`,logical(1),"participant_linkage"))
  list(source_collection_id=p$source_collection_id,participant_id=p$participant_id,selected_administrations=length(selected),
    originally_unlinked_administrations=unlinked,source_linkage=if(unlinked)"Some source identities were not linked; independent participant records are needed."else "Source-declared linkage; not independently verified.")
})
brohn_task_cohort_metric_label <- function(metric) switch(metric,
  correct_test_rt_mean="Mean of individual mean test response times",
  correct_test_rt_median="Mean of individual median test response times",
  correct_test_rt_sd="Mean of individual response-time standard deviations",
  test_first_response_error_rate="Mean first-response error proportion",
  test_omission_rate="Mean no-response proportion",
  keyboard_aat_relative_approach_advantage="Mean relative keyboard approach advantage",
  IAT_D1="Mean IAT D1 score",BIAT_D="Mean Brief IAT D score",metric)
brohn_task_cohort_report_ui <- function(analysis) {
  if(!identical(analysis$schema,"brohn-task-cohort/1.0"))return(NULL)
  rows<-lapply(analysis$summaries,function(s)list(measure=brohn_task_cohort_metric_label(s$metric),mean=s$mean,unit=s$unit,
    contributing_people=s$contributing_person_count,contributing_sessions=s$contributing_session_count,
    eligible_administrations=s$eligible_attempt_count,selected_administrations=s$selected_attempt_count,
    between_person_sd=s$between_person_sd,reason=brohn_default(s$reason,s$sd_reason)))
  shiny::tagList(shiny::h2("Task participants"),
    shiny::p(paste(analysis$quality$selected_attempt_count,"explicitly selected administrations.",
      if(isTRUE(analysis$quality$fully_linked))paste(analysis$quality$selected_person_count,"people according to the reviewed identity map.")else
        "Person counts and cohort summaries are unavailable because some selected identities are unlinked.")),
    shiny::p("These are descriptive means. Each measure keeps its own eligible people and sessions; no confidence interval or hypothesis test was calculated."),
    brohn_table(rows,maximum=30L,label="Task cohort outcomes and measure-specific support"),
    shiny::tags$details(shiny::tags$summary("Review selected administrations and identities"),
      shiny::p(paste("Showing up to 30 of",length(analysis$membership),"selected administrations. JSON + provenance retains the complete membership and source hashes.")),
      brohn_table(analysis$membership,columns=c("source_collection_id","source_participant_id","source_session_id","source_attempt_id","person_id","session_id","linked","completion_status","linkage_reason"),maximum=30L,label="Selected task administration identities")),
    shiny::tags$details(shiny::tags$summary("Review each measure's available evidence"),
      shiny::p(paste("Showing up to 30 of",length(analysis$attempt_metrics),"administration-measure records. Unsupported values remain unavailable; no missing value becomes zero.")),
      brohn_table(analysis$attempt_metrics,columns=c("attempt_id","metric","unit","eligible","value","reason"),maximum=30L,label="Task administration metric support")),
    shiny::tags$details(shiny::tags$summary("Review person and session averaging"),
      shiny::p(paste("Repeat policy:",switch(analysis$provenance$plan$repeat_policy,
        one_selected_attempt_per_person="One explicitly selected administration per person.",
        "Equal eligible administrations within each session, then equal sessions within each person, then equal people."))),
      shiny::p(paste("Showing up to 30 of",length(analysis$per_person),"person-measure records and",length(analysis$per_session),"session-measure records; full JSON contains all rows.")),
      brohn_table(analysis$per_person,columns=c("person_id","metric","value","unit","eligible_attempt_count","eligible_session_count","reason"),maximum=30L,label="Task person-level descriptive outcomes"),
      brohn_table(analysis$per_session,columns=c("person_id","session_id","metric","value","unit","eligible_attempt_count","reason"),maximum=30L,label="Task session-level descriptive outcomes")),
    shiny::tags$details(shiny::tags$summary("Inspect the frozen plan and limitations"),shiny::tags$pre(brohn_json(analysis$provenance,TRUE)),
      shiny::tags$ul(lapply(analysis$limitations,shiny::tags$li))))
}
brohn_task_cohort_export_rows <- function(analysis,level="summaries") {
  brohn_require(identical(analysis$schema,"brohn-task-cohort/1.0")&&level %in% c("summaries","per_person","per_session","attempt_metrics","membership"),"Choose a saved task-cohort table.")
  lapply(analysis[[level]],function(row) {
    row<-lapply(row,function(value)if(is.list(value))brohn_json(value)else value)
    c(list(cohort_recipe=analysis$provenance$recipe,plan_hash=analysis$provenance$plan_hash,
      identity_map_hash=analysis$provenance$identity_map_hash),row)
  })
}
brohn_export_task_cohort_csv <- function(report,path,level="summaries") {
  brohn_export_report_csv(list(analysis=list(observations=brohn_task_cohort_export_rows(report$analysis,level))),path)
}
.brohn_tc_review_attempts <- function(catalog,token,input) {
  mode<-input[[.brohn_tc_field(token,"membership_mode")]]
  brohn_require(mode %in% c("all","select","file"),"Choose complete membership, individual selection or a reviewed membership file.")
  ids<-if(mode=="all")as.list(vapply(catalog$attempts,`[[`,character(1),"id"))else if(mode=="select") {
    brohn_require(length(catalog$attempts)<=100L,"Use all administrations or a reviewed membership file for more than 100 administrations.")
    as.list(input[[.brohn_tc_field(token,"attempts")]])
  } else {
    file<-input[[.brohn_tc_field(token,"membership_file")]]
    brohn_require(is.data.frame(file)&&nrow(file)==1L&&tolower(tools::file_ext(file$name[[1L]]))=="json","Upload one completed membership JSON file.")
    brohn_read_json_file(file$datapath[[1L]],1024^2)
  }
  brohn_require(brohn_array(ids)&&length(ids)>0L&&length(ids)<=5000L&&all(vapply(ids,brohn_text,logical(1),max=240))&&!anyDuplicated(unlist(ids)),"Select at least one exact administration with no duplicate membership.")
  available<-vapply(catalog$attempts,`[[`,character(1),"id")
  brohn_require(!anyDuplicated(available)&&all(unlist(ids) %in% available),"Membership must belong to these reviewed reports without duplicate source administrations.")
  catalog$attempts[match(unlist(ids),available)]
}
brohn_task_cohort_crosswalk_input <- function(catalog,selected,token,input) {
  mode<-input[[.brohn_tc_field(token,"identity_mode")]]
  brohn_require(mode %in% c("unlinked","source","edit","file"),"Choose an explicit identity review method.")
  proposed<-brohn_task_cohort_identity_rows(selected)
  if(mode=="unlinked")return(proposed)
  brohn_require(isTRUE(input[[.brohn_tc_field(token,"identity_confirmed")]]),"Confirm that you reviewed the participant and visit identities; matching labels do not verify them.")
  if(mode=="file") {
    file<-input[[.brohn_tc_field(token,"identity_file")]]
    brohn_require(is.data.frame(file)&&nrow(file)==1L&&tolower(tools::file_ext(file$name[[1L]]))=="json","Upload one completed reviewed identity JSON file.")
    return(brohn_read_json_file(file$datapath[[1L]],4*1024^2))
  }
  notes<-.brohn_tc_nullable(input[[.brohn_tc_field(token,"identity_notes")]])
  if(any(!vapply(selected,`[[`,logical(1),"participant_linkage")))brohn_require(brohn_text(notes,5000),
    "Some selected administrations were originally unlinked. Explain the independent participant records used to link them, or keep these identities unlinked.")
  statement<-if(mode=="source")"Researcher explicitly confirmed that repeated person and session codes identify the same people and visits within each source collection. Distinct source collections remain separate."else
    "Researcher explicitly reviewed the entered shared person/session identities as representing the same people and visits."
  proposed$linkage_statement<-paste(statement,brohn_default(notes,""))
  if(mode=="source") {
    single<-length(unique(vapply(proposed$participants,`[[`,character(1),"source_collection_id")))==1L
    proposed$participants<-lapply(proposed$participants,function(p){p$person_id<-if(single)p$participant_id else paste0("source-person-",.brohn_task_cohort_key(p$source_collection_id,p$participant_id));p})
    proposed$sessions<-lapply(proposed$sessions,function(s){s$session_id<-if(single)s$source_session_id else paste0("source-session-",.brohn_task_cohort_key(s$source_collection_id,s$participant_id,s$source_session_id));s})
    return(proposed)
  }
  brohn_require(length(catalog$identities$participants)<=100L&&length(catalog$identities$sessions)<=200L,"Use the reviewed identity file for larger crosswalks; no editor rows are truncated.")
  original_p<-vapply(catalog$identities$participants,function(p).brohn_task_cohort_key(p$source_collection_id,p$participant_id),character(1))
  original_s<-vapply(catalog$identities$sessions,function(s).brohn_task_cohort_key(s$source_collection_id,s$participant_id,s$source_session_id),character(1))
  proposed$participants<-lapply(proposed$participants,function(p){i<-match(.brohn_task_cohort_key(p$source_collection_id,p$participant_id),original_p);p["person_id"]<-list(.brohn_tc_nullable(input[[.brohn_tc_field(token,paste0("person_",i))]]));p})
  proposed$sessions<-lapply(proposed$sessions,function(s){i<-match(.brohn_task_cohort_key(s$source_collection_id,s$participant_id,s$source_session_id),original_s)
    s["session_id"]<-list(.brohn_tc_nullable(input[[.brohn_tc_field(token,paste0("session_",i))]]))
    s["equivalence_statement"]<-list(.brohn_tc_nullable(input[[.brohn_tc_field(token,paste0("equivalence_",i))]]));s})
  proposed
}
.brohn_tc_context_guard <- function(context,input,state,current,token) {
  brohn_require(!is.null(context)&&identical(context$token,token)&&identical(state$page,"study")&&
    identical(state$study_id,context$study_id)&&state$stage %in% c("Results","History")&&
    identical(current$study$id,context$study_id)&&
    identical(input$study_form_identity,paste(context$study_id,state$stage,sep=":")),
    "Return to this study's current task-participant review. This dialog or study context has changed.")
  invisible(TRUE)
}
brohn_install_task_cohort_ui <- function(input,output,session,store,state,current,attempt,message,refresh) {
  context<-shiny::reactiveVal(NULL)
  token<-function()substr(gsub("-","",brohn_id("review")),7L,30L)
  command<-function(label,name,ctx,primary=FALSE)brohn_command(label,name,list(token=ctx$token),if(primary)"btn btn-primary"else"btn btn-default")
  guard<-function(value){ctx<-context();brohn_require(is.list(value)&&brohn_text(value$token,64),"Use the displayed task-cohort review action.");.brohn_tc_context_guard(ctx,input,state,current,value$token);ctx}
  shiny::observeEvent(input$task_cohort_open,attempt(function() {
    id<-input$task_cohort_open;study<-.brohn_tc_study(store,id)
    ctx<-list(token=token(),study_id=id,phase="sources",catalog=NULL)
    .brohn_tc_context_guard(ctx,input,state,current,ctx$token)
    records<-list();offset<-0L
    repeat{page<-brohn_task_cohort_report_catalog(store,id,limit=100L,offset=offset);records<-c(records,page$records);if(!page$has_next)break;offset<-page$offset+page$limit}
    brohn_require(length(records)>0L,"Save an imported task report first. Native summary reports require their trial export and declared-summary import.")
    context(ctx)
    choices<-stats::setNames(vapply(records,`[[`,character(1),"id"),vapply(records,function(r)paste(r$title,r$origin,
      if(r$status=="unsupported_source")"Summary only - needs trial import"else paste(r$attempt_count,"administrations"),r$id,sep=" | "),character(1)))
    shiny::showModal(shiny::modalDialog(title="Summarise task participants",size="l",easyClose=FALSE,
      shiny::p("Choose saved reports from this study. One exact task definition, collection origin and scoring recipe can be summarised at a time."),
      shiny::selectizeInput(.brohn_tc_field(ctx$token,"reports"),"Saved task reports",choices=NULL,multiple=TRUE,
        options=list(placeholder="Search this study's reports",maxOptions=100)),
      shiny::p(paste(length(records),"saved task reports are searchable. Select up to 100; no older reports are hidden behind a recent-report limit.")),
      shiny::p("Native summary reports do not yet contain the canonical administration evidence this workflow needs. Their original trials and registry can be exported and imported as declared summaries."),
      footer=shiny::tagList(command("Cancel","task_cohort_cancel",ctx),command("Review administrations","task_cohort_review",ctx,TRUE))))
    shiny::updateSelectizeInput(session,.brohn_tc_field(ctx$token,"reports"),choices=choices,selected=character(),server=TRUE)
  }))
  shiny::observeEvent(input$task_cohort_review,attempt(function() {
    prior<-guard(input$task_cohort_review);brohn_require(prior$phase=="sources","Use the current source-selection dialog.")
    catalog<-brohn_task_cohort_catalog(store,prior$study_id,as.list(input[[.brohn_tc_field(prior$token,"reports")]]))
    unsupported<-Filter(function(r)r$status!="supported",catalog$reports)
    brohn_require(!length(unsupported),if(length(unsupported))paste(unsupported[[1L]]$title,unsupported[[1L]]$reason,"Remove that report explicitly and choose a supported imported report.")else "")
    brohn_require(length(catalog$groups)==1L,"These reports differ in task definition, profile, origin, scoring recipe or evidence level. Select one compatible group of source reports.")
    ctx<-list(token=token(),study_id=prior$study_id,phase="membership",catalog=catalog);context(ctx)
    field<-function(x).brohn_tc_field(ctx$token,x)
    condition<-function(name,value)paste0("input.",field(name)," === '",value,"'")
    ids<-vapply(catalog$attempts,`[[`,character(1),"id")
    labels<-vapply(catalog$attempts,function(a)paste(a$source_collection_id,a$participant_id,a$session_id,a$source_attempt_id,a$completion_status,sep=" | "),character(1))
    p<-catalog$identities$participants;s<-catalog$identities$sessions
    originally_unlinked<-sum(!vapply(catalog$attempts,`[[`,logical(1),"participant_linkage"))
    identity_editor<-if(length(p)<=100L&&length(s)<=200L)shiny::tagList(
      lapply(seq_along(p),function(i)shiny::tags$fieldset(shiny::tags$legend(paste("Source person",i,p[[i]]$source_collection_id,p[[i]]$participant_id,sep=" | ")),
        shiny::textInput(field(paste0("person_",i)),paste("Shared person code",i),""))),
      lapply(seq_along(s),function(i)shiny::tags$fieldset(shiny::tags$legend(paste("Source visit",i,s[[i]]$source_collection_id,s[[i]]$participant_id,s[[i]]$source_session_id,sep=" | ")),
        shiny::textInput(field(paste0("session_",i)),paste("Shared visit code",i),""),
        shiny::textInput(field(paste0("equivalence_",i)),paste("Why multiple source visits describe the same visit",i,"(only if merging)"),""))))else
      shiny::p("Use the reviewed identity file for this larger selection. No person or visit rows are silently omitted.")
    shiny::showModal(shiny::modalDialog(title="Review task membership and people",size="l",easyClose=FALSE,
      shiny::h2("Selected administrations"),shiny::p(paste(length(ids),"administrations from",length(catalog$reports),"reports. Unavailable administrations are retained unless you explicitly remove them.")),
      shiny::radioButtons(field("membership_mode"),"Membership",c("All reviewed administrations"="all","Choose administrations"="select","Use a reviewed membership file"="file"),selected="all"),
      shiny::conditionalPanel(condition("membership_mode","select"),if(length(ids)<=100L)shiny::checkboxGroupInput(field("attempts"),"Administrations to include",stats::setNames(ids,labels),selected=ids)else shiny::p("For more than 100 administrations, use all membership or the complete downloadable membership file.")),
      shiny::conditionalPanel(condition("membership_mode","file"),shiny::downloadButton("task_cohort_membership_template","Download complete membership template",icon=NULL),
        shiny::p("The JSON array contains every administration ID. Remove only IDs you explicitly intend to exclude."),
        shiny::fileInput(field("membership_file"),"Reviewed membership JSON",accept=".json")),
      shiny::h2("Repeated visits"),shiny::radioButtons(field("repeat"),"How should repeated administrations count?",
        c("One explicitly selected administration per person"="one_selected_attempt_per_person","Average administrations within visits, then visits within people"="equal_attempts_within_session_then_equal_sessions_within_person"),selected="one_selected_attempt_per_person"),
      shiny::p("Every person receives equal weight. The one-administration policy will ask you to choose if a person has multiple selected administrations, even when a repeat has no available score."),
      shiny::h2("Participant and visit identities"),
      if(originally_unlinked)shiny::p(role="status",class="brohn-muted",paste(originally_unlinked,
        "selected administrations have source identities that were not linked to a person. Labels may be generated display codes. Use independent participant records and explain the evidence below, or keep these identities unlinked.")),
      shiny::radioButtons(field("identity_mode"),"Identity review",c("Confirm source codes within each collection; keep collections separate"="source","Enter shared person and visit codes"="edit","Upload a reviewed identity map"="file","Keep identities unlinked (no person-level summaries)"="unlinked"),selected="source"),
      shiny::conditionalPanel(condition("identity_mode","source"),shiny::p("Review these exact source identities. Repeated person and visit codes will link only within their collection. Identical codes from different collections remain separate."),
        brohn_table(brohn_task_cohort_identity_review_rows(catalog),columns=c("source_collection_id","participant_id","selected_administrations","originally_unlinked_administrations","source_linkage"),maximum=30L,label="Source person codes and original linkage awaiting explicit review"),
        shiny::p(paste("Showing up to 30 of",length(p),"source people. The complete identity template contains",length(s),"source visits."))),
      shiny::conditionalPanel(condition("identity_mode","edit"),identity_editor),
      shiny::conditionalPanel(condition("identity_mode","file"),shiny::p("Fill the complete JSON person and session maps. Null destinations remain unlinked; source identities cannot be changed."),shiny::fileInput(field("identity_file"),"Reviewed participant and visit map JSON",accept=".json")),
      shiny::downloadButton("task_cohort_identity_template","Download complete identity template",icon=NULL),
      shiny::textAreaInput(field("identity_notes"),"Identity evidence and notes (required when linking originally unlinked codes)","",rows=2),
      shiny::checkboxInput(field("identity_confirmed"),"I reviewed these person and visit links against the study's participant records",FALSE),
      shiny::p("Without complete explicit identity links, original administration outcomes remain available but unique-person counts and cohort means are withheld."),
      shiny::textInput(field("description"),"Name this selection and repeat plan",paste("Task participants -",catalog$design$title)),
      shiny::p("Keep this name short. It will identify the saved report in Results and History."),
      shiny::tags$details(shiny::tags$summary("Frozen source recipe"),shiny::tags$pre(brohn_json(catalog$groups[[1L]]$homogeneous,TRUE))),
      footer=shiny::tagList(command("Cancel","task_cohort_cancel",ctx),command("Save task participant report","task_cohort_save",ctx,TRUE))))
  }))
  shiny::observeEvent(input$task_cohort_cancel,attempt(function(){guard(input$task_cohort_cancel);context(NULL);shiny::removeModal()}))
  shiny::observeEvent(input$task_cohort_save,attempt(function() {
    ctx<-guard(input$task_cohort_save);brohn_require(ctx$phase=="membership","Review source membership before creating a report.")
    selected<-.brohn_tc_review_attempts(ctx$catalog,ctx$token,input)
    map<-brohn_task_cohort_crosswalk_input(ctx$catalog,selected,ctx$token,input)
    report_title<-input[[.brohn_tc_field(ctx$token,"description")]]
    brohn_require(!is.null(report_title),"Name this selection and repeat plan before saving.")
    .brohn_tc_validate_report_title(report_title)
    job<-brohn_queue_task_cohort(store,ctx$study_id,ctx$catalog$report_ids,lapply(selected,`[[`,"id"),map,
      input[[.brohn_tc_field(ctx$token,"repeat")]],report_title,ctx$catalog$selection_hash,report_title=report_title)
    context(NULL);shiny::removeModal();state$page<-"activity";refresh();message("Task participant report queued with the exact reviewed sources, identities and repeat policy.");invisible(job)
  }))
  output$task_cohort_membership_template<-shiny::downloadHandler(filename=function()"brohn-task-membership.json",content=function(file) {
    ctx<-context();.brohn_tc_context_guard(ctx,input,state,current,ctx$token);brohn_require(ctx$phase=="membership","Review administrations before downloading their membership.")
    brohn_write_json_file(lapply(ctx$catalog$attempts,`[[`,"id"),file)
  },contentType="application/json")
  output$task_cohort_identity_template<-shiny::downloadHandler(filename=function()"brohn-task-identities.json",content=function(file) {
    ctx<-context();.brohn_tc_context_guard(ctx,input,state,current,ctx$token);brohn_require(ctx$phase=="membership","Review administrations before downloading the identity template.")
    brohn_write_json_file(ctx$catalog$identities,file)
  },contentType="application/json")
  saved_report<-function() {
    brohn_require(identical(state$page,"report")&&brohn_valid_id(state$report_id),"Open the current saved task-cohort report before downloading its evidence.")
    report<-brohn_get_entity(store,"report",state$report_id)
    brohn_require(!is.null(report)&&identical(report$body$analysis$schema,"brohn-task-cohort/1.0"),"The selected report does not contain saved task-cohort evidence.")
    report
  }
  download<-function(level,path) {
    tryCatch(brohn_export_task_cohort_csv(saved_report()$body,path,level),error=function(e){state$error<-conditionMessage(e);stop(e)})
  }
  for(specification in list(c("report_task_cohort_people_csv","per_person"),c("report_task_cohort_sessions_csv","per_session"),
      c("report_task_cohort_attempts_csv","attempt_metrics"),c("report_task_cohort_membership_csv","membership")))local({
    name<-specification[[1L]];level<-specification[[2L]]
    output[[name]]<-shiny::downloadHandler(filename=function()paste0(saved_report()$id,"-",level,".csv"),
      content=function(file)download(level,file),contentType="text/csv")
  })
  invisible(list(context=context,selection=function(){ctx<-context();if(is.null(ctx))NULL else ctx$catalog},download=download))
}

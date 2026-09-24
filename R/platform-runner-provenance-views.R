# Assigned participant code is a separate, immutable dependency record. Neither
# a preserved manifest nor this view proves browser execution or scientific validity.
.brohn_rp_hash <- function(x) brohn_text(x,64L) && grepl("^[a-f0-9]{64}$",x)
.brohn_rp_authorize <- function(store,study_id,project_id) {
  .brohn_store_ready(store)
  brohn_require(brohn_valid_id(study_id)&&brohn_valid_id(project_id),"Choose the source study and project.")
  if(!is.null(store$hosted_profile))brohn_hosted_require_project(store,project_id)
  row<-DBI::dbGetQuery(store$con,"SELECT id FROM entities WHERE kind='study' AND id=? AND project_id=?",params=list(study_id,project_id))
  brohn_require(nrow(row)==1L,"The participant-code source is unavailable in this study and project.")
}
.brohn_rp_command <- function(command) {
  brohn_fields(command,c("kind","id","study_id"),c("revision","hash"),"Participant code selection")
  brohn_require(command$kind %in% c("release","run","report")&&brohn_valid_id(command$id)&&brohn_valid_id(command$study_id),"Choose a participant-code source.")
  if(command$kind=="report")brohn_require(brohn_number(command$revision,1,1e9,TRUE)&&.brohn_rp_hash(command$hash),"Reopen the exact saved report before reviewing its participant code.")
  else brohn_require(!any(c("revision","hash") %in% names(command)),"Use the current release or session selection.")
  invisible(command)
}
.brohn_rp_runtime <- function(runtime) {
  brohn_require(is.list(runtime)&&runtime$status %in% c("pinned","legacy_unpinned"),"Participant-code preservation state is unavailable.")
  if(runtime$status=="pinned") {
    brohn_require(.brohn_rp_hash(runtime$manifest_hash)&&is.list(runtime$manifest),"Preserved participant-code identity is incomplete.")
    .brohn_runner_manifest(runtime$manifest,runtime$manifest_hash)
  } else brohn_require(is.null(runtime$manifest_hash)&&is.null(runtime$manifest),"Unknown historical code must not have an inferred manifest.")
  runtime[c("status","manifest_hash","manifest")]
}
brohn_runner_provenance_read <- function(store,command,project_id) {
  .brohn_rp_command(command);.brohn_rp_authorize(store,command$study_id,project_id)
  brohn_require(command$kind %in% c("release","run"),"Choose one release or participant session.")
  if(command$kind=="release") {
    row<-DBI::dbGetQuery(store$con,paste("SELECT id,study_id,project_id,design_hash,design_revision FROM delivery_deployments",
      "WHERE id=? AND study_id=? AND project_id=?"),params=list(command$id,command$study_id,project_id))
    brohn_require(nrow(row)==1L,"This release is unavailable in the selected study and project.")
    source<-list(kind="release",id=command$id,study_id=command$study_id,project_id=project_id,
      deployment_id=command$id,design_hash=row$design_hash[[1L]],design_revision=row$design_revision[[1L]])
    runtime<-.brohn_rp_runtime(brohn_runner_assets_read(store,command$id))
  } else {
    row<-DBI::dbGetQuery(store$con,paste("SELECT r.id,r.deployment_id,r.protocol_hash,d.design_hash,d.design_revision FROM delivery_runs r",
      "JOIN delivery_deployments d ON d.id=r.deployment_id AND d.study_id=r.study_id",
      "WHERE r.id=? AND r.study_id=? AND d.project_id=?"),params=list(command$id,command$study_id,project_id))
    brohn_require(nrow(row)==1L,"This session is unavailable in the selected study and project.")
    assigned<-brohn_runner_run_read(store,command$id)
    brohn_require(identical(assigned$run_id,command$id)&&identical(assigned$deployment_id,row$deployment_id[[1L]]),"The code assignment belongs to a different session or release.")
    source<-list(kind="run",id=command$id,study_id=command$study_id,project_id=project_id,
      deployment_id=row$deployment_id[[1L]],protocol_hash=row$protocol_hash[[1L]],
      design_hash=row$design_hash[[1L]],design_revision=row$design_revision[[1L]])
    runtime<-.brohn_rp_runtime(assigned)
  }
  brohn_require(.brohn_rp_hash(source$design_hash)&&(is.null(source$protocol_hash)||.brohn_rp_hash(source$protocol_hash)),"The source's saved scientific identity is invalid.")
  list(schema="brohn-participant-code-evidence/1.0",source=source,status=runtime$status,
    manifest_hash=runtime$manifest_hash,manifest=runtime$manifest,
    interpretation="Assigned generic participant code, separate from the frozen scientific protocol. This view verifies the manifest and assignment, not every stored file's current bytes. Files are checked when served and during backup. Preservation does not prove browser execution, physical timing, scientific validity or the complete operating environment.")
}
.brohn_rp_report_guard <- function(store,command,project_id) {
  .brohn_rp_command(command);brohn_require(command$kind=="report","Choose an exact saved report.")
  .brohn_rp_authorize(store,command$study_id,project_id)
  row<-DBI::dbGetQuery(store$con,paste("SELECT v.body_hash FROM entities e JOIN entity_versions v ON e.kind=v.kind AND e.id=v.id AND e.revision=v.revision",
    "WHERE e.kind='report' AND e.id=? AND e.project_id=? AND e.revision=?"),params=list(command$id,project_id,command$revision))
  brohn_require(nrow(row)==1L&&identical(row$body_hash[[1L]],command$hash),"The saved report changed or is unavailable. Reopen its participant-code review.")
  invisible(TRUE)
}
brohn_runner_report_provenance <- function(store,command,project_id) {
  .brohn_rp_report_guard(store,command,project_id)
  record<-brohn_report_for_review(store,command$id,command$revision)
  brohn_require(identical(record$body$study_id,command$study_id)&&is.null(record$body$dataset_id)&&
    identical(brohn_hash(record$body),command$hash),"This report does not retain direct native participant-session sources.")
  refs<-record$body$provenance$runs
  brohn_require(is.list(refs)&&length(refs)>0L&&length(refs)<=100000L,"This report does not retain a supported direct participant-session inventory.")
  refs<-lapply(refs,function(r){
    brohn_require(is.list(r)&&brohn_valid_id(r$run_id)&&brohn_valid_id(r$deployment_id)&&.brohn_rp_hash(r$design_hash),"A report's participant-session reference is incomplete.")
    list(run_id=r$run_id,deployment_id=r$deployment_id,design_hash=r$design_hash)
  })
  brohn_require(!anyDuplicated(vapply(refs,`[[`,character(1),"run_id")),"A report repeats a participant-session reference.")
  list(command=command,project_id=project_id,refs=refs,total=length(refs))
}
brohn_runner_release_entry_ui <- function(deployment,study_id) {
  status<-deployment$participant_runtime$status
  label<-if(identical(status,"pinned"))"Code preserved with this release"else if(identical(status,"legacy_unpinned"))"Code history not preserved"else"Review participant code history"
  shiny::tags$details(shiny::tags$summary("Participant code"),shiny::p(label),
    brohn_command("Review participant code","runner_provenance_open",list(kind="release",id=deployment$id,study_id=study_id)))
}
brohn_runner_report_entry_ui <- function(record) {
  body<-record$body
  if(!is.null(body$dataset_id)||!brohn_valid_id(body$study_id)||!length(body$provenance$runs))return(NULL)
  shiny::tags$details(shiny::tags$summary("Participant code linked to this report"),
    shiny::p("Inspect the code assigned to the report's original sessions. This separate record does not change the saved analysis."),
    brohn_command("Review report participant code","runner_provenance_open",list(kind="report",id=record$id,
      study_id=body$study_id,revision=record$revision,hash=brohn_hash(body))))
}
.brohn_rp_evidence_ui <- function(evidence) {
  pinned<-identical(evidence$status,"pinned")
  shiny::tagList(shiny::h3(if(pinned)"Participant code preserved"else"Historical code is unknown"),
    shiny::p(if(pinned)"The generic participant application files assigned to this source were preserved with its release."else
      "This source predates preserved participant-code assignments. Its exact historical code was not recorded; today's installation cannot establish it."),
    shiny::p("This records assigned code. It does not prove which bytes executed in a browser, physical timing or scientific validity. The saved design, responses and analysis stay unchanged."),
    shiny::tags$details(style="overflow-wrap:anywhere",shiny::tags$summary("Source and code identity"),
      shiny::p(paste(if(evidence$source$kind=="run")"Session:"else"Release:",evidence$source$id)),
      shiny::p(paste("Design revision:",evidence$source$design_revision)),
      if(pinned)shiny::p(paste("Code manifest SHA-256:",evidence$manifest_hash)),
      if(pinned)shiny::p("This view verifies the saved manifest and assignment. File contents are checked when served and during backup; opening this panel does not recheck every file."),
      if(!is.null(evidence$report))shiny::p(paste("Linked saved report:",evidence$report$id,"revision",evidence$report$revision))),
    if(pinned)shiny::tags$details(shiny::tags$summary(paste("Preserved file inventory",paste0("(",length(evidence$manifest$files)," files)"))),
      brohn_table(evidence$manifest$files,columns=c("path","size","hash","media_type"),maximum=64L,label="Preserved participant code files")))
}
brohn_install_runner_provenance <- function(input,output,session,store,state,current,attempt,prepare_download) {
  selected<-shiny::reactiveVal(NULL)
  context<-function()list(page=state$page,stage=if(identical(state$page,"study"))state$stage else NULL,
    study_id=if(identical(state$page,"study"))current$study$id else NULL,report_id=if(identical(state$page,"report"))state$report_id else NULL)
  authorize<-function(command) {
    .brohn_rp_command(command)
    if(command$kind=="report") {
      brohn_require(identical(state$page,"report")&&identical(state$report_id,command$id),"Open this saved report before reviewing its participant code.")
      record<-brohn_report_for_review(store,command$id,command$revision)
      brohn_require(identical(record$body$study_id,command$study_id),"The report belongs to a different study.");record$project_id
    } else {
      brohn_require(identical(state$page,"study")&&state$stage %in% c("Collect","Review","History")&&
        !is.null(current$study)&&identical(current$study$id,command$study_id),"Open this study's Collect, Review or History page first.")
      current$study$project_id
    }
  }
  bound<-function(require_input=TRUE) {
    s<-selected();brohn_require(!is.null(s)&&identical(s$context,context()),"This participant-code review belongs to another page. Open it again.")
    if(require_input)brohn_require(identical(input$runner_provenance_identity,s$identity),"The selected participant-code record changed. Reopen it before downloading.")
    if(s$command$kind=="report").brohn_rp_report_guard(store,s$command,s$project_id)else authorize(s$command)
    s
  }
  evidence<-function() {
    s<-bound();brohn_require(!is.null(s$evidence),"Select one release or session before downloading its code record.")
    e<-brohn_runner_provenance_read(store,s$evidence_command,s$project_id)
    if(!is.null(s$report_link))e$report<-s$report_link
    brohn_require(identical(brohn_hash(e),brohn_hash(s$evidence)),"The preserved participant-code record changed. Stop and inspect its integrity.")
    e
  }
  show<-function(s) {
    identity<-shiny::tags$input(id="runner_provenance_identity",type="text",class="shiny-input-text",value=s$identity,
      style="display:none",tabindex="-1",`aria-hidden`="true")
    body<-if(!is.null(s$evidence)).brohn_rp_evidence_ui(s$evidence)else {
      refs<-s$report$refs;offset<-s$offset;last<-min(length(refs),offset+40L)
      shiny::tagList(shiny::p(paste(length(refs),"original sessions referenced directly by this saved report. This separate lookup does not add code identity to the scientific report.")),
        shiny::p("A preserved assignment records generic application files. Imported summaries are not treated as proof of original browser code."),
        shiny::tags$ul(lapply(seq.int(offset+1L,last),function(i)shiny::tags$li(paste("Session",i,refs[[i]]$run_id)," ",
          brohn_command("Inspect assigned code","runner_provenance_run",list(identity=s$identity,run_id=refs[[i]]$run_id))))),
        shiny::p(paste("Showing",offset+1L,"to",last,"of",length(refs),"sessions")),
        shiny::div(class="brohn-toolbar",if(offset>0L)brohn_command("Previous code sources","runner_provenance_page",list(identity=s$identity,offset=offset-40L)),
          if(last<length(refs))brohn_command("Next code sources","runner_provenance_page",list(identity=s$identity,offset=offset+40L))))
    }
    shiny::showModal(shiny::modalDialog(title="Participant code",size="l",easyClose=FALSE,identity,body,
      footer=shiny::tagList(if(!is.null(s$evidence))shiny::downloadButton("runner_provenance_evidence","Download code provenance JSON",icon=NULL),
        if(!is.null(s$evidence)&&s$evidence$status=="pinned")shiny::downloadButton("runner_provenance_manifest","Download code manifest JSON",icon=NULL),
        if(!is.null(s$report)&&!is.null(s$evidence))shiny::actionButton("runner_provenance_back","Back to report sessions"),
        shiny::actionButton("runner_provenance_close",if(is.function(s$return_view))"Back to source review"else"Close participant code"))))
  }
  open<-function(command,return_view=NULL) {
    project<-authorize(command);s<-list(command=command,project_id=project,context=context(),return_view=return_view,offset=0L)
    if(command$kind=="report")s$report<-brohn_runner_report_provenance(store,command,project)else {
      s$evidence_command<-command;s$evidence<-brohn_runner_provenance_read(store,command,project)
    }
    s$identity<-brohn_hash(list(command,s$context));selected(s);show(s);invisible(s)
  }
  shiny::observeEvent(input$runner_provenance_open,attempt(function()open(input$runner_provenance_open)))
  shiny::observeEvent(input$runner_provenance_run,attempt(function(){
    s<-bound();c<-input$runner_provenance_run;brohn_fields(c,c("identity","run_id"),label="Report code source")
    brohn_require(!is.null(s$report)&&identical(c$identity,s$identity),"Use the current report's participant sessions.")
    refs<-Filter(function(r)identical(r$run_id,c$run_id),s$report$refs)
    brohn_require(length(refs)==1L,"This session is not a source of the selected report.")
    command<-list(kind="run",id=c$run_id,study_id=s$command$study_id);e<-brohn_runner_provenance_read(store,command,s$project_id)
    brohn_require(identical(e$source$deployment_id,refs[[1L]]$deployment_id)&&identical(e$source$design_hash,refs[[1L]]$design_hash),"The original report and participant session do not have the same release/design identity.")
    s$report_link<-list(id=s$command$id,revision=s$command$revision,hash=s$command$hash);e$report<-s$report_link
    s$evidence<-e;s$evidence_command<-command;s$identity<-brohn_hash(list(s$command,s$context,command));selected(s);show(s)
  }))
  shiny::observeEvent(input$runner_provenance_page,attempt(function(){s<-bound();c<-input$runner_provenance_page
    brohn_fields(c,c("identity","offset"),label="Report code source page")
    brohn_require(!is.null(s$report)&&is.null(s$evidence)&&identical(c$identity,s$identity)&&brohn_number(c$offset,0,s$report$total-1L,TRUE)&&c$offset%%40==0,"Choose a current report source page.")
    s$offset<-as.integer(c$offset);selected(s);show(s)
  }))
  shiny::observeEvent(input$runner_provenance_back,attempt(function(){s<-bound();brohn_require(!is.null(s$report),"Open a report's participant sessions first.")
    s$evidence<-NULL;s$evidence_command<-NULL;s$report_link<-NULL;s$identity<-brohn_hash(list(s$command,s$context));selected(s);show(s)
  }))
  shiny::observeEvent(input$runner_provenance_close,attempt(function(){s<-bound(FALSE);selected(NULL);shiny::removeModal();if(is.function(s$return_view))s$return_view()}))
  output$runner_provenance_evidence<-shiny::downloadHandler(filename=function()shiny::isolate(paste0(evidence()$source$id,"-participant-code.json")),contentType="application/json",
    content=function(file)prepare_download(function()shiny::isolate(brohn_write_json_file(evidence(),file,maximum=1024^2))))
  output$runner_provenance_manifest<-shiny::downloadHandler(filename=function()shiny::isolate(paste0(evidence()$source$id,"-code-manifest.json")),contentType="application/json",
    content=function(file)prepare_download(function()shiny::isolate({e<-evidence();brohn_require(e$status=="pinned","No historical participant-code manifest was preserved.");brohn_write_json_file(e$manifest,file,maximum=1024^2)})))
  invisible(list(open=open,selected=bound,evidence=evidence))
}

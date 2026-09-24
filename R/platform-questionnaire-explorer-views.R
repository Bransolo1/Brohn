# Bounded, source-linked inspection. Scientific summaries remain the saved ones.
.brohn_qx_fields <- list(questions = c("search", "question_id", "condition_id"),
  answers = c("search", "question_id", "condition_id", "stimulus_id", "participant_id", "session_id", "status"))
.brohn_qx_label <- function(x, fallback = "Not retained") if (is.null(x)) fallback else as.character(x)
.brohn_qx_state_label <- function(x) switch(.brohn_qx_label(x, "unavailable"),
  optional_omission = "Optional omission", not_displayed = "Not displayed", dependency_invalidated = "Dependent answer cleared",
  answered = "Answered", information_acknowledged = "Information acknowledged", information_unacknowledged = "Information unacknowledged",
  invalidated_unanswered = "Cleared; unanswered", not_submitted = "Not submitted", gsub("_", " ", .brohn_qx_label(x), fixed = TRUE))
.brohn_qx_button <- function(label, action, context = NULL, collection = NULL, ..., id = NULL) {
  shiny::tags$button(type = "button", class = "btn btn-outline-secondary", id = id,
    `data-qx-action` = brohn_json(c(list(action = action, identity = context, collection = collection), list(...))), label)
}
.brohn_qx_script <- function() shiny::tags$script(shiny::HTML("(function(){
  if(window.brohnQuestionnaireExplorer)return;window.brohnQuestionnaireExplorer=true;
  let timer=null;
  // Shiny binds dynamically inserted tabsets without constructing Bootstrap's
  // Tab objects. Construct them on each mount so roles and keyboard navigation
  // exist before the first click or server-driven tab change.
  function bindTabs(){if(!window.bootstrap||!window.bootstrap.Tab)return;
    document.querySelectorAll('#qx_tab [data-bs-toggle=\"tab\"],#qx_tab [data-toggle=\"tab\"]').forEach(tab=>window.bootstrap.Tab.getOrCreateInstance(tab));}
  new MutationObserver(bindTabs).observe(document.body,{childList:true,subtree:true});bindTabs();
  function send(command,element){
    clearTimeout(timer);const root=document.getElementById('qx-root');if(!root||!window.Shiny)return;
    const group=command.collection==='questions'?'questions':'answers';const form={};
    root.querySelectorAll('[data-qx-form=\"'+group+'\"] input,[data-qx-form=\"'+group+'\"] select').forEach(x=>{if(x.dataset.qxField)form[x.dataset.qxField]=x.value;});
    command.form=form;command.form_identity=root.dataset.qxIdentity;command.focus_id=element&&element.id||null;
    Shiny.setInputValue('qx_action',command,{priority:'event'});
  }
  document.addEventListener('click',event=>{const button=event.target.closest('[data-qx-action]');if(!button)return;event.preventDefault();send(JSON.parse(button.dataset.qxAction),button);});
  document.addEventListener('keydown',event=>{const field=event.target.closest('input[data-qx-field]');if(!field||event.key!=='Enter')return;event.preventDefault();const form=field.closest('[data-qx-form]');send({action:'apply',collection:form.dataset.qxForm},field);});
  document.addEventListener('input',event=>{const field=event.target.closest('[data-qx-field]');if(!field||field.tagName==='SELECT')return;clearTimeout(timer);timer=setTimeout(()=>{if(!field.isConnected)return;send({action:'apply',collection:field.closest('[data-qx-form]').dataset.qxForm},field);},450);});
  document.addEventListener('change',event=>{const field=event.target.closest('select[data-qx-field]');if(field)send({action:'apply',collection:field.closest('[data-qx-form]').dataset.qxForm},field);});
})();"))

brohn_questionnaire_explorer_ui <- function(report_record) {
  if (!identical(report_record$body$analysis$kind, "questionnaire")) return(NULL)
  shiny::tagList(brohn_card(title = "Explore saved questionnaire answers",
    subtitle = "Find every saved question and response, including omissions, and inspect its original source and retained changes.",
    brohn_command("Explore all answers", "open_questionnaire_explorer", list(report_id = report_record$id,
      report_revision = report_record$revision, report_hash = brohn_hash(report_record$body), project_id = report_record$project_id), id = "qx-open")),
    .brohn_qx_script(), shiny::uiOutput("qx_progress"), shiny::uiOutput("qx_error"), shiny::uiOutput("qx_body"))
}
.brohn_qx_controls <- function(collection, identity) {
  labels <- c(search = "Find prompt or participant/session code (Match case)", question_id = "Exact question code", condition_id = "Exact condition code",
    stimulus_id = "Exact stimulus code", participant_id = "Exact participant code", session_id = "Exact session code", status = "Final state")
  shiny::div(class = "brohn-qx-controls", `data-qx-form` = collection,
    shiny::div(class = "brohn-form-grid", lapply(.brohn_qx_fields[[collection]], function(field) {
      id <- paste("qx", collection, field, sep = "_")
      choices <- c("Every available final state" = "", "Answered" = "answered", "Optional omission" = "optional_omission",
        "Not displayed" = "not_displayed", "Information acknowledged" = "information_acknowledged", "Information unacknowledged" = "information_unacknowledged",
        "Cleared; unanswered" = "invalidated_unanswered", "Not submitted" = "not_submitted")
      shiny::div(class = "form-group", shiny::tags$label(`for` = id, labels[[field]]),
        if (field == "status") shiny::tags$select(id = id, class = "form-control shiny-input-select", `data-qx-field` = field,
          lapply(seq_along(choices), function(i) shiny::tags$option(value = choices[[i]], names(choices)[[i]]))) else
          shiny::tags$input(id = id, type = "text", class = "form-control shiny-input-text", value = "", maxlength = 1024, `data-qx-field` = field))
    }), shiny::div(class = "form-group", shiny::tags$label(`for` = paste0("qx_", collection, "_limit"), "Records per page"),
      shiny::tags$select(id = paste0("qx_", collection, "_limit"), class = "form-control", `data-qx-field` = "limit",
        lapply(c(25, 50, 100), function(n) shiny::tags$option(value = n, selected = if (n == 50) "selected" else NULL, n))))),
    .brohn_qx_button("Apply filters", "apply", identity, collection),
    shiny::p(class = "brohn-muted", if (collection == "questions") "Saved whole-report counts and means stay unchanged by participant filters in Answers." else
      "Codes are supplied identifiers, not verified identity. Repeated visits remain separate. Empty filters include every final state."))
}
.brohn_qx_filters <- function(form, collection) {
  brohn_require(is.list(form) && all(names(form) %in% c(.brohn_qx_fields[[collection]], "limit")), "Use the current labelled answer filters.")
  filters <- form[intersect(names(form), .brohn_qx_fields[[collection]])]
  brohn_require(all(vapply(filters, function(x) brohn_text(x, 1024, TRUE) && validUTF8(x), logical(1))), "This search is too long or contains unsupported text. Use a shorter phrase or an exact code.")
  filters <- filters[vapply(filters, nzchar, logical(1))]
  if (!length(filters)) filters <- list()
  limit <- suppressWarnings(as.integer(brohn_default(form$limit, "50")))
  brohn_require(length(limit) == 1L && !is.na(limit) && limit %in% c(25L, 50L, 100L), "Choose 25, 50 or 100 records per page.")
  list(filters = filters, limit = limit)
}
.brohn_qx_person <- function(row) {
  if (isFALSE(row$summary$participant_linkage) || is.null(row$participant_id) || startsWith(row$participant_id, "unlinked:"))
    paste("Unlinked session", .brohn_qx_label(row$session_id)) else paste("Participant/session code:", row$participant_id, "/", .brohn_qx_label(row$session_id))
}
.brohn_qx_saved_mean <- function(summary) {
  if (!is.null(summary$numeric_response_mean) && isTRUE(summary$numeric_summary_status %in% c("declared_quantitative_question", "source_numeric_values_without_design")))
    format(summary$numeric_response_mean, digits = 17, trim = TRUE) else "Unavailable in saved summary"
}
.brohn_qx_page_ui <- function(page, identity, collection, generation, offset = 0L, previous = FALSE) {
  if (is.null(page)) return(NULL)
  count <- if (page$returned) paste0(offset+1L, "\u2013", offset+page$returned) else "0"
  fields <- if (collection == "questions") c("Question", "Condition", "Saved counts and mean", "Open") else
    if (collection == "distribution") c("Native value", "Saved count", "Open") else c("Assessment", "Participant/session code", "State and native value", "Open")
  cells <- function(row) {
    preview <- .brohn_qx_label(row$value_preview$text, if (identical(row$value_kind, "absent")) "No value field" else "")
    if (identical(row$value_kind, "text") && identical(preview, "")) preview <- "Empty text"
    open <- .brohn_qx_button(if (collection == "questions") "Open question" else "Open record", "record", identity, collection,
      key = row$record_key, hash = row$source_hash, generation = generation, id = paste0("qx-row-", collection, "-", row$ordinal))
    if (collection == "questions") return(list(shiny::tagList(shiny::strong(.brohn_qx_label(row$prompt$text)), shiny::p(row$question_id)),
      .brohn_qx_label(row$condition_id, "No condition"), paste("Responses", .brohn_qx_label(row$summary$response_count), "\u00b7 answered", .brohn_qx_label(row$summary$answered_count),
        "\u00b7 missing", .brohn_qx_label(row$summary$missing_count), "\u00b7 mean", .brohn_qx_saved_mean(row$summary)), open))
    if (collection == "distribution") return(list(shiny::tagList(shiny::strong(row$value_kind), shiny::p(preview)), .brohn_qx_label(row$summary$count), open))
    list(shiny::tagList(shiny::strong(.brohn_qx_label(row$prompt$text, row$question_id)), shiny::p(paste(.brohn_qx_label(row$question_id), "\u00b7", .brohn_qx_label(row$condition_id, "No condition")))),
      .brohn_qx_person(row), shiny::tagList(shiny::strong(.brohn_qx_state_label(row$status)), shiny::p(paste(row$value_kind, "\u00b7", preview)),
        if (isTRUE(row$value_preview$truncated)) shiny::tags$small("Abbreviated in this list; open for the full value.")), open)
  }
  rows <- lapply(page$rows, cells)
  shiny::tagList(shiny::p(role = "status", `aria-live` = "polite", paste0("Showing ", count, " of ", page$matching_total,
    " matching records; ", page$source_total, " records in this saved source.")),
    if (!page$returned) shiny::p("No records match these filters. The saved source remains available.") else
      shiny::tags$table(class = "brohn-qx-table", shiny::tags$caption(class = "brohn-qx-caption visually-hidden", paste("Saved", collection)),
        shiny::tags$thead(shiny::tags$tr(lapply(fields, function(x) shiny::tags$th(scope = "col", x)))),
        shiny::tags$tbody(lapply(rows, function(row) shiny::tags$tr(lapply(seq_along(row), function(i) shiny::tags$td(`data-label` = fields[[i]], row[[i]])))))),
    shiny::div(class = "brohn-toolbar", if (previous) .brohn_qx_button("Previous page", "previous", identity, collection, generation = generation),
      if (!is.null(page$next_cursor)) .brohn_qx_button("Next page", "next", identity, collection, generation = generation)))
}
.brohn_qx_chunk_ui <- function(chunk, identity, source = FALSE, previous = FALSE) {
  if (is.null(chunk)) return(NULL)
  shiny::tagList(shiny::p(paste(if (source) "Canonical source JSON" else if (chunk$value_kind == "text") "Native text" else "Canonical JSON value",
    "\u00b7", chunk$total_characters, "characters \u00b7", chunk$total_utf8_bytes, "UTF-8 bytes")),
    shiny::p(paste("Characters", if (chunk$total_characters) chunk$offset+1L else 0L, "to", chunk$offset+nchar(chunk$text, type = "chars"))),
    # The span preserves an initial LF that the HTML parser otherwise consumes
    # immediately after <pre>; noWS prevents pretty-print whitespace additions.
    shiny::tags$pre(class = "brohn-qx-value", tabindex = "0", role = "region", `aria-label` = if (source) "Complete source text chunk" else "Complete value text chunk",
      .noWS = "inside", shiny::tags$span(chunk$text)),
    if (chunk$total_characters == 0L) shiny::p("Empty text (zero characters)."),
    shiny::div(class = "brohn-toolbar", if (previous) .brohn_qx_button("Previous text chunk", "chunk_previous", identity, field = chunk$field,
      detail_key = chunk$record_key, chunk_offset = chunk$offset),
      if (!is.null(chunk$next_offset)) .brohn_qx_button("Next text chunk", "chunk_next", identity, field = chunk$field,
        detail_key = chunk$record_key, chunk_offset = chunk$offset)),
    shiny::p(class = "brohn-muted", paste("Full value SHA-256:", chunk$value_hash)))
}

brohn_install_questionnaire_explorer <- function(input, output, session, store, state, attempt, message, prepare_download, open_session = NULL) {
  owned <- new.env(parent = emptyenv()); owned$opened <- NULL; owned$last_used <- Sys.time()
  selected <- shiny::reactiveVal(NULL); ready <- shiny::reactiveVal(NULL); progress <- shiny::reactiveVal(NULL); problem <- shiny::reactiveVal(NULL)
  pages <- shiny::reactiveValues(questions = NULL, answers = NULL, distribution = NULL, history = NULL, invalidations = NULL)
  detail <- shiny::reactiveValues(record = NULL, anchor = NULL, value = NULL, source = NULL, mode = "value", parent = NULL,
    value_offsets = list(0L), source_offsets = list(0L))
  configurations <- new.env(parent = emptyenv())
  close <- function() {if (!is.null(owned$opened)) brohn_close_questionnaire_index(owned$opened); owned$opened <- NULL; ready(NULL)
    for (key in c("questions", "answers", "distribution", "history", "invalidations")) {pages[[key]] <- NULL; configurations[[key]] <- NULL}
    detail$record <- NULL; detail$value <- NULL; detail$source <- NULL; detail$parent <- NULL}
  session$onSessionEnded(close)
  # Read catalog records only for an action; never cache a complete inline analysis
  # in a reactive expression for the lifetime of the researcher session.
  report <- function() {shiny::req(identical(state$page, "report"), state$report_id); brohn_get_entity(store, "report", state$report_id)}
  shiny::observeEvent(list(state$page, state$report_id), {s <- selected()
    if (!is.null(s) && (!identical(state$page, "report") || !identical(state$report_id, s$report_id))) {close(); selected(NULL); progress(NULL); problem(NULL)}
  }, ignoreInit = FALSE, priority = 100)
  guard <- function(identity = NULL) {
    s <- selected()
    brohn_require(!is.null(s) && !is.null(owned$opened) && identical(state$page, "report") && identical(state$report_id, s$report_id),
      "Reopen this exact saved report before exploring its answers.")
    brohn_require(is.null(identity) || identical(identity, ready()$identity), "This action belongs to an earlier answer view. Use the current controls.")
    tryCatch(brohn_check_questionnaire_index_context(store, owned$opened, s$report_id, s$report_revision, s$report_hash, s$project_id),
      error = function(e) {close(); stop(e)})
    owned$last_used <- Sys.time(); owned$opened$handle
  }
  handle_error <- function(fn) attempt(function() {problem(NULL); tryCatch(fn(), error = function(e) {problem(conditionMessage(e)); stop(e)})})
  fetch <- function(collection, filters = list(), limit = 50L, cursor = NULL, offset = 0L) {
    handle <- guard(); previous <- configurations[[collection]]
    page <- brohn_questionnaire_index_page(handle, collection, filters, cursor, limit)
    generation <- if (is.null(previous)) 1L else previous$generation+1L
    configurations[[collection]] <- list(filters = filters, limit = limit, cursor = cursor, offset = offset, generation = generation)
    pages[[collection]] <- page
  }
  bind_job <- function(job) {
    s <- selected(); brohn_require(identical(job$request$report_id, s$report_id) && job$request$report_revision == s$report_revision &&
      identical(job$request$report_hash, s$report_hash) && identical(job$request$project_id, s$project_id), "The prepared view belongs to another saved report.")
    if (identical(job$status, "succeeded") && is.null(owned$opened)) {
      owned$opened <- brohn_open_questionnaire_index(store, job$result$questionnaire_index_id, job$result$index_hash,
        s$report_id, s$report_revision, s$report_hash, s$project_id)
      b <- owned$opened$record$body
      ready(list(identity = brohn_hash(list(source = s, index_id = owned$opened$record$id, index_hash = job$result$index_hash)), origin = b$origin,
        answer_source = b$answer_source, original_counts = b$original_counts, binding = b$binding, source_support = b$source_support))
      fetch("questions"); fetch("answers")
    }
    progress(job)
  }
  shiny::observeEvent(input$open_questionnaire_explorer, handle_error(function() {
    r <- report(); command <- input$open_questionnaire_explorer
    brohn_require(identical(command$report_id, r$id) && command$report_revision == r$revision && identical(command$report_hash, brohn_hash(r$body)) &&
      identical(command$project_id, r$project_id), "Reopen this report before exploring its saved answers.")
    if (!is.null(owned$opened) && identical(selected(), command)) {guard(); return(invisible(NULL))}
    close(); selected(command); job <- brohn_queue_questionnaire_index(store, r$id, r$revision, command$report_hash, r$project_id)
    bind_job(job); message(if (job$status == "succeeded") "Complete saved answers ready" else "Preparing saved answers")
  }))
  shiny::observe({s <- selected(); p <- progress(); if (is.null(s) || is.null(p) || !p$status %in% c("queued", "running")) return()
    shiny::invalidateLater(750, session)
    handle_error(function() {r <- report(); brohn_require(identical(r$id, s$report_id), "Open the original saved report.")
      job <- .brohn_qexplorer_job(store, p$id, s$project_id); if (!identical(job, p)) bind_job(job)})
  })
  shiny::observe({shiny::invalidateLater(60000, session); if (!is.null(owned$opened) && as.numeric(difftime(Sys.time(), owned$last_used, units = "secs")) > 900) {
    close(); problem("This answer view closed after 15 minutes without use. Explore all answers reopens the saved index.")
  }})
  output$qx_progress <- shiny::renderUI({p <- progress(); if (is.null(p) || p$status == "succeeded") return(NULL)
    brohn_card(class = "brohn-qx", title = if (p$status %in% c("queued", "running")) "Preparing saved answers" else "Saved answers need attention",
      shiny::p(role = "status", `aria-live` = "polite", if (p$status %in% c("queued", "running")) "Reading and indexing the complete retained source. Your saved report remains usable." else paste("View preparation", p$status)),
      if (p$status %in% c("queued", "running")) shiny::tags$progress(`aria-label` = "Preparing saved answers"),
      if (!is.null(p$error$message)) shiny::p(p$error$message),
      if (p$status %in% c("queued", "running")) brohn_command("Cancel preparation", "qx_cancel", list(job_id = p$id, report_hash = selected()$report_hash)) else
        brohn_command("Retry saved source", "qx_retry", list(job_id = p$id, report_hash = selected()$report_hash)))
  })
  output$qx_error <- shiny::renderUI({text <- problem(); if (is.null(text)) return(NULL)
    shiny::div(class = "brohn-alert brohn-alert-error", role = "alert", shiny::p(text), shiny::p("The report and complete downloads remain available."),
      if (!is.null(selected())) brohn_command("Rebuild from this saved source", "qx_rebuild", selected()))
  })
  for (name in c("cancel", "retry", "rebuild")) local({action <- name; shiny::observeEvent(input[[paste0("qx_", action)]], handle_error(function() {
    s <- selected(); r <- report(); command <- input[[paste0("qx_", action)]]
    brohn_require(!is.null(s) && identical(r$id, s$report_id) && identical(command$report_hash, s$report_hash), "This request belongs to another report.")
    if (action == "rebuild") {brohn_require(identical(command, s), "Use this saved source's rebuild action."); close()
      job <- brohn_queue_questionnaire_index(store, s$report_id, s$report_revision, s$report_hash, s$project_id, rebuild = TRUE)
    } else {brohn_require(identical(command$job_id, progress()$id), "This preparation action is stale.")
      job <- if (action == "cancel") {brohn_cancel_questionnaire_index(store, command$job_id, s$project_id); .brohn_qexplorer_job(store, command$job_id, s$project_id)} else
        brohn_retry_questionnaire_index(store, command$job_id, s$project_id)}
    bind_job(job)
  }))})
  output$qx_body <- shiny::renderUI({r <- ready(); if (is.null(r)) return(NULL)
    shiny::div(id = "qx-root", class = "brohn-qx", `data-qx-identity` = r$identity,
      brohn_card(title = "Complete saved answers", subtitle = paste("Original origin:", r$origin, "\u00b7 source:", gsub("_", " ", r$answer_source, fixed = TRUE)),
        shiny::p("These are retained source records. Browsing preserves the report's original scientific status, counts and design."),
        shiny::p(paste("Recorded questionnaire responses:", .brohn_qx_label(r$original_counts$observations), "\u00b7 saved question summaries:",
          .brohn_qx_label(r$original_counts$features), "\u00b7 final-state records can also include information and questions that were not displayed.")),
        shiny::tabsetPanel(id = "qx_tab", selected = "Questions",
          shiny::tabPanel("Questions", .brohn_qx_controls("questions", r$identity), shiny::uiOutput("qx_questions")),
          shiny::tabPanel("Answers", .brohn_qx_controls("answers", r$identity), shiny::uiOutput("qx_answers"))),
        shiny::uiOutput("qx_detail")))
  })
  for (name in c("questions", "answers")) local({collection <- name
    output[[paste0("qx_", collection)]] <- shiny::renderUI({r <- ready(); p <- pages[[collection]]; if (is.null(r) || is.null(p)) return(NULL)
      c <- configurations[[collection]]; .brohn_qx_page_ui(p, r$identity, collection, c$generation, c$offset, !is.null(p$previous_cursor))})
  })
  read_chunk <- function(field, offset = 0L, offsets = list(0L)) {
    h <- guard(); row <- detail$record$record
    chunk <- brohn_questionnaire_index_value(h, row$record_key, if (field == "record") row$source_hash else row$value_hash, offset, field = field)
    key <- if (field == "record") "source" else "value"; detail[[key]] <- chunk; detail[[paste0(key, "_offsets")]] <- offsets
  }
  open_record <- function(row, focus_id = NULL, retain_parent = FALSE) {
    h <- guard(); result <- brohn_questionnaire_index_record(h, row$record_key, row$source_hash)
    if (!retain_parent) detail$parent <- NULL
    detail$record <- result; detail$anchor <- focus_id; detail$mode <- "value"; detail$value <- NULL; detail$source <- NULL
    for (collection in c("distribution", "history", "invalidations")) {pages[[collection]] <- NULL; configurations[[collection]] <- NULL}
    if (!is.null(row$value_hash)) read_chunk("value")
    if (row$collection == "questions") fetch("distribution", list(parent_key = row$record_key))
    session$onFlushed(function() session$sendCustomMessage("brohn-focus", "qx-detail-heading"), once = TRUE)
  }
  shiny::observeEvent(input$qx_action, handle_error(function() {
    command <- input$qx_action; h <- guard(command$form_identity)
    brohn_require(is.null(command$identity) || identical(command$identity, ready()$identity), "This row belongs to an earlier answer view.")
    action <- command$action; collection <- command$collection
    if (action %in% c("close", "parent", "answers", "changes", "source", "value", "session", "chunk_next", "chunk_previous"))
      brohn_require(!is.null(detail$record) && identical(command$detail_key, detail$record$record$record_key), "This detail changed. Use the current record's controls.")
    if (!is.null(collection) && collection %in% c("questions", "answers")) {
      query <- .brohn_qx_filters(command$form, collection); old <- configurations[[collection]]
      changed <- !identical(brohn_hash(query), brohn_hash(old[c("filters", "limit")]))
      if (changed || action == "apply") {
        if (changed) {fetch(collection, query$filters, query$limit); detail$record <- NULL; detail$value <- NULL; detail$source <- NULL}
        if (action %in% c("apply", "next", "previous", "record")) return(invisible(NULL))
      }
    }
    if (action %in% c("next", "previous")) {
      brohn_require(collection %in% c("questions", "answers", "distribution", "history", "invalidations"), "Choose an available saved collection.")
      c <- configurations[[collection]]; p <- pages[[collection]]
      brohn_require(!is.null(c) && identical(as.numeric(command$generation), as.numeric(c$generation)), "This page changed. Use its current navigation controls.")
      if (action == "next") {brohn_require(!is.null(p$next_cursor), "This is the last page."); fetch(collection, c$filters, c$limit, p$next_cursor, c$offset+p$returned)} else {
        brohn_require(!is.null(p$previous_cursor), "This is the first page."); fetch(collection, c$filters, c$limit, p$previous_cursor, max(0L, c$offset-c$limit))}
    } else if (action == "record") {
      c <- configurations[[collection]]; p <- pages[[collection]]
      brohn_require(!is.null(c) && identical(as.numeric(command$generation), as.numeric(c$generation)), "This record list changed. Select its current row.")
      rows <- Filter(function(r) identical(r$record_key, command$key) && identical(r$source_hash, command$hash), p$rows)
      brohn_require(length(rows) == 1L, "Choose a record in the current source page.")
      parent <- if (collection %in% c("history", "invalidations", "distribution")) brohn_default(detail$parent, detail$record) else NULL
      anchor <- if (!is.null(parent)) detail$anchor else command$focus_id
      open_record(rows[[1L]], anchor); detail$parent <- parent
    } else if (action == "close") {
      target <- detail$anchor; detail$record <- NULL; detail$value <- NULL; detail$source <- NULL; detail$parent <- NULL
      if (!is.null(target)) session$onFlushed(function() session$sendCustomMessage("brohn-focus", target), once = TRUE)
    } else if (action == "parent") {
      parent <- detail$parent; brohn_require(!is.null(parent), "The parent record is unavailable."); open_record(parent$record, detail$anchor)
    } else if (action == "answers") {
      row <- detail$record$record; brohn_require(identical(row$collection, "questions"), "Open the saved question first.")
      filters <- list(question_id = row$question_id); if (!is.null(row$condition_id)) filters$condition_id <- row$condition_id
      for (field in .brohn_qx_fields$answers) {
        if (field == "status") shiny::updateSelectInput(session, paste0("qx_answers_", field), selected = "") else
          shiny::updateTextInput(session, paste0("qx_answers_", field), value = brohn_default(filters[[field]], ""))}
      fetch("answers", filters, configurations$answers$limit); shiny::updateTabsetPanel(session, "qx_tab", selected = "Answers")
      detail$record <- NULL; detail$value <- NULL; detail$source <- NULL
    } else if (action == "session") {
      brohn_require(is.function(open_session), "Exact participant-session review is unavailable in this installation.")
      local({
        row <- detail$record$record
        open_session(owned$opened,row$record_key,row$source_hash,validate_selection=function(){
          guard()
          brohn_require(!is.null(detail$record)&&identical(detail$record$record$record_key,row$record_key)&&
            identical(detail$record$record$source_hash,row$source_hash),"Reopen the selected saved answer.")
          invisible(TRUE)
        })
      })
    } else if (action == "changes") {
      row <- detail$record$record; brohn_require(identical(row$collection, "answers"), "Open a final answer before inspecting its changes.")
      detail$mode <- "changes"; fetch("history", list(parent_key = row$record_key)); fetch("invalidations", list(parent_key = row$record_key))
    } else if (action == "source") {detail$mode <- "source"; read_chunk("record")
    } else if (action == "value") {detail$mode <- "value"
    } else if (action %in% c("chunk_next", "chunk_previous")) {
      field <- command$field; brohn_require(field %in% c("value", "record"), "Choose a complete value or source chunk.")
      key <- if (field == "record") "source" else "value"; chunk <- detail[[key]]; offsets <- detail[[paste0(key, "_offsets")]]
      brohn_require(!is.null(chunk) && identical(as.numeric(command$chunk_offset), as.numeric(chunk$offset)), "This text chunk changed. Use its current controls.")
      if (action == "chunk_next") {brohn_require(!is.null(chunk$next_offset), "This is the last text chunk."); read_chunk(field, chunk$next_offset, c(offsets, list(chunk$next_offset)))} else {
        brohn_require(length(offsets) > 1L, "This is the first text chunk."); offsets <- head(offsets, -1L); read_chunk(field, tail(offsets, 1L)[[1L]], offsets)}
    } else brohn_require(FALSE, "Choose an available saved-answer action.")
  }))
  output$qx_detail <- shiny::renderUI({r <- ready(); d <- detail$record; if (is.null(r) || is.null(d)) return(NULL)
    row <- d$record; original <- if (!is.null(d$record_json)) brohn_parse(d$record_json, 128*1024) else NULL
    button <- function(label, action) .brohn_qx_button(label, action, r$identity, detail_key = row$record_key)
    prompt <- brohn_default(d$full_prompt, brohn_default(original$prompt, row$prompt$text))
    pages_ui <- function(collection) {p <- pages[[collection]]; c <- configurations[[collection]]; if (is.null(p)) return(NULL)
      .brohn_qx_page_ui(p, r$identity, collection, c$generation, c$offset, !is.null(p$previous_cursor))}
    shiny::tags$section(class = "brohn-qx-detail", `aria-labelledby` = "qx-detail-heading",
      shiny::h3(id = "qx-detail-heading", tabindex = "-1", if (row$collection == "questions") "Saved question" else if (row$collection == "history" && isTRUE(d$links$reference$confirmation)) "Confirmed the same answer" else "Saved record"),
      shiny::div(class = "brohn-toolbar", button("Close detail", "close"),
        if (!is.null(detail$parent)) button("Return to parent record", "parent")),
      if (!is.null(prompt)) shiny::p(class = "brohn-qx-prompt", prompt),
      shiny::p(paste("Question:", .brohn_qx_label(row$question_id), "\u00b7 state:", .brohn_qx_state_label(row$status), "\u00b7 native type:", row$value_kind)),
      if (row$collection != "questions") shiny::p(.brohn_qx_person(row)),
      shiny::p(paste("Placement:", .brohn_qx_label(row$occurrence_id), "\u00b7 compiled step:", .brohn_qx_label(row$step_id))),
      shiny::p(paste("Condition:", .brohn_qx_label(row$condition_id), "\u00b7 stimulus:", .brohn_qx_label(row$stimulus_id))),
      if (row$collection == "questions") shiny::tagList(shiny::p(paste("Saved mean:", .brohn_qx_saved_mean(row$summary))),
        button("See answers", "answers"), shiny::h4("Complete saved distribution"), pages_ui("distribution")),
      shiny::div(class = "brohn-toolbar", if (!is.null(row$value_hash)) button("Value", "value"),
        if (row$collection == "answers") button("Changes", "changes"), button("Complete source record", "source")),
      if (is.function(open_session) && identical(row$collection,"answers") && identical(d$answer_source,"revision_effective_records") &&
          identical(d$links$run_source$support,"retained_run_identity") && r$binding$origin %in% c("sample","pilot","live"))
        button("Review participant session", "session"),
      if (detail$mode == "value") if (is.null(row$value_hash)) shiny::p("No native value was retained for this record.") else
        .brohn_qx_chunk_ui(detail$value, r$identity, previous = length(detail$value_offsets) > 1L),
      if (detail$mode == "source") .brohn_qx_chunk_ui(detail$source, r$identity, source = TRUE, previous = length(detail$source_offsets) > 1L),
      if (detail$mode == "changes") if (identical(d$answer_source, "recorded_observations")) shiny::p("No edit history was retained for this source.") else
        shiny::tagList(shiny::h4("Acknowledged changes"), shiny::p("Confirmations of the same answer are retained evidence; they do not add a newly scored response."), pages_ui("history"),
          shiny::h4("Dependent-answer clearing"), pages_ui("invalidations")),
      if (row$collection == "answers") shiny::p(paste("Original response time:", .brohn_qx_label(row$summary$response_time_ms, "Unavailable in retained source"),
        if (!is.null(row$summary$response_time_ms)) "ms" else "", "\u00b7 timing is retained as recorded, without inferring reading time.")),
      shiny::tags$details(shiny::tags$summary("Source"), shiny::p(paste("Report:", r$binding$report_id, "\u00b7 revision", r$binding$report_revision)),
        shiny::p(paste("Report SHA-256:", r$binding$report_hash)), shiny::p(paste("Analysis SHA-256:", r$binding$analysis_sha256)),
        shiny::p(paste("Source ordinal:", row$ordinal)), shiny::tags$pre(brohn_json(d$source_path)), shiny::p(paste("Source row SHA-256:", row$source_hash)),
        if (length(d$links)) shiny::tags$pre(brohn_json(d$links)),
        if (!is.function(open_session) || !identical(row$collection,"answers") || !identical(d$answer_source,"revision_effective_records") ||
            !identical(d$links$run_source$support,"retained_run_identity") || !r$binding$origin %in% c("sample","pilot","live"))
          shiny::p("No exact local session link is retained for this source. Complete saved source records remain inspectable.")))
  })
  # Expose only bounded inspection state to component tests and owning modules.
  invisible(list(ready = ready, pages = pages, detail = detail, progress = progress, selected = selected, close = close))
}

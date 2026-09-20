source("R/platform-participant-equipment.R") # Registered optional new-draft policy.
# Actual Shiny observers and real saved-study revision CAS; no browser claim.
for (module in c("platform-core", "platform-store", "platform-library", "platform-scales", "platform-question-sections", "platform-question-sections-views", "platform-app")) source(paste0("R/", module, ".R"), encoding = "UTF-8")
source("tests/fixtures/question-sections-original.R")
local({
  checks <- 0L
  check <- function(label, ok) {if (!isTRUE(ok)) stop("FAIL: ", label); checks <<- checks+1L}
  rejected <- function(expr) inherits(try(force(expr), silent = TRUE), "try-error")
  root <- tempfile("brohn-section-editor-"); dir.create(root)
  store <- brohn_open_store(file.path(root, "workspace"))
  brohn_initialise_library(store)
  on.exit({brohn_close_store(store); resolved <- normalizePath(root, winslash = "/", mustWork = TRUE)
    stopifnot(startsWith(resolved, paste0(normalizePath(tempdir(), winslash = "/"), "/")), startsWith(basename(resolved), "brohn-section-editor-"))
    Sys.chmod(list.files(resolved, full.names = TRUE, recursive = TRUE, all.files = TRUE), "0666"); unlink(resolved, recursive = TRUE)}, add = TRUE)
  original <- brohn_sections_fixture(); saved <- brohn_put_entity(store, "study", original$id, original)
  summary <- htmltools::renderTags(brohn_question_sections_ui(original))$html
  check("flat summary offers explicit enable with source identity", grepl("Enable questionnaire sections", summary, fixed = TRUE) && grepl(brohn_hash(original), summary, fixed = TRUE))
  server <- function(input, output, session) {
    current <- new.env(parent = emptyenv()); current$study <- saved
    state <- shiny::reactiveValues(page = "study", stage = "Questions", error = NULL, status = NULL)
    attempt <- function(fn) {state$error <- NULL; tryCatch(fn(), error = function(e) {state$error <- conditionMessage(e); NULL})}
    message <- function(text) state$status <- text
    capture <- function() invisible(NULL)
    update_study <- function(d) current$study <- brohn_save_study(store, d, current$study$revision)
    api <- brohn_install_question_sections_ui(input, output, session, current, state, capture, update_study, attempt, message)
  }
  shiny::testServer(server, {
    cmd <- function(...) c(api$context()[c("editor_id", "version")], list(...))
    form_cmd <- function(..., new_label = NULL, target_id = NULL) cmd(..., node_identity = api$context()$node_identity,
      form = list(node_identity = api$context()$node_identity, label = input$sections_label,
        placement = input$sections_placement, new_label = new_label, target_id = target_id))
    open <- function() {
      session$setInputs(study_form_identity = paste(current$study$id, "Questions", sep = ":"),
        question_sections_open = list(study_id = current$study$id, design_hash = brohn_hash(current$study$body)))
      session$flushReact()
    }
    bind <- function(label = NULL, placement = NULL) {
      ctx <- api$context(); s <- brohn_find(api$design()$questionnaire_sections$sections, ctx$section_id)
      item <- if (is.null(ctx$group_id)) s else brohn_find(s$groups, ctx$group_id)
      session$setInputs(sections_node_identity = ctx$node_identity,
        sections_label = if (is.null(label)) item$label else label,
        sections_placement = if (is.null(placement)) item$placement else placement)
      session$flushReact()
    }
    pick <- function(sid, gid = NULL) {session$setInputs(sections_select = cmd(section_id = sid, group_id = gid)); session$flushReact(); bind()}
    open(); bind()
    check("Enable opens an all-fixed draft and does not save immediately", api$context()$active && current$study$revision == saved$revision && !"questionnaire_sections" %in% names(current$study$body))
    check("actual Shiny tree shows dependency grouping and original members", grepl("grouped questions", output$sections_editor_tree$html, fixed = TRUE) && grepl("Original question q-follow", output$sections_editor_tree$html, fixed = TRUE))
    check("unsupported first-section movement is disabled with a reason", grepl("disabled", output$sections_editor_node$html, fixed = TRUE) && grepl("no neighbour", output$sections_editor_node$html, fixed = TRUE))
    before <- brohn_hash(current$study$body); old <- cmd()
    session$setInputs(sections_cancel = old)
    check("Cancel discards enable without changing source", !api$context()$active && identical(before, brohn_hash(current$study$body)))
    session$setInputs(sections_save = old)
    check("late Save after Cancel cannot change a saved study", !is.null(state$error) && identical(before, brohn_hash(current$study$body)))
    open(); bind(label = "Original consumer sections"); session$setInputs(sections_save = cmd())
    check(paste("Save includes unapplied current name and creates one real revision", brohn_default(state$error, "")), is.null(state$error) && current$study$revision == saved$revision+1L && current$study$body$questionnaire_sections$sections[[1]]$label == "Original consumer sections")
    check("saved source is exactly the real catalog revision", identical(brohn_hash(brohn_study(store, current$study$id)$body), brohn_hash(current$study$body)))
    check("enabled summary exposes edit with named sections", grepl("Edit questionnaire sections", htmltools::renderTags(brohn_question_sections_ui(current$study$body))$html, fixed = TRUE))
    open(); bind(); sid <- api$design()$questionnaire_sections$sections[[1]]$id
    pair <- api$design()$questionnaire_sections$sections[[1]]$groups[[2]]$id
    pick(sid, pair)
    check("selected group exposes complete member count and explicit scope effects", grepl("Move all 2 questions together", output$sections_editor_node$html, fixed = TRUE) && grepl("contained scale", output$sections_editor_node$html, fixed = TRUE))
    bind(placement = "shuffle"); session$setInputs(sections_apply = cmd()); session$flushReact(); bind()
    check("actual field Apply saves group variation only in editor draft", brohn_find(api$design()$questionnaire_sections$sections[[1]]$groups, pair)$placement == "shuffle" && current$study$revision == saved$revision+1L)
    prior_version <- cmd(); session$setInputs(sections_action = cmd(op = "move_group", section_id = sid, group_id = pair, direction = 1L)); session$flushReact(); bind()
    check("keyboard group move preserves exact internal dependency order", identical(brohn_find(api$design()$questionnaire_sections$sections[[1]]$groups, pair)$question_ids, list("q-driver", "q-follow")) && api$design()$questionnaire_sections$sections[[1]]$groups[[3]]$id == pair)
    draft_hash <- brohn_hash(api$design()); session$setInputs(sections_action = c(prior_version, list(op = "move_group", section_id = sid, group_id = pair, direction = 1L)))
    check("stale ordered-list command cannot address newer layout", grepl("draft changed", state$error, fixed = TRUE) && identical(draft_hash, brohn_hash(api$design())))
    check("form actions capture live fields and do not serialize a debounced name", grepl("data-brohn-sections-form", output$sections_new_control$html, fixed = TRUE) && !grepl('label', output$sections_new_control$html, fixed = TRUE))
    stale <- form_cmd(op = "new_section", section_id = sid, group_id = pair, label = "Old rendered name", new_label = "Original follow-up section")
    stale$form$node_identity <- "previous-selected-node"; draft_hash <- brohn_hash(api$design())
    session$setInputs(sections_action = stale)
    check("previous selected-node form cannot create a section", grepl("selected group changed", state$error, fixed = TRUE) && identical(draft_hash, brohn_hash(api$design())))
    stale <- form_cmd(op = "new_section", section_id = sid, group_id = "different-group", new_label = "Wrong selected group")
    session$setInputs(sections_action = stale)
    check("a current form cannot address a different selected group", grepl("selected group changed", state$error, fixed = TRUE) && identical(draft_hash, brohn_hash(api$design())))
    # Atomic click snapshot is current even when Shiny's debounced scalar input
    # and an obsolete command label still contain the previous visible name.
    session$setInputs(sections_new_label = "Old debounced name", sections_action = form_cmd(op = "new_section", section_id = sid, group_id = pair,
      label = "Old rendered name", new_label = "Original follow-up section")); session$flushReact(); bind()
    target <- api$context()$section_id
    check("creating section moves complete group and tracks its generated parent", target != sid && api$context()$group_id == pair && brohn_find(api$design()$questionnaire_sections$sections, target)$label == "Original follow-up section")
    pick(target); bind(placement = "shuffle"); session$setInputs(sections_apply = cmd()); session$flushReact(); bind()
    check("actual field Apply saves section variation independently from group policy", brohn_find(api$design()$questionnaire_sections$sections, target)$placement == "shuffle")
    pick(target, pair)
    session$setInputs(sections_target = "Old debounced target", sections_action = form_cmd(op = "transfer_group", section_id = target, group_id = pair, target_id = sid)); session$flushReact(); bind()
    check("moving back prunes empty source section and preserves membership", api$context()$section_id == sid && is.null(brohn_find(api$design()$questionnaire_sections$sections, target)) && identical(brohn_find(brohn_find(api$design()$questionnaire_sections$sections, sid)$groups, pair)$question_ids, list("q-driver", "q-follow")))
    session$setInputs(sections_action = cmd(op = "scope", section_id = sid, group_id = pair, scope = "after_each")); session$flushReact(); bind()
    check("whole-group assessment placement changes all members explicitly", all(vapply(Filter(function(q) q$id %in% c("q-driver", "q-follow"), api$design()$questions), function(q) q$scope == "after_each", logical(1))) && api$context()$section_id != sid)
    before_group <- brohn_find(api$design()$questionnaire_sections$sections, sid)$groups[[1]]$id
    pick(sid, before_group); draft_hash <- brohn_hash(api$design())
    check("invalid scope actions show disabled controls and dependency reason", grepl("unavailable", output$sections_editor_node$html, fixed = TRUE) && grepl("disabled", output$sections_editor_node$html, fixed = TRUE))
    session$setInputs(sections_action = cmd(op = "scope", section_id = sid, group_id = before_group, scope = "end"))
    check("invalid scope command cannot mutate draft or saved source", !is.null(state$error) && identical(draft_hash, brohn_hash(api$design())) && current$study$revision == saved$revision+1L)
    check("scope rejection is visible in the dialog with a named next action", grepl('role="alert"', output$sections_editor_error$html, fixed = TRUE) && grepl("Keep its current placement", output$sections_editor_error$html, fixed = TRUE))
    session$setInputs(sections_label = "Uncommitted rename before rejected move", sections_action = cmd(op = "scope", section_id = sid, group_id = before_group, scope = "end"))
    check("failed structural change also rolls back pending name application", !is.null(state$error) && identical(draft_hash, brohn_hash(api$design())))
    bind()
    session$setInputs(sections_save = cmd()); check("accepted structural draft saves exactly one further revision", is.null(state$error) && current$study$revision == saved$revision+2L)
    check("group operations retain original typed answer values", identical(brohn_json(current$study$body$questions[[1]]$options), brohn_json(original$questions[[1]]$options)))
    open(); bind(); prior <- cmd(); original_saved <- brohn_hash(current$study$body)
    session$setInputs(sections_action = cmd(op = "flat")); session$flushReact()
    check("flat opt-out draft explains source order and remains unsaved", !"questionnaire_sections" %in% names(api$design()) && grepl("Flat order selected", output$sections_editor_tree$html, fixed = TRUE) && identical(original_saved, brohn_hash(current$study$body)))
    session$setInputs(sections_cancel = prior)
    check("current-editor Cancel remains usable after draft version changes", !api$context()$active && identical(original_saved, brohn_hash(current$study$body)))
    open(); bind(); old_editor <- prior; now <- cmd()
    session$setInputs(sections_cancel = old_editor)
    check("old editor cancellation cannot close a newly opened draft", api$context()$active && !is.null(state$error))
    session$setInputs(sections_node_identity = "old-form", sections_label = "Must not save", sections_save = now)
    check("unbound or stale selected fields cannot overwrite a name", !is.null(state$error) && identical(original_saved, brohn_hash(current$study$body)))
    bind(); changed <- current$study$body; changed$title <- "Changed outside section editor"; update_study(changed)
    session$setInputs(sections_save = cmd())
    check("underlying revision/hash change rejects stale publication", grepl("underlying study changed", state$error, fixed = TRUE) && current$study$body$title == changed$title)
    session$setInputs(sections_cancel = cmd()); open(); bind(); state$page <- "home"
    session$setInputs(sections_save = cmd())
    check("navigation away cannot save an otherwise matching editor", grepl("Questions page", state$error, fixed = TRUE))
    session$setInputs(sections_cancel = cmd()); state$page <- "study"; open(); bind()
    # Persisted external update bypasses the UI context; real save CAS is final.
    external <- current$study$body; external$description <- "Original external CAS change"
    brohn_save_study(store, external, current$study$revision)
    session$setInputs(sections_save = cmd())
    check("external catalog change fails final revision CAS", !is.null(state$error) && brohn_study(store, current$study$id)$body$description == external$description)
    session$setInputs(sections_cancel = cmd()); current$study <- brohn_study(store, current$study$id)
    current$study <- brohn_archive_study(store, current$study$id, TRUE, current$study$revision)
    open(); check("archived study cannot open a section editor", !api$context()$active && !is.null(state$error))
  })

  scale_design <- brohn_new_design("Original scale placement editor", "survey", "study-scale-editor")
  scale_design$questions <- lapply(1:2, function(i) brohn_question(paste("Original scale item", i), "rating", "before", paste0("scale-item-", i)))
  scale_design$scales <- list(list(schema = "brohn-questionnaire-scale/1.0", id = "original-scale", label = "Original synthetic scale", version = "original/1", source = "Original arithmetic-only fixture", scope = "before",
    items = lapply(2:1, function(i) list(question_id = paste0("scale-item-", i), reverse = FALSE, min = 1, max = 7)),
    scoring = list(aggregation = "mean", missing = "complete", minimum_answered = 2L, prorate = FALSE), conversion = NULL))
  scale_design$questionnaire_sections <- brohn_question_sections_new(scale_design)
  saved <- brohn_put_entity(store, "study", scale_design$id, scale_design)
  shiny::testServer(server, {
    session$setInputs(study_form_identity = paste(saved$id, "Questions", sep = ":"), question_sections_open = list(study_id = saved$id, design_hash = brohn_hash(saved$body)))
    session$flushReact(); c <- api$context(); s <- api$design()$questionnaire_sections$sections[[1]]; g <- s$groups[[1]]
    session$setInputs(sections_select = c(c[c("editor_id", "version")], list(section_id = s$id, group_id = g$id))); session$flushReact()
    c <- api$context(); session$setInputs(sections_node_identity = c$node_identity, sections_label = g$label, sections_placement = g$placement)
    session$setInputs(sections_action = c(c[c("editor_id", "version")], list(op = "scope", section_id = s$id, group_id = g$id, scope = "end"))); session$flushReact()
    check("actual Shiny scope move retains entire scale and authored member order", is.null(state$error) && api$design()$scales[[1]]$scope == "end" && identical(api$design()$questionnaire_sections$sections[[1]]$groups[[1]]$question_ids, list("scale-item-1", "scale-item-2")))
    c <- api$context(); session$setInputs(sections_node_identity = c$node_identity, sections_label = g$label, sections_placement = "fixed", sections_save = c[c("editor_id", "version")])
    check("scope move saves matching question and scale placement together", is.null(state$error) && current$study$body$scales[[1]]$scope == "end" && all(vapply(current$study$body$questions, function(q) q$scope == "end", logical(1))))
    check("scope move preserves instrument key order and typed bounds", identical(current$study$body$scales[[1]]$items, saved$body$scales[[1]]$items))
  })
  cat(sprintf("PASS: %d questionnaire section editor checks (real Shiny draft, revision CAS, moves, scope, cancel, stale guards)\n", checks))
})

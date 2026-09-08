source("R/platform-load.R"); brohn_load()
source("R/platform-maxdiff.R"); source("R/platform-maxdiff-views.R")
local({
  checks <- 0L
  check <- function(name, value) {if (!isTRUE(value)) stop("MaxDiff UI QA: ", name, call. = FALSE); checks <<- checks+1L}
  rejects <- function(expr) inherits(try(force(expr), silent = TRUE), "try-error")
  d <- brohn_maxdiff_new(id = "original-explicit-choice")
  body <- list(id = "original-choice-study", title = "Original UI fixture", archived = FALSE, maxdiff = list(d), description = "Retained underlying design")
  server <- function(input, output, session) {
    current <- new.env(parent = emptyenv()); current$study <- list(id = body$id, revision = 1L, body = body); current$pending <- NULL
    state <- shiny::reactiveValues(page = "study", stage = "Tasks", error = NULL)
    attempt <- function(fn) {state$error <- NULL; tryCatch(fn(), error = function(e) {state$error <- conditionMessage(e); NULL})}
    update_study <- function(design) {current$study <- list(id = design$id, revision = current$study$revision+1L, body = design)}
    capture <- function() {if (!is.null(current$pending)) {b <- current$study$body; b$description <- current$pending; update_study(b); current$pending <- NULL}}
    api <- brohn_install_maxdiff_ui(input, output, session, current, state, attempt, capture, update_study)
  }
  shiny::testServer(server, {
    fill_structure <- function(context = api$context(), exercise = context$exercise) {
      args <- list(maxdiff_structure_identity = paste(context$token, context$version, sep = ":"))
      for (i in exercise$items) args[[brohn_maxdiff_field_id(context$token, context$version, "label", i$id)]] <- i$label
      for (s in exercise$sets) args[[brohn_maxdiff_field_id(context$token, context$version, "members", s$id)]] <- unlist(s$item_ids)
      do.call(session$setInputs, args)
    }
    fill <- function() {
      context <- api$context(); e <- context$exercise
      session$setInputs(maxdiff_form_identity = context$token, maxdiff_title = e$title, maxdiff_origin = e$origin, maxdiff_rights = e$materials_rights,
        maxdiff_seed = e$seed, maxdiff_prompt = e$settings$prompt, maxdiff_best = e$settings$best_label, maxdiff_worst = e$settings$worst_label,
        maxdiff_required = e$settings$required, maxdiff_set_order = e$settings$set_order, maxdiff_item_order = e$settings$item_order,
        maxdiff_rationale = e$settings$design_rationale, maxdiff_fit = e$settings$analysis$fit_aggregate)
      fill_structure(context); context
    }
    command <- function(action, extra = list(), context = api$context()) {
      session$setInputs(maxdiff_structure_command = c(list(token = context$token, version = context$version, action = action), extra))
    }
    session$setInputs(study_form_identity = paste(body$id, "Tasks", sep = ":"), maxdiff_edit = d$id)
    ctx <- fill()
    check("Tasks editor opens the saved stable exercise", is.null(state$error) && identical(ctx$exercise, d))
    session$setInputs(maxdiff_prompt = "", maxdiff_save = list(token = ctx$token))
    check("empty research framing cannot be saved", !is.null(state$error) && current$study$revision == 1L)
    session$setInputs(maxdiff_prompt = "Which original feature is most and least useful?", maxdiff_best = "Most useful", maxdiff_worst = "Most useful")
    session$setInputs(maxdiff_save = list(token = ctx$token))
    check("equal best and worst labels fail explicitly", !is.null(state$error) && current$study$revision == 1L)
    session$setInputs(maxdiff_worst = "Least useful", maxdiff_fit = "true")
    session$setInputs(maxdiff_save = list(token = ctx$token))
    check("checkbox strings cannot enable an aggregate recipe", !is.null(state$error) && current$study$revision == 1L)
    session$setInputs(maxdiff_fit = TRUE, maxdiff_required = FALSE, maxdiff_origin = "researcher_supplied", maxdiff_rights = "Original researcher-owned labels.",
      maxdiff_seed = 73, maxdiff_set_order = "fixed", maxdiff_item_order = "fixed")
    changed <- ctx$exercise; changed$items[[1L]]$label <- "Original renamed feature"; fill_structure(ctx, changed)
    first_set <- changed$sets[[1L]]; first_member <- first_set$item_ids[[1L]]
    command("move_member", list(id = first_set$id, item_id = first_member, direction = 1L)); ctx2 <- api$context()
    check("keyboard move preserves item IDs and prior label edits", is.null(state$error) && ctx2$exercise$sets[[1L]]$item_ids[[2L]] == first_member &&
      ctx2$exercise$items[[1L]]$id == d$items[[1L]]$id && ctx2$exercise$items[[1L]]$label == "Original renamed feature")
    command("remove_set", list(id = first_set$id), ctx)
    check("stale structure command cannot change a newer draft", !is.null(state$error) && api$context()$version == ctx2$version && length(api$context()$exercise$sets) == 4L)
    fill_structure(ctx2); command("move_set", list(id = first_set$id, direction = 1L)); ctx <- api$context(); fill_structure(ctx)
    check("choice-set order moves without changing stable set identity", ctx$exercise$sets[[2L]]$id == first_set$id)
    command("remove_item", list(id = d$items[[1L]]$id))
    check("referenced item removal is blocked before corrupting sets", !is.null(state$error) && length(api$context()$exercise$items) == 4L)
    command("add_item"); ctx <- api$context(); new_item <- tail(ctx$exercise$items, 1L)[[1L]]; fill_structure(ctx)
    check("new item receives a separate stable identity", length(ctx$exercise$items) == 5L && !new_item$id %in% brohn_ids(d$items))
    session$setInputs(maxdiff_save = list(token = ctx$token))
    check("unnamed added item blocks save without rewriting study", !is.null(state$error) && current$study$revision == 1L)
    command("remove_item", list(id = new_item$id)); ctx <- api$context(); fill_structure(ctx)
    session$setInputs(maxdiff_review = list(token = ctx$token))
    checked <- output$maxdiff_review_output$html
    check("review shows exact coverage and no optimum claim", is.null(state$error) && grepl("do not certify an optimal design", checked, fixed = TRUE) && grepl("Fixed item positions", checked, fixed = TRUE))
    session$setInputs(maxdiff_save = list(token = ctx$token)); saved <- current$study
    check("Save persists framing, order, seed and optional pair requirement once", is.null(state$error) && saved$revision == 2L && is.null(api$context()) &&
      saved$body$maxdiff[[1L]]$settings$prompt == "Which original feature is most and least useful?" && !saved$body$maxdiff[[1L]]$settings$required &&
      saved$body$maxdiff[[1L]]$seed == 73 && saved$body$maxdiff[[1L]]$settings$item_order == "fixed")
    check("underlying design remains intact and frozen compiler uses the saved order", saved$body$description == body$description &&
      identical(brohn_maxdiff_compile(saved$body$maxdiff[[1L]])$trials[[1L]]$item_order, saved$body$maxdiff[[1L]]$sets[[1L]]$item_ids))
    session$setInputs(maxdiff_edit = d$id); old <- fill(); session$setInputs(maxdiff_title = "Discard this title", maxdiff_cancel = list(token = old$token))
    check("Cancel discards pending edits without a revision", is.null(api$context()) && identical(current$study, saved))
    session$setInputs(maxdiff_save = list(token = old$token))
    check("late Save after Cancel cannot resurrect the draft", !is.null(state$error) && identical(current$study, saved))
    session$setInputs(maxdiff_edit = d$id); ctx <- fill(); session$setInputs(maxdiff_cancel = list(token = old$token))
    check("stale Cancel cannot close a newer editor", !is.null(state$error) && api$context()$token == ctx$token)
    session$setInputs(maxdiff_form_identity = old$token, maxdiff_save = list(token = ctx$token))
    check("stale field identity cannot save into the new draft", !is.null(state$error) && identical(current$study, saved))
    session$setInputs(maxdiff_form_identity = ctx$token)
    current$pending <- "Concurrent pending Tasks edit"
    session$setInputs(maxdiff_save = list(token = ctx$token))
    check("flushed underlying change invalidates the old draft", !is.null(state$error) && current$study$revision == saved$revision+1L &&
      current$study$body$description == "Concurrent pending Tasks edit" && identical(current$study$body$maxdiff, saved$body$maxdiff))
    session$setInputs(maxdiff_edit = d$id); ctx <- fill(); state$stage <- "Questions"; session$setInputs(maxdiff_delete = list(token = ctx$token))
    check("navigation prevents a late remove command", !is.null(state$error) && length(current$study$body$maxdiff) == 1L)
    state$stage <- "Tasks"; current$study$body$archived <- TRUE; session$setInputs(maxdiff_save = list(token = ctx$token))
    check("archived studies reject late edits", !is.null(state$error))
    current$study$body$archived <- FALSE; session$setInputs(maxdiff_edit = d$id); ctx <- fill()
    session$setInputs(maxdiff_delete = list(token = ctx$token))
    check("explicit remove changes only this current exercise", is.null(state$error) && length(current$study$body$maxdiff) == 0L && current$study$body$description == "Concurrent pending Tasks edit")
    session$setInputs(maxdiff_add = 1L); ctx <- fill(); session$setInputs(maxdiff_cancel = list(token = ctx$token))
    check("add then Cancel does not insert example materials", is.null(state$error) && length(current$study$body$maxdiff) == 0L)
  })
  # The UI consumes the immutable analysis; it never reruns scoring or fills
  # missing values with zero. Check exact full labels and escaped local content.
  d$items <- head(d$items, 3L); d$items[[1L]]$label <- "<script>untrusted original label</script>"; d$sets <- list(list(id = "all", item_ids = as.list(brohn_ids(d$items))))
  row <- function(n, best, worst) list(id = paste0("r-", n), participant_id = paste0("anonymous-", n), participant_linkage = FALSE, session_id = "visit", exposure_id = paste0("e-", n),
    design_hash = brohn_hash(d), set_id = "all", item_order = d$sets[[1L]]$item_ids, presented = TRUE, status = "answered", best_id = best, worst_id = worst, missing_reason = NULL)
  rows <- lapply(1:3, function(i) row(i, paste0("item-", i), paste0("item-", c(2, 3, 1)[[i]])))
  result <- brohn_maxdiff_analysis(d, rows); before <- brohn_hash(result)
  html <- as.character(brohn_maxdiff_result_ui(result))
  check("result view preserves immutable analysis", identical(before, brohn_hash(result)))
  check("available paired utilities remain aggregate with honest anonymous linkage", grepl("Aggregate paired utilities", html, fixed = TRUE) && grepl("Unique people are unavailable", html, fixed = TRUE))
  check("untrusted item text is escaped in both counts and utilities", !grepl("<script>untrusted", html, fixed = TRUE) && grepl("&lt;script&gt;untrusted", html, fixed = TRUE))
  check("saved design and response hashes are visible without replacement", grepl(result$design_hash, html, fixed = TRUE) && grepl(result$responses_hash, html, fixed = TRUE))
  incomplete <- row(4, NULL, NULL); incomplete$status <- "missing"; incomplete$missing_reason <- "Participant skipped"
  result <- brohn_maxdiff_analysis(d, list(incomplete)); html <- as.character(brohn_maxdiff_result_ui(result))
  check("missing denominator remains unavailable instead of zero preference", grepl("Unavailable", html, fixed = TRUE) && all(vapply(result$items, function(i) is.null(i$exposure_adjusted_score), logical(1))))
  check("unavailable model gives its concrete missing-pair reason", grepl("no complete pairs", html, fixed = TRUE) && !grepl("Saved aggregate paired MaxDiff utilities", html, fixed = TRUE))
  result$exposures[[1L]]$missing_reason <- "Tampered ledger"
  check("tampered saved response evidence fails closed", rejects(brohn_maxdiff_result_ui(result)))
  d$settings$analysis$fit_aggregate <- FALSE; result <- brohn_maxdiff_analysis(d, list()); html <- as.character(brohn_maxdiff_result_ui(result))
  check("explicit counts-only design is not presented as a failed fit", grepl("not requested", html, fixed = TRUE) && grepl("aggregate fit disabled", html, fixed = TRUE))
  summary <- as.character(brohn_maxdiff_summary_ui(body))
  check("Tasks entry exposes actual dedicated explicit choice editor", grepl("Add best-worst exercise", summary, fixed = TRUE) && grepl("maxdiff_edit", summary, fixed = TRUE))
  structure <- as.character(brohn_maxdiff_structure_ui(d, "original-form", 3L))
  check("ordered controls have semantic labels and scoped command versions", grepl("Move position 2 up in set 1", structure, fixed = TRUE) && grepl("data-maxdiff-version=\"3\"", structure, fixed = TRUE))
  cat("Brohn MaxDiff UI:", checks, "checks passed\n")
})

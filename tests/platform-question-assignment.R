source("R/platform-participant-equipment.R") # Registered optional new-draft policy.
# Exact independent oracle + real catalog/API/portable-release compatibility.
for (module in c("platform-core", "platform-store", "platform-delivery", "platform-portability")) source(paste0("R/", module, ".R"), encoding = "UTF-8")
source("tests/fixtures/question-assignment-original.R")
local({
  count <- 0L
  check <- function(name, ok) {if (!isTRUE(ok)) stop("FAIL: ", name); count <<- count+1L}
  rejects <- function(x) inherits(try(force(x), silent = TRUE), "try-error")
  read <- function(path) brohn_parse(paste(readLines(path, warn = FALSE, encoding = "UTF-8"), collapse = "\n"))
  legacy <- read("tests/fixtures/question-assignment-legacy.json")
  oracle <- read("tests/fixtures/question-assignment-oracle.json")
  old <- legacy$design
  check("new authoring pins policy even while randomization is disabled", identical(brohn_question()$option_assignment, "participant-sha256/1.0") && !brohn_question()$randomize_options)
  check("pre-change fixture has no implicit policy migration", all(vapply(old$questions, function(q) !"option_assignment" %in% names(q), logical(1))))
  check("two historical full protocols reproduce pre-change canonical bytes", all(vapply(legacy$protocols, function(p) identical(brohn_json(p), brohn_json(brohn_compile(old, p$allocation_index))), logical(1))))
  upgraded <- brohn_upgrade_option_assignment(old)
  check("explicit migration changes randomized questions only, without mutating original", all(vapply(upgraded$questions, function(q) identical(q$option_assignment, "participant-sha256/1.0"), logical(1))) && identical(brohn_hash(old), brohn_hash(legacy$design)))
  check("migration is idempotent at exact canonical hash", identical(brohn_hash(upgraded), brohn_hash(brohn_upgrade_option_assignment(upgraded))))
  no_shuffle <- old; no_shuffle$questions[[1]]$randomize_options <- FALSE
  check("migration leaves a fixed legacy question untouched", identical(brohn_upgrade_option_assignment(no_shuffle)$questions[[1]], no_shuffle$questions[[1]]))
  selected <- brohn_upgrade_option_assignment(old, "q-after")
  check("single-question migration preserves unselected legacy questions", identical(selected$questions[[1]], old$questions[[1]]) && identical(selected$questions[[3]], old$questions[[3]]) && identical(selected$questions[[2]]$option_assignment, "participant-sha256/1.0"))
  check("empty explicit selection is an exact no-op", identical(brohn_upgrade_option_assignment(old, character()), old))
  for (ids in list("missing", c("q-after", "q-after"), NA_character_, 1, list("q-after"))) check("invalid migration targets cannot modify the design", rejects(brohn_upgrade_option_assignment(old, ids)))
  for (bad in list(NULL, TRUE, 1, "participant-sha256/9.0", c("participant-sha256/1.0", "legacy-timeline-r/1.0"))) {
    invalid <- old; invalid$questions[[1]]["option_assignment"] <- list(bad)
    check("unknown/null/non-scalar assignment fails before release", rejects(brohn_compile(invalid)))
  }
  explicit_legacy <- old; explicit_legacy$questions[[1]]$option_assignment <- "legacy-timeline-r/1.0"
  steps <- function(d, i) Filter(function(s) s$type == "question", brohn_compile(d, i)$timeline)
  check("explicit legacy assignment retains historical realized order", identical(steps(old, 2)[[1]]$question$options, steps(explicit_legacy, 2)[[1]]$question$options))
  for (i in 1:12) {
    actual <- steps(upgraded, i)
    expected <- Filter(function(r) r$allocation_index == i, oracle$rows)
    check(paste("four assessment permutations match independent SHA-256 oracle, allocation", i), all(vapply(seq_along(actual), function(j)
      identical(as.list(brohn_ids(actual[[j]]$question$options)), expected[[j]]$option_order), logical(1))))
    check(paste("typed zero/false/text/number values remain exact for allocation", i), all(vapply(actual, function(s) {
      source <- brohn_find(upgraded$questions, s$question$id)
      all(vapply(s$question$options, function(o) identical(o, brohn_find(source$options, o$id)), logical(1)))
    }, logical(1))))
  }
  orders <- vapply(1:12, function(i) paste(brohn_ids(steps(upgraded, i)[[1]]$question$options), collapse = ","), character(1))
  check("prespecified twelve participants receive more than one order", length(unique(orders)) > 1L)
  stable <- steps(upgraded, 7)
  unrelated <- brohn_question("Original unrelated information", "information", "before", "q-unrelated")
  shifted <- upgraded; shifted$questions <- c(list(unrelated), shifted$questions); shifted$instructions <- "Original extra instruction"; shifted$baseline_ms <- 300L
  shifted_steps <- Filter(function(s) s$question$id != "q-unrelated", steps(shifted, 7))
  check("unrelated earlier items/instructions/baselines do not change assignments", identical(lapply(stable, function(s) s$question$options), lapply(shifted_steps, function(s) s$question$options)))
  reversed <- upgraded; reversed$stimuli <- rev(reversed$stimuli)
  by_instance <- function(items) {out <- lapply(items, function(s) s$question$options); names(out) <- vapply(items, function(s) paste(s$question$id, s$stimulus_id, sep = "/"), character(1)); out[order(names(out))]}
  check("reordering stimulus presentations preserves each exact stimulus question assignment", identical(by_instance(stable), by_instance(steps(reversed, 7))))
  check("after-each stimulus identities have distinct prescribed assignments", !identical(stable[[2]]$question$options, stable[[3]]$question$options))
  fixed <- upgraded; fixed$questions <- lapply(fixed$questions, function(q) {q$randomize_options <- FALSE; q})
  check("fixed options retain authored order for every context/allocation", all(vapply(c(steps(fixed, 1), steps(fixed, 12)), function(s) identical(s$question$options, brohn_find(fixed$questions, s$question$id)$options), logical(1))))
  kind <- RNGkind(); present <- exists(".Random.seed", .GlobalEnv, inherits = FALSE); if (present) prior <- .Random.seed
  on.exit({do.call(RNGkind, as.list(kind)); if (present) assign(".Random.seed", prior, .GlobalEnv)}, add = TRUE)
  suppressWarnings(RNGkind("L'Ecuyer-CMRG", "Box-Muller", "Rounding")); set.seed(45); state <- .Random.seed
  check("new assignment is independent of ambient RNG kinds and preserves RNG state", identical(lapply(stable, function(s) s$question$options), lapply(steps(upgraded, 7), function(s) s$question$options)) && identical(state, .Random.seed))
  do.call(RNGkind, as.list(kind))

  root <- .brohn_port_temp(); store <- brohn_open_store(file.path(root, "workspace"))
  on.exit({brohn_close_store(store); .brohn_port_cleanup(root)}, add = TRUE)
  saved <- brohn_put_entity(store, "study", old$id, old)
  old_release <- brohn_publish(store, old$id, origin = "sample", quota = 5L)
  app <- brohn_delivery_app(store, "www/participant")
  api_start <- function(release, client, operation) {
    raw <- charToRaw(brohn_json(list(consented = TRUE, client_id = client, operation_id = operation)))
    response <- app$call(list(PATH_INFO = paste0("/api/start/", release$token), REQUEST_METHOD = "POST", HTTP_HOST = "127.0.0.1:3840", HTTP_ORIGIN = "http://127.0.0.1:3840", CONTENT_TYPE = "application/json", CONTENT_LENGTH = as.character(length(raw)), rook.input = list(read = function(n = -1L) raw)))
    stopifnot(response$status == 200L); brohn_parse(response$body)
  }
  first <- api_start(old_release, "old-one", "old-start-one")
  check("old release actual Start API returns exact pre-change protocol", identical(brohn_json(first$protocol), brohn_json(legacy$protocols[[1]])))
  brohn_put_entity(store, "study", old$id, upgraded, expected_revision = saved$revision)
  new_release <- brohn_publish(store, old$id, origin = "sample", quota = 12L)
  second <- api_start(old_release, "old-two", "old-start-two")
  check("new start on old release stays legacy after explicit current-draft upgrade", identical(brohn_json(second$protocol), brohn_json(legacy$protocols[[2]])) && identical(old_release$design_hash, brohn_hash(old)))
  assigned <- lapply(1:12, function(i) api_start(new_release, paste0("new-", i), paste0("start-", i)))
  check("current release API freezes all twelve expected participant assignments", all(vapply(seq_along(assigned), function(i) identical(brohn_json(assigned[[i]]$protocol), brohn_json(brohn_compile(upgraded, i))), logical(1))))
  check("same start operation and same client new operation retain assignment and quota", identical(api_start(new_release, "new-1", "start-1"), assigned[[1]]) && identical(api_start(new_release, "new-1", "retry-start-1"), assigned[[1]]) && length(brohn_runs(store, old$id)) == 14L)
  pinned <- brohn_run(store, assigned[[7]]$run_id)
  brohn_close_store(store); store <- brohn_open_store(file.path(root, "workspace")); app <- brohn_delivery_app(store, "www/participant")
  check("catalog reopen preserves exact frozen run and API replay", identical(brohn_run(store, pinned$id), pinned) && identical(api_start(new_release, "new-7", "retry-after-reopen"), assigned[[7]]))
  portable <- brohn_export_design(store, old$id, file.path(root, "assignment.brohn-study.zip"))
  imported <- brohn_import_design(store, portable, title = "Original assignment portable copy")
  check("real portable ZIP import preserves explicit policies and typed options", all(vapply(seq_along(imported$body$questions), function(i) identical(imported$body$questions[[i]]$option_assignment, upgraded$questions[[i]]$option_assignment) && identical(imported$body$questions[[i]]$options, upgraded$questions[[i]]$options), logical(1))))
  check("portable clone receives new identities and remains deterministically compilable", !identical(imported$id, old$id) && !identical(imported$body$questions[[1]]$id, upgraded$questions[[1]]$id) && identical(brohn_json(brohn_compile(imported$body, 9)), brohn_json(brohn_compile(imported$body, 9))))
  cat(sprintf("PASS: %d option assignment checks (independent oracle, historical releases, actual API, replay, portable ZIP)\n", count))
})

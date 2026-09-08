# Local synthetic study preparation and post-browser inspection. No participant
# HTTP routes are added by this fixture; the real delivery service is used.
args <- commandArgs(trailingOnly = TRUE)
stopifnot(length(args) == 3L)
action <- args[[1]]; workspace <- args[[2]]; output <- args[[3]]
for (module in c("platform-core", "platform-store", "platform-delivery")) source(paste0("R/", module, ".R"))
store <- brohn_open_store(workspace)
write_json <- function(x) writeBin(charToRaw(enc2utf8(brohn_json(x))), output)
local({
  on.exit(brohn_close_store(store), add = TRUE)
  if (identical(action, "inspect")) {
    runs <- brohn_runs(store)
    write_json(list(runs = lapply(runs, function(run) list(id = run$id, study_id = run$study_id,
      origin = run$origin, alias = run$participant_alias, allocation_index = run$allocation_index,
      outcome = run$completion_status, transfer = run$transfer_status, acked = run$acked_sequence,
      design_hash = run$protocol$design_hash, order = run$protocol$realized_stimulus_order,
      events = brohn_run_events(store, run$id)))))
    return(invisible(NULL))
  }
  stopifnot(identical(action, "prepare"))
  make <- function(id, type, scope = "before", required = TRUE) {
    q <- brohn_question(paste("Question", id), type, scope, id)
    q$required <- required
    q
  }
  design <- brohn_new_design("Synthetic packaging participant journey", id = "browser-main")
  design$baseline_ms <- 100; design$fixation_ms <- 100
  for (i in 1:2) design$stimuli[[i]]$duration_ms <- 250
  design$stimuli[[2]]$content <- "Synthetic candidate package B"
  image <- tempfile(fileext = ".png")
  png::writePNG(array(rep(c(0.1, 0.3, 0.7), each = 32*24), c(24, 32, 3)), image)
  asset <- brohn_store_object(store, path = image, media_type = "image/png")
  unlink(image)
  design$stimuli[[1]]$type <- "image"; design$stimuli[[1]]$asset <- c(asset, list(width = 32, height = 24, filename = "original-synthetic.png"))
  single <- make("q-single", "single_choice")
  single$options <- list(list(id = "no", label = "No", value = FALSE), list(id = "yes", label = "Yes", value = TRUE))
  information <- make("q-information", "information", required = FALSE)
  text <- make("q-text", "text"); text$show_if <- list(op = "equals", question_id = single$id, value = FALSE)
  number <- make("q-number", "number"); number$min <- 0; number$max <- 10
  multiple <- make("q-multiple", "multiple_choice"); multiple$options <- multiple$options[1:3]
  dropdown <- make("q-dropdown", "dropdown"); dropdown$options <- dropdown$options[1:3]
  dropdown$options[[2]]$value <- "false" # String code must not become boolean FALSE.
  slider <- make("q-slider", "slider"); slider$min <- 0; slider$max <- 10
  rating <- make("q-rating", "rating", "after_each")
  long <- make("q-long", "long_text", "end")
  matrix <- make("q-matrix", "matrix", "end"); matrix$options <- matrix$options[1:3]
  matrix$rows <- list(list(id = "clarity", label = "Clarity"), list(id = "appeal", label = "Appeal"))
  ranking <- make("q-ranking", "ranking", "end"); ranking$options <- ranking$options[1:3]
  allocation <- make("q-allocation", "allocation", "end"); allocation$options <- allocation$options[1:2]; allocation$min <- 0; allocation$max <- 100
  design$questions <- list(single, information, text, number, multiple, dropdown, slider, rating, long, matrix, ranking, allocation)
  invisible(brohn_put_entity(store, "study", design$id, design))
  main <- brohn_publish(store, design$id, origin = "pilot", quota = 3, alias_required = FALSE)

  alias_design <- brohn_new_design("Synthetic alias-required survey", "survey", id = "browser-alias")
  alias_design$consent$required <- FALSE
  alias_design$questions <- list(make("q-alias-answer", "text"))
  invisible(brohn_put_entity(store, "study", alias_design$id, alias_design))
  alias <- brohn_publish(store, alias_design$id, origin = "pilot", quota = 3, alias_required = TRUE)

  timed_design <- brohn_new_design("Synthetic interruption", id = "browser-timed")
  timed_design$baseline_ms <- 0; timed_design$fixation_ms <- 0
  timed_design$questions <- list()
  timed_design$stimuli[[1]]$content <- "Interrupt this timed control"
  timed_design$stimuli[[2]]$content <- "Second timed candidate"
  for (i in 1:2) timed_design$stimuli[[i]]$duration_ms <- 5000
  invisible(brohn_put_entity(store, "study", timed_design$id, timed_design))
  timed <- brohn_publish(store, timed_design$id, origin = "pilot", quota = 3)

  closed <- brohn_publish(store, alias_design$id, origin = "pilot", quota = 2)
  invisible(brohn_deployment_state(store, closed$id, "closed"))
  write_json(list(main = main, alias = alias, timed = timed, closed = closed,
    asset_hash = asset$hash, main_design_hash = brohn_hash(design), question_types = lapply(design$questions, function(q) q$type)))
})

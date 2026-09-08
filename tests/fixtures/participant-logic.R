# Original synthetic exact-number and mixed-type display-logic regression.
args <- commandArgs(trailingOnly = TRUE)
stopifnot(length(args) == 3L)
for (module in c("platform-core", "platform-store", "platform-methods", "platform-analysis-plan", "platform-delivery", "platform-jobs")) source(paste0("R/", module, ".R"))
store <- brohn_open_store(args[[2]])
local({
  on.exit(brohn_close_store(store), add = TRUE)
  if (args[[1]] == "prepare") {
    d <- brohn_new_design("Original exact typed display logic", "survey")
    d$consent$required <- FALSE
    choice <- brohn_question("Choose exact numeric code", "single_choice", "before", "qa-exact")
    choice$options <- list(list(id = "near", label = "Near one", value = 1 + 1e-10), list(id = "one", label = "Exactly one", value = 1))
    mixed <- brohn_question("Choose original typed values", "multiple_choice", "before", "qa-mixed")
    mixed$options <- list(list(id = "number", label = "Number one", value = 1), list(id = "text", label = "Text one", value = "1"),
      list(id = "false", label = "Boolean false", value = FALSE), list(id = "zero", label = "Number zero", value = 0))
    info <- function(id, prompt, qid, op, value) {
      q <- brohn_question(prompt, "information", "before", id)
      q$required <- FALSE; q$show_if <- list(op = op, question_id = qid, value = value); q
    }
    questions <- list(choice, info("qa-equal-one", "Exact one branch", choice$id, "equals", 1),
      info("qa-not-one", "Not exact one branch", choice$id, "not_equals", 1), mixed,
      info("qa-number", "Numeric membership branch", mixed$id, "contains", 1),
      info("qa-text", "Text membership branch", mixed$id, "contains", "1"),
      info("qa-false", "False membership branch", mixed$id, "contains", FALSE),
      info("qa-zero", "Zero membership branch", mixed$id, "contains", 0))
    d$questions <- questions
    brohn_put_entity(store, "study", d$id, d)
    deployment <- brohn_publish(store, d$id, origin = "sample", quota = 2L, alias_required = TRUE)
    brohn_write_json_file(list(study_id = d$id, deployment = deployment), args[[3]])
  } else {
    config <- brohn_read_json_file(args[[3]])
    config$runs <- lapply(Filter(function(r) identical(r$study_id, config$study_id), brohn_runs(store)), function(r)
      list(id = r$id, status = r$completion_status, transfer = r$transfer_status, events = brohn_run_events(store, r$id),
        jobs = lapply(brohn_list_jobs(store, 100L, list(run_id = r$id)), function(j) j[c("id", "operation", "status")])))
    brohn_write_json_file(config, args[[3]])
  }
})

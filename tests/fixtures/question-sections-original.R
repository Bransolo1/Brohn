# Original same-scope questionnaire materials for pure domain tests.
brohn_sections_fixture <- function() {
  design <- brohn_new_design("Original questionnaire section fixture", "comparison", "study-sections")
  design$instructions <- "Original section-order fixture"; design$order <- "fixed"
  design$stimuli[[1]]$content <- "Original concept A"; design$stimuli[[2]]$content <- "Original concept B"
  question <- function(id, scope = "before") {
    q <- brohn_question(paste("Original question", id), "single_choice", scope, id)
    q$options <- list(list(id = "zero", label = "Original zero", value = 0), list(id = "false", label = "Original false", value = FALSE))
    q
  }
  design$questions <- list(question("q-start"), question("q-driver"), question("q-follow"),
    question("q-independent"), question("q-anchor"), question("q-later"), question("q-after", "after_each"), question("q-end", "end"))
  design$questions[[3]]$show_if <- list(op = "and", rules = list(
    list(op = "answered", question_id = "q-driver"),
    list(op = "not", rule = list(op = "equals", question_id = "q-driver", value = FALSE))))
  design$questions[[7]]$show_if <- list(op = "equals", question_id = "q-start", value = 0)
  design$questions[[8]]$show_if <- list(op = "equals", question_id = "q-start", value = 0)
  design
}

brohn_sections_order_fixture <- function() {
  d <- brohn_sections_fixture()
  for (id in c("q-middle", "q-extra", "q-last", "q-after-extra")) {
    q <- d$questions[[1]]; q$id <- id; q$prompt <- paste("Original question", id)
    q$scope <- if (id == "q-after-extra") "after_each" else "before"
    d$questions[[length(d$questions)+1L]] <- q
  }
  group <- function(id, members, placement = "fixed") list(id = id, label = paste("Original group", id), placement = placement, question_ids = as.list(members))
  section <- function(id, groups, placement = "fixed", scope = "before") list(id = id, label = paste("Original section", id), scope = scope, placement = placement, groups = groups)
  d$questionnaire_sections <- list(schema_version = "brohn-questionnaire-sections/1.0", assignment = "participant-sha256/1.0", sections = list(
    section("section-first", list(group("group-start", "q-start"))),
    section("section-choices", list(group("group-pair", c("q-driver", "q-follow"), "shuffle"),
      group("group-independent", "q-independent", "shuffle"), group("group-anchor", "q-anchor"), group("group-later", "q-later", "shuffle")), "shuffle"),
    section("section-middle", list(group("group-middle", "q-middle"))),
    section("section-extra", list(group("group-extra", "q-extra")), "shuffle"),
    section("section-last", list(group("group-last", "q-last"))),
    section("section-after", list(group("group-after", "q-after", "shuffle"), group("group-after-extra", "q-after-extra", "shuffle")), scope = "after_each"),
    section("section-end", list(group("group-end", "q-end")), scope = "end")))
  d
}

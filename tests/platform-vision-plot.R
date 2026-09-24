# Independent display states. These fictional buckets do not qualify a model.
source("R/platform-core.R", encoding = "UTF-8")
source("R/platform-vision-explorer-views.R", encoding = "UTF-8")
local({
  checks <- 0L
  check <- function(value, label) {
    if (!isTRUE(value)) stop(label, call. = FALSE)
    checks <<- checks + 1L
    cat("PASS", label, "\n")
  }
  plot <- list(metric = list(id = "hands.Left.pinch", unit = "image-width fraction"),
    fragments = list(list(points = list(list(x = 0, y = .2), list(x = .1, y = .3)))),
    states = list(list(first_time_text = "0", last_time_text = "0.1", frames = 2L,
      valid_frames = 1L, states = list(detected = 2L))))
  figure <- function(value) as.character(brohn_vision_plot_svg(value, 300))
  mixed <- figure(plot)
  check(grepl('fill="#b8b0ea"', mixed, fixed = TRUE),
    "Detected hands with mixed validity use the mixed-state colour")
  check(grepl("1 of 2 pass saved channel rules", mixed, fixed = TRUE),
    "Mixed state has an accessible exact valid/observed denominator")
  plot$states[[1L]]$valid_frames <- 2L
  check(grepl('fill="#a7e9d3"', figure(plot), fixed = TRUE),
    "All-valid detected hands use the valid-state colour")
  plot$states[[1L]]$valid_frames <- 0L
  check(grepl('fill="#e8c87a"', figure(plot), fixed = TRUE),
    "All-invalid detected hands use the invalid-state colour")
  plot$states[[1L]]$states <- list(absent = 1L, detected = 1L)
  check(grepl('fill="#b8b0ea"', figure(plot), fixed = TRUE),
    "Distinct saved states stay mixed even when all are invalid")
  check(grepl("<h3>Observed frame states</h3>", mixed, fixed = TRUE),
    "Frame-state heading nests directly under the report card heading")
  cat("PASS:", checks, "independent saved-video display checks\n")
})

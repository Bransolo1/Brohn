# Offline reports must retain a complete document, escaped researcher text and
# unchanged scientific output. Actual narrow-screen checks are browser journeys.
source("R/platform-load.R", encoding = "UTF-8"); brohn_load(ui = TRUE)
source("tests/fixtures/platform-analysis-fixture.R")
local({
  checks <- 0L
  check <- function(name, ok) {
    if (!isTRUE(ok)) stop(paste("Offline report QA failed:", name), call. = FALSE)
    checks <<- checks + 1L
  }
  f <- researcher_analysis_fixture()
  analysis <- brohn_questionnaire_analysis(brohn_import_responses(f$responses, f$response_mapping, f$design), f$design)
  title <- 'Original <study> & "ratings" \\1 / caf\u00e9'
  report <- list(id = "original-offline-report", title = title, created_at = "2026-09-08T00:00:00Z",
    origin = "sample", status = "ready", analysis = analysis,
    provenance = list(note = '</head><script src="https://invalid.example/execute"></script>', design = f$design),
    processing = list(method = "Original independently specified fictional rating arithmetic"))
  before <- brohn_hash(report)
  path <- tempfile("brohn-offline-report-", fileext = ".html")
  on.exit(unlink(path), add = TRUE)
  brohn_export_report_html(report, path)
  html <- paste(readLines(path, encoding = "UTF-8", warn = FALSE), collapse = "\n")
  count <- function(pattern) {x <- gregexpr(pattern, html, fixed = TRUE)[[1]]; if (x[[1]] == -1L) 0L else length(x)}
  check("one complete standards-mode English document", startsWith(html, '<!doctype html>\n<html lang="en">') && count("<html ") == 1 && count("</html>") == 1)
  check("head and body each appear exactly once", count("<head>") == 1 && count("</head>") == 1 && count("<body>") == 1 && count("</body>") == 1)
  check("head precedes the body", regexpr("</head>", html, fixed = TRUE)[1] < regexpr("<body>", html, fixed = TRUE)[1])
  check("escaped title survives in metadata and visible heading", count("&lt;study&gt; &amp;") == 2 && grepl('\\1 / caf\u00e9', html, fixed = TRUE))
  check("document retains Unicode encoding and mobile viewport", grepl('charset="UTF-8"', html, fixed = TRUE) && grepl('name="viewport"', html, fixed = TRUE))
  check("offline page retains its soft-dark styles", count("<style>") >= 1 && grepl("background:#11171c", html, fixed = TRUE))
  check("responsive rules survive serialization", grepl("@media(max-width:600px)", html, fixed = TRUE) && grepl("grid-template-columns:minmax(0,1fr)", html, fixed = TRUE))
  check("untrusted provenance cannot inject document or network script", !grepl("<script", html, fixed = TRUE) && grepl("&lt;script", html, fixed = TRUE))
  check("independent explicit-response contrast remains visible", grepl("1.375", html, fixed = TRUE) && grepl("eligible people", html, fixed = TRUE))
  check("rendering cannot change the canonical report", identical(before, brohn_hash(report)))
  cat(sprintf("Offline report HTML: %d scoped checks passed.\n", checks))
})

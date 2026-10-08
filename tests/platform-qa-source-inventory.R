# Exercise source conservation using only a fresh synthetic checkout tree.
source("scripts/qa-source-inventory.R", local = TRUE)
local({
  fixture <- tempfile("brohn-source-inventory-"); dir.create(fixture)
  root <- normalizePath(fixture, winslash = "/", mustWork = TRUE)
  on.exit({
    stopifnot(identical(normalizePath(fixture, winslash = "/", mustWork = TRUE), root),
      startsWith(root, paste0(normalizePath(tempdir(), winslash = "/", mustWork = TRUE), "/")))
    unlink(fixture, recursive = TRUE)
  }, add = TRUE)
  checks <- character()
  check <- function(name, value) {if (!isTRUE(value)) stop("FAIL: ", name); checks <<- c(checks, name)}
  rejects <- function(expr) inherits(try(force(expr), silent = TRUE), "try-error")
  put <- function(path, bytes) {
    destination <- file.path(fixture, path)
    dir.create(dirname(destination), recursive = TRUE, showWarnings = FALSE)
    writeBin(charToRaw(bytes), destination)
  }
  for (folder in c("R", "src", "scripts", "www", "tests")) dir.create(file.path(fixture, folder))
  originals <- c("app.R", "renv.lock", ".gitattributes", "package.json", "pnpm-lock.yaml", "playwright.config.mjs",
    "R/base.R", "R/assigned-domain/a.R", "R/assigned-authoring/R/a.R", "R/assigned-authoring/scripts/a.py",
    "src/guard.c", "scripts/workers/a.py", "www/participant/index.html", "www/assigned-participant/index.html",
    "www/assigned-participant/nested/a.mjs", "www/brand/icon.svg", "www/assigned-participant/image.png",
    "config/assigned-delivery-sources.json", "registry/profile.json", "tests/fixtures/raw.bin", "examples/stimuli/a.png")
  for (path in originals) put(path, paste0(path, "\r\n"))
  baseline <- brohn_qa_source_inventory(fixture)
  check("all nested source, configuration, test and asset bytes included", identical(names(baseline), sort(originals, method = "radix")))
  check("independent literal digest", identical(baseline[["config/assigned-delivery-sources.json"]],
    digest::digest(charToRaw("config/assigned-delivery-sources.json\r\n"), algo = "sha256", serialize = FALSE)))
  check("repeat inventory is deterministic", identical(baseline, brohn_qa_source_inventory(fixture)))
  for (path in c("R/assigned-domain/a.R", "R/assigned-authoring/scripts/a.py", "www/assigned-participant/nested/a.mjs", "config/assigned-delivery-sources.json")) {
    put(path, paste0(path, "\n"))
    altered <- brohn_qa_source_inventory(fixture)
    check(paste("literal-byte drift detected", path), !identical(baseline, altered) && identical(names(baseline), names(altered)))
    put(path, paste0(path, "\r\n"))
  }
  put("www/assigned-participant/new.bin", "addition")
  check("new binary asset detected", !identical(baseline, brohn_qa_source_inventory(fixture)))
  unlink(file.path(fixture, "www/assigned-participant/new.bin"))
  unlink(file.path(fixture, "R/assigned-domain/a.R"))
  check("nested removal detected", !identical(baseline, brohn_qa_source_inventory(fixture)))
  put("R/assigned-domain/a.R", "R/assigned-domain/a.R\r\n")
  for (path in c("scripts/__pycache__/a.pyc", "scripts/a.pyc", "work/source.R", "data/recording.csv", "node_modules/a.js", "renv/library/a.R", "test-results/result.json")) put(path, "not checkout source")
  check("dependency caches and research or output roots excluded", identical(baseline, brohn_qa_source_inventory(fixture)))
  unlink(file.path(fixture, "renv.lock"))
  check("missing dependency lock refuses inventory", rejects(brohn_qa_source_inventory(fixture)))
  put("renv.lock", "renv.lock\r\n")
  # Optional config/registry roots permit older source checkouts, but removing
  # one after the initial snapshot still changes the complete inventory.
  unlink(file.path(fixture, "config"), recursive = TRUE)
  check("removed optional configuration detected", !identical(baseline, brohn_qa_source_inventory(fixture)))
  cat("Passed ", length(checks), " source-inventory checks. No application or scientific qualification.\n", sep = "")
})

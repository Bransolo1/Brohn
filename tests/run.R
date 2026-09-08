source("R/study.R")
source("R/comparison.R")
source("R/presentation.R")
checks <- 0L
expect <- function(ok) {
  stopifnot(isTRUE(ok)); checks <<- checks + 1L
}
reject <- function(field, value) {
  x <- new_study(); x[field] <- list(value)
  expect(length(validate_study(x)) > 0L)
}
x <- new_study()
expect(length(validate_study(x)) == 0L)
expect(length(validate_study(new_study(include_liking = FALSE))) == 0L)
expect(identical(unserialize(serialize(x, NULL)), x))
reject("schema_version", "99.0.0")
reject("id", NA_character_)
reject("revision", 1.5)
reject("design", "independent_groups")
reject("stimulus_ids", c("same", "same"))
reject("measures", c("eye", "unknown_sensor"))
reject("measures", c("eye", "eye"))
reject("measures", "eye") # Liking question cannot silently outlive its measure.
reject("questions", list())
bad <- x; bad$questions[[1]]$option_ids[2] <- "like-1"
expect(length(validate_study(bad)) > 0L)
bad <- x; bad$questions[[1]]$codes <- list(list(1))
expect(length(validate_study(bad)) > 0L)
bad <- x; bad$analysis$contrast <- "A-B"
expect(length(validate_study(bad)) > 0L)
bad <- x; bad$analysis$status <- "qualified"
expect(length(validate_study(bad)) > 0L)
for (mode in c("sample", "preview", "pilot", "live")) {
  run <- new_session(x, paste0("run-", mode), "participant-001", mode)
  expect(identical(run$mode, mode) && identical(run$study_revision, 1L))
}
expect(inherits(try(new_session(x, "run", "p", "production"), silent = TRUE), "try-error"))
expect(all(measure_registry()$maturity == "planned"))
source("tests/records.R")
source("tests/storage.R")
source("tests/drafts.R")
source("tests/assets.R")
source("tests/aois.R")
cat(sprintf("PASS: %d contract checks\n", checks))

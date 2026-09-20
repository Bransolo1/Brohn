# Typed reusable questionnaire export; no services or scientific workers.
source("R/platform-core.R", encoding = "UTF-8")
source("R/platform-data-views.R", encoding = "UTF-8")
local({
  checks <- 0L
  check <- function(label, result) {if (!isTRUE(result)) stop("FAIL: ", label); checks <<- checks+1L; cat("PASS", label, "\n")}
  folder <- tempfile("brohn-questionnaire-csv-"); dir.create(folder)
  values <- list(0, FALSE, "0", "false", NULL, "", "=SUM(1,2)", "+original", "@original", "-original", "\tOriginal", "\u00e9\u6f22\U0001f512\nOriginal, \"quoted\" text", list(0, FALSE, NULL, "0"))
  observations <- lapply(seq_along(values), function(i) list(participant_id = "original-person", session_id = "original-visit",
    question_id = "q-original-typed", exposure_id = paste0("original-assessment-", i),
    value = values[[i]], missing_reason = if (is.null(values[[i]])) "optional_omission" else NULL,
    source = list(origin = "sample", source_row = i)))
  report <- list(analysis = list(kind = "questionnaire", observations = observations))
  original_hash <- brohn_hash(report)
  path <- file.path(folder, "questionnaire.csv"); brohn_export_report_csv(report, path)
  data <- utils::read.csv(path, stringsAsFactors = FALSE, colClasses = "character", check.names = FALSE,
    na.strings = NULL, encoding = "UTF-8")
  check("every original observation has one canonical response record", nrow(data) == length(values) && "response_record_json" %in% names(data))
  decoded <- lapply(data$response_record_json, brohn_parse)
  if (!identical(brohn_hash(decoded), brohn_hash(observations))) for (i in seq_along(decoded)) {
    if (!identical(brohn_hash(decoded[[i]]), brohn_hash(observations[[i]]))) {
      cat("DIAGNOSTIC row", i, "expected", brohn_json(observations[[i]]), "actual", brohn_json(decoded[[i]]), "\n")
      cat("EXPECTED POINTS", utf8ToInt(observations[[i]]$value), "ACTUAL POINTS", utf8ToInt(decoded[[i]]$value), "\n")
    }
  }
  check("all complete source rows reconstruct with exact canonical equality", identical(brohn_hash(decoded), brohn_hash(observations)))
  check("numeric zero and text zero remain different native values", is.numeric(decoded[[1L]]$value) && decoded[[1L]]$value == 0 && identical(decoded[[3L]]$value, "0"))
  check("logical false and literal false retain distinct native types", identical(decoded[[2L]]$value, FALSE) && identical(decoded[[4L]]$value, "false"))
  check("null omission and empty text remain distinct", "value" %in% names(decoded[[5L]]) && is.null(decoded[[5L]]$value) && identical(decoded[[6L]]$value, ""))
  check("display cells keep the existing readable scalar conventions", identical(data$value[1:6], c("0", "false", "0", "false", "", "")))
  check("formula-like display values retain their existing spreadsheet prefix", identical(data$value[7:11], paste0("'", unlist(values[7:11], use.names = FALSE))))
  check("canonical records retain original formula-like text without the display prefix", identical(lapply(decoded[7:11], `[[`, "value"), values[7:11]))
  check("Unicode, newlines, commas and quotes reconstruct exactly", identical(decoded[[12L]]$value, values[[12L]]))
  check("nested arrays preserve zero false null and text", identical(brohn_json(decoded[[13L]]$value), brohn_json(values[[13L]])))
  check("source person session assessment and row identities stay exact", all(vapply(seq_along(decoded), function(i)
    identical(decoded[[i]]$participant_id, "original-person") && identical(decoded[[i]]$session_id, "original-visit") &&
    identical(decoded[[i]]$exposure_id, paste0("original-assessment-", i)) && decoded[[i]]$source$source_row == i, logical(1))))
  check("export does not mutate the saved report", identical(brohn_hash(report), original_hash))
  non_questionnaire <- list(analysis = list(kind = "gaze", observations = list(list(participant_id = "original-person", value = 1/3))))
  path <- file.path(folder, "gaze.csv"); brohn_export_report_csv(non_questionnaire, path)
  lines <- readLines(path, warn = FALSE, encoding = "UTF-8")
  check("non-questionnaire scalar export bytes retain the prior columns and precision", identical(lines,
    c('"participant_id","value"', '"original-person","0.33333333333333331"')))
  native_label<-"\u00e9\u6f22\U0001f512\nOriginal, \"recording\""
  mixed<-list(analysis=list(kind="physiology",observations=list(list(label=native_label,unit="\u00b5S",value=0),
    list(label="=SUM(1,2)",unit="\u00b5S",value=NULL))))
  path<-file.path(folder,"physiology-unicode.csv");brohn_export_report_csv(mixed,path)
  recovered<-utils::read.csv(path,colClasses="character",encoding="UTF-8",na.strings=NULL,check.names=FALSE)
  check("physiology labels units quotes and newlines retain exact UTF-8 under C locale", identical(recovered$label[[1]],native_label)&&all(recovered$unit=="\u00b5S"))
  check("all measurement CSVs retain zero missing and formula-safe distinctions", identical(recovered$value,c("0",""))&&identical(recovered$label[[2]],"'=SUM(1,2)"))
  summaries <- list(analysis = list(kind = "questionnaire", observations = list(), features = list(list(question_id = "q-summary", response_count = 0))))
  path <- file.path(folder, "summaries.csv"); brohn_export_report_csv(summaries, path)
  check("summary fallback does not mislabel a feature as an original response", !grepl("response_record_json", readLines(path, n = 1L), fixed = TRUE))
  reserved <- report; reserved$analysis$observations[[1L]]$response_record_json <- "Original source collision"
  path <- file.path(folder, "reserved.csv")
  error <- tryCatch({brohn_export_report_csv(reserved, path); NULL}, error = conditionMessage)
  check("reserved source-field collision fails before creating an output file", !is.null(error) && grepl("reserved response_record_json", error, fixed = TRUE) && !file.exists(path))
  cat("PASS:", checks, "questionnaire CSV checks; no scientific workers.\n")
})

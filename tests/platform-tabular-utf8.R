# Original source-byte fixtures. No services, devices or scientific workers.
source("R/platform-core.R", encoding = "UTF-8")
source("R/platform-analysis.R", encoding = "UTF-8")
source("R/platform-data-views.R", encoding = "UTF-8")
local({
  count <- 0L
  check <- function(label, result) {if (!isTRUE(result)) stop("FAIL: ", label); count <<- count+1L; cat("PASS", label, "\n")}
  reject <- function(label, expr, text = NULL) {
    error <- tryCatch({force(expr); NULL}, error = conditionMessage)
    check(label, !is.null(error) && (is.null(text) || grepl(text, error, fixed = TRUE)))
  }
  folder <- tempfile("brohn-tabular-utf8-"); dir.create(folder)
  write_source <- function(name, text, bom = FALSE) {
    path <- file.path(folder, name)
    writeBin(c(if (bom) as.raw(c(0xef, 0xbb, 0xbf)) else raw(), charToRaw(enc2utf8(text))), path)
    path
  }
  title <- "\u00e9tiquette"; value <- "\u6f22\U0001f512\nOriginal, \"quoted\" text"
  quoted <- function(x) paste0('"', gsub('"', '""', x, fixed = TRUE), '"')
  for (format in c("csv", "tsv")) for (bom in c(FALSE, TRUE)) {
    sep <- if (format == "csv") "," else "\t"
    path <- write_source(paste0(format, "-", bom, ".", format),
      paste0(paste(c(quoted(title), "code", "value"), collapse = sep), "\r\n",
        paste(c(quoted(value), "001", "NA"), collapse = sep), "\r\n",
        paste(c(quoted(""), "false", "0"), collapse = sep), "\r\n"), bom)
    original <- digest::digest(file = path, algo = "sha256")
    data <- brohn_read_table(path, format)
    check(paste(format, "BOM", bom, "preserves Unicode header and multiline value"),
      identical(names(data), c(title, "code", "value")) && identical(data[[1L]], c(value, "")))
    check(paste(format, "BOM", bom, "preserves character codes and source bytes"),
      identical(data$code, c("001", "false")) && identical(data$value, c("NA", "0")) &&
      all(vapply(data, is.character, logical(1))) && identical(digest::digest(file = path, algo = "sha256"), original))
  }
  ascii <- write_source("ascii.csv", "person,condition,value\np-001,control,01.20\np-002,test,NA\n")
  check("ASCII source retains exact headers rows character codes and NA text", identical(brohn_read_table(ascii, "csv"),
    data.frame(person = c("p-001", "p-002"), condition = c("control", "test"), value = c("01.20", "NA"), stringsAsFactors = FALSE)))
  no_newline <- write_source("no-newline.csv", "id,value\noriginal,01")
  check("ordinary final row without trailing newline remains readable", identical(brohn_read_table(no_newline, "csv")$value, "01"))
  no_newline <- write_source("no-newline.tsv", "id\tvalue\noriginal\t01")
  check("ordinary TSV final row without trailing newline remains readable", identical(brohn_read_table(no_newline, "tsv")$value, "01"))
  for (format in c("csv", "tsv")) for (where in c("header", "value")) {
    sep <- if (format == "csv") "," else "\t"
    path <- file.path(folder, paste0("invalid-", where, ".", format))
    bytes <- if (where == "header") c(charToRaw("invalid"), as.raw(c(0xc3, 0x28)), charToRaw(paste0(sep, "value\noriginal", sep, "1\n"))) else
      c(charToRaw(paste0("id", sep, "value\noriginal", sep)), as.raw(c(0xc3, 0x28)), as.raw(10))
    writeBin(bytes, path)
    reject(paste(format, "malformed UTF-8", where, "fails explicitly"), brohn_read_table(path, format), "malformed UTF-8")
  }
  for (invalid in list(c(0xc0, 0xaf), c(0xed, 0xa0, 0x80), c(0xf4, 0x90, 0x80, 0x80), c(0xe2, 0x82))) {
    path <- file.path(folder, "invalid-sequence.csv")
    writeBin(c(charToRaw("id,value\noriginal,\""), as.raw(invalid), charToRaw("\"\n")), path)
    reject("overlong surrogate out-of-range or truncated UTF-8 is rejected", brohn_read_table(path, "csv"), "malformed UTF-8")
  }
  nul <- file.path(folder, "nul.csv")
  writeBin(c(charToRaw("id,value\noriginal,before"), as.raw(0), charToRaw("after\n")), nul)
  reject("embedded NUL cannot silently truncate source text", brohn_read_table(nul, "csv"))
  quotes <- write_source("unclosed.csv", "id,value\noriginal,\"unterminated\n")
  reject("unterminated quoted data cannot return a partial table", brohn_read_table(quotes, "csv"))
  duplicate <- write_source("duplicate.csv", paste0(title, ",", title, "\n1,2\n"))
  reject("duplicate Unicode headers retain the unique-name gate", brohn_read_table(duplicate, "csv"), "uniquely named")
  empty <- write_source("empty.csv", "id,value\n")
  reject("zero data rows remain unsupported", brohn_read_table(empty, "csv"), "uniquely named")
  reject("row limit still rejects an extra source row", brohn_read_table(ascii, "csv", max_rows = 1L), "uniquely named")
  wide <- write_source("wide.csv", paste0(paste0("c", 1:1025, collapse = ","), "\n", paste(rep("0", 1025), collapse = ","), "\n"))
  reject("column limit remains1024 without unbounded allocation for a tiny wide file", brohn_read_table(wide, "csv"), "uniquely named")
  reject("unsupported tabular format still fails", brohn_read_table(ascii, "json"), "tabular source")
  values <- list(0, FALSE, "0", "false", NULL, "", "=SUM(1,2)", value, list(0, FALSE, NULL, "0"))
  original <- lapply(seq_along(values), function(i) list(participant_id = "original-person", session_id = "original-visit",
    question_id = "q-original", exposure_id = paste0("assessment-", i), value = values[[i]], origin = "sample"))
  path <- file.path(folder, "questionnaire-export.csv")
  brohn_export_report_csv(list(analysis = list(kind = "questionnaire", observations = original)), path)
  imported <- brohn_read_table(path, "csv")
  check("actual questionnaire CSV imports every full typed source companion", identical(brohn_hash(lapply(imported$response_record_json, brohn_parse)), brohn_hash(original)))
  check("actual questionnaire CSV keeps Unicode display and spreadsheet-safe formula text", identical(imported$value[[8L]], value) && identical(imported$value[[7L]], "'=SUM(1,2)"))
  cat("PASS:", count, "tabular UTF-8 checks; no scientific workers.\n")
})

args <- commandArgs(TRUE)
stopifnot(length(args) == 2L, !dir.exists(args[[2L]]))
source_path <- normalizePath(args[[1L]], winslash = "/", mustWork = TRUE)
dir.create(args[[2L]], recursive = TRUE)
out <- normalizePath(args[[2L]], winslash = "/", mustWork = TRUE)
invisible(asNamespace("shiny")); invisible(asNamespace("jsonlite")); invisible(asNamespace("digest"))
registry <- get(".__S3MethodsTable__.", asNamespace("base"))
before_names <- ls(registry, all.names = TRUE)
before_methods <- mget(before_names, registry, inherits = FALSE)
before_options <- options()
before_dispatch <- get("HandlerManager", asNamespace("shiny"))$public_methods$.httpServer
before_session <- get("ShinySession", asNamespace("shiny"))$public_methods$handleRequest
before_generic <- get("$<-", baseenv()); before_aslist <- base::as.list.default
private <- new.env(parent = .GlobalEnv)
sys.source(source_path, envir = private)
checks <- character()
check <- function(label, value) {stopifnot(isTRUE(value)); checks <<- c(checks, label)}
refuse <- function(label, expr) check(label, tryCatch({force(expr); FALSE}, brohn_http_response_error = function(e) TRUE))
response <- function(content, status = 200L, headers = list(), type = "application/octet-stream") {
  structure(list(status = status, content_type = type, content = content, headers = headers,
    retained_metadata = list(identity = "source-untouched")), class = "httpResponse")
}
finalize <- private$brohn_http_identity_response
check("No global application setter binding", !exists("$<-.brohn_http_identity_headers", .GlobalEnv, inherits = FALSE))
check("Exactly one dedicated S3 registration", identical(setdiff(ls(registry, all.names = TRUE), before_names), "$<-.brohn_http_identity_headers"))
check("Existing S3 entries are unchanged", identical(before_methods, mget(before_names, registry, inherits = FALSE)))
check("Registered method is exact private source function", identical(get("$<-.brohn_http_identity_headers", registry), private$`$<-.brohn_http_identity_headers`))
check("Options, base generic, and as.list unchanged", identical(options(), before_options) && identical(get("$<-", baseenv()), before_generic) && identical(base::as.list.default, before_aslist))
check("Shiny dispatcher and session methods unchanged", identical(before_dispatch, get("HandlerManager", asNamespace("shiny"))$public_methods$.httpServer) && identical(before_session, get("ShinySession", asNamespace("shiny"))$public_methods$handleRequest))
headers <- list("Cache-Control" = "no-store", "X-Content-Type-Options" = "nosniff", "Content-Disposition" = 'attachment; filename="saved.csv"', "X-Saved-Ref" = "unchanged")
utf8 <- enc2utf8(paste0("<svg><text>", intToUtf8(c(0x00E9, 0x2014, 0x1F9E0)), "</text></svg>"))
fixtures <- list(empty_text = "", ascii = "saved observations", utf8 = utf8, empty_raw = raw(0), binary = as.raw(0:255))
for (name in names(fixtures)) {
  input <- response(fixtures[[name]], 404L, headers)
  frozen <- serialize(input, NULL)
  value <- finalize(input)
  bytes <- if (is.raw(fixtures[[name]])) length(fixtures[[name]]) else nchar(fixtures[[name]], type = "bytes")
  check(paste(name, "status, content, type and metadata preserved"), identical(value[names(value) != "headers"], input[names(input) != "headers"]))
  check(paste(name, "unrelated headers preserved"), identical(unclass(value$headers)[names(headers)], headers))
  check(paste(name, "exact decimal length and identity encoding"), identical(value$headers[["Content-Length"]], as.character(bytes)) && identical(value$headers[["Content-Encoding"]], "identity"))
  check(paste(name, "input unchanged and finalizer idempotent"), identical(serialize(input, NULL), frozen) && identical(finalize(value), value))
}
for (n in c(0L, 1L, 100000L, 1000000L)) {
  path <- file.path(out, paste0("source-", n, ".bin"))
  writeBin(rep(as.raw(0x78), n), path)
  content <- list(owned = FALSE, file = path)
  value <- finalize(response(content, headers = headers))
  h <- as.list(value$headers)
  h$`Content-Type` <- value$content_type
  h$`Content-Length` <- file.info(path)$size
  check(paste(n, "file is preserved without ownership transfer"), identical(value$content, content) && file.exists(path) && identical(unname(file.info(path)$size), as.numeric(n)))
  check(paste(n, "Shiny-style numeric overwrite stays decimal in private load"), identical(h[["Content-Length"]], format(n, scientific = FALSE, trim = TRUE)))
}
for (n in list(0, 100000, 1000000, 2^53 - 1)) {
  h <- as.list(finalize(response(raw(0)))$headers)
  h$`Content-Length` <- n
  check(paste("Exact bounded length", format(n, scientific = FALSE)), identical(h[["Content-Length"]], format(n, scientific = FALSE, trim = TRUE, digits = 22L)))
}
for (bad in list(-1, 0.5, NA_real_, Inf, 2^53, "1e+05", "01", "9007199254740993", logical(0), TRUE, NULL)) {
  refuse("Invalid overwritten byte count refused", {h <- as.list(finalize(response(raw(0)))$headers); h$`Content-Length` <- bad})
}
good <- finalize(response("abc", headers = list("content-length" = 3, "content-encoding" = "Identity")))
check("Existing valid length/identity canonicalized", identical(names(good$headers), c("Content-Encoding", "Content-Length")) && identical(good$headers[["Content-Length"]], "3"))
good <- finalize(response("abc", headers = list("Content-Type" = "application/octet-stream")))
check("Matching dispatcher Content-Type retained", identical(good$headers[["Content-Type"]], "application/octet-stream"))
h <- as.list(finalize(response("abc"))$headers); h$`content-length` <- 3
check("Mixed-case overwrite does not duplicate Content-Length", identical(sum(tolower(names(h)) == "content-length"), 1L) && identical(h[["Content-Length"]], "3"))
for (status in c(200L, 201L, 301L, 400L, 403L, 404L, 500L, 599L)) check(paste("Body-capable status", status, "preserved"), identical(finalize(response("x", status))$status, status))
for (status in list(100L, 199L, 204L, 205L, 206L, 304L, 600L, 200.5, NA, "200")) refuse("Unsupported status refused", finalize(response("x", status)))
for (h in list(list("Content-Encoding" = "gzip"), list("Content-Encoding" = "br"), list("Transfer-Encoding" = "chunked"), list("Content-Range" = "bytes 0-2/9"), list("Trailer" = "Digest"), list("Content-Length" = "2"), list("Content-Length" = 4), list("Content-Length" = "3", "content-length" = "3"), list("Bad\r\nField" = "x"), list("X-Test" = "line\r\ninjected"), list("X-Test" = c("a", "b")), list("Content-Type" = "text/plain"), list("content-type" = "application/octet-stream"), setNames(list("x"), ""))) refuse("Malformed, contradictory or unsupported headers refused", finalize(response("abc", headers = h)))
for (content in list(NULL, c("a", "b"), NA_character_, 123, list(file = file.path(out, "missing"), owned = FALSE), list(file = out, owned = FALSE), list(file = file.path(out, "source-1.bin"), owned = TRUE), list(file = file.path(out, "source-1.bin"), owned = FALSE, offset = 0), structure("x", class = "other"))) refuse("Unsupported content refused", finalize(response(content)))
latin1 <- rawToChar(as.raw(0xE9)); Encoding(latin1) <- "latin1"
invalid <- rawToChar(as.raw(0xFF)); Encoding(invalid) <- "UTF-8"
refuse("Latin1 conversion refused without mutating content", finalize(response(latin1)))
refuse("Malformed UTF-8 refused", finalize(response(invalid)))
unknown <- rawToChar(charToRaw(utf8)); Encoding(unknown) <- "unknown"
if (identical(charToRaw(unknown), charToRaw(enc2utf8(unknown)))) {
  value <- finalize(response(unknown))
  check("Native unknown UTF-8 retained with exact byte length when conversion is stable", identical(value$content, unknown) && identical(value$headers[["Content-Length"]], as.character(length(charToRaw(unknown)))))
} else refuse("Unknown encoding refused when native conversion changes bytes", finalize(response(unknown)))
unknown_invalid <- rawToChar(as.raw(0xFF)); Encoding(unknown_invalid) <- "unknown"
refuse("Unknown malformed UTF-8 refused", finalize(response(unknown_invalid)))
byte_text <- rawToChar(charToRaw(utf8)); Encoding(byte_text) <- "bytes"
refuse("Byte-marked text refused with typed error", finalize(response(byte_text)))
refuse("Header control character refused", finalize(response("x", headers = list("X-Test" = paste0("x", intToUtf8(1L))))))
refuse("Media type control character refused", finalize(response("x", type = paste0("text/plain", intToUtf8(127L)))))
for (owned in list(0, NA, "FALSE")) refuse("File ownership requires exact logical FALSE", finalize(response(list(file = file.path(out, "source-1.bin"), owned = owned))))
refuse("Non-httpResponse refused", finalize(list(status = 200, content_type = "text/plain", content = "x")))
refuse("Duplicate response fields refused", finalize(structure(c(unclass(response("x")), list(status = 200)), class = "httpResponse")))
check("Source declarations remain private", !exists("brohn_http_identity_response", .GlobalEnv, inherits = FALSE))
record <- list(schema = "brohn-http-response-unit/0.1", passed = TRUE, checks = checks,
  source_sha256 = digest::digest(file = source_path, algo = "sha256"),
  runtime = list(R = R.version.string, shiny = as.character(packageVersion("shiny")), httpuv = as.character(packageVersion("httpuv"))),
  scope = "Deterministic synthetic representations, strict refusals and private-source registry scope; no application callsite or authority qualification.")
writeLines(jsonlite::toJSON(record, auto_unbox = TRUE, pretty = TRUE), file.path(out, "results.json"), useBytes = TRUE)
cat(length(checks), "HTTP response unit checks passed\n")

args <- commandArgs(TRUE)
stopifnot(length(args) == 3L)
out <- normalizePath(args[[1L]], winslash = "/", mustWork = TRUE)
port <- as.integer(args[[2L]])
private <- new.env(parent = globalenv())
sys.source(args[[3L]], envir = private)
stopifnot(!exists("$<-.brohn_http_identity_headers", globalenv(), inherits = FALSE))
text <- enc2utf8(paste0("Saved ", intToUtf8(c(0x00E9, 0x2014, 0x1F9E0)), " findings."))
unknown <- rawToChar(charToRaw(text)); Encoding(unknown) <- "unknown"
fixtures <- list(
  file_zero = list(status = 200L, type = "application/octet-stream", bytes = raw(0), mode = "file"),
  file_power = list(status = 200L, type = "application/octet-stream", bytes = rep(as.raw(0x78), 100000L), mode = "file"),
  file_million = list(status = 200L, type = "application/octet-stream", bytes = rep(as.raw(0x79), 1000000L), mode = "file"),
  raw_binary = list(status = 200L, type = "application/octet-stream", bytes = rep(as.raw(0:255), 32L), mode = "raw"),
  raw_zero = list(status = 200L, type = "application/octet-stream", bytes = raw(0), mode = "raw"),
  svg_utf8 = list(status = 200L, type = "image/svg+xml", text = paste0('<svg xmlns="http://www.w3.org/2000/svg"><text>', text, '</text></svg>'), mode = "text"),
  text_native_ascii = list(status = 200L, type = "text/plain; charset=UTF-8", text = "Saved ASCII findings.", mode = "text"),
  text_zero = list(status = 200L, type = "text/plain; charset=UTF-8", text = "", mode = "text"),
  refused_403 = list(status = 403L, type = "text/plain; charset=UTF-8", text = paste("Access ended.", text), mode = "text"),
  refused_404 = list(status = 404L, type = "text/plain; charset=UTF-8", text = paste("Saved evidence unavailable.", text), mode = "text"))
for (name in names(fixtures)) {
  fixture <- fixtures[[name]]
  if (fixture$mode == "text") fixture$bytes <- charToRaw(fixture$text)
  fixture$path <- file.path(out, paste0(name, ".bin"))
  writeBin(fixture$bytes, fixture$path)
  fixtures[[name]] <- fixture
}
manifest <- lapply(names(fixtures), function(name) {
  x <- fixtures[[name]]
  list(name = name, status = x$status, type = x$type, mode = x$mode,
    file = basename(x$path), bytes = length(x$bytes), sha256 = digest::digest(x$bytes, algo = "sha256", serialize = FALSE))
})
writeLines(jsonlite::toJSON(list(fixtures = manifest,
  encoding = list(native_unknown_utf8_byte_stable = identical(charToRaw(unknown), charToRaw(enc2utf8(unknown))),
    note = "Marked UTF-8 and unknown ASCII are exercised on wire. Non-byte-preserving native conversion is refused in the unit suite."),
  runtime = list(R = R.version.string,
  shiny = as.character(packageVersion("shiny")), httpuv = as.character(packageVersion("httpuv")))),
  auto_unbox = TRUE, pretty = TRUE), file.path(out, "fixtures.json"), useBytes = TRUE)
ui <- shiny::fluidPage(shiny::uiOutput("links"))
server <- function(input, output, session) {
  links <- lapply(names(fixtures), function(name) {
    fixture <- fixtures[[name]]
    uri <- session$registerDataObj(name, fixture, function(data, req) {
      content <- switch(data$mode, file = list(file = data$path, owned = FALSE), raw = data$bytes, text = data$text)
      cat(name, req$REQUEST_METHOD, "\n")
      input <- structure(list(status = data$status, content_type = data$type, content = content,
        headers = list("Cache-Control" = "no-store", "X-Content-Type-Options" = "nosniff",
          "Content-Disposition" = paste0('attachment; filename="', name, '.bin"'), "X-Saved-Ref" = name)), class = "httpResponse")
      private$brohn_http_identity_response(input)
    })
    shiny::tags$a(name, id = name, href = uri)
  })
  output$links <- shiny::renderUI(shiny::tagList(links))
}
later::later(function() quit(save = "no", status = 0), 60)
shiny::runApp(list(ui = ui, server = server), host = "127.0.0.1", port = port, launch.browser = FALSE)

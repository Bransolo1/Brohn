# Optional, declarative participant opening content. No timed step or run is
# created by welcome preparation. Existing designs remain byte-semantically intact.
brohn_new_welcome <- function(title = "Welcome to this study") list(schema = "brohn-welcome/1.0",
  title = title, text = "Thank you for considering this study. Read the information on the next page before deciding whether to take part.",
  asset = NULL, image_alt = "")

brohn_validate_welcome <- function(welcome) {
  brohn_fields(welcome, c("schema", "title", "text", "asset", "image_alt"), label = "Welcome page")
  brohn_require(identical(welcome$schema, "brohn-welcome/1.0"), "This welcome-page version is not supported.")
  brohn_require(brohn_text(welcome$title, 240) && brohn_text(welcome$text, 20000, TRUE), "Give the welcome page a short title and supported text.")
  brohn_require(brohn_text(welcome$image_alt, 2000, TRUE), "Keep the welcome image description short.")
  if (!is.null(welcome$asset)) {
    a <- welcome$asset
    brohn_fields(a, c("hash", "size", "media_type", "filename", "width", "height"), label = "Welcome image")
    brohn_require(brohn_text(a$hash, 64) && grepl("^[a-f0-9]{64}$", a$hash) &&
      brohn_number(a$size, 33, 5*1024^2, TRUE) && identical(a$media_type, "image/png"), "Attach a supported PNG welcome image of up to 5 MiB.")
    brohn_require(brohn_text(a$filename, 240) && !grepl("[/\\\\:]", a$filename) && !a$filename %in% c(".", ".."), "Use a plain display filename for the welcome image.")
    brohn_require(brohn_number(a$width, 1, 4096, TRUE) && brohn_number(a$height, 1, 4096, TRUE) && a$width*a$height <= 8000000,
      "Welcome images support up to 4096 pixels per side and 8 million pixels in total.")
    brohn_require(brohn_text(welcome$image_alt, 2000), "Describe the welcome image for participants who cannot see it.")
  }
  invisible(welcome)
}

brohn_attach_welcome_png <- function(store, design, path, filename = basename(path), image_alt) {
  brohn_validate_design(design)
  brohn_require(!is.null(design$welcome), "Enable the welcome page before attaching its image.")
  brohn_require(brohn_text(image_alt, 2000), "Describe the welcome image before attaching it.")
  filename <- basename(filename)
  brohn_require(brohn_text(filename, 240) && !grepl("[/\\\\:]", filename), "Choose a PNG with a plain filename.")
  decoded <- new_png_asset(path, "welcome-image")
  bytes <- jsonlite::base64_dec(decoded$data_base64)
  asset <- brohn_store_object(store, bytes = bytes, media_type = "image/png")
  design$welcome$asset <- c(asset, list(filename = filename, width = decoded$width, height = decoded$height))
  design$welcome$image_alt <- image_alt
  brohn_validate_design(design); design
}

brohn_capture_welcome <- function(input, design) {
  # The caller checks the current Plan form identity before reading any inputs.
  if (is.null(input$welcome_enabled)) return(design)
  if (!isTRUE(input$welcome_enabled)) {design$welcome <- NULL; return(design)}
  welcome <- brohn_default(design$welcome, brohn_new_welcome())
  for (field in c("title", "text", "image_alt")) {
    value <- input[[paste0("welcome_", field)]]
    if (!is.null(value)) welcome[[field]] <- value
  }
  brohn_validate_welcome(welcome); design$welcome <- welcome; design
}

# Exact-byte original PNG and real catalog / release / package roundtrips.
source("R/platform-load.R", encoding = "UTF-8"); brohn_load(ui = TRUE)
local({
  checks <- 0L; check <- function(ok, label) {if (!isTRUE(ok)) stop(label, call. = FALSE); checks <<- checks+1L; cat("PASS", label, "\n")}
  rejects <- function(expr) inherits(try(force(expr), silent = TRUE), "try-error")
  root <- tempfile("brohn-welcome-"); dir.create(root)
  store <- brohn_open_store(file.path(root, "source")); brohn_initialise_library(store)
  target <- brohn_open_store(file.path(root, "target")); brohn_initialise_library(target)
  on.exit({brohn_close_store(store); brohn_close_store(target)}, add = TRUE)
  source_image <- file.path(root, "original-geometry.png"); replacement_image <- file.path(root, "replacement.png")
  png::writePNG(array(c(1,0,0,1,0,1,0,1,0,0,1,1), c(2,2,3)), source_image)
  png::writePNG(array(c(0,1,0,1,1,0,1,0,1,0,1,0), c(2,2,3)), replacement_image)
  design <- brohn_new_design("Original welcome fixture", "survey")
  design$questions <- list(brohn_question("Independent saved response", "text", "end", "welcome-question"))
  old_protocol <- brohn_compile(design, 1L); old_hash <- brohn_hash(design)
  old <- brohn_put_entity(store, "study", design$id, design)
  legacy_release <- brohn_publish(store, old$id, "sample")
  design$welcome <- brohn_new_welcome("Welcome <script>literal</script>")
  design$welcome$text <- "Original introduction.\nSecond line remains distinct."
  design <- brohn_attach_welcome_png(store, design, source_image, "original-geometry.png", "Four original coloured squares")
  study <- brohn_save_study(store, design, old$revision)
  hash <- design$welcome$asset$hash
  check(identical(hash, digest::digest(file = source_image, algo = "sha256")) && identical(readBin(brohn_object_path(store, hash), "raw", 1024), readBin(source_image, "raw", 1024)), "Welcome upload retains exact original PNG bytes and content identity")
  check(identical(brohn_hash(brohn_compile(study$body, 1L)$timeline), brohn_hash(old_protocol$timeline)), "Optional pre-consent welcome does not change timed or response steps")
  check(identical(brohn_hash(brohn_study(store, old$id, old$revision)$body), old_hash), "Enabling a welcome leaves the old design revision unchanged")
  app <- brohn_delivery_app(store)
  get <- function(path) {
    response <- app$call(list(PATH_INFO = path, REQUEST_METHOD = "GET", HTTP_HOST = "127.0.0.1:3840", HTTP_ORIGIN = "http://127.0.0.1:3840"))
    if (is.character(response$body) && grepl("application/json", response$headers[["Content-Type"]])) response$value <- brohn_parse(response$body)
    response
  }
  legacy_entry <- get(paste0("/api/entry/", legacy_release$token))
  check(legacy_entry$status == 200L && !"welcome" %in% names(legacy_entry$value), "Existing release without welcome retains the original entry contract")
  release <- brohn_publish(store, study$id, "sample")
  entry <- get(paste0("/api/entry/", release$token))$value
  check(identical(entry$welcome, study$body$welcome), "Participant entry exposes exact frozen welcome content without modifying its manifest")
  asset <- get(entry$welcome_image_url)
  check(asset$status == 200L && identical(digest::digest(file = asset$body$file, algo = "sha256"), hash), "Release capability delivers its exact welcome image")
  check(get(paste0("/api/assets/", legacy_release$token, "/", hash))$status == 404L, "A release cannot retrieve an image from a different design revision")
  check(get(paste0("/api/assets/", release$token, "/", strrep("f",64)))$status == 404L, "An arbitrary object hash is not an image download capability")
  replacement <- brohn_attach_welcome_png(store, study$body, replacement_image, "replacement.png", "Replacement original squares")
  study <- brohn_save_study(store, replacement, study$revision)
  check(identical(get(paste0("/api/entry/", release$token))$value$welcome$asset$hash, hash) &&
    get(paste0("/api/assets/", release$token, "/", replacement$welcome$asset$hash))$status == 404L, "Replacing draft artwork leaves the old released page and asset access pinned")
  copied <- brohn_clone_study(store, study$id)
  template <- brohn_save_template(store, study$id); reused <- brohn_use_template(store, template$id)
  check(identical(copied$body$welcome, study$body$welcome) && identical(reused$body$welcome, study$body$welcome) && copied$id != study$id && reused$id != study$id,
    "Clone and template reuse retain exact welcome content in distinct design identities")
  package <- brohn_export_design(store, study$id, file.path(root, "welcome.brohn-study.zip"))
  imported <- brohn_import_design(target, package)
  check(identical(imported$body$welcome, study$body$welcome) && identical(digest::digest(file = brohn_object_path(target, study$body$welcome$asset$hash), algo = "sha256"), study$body$welcome$asset$hash),
    "Portable design roundtrip retains welcome wording, alt text and exact PNG bytes")
  check(length(brohn_runs(store)) == 0 && length(brohn_runs(target)) == 0, "Preparing, previewing and reusing welcome content allocates no participant sessions")
  bad <- study$body; bad$welcome$image_alt <- ""
  check(rejects(brohn_validate_design(bad)), "Attached welcome image requires useful nonempty alternative text")
  bad <- study$body; bad$welcome$asset$media_type <- "image/svg+xml"
  check(rejects(brohn_validate_design(bad)), "Executable or unsupported image formats are rejected")
  bad <- study$body; bad$welcome$asset$filename <- "C:/private/file.png"
  check(rejects(brohn_validate_design(bad)), "Welcome image metadata cannot retain a private absolute path")
  corrupt <- file.path(root, "corrupt.png"); writeBin(charToRaw("not an image"), corrupt)
  check(rejects(brohn_attach_welcome_png(store, study$body, corrupt, "corrupt.png", "A claimed image")), "Invalid image bytes fail full PNG validation")
  doc <- .brohn_welcome_preview_document(store, study)
  check(!grepl("<script>literal</script>", doc, fixed = TRUE) && grepl("\\u003cscript\\u003e", doc, fixed = TRUE), "Embedded preview data escapes HTML delimiters while retaining literal authored text")
  check(grepl("participant/welcome.js", doc, fixed = TRUE) && !grepl("runner.js", doc, fixed = TRUE) && !grepl(release$token, doc, fixed = TRUE), "Sandbox preview uses the shared renderer without the session runner or release credential")
  # Existing design fields remain untouched when the optional authoring control
  # is absent or explicitly disabled.
  unchanged <- brohn_capture_welcome(list(), old$body)
  disabled <- brohn_capture_welcome(list(welcome_enabled = FALSE), study$body)
  check(identical(unchanged, old$body) && !"welcome" %in% names(disabled), "Absent or disabled welcome state preserves legacy design semantics")
  cat("PASS", checks, "welcome domain and source checks\n")
})

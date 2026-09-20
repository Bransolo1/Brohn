# Exact saved materials; authoring does not change a registered task procedure.
brohn_material_target <- function(design, kind, material_id, task_id = NULL) {
  brohn_require(kind %in% c("stimulus", "exemplar") && brohn_valid_id(material_id), "Choose an existing study material.")
  if (kind == "stimulus") {
    i <- match(material_id, brohn_ids(design$stimuli)); brohn_require(!is.na(i), "This study material no longer exists.")
    return(list(kind = kind, index = i, material = design$stimuli[[i]], title = design$stimuli[[i]]$title, stage = "Plan"))
  }
  brohn_require(brohn_valid_id(task_id), "Choose the task that owns this exemplar.")
  i <- match(task_id, brohn_ids(design$blocks)); brohn_require(!is.na(i), "This task no longer exists.")
  task <- design$blocks[[i]]
  brohn_require(brohn_task_profile(task$profile)$kind %in% c("iat", "biat", "aat"), "This reaction-time procedure uses its own fixed cues.")
  j <- match(material_id, brohn_ids(task$materials)); brohn_require(!is.na(j), "This task exemplar no longer exists.")
  list(kind = kind, task_index = i, index = j, material = task$materials[[j]], title = paste(task$title, "- exemplar", j), stage = "Tasks")
}

.brohn_material_set <- function(design, target, material) {
  if (target$kind == "stimulus") design$stimuli[[target$index]] <- material else design$blocks[[target$task_index]]$materials[[target$index]] <- material
  brohn_validate_design(design); design
}

brohn_material_description <- function(material, kind) {
  if ("image_alt" %in% names(material)) material$image_alt else if (kind == "stimulus") "Study image" else if (nzchar(material$content)) material$content else "Task image"
}

brohn_material_attach_png <- function(store, design, kind, material_id, task_id = NULL, path, filename = basename(path), image_alt) {
  brohn_validate_design(design); target <- brohn_material_target(design, kind, material_id, task_id)
  brohn_require(brohn_text(image_alt, 2000), "Describe the selected image for participants who cannot see it.")
  filename <- basename(filename); brohn_require(brohn_text(filename, 240) && !grepl("[/\\\\:]", filename), "Choose an image with a plain filename.")
  source <- new_png_asset(path, material_id); bytes <- jsonlite::base64_dec(source$data_base64)
  asset <- c(brohn_store_object(store, bytes = bytes, media_type = "image/png"), list(filename = filename, width = source$width, height = source$height))
  material <- target$material
  if (kind == "stimulus" && (is.null(material$asset) || !identical(material$asset$hash, asset$hash))) material$aois <- list()
  material$asset <- asset; material$type <- "image"; material$image_alt <- image_alt
  .brohn_material_set(design, target, material)
}

brohn_material_describe <- function(design, kind, material_id, task_id = NULL, image_alt) {
  brohn_validate_design(design); target <- brohn_material_target(design, kind, material_id, task_id); material <- target$material
  brohn_require(material$type == "image" && !is.null(material$asset), "Attach an image before saving its description.")
  brohn_require(brohn_text(image_alt, 2000), "Describe the image for participants who cannot see it.")
  material$image_alt <- image_alt; .brohn_material_set(design, target, material)
}

brohn_material_use_text <- function(design, kind, material_id, task_id = NULL, text) {
  brohn_validate_design(design); target <- brohn_material_target(design, kind, material_id, task_id); material <- target$material
  brohn_require(brohn_text(text, if (kind == "stimulus") 20000 else 4000, kind == "stimulus"), "Write the participant text before removing this task image.")
  material$type <- "text"; material$content <- text; material["asset"] <- list(NULL); material$image_alt <- NULL
  if (kind == "stimulus") material$aois <- list()
  .brohn_material_set(design, target, material)
}

brohn_material_preview_type <- function(material) {
  if (identical(material$type, "text")) return("text")
  brohn_require(!is.null(material$asset), "This material has no attached media. Attach an image or use text.")
  type <- material$asset$media_type
  brohn_require(.brohn_delivery_media_allowed(type), "This retained media type has no supported preview. Use a supported material before releasing the study.")
  native <- if (startsWith(type, "image/")) "image" else if (startsWith(type, "audio/")) "audio" else "video"
  brohn_require(identical(material$type, native), "The saved material kind and media type disagree. Reopen and replace this material.")
  native
}

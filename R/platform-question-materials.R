# Optional question illustrations. Pure metadata validation is available to all
# compile/replay workers; byte verification is used only at file/store boundaries.
brohn_validate_illustration <- function(value) {
  brohn_fields(value, c("asset", "image_alt"), label = "Study illustration")
  a <- value$asset
  brohn_fields(a, c("hash", "size", "media_type", "filename", "width", "height"), label = "Illustration image")
  brohn_require(brohn_text(a$hash,64) && grepl("^[a-f0-9]{64}$",a$hash) && identical(a$media_type,"image/png") &&
    brohn_number(a$size,33,5*1024^2,TRUE), "Attach a supported PNG illustration of up to 5 MiB.")
  brohn_require(brohn_text(a$filename,240) && !grepl("[/\\\\:]",a$filename) && !a$filename %in% c(".",".."), "Use a plain illustration filename.")
  brohn_require(brohn_number(a$width,1,4096,TRUE) && brohn_number(a$height,1,4096,TRUE) && a$width*a$height<=8000000,
    "Illustrations support up to 4096 pixels per side and 8 million pixels per image.")
  brohn_require(brohn_text(value$image_alt,2000), "Describe the illustration for participants who cannot see it.")
  invisible(value)
}
brohn_question_illustrations <- function(design) {
  result <- list()
  for(q in design$questions) if("illustration" %in% names(q)) {
    brohn_validate_illustration(q$illustration)
    result[[length(result)+1L]] <- c(list(question_id=q$id,type="image"),q$illustration)
  }
  result
}
brohn_maxdiff_illustrations <- function(design) {
  result<-list()
  for(exercise in design$maxdiff)for(item in exercise$items)if("illustration" %in% names(item)) {
    brohn_validate_illustration(item$illustration)
    result[[length(result)+1L]]<-c(list(exercise_id=exercise$id,item_id=item$id,type="image"),item$illustration)
  }
  result
}
brohn_study_illustrations <- function(design) c(brohn_question_illustrations(design),brohn_maxdiff_illustrations(design))
brohn_illustration_profile <- function(design) {
  images <- brohn_study_illustrations(design); unique <- list(); pixels <- 0
  for(image in images) {
    a <- image$asset; previous <- unique[[a$hash]]
    if(!is.null(previous)) brohn_require(identical(brohn_json(previous[c("size","media_type","width","height")]),brohn_json(a[c("size","media_type","width","height")])), "Shared illustration metadata disagrees.")
    else {unique[[a$hash]]<-a;pixels<-pixels+a$width*a$height}
  }
  all <- unique
  for(s in design$stimuli) if(!is.null(s$asset)) {
    a<-s$asset;previous<-all[[a$hash]]
    if(!is.null(previous))brohn_require(identical(previous$media_type,a$media_type)&&previous$size==a$size,"Shared study media metadata disagrees.")
    else all[[a$hash]]<-a
  }
  bytes<-sum(vapply(all,function(a)as.numeric(a$size),numeric(1)))
  if(length(images))brohn_require(pixels<=64000000 && bytes<=512*1024^2,
    "Use smaller images. Question and choice illustrations share up to 64 million unique pixels; their bytes and passive media together must fit 512 MiB.")
  list(assets=unique,pixels=pixels,media_bytes=bytes)
}
brohn_verify_illustration_file <- function(asset,path) {
  decoded<-new_png_asset(path,"question-illustration")
  brohn_require(identical(decoded$sha256,asset$hash) && file.info(path)$size==asset$size &&
    decoded$width==asset$width && decoded$height==asset$height,"The illustration bytes or dimensions differ from their saved source.")
  invisible(TRUE)
}
brohn_verify_study_illustrations <- function(store,design) {
  profile<-brohn_illustration_profile(design)
  for(a in profile$assets)brohn_verify_illustration_file(a,brohn_object_path(store,a$hash,verify=TRUE))
  invisible(profile)
}
brohn_verify_question_illustrations <- brohn_verify_study_illustrations
brohn_question_material <- function(question) {
  list(id=question$id,type=if(is.null(question$illustration))"text" else "image",content=question$prompt,
    asset=question$illustration$asset,image_alt=question$illustration$image_alt)
}
brohn_remove_question_illustration <- function(design,id) {
  brohn_validate_design(design);i<-match(id,brohn_ids(design$questions));brohn_require(!is.na(i),"Choose an existing question.")
  design$questions[[i]]$illustration<-NULL;brohn_validate_design(design);design
}
brohn_maxdiff_material <- function(item) list(id=item$id,type=if(is.null(item$illustration))"text" else "image",content=item$label,
  asset=item$illustration$asset,image_alt=item$illustration$image_alt)
brohn_remove_maxdiff_illustration <- function(design,exercise_id,item_id) {
  brohn_validate_design(design);i<-match(exercise_id,brohn_ids(design$maxdiff));brohn_require(!is.na(i),"Choose an existing best-worst exercise.")
  j<-match(item_id,brohn_ids(design$maxdiff[[i]]$items));brohn_require(!is.na(j),"Choose an existing best-worst item.")
  design$maxdiff[[i]]$items[[j]]$illustration<-NULL;brohn_validate_design(design);design
}

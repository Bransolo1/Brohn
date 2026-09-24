# One text exemplar per line; validate the whole edited task after all categories
# are captured so a deliberate move between categories can be saved atomically.
brohn_gnat_update_words <- function(task, category_id, text) {
  brohn_require(identical(task$profile,"gnat-brohn-single-target/1.0") &&
    category_id %in% brohn_ids(task$categories),"Choose a category in the current GNAT task.")
  indices <- which(vapply(task$materials,function(m)identical(m$category_id,category_id),logical(1)))
  brohn_require(length(indices)>=2L && brohn_text(text,64L*4001L,TRUE),"Enter 2 to 64 text exemplars, one per line.")
  previous <- task$materials[indices]
  # Merely reopening or saving another field must not reparse original material.
  if(identical(text,paste(vapply(previous,`[[`,character(1),"content"),collapse="\n")))return(task)
  words <- strsplit(gsub("\r\n","\n",text,fixed=TRUE),"\n",fixed=TRUE)[[1L]]
  brohn_require(length(words)>=2L && length(words)<=64L && all(vapply(words,brohn_text,logical(1),max=4000)),
    "Enter 2 to 64 nonempty exemplars, one per line. Remove empty lines within the list.")
  replacement <- lapply(seq_along(words),function(i)list(id=if(i<=length(previous))previous[[i]]$id else brohn_id("material"),
    category_id=category_id,type="text",content=words[[i]],asset=NULL))
  materials <- list()
  for(i in seq_along(task$materials)) {
    if(i==indices[[1L]])materials<-c(materials,replacement)
    if(!i %in% indices)materials<-c(materials,list(task$materials[[i]]))
  }
  task$materials<-materials;task
}

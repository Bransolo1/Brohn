# Search the catalog before applying the page bound, including older studies.
brohn_search_library <- function(store, kind, query = "", project_id = NULL, archived = NULL,
                                 modality = NULL, limit = 40L, offset = 0L) {
  .brohn_store_ready(store)
  brohn_require(kind %in% c("study", "dataset", "template"), "Choose a searchable research library.")
  brohn_require(brohn_text(query, 500, TRUE) && brohn_number(limit, 1, 100, TRUE) && brohn_number(offset, 0, 1e8, TRUE), "Invalid library query or page.")
  where <- "e.kind=?"; params <- list(kind)
  if (!is.null(project_id)) {brohn_require(brohn_valid_id(project_id), "Choose an existing project."); where <- paste(where, "AND e.project_id=?"); params <- c(params, list(project_id))}
  if (nzchar(trimws(query))) {
    where <- paste(where, "AND instr(lower(coalesce(json_extract(v.body_json,'$.title'),'') || ' ' || coalesce(json_extract(v.body_json,'$.description'),'') || ' ' || coalesce(json_extract(v.body_json,'$.tags'),'') || ' ' || coalesce(json_extract(v.body_json,'$.source.filename'),'')),lower(?))>0")
    params <- c(params, list(trimws(query)))
  }
  if (!is.null(archived)) {
    brohn_require(kind == "study" && is.logical(archived) && length(archived) == 1L && !is.na(archived), "Archive filtering applies to studies.")
    where <- paste(where, "AND coalesce(json_extract(v.body_json,'$.archived'),0)=?"); params <- c(params, list(as.integer(archived)))
  }
  if (!is.null(modality) && nzchar(modality)) {
    brohn_require(kind == "dataset" && brohn_text(modality, 96), "Family filtering applies to datasets.")
    where <- paste(where, "AND json_extract(v.body_json,'$.modality')=?"); params <- c(params, list(modality))
  }
  from <- paste("FROM entity_versions v JOIN entities e ON v.kind=e.kind AND v.id=e.id AND v.revision=e.revision WHERE", where)
  total <- as.integer(DBI::dbGetQuery(store$con, paste("SELECT COUNT(*) AS n", from), params = params)$n[[1]])
  rows <- DBI::dbGetQuery(store$con, paste("SELECT v.*", from, "ORDER BY e.updated_at DESC,e.id ASC LIMIT ? OFFSET ?"), params = c(params, list(limit, offset)))
  list(records = lapply(seq_len(nrow(rows)), function(i) .brohn_store_entity(rows[i, , drop = FALSE])), total = total,
    offset = offset, limit = limit, has_previous = offset > 0, has_next = offset + nrow(rows) < total)
}
brohn_library_results_ui <- function(result, kind) {
  cards <- lapply(result$records, function(record) {
    if (kind == "study") return(brohn_study_card(record))
    if (kind == "dataset") return(brohn_card(title = record$body$title,
      subtitle = paste(record$body$modality, "\u00b7", record$body$source$filename, "\u00b7", format(record$body$source$size, big.mark = ","), "bytes"),
      brohn_badge(record$body$status), brohn_command("Inspect and map", "open_dataset", record$id, "btn btn-primary")))
    brohn_card(title = record$body$title, subtitle = paste("Saved design", "\u00b7", length(record$body$design$questions), "questions"),
      brohn_command("Use this design", "brohn_use_template", record$id, "btn btn-primary"))
  })
  shiny::tagList(shiny::p(role = "status", paste(result$total, "matching", switch(kind, study = "studies", dataset = "datasets", template = "designs"))),
    if (length(cards)) shiny::div(class = "brohn-grid", cards) else brohn_empty("No matching research", "Try another search or adjust the library filter."),
    if (result$has_previous || result$has_next) shiny::div(class = "brohn-toolbar",
      if (result$has_previous) brohn_command("Previous page", "library_page", list(kind = kind, direction = -1)),
      shiny::span(paste("Page", floor(result$offset/result$limit)+1L, "of", ceiling(result$total/result$limit))),
      if (result$has_next) brohn_command("Next page", "library_page", list(kind = kind, direction = 1))))
}

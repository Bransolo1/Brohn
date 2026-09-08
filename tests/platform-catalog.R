source("R/platform-load.R"); brohn_load(ui = FALSE)
local({
  checks <- 0L; check <- function(name, ok) {if (!isTRUE(ok)) stop("Catalog: ", name); checks <<- checks + 1L}
  root <- .brohn_port_temp(); store <- brohn_open_store(file.path(root, "catalog"))
  on.exit({brohn_close_store(store); .brohn_port_cleanup(root)}, add = TRUE)
  brohn_store_batch(store, function() for (i in 1:520) brohn_put_entity(store, "dataset", paste0("dataset-", i),
    list(title = paste("Recording", i), modality = if (i %% 2) "eeg" else "gaze", source = list(filename = if (i == 1) "old-caf\u00e9_100%.csv" else paste0(i, ".csv"))),
    project_id = if (i == 520) "second-project" else "default"))
  first <- brohn_search_library(store, "dataset", limit = 40)
  check("full catalog is counted before pagination", first$total == 520 && length(first$records) == 40 && first$has_next && !first$has_previous)
  old <- brohn_search_library(store, "dataset", "caf\u00e9_100%")
  check("older filename remains searchable beyond recent500", old$total == 1 && old$records[[1]]$id == "dataset-1")
  check("wildcards are literal search text", brohn_search_library(store, "dataset", "%")$total == 1)
  check("query text is parameterized", brohn_search_library(store, "dataset", "' OR 1=1 --")$total == 0)
  check("family filter counts all matching sources", brohn_search_library(store, "dataset", modality = "eeg")$total == 260)
  check("project filter excludes other project", brohn_search_library(store, "dataset", project_id = "default")$total == 519)
  second <- brohn_search_library(store, "dataset", limit = 40, offset = 40)
  check("pages are disjoint with deterministic ordering", !any(brohn_ids(first$records) %in% brohn_ids(second$records)) && second$has_previous)
  last <- brohn_search_library(store, "dataset", limit = 40, offset = 480)
  check("last page marks its boundary", length(last$records) == 40 && !last$has_next)
  record <- brohn_get_entity(store, "dataset", "dataset-1"); body <- record$body; body$title <- "Renamed source"
  brohn_put_entity(store, "dataset", record$id, body, record$revision)
  check("current revision replaces prior search title", brohn_search_library(store, "dataset", "Renamed source")$total == 1 && brohn_search_library(store, "dataset", "Recording 1")$total == 110)
  d <- brohn_new_design("Archived packaging", "blank"); d$archived <- TRUE
  brohn_put_entity(store, "study", d$id, d)
  check("archive filter is independent of search", brohn_search_library(store, "study", "packaging", archived = TRUE)$total == 1 && brohn_search_library(store, "study", archived = FALSE)$total == 0)
  cat(sprintf("PASS: %d library search and pagination assertions\n", checks))
})

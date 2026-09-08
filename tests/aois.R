source("R/aois.R")
local({
  path <- tempfile(fileext = ".png")
  on.exit(unlink(path), add = TRUE)
  png::writePNG(array(0.4, c(3, 2, 3)), path)
  x <- create_draft()
  for (id in x$study$stimulus_ids) x <- set_stimulus_asset(x, new_png_asset(path, id))
  for (id in x$study$stimulus_ids) x <- set_study_aoi(x, new_rectangle_aoi(x$study, id, "Logo", 0, 0, 0.5, 0.5))
  unchanged <- set_stimulus_asset(x, x$study$stimulus_assets[[1]])
  expect(identical(unchanged, x))
  png::writePNG(array(0.6, c(3, 2, 3)), path)
  replaced <- set_stimulus_asset(x, new_png_asset(path, "stimulus-a"))
  expect(length(replaced$study$aois) == 1 && identical(replaced$study$aois[[1]]$stimulus_id, "stimulus-b"))
  expect(!length(validate_bundle(replaced)))
})
# Synthetic image/rectangle fixtures; these do not validate an eye-tracking method.
local({
  directory <- tempfile("study-aois-")
  dir.create(directory)
  on.exit(unlink(directory, recursive = TRUE), add = TRUE)
  path <- file.path(directory, "synthetic.png")
  png::writePNG(array(seq(0, 1, length.out = 18), c(3, 2, 3)), path)
  draft <- create_draft()
  expect(!length(validate_study_aois(draft$study)))
  expect(identical(remove_study_aoi(draft, "absent"), draft))
  fails <- function(expression) inherits(try(expression, silent = TRUE), "try-error")
  expect(fails(new_rectangle_aoi(draft$study, "stimulus-a", "Logo", 0, 0, 1, 1)))
  for (stimulus in draft$study$stimulus_ids) {
    draft <- set_stimulus_asset(draft, new_png_asset(path, stimulus))
  }
  region <- new_rectangle_aoi(draft$study, "stimulus-a", "Logo", 0.1, 0.2, 0.3, 0.4)
  expect(scalar_text(region$id) && identical(region$shape, "rectangle"))
  expect(identical(region$asset_sha256, draft$study$stimulus_assets[[1L]]$sha256))
  invalid <- function(regions) {
    study <- draft$study; study["aois"] <- list(regions)
    length(validate_study_aois(study)) > 0L
  }
  expect(!invalid(list()))
  expect(!invalid(list(region)))
  expect(invalid(NULL))
  expect(invalid(list(named = region)))
  expect(invalid(list(region, region)))
  for (field in c("x", "y", "width", "height")) {
    for (value in list(NA_real_, NaN, Inf, -Inf, "0.1", TRUE, c(0.1, 0.2), NULL, 1i)) {
      bad <- region; bad[field] <- list(value)
      expect(invalid(list(bad)))
    }
  }
  for (coordinates in list(c(-1e-10, 0, 0.1, 0.1), c(0, -1e-10, 0.1, 0.1),
                           c(1.1, 0, 0.1, 0.1), c(0, 1.1, 0.1, 0.1),
                           c(0, 0, 0, 1), c(0, 0, 1, 0), c(0, 0, -0.1, 1),
                           c(0, 0, 1, -0.1), c(0.8, 0, 0.200000001, 1),
                           c(0, 0.8, 1, 0.200000001))) {
    bad <- region; bad[c("x", "y", "width", "height")] <- as.list(coordinates)
    expect(invalid(list(bad)))
  }
  edge <- region; edge[c("x", "y", "width", "height")] <- list(0.1, 0.2, 0.9, 0.8)
  expect(!invalid(list(edge)))
  edge$width <- 0.9 + .Machine$double.eps
  expect(!invalid(list(edge)))
  for (change in list(list(id = ""), list(stimulus_id = "unknown"), list(label = " "),
                      list(shape = "circle"), list(asset_sha256 = strrep("0", 64)),
                      list(extra = "field"))) {
    bad <- region; bad[names(change)] <- change
    expect(invalid(list(bad)))
  }
  bad <- region; bad$id <- NULL
  expect(invalid(list(bad)))
  second <- region; second$id <- "another-id"
  expect(invalid(list(region, second)))
  second$label <- " Logo "
  expect(invalid(list(region, second)))
  second$stimulus_id <- "stimulus-b"
  expect(!invalid(list(region, second)))
  missing_image <- draft$study; missing_image$aois <- list(region)
  missing_image$stimulus_assets <- missing_image$stimulus_assets[-1L]
  expect(length(validate_study_aois(missing_image)) > 0L)

  inserted <- set_study_aoi(draft, region)
  expect(inserted$study$revision == draft$study$revision + 1 &&
           inserted$session$study_revision == inserted$study$revision)
  expect(identical(inserted$study$aois, list(region)))
  expect(identical(set_study_aoi(inserted, region), inserted))
  reordered <- region[rev(names(region))]
  expect(identical(set_study_aoi(inserted, reordered), inserted))
  updated_region <- new_rectangle_aoi(inserted$study, "stimulus-a", "Brand", 0, 0, 1, 1, region$id)
  updated <- set_study_aoi(inserted, updated_region)
  expect(length(updated$study$aois) == 1L && updated$study$revision == inserted$study$revision + 1)
  expect(identical(updated$study$aois[[1L]]$id, region$id))
  integer_region <- updated_region
  integer_region[c("x", "y", "width", "height")] <- list(0L, 0L, 1L, 1L)
  expect(identical(set_study_aoi(updated, integer_region), updated))
  paired <- set_study_aoi(inserted, second)
  expect(length(paired$study$aois) == 2L)
  collision <- second; collision$stimulus_id <- "stimulus-a"
  expect(fails(set_study_aoi(paired, collision)))
  expect(fails(new_rectangle_aoi(inserted$study, "stimulus-a", "Logo", 0, 0, 1, 1)))
  expect(isTRUE(all.equal(bundle_from_json(bundle_to_json(paired)), paired)))
  expect(identical(paired$study$questions, draft$study$questions))
  preserved <- paired; preserved$study$aois <- NULL
  preserved$study$revision <- draft$study$revision
  preserved$session$study_revision <- draft$session$study_revision
  expect(identical(preserved, draft))
  removed <- remove_study_aoi(paired, region$id)
  expect(identical(removed$study$aois, list(second)) &&
           removed$study$revision == paired$study$revision + 1 &&
           removed$session$study_revision == removed$study$revision)
  expect(identical(remove_study_aoi(removed, region$id), removed))
  empty <- remove_study_aoi(removed, second$id)
  expect(identical(empty$study$aois, list()))
  expect(isTRUE(all.equal(bundle_from_json(bundle_to_json(empty)), empty)))
  expect(fails(remove_study_aoi(empty, "")))
  for (mode in c("sample", "preview")) {
    editable <- draft; editable$session$mode <- mode
    expect(!length(validate_bundle(set_study_aoi(editable, region))))
  }
  for (mode in c("pilot", "live")) {
    locked <- inserted; locked$session$mode <- mode
    expect(fails(set_study_aoi(locked, updated_region)))
    expect(fails(remove_study_aoi(locked, region$id)))
  }
  locked <- inserted; locked$clocks <- list(new_clock("clock", "domain"))
  expect(!length(validate_bundle(locked)))
  expect(fails(set_study_aoi(locked, updated_region)))
  expect(fails(remove_study_aoi(locked, region$id)))
})

source("R/assets.R")
# Synthetic PNGs only. These checks make no claim about participant testing.
local({
  directory <- tempfile("stimulus-assets-")
  dir.create(directory)
  on.exit(unlink(directory, recursive = TRUE), add = TRUE)
  path <- file.path(directory, "synthetic.png")
  png::writePNG(array(seq(0, 1, length.out = 18), c(3, 2, 3)), path)
  asset <- new_png_asset(path, "stimulus-a")
  ids <- c("stimulus-a", "stimulus-b")
  expect(!length(validate_stimulus_assets(list(), ids)))
  expect(!length(validate_stimulus_assets(list(asset), ids)))
  expect(asset$width == 2 && asset$height == 3)
  bytes <- readBin(path, "raw", n = file.info(path)$size)
  expect(identical(jsonlite::base64_dec(asset$data_base64), bytes))
  expect(identical(asset$sha256, digest::digest(bytes, "sha256", serialize = FALSE)))
  invalid <- function(x) length(validate_stimulus_assets(list(x), ids)) > 0L
  bad <- asset; bad$sha256 <- paste(rep("0", 64), collapse = "")
  expect(invalid(bad))
  bad <- asset; bad$width <- 3
  expect(invalid(bad))
  bad <- asset; bad$stimulus_id <- "unknown"
  expect(invalid(bad))
  expect(length(validate_stimulus_assets(list(asset, asset), ids)) > 0L)
  bad <- asset; bad$media_type <- "image/jpeg"
  expect(invalid(bad))
  bad <- asset; bad$filename <- "local-path.png"
  expect(invalid(bad))
  bad <- asset; bad$data_base64 <- paste0(asset$data_base64, "\n")
  expect(invalid(bad))
  bad <- asset; substr(bad$data_base64, 1, 1) <- "!"
  expect(invalid(bad))
  expect(length(validate_stimulus_assets(list(a = asset), ids)) > 0L)
  expect(length(validate_stimulus_assets(NULL, ids)) > 0L)
  header <- bytes[1:33]
  header[17:20] <- as.raw(c(0, 0, 16, 1)) # Width 4097, before CRC/image decode.
  bad_path <- file.path(directory, "oversized-header.png")
  writeBin(header, bad_path)
  expect(inherits(try(new_png_asset(bad_path, "stimulus-a"), silent = TRUE), "try-error"))
  bad <- asset; bad$data_base64 <- stimulus_base64(header)
  expect(invalid(bad))
  header[17:24] <- as.raw(c(0, 0, 11, 184, 0, 0, 11, 184)) # 3000 x 3000.
  writeBin(header, bad_path)
  expect(inherits(try(new_png_asset(bad_path, "stimulus-a"), silent = TRUE), "try-error"))
  writeBin(bytes[1:33], bad_path) # Valid header, missing image data.
  expect(inherits(try(new_png_asset(bad_path, "stimulus-a"), silent = TRUE), "try-error"))
  bad <- asset; bad$data_base64 <- stimulus_base64(bytes[1:33])
  bad$sha256 <- digest::digest(bytes[1:33], "sha256", serialize = FALSE)
  expect(invalid(bad))
  writeBin(raw(stimulus_asset_limits()$bytes + 1), bad_path)
  expect(inherits(try(new_png_asset(bad_path, "stimulus-a"), silent = TRUE), "try-error"))
  bad <- asset; bad$data_base64 <- strrep("A", 4 * ceiling(stimulus_asset_limits()$bytes / 3) + 4)
  expect(invalid(bad))

  draft <- create_draft()
  revised <- set_stimulus_asset(draft, asset)
  expect(revised$study$revision == 2 && revised$session$study_revision == 2)
  expect(identical(set_stimulus_asset(revised, asset), revised))
  expect(identical(revised$study$questions, draft$study$questions))
  expect(identical(revised$study$stimulus_assets[[1]], asset))
  second <- new_png_asset(path, "stimulus-b")
  paired <- set_stimulus_asset(revised, second)
  expect(length(paired$study$stimulus_assets) == 2 && paired$study$revision == 3)
  expect(isTRUE(all.equal(bundle_from_json(bundle_to_json(paired)), paired)))
  expect(nchar(bundle_to_json(paired), type = "bytes") < 16 * 1024^2)
  if (nzchar(Sys.getenv("CONTRACT_FIXTURE_DIR"))) {
    writeLines(bundle_to_json(paired), file.path(Sys.getenv("CONTRACT_FIXTURE_DIR"), "images.json"))
  }
  png::writePNG(array(0.5, c(3, 2, 3)), path)
  replacement <- new_png_asset(path, "stimulus-a")
  replaced <- set_stimulus_asset(paired, replacement)
  expect(length(replaced$study$stimulus_assets) == 2 && replaced$study$revision == 4)
  expect(identical(replaced$study$stimulus_assets[[2]], second))
  expect(inherits(try(set_stimulus_asset(sample_bundle(), asset), silent = TRUE), "try-error"))
  for (mode in c("pilot", "live")) {
    locked <- draft; locked$session$mode <- mode
    expect(inherits(try(set_stimulus_asset(locked, asset), silent = TRUE), "try-error"))
  }
})

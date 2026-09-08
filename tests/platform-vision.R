# Actual Python-in-R supervised vision jobs, durable artifact downloads and review.
for (module in c("platform-core", "platform-store", "platform-publication", "platform-methods", "platform-delivery", "platform-library", "platform-analysis", "platform-vision", "platform-jobs"))
  source(paste0("R/", module, ".R"), encoding = "UTF-8")
for (module in c("questionnaire-artifacts", "questionnaire-artifact-storage")) source(paste0("R/platform-",module,".R"),encoding="UTF-8")
local({
  checks <- 0L
  check <- function(name, ok) {if (!isTRUE(ok)) stop(paste("Vision QA failed:", name), call. = FALSE); checks <<- checks + 1L}
  rejected <- function(expr) inherits(try(force(expr), silent = TRUE), "try-error")
  root <- tempfile("brohn-vision-qa-"); dir.create(root); root <- normalizePath(root, winslash = "/")
  store <- brohn_open_store(file.path(root, "workspace"))
  on.exit({
    brohn_close_store(store)
    actual <- normalizePath(root, winslash = "/", mustWork = FALSE)
    stopifnot(startsWith(tolower(actual), paste0(tolower(normalizePath(tempdir(), winslash = "/")), "/")), grepl("^brohn-vision-qa-", basename(actual)))
    unlink(actual, recursive = TRUE, force = TRUE)
  }, add = TRUE)
  brohn_initialise_library(store)
  # Original generated media only, no people or remote resources.
  fixture <- paste(
    "import cv2,numpy as np,sys,subprocess,shutil; from pathlib import Path",
    "root=Path(sys.argv[1]); rgb=np.full((240,320,3),220,dtype=np.uint8); rgb[55:185,95:225]=[30,100,210]; rgb[75:90,105:215]=[210,120,20]",
    "assert cv2.imwrite(str(root/'original.png'),cv2.cvtColor(rgb,cv2.COLOR_RGB2BGR))",
    "subprocess.run([shutil.which('ffmpeg'),'-v','error','-f','lavfi','-i','color=c=black:s=160x120:r=10:d=0.4','-c:v','libx264','-pix_fmt','yuv420p','-y',str(root/'original.mp4')],check=True)", sep = "\n")
  processx::run(brohn_python_profile("video"), c("-c", fixture, root), timeout = 30, windows_hide_window = TRUE)
  design <- brohn_new_design("Original synthetic vision QA", id = "vision-qa")
  asset <- brohn_store_object(store, path = file.path(root, "original.png"), media_type = "image/png")
  asset$width <- 320L; asset$height <- 240L; asset$filename <- "original.png"
  design$stimuli[[1]]$type <- "image"; design$stimuli[[1]]$asset <- asset
  study <- brohn_put_entity(store, "study", design$id, design)
  queued <- brohn_queue_aoi_proposal(store, study$id, "stimulus-a", list(x=.5, y=.5))
  repeated <- brohn_queue_aoi_proposal(store, study$id, "stimulus-a", list(x=.5, y=.5))
  check("same pinned point proposal is idempotent", identical(queued$id, repeated$id))
  check("queue pins study and stimulus bytes", queued$request$study_revision == 1L && identical(queued$request$source_hash, asset$hash))
  claim <- brohn_claim_job(store, "vision-qa", lease_seconds = 60)
  brohn_process_job(store, claim, timeout_seconds = 120)
  finished <- brohn_get_job(store, claim$id)
  if (finished$status != "succeeded") stop(paste("Actual segmentation worker failed:", brohn_json(finished$error)), call. = FALSE)
  check("actual nested R/Python proposal job succeeds", finished$status == "succeeded")
  proposal <- brohn_get_entity(store, "aoi_proposal", finished$result$proposal_id)
  report <- brohn_get_entity(store, "report", finished$result$report_id)
  check("proposal requires explicit review", proposal$body$status == "needs_review" && identical(proposal$body$proposal$accepted, FALSE))
  check("original study remains unmodified by proposal", brohn_study(store, study$id)$revision == 1L && length(brohn_study(store, study$id)$body$stimuli[[1]]$aois) == 0L)
  mask_path <- brohn_proposal_mask_path(store, proposal$id)
  check("full mask remains available after attempt scratch cleanup", file.exists(mask_path) &&
    !length(setdiff(list.dirs(file.path(store$root, "scratch"), recursive = FALSE, full.names = FALSE), "publication")) &&
    identical(digest::digest(file=mask_path, algo="sha256"), proposal$body$proposal$mask_object$hash))
  download <- file.path(root, "downloaded-mask.png")
  check("mask download preserves exact immutable bytes", file.copy(mask_path, download) && identical(digest::digest(file=download, algo="sha256"), proposal$body$proposal$mask_sha256))
  report_download <- brohn_read_json_file(brohn_object_path(store, report$body$result_object$hash))
  check("download result contains durable mask object without scratch paths", !grepl("mask_path|output_directory|source_path|/scratch/", brohn_json(report_download)) &&
    identical(report_download$report$analysis$proposal$mask_object$hash, proposal$body$proposal$mask_object$hash))
  check("report and proposal preserve exact model identity", identical(report$body$analysis$engine$model$sha256,
    "e24338a717c1b7ad8d159666677ef400babb7f33b8ad60c4d96db4ecf694cd25"))
  check("stale study revision cannot accept proposal", rejected(brohn_review_aoi_proposal(store, proposal$id, "accept_rectangle", "Product", proposal$revision, 0L)))
  archived <- brohn_archive_study(store, study$id, TRUE, study$revision)
  check("archived study cannot queue proposals", rejected(brohn_queue_aoi_proposal(store, study$id, "stimulus-a", list(x=.5,y=.5))))
  check("archived study cannot accept proposal", rejected(brohn_review_aoi_proposal(store, proposal$id, "accept_rectangle", "Product", proposal$revision, archived$revision)))
  restored <- brohn_archive_study(store, study$id, FALSE, archived$revision)
  accepted <- brohn_review_aoi_proposal(store, proposal$id, "accept_rectangle", "Product", proposal$revision, restored$revision)
  updated <- brohn_study(store, study$id)
  check("acceptance appends explicit rectangle and increments study revision", accepted$body$status == "accepted_rectangle" && updated$revision == restored$revision + 1L &&
    length(updated$body$stimuli[[1]]$aois) == 1L && grepl("researcher_reviewed_proposal_rectangle", updated$body$stimuli[[1]]$aois[[1]]$source, fixed=TRUE))
  check("accepted rectangle retains reviewed mask evidence", identical(brohn_proposal_mask_path(store, accepted$id), mask_path) && identical(accepted$body$review$aoi_id, updated$body$stimuli[[1]]$aois[[1]]$id))
  check("double acceptance is rejected", rejected(brohn_review_aoi_proposal(store, accepted$id, "accept_rectangle", "Again", accepted$revision, updated$revision)))

  # A separately preserved proposal copy isolates edit/reject contracts without
  # pretending another model inference was run.
  pending <- proposal$body; pending$id <- "aoi-proposal-review-fixture"; pending$job_id <- "original-result-reference"
  pending_record <- brohn_put_entity(store, "aoi_proposal", pending$id, pending)
  changed <- updated$body; changed$stimuli[[1]]$aois <- list()
  changed$stimuli[[1]]$asset <- brohn_store_object(store, bytes = as.raw(c(1,2,3)), media_type = "image/png")
  changed_record <- brohn_save_study(store, changed, updated$revision)
  check("replaced stimulus blocks accepting old mask", rejected(brohn_review_aoi_proposal(store, pending$id, "accept_rectangle", "Wrong image", pending_record$revision, changed_record$revision)))
  rejected_proposal <- brohn_review_aoi_proposal(store, pending$id, "reject", expected_revision = pending_record$revision, note = "Image was replaced")
  check("rejection preserves proposal and decision note", rejected_proposal$body$status == "rejected" && identical(rejected_proposal$body$review$note, "Image was replaced"))

  imported <- brohn_ingest_dataset(store, file.path(root, "original.mp4"), "Original synthetic blank video", modality = "video", origin = "sample")
  mapping <- list(origin_statement = "Original four-frame synthetic black video; no person.", profile = "face_pose_hands_v1")
  valid <- imported$body; valid$metadata <- mapping
  check("valid video profile mapping is accepted", !rejected(brohn_validate_vision_mapping(valid)))
  invalid <- valid; invalid$metadata$profile <- "emotion_score"
  check("unsupported psychological profile is rejected", rejected(brohn_validate_vision_mapping(invalid)))
  invalid <- valid; invalid$metadata$start_s <- 2; invalid$metadata$end_s <- 1
  check("reversed explicit interval is rejected", rejected(brohn_validate_vision_mapping(invalid)))
  curated <- brohn_curate_dataset(store, imported$id, mapping, imported$revision)
  video_job <- brohn_queue_dataset(store, curated$id)
  video_claim <- brohn_claim_job(store, "vision-qa", lease_seconds = 60)
  brohn_process_job(store, video_claim, timeout_seconds = 120)
  video_done <- brohn_get_job(store, video_job$id)
  if (video_done$status != "succeeded") stop(paste("Actual video worker failed:", brohn_json(video_done$error)), call. = FALSE)
  video_report <- brohn_get_entity(store, "report", video_done$result$report_id)
  check("actual video job preserves insufficient support without zero scores", video_report$body$analysis$status == "insufficient_support" && length(video_report$body$analysis$features) == 0L)
  full <- video_report$body$analysis$artifacts[[1]]
  full_path <- brohn_object_path(store, full$hash)
  check("full native per-frame JSONL survives scratch cleanup", length(readLines(full_path, warn=FALSE)) == 4L &&
    identical(digest::digest(file=full_path,algo="sha256"),full$hash) && !length(setdiff(list.dirs(file.path(store$root,"scratch"),recursive=FALSE,full.names=FALSE),"publication")))
  check("video preserves source, provenance and origin separately", video_report$body$origin == "sample" &&
    identical(video_report$body$analysis$source$sha256, curated$body$source$hash) &&
    identical(video_report$body$processing$code_hashes[["scripts/workers/vision.py"]],digest::digest(file="scripts/workers/vision.py",algo="sha256")))
  check("vision report uses parent-owned native publication",identical(video_report$body$processing$publication$mode,"staged-windows-parent-read-seal/1.0"))
  check("video report has no ephemeral artifact path", !grepl("/scratch/|source_path|output_directory",brohn_json(video_report$body)))

  # Deliberately malformed/cancelled publication: catalog metadata must roll back.
  scratch <- file.path(store$root,"scratch","artifact-fence-test"); dir.create(file.path(scratch,"artifacts"),recursive=TRUE)
  file <- file.path(scratch,"artifacts","original.jsonl"); writeLines('{"original":true}',file)
  raw_analysis <- list(artifacts=list(list(kind="vision-observations",path=file,sha256=digest::digest(file=file,algo="sha256"),bytes=file.info(file)$size)))
  fence_job <- brohn_enqueue_job(store,"artifact_qa",list(original=TRUE),"vision-artifact-fence")
  fence_claim <- brohn_claim_job(store,"vision-qa",lease_seconds=60)
  before <- DBI::dbGetQuery(store$con,"SELECT COUNT(*) AS n FROM objects")$n
  bad <- raw_analysis; bad$artifacts[[1]]$sha256 <- paste(rep("0",64),collapse="")
  check("bad artifact hash cannot publish metadata", rejected(brohn_promote_worker_artifacts(store,bad,scratch,fence_claim)) && DBI::dbGetQuery(store$con,"SELECT COUNT(*) AS n FROM objects")$n == before)
  outside <- file.path(root,"outside.jsonl"); writeLines('{"original":true}',outside)
  bad <- raw_analysis; bad$artifacts[[1]]$path <- outside
  check("artifact outside scratch is rejected", rejected(brohn_promote_worker_artifacts(store,bad,scratch,fence_claim)))
  invisible(brohn_cancel_job(store,fence_job$id))
  check("cancelled fence cannot promote even correct bytes", rejected(brohn_promote_worker_artifacts(store,raw_analysis,scratch,fence_claim)) && DBI::dbGetQuery(store$con,"SELECT COUNT(*) AS n FROM objects")$n == before)
  failed_job <- brohn_enqueue_job(store,"segment_aoi",modifyList(queued$request,list(source_hash=paste(rep("0",64),collapse=""))),"vision-corrupt-source")
  failed_claim <- brohn_claim_job(store,"vision-qa",lease_seconds=60)
  count <- length(brohn_list_entities(store,"aoi_proposal"))
  brohn_process_job(store,failed_claim,timeout_seconds=30)
  check("failed pinned source cannot publish a proposal", brohn_get_job(store,failed_job$id)$status=="failed" && length(brohn_list_entities(store,"aoi_proposal"))==count)
  check("catalog remains consistent after failures", identical(DBI::dbGetQuery(store$con,"PRAGMA integrity_check")[[1]],"ok"))
  cat(sprintf("PASS: %d vision assertions (real child workers, immutable artifacts, explicit review, stale/failure fences)\n",checks))
})

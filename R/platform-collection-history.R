# A release-scoped collection inventory. It freezes saved session/report
# membership, not scientific eligibility, cross-device alignment or a new score.
.brohn_collection_id <- function(release_id) paste0("collection-", release_id)
.brohn_collection_release <- function(store, release_id, study_id, project_id) {
  release <- brohn_deployment(store, release_id, include_token = FALSE)
  brohn_require(!is.null(release) && identical(release$study_id, study_id) && identical(release$project_id, project_id),
    "Choose a release belonging to the open study and project.")
  release
}
brohn_collection_record <- function(store, release_id, study_id, project_id) {
  .brohn_collection_release(store, release_id, study_id, project_id)
  record <- brohn_get_entity(store, "collection", .brohn_collection_id(release_id))
  if (!is.null(record)) brohn_require(record$revision == 1L && identical(record$project_id, project_id) &&
    identical(record$body$study_id, study_id) && identical(record$body$release$id, release_id) &&
    identical(record$body$schema, "brohn-finalized-collection/1.0"), "The saved collection identity is inconsistent.")
  record
}
brohn_collection_page <- function(store, study_id, project_id, offset = 0L, limit = 20L) {
  study <- brohn_study(store, study_id)
  brohn_require(identical(study$project_id, project_id) && brohn_number(offset, 0, 1e8, TRUE) &&
    brohn_number(limit, 1, 40, TRUE), "Choose a collection history page in this project.")
  if (!DBI::dbExistsTable(store$con, "delivery_deployments")) return(list(records = list(), total = 0L, offset = 0L, limit = limit))
  from <- "FROM delivery_deployments d LEFT JOIN entities e ON e.kind='collection' AND e.id='collection-'||d.id WHERE d.study_id=? AND d.project_id=? AND d.status='closed'"
  read <- function() {
    total <- DBI::dbGetQuery(store$con, paste("SELECT count(*) AS n", from), params = list(study_id, project_id))$n[[1L]]
    actual <- if (total) min(offset, floor((total-1L)/limit)*limit) else 0L
    rows <- DBI::dbGetQuery(store$con, paste("SELECT d.id,d.origin,d.design_revision,d.created_at,e.id AS collection_id", from,
      "ORDER BY d.created_at DESC,d.id LIMIT ? OFFSET ?"), params = list(study_id, project_id, limit, actual))
    list(records = lapply(seq_len(nrow(rows)), function(i) as.list(rows[i,,drop=FALSE])), total = total, offset = actual, limit = limit)
  }
  if (RSQLite::sqliteIsTransacting(store$con)) read() else DBI::dbWithTransaction(store$con, read())
}
brohn_collection_review <- function(store, release_id, study_id, project_id, verify_reports = FALSE) {
  .brohn_delivery_schema(store)
  read <- function() {
    release <- .brohn_collection_release(store, release_id, study_id, project_id)
    brohn_require(identical(release$status, "closed"), "Close recruitment before reviewing a final collection.")
    count <- DBI::dbGetQuery(store$con, "SELECT count(*) AS n FROM delivery_runs WHERE deployment_id=?", params = list(release_id))$n[[1L]]
    brohn_require(count <= 2000L, "This finalization profile supports up to 2,000 sessions per release. Keep this larger release closed; its existing sessions and reports remain available in Review and Results.")
    rows <- DBI::dbGetQuery(store$con, paste("SELECT id,study_id,deployment_id,origin,protocol_hash,allocation_index,completion_status,transfer_status,acked_sequence,finalized_at",
      "FROM delivery_runs WHERE deployment_id=? ORDER BY allocation_index,id"), params = list(release_id))
    sessions <- list(); blockers <- list(); jobs <- list(); reports <- list(); captures <- list(); resolutions <- list()
    block <- function(kind, id, text) blockers[[length(blockers)+1L]] <<- list(kind = kind, id = id, text = text)
    for (i in seq_len(nrow(rows))) {
      run <- as.list(rows[i,,drop=FALSE]); run$finalized_at <- if (is.na(run$finalized_at)) NULL else run$finalized_at
      brohn_require(identical(run$study_id, study_id) && identical(run$origin, release$origin), "A session has an inconsistent study or collection origin.")
      if (verify_reports) {
        assigned <- brohn_run_protocol(store,run$id,study_id,project_id)
        brohn_require(identical(assigned$hash,run$protocol_hash) && identical(assigned$protocol$design_hash,release$design_hash),
          "A saved participant protocol no longer matches the closed release.")
      }
      sessions[[length(sessions)+1L]] <- run
      resolution <- brohn_session_resolution(store,run$id)
      if (!is.null(resolution)) {
        b<-resolution$body;s<-b$source
        brohn_require(identical(resolution$project_id,project_id)&&identical(b$study_id,study_id)&&identical(b$release_id,release_id)&&
          identical(b$origin,release$origin)&&identical(s$run_id,run$id)&&identical(s$protocol_hash,run$protocol_hash)&&
          identical(s$design_hash,release$design_hash)&&identical(s$received_sequence,run$acked_sequence)&&
          identical(s$original_receipt$completion_status,run$completion_status)&&identical(s$original_receipt$transfer_status,run$transfer_status)&&
          identical(s$original_receipt$finalized_at,run$finalized_at)&&
          b$effective_resolution %in% c("researcher_interrupted","received_completion_confirmed","participant_ending_preserved"),
          "A saved researcher resolution does not match its original session, receipt or release. Open the saved resolution before finalization.")
        if(verify_reports)brohn_require(identical(.brohn_sr_snapshot(store,release_id,run$id,study_id,project_id,verify_bytes=TRUE)$hash,b$source_hash),
          "Received evidence changed after researcher resolution. Preserve the saved source and inspect its resolution before finalization.")
        resolutions[[length(resolutions)+1L]]<-list(id=resolution$id,revision=resolution$revision,hash=brohn_hash(b),run_id=run$id,
          release_id=release_id,study_id=study_id,source_hash=b$source_hash,protocol_hash=s$protocol_hash,design_hash=s$design_hash,
          received_sequence=s$received_sequence,effective_resolution=b$effective_resolution,
          participant_ending=if(is.null(b$participant_ending))NULL else b$participant_ending$outcome,
          participant_final_receipt_missing=b$participant_final_receipt_missing,received_completion_analysis_eligible=b$received_completion_analysis_eligible,
          retained_camera=s$camera,partial_camera_omitted=brohn_session_resolution_capture_omission(resolution),decided_at=b$operator$decided_at)
      }
      if (run$completion_status == "in_progress" && is.null(resolution)) block("session",run$id,paste("Session",run$allocation_index,"is still in progress. Return to its participant browser to finish or withdraw, or use Review session recovery to inspect its received evidence. Closing recruitment does not stop an active session."))
      else if (is.null(resolution) && (!run$completion_status %in% c("completed","withdrawn","interrupted") || run$transfer_status != "saved" || is.null(run$finalized_at)))
        block("session",run$id,paste("Session",run$allocation_index,"does not have a supported final saved receipt. Review its participant browser and receipt before finalizing."))
      capture <- if (DBI::dbExistsTable(store$con,"camera_captures")) brohn_capture(store,run_id=run$id) else NULL
      if (!is.null(capture)) {
        captures[[length(captures)+1L]] <- list(id=capture$id,run_id=run$id,status=capture$status,hash=brohn_hash(capture),
          total_bytes=capture$total_bytes,acked_sequence=capture$acked_sequence)
        if (capture$status == "recording" && !brohn_session_resolution_capture_omission(resolution)) block("session",run$id,paste("Session",run$allocation_index,"still has an open camera recording. Finish its upload in the participant browser or use Review session recovery to inspect its received evidence."))
      }
      job_rows <- DBI::dbGetQuery(store$con, paste("SELECT * FROM jobs WHERE json_extract(request_json,'$.run_id')=? OR",
        "json_extract(request_json,'$.dataset_id') IN (SELECT e.id FROM entities e JOIN entity_versions v ON e.kind=v.kind AND e.id=v.id AND e.revision=v.revision",
        "WHERE e.kind='dataset' AND e.project_id=? AND json_extract(v.body_json,'$.source_provenance.run_id')=?) ORDER BY created_at,id"), params=list(run$id,project_id,run$id))
      attempts <- lapply(seq_len(nrow(job_rows)),function(j).brohn_store_job(job_rows[j,,drop=FALSE]))
      automatic <- Filter(function(j)j$operation=="analyse_run",attempts)
      confirmed <- Filter(function(j)j$operation=="analyse_resolved_run",attempts)
      for (job in attempts) {
        jobs[[length(jobs)+1L]] <- list(id=job$id,run_id=run$id,operation=job$operation,status=job$status,
          request_hash=brohn_hash(job$request),report_id=job$result$report_id)
        if (job$status %in% c("queued","running")) block("job",job$id,paste("Session",run$allocation_index,":",gsub("_"," ",job$operation),"is",job$status,". Open processing to inspect or recover it."))
      }
      if (identical(run$completion_status,"completed") && !any(vapply(automatic,function(j)identical(j$status,"succeeded")&&!is.null(j$result$report_id),logical(1))))
        block("job",if(length(automatic))tail(automatic,1)[[1L]]$id else run$id,paste("Session",run$allocation_index,"has no successful automatic response report. Open processing and retry its saved inputs."))
      if (!is.null(resolution) && isTRUE(resolution$body$received_completion_analysis_eligible) &&
          !any(vapply(confirmed,function(j)identical(j$status,"succeeded")&&!is.null(j$result$report_id)&&
            identical(j$request$resolution_id,resolution$id)&&identical(j$request$resolution_hash,brohn_hash(resolution$body)),logical(1))))
        block("job",if(length(confirmed))tail(confirmed,1)[[1L]]$id else run$id,paste("Session",run$allocation_index,"has a researcher-confirmed received completion but no successful report for that exact decision. Open its saved resolution to analyse the received completion, or recover its job in Activity."))
      if (!is.null(capture) && capture$total_bytes>0 && !brohn_session_resolution_capture_omission(resolution) &&
          !any(vapply(attempts,function(j)j$operation=="assemble_capture" && j$status=="succeeded",logical(1))))
        block("job",capture$id,paste("Session",run$allocation_index,"camera bytes have not been preserved as a completed recording dataset. Open processing to recover assembly."))
      for (job in Filter(function(j)j$status=="succeeded" && !is.null(j$result$report_id),attempts)) {
        report <- brohn_get_entity(store,"report",job$result$report_id)
        brohn_require(!is.null(report) && identical(report$project_id,project_id) && identical(report$body$study_id,study_id) && identical(report$body$origin,release$origin),
          "A processing result is missing or belongs to another study or origin. Inspect it before finalization.")
        if (job$operation=="analyse_run") brohn_require(length(report$body$provenance$runs)==1L &&
          identical(report$body$provenance$runs[[1L]]$run_id,run$id) && identical(report$body$provenance$design_hash,release$design_hash),
          "The automatic response report does not match its assigned session and release.")
        if (job$operation=="analyse_resolved_run") brohn_require(!is.null(resolution)&&isTRUE(resolution$body$received_completion_analysis_eligible)&&
          identical(job$request$resolution_id,resolution$id)&&identical(job$request$resolution_hash,brohn_hash(resolution$body))&&
          length(report$body$provenance$runs)==1L&&identical(report$body$provenance$runs[[1L]]$run_id,run$id)&&
          identical(report$body$provenance$runs[[1L]]$deployment_id,release_id)&&
          identical(report$body$provenance$runs[[1L]]$design_hash,release$design_hash)&&
          identical(report$body$provenance$runs[[1L]]$final_sequence,run$acked_sequence)&&
          identical(report$body$provenance$runs[[1L]]$finalized_at,run$finalized_at)&&
          identical(report$body$provenance$design_hash,release$design_hash)&&
          identical(report$body$provenance$session_resolution$id,resolution$id)&&
          identical(report$body$provenance$session_resolution$hash,brohn_hash(resolution$body))&&
          identical(brohn_hash(report$body$provenance$session_resolution$body),brohn_hash(resolution$body)),
          "The researcher-confirmed response report does not match its original session, release or immutable resolution.")
        # Reading the entity verifies its stored JSON hash. Do not retain its
        # potentially large observations or private answers in the inventory.
        previous <- Filter(function(r)identical(r$id,report$id),reports)
        if(length(previous)) brohn_require(identical(previous[[1L]]$hash,brohn_hash(report$body)) &&
          identical(previous[[1L]]$run_id,run$id),"A saved report reference is inconsistent across sessions.") else
          reports[[length(reports)+1L]] <- list(id=report$id,revision=report$revision,hash=brohn_hash(report$body),
            job_id=job$id,run_id=run$id,title=brohn_default(report$body$title,"Saved report"))
      }
      for (operation in unique(vapply(Filter(function(j)j$status %in% c("failed","cancelled"),attempts),`[[`,character(1),"operation"))) {
        failed <- Filter(function(j)j$operation==operation && j$status %in% c("failed","cancelled"),attempts)
        # A retry only resolves the exact frozen request, not a different run or
        # analysis configuration with a conveniently successful operation name.
        for (job in failed) if (!brohn_session_resolution_capture_omission(resolution,job) &&
            !any(vapply(attempts,function(j)j$status=="succeeded" && j$operation==operation && identical(brohn_hash(j$request),brohn_hash(job$request)),logical(1))))
          block("job",job$id,paste("Session",run$allocation_index,":",gsub("_"," ",operation),"is",job$status,"without a successful retry of those saved inputs. Open processing to retry it."))
      }
    }
    inventory <- list(release=release, sessions=sessions, jobs=jobs, reports=reports, captures=captures,resolutions=resolutions)
    list(inventory=inventory,hash=brohn_hash(inventory),blockers=blockers,ready=!length(blockers),
      counts=list(started=length(sessions),completed=sum(vapply(sessions,function(s)s$completion_status=="completed",logical(1))),
        withdrawn=sum(vapply(sessions,function(s)s$completion_status=="withdrawn",logical(1))),
        interrupted=sum(vapply(sessions,function(s)s$completion_status=="interrupted",logical(1))),
        original_in_progress=sum(vapply(sessions,function(s)s$completion_status=="in_progress",logical(1))),
        researcher_resolutions=list(total=length(resolutions),
          researcher_interrupted=sum(vapply(resolutions,function(s)s$effective_resolution=="researcher_interrupted",logical(1))),
          received_completion_confirmed=sum(vapply(resolutions,function(s)s$effective_resolution=="received_completion_confirmed",logical(1))),
          participant_ending_preserved=sum(vapply(resolutions,function(s)s$effective_resolution=="participant_ending_preserved",logical(1))),
          participant_final_receipt_missing=sum(vapply(resolutions,function(s)isTRUE(s$participant_final_receipt_missing),logical(1))))))
  }
  if (RSQLite::sqliteIsTransacting(store$con)) read() else DBI::dbWithTransaction(store$con, read())
}
brohn_finalize_collection <- function(store, release_id, study_id, project_id, expected_hash) {
  .brohn_store_tx(store,function() {
    old <- brohn_collection_record(store,release_id,study_id,project_id)
    if (!is.null(old)) return(old)
    brohn_require(!.brohn_store_execution_paused(store),"This restored workspace is paused. Resume workspace processing before finalizing a new collection.")
    review <- brohn_collection_review(store,release_id,study_id,project_id,TRUE)
    brohn_require(identical(review$hash,expected_hash),"The collection changed after review. Refresh the collection review before finalizing.")
    brohn_require(review$ready,"Resolve the listed sessions and processing before finalizing this collection.")
    body <- c(list(schema="brohn-finalized-collection/1.0",id=.brohn_collection_id(release_id),study_id=study_id,
      finalized_at=brohn_now(),inventory_hash=review$hash,counts=review$counts,
      policy=list(membership="All started sessions in this closed release, including distinct saved terminal outcomes.",
        reports="Saved successful reports at finalization; later analyses do not rewrite this inventory.",
        denominator="Sessions, not unique people. Completion is not scientific quality or eligibility.",
        researcher_resolutions="Immutable researcher decisions are separate references and counts. Original participant completion, transfer and final receipt fields remain unchanged; confirmed received completions are not counted as original completed receipts.",
        scope="This release's participant receipts and linked processing. Separate imported datasets and external device recordings are not included automatically.",
        late_uploads="Finalization requires supported saved terminal receipts or explicit source-bound researcher resolutions with resolved linked processing. Partial camera bytes remain partial; existing original outcomes stay immutable and further collection uses a new release.")),review$inventory)
    brohn_put_entity(store,"collection",body$id,body,project_id=project_id)
  })
}
brohn_collection_report <- function(store, record, report_id) {
  item <- Filter(function(r)identical(r$id,report_id),record$body$reports)
  brohn_require(length(item)==1L,"Choose a report included in this finalized collection.")
  report <- brohn_get_entity(store,"report",report_id,item[[1L]]$revision)
  brohn_require(!is.null(report) && identical(report$project_id,record$project_id) && identical(brohn_hash(report$body),item[[1L]]$hash),
    "This collection report is unavailable or its saved identity changed.")
  # Existing report navigation uses the immutable report head. Refuse a changed
  # head instead of opening a different revision than the collection promises.
  head <- brohn_get_entity(store,"report",report_id)
  brohn_require(identical(head$revision,report$revision),"This report has a newer revision. Download the collection manifest to retain its original reference.")
  report
}

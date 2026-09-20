source("R/platform-load.R",encoding="UTF-8");brohn_load()
local({
  checks<-0L
  check<-function(name,value){if(!isTRUE(value))stop("Cardiac marker QA: ",name,call.=FALSE);checks<<-checks+1L}
  rejects<-function(expr)inherits(try(force(expr),silent=TRUE),"try-error")
  root<-Sys.getenv("BROHN_CARDIAC_MARKER_QA",tempfile("brohn-cardiac-markers-"));dir.create(root,recursive=TRUE,showWarnings=FALSE)
  root<-normalizePath(root,winslash="/",mustWork=TRUE);stopifnot(startsWith(basename(root),"brohn-cardiac-markers-"))
  store<-brohn_open_store(file.path(root,"workspace"));brohn_initialise_library(store);on.exit(brohn_close_store(store),add=TRUE)
  processx::run(brohn_python_profile("ecg"),c("tests/workers/cardiac_markers.py","--fixture",root),windows_hide_window=TRUE)
  run_job<-function(queued){
    force(queued);claim<-brohn_claim_job(store,"cardiac-marker-qa",120);stopifnot(identical(claim$id,queued$id))
    brohn_process_job(store,claim,timeout_seconds=120);done<-brohn_get_job(store,queued$id)
    if(!identical(done$status,"succeeded"))stop(brohn_json(done$error))
    brohn_get_entity(store,"signal_view",done$result$signal_view_id)
  }
  saved<-list()
  for(modality in c("ecg","ppg")){
    fixture<-brohn_read_json_file(file.path(root,paste0(modality,"-request.json")))
    manifests<-list(fixture$artifact,fixture$marker_overlay$event_artifact)
    artifacts<-lapply(manifests,function(a){object<-brohn_store_object(store,path=a$path,media_type="application/x-ndjson")
      c(list(kind=a$kind),object,a[c("schema","tables","rows","provenance_sha256","complete")])})
    id<-brohn_id("report");body<-list(id=id,title=paste("Independent",toupper(modality),"marker fixture"),origin="sample",status="Available",
      analysis=list(kind=modality,artifacts=artifacts,artifact_verification=fixture$verification_receipt))
    report<-brohn_put_entity(store,"report",id,body,0L,"default");before<-brohn_hash(report$body)
    catalog<-run_job(brohn_queue_signal_view(store,id,"physiology-series"))
    check(paste(modality,"catalog retains separate segment identity"),catalog$body$view$tables[[1L]]$identity$segment_id=="segment-1")
    queued<-brohn_queue_signal_view(store,id,"physiology-series",fixture$selection,max_bins=1L)
    check(paste(modality,"queue freezes both exact artifacts and named view recipe"),queued$request$recipe=="processed-signal-view/1.2.0"&&
      queued$request$marker_overlay$event_artifact$sha256==fixture$marker_overlay$event_artifact$sha256)
    check(paste(modality,"exact overlay request deduplicates"),brohn_queue_signal_view(store,id,"physiology-series",fixture$selection,max_bins=1L)$id==queued$id)
    input<-brohn_signal_input(store,queued);view<-run_job(queued);m<-view$body$view$marker_overlay
    check(paste(modality,"actual supervised marker join preserves every source sample"),identical(as.numeric(vapply(m$markers,`[[`,numeric(1),"source_sample_index")),c(501,503,505,507))&&m$selected_marker_count==4)
    check(paste(modality,"exact values survive waveform decimation"),identical(as.numeric(vapply(m$markers,`[[`,numeric(1),"value")),c(-2,3,2,-1)))
    check(paste(modality,"missing and rejected interval evidence remains distinct"),is.null(m$markers[[1L]]$previous_interval_ms)&&is.null(m$markers[[1L]]$previous_interval_plausible)&&identical(m$markers[[3L]]$previous_interval_plausible,FALSE))
    check(paste(modality,"detections stay unreviewed"),m$review_status=="unreviewed_algorithm_detections"&&m$event_type==fixture$marker_overlay$event_type)
    raw_selection<-fixture$selection;raw_selection$value_column<-"raw"
    raw_job<-brohn_queue_signal_view(store,id,"physiology-series",raw_selection,max_bins=1L)
    raw_input<-brohn_signal_input(store,raw_job);raw_view<-run_job(raw_job);raw<-raw_view$body$view
    check(paste(modality,"input values from actual second saved view use exact samples"),identical(as.numeric(vapply(raw$marker_overlay$markers,`[[`,numeric(1),"value")),c(6,16,14,8)))
    clean_events<-lapply(m$markers,function(x){x$value<-NULL;x})
    input_events<-lapply(raw$marker_overlay$markers,function(x){x$value<-NULL;x})
    check(paste(modality,"waveform choice never relocates or reclassifies a saved detection"),identical(brohn_hash(clean_events),brohn_hash(input_events))&&raw$marker_overlay$waveform_column=="raw"&&raw$marker_overlay$detection_basis=="saved_cleaned_waveform")
    changed<-raw;changed$marker_overlay$waveform_column<-"clean"
    check(paste(modality,"substituted waveform declaration rejected"),rejects(brohn_validate_signal_result(changed,raw_input)))
    changed<-raw;changed$marker_overlay$detection_basis<-"raw"
    check(paste(modality,"new detection basis cannot be invented by display"),rejects(brohn_validate_signal_result(changed,raw_input)))
    changed<-raw;changed$marker_overlay$schema<-"brohn-cardiac-marker-overlay/1.0";changed$marker_overlay$waveform_column<-NULL;changed$marker_overlay$detection_basis<-NULL
    check(paste(modality,"legacy cleaned marker cannot be relabelled as input"),rejects(brohn_validate_signal_result(changed,raw_input)))
    legacy<-view$body$view;legacy$marker_overlay$schema<-"brohn-cardiac-marker-overlay/1.0";legacy$marker_overlay$waveform_column<-NULL;legacy$marker_overlay$detection_basis<-NULL
    check(paste(modality,"old exact cleaned view remains readable"),!rejects(brohn_validate_signal_result(legacy,input))&&!is.null(brohn_signal_markers(legacy)))
    raw_html<-as.character(brohn_signal_plot_ui(raw_view));raw_svg<-as.character(brohn_signal_svg(raw))
    check(paste(modality,"input labels and detector basis remain explicit in table and SVG"),grepl("Input value (",raw_html,fixed=TRUE)&&grepl("unit conversion",raw_html,fixed=TRUE)&&grepl("detections were calculated from the cleaned signal",raw_svg,fixed=TRUE)&&!grepl("cleaned value",raw_svg,fixed=TRUE))
    brohn_write_json_file(raw,file.path(root,paste0(modality,"-input-view.json")))
    check(paste(modality,"source report unchanged and both private paths absent"),identical(brohn_hash(brohn_get_entity(store,"report",id)$body),before)&&
      !grepl(root,brohn_json(view$body),fixed=TRUE)&&!grepl('"path"',brohn_json(view$body),fixed=TRUE))
    altered<-view$body$view;altered$marker_overlay$event_artifact$sha256<-paste(rep("f",64),collapse="")
    check(paste(modality,"substituted event hash rejected"),rejects(brohn_validate_signal_result(altered,input)))
    altered<-view$body$view;altered$marker_overlay$review_status<-"reviewed"
    check(paste(modality,"view cannot grant scientific review"),rejects(brohn_validate_signal_result(altered,input)))
    altered<-view$body$view;altered$marker_overlay$selected_marker_count<-5
    check(paste(modality,"partial marker list rejected"),rejects(brohn_validate_signal_result(altered,input)))
    altered<-view$body$view;altered$marker_overlay$markers[[2L]]$source_sample_index<-501
    check(paste(modality,"duplicate marker key rejected"),rejects(brohn_validate_signal_result(altered,input)))
    altered<-view$body$view;altered$marker_overlay$alignment<-"not_checked_display_limit_exceeded"
    check(paste(modality,"displayed markers require checked exact alignment"),rejects(brohn_validate_signal_result(altered,input)))
    ranged<-fixture$selection;ranged$range<-list(13,15)
    narrower<-run_job(brohn_queue_signal_view(store,id,"physiology-series",ranged,max_bins=1L));n<-narrower$body$view$marker_overlay
    check(paste(modality,"ranged view preserves interval beginning before displayed window"),n$selected_marker_count==2&&n$markers[[1L]]$previous_interval_ms==2000&&n$markers[[1L]]$event_row_index==1)
    path<-file.path(root,paste0(modality,"-saved-view.json"));brohn_copy_object_download(store,view$body$result_object$hash,path)
    check(paste(modality,"saved JSON download exact"),.brohn_store_hash(path,file=TRUE)==view$body$result_object$hash)
    brohn_write_json_file(view$body$view,file.path(root,paste0(modality,"-view.json")))
    saved[[modality]]<-list(report_id=id,report_hash=before,view_id=view$id,view_hash=brohn_hash(view$body))
  }
  # Actual complete-reader output exercises the bounded status contract without
  # manufacturing a scientific report or making an unchecked join look exact.
  limit_code<-paste("import importlib.util,json,sys;from pathlib import Path",
    "s=importlib.util.spec_from_file_location('cases','tests/workers/cardiac_markers.py');m=importlib.util.module_from_spec(s);s.loader.exec_module(m)",
    "root=Path(sys.argv[1]);request=m.fixture(root,n=5005,indices=list(range(1,5005,2)))",
    "(root/'limit-request.json').write_text(json.dumps(request),encoding='utf-8')",
    "(root/'limit-view.json').write_text(json.dumps(m.worker.run(request)),encoding='utf-8')",sep="\n")
  limit_root<-file.path(root,"limit");dir.create(limit_root)
  processx::run(brohn_python_profile("ecg"),c("-B","-c",limit_code,limit_root),windows_hide_window=TRUE)
  limit_input<-brohn_read_json_file(file.path(limit_root,"limit-request.json"));limit_view<-brohn_read_json_file(file.path(limit_root,"limit-view.json"))
  check("actual over-limit count is accepted only as unchecked",!rejects(brohn_validate_signal_result(limit_view,limit_input))&&limit_view$marker_overlay$selected_marker_count==2502)
  altered<-limit_view;altered$marker_overlay$alignment<-"exact_source_sample_and_recorded_time"
  check("over-limit exact-alignment claim rejected",rejects(brohn_validate_signal_result(altered,limit_input)))
  altered<-limit_view;altered$marker_overlay$selected_marker_count<-limit_input$marker_overlay$event_artifact$rows+1
  check("count cannot exceed complete saved event rows",rejects(brohn_validate_signal_result(altered,limit_input)))
  altered<-limit_view;altered$marker_overlay$markers<-list(saved_marker=list(source_sample_index=501))
  check("over-limit partial marker list rejected",rejects(brohn_validate_signal_result(altered,limit_input)))
  altered<-limit_view;altered$marker_overlay$selected_marker_count<-2000
  check("within-limit count cannot bypass exact join",rejects(brohn_validate_signal_result(altered,limit_input)))
  brohn_close_store(store);store<-brohn_open_store(file.path(root,"workspace"))
  for(item in saved)check("exact unreviewed display survives reopen",brohn_hash(brohn_get_entity(store,"signal_view",item$view_id)$body)==item$view_hash&&brohn_hash(brohn_get_entity(store,"report",item$report_id)$body)==item$report_hash)
  brohn_write_json_file(list(checks=checks,origin="original_independent_synthetic_fixture",workspace=store$root,reports=saved),file.path(root,"acceptance.json"))
  cat(checks," cardiac marker checks passed; evidence ",root,"\n",sep="")
})

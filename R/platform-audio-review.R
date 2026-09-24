# Source-bound waveform/spectrum review; saved acoustic measurements are unchanged.
.brohn_audio_review_profile <- "audio-source-review/1.0"
.brohn_audio_review_loaded <- stats::setNames(lapply(c("R/platform-audio-review.R", "scripts/workers/audio_review.py"),
  function(p) digest::digest(file=p,algo="sha256")),c("R/platform-audio-review.R", "scripts/workers/audio_review.py"))
.brohn_ar_parameters <- function(body) {
  a<-body$analysis
  if(length(a$recordings)!=1L||length(a$parameters)!=1L)return(NULL)
  key<-a$recordings[[1L]]$recording_id
  if(!brohn_text(key,128)||!identical(names(a$parameters),key))return(NULL)
  a$parameters[[key]]
}
.brohn_ar_supported <- function(body) identical(body$analysis$kind,"audio") && identical(.brohn_ar_parameters(body)$recipe,"audio-praat-acoustics/1.0")
.brohn_ar_decimal <- function(x) brohn_text(x,64) && grepl("^[0-9]+(\\.[0-9]+)?$",x) && is.finite(suppressWarnings(as.numeric(x)))
.brohn_ar_ref <- function(r) list(id=r$id,revision=r$revision,hash=.brohn_sv_hash(r$body))
# Cache only completed pure structural checks keyed by complete input/output
# content. Project/catalog checks and immutable source read guards always run.
.brohn_ar_validated <- local({keys<-character();function(key,add=FALSE){
  if(!add)return(key %in% keys)
  keys<<-tail(unique(c(keys,key)),32L);invisible(TRUE)
}})
brohn_audio_review_source <- function(store,report_id,revision,hash,project_id,verify=TRUE) {
  brohn_project(store,project_id)
  .brohn_qexplorer_catalog(store,"report",report_id,revision,project_id)
  r<-brohn_get_entity(store,"report",report_id,revision); b<-r$body; a<-b$analysis; p<-b$provenance
  brohn_require(!is.null(r) && identical(.brohn_sv_hash(b),hash) && .brohn_ar_supported(b),"Open the exact saved audio acoustic report in this project.")
  brohn_require(identical(b$id,r$id) && identical(b$dataset_id,p$dataset_id) && brohn_number(p$dataset_revision,1,1e9,TRUE),"The audio report lacks an exact original dataset revision.")
  .brohn_qexplorer_catalog(store,"dataset",p$dataset_id,p$dataset_revision,project_id)
  d<-brohn_get_entity(store,"dataset",p$dataset_id,p$dataset_revision)
  brohn_require(identical(d$body$modality,"audio") && identical(d$body$study_id,b$study_id) && identical(d$body$origin,b$origin),
    "Audio source, study identity or origin disagrees with this report.")
  if(is.null(b$study_id)) {
    brohn_require(is.null(p$design)&&is.null(p$design_hash)&&is.null(p$study_id)&&is.null(p$study_revision),"A standalone audio source cannot acquire an invented frozen study.")
  }else {
    brohn_require(identical(b$study_id,p$design$id)&&identical(p$study_id,b$study_id)&&identical(brohn_hash(p$design),p$design_hash)&&
      identical(p$design$project_id,project_id),"The saved audio study provenance disagrees with this project.")
    owner<-DBI::dbGetQuery(store$con,"SELECT project_id FROM entities WHERE kind='study' AND id=?",params=list(b$study_id))
    brohn_require(nrow(owner)==1L && identical(owner$project_id[[1L]],project_id),"The original study is unavailable in this project.")
  }
  brohn_require(identical(d$body$source$hash,p$source$hash) && identical(a$source$sha256,p$source$hash) &&
    identical(b$origin,p$origin) && identical(brohn_hash(d$body),p$dataset_hash) &&
    identical(brohn_hash(d$body$metadata),brohn_hash(p$mapping)),"The acoustic result disagrees with its original source or mapping.")
  parameters<-.brohn_ar_parameters(b)
  brohn_require(length(a$recordings)==1L && identical(a$recordings[[1L]]$status,"computed") &&
    identical(parameters$channel_mixing,"none") && identical(parameters$amplitude_reference,"digital full scale") &&
    identical(parameters$calibration_to_spl,FALSE),"This view requires one saved full-scale source channel without mixing.")
  rec<-a$recordings[[1L]]; channel<-parameters$channel_index
  header<-list(frames=rec$samples,sampling_rate=a$source$native_sampling_rate,channels=a$source$native_channels)
  brohn_require(brohn_number(header$frames,1,20000000,TRUE) && brohn_number(header$sampling_rate,64,384000,TRUE) &&
    brohn_number(header$channels,1,64,TRUE) && header$frames*header$channels<=20000000 &&
    brohn_number(channel,0,header$channels-1,TRUE) && identical(rec$channel,paste0("audio-",channel)) &&
    rec$sampling_rate==header$sampling_rate && identical(rec$unit,"FS"),"The saved audio header or selected channel is incomplete.")
  if(!is.null(d$body$metadata$channel_index))brohn_require(d$body$metadata$channel_index==channel,"The saved acoustic channel differs from its source mapping.")
  brohn_require(!is.null(b$result_object),"This audio report needs its retained original worker envelope before source review.")
  retained<-.brohn_sv_retained(store,r,"report",verify)
  path<-brohn_object_path(store,d$body$source$hash,verify=verify)
  size<-as.numeric(file.info(path)$size)
  brohn_require(brohn_number(size,1,512*1024^2,TRUE),"Audio review accepts a retained source up to 512 MiB.")
  header<-lapply(header,as.integer)
  lineage<-if(exists("brohn_audio_extraction_lineage",mode="function"))brohn_audio_extraction_lineage(store,d,verify)else NULL
  list(report=r,dataset=d,header=header,channel=as.integer(channel),source_path=path,
    extraction_lineage=lineage$binding,source_objects=c(list(list(hash=d$body$source$hash,bytes=size),retained),lineage$source_refs))
}
brohn_audio_review_selection <- function(source,start_s="0",end_s=NULL) {
  parameters<-.brohn_ar_parameters(source$report$body); rate<-source$header$sampling_rate
  if(is.null(end_s))end_s<-sub("\\.?0+$","",sprintf("%.9f",min(5,floor(source$header$frames/rate*1e9)/1e9)))
  list(channel_index=source$channel,start_s=start_s,end_s=end_s,
    frame_length_samples=as.integer(max(32,round(rate*parameters$spectral_frame_s))),
    frame_hop_samples=as.integer(max(1,round(rate*parameters$frame_step_s))))
}
brohn_prepare_audio_review <- function(store,report_id,revision,hash,project_id,start_s,end_s) {
  s<-brohn_audio_review_source(store,report_id,revision,hash,project_id,verify=FALSE)
  brohn_require(.brohn_ar_decimal(start_s)&&.brohn_ar_decimal(end_s)&&as.numeric(start_s)<as.numeric(end_s),"Enter increasing nonnegative decimal seconds.")
  selection<-brohn_audio_review_selection(s,start_s,end_s)
  brohn_require(as.numeric(end_s)<=s$header$frames/s$header$sampling_rate &&
    (as.numeric(end_s)-as.numeric(start_s))*s$header$sampling_rate<=2000000,"Choose a source interval containing at most two million samples.")
  request<-list(schema="brohn-audio-review-job/1.0",profile=.brohn_audio_review_profile,report=.brohn_ar_ref(s$report),dataset=.brohn_ar_ref(s$dataset),
    project_id=project_id,study_id=s$report$body$study_id,origin=s$report$body$origin,source_hash=s$dataset$body$source$hash,
    parameters_hash=brohn_hash(s$report$body$analysis$parameters),header=s$header,selection=selection)
  if(!is.null(s$extraction_lineage))request$extraction_lineage<-s$extraction_lineage
  request
}
brohn_queue_audio_review <- function(store,report_id,revision,hash,project_id,start_s,end_s,retry=FALSE) {
  r<-brohn_prepare_audio_review(store,report_id,revision,hash,project_id,start_s,end_s)
  brohn_enqueue_job(store,"audio_review",r,paste0("audio-review:",brohn_hash(r),if(retry)paste0(":",brohn_id("retry"))else""))
}
brohn_audio_review_input <- function(store,job,verify=TRUE) {
  r<-job$request
  brohn_fields(r,c("schema","profile","report","dataset","project_id","study_id","origin","source_hash","parameters_hash","header","selection"),"extraction_lineage",label="Audio review job")
  brohn_require(identical(job$operation,"audio_review")&&identical(r$schema,"brohn-audio-review-job/1.0")&&identical(r$profile,.brohn_audio_review_profile),"Choose a registered saved audio review.")
  expected<-brohn_prepare_audio_review(store,r$report$id,r$report$revision,r$report$hash,r$project_id,r$selection$start_s,r$selection$end_s)
  brohn_require(.brohn_sv_same(r,expected),"The audio review substituted its original report, source, channel, origin or settings.")
  s<-brohn_audio_review_source(store,r$report$id,r$report$revision,r$report$hash,r$project_id,verify)
  list(schema="brohn-analysis-input/1.0",operation="audio_review",binding=r,project_id=r$project_id,origin=r$origin,
    source_path=s$source_path,source_hash=r$source_hash,header=s$header,selection=lapply(r$selection,function(x)if(is.numeric(x))as.integer(x)else x),source_objects=s$source_objects)
}
brohn_validate_audio_review <- function(result,input) {
  checked_key<-digest::digest(list(result=result,input=input),algo="sha256",serialize=TRUE,serializeVersion=2)
  if(.brohn_ar_validated(checked_key))return(invisible(result))
  brohn_require(identical(result$schema,"brohn-audio-review-result/1.0")&&identical(result$profile,.brohn_audio_review_profile)&&
    .brohn_sv_same(result$binding,input$binding)&&.brohn_sv_same(result$selection,input$selection)&&identical(result$source_hash,input$source_hash)&&
    .brohn_sv_same(result$source[c("frames","sampling_rate","channels")],input$header)&&identical(result$source$unit,"FS")&&identical(result$source$channel_mixing,"none"),
    "Audio review changed its pinned source, header, settings or channel.")
  p<-result$parameters;s<-result$support;sel<-input$selection
  brohn_require(identical(p$window,"periodic Hann")&&identical(p$detrend,FALSE)&&identical(p$padding,"none")&&identical(p$resampling,"none")&&
    identical(p$spectrum,"one-sided power spectral density")&&identical(p$power_unit,"FS^2/Hz")&&identical(p$range,"start included; end excluded"),"Audio review changed its spectral method or units.")
  brohn_require(brohn_number(s$first_sample,0,input$header$frames-1,TRUE)&&brohn_number(s$stop_sample,s$first_sample+1,input$header$frames,TRUE)&&
    s$selected_samples==s$stop_sample-s$first_sample&&s$selected_samples<=2000000&&
    s$spectral_frames==max(0,1+floor((s$selected_samples-sel$frame_length_samples)/sel$frame_hop_samples))&&
    s$frequency_bins==floor(sel$frame_length_samples/2)+1&&s$spectral_cells==s$spectral_frames*s$frequency_bins&&s$spectral_cells<=2000000,
    "Audio review sample and spectral support do not reconcile.")
  # Decimal-to-sample conversion is authoritative in the native worker; allow
  # only floating representation tolerance in this independent boundary check.
  for(pair in list(c("first_sample","start_s"),c("stop_sample","end_s"))) {
    x<-as.numeric(sel[[pair[[2L]]]])*input$header$sampling_rate;n<-s[[pair[[1L]]]]
    brohn_require(n>=x-1e-7&&n<x+1,"Audio review changed the selected sample boundary.")
  }
  brohn_require(brohn_array(result$waveform)&&length(result$waveform)>0&&length(result$waveform)<=1000&&
    brohn_array(result$spectrogram)&&length(result$spectrogram)<=120,"Audio review exceeds its bounded display.")
  cursor<-s$first_sample
  for(w in result$waveform) {
    brohn_require(w$first_sample==cursor&&brohn_number(w$stop_sample,cursor+1,s$stop_sample,TRUE)&&w$samples==w$stop_sample-cursor&&
      brohn_number(w$minimum_fs)&&brohn_number(w$maximum_fs)&&w$minimum_fs<=w$maximum_fs&&
      brohn_number(w$minimum_sample,cursor,w$stop_sample-1,TRUE)&&brohn_number(w$maximum_sample,cursor,w$stop_sample-1,TRUE),"Waveform extrema lost their exact contiguous source positions.")
    cursor<-w$stop_sample
  }
  brohn_require(cursor==s$stop_sample,"Waveform display omitted selected source samples.")
  brohn_require(brohn_number(s$full_scale_or_exceeding_samples,0,s$selected_samples,TRUE)&&is.logical(s$exact_silence)&&length(s$exact_silence)==1L&&!is.na(s$exact_silence),"Audio source quality support is incomplete.")
  frame_cursor<-0;cells<-0;rate<-input$header$sampling_rate;frame<-sel$frame_length_samples;hop<-sel$frame_hop_samples
  near<-function(a,b)brohn_number(a)&&abs(a-b)<=1e-10*max(1,abs(b))
  for(t in result$spectrogram) {
    brohn_require(t$first_frame==frame_cursor&&brohn_number(t$stop_frame,frame_cursor+1,s$spectral_frames,TRUE)&&length(t$cells)<=80&&length(t$cells)>0,
      "Spectrum display changed its native frame coverage.")
    brohn_require(near(t$start_s,(s$first_sample+t$first_frame*hop)/rate)&&near(t$end_s,(s$first_sample+(t$stop_frame-1)*hop+frame)/rate)&&
      near(t$plot_left_s,(s$first_sample+t$first_frame*hop+frame/2-hop/2)/rate)&&near(t$plot_right_s,(s$first_sample+(t$stop_frame-1)*hop+frame/2+hop/2)/rate),"Spectrum display substituted its source time geometry.")
    bin_cursor<-0
    for(c in t$cells){brohn_require(c$first_bin==bin_cursor&&brohn_number(c$stop_bin,bin_cursor+1,s$frequency_bins,TRUE)&&
      c$source_cells==(t$stop_frame-frame_cursor)*(c$stop_bin-bin_cursor)&&brohn_number(c$mean_power_fs2_per_hz,0)&&
      near(c$lowest_hz,c$first_bin*rate/frame)&&near(c$highest_hz,(c$stop_bin-1)*rate/frame),"Spectrum cells lost their original frequency/frame support.")
      cells<-cells+c$source_cells;bin_cursor<-c$stop_bin}
    brohn_require(bin_cursor==s$frequency_bins,"Spectrum display omitted frequency bins.");frame_cursor<-t$stop_frame
  }
  brohn_require(frame_cursor==s$spectral_frames&&cells==s$spectral_cells&&length(result$artifacts)==2L,"Spectrum display or export support is incomplete.")
  for(i in 1:2){a<-result$artifacts[[i]];brohn_require(identical(a$kind,c("audio-source-samples","audio-source-spectrum")[[i]])&&
    identical(a$filename,c("audio-samples.csv","audio-spectrum.csv")[[i]])&&a$rows==c(s$selected_samples,s$spectral_cells)[[i]]&&
    brohn_number(a$bytes,1,128*1024^2,TRUE)&&brohn_text(a$hash,64)&&grepl("^[a-f0-9]{64}$",a$hash),"Audio exports require complete exact byte and row receipts.")}
  .brohn_ar_validated(checked_key,TRUE);invisible(result)
}
brohn_analyse_audio_review <- function(input,scratch) {
  directory<-file.path(scratch,"artifacts");brohn_require(dir.create(directory),"Cannot prepare a new audio review directory.")
  request<-list(schema="brohn-audio-review-request/1.0",profile=.brohn_audio_review_profile,binding=input$binding,
    source_path=input$source_path,source_hash=input$source_hash,header=lapply(input$header,as.integer),selection=input$selection,
    output_directory=normalizePath(directory,winslash="/",mustWork=TRUE))
  rp<-file.path(scratch,"audio-request.json");out<-file.path(scratch,"audio-result.json");brohn_write_json_file(request,rp)
  child<-processx::run(brohn_python_profile("audio"),c("scripts/workers/audio_review.py","--request",rp,"--output",out),
    timeout=15*60,error_on_status=FALSE,cleanup_tree=TRUE,windows_hide_window=TRUE)
  brohn_require(file.exists(out),paste("Audio review returned no result.",substr(child$stderr,1,500)))
  result<-brohn_read_json_file(out);brohn_require(child$status==0&&!identical(result$status,"error"),paste("Audio review needs attention:",result$error$message))
  brohn_validate_audio_review(result,input);list(audio_review=result)
}
brohn_publish_audio_review <- function(store,output,scratch,job,input,output_path) {
  brohn_require(!RSQLite::sqliteIsTransacting(store$con),"Publish audio review outside an enclosing writer transaction.")
  .brohn_publication_output_identity(output,.brohn_audio_review_loaded);.brohn_publication_job(store,job)
  if(!is.null(input$binding$extraction_lineage))
    .brohn_publication_output_identity(output,.brohn_audio_extraction_loaded["R/platform-audio-extraction.R"])
  guards<-brohn_hold_signal_value_sources(store,input);on.exit(for(g in guards).brohn_qexplorer_release(g),add=TRUE)
  brohn_require(.brohn_sv_same(input,brohn_audio_review_input(store,job))&&.brohn_sv_same(brohn_read_json_file(output_path),output),"The audio source or worker output changed before publication.")
  result<-output$report$audio_review;brohn_validate_audio_review(result,input)
  csv<-document<-NULL;committed<-FALSE
  on.exit({if(!is.null(document))brohn_close_publication(document$guard,committed);if(!is.null(csv))brohn_close_publication(csv$guard,committed)},add=TRUE)
  specs<-lapply(result$artifacts,function(a)list(key=a$kind,kind=a$kind,
    path=brohn_checked_artifact_path(store,file.path(scratch,"artifacts",a$filename),scratch),sha256=a$hash,bytes=a$bytes,media_type="text/csv"))
  csv<-.brohn_publication_stage(store,job,specs);id<-paste0("audio-review-",job$id)
  body<-list(schema="brohn-saved-audio-review/1.0",id=id,report_id=input$binding$report$id,dataset_id=input$binding$dataset$id,study_id=input$binding$study_id,
    origin=input$origin,request=job$request,result=result,csv_objects=lapply(seq_along(csv$descriptors),function(i)c(list(kind=result$artifacts[[i]]$kind),csv$descriptors[[i]][c("hash","size","media_type")])),
    created_at=brohn_now(),processing=list(job_id=job$id,attempt=job$attempt,worker_output_hash=digest::digest(file=output_path,algo="sha256"),code_hashes=output$code_identity))
  document<-.brohn_publication_stage_json(store,job,body,file.path(scratch,"published-audio-review.json"))
  receipt<-brohn_store_batch(store,function(){
    brohn_require(.brohn_sv_same(input,brohn_audio_review_input(store,job,verify=FALSE)),"Audio source authority changed before publication.")
    for(g in guards).Call(g$native$check,g$pointer)
    .brohn_publication_register(store,csv);body$result_object<-.brohn_publication_register(store,document)[[1L]][c("hash","size","media_type")]
    brohn_put_entity(store,"audio_review",id,body,project_id=input$project_id)
    brohn_complete_job(store,job$id,job$worker,job$token,list(audio_review_id=id,report_id=body$report_id,dataset_id=body$dataset_id,output_hash=body$result_object$hash))})
  committed<-TRUE;receipt
}
brohn_audio_review_record <- function(store,id,report_id,project_id,verify=FALSE) {
  r<-brohn_get_entity(store,"audio_review",id)
  brohn_require(!is.null(r)&&identical(r$project_id,project_id)&&identical(r$body$report_id,report_id),"Open an audio review belonging to this report and project.")
  .brohn_qexplorer_catalog(store,"audio_review",id,r$revision,project_id)
  input<-brohn_audio_review_input(store,list(operation="audio_review",request=r$body$request),verify)
  brohn_validate_audio_review(r$body$result,input)
  brohn_require(length(r$body$csv_objects)==2L,"The saved audio view has incomplete exact exports.")
  for(i in 1:2){a<-r$body$result$artifacts[[i]];o<-r$body$csv_objects[[i]]
    brohn_require(identical(o$kind,a$kind)&&identical(o$hash,a$hash)&&o$size==a$bytes,"The saved audio export changed its source artifact.")}
  if(verify).brohn_sv_retained(store,r,"audio_review",TRUE)
  r
}

# Independent source binding and visual contract tests; no acoustic rescoring.
source("R/platform-load.R",encoding="UTF-8");brohn_load(ui=TRUE)
source("R/platform-audio-review.R",encoding="UTF-8");source("R/platform-audio-review-views.R",encoding="UTF-8")
args<-commandArgs(trailingOnly=TRUE)
folder<-if(length(args))normalizePath(args[[1]],winslash="/",mustWork=TRUE)else tempfile("brohn-audio-domain-")
dir.create(folder,recursive=TRUE,showWarnings=FALSE)
checks<-character();check<-function(label,value){stopifnot(isTRUE(value));checks<<-c(checks,label);cat("PASS",label,"\n")}
rejects<-function(expr)inherits(try(force(expr),silent=TRUE),"try-error")
local({
  store<-brohn_open_store(file.path(folder,"workspace"));on.exit(brohn_close_store(store),add=TRUE);brohn_initialise_library(store)
  design<-brohn_new_design("Original source audio review fixture",id="qa-audio-source");study<-brohn_put_entity(store,"study",design$id,design)
  # PCM16 source written directly, without SoundFile or the production decoder.
  fs<-8000L;values<-rep(c(0L,8192L,0L,-8192L),6000L);wav<-file.path(folder,"original-square-cycle.wav")
  con<-file(wav,"wb");writeChar("RIFF",con,eos=NULL);writeBin(as.integer(36+2*length(values)),con,size=4,endian="little")
  writeChar("WAVEfmt ",con,eos=NULL);writeBin(16L,con,size=4,endian="little");writeBin(c(1L,1L),con,size=2,endian="little")
  writeBin(c(fs,fs*2L),con,size=4,endian="little");writeBin(c(2L,16L),con,size=2,endian="little");writeChar("data",con,eos=NULL)
  writeBin(as.integer(2*length(values)),con,size=4,endian="little");writeBin(values,con,size=2,endian="little");close(con)
  d<-brohn_ingest_dataset(store,wav,"Original PCM16 cycle","audio",study_id=design$id,origin="sample")
  mapping<-list(unit="FS",channel_index=0L,origin_statement="Original synthetic PCM16; no human recording or measured acoustic claim.",
    parameters=list(recipe="audio-praat-acoustics/1.0",pitch_floor_hz=75,pitch_ceiling_hz=600,frame_step_s=.01,spectral_frame_s=.025))
  d<-brohn_curate_dataset(store,d$id,mapping,d$revision)
  analysis<-list(kind="audio",parameters=list(`recording-1`=c(mapping$parameters,list(channel_index=0L,channel_mixing="none",amplitude_reference="digital full scale",calibration_to_spl=FALSE))),
    source=list(sha256=d$body$source$hash,native_sampling_rate=8000,native_channels=1L),
    recordings=list(list(status="computed",recording_id="recording-1",channel="audio-0",samples=24000L,sampling_rate=8000,unit="FS")))
  body<-list(id="report-qa-audio",study_id=design$id,dataset_id=d$id,title="Original synthetic saved contract",origin="sample",
    provenance=brohn_analysis_provenance(d$body,d$revision,study$body,study$revision),analysis=analysis)
  body$result_object<-brohn_store_object(store,bytes=charToRaw(brohn_json(list(schema="brohn-analysis-output/1.0",report=body))),media_type="application/json")
  r<-brohn_put_entity(store,"report",body$id,body,project_id=study$project_id)
  original_hash<-brohn_hash(r$body);source_hash<-digest::digest(file=wav,algo="sha256")
  src<-brohn_audio_review_source(store,r$id,r$revision,original_hash,r$project_id)
  check("Original report, dataset revision, channel and integer header are bound",src$channel==0L&&all(vapply(src$header,is.integer,logical(1))))
  sel<-brohn_audio_review_selection(src);check("Default window uses original duration and saved frame/hop settings",identical(sel$end_s,"3")&&sel$frame_length_samples==200L&&sel$frame_hop_samples==80L)
  req<-brohn_prepare_audio_review(store,r$id,r$revision,original_hash,r$project_id,"0","0.5")
  job<-list(operation="audio_review",request=req);input<-brohn_audio_review_input(store,job)
  check("Job preparation includes both original recording and retained report objects",length(input$source_objects)==2L)
  for(field in c("origin","source_hash","parameters_hash")){bad<-job;bad$request[[field]]<-"changed";check(paste("Substituted",field,"is refused"),rejects(brohn_audio_review_input(store,bad)))}
  for(field in c("channel_index","frame_length_samples","frame_hop_samples")){bad<-job;bad$request$selection[[field]]<-1+bad$request$selection[[field]];check(paste("Substituted",field,"is refused"),rejects(brohn_audio_review_input(store,bad)))}
  check("Negative and nondecimal windows are refused",rejects(brohn_prepare_audio_review(store,r$id,r$revision,original_hash,r$project_id,"-1","1"))&&rejects(brohn_prepare_audio_review(store,r$id,r$revision,original_hash,r$project_id,"0","1e-2")))
  check("Beyond-source windows are refused",rejects(brohn_prepare_audio_review(store,r$id,r$revision,original_hash,r$project_id,"0","4")))
  check("Foreign project cannot resolve the audio report",rejects(brohn_audio_review_source(store,r$id,r$revision,original_hash,"foreign")))
  scratch<-file.path(folder,"native-review");dir.create(scratch)
  result<-brohn_analyse_audio_review(input,scratch)$audio_review
  check("Actual native worker returns exact selected support and saved channel",result$support$selected_samples==4000&&result$selection$channel_index==0&&result$source$unit=="FS")
  samples<-utils::read.csv(file.path(scratch,"artifacts","audio-samples.csv"))
  check("Complete decoded PCM16 samples match independent original integer arithmetic",nrow(samples)==4000&&identical(samples$source_sample_index,0:3999)&&all(samples$amplitude_fs==values[1:4000]/32768))
  check("Native spectrum full row count agrees with complete window arithmetic",result$support$spectral_frames==48&&result$support$spectral_cells==48*101)
  for(field in c("source_hash","profile")){bad<-result;bad[[field]]<-"changed";check(paste("Returned",field,"substitution fails publication validation"),rejects(brohn_validate_audio_review(bad,input)))}
  bad<-result;bad$waveform[[1]]$minimum_sample<-999999;check("Waveform extrema cannot leave their source bin",rejects(brohn_validate_audio_review(bad,input)))
  bad<-result;bad$spectrogram[[1]]$plot_left_s<-99;check("Spectrogram display geometry cannot drift from source frames",rejects(brohn_validate_audio_review(bad,input)))
  bad<-result;bad$spectrogram[[1]]$cells[[1]]$source_cells<-99;check("Spectrogram aggregation denominators remain checked",rejects(brohn_validate_audio_review(bad,input)))
  DBI::dbExecute(store$con,"UPDATE entities SET project_id='foreign-audio-qa' WHERE kind='dataset' AND id=?",params=list(d$id))
  moved_refused<-rejects(brohn_audio_review_input(store,job,verify=FALSE))
  DBI::dbExecute(store$con,"UPDATE entities SET project_id=? WHERE kind='dataset' AND id=?",params=list(d$project_id,d$id))
  check("Warm structural validation never bypasses current source ownership",moved_refused)
  for(kind in c("waveform","spectrum")){svg<-brohn_audio_review_svg(result,kind);small<-brohn_audio_review_svg(result,kind,320L)
    check(paste(kind,"SVG retains exact binding and has distinct desktop/mobile accessibility IDs"),grepl(input$source_hash,svg,fixed=TRUE)&&grepl(paste0("ar-",kind,"-920-title"),svg,fixed=TRUE)&&grepl(paste0("ar-",kind,"-320-title"),small,fixed=TRUE))
    writeLines(svg,file.path(folder,paste0(kind,".svg")),useBytes=TRUE)}
  short_req<-brohn_prepare_audio_review(store,r$id,r$revision,original_hash,r$project_id,"0","0.001")
  short_input<-brohn_audio_review_input(store,list(operation="audio_review",request=short_req));short_dir<-file.path(folder,"short-review");dir.create(short_dir)
  short<-brohn_analyse_audio_review(short_input,short_dir)$audio_review
  check("Short selection keeps all eight samples and an explicit empty spectrum",short$support$selected_samples==8&&short$support$spectral_cells==0&&length(short$spectrogram)==0&&grepl("No complete spectral frame",brohn_audio_review_svg(short,"spectrum"),fixed=TRUE))
  check("Numerical alternatives keep all display bins at round-trip precision",length(.brohn_ar_rows(result,"waveform"))==length(result$waveform)&&length(.brohn_ar_rows(result,"spectrum"))==sum(vapply(result$spectrogram,function(t)length(t$cells),integer(1))))
  check("Review does not change original source, report or create scoring jobs",identical(original_hash,brohn_hash(brohn_get_entity(store,"report",r$id)$body))&&identical(source_hash,digest::digest(file=wav,algo="sha256"))&&length(brohn_list_jobs(store))==0L)
  standalone<-brohn_ingest_dataset(store,wav,"Original standalone audio","audio",origin="sample")
  standalone<-brohn_curate_dataset(store,standalone$id,mapping,standalone$revision)
  sb<-body;sb$id<-"report-qa-standalone";sb$study_id<-NULL;sb$dataset_id<-standalone$id;sb$result_object<-NULL
  sb$provenance<-brohn_analysis_provenance(standalone$body,standalone$revision)
  sb$result_object<-brohn_store_object(store,bytes=charToRaw(brohn_json(list(schema="brohn-analysis-output/1.0",report=sb))),media_type="application/json")
  sr<-brohn_put_entity(store,"report",sb$id,sb,project_id=standalone$project_id)
  ss<-brohn_audio_review_source(store,sr$id,sr$revision,brohn_hash(sr$body),sr$project_id)
  check("Standalone Data-library audio retains absent study and exact project/source",is.null(ss$report$body$study_id)&&identical(ss$dataset$id,standalone$id))
  invented<-sb;invented$id<-"report-qa-invented-study";invented$provenance$design<-study$body;ir<-brohn_put_entity(store,"report",invented$id,invented,project_id=sr$project_id)
  check("Standalone audio cannot silently acquire a frozen study",rejects(brohn_audio_review_source(store,ir$id,ir$revision,brohn_hash(ir$body),ir$project_id)))
  brohn_write_json_file(list(passed=TRUE,checks=as.list(checks),source_hash=source_hash,report_hash=original_hash,
    code_hashes=.brohn_audio_review_loaded,scope="Original synthetic saved-contract and direct native review; no saved scientific job or human acoustic validity claim."),file.path(folder,"results.json"))
  cat(length(checks),"audio review domain checks passed\n")
})

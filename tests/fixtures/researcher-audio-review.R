# Original PCM16 audio fixtures; no person, microphone or external media.
args<-commandArgs(trailingOnly=TRUE);stopifnot(length(args)>=2L)
mode<-args[[1]];folder<-normalizePath(args[[2]],winslash="/",mustWork=TRUE)
stopifnot(startsWith(basename(folder),"brohn-audio-browser-"))
source("R/platform-load.R",encoding="UTF-8");brohn_load(ui=TRUE)
config_path<-file.path(folder,"fixture.json")
if(mode=="serve") {
  config<-brohn_read_json_file(config_path);Sys.setenv(BROHN_WORKSPACE=config$workspace,BROHN_APP_MODE="platform")
  stop_owned<-function()if(file.exists(file.path(folder,"stop.request")))shiny::stopApp()else later::later(stop_owned,.2)
  later::later(stop_owned,.2);shiny::runApp(".",host="127.0.0.1",port=config$port,launch.browser=FALSE)
}else local({
  store<-brohn_open_store(file.path(folder,"workspace"));on.exit(brohn_close_store(store),add=TRUE)
  if(mode=="setup") {
    stopifnot(!file.exists(config_path));brohn_initialise_library(store)
    design<-brohn_new_design("Original audio researcher acceptance",id="qa-audio-browser");brohn_put_entity(store,"study",design$id,design)
    write_wave<-function(file,columns,rate) {
      values<-as.integer(t(do.call(cbind,columns)));channels<-length(columns)
      con<-file(file,"wb");on.exit(close(con));writeChar("RIFF",con,eos=NULL);writeBin(as.integer(36+2*length(values)),con,size=4,endian="little")
      writeChar("WAVEfmt ",con,eos=NULL);writeBin(16L,con,size=4,endian="little");writeBin(c(1L,channels),con,size=2,endian="little")
      writeBin(as.integer(c(rate,rate*2*channels)),con,size=4,endian="little");writeBin(as.integer(c(2*channels,16)),con,size=2,endian="little")
      writeChar("data",con,eos=NULL);writeBin(as.integer(2*length(values)),con,size=4,endian="little");writeBin(values,con,size=2,endian="little")
    }
    rate<-8000L;n<-24000L;time<-(0:(n-1))/rate
    left<-as.integer(round(4096*cos(2*pi*125*time)));right<-as.integer(round(16384*sin(2*pi*250*time)));right[[51]]<-29491L
    source_files<-list(tone=file.path(folder,"original-stereo.wav"),silence=file.path(folder,"original-silence.wav"))
    write_wave(source_files$tone,list(left,right),rate);write_wave(source_files$silence,list(rep(0L,n)),rate)
    jobs<-datasets<-hashes<-list()
    for(kind in names(source_files)){
      d<-brohn_ingest_dataset(store,source_files[[kind]],paste("Original audio",kind),"audio",study_id=if(kind=="tone")design$id else NULL,origin="sample")
      d<-brohn_curate_dataset(store,d$id,list(unit="FS",channel_index=if(kind=="tone")1L else 0L,
        origin_statement="Original generated PCM16 acceptance fixture. No human or microphone recording.",
        parameters=list(recipe="audio-praat-acoustics/1.0",pitch_floor_hz=75,pitch_ceiling_hz=600,frame_step_s=.01,spectral_frame_s=.025)),d$revision)
      j<-brohn_queue_dataset(store,d$id);jobs[[kind]]<-j$id;datasets[[kind]]<-d$id;hashes[[kind]]<-d$body$source$hash
    }
    brohn_write_json_file(list(workspace=store$root,port=as.integer(Sys.getenv("BROHN_AUDIO_TEST_PORT","3923")),study_id=design$id,
      jobs=jobs,datasets=datasets,sources=source_files,source_hashes=hashes,expected=list(rate=rate,samples=n,tone_channel=1L,
      transient_sample=50L,transient_fs=29491/32768,frame_length=200L,frame_hop=80L)),config_path)
  }else if(mode=="seed") {
    config<-brohn_read_json_file(config_path);reports<-list()
    repeat{j<-brohn_claim_job(store,"audio-original-fixture",300);if(is.null(j))break;brohn_process_job(store,j,timeout_seconds=300)}
    for(kind in names(config$jobs)){j<-brohn_get_job(store,config$jobs[[kind]]);stopifnot(j$status=="succeeded")
      r<-brohn_get_entity(store,"report",j$result$report_id);stopifnot(.brohn_ar_supported(r$body))
      reports[[kind]]<-list(id=r$id,revision=r$revision,hash=brohn_hash(r$body))}
    config$reports<-reports;brohn_write_json_file(config,config_path);cat("PASS two original sources published by actual acoustic workers\n")
  }else if(mode=="inspect") {
    config<-brohn_read_json_file(config_path)
    brohn_write_json_file(list(reports=lapply(config$reports,function(ref){r<-brohn_get_entity(store,"report",ref$id);list(id=r$id,hash=brohn_hash(r$body),unchanged=identical(ref$hash,brohn_hash(r$body)))}),
      reviews=brohn_list_entities(store,"audio_review"),signals=brohn_list_entities(store,"signal_view"),jobs=brohn_list_jobs(store)),file.path(folder,"snapshot.json"))
  }else if(mode=="worker") {
    while(!file.exists(file.path(folder,"stop.worker"))){j<-brohn_claim_job(store,"audio-browser-fixture",90);if(is.null(j))Sys.sleep(.2)else {
      brohn_process_job(store,j,timeout_seconds=300);cat(brohn_json(list(id=j$id,status=brohn_get_job(store,j$id)$status)),"\n")}}
  }else stop("Unknown audio review fixture mode")
})

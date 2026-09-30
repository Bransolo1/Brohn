# Generate synthetic originals through genuine ingestion and scientific workers.
# This phase occurs before any saved-display/report export preparation.
args<-commandArgs(TRUE);stopifnot(length(args)==2L)
repo<-normalizePath(args[[1L]],winslash="/",mustWork=TRUE)
out<-args[[2L]];stopifnot(!file.exists(out));dir.create(out,recursive=TRUE);out<-normalizePath(out,winslash="/",mustWork=TRUE)
cfg<-list(checkout=repo,out=out)
setwd(repo);source("R/platform-load.R",encoding="UTF-8");brohn_load(ui=FALSE)
local({
 out<-cfg$out;checks<-list();passed<-FALSE;failure<-NULL;reports<-list();datasets<-list()
 check<-function(name,value){if(!isTRUE(value))stop(name,call.=FALSE);checks[[length(checks)+1L]]<<-name;cat("PASS",name,"\n")}
 same<-function(a,b)identical(brohn_json(a),brohn_json(b))
 ref<-function(r)list(kind=r$kind,id=r$id,revision=r$revision,body_hash=brohn_hash(r$body),project_id=r$project_id)
 store<-brohn_open_store(file.path(out,"workspace"));brohn_initialise_library(store)
 on.exit({
   for(j in brohn_list_jobs(store))if(j$status %in% c("queued","running"))brohn_cancel_job(store,j$id)
   objects<-DBI::dbGetQuery(store$con,"SELECT * FROM objects ORDER BY hash")
   brohn_write_json_file(list(schema="brohn-eda-original-source-corpus/0.1",passed=passed,checks=checks,failure=failure,
     reports=lapply(reports,ref),datasets=lapply(datasets,ref),
     jobs=lapply(brohn_list_jobs(store),function(j)j[c("id","operation","status","attempt","error","result")]),
     objects=lapply(seq_len(nrow(objects)),function(i)as.list(objects[i,,drop=FALSE])),
     scope="Original synthetic CSV sources, actual async ingestion and unchanged scientific child publication; no display/export workers, browser, device or construct qualification."),file.path(out,"results.json"))
   brohn_close_store(store)
 },add=TRUE)
 tryCatch({
  runjob<-function(job){force(job);claim<-brohn_claim_job(store,"eda-original-source-corpus",lease_seconds=120L)
   stopifnot(!is.null(claim),identical(job$id,claim$id));brohn_process_job(store,claim,timeout_seconds=300L)
   done<-brohn_get_job(store,job$id);if(done$status!="succeeded")stop("Original worker failed: ",brohn_json(done$error));done}
  study<-brohn_create_study(store,"Original synthetic EDA and liking comparison", "comparison")
  design<-study$body;design$description<-"Synthetic source preservation and report software qualification. No human participant or physical device recording."
  design$measures<-list("eda","questionnaire");design$questions[[1L]]$prompt<-"How much do you like this synthetic concept?"
  study<-brohn_save_study(store,design,study$revision);brohn_write_json_file(study,file.path(out,"study.json"))
  ingest_analyse<-function(name,modality,path,mapping){
    upload<-file.path(tempdir(),paste0("eda-corpus-upload-",name,".csv"));stopifnot(!file.exists(upload),file.copy(path,upload,copy.mode=FALSE))
    pending<-brohn_queue_ingestion(store,list(path=upload,name=basename(path),size=as.numeric(file.info(upload)$size),reference=paste0("original-",name)),
      paste("Original synthetic",name),modality,"sample",study$id,operation_id=paste0("original-",name))
    intake<-runjob(brohn_get_job(store,pending$body$job_id));d<-brohn_get_entity(store,"dataset",intake$result$dataset_id)
    d<-brohn_curate_dataset(store,d$id,mapping,d$revision,study$id,study$revision);datasets[[name]]<<-d
    done<-runjob(brohn_queue_dataset(store,d$id,revision=d$revision));r<-brohn_get_entity(store,"report",done$result$report_id);reports[[name]]<<-r
    brohn_write_json_file(d,file.path(out,paste0(name,"-dataset.json")));brohn_write_json_file(r,file.path(out,paste0(name,"-report.json")))
    dir.create(file.path(out,name));for(a in r$body$analysis$artifacts){p<-brohn_object_path(store,brohn_default(a$hash,a$sha256),TRUE)
      stopifnot(file.copy(p,file.path(out,name,paste0(a$kind,".ndjson")),copy.mode=FALSE))}
    envelope<-brohn_read_json_file(brohn_object_path(store,r$body$result_object$hash,TRUE),maximum=16*1024^2)
    check(paste(name,"exact original worker envelope and native publication"),same(envelope$report,r$body[setdiff(names(r$body),"result_object")])&&isTRUE(r$body$processing$publication$native_seal))
    check(paste(name,"original source and exact saved study binding"),r$body$provenance$source$hash==digest::digest(file=path,algo="sha256")&&r$body$provenance$design_hash==brohn_hash(study$body)&&r$body$study_id==study$id)
    r
  }
  t<-(0:4499)/25;dt<-pmax(t-21,0);signal<-5+.0002*t+exp(-dt/2)-exp(-dt/.7);signal[3001]<-NA
  events<-data.frame(time=c(20,70,100,104,121,175),code=c("A","B","A","B","A","B"),exposure=c("responder","nonresponse","overlap-a","overlap-b","gap","edge"))
  onset<-exposure<-rep("",length(t));for(i in seq_len(nrow(events))){row<-events$time[[i]]*25+1;onset[[row]]<-events$code[[i]];exposure[[row]]<-events$exposure[[i]]}
  path<-file.path(out,"event-original.csv");utils::write.csv(data.frame(time=t,participant="0001",session="00001",conductance=signal,onset=onset,exposure=exposure),path,row.names=FALSE,na="NA",fileEncoding="UTF-8")
  p<-list(recipe="eda-event-highpass/1.0",event_codes=list(A="condition-a",B="condition-b"),nuisance_codes=list(),
    event_source="Synthetic measured markers on the same25Hz source clock; no device timing claim.",settings_source="Synthetic software fixture; not recommended research thresholds.",
    baseline_s=list(-2,0),response_s=list(0,6),onset_latency_s=list(.5,4),recovery_end_s=10,nuisance_effect_s=list(0,10),
    overlap_policy="exclude",response_selection="first_onset",minimum_scr_amplitude_us=.05,relative_prominence=.1,edge_exclusion_s=10,minimum_segment_s=40)
  m<-list(time_column="time",time_unit="s",sampling_rate=25,participant_column="participant",session_column="session",value_columns=list("conductance"),unit="uS",
    event_column="onset",exposure_column="exposure",parameters=p,origin_statement="Original synthetic event conductance with response, nonresponse, overlap, missing sample and filter-edge witnesses.")
  event<-ingest_analyse("event","eda",path,m);a<-event$body$analysis
  ecell<-function(exposure)Filter(function(x)identical(x$exposure_id,exposure),a$recordings)[[1L]]
  efeat<-function(exposure,name)Filter(function(x)identical(x$exposure_id,exposure)&&identical(x$name,name),a$features)[[1L]]
  check("event has six exact cells and complete4499 rows beyond preview",length(a$recordings)==6L&&length(a$features)==78L&&length(a$artifacts)==2L&&a$artifacts[[1L]]$rows==4499L&&length(a$series)<4499L)
  check("event supported nonresponse preserves zero magnitude and null responder amplitude",isTRUE(ecell("nonresponse")$nonresponse)&&efeat("nonresponse","scr_response_magnitude")$value==0&&is.null(efeat("nonresponse","scr_responder_amplitude")$value))
  check("event overlap gap and edge preserve distinct unavailable support",ecell("overlap-a")$reason=="ambiguous_overlapping_events"&&!isTRUE(ecell("gap")$baseline_support$complete)&&ecell("edge")$status=="unavailable")
  t<-(0:4300)/10;signal<-4+.001*t
  for(onset in seq(3,429,6)){dt<-t-onset;signal<-signal+ifelse(dt>=0,exp(-pmax(dt,0)/1.8)-exp(-pmax(dt,0)/.4),0)}
  signal[c(3601L,4251L)]<-NA
  path<-file.path(out,"continuous-original.csv");utils::write.csv(data.frame(time=t,participant="0001",session="00002",conductance=signal/1e6),path,row.names=FALSE,na="NA",fileEncoding="UTF-8")
  m<-list(time_column="time",time_unit="s",sampling_rate=10,participant_column="participant",session_column="session",value_columns=list("conductance"),unit="S",
    parameters=list(recipe="eda-neurokit-highpass/1.0"),origin_statement="Original synthetic conductance in siemens; missing samples at360 and425seconds preserve distinct processed segments and a short unavailable segment.")
  continuous<-ingest_analyse("continuous","eda",path,m);a<-continuous$body$analysis
  check("continuous original retains computed and unavailable segments",length(a$recordings)==3L&&a$quality$computed_channel_segments==2L&&a$quality$unavailable_channel_segments==1L&&a$status=="partial")
  check("continuous conversion and complete artifact evidence retained",all(vapply(a$recordings,function(x)x$unit=="uS"&&x$source_unit=="S"&&x$scale_factor==1e6,logical(1)))&&length(a$artifacts)==2L&&a$quality$complete_processed_artifacts&&!a$quality$raw_source_duplicated)
  check("continuous preview is distinct from complete rows",a$artifacts[[1L]]$rows>a$quality$series_samples_displayed&&a$quality$event_records_total>50L)
  liking<-data.frame(person=c("0001","0001","0002","0002"),visit=c("00001","00001","00003","00003"),question="q-liking",
    stimulus=rep(c("stimulus-a","stimulus-b"),2),condition=rep(c("condition-a","condition-b"),2),exposure=paste0("rating-",1:4),value=c("2","6","3",""))
  path<-file.path(out,"liking-original.csv");utils::write.csv(liking,path,row.names=FALSE,na="",fileEncoding="UTF-8")
  m<-list(participant_column="person",session_column="visit",question_column="question",stimulus_column="stimulus",condition_column="condition",exposure_column="exposure",
    value_columns=list("value"),unit="numeric_rating",origin_statement="Original synthetic explicit ratings. Matching text labels do not by themselves establish cross-report identity equivalence.")
  r<-ingest_analyse("liking","questionnaire",path,m);a<-r$body$analysis
  check("liking original preserves three ratings and one explicit missing",length(a$observations)==4L&&same(lapply(a$observations,`[[`,"value"),list(2,6,3,NULL))&&a$quality$missing_response_count==1L)
  check("liking original paired estimate remains one person with null interval",length(a$contrasts)==1L&&a$contrasts[[1L]]$estimate==4&&a$contrasts[[1L]]$participant_count==1L&&is.null(a$contrasts[[1L]]$interval95))
  check("three originals share one exact saved study without a constructed crosswalk",length(unique(vapply(reports,function(r)r$body$study_id,character(1))))==1L&&all(vapply(reports,function(r)is.null(r$body$provenance$crosswalk),logical(1))))
  jobs<-brohn_list_jobs(store);check("six actual original ingestion and science jobs settle before adapter work",length(jobs)==6L&&sum(vapply(jobs,function(j)j$operation=="ingest_source",logical(1)))==3L&&sum(vapply(jobs,function(j)j$operation=="analyse_dataset",logical(1)))==3L&&all(vapply(jobs,function(j)j$status=="succeeded",logical(1))))
  brohn_write_json_file(list(event=list(source_rows=4500,complete_samples=4499,cells=6,features=78,nonresponse_magnitude=0,responder_amplitude=NULL),
    continuous=list(source_rows=4301,computed_segments=2,unavailable_segments=1,source_unit="S",unit="uS",scale_factor=1e6),
    liking=list(values=list(2,6,3,NULL),paired_difference=4,people=1,interval95=NULL),
    linkage="Matching source labels are not a cross-report identity proof. No multimodal estimate constructed."),file.path(out,"expected-witnesses.json"))
  passed<-TRUE
 },error=function(e){failure<<-conditionMessage(e);stop(e)})
 cat("Original EDA corpus:",length(checks),"checks passed\n")
})

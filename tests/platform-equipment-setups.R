# Original source metadata -> immutable workspace setup -> two independent study
# requests. Offline generated declarations; no subscription or physical device.
source("R/platform-load.R",encoding="UTF-8");brohn_load(ui=FALSE)
local({
  root<-tempfile("brohn-equipment-setup-");dir.create(root);store<-brohn_open_store(file.path(root,"w"));brohn_initialise_library(store)
  on.exit({brohn_close_store(store);actual<-normalizePath(root,winslash="/",mustWork=FALSE)
    stopifnot(startsWith(tolower(actual),paste0(tolower(normalizePath(tempdir(),winslash="/")),"/")),startsWith(basename(actual),"brohn-equipment-setup-"));unlink(actual,recursive=TRUE)},add=TRUE)
  checks<-0L;check<-function(name,ok){if(!isTRUE(ok))stop("Equipment setup QA: ",name);checks<<-checks+1L;cat("PASS ",name,"\n",sep="")}
  rejects<-function(expr)inherits(try(force(expr),silent=TRUE),"try-error")
  path<-file.path(root,"metadata.json");processx::run(.brohn_acq_python(),c("tests/acquisition/equipment_metadata.py","--fixture",path),error_on_status=TRUE,windows_hide_window=TRUE)
  streams<-brohn_read_json_file(path);first<-brohn_create_study(store,"Original setup study one");second<-brohn_create_study(store,"Original setup study two")
  discovery<-function(study,observed) {
    d<-brohn_queue_lsl_discovery(store,study$id,"original-setups",observed$source_id,TRUE);b<-d$body
    b$status<-"ready";b$result<-list(schema="brohn-lsl-discovery/1.0",metadata_only=TRUE,streams=list(observed));b$result_hash<-brohn_hash(b$result)
    brohn_put_entity(store,"acquisition_discovery",d$id,b,d$revision,d$project_id)
  }
  d1<-discovery(first,streams$original);d2<-discovery(second,streams$restarted)
  channels<-lapply(seq_along(streams$original$channels),function(i){c<-streams$original$channels[[i]];list(id=paste0("channel-",i),label=c$label,type=c$type,unit=c$unit,value_type="string")})
  readiness<-list(schema="brohn-acquisition-readiness/1.1",modality="eeg",channels=lapply(channels,function(c)list(id=c$id,role="contact")),
    preview_channels=list("channel-1","channel-2"),reference="Original generated contact-state fixture; no electrodes",site="Offline software source",
    acquisition_checks=list(list(id="check-1",name="Original contact code",version="original-protocol/1",source="Original synthetic fixture specification",
      rationale="Retain text 001 as an exact source code",channel_id="channel-1",unit="code",kind="source_code",accepted_values=list("001"),minimum_fraction=.95,
      window_s=5,minimum_samples=100,minimum_span_s=1,maximum_age_s=5)))
  selection<-brohn_lsl_selection(d1,streams$original$uid,"stream-1","first-source-clock","monotonic","signal",channels,"Original software unit declarations",.1,readiness)
  dirty<-selection;dirty$participant_id<-"NEVER-COPY-PERSON";dirty$session_id<-"NEVER-COPY-SESSION";dirty$origin<-"live";dirty$run_id<-"NEVER-COPY-RUN"
  dirty$reviewed<-TRUE;dirty$readiness$acquisition_checks[[1L]]$reviewed<-TRUE;dirty$readiness$owner<-list(pid=123L);dirty$channels[[1L]]$session_id<-"NEVER-COPY-NESTED"
  saved<-brohn_save_equipment_setup(store,"Original reusable contact equipment",d1$id,streams$original$uid,dirty)
  text<-brohn_json(saved$body)
  check("setup save creates a workspace revision without starting acquisition",saved$revision==1L&&length(brohn_acquisitions(store))==0L&&length(brohn_list_jobs(store))==0L)
  check("setup omits people sessions origins owners live UID and review flags",!grepl('NEVER-COPY|"(reviewed|participant_id|session_id|origin|owner|uid|metadata_xml|clock_id)":',text))
  check("exact native source code remains text",identical(saved$body$configuration$readiness$acquisition_checks[[1L]]$accepted_values,list("001")))
  check("complete ordered source metadata and bounded settings are preserved",identical(saved$body$source$channel_metadata_sha256,streams$original$channel_metadata_sha256)&&
    length(saved$body$source$channels)==2L&&saved$body$configuration$gap_threshold_s==.1&&identical(saved$body$configuration$readiness$preview_channels,list("channel-1","channel-2")))
  applied<-brohn_apply_equipment_setup(store,saved$id,saved$revision,brohn_hash(saved$body),d2$id,streams$restarted$uid)
  check("restart matches stable metadata but binds only fresh outlet",identical(applied$binding$uid,"restarted-outlet")&&identical(applied$binding$metadata_sha256,streams$restarted$metadata_sha256)&&
    !identical(applied$binding$metadata_sha256,streams$original$metadata_sha256))
  check("apply is pending settings only with no authority or subscription",is.null(applied$reviewed)&&is.null(applied$configuration$uid)&&length(brohn_acquisitions(store))==0L&&length(brohn_list_jobs(store))==0L)
  for(name in c("renamed","unit","type","vendor","container","reordered","native_type")) {
    bad<-discovery(second,streams[[name]]);comparison<-brohn_compare_equipment_source(saved,streams[[name]])
    check(paste("changed",name,"has visible differences and cannot apply channel maps"),!comparison$matches&&length(comparison$differences)>0L&&
      rejects(brohn_apply_equipment_setup(store,saved$id,1L,brohn_hash(saved$body),bad$id,streams[[name]]$uid)))
  }
  bad<-streams$original;bad$channel_metadata_sha256<-NULL
  check("legacy discovery requires a fresh complete channel fingerprint",rejects(brohn_equipment_source(bad)))
  check("substituted setup body hash cannot apply",rejects(brohn_apply_equipment_setup(store,saved$id,1L,strrep("f",64),d2$id,streams$restarted$uid)))
  check("unknown outlet cannot apply",rejects(brohn_apply_equipment_setup(store,saved$id,1L,brohn_hash(saved$body),d2$id,"not-discovered")))
  limits<-list(max_duration_s=10,max_samples=1000,max_bytes=1024^2,chunk_samples=64,inlet_buffer=1)
  queue<-function(study,d,selected,reference,review=TRUE,participant="ORIGINAL-PERSON",session="ORIGINAL-SESSION",origin="sample")
    brohn_queue_acquisition(store,study$id,d$id,list(selected),list(participant_id=participant,session_id=session),origin,
      "Original software-only declaration; no physical device or person",limits,study$revision,review,equipment_setups=list("stream-1"=reference))
  check("reused setup cannot replace explicit collection review",rejects(queue(first,d1,selection,applied$reference,FALSE)))
  one<-queue(first,d1,selection,applied$reference)
  check("first study freezes exact setup revision and current request",one$body$equipment_setups[["stream-1"]]$revision==1L&&
    identical(one$body$equipment_setups[["stream-1"]]$hash,brohn_hash(saved$body))&&identical(one$body$request$streams[[1L]]$uid,streams$original$uid))
  brohn_stop_acquisition(store,one$id,one$revision,TRUE)
  selection2<-brohn_lsl_selection(d2,streams$restarted$uid,"stream-1","second-source-clock","device",selection$kind,selection$channels,
    "Fresh original software declaration",selection$gap_threshold_s,selection$readiness)
  two<-queue(second,d2,selection2,applied$reference,TRUE,"FRESH-PERSON","FRESH-SESSION","pilot")
  check("second study keeps fresh identities origin clocks and live metadata",identical(two$body$request$identity,list(participant_id="FRESH-PERSON",session_id="FRESH-SESSION"))&&
    two$body$request$origin=="pilot"&&two$body$request$streams[[1L]]$clock_id=="second-source-clock"&&two$body$request$streams[[1L]]$uid=="restarted-outlet"&&
    two$body$request$streams[[1L]]$metadata_sha256==streams$restarted$metadata_sha256)
  check("current edited settings have a separate frozen configuration hash",two$body$equipment_setups[["stream-1"]]$applied_configuration_hash==brohn_hash(brohn_equipment_configuration(selection2))&&
    two$body$equipment_setups[["stream-1"]]$applied_configuration_hash!=two$body$equipment_setups[["stream-1"]]$configuration_hash)
  changed<-selection;changed$readiness$acquisition_checks[[1L]]$minimum_fraction<-.8
  revised<-brohn_save_equipment_setup(store,"Original reusable contact equipment revised",d1$id,streams$original$uid,changed,saved$id,1L)
  check("revision save preserves original setup and queued references",revised$revision==2L&&brohn_equipment_setup(store,saved$id,1L)$body$configuration$readiness$acquisition_checks[[1L]]$minimum_fraction==.95&&
    brohn_acquisition(store,two$id)$body$equipment_setups[["stream-1"]]$revision==1L)
  check("stale setup editor cannot overwrite a newer revision",rejects(brohn_save_equipment_setup(store,"stale edit",d1$id,streams$original$uid,selection,saved$id,1L)))
  check("explicit historical setup remains exactly addressable",brohn_apply_equipment_setup(store,saved$id,1L,brohn_hash(saved$body),d2$id,streams$restarted$uid)$configuration$readiness$acquisition_checks[[1L]]$minimum_fraction==.95)
  brohn_close_store(store);store<-brohn_open_store(file.path(root,"w"))
  check("workspace reopen retains revisions and independent study requests",length(brohn_entity_history(store,"equipment_setup",saved$id))==2L&&
    brohn_acquisition(store,one$id)$body$study_id==first$id&&brohn_acquisition(store,two$id)$body$study_id==second$id&&
    identical(brohn_equipment_setup(store,saved$id,1L)$body$configuration$readiness$acquisition_checks[[1L]]$accepted_values,list("001")))
  check("two-study reuse never queues generic processing or starts recorder",length(brohn_list_jobs(store))==0L&&brohn_acquisition(store,two$id)$body$status=="queued")
  cat(sprintf("PASS: %d reusable equipment setup checks\n",checks))
})

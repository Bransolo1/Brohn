# Original named camera processing and immutable permission/source authority.
# Existing 1.0 recording/geometry agreements keep their original meaning.
.brohn_camera_facial_schema <- "brohn-camera-policy/1.1"
brohn_camera_analysis_notice <- function() paste(
  "This study will use local computer models to estimate 20 facial action-unit scores and seven native expression-category scores from your saved camera video.",
  "These outputs do not establish your feelings, attention or liking. Identity recognition, gaze and pose estimation are disabled.",
  "Only eligible completed recordings enter this automatic analysis. The recording and analysis remain subject to the storage and retention information above.")
brohn_camera_analysis_policy_hash <- function(policy) brohn_hash(policy[setdiff(names(policy),"analysis_policy_hash")])
brohn_camera_analysis_settings <- function(start_s,end_s,frame_stride,max_support_gap_s) {
  list(schema="brohn-camera-facial-settings/1.0",start_s=start_s,end_s=end_s,frame_stride=frame_stride,max_support_gap_s=max_support_gap_s)
}
brohn_camera_analysis_budget <- function(policy) {
  s<-policy$analysis_settings;end<-if(is.null(s$end_s))policy$max_duration_s else as.numeric(s$end_s)
  span<-max(0,end-as.numeric(s$start_s));frames<-ceiling(span*policy$frame_rate)+2
  list(declared_window_seconds=span,conservative_declared_frames=frames,conservative_selected_frames=ceiling(frames/s$frame_stride),
    maximum_analysed_frames=300L,nominal_interval_seconds=s$frame_stride/policy$frame_rate,
    nominal_interval_supported=s$frame_stride/policy$frame_rate<=s$max_support_gap_s,
    basis="Planning estimate from declared frame-rate/time bounds with two boundary frames; actual encoded PTS selection remains authoritative.")
}
brohn_camera_analysis_validate_policy <- function(policy) {
  brohn_fields(policy,c("schema","required","audio","consent_text","retention_text","width","height","frame_rate","max_duration_s","max_bytes","analysis_profile","analysis_settings","analysis_notice","analysis_policy_hash"),label="Named facial camera policy")
  brohn_require(identical(policy$schema,.brohn_camera_facial_schema)&&identical(policy$analysis_profile,.brohn_facial_profile),"Choose the registered 1.1 named facial camera policy.")
  # Delegate unchanged recording limits to the existing 1.0 validator.
  base<-policy[setdiff(names(policy),c("analysis_settings","analysis_notice","analysis_policy_hash"))];base$schema<-"brohn-camera-policy/1.0";base$analysis_profile<-"none"
  brohn_validate_camera_policy(base)
  s<-policy$analysis_settings
  brohn_fields(s,c("schema","start_s","end_s","frame_stride","max_support_gap_s"),label="Camera facial analysis settings")
  brohn_require(identical(s$schema,"brohn-camera-facial-settings/1.0"),"Choose registered facial window and stride settings.")
  m<-c(list(profile=.brohn_facial_profile,origin_statement="Frozen camera policy validation",consent_statement="Policy preparation; no participant permission is implied."),s[setdiff(names(s),"schema")])
  brohn_validate_facial_mapping(list(modality="video",source=list(format="webm"),metadata=m))
  limit<-format(policy$max_duration_s,digits=17,scientific=FALSE,trim=TRUE)
  brohn_require(.brohn_facial_compare(s$start_s,limit)<0L&&(is.null(s$end_s)||.brohn_facial_compare(s$end_s,limit)<=0L),"The facial window must be within the declared recording-duration limit.")
  brohn_require(identical(policy$analysis_notice,brohn_camera_analysis_notice())&&.brohn_facial_sha(policy$analysis_policy_hash)&&
    identical(policy$analysis_policy_hash,brohn_camera_analysis_policy_hash(policy)),"The named processing notice or complete recording policy digest changed.")
  budget<-brohn_camera_analysis_budget(policy)
  brohn_require(budget$conservative_selected_frames<=300,"The declared recording window can exceed 300 analysed frames. Choose a shorter explicit window or larger frame stride before saving this automatic profile.")
  invisible(policy)
}
brohn_camera_analysis_policy <- function(base,settings) {
  brohn_validate_camera_policy(base)
  p<-base;p$schema<-.brohn_camera_facial_schema;p$analysis_profile<-.brohn_facial_profile;p$analysis_settings<-settings
  p$analysis_notice<-brohn_camera_analysis_notice();p$analysis_policy_hash<-brohn_camera_analysis_policy_hash(p)
  brohn_camera_analysis_validate_policy(p);p
}
brohn_camera_analysis_validate_ack <- function(policy,request) {
  if(!identical(policy$schema,.brohn_camera_facial_schema)) {
    brohn_validate_camera_policy(policy)
    brohn_require(!any(c("analysis_consent","analysis_policy_hash")%in%names(request)),"An original 1.0 recording agreement cannot contain retroactive named facial permission.")
    return(invisible(TRUE))
  }
  brohn_camera_analysis_validate_policy(policy)
  brohn_require(.brohn_camera_flag(request$consented)&&.brohn_camera_flag(request$analysis_consent)&&
    identical(request$analysis_consent,request$consented)&&identical(request$analysis_policy_hash,policy$analysis_policy_hash),
    "Confirm the exact named facial-processing notice through the camera agreement before starting this recording.")
  invisible(TRUE)
}
brohn_camera_analysis_metadata <- function(capture) {
  p<-capture$start$policy;request<-capture$start$request
  brohn_camera_analysis_validate_ack(p,request)
  brohn_require(identical(p$schema,.brohn_camera_facial_schema)&&isTRUE(request$consented)&&isTRUE(request$analysis_consent),"This recording has no original named participant permission for automatic facial processing.")
  list(profile=.brohn_facial_profile,
    origin_statement=paste("Browser camera recording",capture$id,"for run",capture$run_id,"with original source outcome",capture$status,
      ". The setup lead-in is part of the recording. Encoded-frame alignment to study stimuli and physical camera accuracy are not established."),
    consent_statement=paste("Original named participant camera agreement: capture",capture$id,"; policy SHA-256",p$analysis_policy_hash,
      "; protocol SHA-256",capture$start$protocol_hash,". Full participant information and retention text are retained in the original capture policy.",p$analysis_notice),
    start_s=p$analysis_settings$start_s,end_s=p$analysis_settings$end_s,frame_stride=p$analysis_settings$frame_stride,max_support_gap_s=p$analysis_settings$max_support_gap_s)
}
brohn_camera_analysis_eligibility <- function(run,capture,publication=NULL) {
  no<-function(code,reason,action)list(eligible=FALSE,code=code,reason=reason,action=action)
  if(is.null(run))return(no("run_unavailable","The original participant run is unavailable.","Inspect the original session and source references."))
  if(!identical(run$completion_status,"completed")||!identical(run$transfer_status,"saved"))return(no("original_run_not_completed","The original participant session is not completed and fully received.","Finish or review the session; an operator resolution does not rewrite its original outcome."))
  if(is.null(capture))return(no("capture_unavailable","No original camera receipt is available.","Inspect the participant camera decision."))
  if(!identical(capture$start$policy$schema,.brohn_camera_facial_schema)||!identical(capture$start$policy$analysis_profile,.brohn_facial_profile))
    return(no("named_profile_not_requested","The original camera policy did not request this named automatic facial profile.","Keep its original recording/geometry policy. Separately documented later permission belongs to a reviewed manual analysis."))
  brohn_camera_analysis_validate_ack(capture$start$policy,capture$start$request)
  if(!isTRUE(capture$start$request$consented)||!isTRUE(capture$start$request$analysis_consent))return(no("named_permission_declined","The participant did not agree to this recording and named processing.","Retain the recorded decision; do not automatically analyse it."))
  if(!identical(capture$status,"completed")||!isTRUE(capture$final$container_complete)||identical(capture$final$reason,"page_reload_recording_end_unobserved"))
    return(no("capture_not_completed","The original camera recording is incomplete, interrupted, withdrawn or has an unobserved end.","Review its retained source and outcome; no automatic facial analysis is eligible."))
  if(is.null(publication))return(no("awaiting_assembly","The recording has not yet completed source assembly.","Inspect the capture assembly job and retained chunks."))
  a<-publication$body$assembly
  if(!isTRUE(a$complete_transport)||!isTRUE(a$container_complete_declared)||!isTRUE(a$recording_end_observed)||!isTRUE(a$decoder$supported))
    return(no("assembly_requires_review","The saved recording does not have complete supported source evidence.","Review the assembly report and its original artifacts."))
  list(eligible=TRUE,code="eligible_original_named_recording",reason="Original named participant permission and completed source are available.",action="Queue the frozen original dataset revision using the selected profile and exact settings.")
}
brohn_camera_analysis_source <- function(run,capture,publication,dataset,mode=c("automatic","manual")) {
  mode<-match.arg(mode);d<-dataset$body;b<-publication$body;s<-capture$start;p<-s$policy;a<-b$assembly
  brohn_require(is.list(run)&&is.list(capture)&&is.list(publication)&&is.list(dataset)&&is.list(d)&&is.list(b),"Choose the original run, capture, publication and dataset revision.")
  project<-run$protocol$design$project_id
  brohn_require(brohn_valid_id(project)&&identical(dataset$project_id,project)&&identical(publication$project_id,project)&&identical(capture$project_id,project)&&
    identical(d$id,dataset$id)&&identical(b$id,publication$id)&&identical(b$capture_id,capture$id)&&identical(b$run_id,run$id)&&identical(capture$run_id,run$id)&&
    identical(s$request$capture_id,capture$id)&&identical(b$dataset_id,dataset$id),"Camera source identities or project authority do not agree.")
  brohn_require(identical(s$study_id,run$study_id)&&identical(run$study_id,run$protocol$design$id)&&identical(d$study_id,s$study_id)&&identical(as.numeric(d$study_revision),as.numeric(s$study_revision))&&
    identical(s$deployment_id,run$deployment_id)&&identical(s$design_hash,brohn_hash(s$design))&&identical(s$design_hash,run$protocol$design_hash)&&
    identical(s$protocol_hash,brohn_hash(run$protocol))&&.brohn_facial_same(s$design,run$protocol$design)&&.brohn_facial_same(p,s$design$camera),
    "Camera recording belongs to a different frozen design, release or protocol.")
  brohn_require(.brohn_facial_same(a$policy,p)&&.brohn_facial_same(a$start,s$request)&&.brohn_facial_same(a$final,capture$final)&&
    identical(a$capture_hash,brohn_hash(capture))&&identical(b$capture_hash,brohn_hash(capture))&&identical(a$capture_id,capture$id)&&identical(a$run_id,run$id)&&
    .brohn_facial_same(a$study,s[c("study_id","study_revision","deployment_id","design_hash","protocol_hash")])&&
    identical(as.numeric(a$total_bytes),as.numeric(capture$total_bytes))&&identical(a$recording_outcome,capture$status)&&
    .brohn_facial_same(a$participant,s[c("participant_id","participant_alias_supplied")])&&identical(s$participant_id,run$participant_alias),"Published camera evidence changed its original receipt, policy or outcome.")
  brohn_camera_analysis_validate_ack(p,s$request)
  brohn_require(isTRUE(s$request$consented)&&!identical(capture$status,"withdrawn")&&!identical(run$completion_status,"withdrawn"),"A declined or withdrawn source cannot acquire facial processing through a later mapping statement.")
  brohn_require(identical(d$modality,"video")&&identical(d$source$format,"webm")&&identical(d$origin,s$origin)&&identical(s$origin,run$origin)&&identical(b$origin,s$origin)&&identical(a$origin,s$origin)&&
    identical(d$source_provenance$acquisition,"browser_camera")&&identical(d$source_provenance$capture_id,capture$id)&&identical(d$source_provenance$run_id,run$id)&&
    identical(d$source_provenance$design_hash,s$design_hash)&&identical(d$source_provenance$protocol_hash,s$protocol_hash)&&
    identical(d$source$hash,b$source_hash)&&identical(d$source_provenance$source_hash,d$source$hash)&&as.numeric(d$source$size)==as.numeric(capture$total_bytes)&&
    .brohn_facial_same(d$source_provenance$capture_policy,p)&&.brohn_facial_same(d$source_provenance$artifacts,b$artifacts),"Saved dataset source, permission provenance or retained artifacts do not match the original camera publication.")
  raw<-Filter(function(x)identical(x$kind,"camera-recording"),b$artifacts)
  kinds<-vapply(b$artifacts,`[[`,character(1),"kind")
  brohn_require(!anyDuplicated(kinds)&&all(c("camera-recording","camera-observations","camera-manifest")%in%kinds)&&all(kinds%in%c("camera-recording","camera-observations","camera-manifest","camera-decoded-frames"))&&
    all(vapply(b$artifacts,function(x)isTRUE(x$complete)&&if(identical(x$kind,"camera-recording"))isTRUE(x$media_type%in%c("video/webm","application/octet-stream"))else
      identical(x$media_type,if(identical(x$kind,"camera-observations"))"application/x-ndjson"else "application/json"),logical(1))),"Camera publication needs every registered complete source artifact and its supported retained media type.")
  # An existing single-chunk source shares the incoming opaque chunk's object
  # identity and may retain application/octet-stream. Do not rewrite that object.
  brohn_require(length(raw)==1L&&identical(raw[[1]]$hash,d$source$hash)&&as.numeric(raw[[1]]$size)==as.numeric(d$source$size),"The recording object differs from the published camera source.")
  brohn_validate_facial_mapping(d)
  original_named<-identical(p$schema,.brohn_camera_facial_schema)&&isTRUE(s$request$analysis_consent)
  expected<-if(original_named)brohn_camera_analysis_metadata(capture)else NULL
  if(mode=="automatic") {
    eligible<-brohn_camera_analysis_eligibility(run,capture,publication)
    brohn_require(isTRUE(eligible$eligible),paste(eligible$reason,eligible$action))
    brohn_require(dataset$revision==1L&&.brohn_facial_same(d$metadata,expected),"Automatic camera processing must use the original dataset mapping and exact frozen participant policy settings.")
  }
  kind<-if(original_named&&.brohn_facial_same(d$metadata,expected))"original_named_participant"else "researcher_attestation"
  if(original_named&&identical(kind,"researcher_attestation"))brohn_require(!identical(d$metadata$consent_statement,expected$consent_statement),
    "Changed processing settings need a separately documented permission statement. Keep the original participant policy intact; do not relabel its generated statement as a later researcher attestation.")
  refs<-c(lapply(b$artifacts,function(x)list(hash=x$hash,bytes=x$size)),if(!is.null(b$result_object))list(list(hash=b$result_object$hash,bytes=b$result_object$size)))
  brohn_require(length(refs)>=3L&&all(vapply(refs,function(x).brohn_facial_sha(x$hash)&&brohn_number(x$bytes,1,128*1024^2,TRUE),logical(1))),"Camera source guards need complete original artifact references.")
  refs<-refs[!duplicated(vapply(refs,`[[`,character(1),"hash"))]
  list(schema="brohn-camera-facial-authority/1.0",mode=mode,permission_kind=kind,statement=d$metadata$consent_statement,
    original_named_permission=original_named,original_camera_policy_schema=p$schema,original_policy_hash=brohn_camera_analysis_policy_hash(p),
    project_id=project,study_id=s$study_id,study_revision=s$study_revision,deployment_id=s$deployment_id,run_id=run$id,capture_id=capture$id,
    capture_hash=brohn_hash(capture),camera_start_request_hash=brohn_hash(s$request),camera_publication_id=publication$id,camera_publication_revision=publication$revision,camera_publication_hash=brohn_hash(b),
    dataset_id=dataset$id,dataset_revision=dataset$revision,dataset_hash=brohn_hash(d),design_hash=s$design_hash,protocol_hash=s$protocol_hash,
    source_hash=d$source$hash,settings_hash=brohn_hash(d$metadata),original_run_outcome=run$completion_status,recording_outcome=capture$status,
    source_refs=refs,limits="Permission provenance is recorded evidence, not independent legal verification. No clock synchronization, person tracking or psychological validity is implied.")
}

# Hand-authored, nonloaded contract only. No recording, assembly or native inference.
source("R/platform-load.R",encoding="UTF-8");brohn_load(ui=FALSE)
source("R/platform-camera-analysis.R",encoding="UTF-8")
args<-commandArgs(trailingOnly=TRUE);folder<-if(length(args))args[[1L]]else tempfile("brohn-camera-analysis-domain-")
stopifnot(!dir.exists(folder));dir.create(folder,recursive=TRUE)
checks<-character();check<-function(label,value){stopifnot(isTRUE(value));checks<<-c(checks,label);cat("PASS",label,"\n")}
rejects<-function(expr)inherits(try(force(expr),silent=TRUE),"try-error")
base<-list(schema="brohn-camera-policy/1.0",required=FALSE,audio=FALSE,consent_text="Hand-authored recording information.",
  retention_text="Hand-authored retention statement.",width=640L,height=480L,frame_rate=10,max_duration_s=10,max_bytes=1048576L,analysis_profile="none")
base_hash<-brohn_hash(base);settings<-brohn_camera_analysis_settings("0",NULL,1L,.25)
p<-brohn_camera_analysis_policy(base,settings)
check("Factory pins named1.1 processing notice and complete policy digest",identical(p$schema,"brohn-camera-policy/1.1")&&identical(p$analysis_notice,brohn_camera_analysis_notice())&&identical(p$analysis_policy_hash,brohn_camera_analysis_policy_hash(p)))
check("Original recording1.0 policy stays byte-canonical unchanged",identical(base_hash,brohn_hash(base)))
geometry<-base;geometry$analysis_profile<-"face_geometry_v1";check("Original geometry1.0 stays accepted",!rejects(brohn_validate_camera_policy(geometry)))
for(field in c("consent_text","retention_text","analysis_notice")){x<-p;x[[field]]<-paste(x[[field]],"changed");check(paste("Changed",field,"refuses stale permission digest"),rejects(brohn_camera_analysis_validate_policy(x)))}
x<-p;x$analysis_settings$frame_stride<-2L;check("Changed processing stride refuses stale permission digest",rejects(brohn_camera_analysis_validate_policy(x)))
x<-p;x$retention_text<-"New prospective retention information.";x$analysis_policy_hash<-brohn_camera_analysis_policy_hash(x)
check("Intentionally revised prospective policy receives a different valid digest",!rejects(brohn_camera_analysis_validate_policy(x))&&!identical(x$analysis_policy_hash,p$analysis_policy_hash))
long<-base;long$max_duration_s<-600;long$frame_rate<-60
check("Large undisclosed automatic workload is refused",rejects(brohn_camera_analysis_policy(long,settings)))
check("Explicit bounded window and stride can prepare long recordings",!rejects(brohn_camera_analysis_policy(long,brohn_camera_analysis_settings("0","598",120L,3))))
check("Exact decimal beyond duration is refused",rejects(brohn_camera_analysis_policy(base,brohn_camera_analysis_settings("0","10.000000000000000001",1L,.25))))
tiny<-brohn_camera_analysis_policy(base,brohn_camera_analysis_settings("0.100000000000000001","0.100000000000000002",1L,.25))
check("Authored sub-double decimal window is preserved",identical(tiny$analysis_settings$start_s,"0.100000000000000001")&&identical(tiny$analysis_settings$end_s,"0.100000000000000002"))
ack<-list(consented=TRUE,analysis_consent=TRUE,analysis_policy_hash=p$analysis_policy_hash)
check("One affirmative camera choice acknowledges exact named processing",!rejects(brohn_camera_analysis_validate_ack(p,ack)))
x<-ack;x$analysis_policy_hash<-strrep("f",64);check("Wrong policy digest is refused",rejects(brohn_camera_analysis_validate_ack(p,x)))
x<-ack;x$analysis_consent<-NULL;check("Missing named processing acknowledgement is refused",rejects(brohn_camera_analysis_validate_ack(p,x)))
x<-ack;x$consented<-FALSE;check("Contradictory affirmative and declined choices are refused",rejects(brohn_camera_analysis_validate_ack(p,x)))
x<-ack;x$consented<-FALSE;x$analysis_consent<-FALSE;check("One negative choice records both decisions without fabricating permission",!rejects(brohn_camera_analysis_validate_ack(p,x)))
check("Legacy original camera receipt remains accepted",!rejects(brohn_camera_analysis_validate_ack(geometry,list(consented=TRUE))))
check("Legacy receipt cannot be retroactively upgraded with new permission fields",rejects(brohn_camera_analysis_validate_ack(geometry,ack)))

context<-function(policy=p,run_status="completed",capture_status="completed",consented=TRUE){
  design<-brohn_new_design("Hand-authored camera authority","blank",id="study-contract");design$camera<-policy
  protocol<-list(design=design,design_hash=brohn_hash(design))
  request<-list(capture_id="camera-contract",consented=consented)
  if(identical(policy$schema,.brohn_camera_facial_schema)){request$analysis_consent<-consented;request$analysis_policy_hash<-policy$analysis_policy_hash}
  run<-list(id="run-contract",study_id=design$id,deployment_id="release-contract",participant_alias="SOFTWARE-ONLY",completion_status=run_status,transfer_status="saved",protocol=protocol,origin="sample")
  capture<-list(id=request$capture_id,run_id=run$id,project_id="default",status=capture_status,total_bytes=512L,
    final=list(container_complete=TRUE,reason=NULL),start=list(request=request,policy=policy,study_id=design$id,study_revision=1L,
      deployment_id=run$deployment_id,design=design,design_hash=brohn_hash(design),protocol_hash=brohn_hash(protocol),origin="sample",participant_id=run$participant_alias,participant_alias_supplied=TRUE))
  artifact<-function(kind,hash,size,type)list(kind=kind,hash=strrep(hash,64),size=size,media_type=type,complete=TRUE)
  artifacts<-list(artifact("camera-recording","a",512L,"video/webm"),artifact("camera-observations","b",100L,"application/x-ndjson"),artifact("camera-manifest","c",1000L,"application/json"))
  assembly<-list(capture_id=capture$id,run_id=run$id,capture_hash=brohn_hash(capture),policy=policy,start=request,final=capture$final,
    study=capture$start[c("study_id","study_revision","deployment_id","design_hash","protocol_hash")],participant=capture$start[c("participant_id","participant_alias_supplied")],
    total_bytes=512,recording_outcome=capture_status,origin="sample",complete_transport=TRUE,container_complete_declared=TRUE,recording_end_observed=TRUE,decoder=list(supported=TRUE))
  publication<-list(id=capture$id,revision=1L,project_id="default",body=list(id=capture$id,capture_id=capture$id,run_id=run$id,dataset_id="dataset-camera-contract",capture_hash=brohn_hash(capture),
    source_hash=artifacts[[1L]]$hash,origin="sample",assembly=assembly,artifacts=artifacts,result_object=list(hash=strrep("d",64),size=2000L)))
  metadata<-if(identical(policy$schema,.brohn_camera_facial_schema)&&consented)brohn_camera_analysis_metadata(capture)else list(profile=.brohn_facial_profile,
    origin_statement="Original camera source; separately reviewed manual processing.",consent_statement="Researcher separately attests documented later permission for local facial processing.",start_s="0",frame_stride=1L,max_support_gap_s=.25)
  dataset<-list(id=publication$body$dataset_id,revision=1L,project_id="default",body=list(id=publication$body$dataset_id,modality="video",study_id=design$id,study_revision=1L,origin="sample",metadata=metadata,
    source=list(hash=artifacts[[1L]]$hash,size=512,format="webm"),source_provenance=list(acquisition="browser_camera",capture_id=capture$id,run_id=run$id,design_hash=capture$start$design_hash,
      protocol_hash=capture$start$protocol_hash,source_hash=artifacts[[1L]]$hash,capture_policy=policy,artifacts=artifacts)))
  list(run=run,capture=capture,publication=publication,dataset=dataset)
}
ctx<-context();authority<-do.call(brohn_camera_analysis_source,ctx)
check("Original named completed source resolves automatic authority",identical(authority$permission_kind,"original_named_participant")&&identical(authority$mode,"automatic")&&isTRUE(authority$original_named_permission))
check("Every original camera artifact and publication document is guarded",length(authority$source_refs)==4L&&identical(authority$dataset_revision,1L))
x<-ctx;x$publication$body$artifacts[[1L]]$media_type<-"application/octet-stream";x$dataset$body$source_provenance$artifacts<-x$publication$body$artifacts
check("Original deduplicated single-chunk opaque media metadata stays valid",!rejects(do.call(brohn_camera_analysis_source,x)))
x$publication$body$artifacts[[1L]]$media_type<-"text/plain";x$dataset$body$source_provenance$artifacts<-x$publication$body$artifacts
check("Unrelated recording media type is refused",rejects(do.call(brohn_camera_analysis_source,x)))
check("Native permission text preserves the policy digest within its field bound",grepl(p$analysis_policy_hash,ctx$dataset$body$metadata$consent_statement,fixed=TRUE)&&nchar(ctx$dataset$body$metadata$consent_statement)<4000)
eligible<-function(x)brohn_camera_analysis_eligibility(x$run,x$capture,x$publication)
for(status in c("in_progress","withdrawn","interrupted")){x<-context(run_status=status);x$run$session_resolution<-list(received_completion_analysis_eligible=TRUE)
  check(paste("Original run",status,"is not upgraded by an operator sidecar"),!isTRUE(eligible(x)$eligible))}
for(status in c("interrupted","withdrawn","partial")){x<-context(capture_status=status);check(paste("Original capture",status,"is not automatically analysed"),!isTRUE(eligible(x)$eligible))}
x<-ctx;x$run$transfer_status<-"pending";check("Pending participant receipt cannot autoqueue",!isTRUE(eligible(x)$eligible))
x<-ctx;x$capture$final$reason<-"page_reload_recording_end_unobserved";check("Unobserved recording end cannot autoqueue",!isTRUE(eligible(x)$eligible))
x<-ctx;x$publication<-NULL;check("Assembly pending supplies a concrete next action",identical(eligible(x)$code,"awaiting_assembly")&&nzchar(eligible(x)$action))
x<-ctx;x$publication$body$assembly$decoder$supported<-FALSE;check("Unsupported decoder is visible and not eligible",identical(eligible(x)$code,"assembly_requires_review"))
for(policy in list(base,geometry)){x<-context(policy=policy);before<-brohn_hash(x);a<-do.call(brohn_camera_analysis_source,c(x,list(mode="manual")))
  check(paste("Legacy",policy$analysis_profile,"permits distinct later researcher attestation"),identical(a$permission_kind,"researcher_attestation")&&!a$original_named_permission&&identical(before,brohn_hash(x)))
  check(paste("Legacy",policy$analysis_profile,"never becomes automatic named permission"),!isTRUE(eligible(x)$eligible)&&rejects(do.call(brohn_camera_analysis_source,x)))}
x<-ctx;x$dataset$revision<-2L;x$dataset$body$metadata$start_s<-"0.5";x$dataset$body$metadata$consent_statement<-"Later separately documented facial-processing permission reviewed by the researcher."
a<-do.call(brohn_camera_analysis_source,c(x,list(mode="manual")))
check("Revised manual settings carry researcher attestation without rewriting original named decision",identical(a$permission_kind,"researcher_attestation")&&a$original_named_permission&&rejects(do.call(brohn_camera_analysis_source,x)))
x$dataset$body$metadata$consent_statement<-ctx$dataset$body$metadata$consent_statement
check("A copied original statement cannot masquerade as separate permission for changed settings",rejects(do.call(brohn_camera_analysis_source,c(x,list(mode="manual")))))
for(x in list(context(run_status="withdrawn"),context(capture_status="withdrawn"),context(capture_status="declined",consented=FALSE)))
  check(paste("Declined or withdrawn source refused even through manual mapping",x$run$completion_status,x$capture$status),rejects(do.call(brohn_camera_analysis_source,c(x,list(mode="manual")))))
mutations<-list(foreign_project=function(x){x$dataset$project_id<-"foreign";x},source_hash=function(x){x$dataset$body$source$hash<-strrep("e",64);x},
  protocol_design=function(x){x$run$protocol$design$title<-"Substitution";x},original_policy=function(x){x$capture$start$policy$retention_text<-"Changed";x},
  published_capture_hash=function(x){x$publication$body$capture_hash<-strrep("e",64);x},artifact_hash=function(x){x$dataset$body$source_provenance$artifacts[[2L]]$hash<-strrep("e",64);x},
  participant_alias=function(x){x$run$participant_alias<-"Different participant";x})
for(name in names(mutations))check(paste("Source substitution refused:",name),rejects(do.call(brohn_camera_analysis_source,mutations[[name]](ctx))))
receipt<-list(status="passed",count=length(checks),checks=as.list(checks),evidence="Pure hand-authored, explicitly sourced nonloaded helper. No participant browser, real assembly, inference or automatic runtime integration is qualified.",
  source_hash=digest::digest(file="R/platform-camera-analysis.R",algo="sha256"),test_hash=digest::digest(file="tests/platform-camera-analysis.R",algo="sha256"))
writeLines(brohn_json(receipt),file.path(folder,"results.json"),useBytes=TRUE);cat("TOTAL",length(checks),"\n")

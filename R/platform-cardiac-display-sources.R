# Exact historical cardiac sources. This module registers no package admission.
# Metadata never scans scientific streams or calls a scientific producer.
.brohn_cds_profile <- "cardiac-saved-findings/0.1"
.brohn_cds_require <- function(ok,code,message) {
 if(!isTRUE(ok))stop(structure(list(message=message,call=NULL,reason_code=code,stage="source_metadata"),class=c("brohn_cardiac_source_error","error","condition")))
 invisible(TRUE)
}
.brohn_cds_limit <- function(measured,maximum,resource,ref=NULL) {
 if(!is.numeric(measured)||length(measured)!=1L||!is.finite(measured)||measured>maximum)stop(structure(list(message=paste("The complete cardiac source exceeds",resource,"capacity; fewer figures cannot reduce original evidence. Use fewer sources or the source's existing original exports."),call=NULL,reason_code="complete_source_limit",stage="source_metadata",source_ref=ref,resource=resource,measured=measured,maximum=maximum,recovery_scope="fewer_sources"),class=c("brohn_cardiac_source_error","error","condition")))
 invisible(TRUE)
}
.brohn_cds_json <- function(text,maximum=2*1024^2) {
 if(is.null(text)||!length(text)||is.na(text))return(NULL)
 brohn_parse(.brohn_edd_json_text(text),maximum)
}
.brohn_cds_ref <- function(kind,id,revision,hash,project)list(kind=kind,id=id,revision=revision,body_hash=hash,project_id=project)
.brohn_cds_lineage_shape <- function(dataset) {
 p<-dataset$lineage
 known<-c("imported_at","source_hash","ingestion_id","processing","review_hash","source_preservation","source_snapshot_hash","acquisition","curation_id","lineage","artifacts","quality","selection","parent_acquisition")
 .brohn_cds_require(is.null(p)||(is.list(p)&&all(names(p) %in% known)),"unsupported_dataset_lineage",paste("Unregistered original source lineage:",paste(paste0("/source_provenance/",setdiff(names(p),known)),collapse=", ")))
 if(!is.null(p$source_hash)).brohn_cds_require(identical(p$source_hash,dataset$source$hash),"source_provenance_mismatch","The original dataset source-provenance hash differs from its source object.")
 if(!is.null(p$lineage)){
  known<-c("stream_id","stream_revision","stream_hash","import_id","import_revision","import_hash","raw_dataset_id","raw_dataset_revision","raw_dataset_hash","raw_source","source_uid","source_id","canonical_hash","original_stream_artifacts")
  .brohn_cds_require(is.list(p$lineage)&&all(names(p$lineage) %in% known),"unsupported_dataset_lineage","Unregistered required curation relationship under /source_provenance/lineage.")
 }
 if(!is.null(p$parent_acquisition)).brohn_cds_require(is.list(p$parent_acquisition)&&all(names(p$parent_acquisition) %in% c("id","original","journal_tip","completion_status")),"unsupported_dataset_lineage","Unregistered required acquisition relationship under /source_provenance/parent_acquisition.")
 invisible(TRUE)
}
.brohn_cds_record <- function(store,ref,maximum=2*1024^2) {
 .brohn_rpk_ref_catalog(store,ref)
 row<-DBI::dbGetQuery(store$con,"SELECT length(CAST(body_json AS BLOB)) bytes FROM entity_versions WHERE kind=? AND id=? AND revision=?",params=list(ref$kind,ref$id,ref$revision))
 .brohn_cds_require(nrow(row)==1L&&row$bytes[[1L]]<=maximum,"source_metadata_bytes","This exact cardiac lineage document exceeds the bounded metadata profile.")
 .brohn_rpk_record(store,ref)
}
.brohn_cds_job <- function(store,processing,operation,result_key,result_id,object) {
 .brohn_cds_require(is.list(processing)&&brohn_valid_id(processing$job_id)&&brohn_number(processing$attempt,1,1e9,TRUE)&&.brohn_rpk_hash(processing$request_hash)&&
  is.list(processing$code_hashes)&&length(processing$code_hashes)>0L&&all(vapply(processing$code_hashes,.brohn_rpk_hash,logical(1))),"missing_producer_receipt","The original cardiac publication lacks its retained implementation and execution receipt.")
 row<-DBI::dbGetQuery(store$con,"SELECT length(CAST(request_json AS BLOB))+coalesce(length(CAST(result_json AS BLOB)),0) bytes FROM jobs WHERE id=?",params=list(processing$job_id))
 .brohn_cds_require(nrow(row)==1L&&row$bytes[[1L]]<=2*1024^2,"missing_producer_receipt","The original producer request/result is missing or oversized.")
 j<-brohn_get_job(store,processing$job_id)
 .brohn_cds_require(j$operation %in% operation&&identical(j$status,"succeeded")&&j$attempt==processing$attempt&&identical(j$result[[result_key]],result_id)&&identical(j$result$output_hash,object$hash),"producer_receipt_mismatch","The exact source no longer matches its original successful producer.")
 # Queue request identity and executed input identity are intentionally distinct.
 list(id=j$id,operation=j$operation,status=j$status,attempt=j$attempt,request=j$request,request_hash=brohn_hash(j$request),result=j$result,execution_request_hash=processing$request_hash,code_hashes=processing$code_hashes)
}
.brohn_cds_report_metadata <- function(store,ref) {
 .brohn_rpk_ref_catalog(store,ref,"report")
 paths<-c(id="$.id",title="$.title",study_id="$.study_id",dataset_id="$.dataset_id",origin="$.origin",provenance="$.provenance",processing="$.processing",result_object="$.result_object",
  schema="$.analysis.schema",kind="$.analysis.kind",modality="$.analysis.modality",status="$.analysis.status",operation="$.analysis.operation",engine="$.analysis.engine",source="$.analysis.source",parameters="$.analysis.parameters",artifacts="$.analysis.artifacts",verification="$.analysis.artifact_verification",ledger="$.analysis.exclusion_review",quality="$.analysis.quality",limitations="$.analysis.limitations")
 sizes<-DBI::dbGetQuery(store$con,paste0("SELECT ",paste(vapply(paths,function(path)paste0("coalesce(length(CAST(json_extract(body_json,'",path,"') AS BLOB)),0)"),character(1)),collapse="+")," bytes FROM entity_versions WHERE kind='report' AND id=? AND revision=? AND project_id=?"),params=list(ref$id,ref$revision,ref$project_id))
 .brohn_cds_require(nrow(sizes)==1L&&sizes$bytes[[1L]]<=2*1024^2,"source_metadata_bytes","Cardiac source metadata exceeds the bounded reader profile.")
 sql<-paste0("SELECT ",paste(vapply(seq_along(paths),function(i)paste0("json_extract(body_json,'",paths[[i]],"') AS ",names(paths)[[i]]),character(1)),collapse=","),",json_array_length(body_json,'$.analysis.recordings') record_count,json_array_length(body_json,'$.analysis.features') feature_count,json_type(body_json,'$.analysis.recordings') record_type,json_type(body_json,'$.analysis.features') feature_type,(SELECT count(*) FROM json_each(body_json,'$.analysis.recordings') r WHERE json_extract(r.value,'$.status')='computed') computed_count FROM entity_versions WHERE kind='report' AND id=? AND revision=? AND project_id=?")
 row<-DBI::dbGetQuery(store$con,sql,params=list(ref$id,ref$revision,ref$project_id));.brohn_cds_require(nrow(row)==1L,"missing_source","The exact cardiac source is unavailable.")
 objects<-c("provenance","processing","result_object","engine","source","parameters","artifacts","verification","ledger","quality","limitations")
 m<-lapply(names(paths),function(n){x<-row[[n]][[1L]];if(n %in% objects).brohn_cds_json(x)else if(is.na(x))NULL else x});names(m)<-names(paths);m$ref<-ref
 m$record_count<-row$record_count[[1L]];m$feature_count<-row$feature_count[[1L]];m$computed_count<-row$computed_count[[1L]]
 .brohn_cds_require(identical(m$id,ref$id)&&identical(m$schema,"brohn-worker-result/1.0")&&m$kind %in% c("ecg","ppg")&&identical(m$kind,m$modality)&&is.null(m$operation),"unsupported_cardiac_family","This source is outside the saved ECG/PPG cardiac family.")
 .brohn_cds_require(identical(row$record_type[[1L]],"array")&&identical(row$feature_type[[1L]],"array")&&brohn_number(m$record_count,0,2000,TRUE)&&brohn_number(m$feature_count,0,26000,TRUE)&&m$status %in% c("completed","partial","insufficient_support"),"unsupported_cardiac_outcome","The saved cardiac outcome or original record inventory is unregistered.")
 keys<-DBI::dbGetQuery(store$con,"SELECT j.key FROM entity_versions v,json_each(v.body_json,'$.analysis') j WHERE v.kind='report' AND v.id=? AND v.revision=?",params=list(ref$id,ref$revision))$key
 known<-c("schema","kind","modality","status","engine","source","parameters","features","recordings","quality","limitations","artifacts","artifact_verification","observations","contrasts","title","exclusion_review","warnings","series","events")
 .brohn_cds_require(all(keys %in% known),"unsupported_scientific_collection",paste("Unregistered cardiac analysis field:",paste(paste0("/analysis/",setdiff(keys,known)),collapse=", ")))
 .brohn_cds_require(is.list(m$parameters)&&!is.null(names(m$parameters))||(!m$record_count&&!length(m$parameters)),"unsupported_cardiac_recipe","Saved effective parameters must remain keyed by original recording identity.")
 recipe<-if(m$kind=="ecg")"ecg-neurokit-detected-rr/1.0"else"ppg-elgendi-detected-prv/1.0"
 .brohn_cds_require(all(vapply(m$parameters,function(p)is.list(p)&&identical(p$recipe,recipe),logical(1))),"unsupported_cardiac_recipe","The saved effective detector recipe is unregistered.")
 .brohn_cds_require(brohn_array(m$artifacts)&&length(m$artifacts) %in% c(0L,2L)&&(!length(m$artifacts)||identical(vapply(m$artifacts,`[[`,character(1),"kind"),c("physiology-series","physiology-events"))),"unsupported_artifact_inventory","Cardiac evidence requires its exact original zero-or-two scientific streams.")
 .brohn_cds_require((m$computed_count>0L)==(length(m$artifacts)==2L),"missing_computed_artifacts","Computed cardiac runs require their original scientific streams; unavailable outcomes cannot invent streams.")
 for(a in m$artifacts).brohn_edd_descriptor(a)
 m$object<-.brohn_rpk_object(store,m$result_object,16*1024^2)
 m$producer<-.brohn_cds_job(store,m$processing,c("analyse_dataset","reanalyse_cardiac"),"report_id",ref$id,m$object)
 child<-identical(m$producer$operation,"reanalyse_cardiac");code<-m$processing$code_hashes
 .brohn_cds_require(identical(m$processing$recipe,"brohn-analysis/1.0.0-draft")&&identical(m$engine$version,"1.0.0")&&identical(m$engine$name,if(child)"Brohn cardiac source exclusion"else"Brohn physiology worker")&&
  .brohn_rpk_hash(m$engine$worker_sha256)&&identical(m$engine$worker_sha256,code[[if(child)"scripts/workers/cardiac_review.py"else"scripts/workers/physiology.py"]])&&
  .brohn_rpk_hash(m$engine$artifact_writer_sha256)&&identical(m$engine$artifact_writer_sha256,code[["scripts/workers/physiology_artifacts.py"]])&&
  (!child||(.brohn_rpk_hash(m$engine$detector_worker_sha256)&&identical(m$engine$detector_worker_sha256,code[["scripts/workers/physiology.py"]]))),"producer_implementation_mismatch","Original cardiac engine, operation and retained detector/writer identities do not agree.")
 p<-m$provenance;m$dataset_ref<-.brohn_cds_ref("dataset",p$dataset_id,p$dataset_revision,p$dataset_hash,ref$project_id)
 .brohn_cds_require(identical(m$dataset_id,p$dataset_id)&&identical(m$origin,p$origin)&&identical(m$study_id,p$study_id),"source_provenance_mismatch","Cardiac report identity, study or origin differs from its original provenance.")
 if(is.null(m$study_id)){
  .brohn_cds_require(is.null(p$design)&&is.null(p$design_hash),"source_provenance_mismatch","A standalone original cannot acquire study provenance.")
 }else{
  .brohn_cds_require(brohn_valid_id(m$study_id)&&identical(p$design$id,m$study_id)&&identical(brohn_hash(p$design),p$design_hash),"source_provenance_mismatch","The original study design is missing or changed.");.brohn_rpk_study(store,m$study_id,ref$project_id)
 }
 .brohn_cds_require(nchar(brohn_json(m),type="bytes")<=2*1024^2,"source_metadata_bytes","Cardiac metadata exceeds its bounded profile.")
 m
}

# This wraps the existing exact dataset/ingestion/curation/acquisition primitives.
# They do not perform EDA admission and never run processing or read streams.
brohn_cardiac_source_metadata <- function(store,report_ref) {
 nodes<-edges<-objects<-jobs<-reports<-contexts<-documents<-list();active<-character()
 add_node<-function(ref,role){.brohn_rpk_ref_catalog(store,ref);key<-brohn_hash(ref);nodes[[key]]<<-list(ref=ref,role=role);key}
 edge<-function(from,to,role){x<-list(from=from,to=to,role=role);edges[[brohn_hash(x)]]<<-x}
 add_object<-function(o){old<-objects[[o$hash]];.brohn_cds_require(is.null(old)||.brohn_rpk_same(old,o),"conflicting_object_descriptor","One source object has conflicting original descriptors.");objects[[o$hash]]<<-o}
 add_job<-function(j){old<-jobs[[j$id]];.brohn_cds_require(is.null(old)||.brohn_rpk_same(old,j),"conflicting_producer","An original producer has conflicting exact receipts.");jobs[[j$id]]<<-j}
 record<-function(ref,role,from=NULL){r<-.brohn_cds_record(store,ref);add_node(ref,role);if(!is.null(from))edge(from,ref,role);r}
 walk<-function(ref){key<-brohn_hash(ref);.brohn_cds_require(!key %in% active,"source_cycle","The cardiac source closure contains a cycle.");if(!is.null(reports[[key]]))return(reports[[key]])
  .brohn_cds_require(length(reports)<32L,"source_report_count","The cardiac closure exceeds 32 original reports.");active<<-c(active,key);on.exit(active<<-setdiff(active,key),add=TRUE)
  m<-.brohn_cds_report_metadata(store,ref);add_node(ref,"complete_scientific_report");add_object(m$object);add_job(m$producer);reports[[key]]<<-m
  drec<-record(m$dataset_ref,"mapped_dataset",ref);d<-.brohn_edd_exact_dataset(store,m$dataset_ref);.brohn_cds_lineage_shape(d);p<-m$provenance
  .brohn_cds_require(identical(d$modality,m$kind)&&identical(d$origin,m$origin)&&.brohn_rpk_same(d$source,p$source)&&.brohn_rpk_same(d$mapping,p$mapping)&&identical(m$source$sha256,d$source$hash)&&m$source$bytes==d$source$size,"source_provenance_mismatch","The original cardiac dataset, source bytes, mapping or origin changed.")
  add_object(.brohn_rpk_object(store,d$source,512*1024^2));for(a in m$artifacts)add_object(.brohn_rpk_object(store,a,64*1024^2))
  ingestion<-.brohn_edd_ingestion(store,d);lineage<-NULL
  if(!is.null(ingestion)){record(ingestion$ref,"ingestion",d$ref);add_object(ingestion$object)}
  if(identical(d$lineage$acquisition,"curated_stream")){
   lineage<-.brohn_edd_curation_lineage(store,d)
   for(o in lineage$objects)add_object(o)
   for(n in c("curation_ref","stream_ref","import_ref","raw_dataset_ref","raw_ingestion_ref"))if(!is.null(lineage$binding[[n]]))record(lineage$binding[[n]],n,d$ref)
   .brohn_cds_lineage_shape(.brohn_edd_exact_dataset(store,lineage$binding$raw_dataset_ref))
   # Retain every original stream artifact, not only the canonical table.
   for(o in d$lineage$lineage$original_stream_artifacts)add_object(.brohn_rpk_object(store,o,512*1024^2))
   if(!is.null(lineage$acquisition))for(n in c("review_ref","preservation_ref"))record(lineage$acquisition$binding[[n]],paste0("acquisition_",n),lineage$binding$raw_dataset_ref)
  }else if(!is.null(d$lineage$parent_acquisition)){
   acq<-.brohn_edd_acquisition_lineage(store,d);for(o in acq$objects)add_object(o)
   for(n in c("review_ref","preservation_ref"))record(acq$binding[[n]],paste0("acquisition_",n),d$ref)
   lineage<-list(binding=list(acquisition=acq$binding),objects=acq$objects,documents=list(),raw_ingestion=NULL,acquisition=acq)
  }
  .brohn_cds_require(is.null(d$lineage$acquisition)||d$lineage$acquisition %in% c("curated_stream"),"unsupported_dataset_lineage","This dataset acquisition lineage needs an explicit cardiac registration.")
  contexts[[key]]<<-list(report_ref=ref,dataset=d,ingestion=ingestion,lineage=lineage,exclusion=NULL)
  if(identical(m$producer$operation,"analyse_dataset")){
   q<-m$producer$request
   .brohn_cds_require(is.null(m$ledger)&&is.null(p$cardiac_review)&&identical(q$dataset_id,d$ref$id)&&q$dataset_revision==d$ref$revision&&identical(q$dataset_hash,d$ref$body_hash)&&identical(q$study_id,m$study_id)&&identical(q$study_hash,p$design_hash),"producer_source_mismatch","Original analysis request does not pin this exact dataset/study.")
   if(!is.null(m$study_id)){
    sr<-.brohn_cds_ref("study",q$study_id,q$study_revision,q$study_hash,ref$project_id);study<-record(sr,"original_study_design",ref)
    .brohn_cds_require(.brohn_rpk_same(study$body,p$design),"source_provenance_mismatch","The original study version differs from the saved design snapshot.")
   }
  }else{
   q<-m$producer$request;review_ref<-.brohn_cds_ref("cardiac_review",q$review_id,q$review_revision,q$review_hash,ref$project_id)
   rr<-record(review_ref,"accepted_review",ref);rv<-rr$body;parent_ref<-.brohn_cds_ref("report",rv$report_id,rv$report_revision,rv$report_hash,ref$project_id)
   parent<-walk(parent_ref);edge(ref,parent_ref,"original_parent")
   preview_ref<-.brohn_cds_ref("cardiac_review_preview",q$preview_id,q$preview_revision,q$preview_hash,ref$project_id);pr<-record(preview_ref,"accepted_preview",ref);pb<-pr$body
   catalog_ref<-.brohn_cds_ref("signal_view",rv$catalog_id,rv$catalog_revision,rv$catalog_hash,ref$project_id);cr<-record(catalog_ref,"original_waveform_catalog",review_ref);cb<-cr$body
   review_source<-list(id=review_ref$id,revision=review_ref$revision,hash=review_ref$body_hash)
   .brohn_cds_require(identical(q$project_id,ref$project_id)&&identical(q$policy,"cardiac-source-exclusion/1.0")&&identical(rv$schema_version,"brohn-cardiac-review/1.0")&&identical(rv$policy,q$policy)&&
    .brohn_rpk_same(parent$dataset_ref,m$dataset_ref)&&identical(rv$dataset_id,d$ref$id)&&rv$dataset_revision==d$ref$revision&&identical(rv$dataset_hash,d$ref$body_hash)&&is.null(parent$ledger)&&
    .brohn_rpk_same(p$cardiac_review,list(parent_report=list(id=parent_ref$id,revision=parent_ref$revision,hash=parent_ref$body_hash),review_source=review_source,policy=q$policy)),"review_source_mismatch","The exclusion child does not bind the original parent and accepted review.")
   .brohn_cds_require(identical(pb$schema_version,"brohn-saved-cardiac-review-preview/1.0")&&identical(pb$report_id,parent_ref$id)&&.brohn_rpk_same(pb$review_source,review_source)&&is.null(pb$preview$resolved_exclusion)&&identical(pb$preview$schema,"brohn-cardiac-review-preview/1.0")&&
    .brohn_rpk_same(pb$preview$ledger,m$ledger)&&.brohn_rpk_same(m$ledger$review_source,review_source)&&identical(m$ledger$schema,"brohn-cardiac-exclusion-ledger/1.0")&&identical(m$ledger$policy,q$policy),"accepted_preview_mismatch","The child differs from its original accepted reanalysis preview and ledger.")
   .brohn_cds_require(identical(cb$schema_version,"brohn-saved-signal-view/1.0.0")&&identical(cb$operation,"signal_catalog")&&identical(cb$report_id,parent_ref$id)&&cb$report_revision==parent_ref$revision&&identical(cb$report_hash,parent_ref$body_hash)&&identical(cb$artifact_hash,rv$artifact_hash)&&identical(parent$artifacts[[1L]]$hash,rv$artifact_hash),"review_catalog_mismatch","The original waveform catalogue no longer matches the reviewed source.")
   tables<-Filter(function(t)identical(t$table_id,rv$table$table_id),cb$view$tables)
   .brohn_cds_require(length(tables)==1L&&.brohn_rpk_same(tables[[1L]],rv$table)&&.brohn_rpk_same(m$ledger$table,rv$table)&&identical(m$ledger$source$sha256,d$source$hash)&&m$ledger$source$bytes==d$source$size,"review_table_mismatch","The accepted ledger/review/catalogue table or source changed.")
   brohn_validate_cardiac_spans(rv$spans,rv$table,FALSE)
   # Ledger spans add saved endpoint context; preserve it rather than regenerate.
   .brohn_cds_require(length(rv$spans)==length(m$ledger$spans)&&all(vapply(seq_along(rv$spans),function(i).brohn_rpk_same(rv$spans[[i]],m$ledger$spans[[i]][names(rv$spans[[i]])]),logical(1))),"review_span_mismatch","The accepted ledger differs from the original decisions.")
   for(id in names(m$parameters)).brohn_cds_require(.brohn_rpk_same(m$parameters[[id]],parent$parameters[[id]]),"parent_parameters_changed","The child detector parameters differ from the original parent.")
   if(!is.null(m$ledger$curation)){
    cu<-m$ledger$curation
    .brohn_cds_require(!is.null(lineage)&&identical(cu$curation_id,lineage$binding$curation_ref$id)&&cu$curation_revision==lineage$binding$curation_ref$revision&&identical(cu$curation_hash,lineage$binding$curation_ref$body_hash)&&.brohn_rpk_same(cu$lineage,d$lineage$lineage),"curation_ledger_mismatch","The ledger's exact curated lineage differs from the original source.")
    ds<-Filter(function(a)identical(a$kind,"curation_decisions_jsonl"),d$lineage$artifacts)
    .brohn_cds_require(length(ds)==1L&&identical(cu$decisions$sha256,ds[[1L]]$hash)&&cu$decisions$bytes==ds[[1L]]$size,"curation_ledger_mismatch","The ledger no longer binds the complete decisions stream.")
   }else .brohn_cds_require(is.null(lineage)||is.null(lineage$binding$curation_ref),"curation_ledger_mismatch","A curated child omitted its original curation ledger.")
   for(x in list(list(record=pr,operation="preview_cardiac_review",result_key="cardiac_preview_id"),list(record=cr,operation="signal_catalog",result_key="signal_view_id"))){
    b<-x$record$body;o<-.brohn_rpk_object(store,b$result_object,2*1024^2);add_object(o)
    jp<-.brohn_cds_job(store,b$processing,x$operation,x$result_key,x$record$id,o);add_job(jp)
    if(x$operation=="preview_cardiac_review").brohn_cds_require(.brohn_rpk_same(jp$request,q[setdiff(names(q),c("preview_id","preview_revision","preview_hash"))])&&is.null(jp$request$candidate),"accepted_preview_producer_mismatch","The accepted preview was produced for another original review or boundary resolution.")
    else .brohn_cds_require(identical(jp$request$report_id,parent_ref$id)&&jp$request$report_revision==parent_ref$revision&&identical(jp$request$report_hash,parent_ref$body_hash)&&identical(jp$request$artifact$sha256,rv$artifact_hash),"review_catalog_producer_mismatch","The original catalogue request changed its report or artifact.")
    documents[[brohn_hash(.brohn_rpk_ref(x$record))]]<<-list(ref=.brohn_rpk_ref(x$record),body=b,object=o)
   }
   contexts[[key]]$exclusion<<-list(parent_ref=parent_ref,review_ref=review_ref,review=rv,catalog_ref=catalog_ref,catalog=cb,preview_ref=preview_ref,preview=pb,producer=m$producer)
  };m
 }
 selected<-walk(report_ref)
 streams<-list();logical_rows<-0;logical_tables<-0
 for(m in reports)for(a in m$artifacts){streams[[a$hash]]<-a;logical_rows<-logical_rows+a$rows;logical_tables<-logical_tables+a$tables}
 .brohn_cds_limit(logical_rows,1e6,"source_rows",report_ref);.brohn_cds_limit(logical_tables,256L,"source_tables",report_ref)
 .brohn_cds_limit(sum(vapply(streams,`[[`,numeric(1),"size")),96*1024^2,"source_stream_bytes",report_ref)
 .brohn_cds_limit(sum(vapply(objects,`[[`,numeric(1),"bytes")),1024^3,"source_object_bytes",report_ref)
 # Preserve every upstream successful producer receipt, not only entity hashes.
 for(node in nodes){if(node$ref$kind %in% c("report","cardiac_review","cardiac_review_preview","signal_view","dataset"))next
  b<-.brohn_cds_record(store,node$ref)$body
  for(pp in list(b$processing,b$preservation,if(is.list(b$review))b$review$publication else NULL))if(is.list(pp)&&!is.null(pp$job_id)){
   j<-brohn_get_job(store,pp$job_id);.brohn_cds_require(!is.null(j)&&identical(j$status,"succeeded"),"lineage_producer_mismatch","An original lineage producer is no longer successful.")
   jobs[[j$id]]<-list(id=j$id,operation=j$operation,status=j$status,attempt=j$attempt,request=j$request,request_hash=brohn_hash(j$request),result=j$result)
  }
 }
 sort_values<-function(x)unname(x[order(names(x),method="radix")])
 graph<-list(schema="brohn-cardiac-source-closure/0.1",root_ref=report_ref,nodes=sort_values(nodes),edges=sort_values(edges),jobs=sort_values(jobs),objects=lapply(sort_values(objects),function(o)o[c("hash","bytes","media_type")]))
 .brohn_cds_require(length(nodes)<=128L&&length(objects)<=256L&&nchar(brohn_json(graph),type="bytes")<=2*1024^2,"source_closure_limit","The cardiac closure exceeds its metadata limits.")
 list(schema="brohn-cardiac-source-metadata/0.1",profile=.brohn_cds_profile,report_ref=report_ref,closure_hash=brohn_eda_value_hash(graph),closure=graph,selected=selected,reports=unname(reports),contexts=unname(contexts),documents=unname(documents),objects=sort_values(objects),streams_validated=FALSE)
}

brohn_cardiac_source_cell_key <- function(report_ref,source_record_index,identity)brohn_eda_value_hash(list(report_ref=report_ref,source_record_index=source_record_index,identity=identity))
brohn_cardiac_source_windows <- function(store,report_ref,cursor=NULL,limit=25L) {
 m<-brohn_cardiac_source_metadata(store,report_ref);s<-m$selected
 .brohn_cds_require(brohn_number(limit,1,100,TRUE),"invalid_page","Choose between 1 and 100 original cardiac records.")
 scope<-brohn_eda_value_hash(list(report_ref=report_ref,closure_hash=m$closure_hash));offset<-0L
 if(!is.null(cursor)){brohn_fields(cursor,c("scope","offset"),label="Original cardiac source page");.brohn_cds_require(identical(cursor$scope,scope)&&brohn_number(cursor$offset,0,s$record_count,TRUE),"stale_cursor","Reopen this exact authorized cardiac source page.");offset<-cursor$offset}
 rows<-DBI::dbGetQuery(store$con,"SELECT CAST(j.key AS INTEGER)+1 record_index,j.value FROM entity_versions v,json_each(v.body_json,'$.analysis.recordings') j WHERE v.kind='report' AND v.id=? AND v.revision=? ORDER BY CAST(j.key AS INTEGER) LIMIT ? OFFSET ?",params=list(report_ref$id,report_ref$revision,as.integer(limit),as.integer(offset)))
 items<-lapply(seq_len(nrow(rows)),function(i){r<-.brohn_cds_json(rows$value[[i]],65536L);idx<-rows$record_index[[i]];identity<-r[intersect(c("recording_id","segment_id","channel","group"),names(r))]
  .brohn_cds_require(brohn_text(r$recording_id,1024)&&brohn_text(r$channel,1024)&&r$status %in% c("computed","unavailable"),"unsupported_record_identity","The original cardiac recording identity or status is unregistered.")
  .brohn_cds_require(!is.null(s$parameters[[r$recording_id]]),"missing_record_parameters","An original cardiac record has no saved effective recipe.")
  bounds<-NULL;if(!is.null(r$start_time_s)&&!is.null(r$end_time_s)){
   .brohn_cds_require(brohn_number(r$start_time_s)&&brohn_number(r$end_time_s)&&r$start_time_s<=r$end_time_s,"invalid_record_bounds","The original cardiac time bounds are malformed.")
   bounds<-list(start_s=.brohn_edd_decimal_parts(.brohn_ecr_shortest(r$start_time_s))$canonical,end_s=.brohn_edd_decimal_parts(.brohn_ecr_shortest(r$end_time_s))$canonical)
  }
  focusable<-identical(r$status,"computed")&&!is.null(bounds)&&r$start_time_s<r$end_time_s
  list(kind="cardiac_source_window",key=brohn_cardiac_source_cell_key(report_ref,idx,identity),identity=identity,source_record_index=idx,source_status=r$status,original_reason=r$reason,
   original_bounds=bounds,focusable=focusable,focus_reason=if(focusable)NULL else brohn_default(r$reason,"original_time_bounds_unavailable"),source_sample_start=r$source_row_start,source_sample_end_exclusive=r$source_row_end_exclusive,original_input_samples=r$samples,unit=r$unit,full_tables_validated=FALSE)
 })
 .brohn_cds_require(identical(brohn_cardiac_source_metadata(store,report_ref)$closure_hash,m$closure_hash),"source_changed","Cardiac source authority or producer proof changed while reading this page.")
 result<-list(schema="brohn-cardiac-source-windows/0.1",source_ref=report_ref,closure_hash=m$closure_hash,total=s$record_count,items=items,cursor=cursor,next_cursor=if(offset+length(items)<s$record_count)list(scope=scope,offset=offset+length(items))else NULL,
  outcome=list(source_status=s$status,original_reason=s$quality$reason,cell_count=s$record_count,exclusion_review_object=NULL,scientific_processing_performed=FALSE))
 .brohn_cds_require(nchar(brohn_json(result),type="bytes")<=2*1024^2,"source_page_bytes","The original cardiac source page exceeds its metadata bound.");result
}

brohn_release_cardiac_display_sources <- function(handle) {
 if(is.environment(handle)&&inherits(handle,"brohn_cardiac_source_resources")&&!isTRUE(handle$state$closed)){
  state<-handle$state;state$closed<-TRUE;for(g in handle$guards)tryCatch(.brohn_qexplorer_release(g),error=function(e)NULL)
 };invisible(NULL)
}
brohn_cardiac_display_sources_current <- function(store,handle) {
 .brohn_cds_require(is.environment(handle)&&inherits(handle,"brohn_cardiac_source_resources")&&environmentIsLocked(handle)&&!isTRUE(handle$state$closed)&&identical(store$workspace_id,handle$workspace_id),"closed_source_handle","Reopen the closed or different-workspace cardiac source handle.")
 .brohn_cm_guard_check(handle$guards);m<-brohn_cardiac_source_metadata(store,handle$metadata$report_ref)
 .brohn_cds_require(identical(m$closure_hash,handle$metadata$closure_hash),"source_changed","Cardiac source permission, original producer or exact identity changed.")
 .brohn_cm_guard_check(handle$guards);invisible(m)
}
brohn_open_cardiac_display_sources <- function(store,report_ref,expected_closure_hash=NULL,pulse=NULL) {
 .brohn_rpk_source_pulse(pulse);m<-brohn_cardiac_source_metadata(store,report_ref)
 .brohn_cds_require(is.null(expected_closure_hash)||identical(expected_closure_hash,m$closure_hash),"source_changed","Reopen the exact original cardiac closure; no new head was substituted.")
 guards<-list();ok<-FALSE;on.exit(if(!ok)for(g in guards).brohn_qexplorer_release(g),add=TRUE)
 guards<-brohn_hold_signal_value_sources(store,list(source_objects=lapply(m$objects,function(o)o[c("hash","bytes")])))
 for(o in m$objects){.brohn_rpk_source_pulse(pulse);brohn_object_path(store,o$hash,TRUE);.brohn_rpk_source_pulse(pulse)}
 complete<-list()
 for(meta in m$reports){.brohn_rpk_source_pulse(pulse);r<-.brohn_rpk_record(store,meta$ref,"report");b<-r$body;original<-brohn_eda_read_json_file(meta$object$path,16*1024^2)
  .brohn_cds_require(identical(original$schema,"brohn-analysis-output/1.0")&&.brohn_rpk_same(original$code_identity,b$processing$code_hashes)&&.brohn_rpk_same(original$report,b[setdiff(names(b),"result_object")])&&identical(brohn_eda_value_hash(original$report$analysis),brohn_eda_value_hash(b$analysis)),"retained_report_mismatch","The catalog differs from the exact sealed original scientific envelope.")
  complete[[length(complete)+1L]]<-list(ref=meta$ref,saved_body=b,complete_analysis=original$report$analysis)
 }
 for(d in m$documents){.brohn_rpk_source_pulse(pulse);original<-brohn_eda_read_json_file(d$object$path,2*1024^2);.brohn_cds_require(.brohn_rpk_same(original,d$body[setdiff(names(d$body),"result_object")]),"retained_context_mismatch","The exact review/preview context differs from its retained publication.")}
 for(context in m$contexts).brohn_edd_validate_lineage_documents(context,pulse)
 .brohn_cds_require(identical(brohn_cardiac_source_metadata(store,report_ref)$closure_hash,m$closure_hash),"source_changed","Cardiac source authority changed while establishing read seals.")
 .brohn_cm_guard_check(guards)
 h<-new.env(parent=emptyenv());class(h)<-"brohn_cardiac_source_resources";h$metadata<-m;h$reports<-complete;h$guards<-guards;h$workspace_id<-store$workspace_id;h$state<-new.env(parent=emptyenv());h$state$closed<-FALSE
 lockEnvironment(h,bindings=TRUE);reg.finalizer(h,brohn_release_cardiac_display_sources,onexit=TRUE);ok<-TRUE;h
}

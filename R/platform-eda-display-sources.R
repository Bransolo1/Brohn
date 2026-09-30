# Exact EDA source and prepared-artifact authority. Metadata paths never decode
# full scientific streams, launch Python, or replace a pinned historical ref.
.brohn_edd_augment_metadata <- function(store,m) {
 if(!identical(m$kind,"eda"))return(m)
 row<-DBI::dbGetQuery(store$con,paste("SELECT json_extract(body_json,'$.analysis.modality') modality,json_extract(body_json,'$.analysis.operation') operation,",
  "json_extract(body_json,'$.analysis.engine') engine,json_extract(body_json,'$.provenance.dataset_revision') dataset_revision,json_extract(body_json,'$.provenance.dataset_hash') dataset_hash,",
  "coalesce(json_array_length(body_json,'$.analysis.recordings'),0) cell_count,",
  "(SELECT json_group_array(DISTINCT json_extract(j.value,'$.recipe')) FROM json_each(body_json,'$.analysis.parameters') j) recipes ",
  "FROM entity_versions WHERE kind='report' AND id=? AND revision=? AND project_id=?"),params=list(m$ref$id,m$ref$revision,m$ref$project_id))
 brohn_require(nrow(row)==1L,"Exact EDA metadata is unavailable.")
 scalar<-function(k){x<-row[[k]][[1L]];if(is.na(x))NULL else x}
 m$eda_modality<-scalar("modality");m$eda_operation<-scalar("operation");m$eda_engine<-.brohn_rpk_parse_optional(row$engine[[1L]],65536L)
 m$eda_recipes<-.brohn_rpk_parse_optional(row$recipes[[1L]],4096L);m$eda_cell_count<-scalar("cell_count")
 m$eda_dataset_ref<-list(kind="dataset",id=m$dataset_id,revision=scalar("dataset_revision"),body_hash=scalar("dataset_hash"),project_id=m$ref$project_id)
 m$eda_source_family<-if(identical(m$eda_operation,"eda_events"))"event"else if(is.null(m$eda_operation))"continuous"else NULL
 m$source_components<-c(m$source_components,list("eda"));m
}
.brohn_edd_unsupported <- function(m,source_admission="task-choice-eda-findings/0.1") {
 spec<-.brohn_edd_profile_spec(.brohn_edd_profile_from_admission(source_admission))
 if(!identical(m$kind,"eda")||!identical(m$schema,"brohn-worker-result/1.0")||!identical(m$eda_modality,"eda")||is.null(m$eda_source_family))return("This saved physiological family has no registered complete EDA report adapter.")
 allowed<-if(m$eda_source_family=="event")c("eda-event-highpass/1.0","eda-event-cvxeda-defaults/1.0")else spec$continuous_recipes
 if(!brohn_array(m$eda_recipes)||!length(m$eda_recipes)||!all(vapply(m$eda_recipes,function(x)is.character(x)&&length(x)==1L&&x %in% allowed,logical(1))))return("This saved EDA recipe is outside the registered event/continuous report profile.")
 if(!length(m$eda_cell_count)||m$eda_cell_count<1L)return("This original EDA report has no saved cells to interpret.")
 if(!length(m$artifacts) %in% c(0L,2L))return("This EDA source requires its exact original zero-or-two processed-stream inventory.")
 if(length(m$artifacts)&&!identical(vapply(m$artifacts,`[[`,character(1),"kind"),c("physiology-series","physiology-events")))return("This EDA report includes unsupported or reordered scientific artifacts.")
 if(m$task_score_count>0L||m$choice_task_count>0L)return("A physiological source cannot mix unregistered task or choice result fields into its EDA envelope.")
 NULL
}
.brohn_edd_descriptor <- function(a) {
 brohn_fields(a,c("hash","size","media_type","kind","schema","complete","rows","tables","provenance_sha256","preview_policy","preview_rows"),label="Original EDA processed stream")
 brohn_require(.brohn_rpk_hash(a$hash)&&brohn_number(a$size,1,64*1024^2,TRUE)&&identical(a$media_type,"application/x-ndjson")&&identical(a$schema,"brohn-physiology-tables/1.0")&&identical(a$complete,TRUE)&&
  a$kind %in% c("physiology-series","physiology-events")&&brohn_number(a$rows,0,1e6,TRUE)&&brohn_number(a$tables,1,256,TRUE)&&.brohn_rpk_hash(a$provenance_sha256)&&brohn_number(a$preview_rows,0,a$rows,TRUE)&&brohn_text(a$preview_policy,500),"An original EDA stream descriptor is unsupported or exceeds its bound.")
 invisible(TRUE)
}
.brohn_edd_exact_dataset <- function(store,ref) {
 .brohn_rpk_ref_catalog(store,ref,"dataset")
 row<-DBI::dbGetQuery(store$con,paste("SELECT json_extract(body_json,'$.id') id,json_extract(body_json,'$.modality') modality,json_extract(body_json,'$.origin') origin,",
  "json_extract(body_json,'$.source') source,json_extract(body_json,'$.metadata') mapping,json_extract(body_json,'$.source_provenance') lineage FROM entity_versions WHERE kind='dataset' AND id=? AND revision=? AND project_id=?"),params=list(ref$id,ref$revision,ref$project_id))
 brohn_require(nrow(row)==1L&&identical(row$id[[1L]],ref$id),"The exact original EDA dataset is missing.")
 current<-DBI::dbGetQuery(store$con,"SELECT e.project_id,coalesce(json_extract(v.body_json,'$.archived'),0) archived FROM entities e JOIN entity_versions v ON e.kind=v.kind AND e.id=v.id AND e.revision=v.revision WHERE e.kind='dataset' AND e.id=?",params=list(ref$id))
 brohn_require(nrow(current)==1L&&identical(current$project_id[[1L]],ref$project_id)&&current$archived[[1L]]==0L,"An original EDA dataset is archived or no longer authorized in this project.")
 list(ref=ref,modality=row$modality[[1L]],origin=row$origin[[1L]],source=.brohn_rpk_parse_optional(row$source[[1L]],65536L),mapping=.brohn_rpk_parse_optional(row$mapping[[1L]],2*1024^2),lineage=.brohn_rpk_parse_optional(row$lineage[[1L]],2*1024^2))
}
.brohn_edd_ingestion <- function(store,dataset) {
 p<-dataset$lineage;if(is.null(p$ingestion_id))return(NULL)
 rows<-DBI::dbGetQuery(store$con,paste("SELECT id,revision,body_hash FROM entity_versions WHERE kind='ingestion' AND id=? AND project_id=?",
  "AND json_extract(body_json,'$.status')='ready' AND json_extract(body_json,'$.dataset_id')=? AND json_extract(body_json,'$.source_object.hash')=? AND json_extract(body_json,'$.review_hash')=?"),params=list(p$ingestion_id,dataset$ref$project_id,dataset$ref$id,dataset$source$hash,p$review_hash))
 brohn_require(nrow(rows)==1L,"The original whole-source ingestion has no unique exact ready publication.")
 ref<-list(kind="ingestion",id=rows$id[[1L]],revision=rows$revision[[1L]],body_hash=rows$body_hash[[1L]],project_id=dataset$ref$project_id)
 r<-.brohn_rpk_record(store,ref,"ingestion");b<-r$body;j<-brohn_get_job(store,b$processing$job_id)
 brohn_require(identical(b$source_object$hash,dataset$source$hash)&&b$source_object$size==dataset$source$size&&identical(b$review_hash,p$review_hash)&&.brohn_rpk_same(b$processing,p$processing)&&
  !is.null(j)&&identical(j$operation,"ingest_source")&&identical(j$status,"succeeded")&&j$attempt==b$processing$attempt&&identical(j$result$dataset_id,dataset$ref$id)&&identical(j$result$source_hash,dataset$source$hash)&&
  identical(j$result$output_hash,b$result_object$hash)&&identical(j$request$source_snapshot_hash,p$source_snapshot_hash),"Original EDA ingestion/source/producer proof changed.")
 list(ref=ref,object=.brohn_rpk_object(store,b$result_object,16*1024^2),dataset_id=dataset$ref$id,body=b)
}
.brohn_edd_source_closure <- function(store,m) {
 d<-.brohn_edd_exact_dataset(store,m$eda_dataset_ref)
 row<-DBI::dbGetQuery(store$con,"SELECT json_extract(body_json,'$.provenance.mapping') mapping,json_extract(body_json,'$.provenance.origin') origin,json_extract(body_json,'$.analysis.source') source FROM entity_versions WHERE kind='report' AND id=? AND revision=? AND project_id=?",params=list(m$ref$id,m$ref$revision,m$ref$project_id))
 source<-.brohn_rpk_parse_optional(row$source[[1L]],65536L)
 brohn_require(identical(d$modality,"eda")&&identical(d$origin,m$origin)&&identical(row$origin[[1L]],m$origin)&&.brohn_rpk_same(d$source,m$original_source)&&.brohn_rpk_same(d$mapping,.brohn_rpk_parse_optional(row$mapping[[1L]],2*1024^2))&&identical(source$sha256,d$source$hash),"The saved EDA source differs from its exact dataset, mapping or origin.")
 objects<-list(.brohn_rpk_object(store,d$source,512*1024^2));ingestion<-.brohn_edd_ingestion(store,d)
 if(!is.null(ingestion))objects<-c(objects,list(ingestion$object))
 for(a in m$artifacts){.brohn_edd_descriptor(a);objects<-c(objects,list(.brohn_rpk_object(store,a,64*1024^2)))}
 # Registered upstream curation is resolved by a separate exact lineage gate.
 lineage<-if(identical(d$lineage$acquisition,"curated_stream")) .brohn_edd_curation_lineage(store,d)else NULL
 if(!is.null(lineage))objects<-c(objects,lineage$objects)
 brohn_require(is.null(d$lineage$parent_acquisition)||!is.null(lineage),"A preserved acquisition requires its registered exact upstream lineage.")
 objects<-.brohn_edd_unique_objects(objects)
 .brohn_edd_limit(length(objects),256L,"source_objects",m$ref,"fewer_sources")
 .brohn_edd_limit(sum(vapply(objects,`[[`,numeric(1),"bytes")),1024^3,"source_bytes",m$ref,"fewer_sources")
 list(dataset=d,ingestion=ingestion,lineage=lineage,objects=objects)
}
.brohn_edd_curation_lineage <- function(store,dataset) {
 p<-dataset$lineage;l<-p$lineage;project<-dataset$ref$project_id
 brohn_require(identical(p$source_hash,dataset$source$hash)&&brohn_valid_id(p$curation_id)&&is.list(l),"The original curated EDA dataset lacks an exact source lineage.")
 exact<-function(kind,id,revision,hash=NULL){row<-DBI::dbGetQuery(store$con,"SELECT body_hash,length(CAST(body_json AS BLOB)) bytes FROM entity_versions WHERE kind=? AND id=? AND revision=? AND project_id=?",params=list(kind,id,revision,project))
  brohn_require(nrow(row)==1L&&row$bytes[[1L]]<=16*1024^2&&(is.null(hash)||identical(hash,row$body_hash[[1L]])),"An exact curated EDA lineage revision is missing, oversized or changed.")
  .brohn_rpk_record(store,list(kind=kind,id=id,revision=revision,body_hash=row$body_hash[[1L]],project_id=project),kind)}
 # The registered curation publisher creates its immutable source at revision1.
 curation<-exact("stream_curation",p$curation_id,1L);c<-curation$body;j<-brohn_get_job(store,c$processing$job_id)
 brohn_require(identical(c$schema,"brohn-stream-curation/1.0")&&identical(c$dataset_id,dataset$ref$id)&&identical(c$origin,dataset$origin)&&.brohn_rpk_same(c$lineage,l)&&.brohn_rpk_same(c$processing,p$processing)&&.brohn_rpk_same(c$extraction$artifacts,p$artifacts)&&.brohn_rpk_same(c$extraction$quality,p$quality)&&
  !is.null(j)&&identical(j$status,"succeeded")&&identical(j$operation,"extract_stream")&&j$attempt==c$processing$attempt&&identical(j$result$curation_id,curation$id)&&identical(j$result$dataset_id,dataset$ref$id)&&identical(j$result$output_hash,c$result_object$hash)&&.brohn_rpk_same(j$request$selection,p$selection),"Curated EDA lineage differs from its original successful extraction publication.")
 stream<-exact("stream",l$stream_id,l$stream_revision,l$stream_hash);imported<-exact("stream_import",l$import_id,l$import_revision,l$import_hash)
 raw_ref<-list(kind="dataset",id=l$raw_dataset_id,revision=l$raw_dataset_revision,body_hash=l$raw_dataset_hash,project_id=project);raw<-.brohn_edd_exact_dataset(store,raw_ref)
 s<-stream$body;b<-imported$body;producer<-brohn_get_job(store,b$processing$job_id)
 brohn_require(identical(s$import_id,imported$id)&&identical(s$source_dataset_id,raw_ref$id)&&s$source_dataset_revision==raw_ref$revision&&identical(s$source_hash,raw$source$hash)&&identical(b$dataset_id,raw_ref$id)&&b$dataset_revision==raw_ref$revision&&identical(b$dataset_hash,raw_ref$body_hash)&&.brohn_rpk_same(b$source,raw$source)&&.brohn_rpk_same(raw$source,l$raw_source)&&.brohn_rpk_same(s$manifest$artifacts,l$original_stream_artifacts)&&
  identical(s$manifest$uid,l$source_uid)&&.brohn_rpk_same(s$manifest$source_id,l$source_id)&&!is.null(producer)&&identical(producer$operation,"normalise_dataset")&&identical(producer$status,"succeeded")&&producer$attempt==b$processing$attempt&&identical(producer$result$import_id,imported$id)&&identical(producer$result$output_hash,b$result_object$hash)&&.brohn_rpk_same(producer$result$stream_ids,b$stream_ids)&&stream$id %in% unlist(b$stream_ids),"Normalized EDA stream/source/import proof differs from its exact original lineage.")
 brohn_validate_stream_selection(s,p$selection)
 csv<-Filter(function(a)identical(a$kind,"curated_signal_csv"),p$artifacts)
 brohn_require(length(csv)==1L&&identical(csv[[1L]]$hash,dataset$source$hash)&&csv[[1L]]$size==dataset$source$size&&all(vapply(c("stream_hash","import_hash","dataset_hash","canonical_hash"),function(k)identical(j$request[[k]],switch(k,stream_hash=l$stream_hash,import_hash=l$import_hash,dataset_hash=l$raw_dataset_hash,canonical_hash=l$canonical_hash)),logical(1))),"Curated EDA CSV or pinned extraction input changed.")
 manifests<-b$manifest$artifacts;brohn_require(any(vapply(manifests,function(a)identical(brohn_default(a$hash,a$sha256),l$canonical_hash),logical(1))),"Original normalized canonical stream object is absent.")
 objects<-c(list(.brohn_rpk_object(store,c$result_object,16*1024^2),.brohn_rpk_object(store,b$result_object,16*1024^2),.brohn_rpk_object(store,raw$source,512*1024^2)),lapply(c(p$artifacts,manifests),function(a).brohn_rpk_object(store,a,512*1024^2)))
 acquisition<-if(is.null(raw$lineage$parent_acquisition))NULL else .brohn_edd_acquisition_lineage(store,raw)
 if(!is.null(acquisition))objects<-c(objects,acquisition$objects)
 raw_ingestion<-.brohn_edd_ingestion(store,raw);if(!is.null(raw_ingestion))objects<-c(objects,list(raw_ingestion$object))
 list(binding=list(curation_ref=.brohn_rpk_ref(curation),stream_ref=.brohn_rpk_ref(stream),import_ref=.brohn_rpk_ref(imported),raw_dataset_ref=raw_ref,raw_ingestion_ref=if(is.null(raw_ingestion))NULL else raw_ingestion$ref,acquisition=acquisition$binding),objects=objects,
  documents=list(list(kind="stream_curation",body=c,object=.brohn_rpk_object(store,c$result_object,16*1024^2)),list(kind="stream_import",body=b,object=.brohn_rpk_object(store,b$result_object,16*1024^2))),raw_ingestion=raw_ingestion,acquisition=acquisition)
}
.brohn_edd_acquisition_lineage <- function(store,dataset) {
 parent<-dataset$lineage$parent_acquisition;project<-dataset$ref$project_id
 rows<-DBI::dbGetQuery(store$con,"SELECT id FROM jobs WHERE operation='acquisition_prepare' AND status='succeeded' AND json_extract(result_json,'$.dataset_id')=? AND json_extract(result_json,'$.acquisition_id')=?",params=list(dataset$ref$id,parent$id))
 brohn_require(nrow(rows)==1L,"The source bundle has no unique exact acquisition review receipt.")
 job<-brohn_get_job(store,rows$id[[1L]]);revision<-job$result$acquisition_revision
 catalog<-.brohn_qexplorer_catalog(store,"acquisition",parent$id,revision,project)
 ref<-list(kind="acquisition",id=parent$id,revision=revision,body_hash=catalog,project_id=project);record<-.brohn_rpk_record(store,ref,"acquisition");b<-record$body
 brohn_require(identical(b$review$status,"prepared")&&identical(b$import_dataset_id,dataset$ref$id)&&identical(b$import_job_id,job$result$dependent_job_id)&&.brohn_rpk_same(b$original,parent$original)&&identical(b$inspection$journal_tip,parent$journal_tip)&&identical(b$completion_status,parent$completion_status)&&identical(b$origin,dataset$origin)&&identical(job$request$schema,"brohn-acquisition-publication/1.0")&&identical(job$request$project_id,project)&&identical(b$review$publication$job_id,job$id)&&identical(b$review$publication$result_object$hash,job$result$result_hash),"Acquisition review differs from the exact preserved source, origin or export publication.")
 preservation<-brohn_get_job(store,b$preservation$job_id);brohn_require(!is.null(preservation)&&identical(preservation$operation,"acquisition_preserve")&&identical(preservation$status,"succeeded")&&identical(preservation$result$acquisition_id,parent$id)&&identical(preservation$result$original_hash,parent$original$hash)&&identical(preservation$result$result_hash,b$preservation$result_object$hash),"Original acquisition preservation proof is missing or changed.")
 original_revision<-preservation$result$acquisition_revision;original_ref<-list(kind="acquisition",id=parent$id,revision=original_revision,body_hash=.brohn_qexplorer_catalog(store,"acquisition",parent$id,original_revision,project),project_id=project)
 original<-.brohn_rpk_record(store,original_ref,"acquisition")
 brohn_require(.brohn_rpk_same(original$body$original,parent$original)&&.brohn_rpk_same(original$body$original_inventory,b$original_inventory)&&identical(original$body$inspection$journal_tip,parent$journal_tip),"Acquisition review substituted its original inventory or journal tip.")
 objects<-lapply(list(parent$original,b$review$publication$result_object,b$preservation$result_object),function(x).brohn_rpk_object(store,x,512*1024^2))
 list(binding=list(review_ref=ref,preservation_ref=original_ref,original=parent$original,journal_tip=parent$journal_tip,completion_status=parent$completion_status),objects=objects,review=record,preservation=original,dataset=dataset)
}
.brohn_edd_unique_objects <- function(objects) {
 unique<-list();for(o in objects){previous<-unique[[o$hash]];if(!is.null(previous))brohn_require(.brohn_rpk_same(previous,o),"One retained EDA object has conflicting descriptors.");unique[[o$hash]]<-o};unname(unique)
}
.brohn_edd_validate_lineage_documents <- function(closure,pulse=NULL) {
 .brohn_rpk_source_pulse(pulse)
 # Called only after the parent has sealed and verified every object in closure.
 ingestion<-function(i){if(is.null(i))return(invisible(NULL));.brohn_rpk_source_pulse(pulse);d<-brohn_eda_read_json_file(i$object$path,16*1024^2)
  brohn_require(identical(d$schema,"brohn-ingestion-publication/1.0")&&.brohn_rpk_same(d$ingestion,i$body[setdiff(names(i$body),"result_object")])&&identical(d$dataset$id,i$dataset_id),"Original ingestion retained document differs from its exact publication.");.brohn_rpk_source_pulse(pulse)}
 ingestion(closure$ingestion);lineage<-closure$lineage;if(is.null(lineage))return(invisible(TRUE))
 ingestion(lineage$raw_ingestion)
 for(x in lineage$documents){.brohn_rpk_source_pulse(pulse);d<-brohn_eda_read_json_file(x$object$path,16*1024^2);expected<-x$body[setdiff(names(x$body),"result_object")]
  if(identical(x$kind,"stream_import")){brohn_require(identical(d$schema,"brohn-analysis-output/1.0")&&.brohn_rpk_same(d$code_identity,x$body$processing$code_hashes),"Original stream import lost its retained worker identity.");d<-d$stream_import}
  brohn_require(.brohn_rpk_same(d,expected),"Original curated/normalized EDA lineage differs from its retained publication document.");.brohn_rpk_source_pulse(pulse)
 }
 acq<-lineage$acquisition;if(!is.null(acq)){
  b<-acq$preservation$body;p<-b$preservation$result_object;b$preservation$result_object<-NULL
  d<-brohn_eda_read_json_file(Filter(function(x)identical(x$hash,p$hash),acq$objects)[[1L]]$path,16*1024^2)
  brohn_require(identical(d$schema,"brohn-acquisition-preservation-result/1.0")&&.brohn_rpk_same(d$acquisition,b),"Original preservation document no longer binds its complete archive/inventory.");.brohn_rpk_source_pulse(pulse)
  b<-acq$review$body;p<-b$review$publication$result_object;b$review$publication$result_object<-NULL
  d<-brohn_eda_read_json_file(Filter(function(x)identical(x$hash,p$hash),acq$objects)[[1L]]$path,16*1024^2)
  brohn_require(identical(d$schema,"brohn-acquisition-review-result/1.0")&&.brohn_rpk_same(d$acquisition,b)&&identical(brohn_hash(d$dataset),acq$dataset$ref$body_hash)&&identical(d$dependent_job$id,b$import_job_id),"Original acquisition review document changed its frozen source dataset or dependent job.");.brohn_rpk_source_pulse(pulse)
 }
 invisible(TRUE)
}

.brohn_rpk_eda_requirements <- function(store,report_refs,source_admission) {
 brohn_require(.brohn_edd_is_admission(.brohn_rpk_admission(source_admission))&&brohn_array(report_refs)&&length(report_refs)>0L&&length(report_refs)<=8L,"Choose up to eight exact reports for the EDA package profile.")
 seen<-active<-root_seen<-character();nodes<-edges<-related<-required<-list();study<-NULL
 selected_keys<-vapply(report_refs,brohn_hash,character(1));brohn_require(!anyDuplicated(selected_keys),"Choose each exact report once.")
 parents<-function(m){out<-list();for(i in seq_along(m$sources)){s<-m$sources[[i]];if(identical(s$state,"selected"))out<-c(out,list(list(ref=list(kind="report",id=s$id,revision=s$revision,body_hash=s$hash,project_id=m$ref$project_id),slot="provenance.selection",index=i)))}
  if(identical(m$source_family,"saved_task_cohort"))for(i in seq_along(m$cohort_sources)){s<-m$cohort_sources[[i]];out<-c(out,list(list(ref=list(kind="report",id=s$id,revision=s$revision,body_hash=s$body_hash,project_id=m$ref$project_id),slot="provenance.source_reports",index=i)))};out}
 walk<-function(ref,root){key<-brohn_hash(ref);brohn_require(!key %in% active,"The EDA source identity graph contains a cycle.");if(key %in% root_seen)return(invisible(NULL));root_seen<<-c(root_seen,key)
  active<<-c(active,key);on.exit(active<<-setdiff(active,key),add=TRUE)
  m<-.brohn_rpk_report_metadata(store,ref);object<-.brohn_rpk_report_proof(store,m,source_admission=source_admission)
  if(is.null(study))study<<-m$study_id;brohn_require(identical(study,m$study_id)&&identical(ref$project_id,report_refs[[1L]]$project_id),"Required EDA sources must belong to the same study and project.")
  first<-!key %in% seen
  if(first){seen<<-c(seen,key);brohn_require(length(seen)<=32L,"The complete source graph exceeds 32 exact reports.")
   ordinal<-match(key,selected_keys);if(is.na(ordinal))ordinal<-NULL
   if(identical(m$kind,"eda")){
    required[[length(required)+1L]]<<-ref
    if(is.null(ordinal)){ordinal<-length(report_refs)+length(related)+1L;related[[key]]<<-list(source_ordinal=ordinal,report_ref=ref,required_by=list(),parent_edges=list())}
   }
   nodes[[key]]<<-list(ref=ref,analysis_kind=m$kind,source_ordinal=ordinal,retained_report=.brohn_td_object_ref(object))
  }
  if(!is.null(related[[key]])){item<-related[[key]];if(!any(vapply(item$required_by,function(x).brohn_rpk_same(x,root),logical(1))))item$required_by<-c(item$required_by,list(root));related[[key]]<<-item}
  for(parent in parents(m)){
   edge<-list(child_ref=ref,parent_ref=parent$ref,parent_slot=parent$slot,parent_index=parent$index)
   if(!any(vapply(edges,function(x).brohn_rpk_same(x,edge),logical(1))))edges[[length(edges)+1L]]<<-edge
   walk(parent$ref,root)
  }
 }
 for(ref in report_refs){root_seen<-character();walk(ref,ref)}
 for(key in names(related)){item<-related[[key]];item$parent_edges<-Filter(function(e).brohn_rpk_same(e$parent_ref,item$report_ref),edges);related[[key]]<-item}
 # Selected EDA keeps selection order; related EDA keeps deterministic DFS order.
 selected<-Filter(function(ref)identical(nodes[[brohn_hash(ref)]]$analysis_kind,"eda"),report_refs)
 required<-c(selected,lapply(related,`[[`,"report_ref"))
 list(required_eda_refs=unname(required),related_eda_refs=unname(related),source_identity_graph_binding=list(schema="brohn-report-source-identity-graph/0.1",root_refs=report_refs,nodes=unname(nodes),edges=edges))
}

.brohn_edd_streams <- function(store,report)lapply(seq_along(report$complete_analysis$artifacts),function(i){a<-report$complete_analysis$artifacts[[i]]
 list(original=a,original_verification=report$complete_analysis$artifact_verification$artifacts[[i]],path=brohn_object_path(store,a$hash,FALSE))})
.brohn_edd_complete_package_sources <- function(store,handle,complete,result,pulse=NULL) {
 .brohn_rpk_source_pulse(pulse)
 m<-handle$metadata;requirements<-.brohn_rpk_eda_requirements(store,m$report_refs,m$source_admission)
 .brohn_edd_validate_source_edges(complete,m$source_admission)
 graph<-requirements$source_identity_graph_binding
 graph$nodes<-lapply(graph$nodes,function(node){.brohn_rpk_source_pulse(pulse);report<-complete[[brohn_hash(node$ref)]];brohn_require(!is.null(report),"An exact source graph node was not sealed before hydration.")
  p<-report$saved_body$provenance;keys<-intersect(c("selection","source_reports"),names(p))
  if(identical(node$analysis_kind,"multimodal"))keys<-c(keys,intersect(c("crosswalk","crosswalk_hash","identity_source"),names(p)))
  context<-p[keys];if(!length(context))context<-structure(list(),names=character())
  if(!is.null(context$crosswalk))brohn_require(identical(brohn_hash(context$crosswalk),context$crosswalk_hash),"Original reviewed source crosswalk hash changed.")
  node$provenance_context<-context;node$context_hash<-brohn_hash(context);node})
 .brohn_edd_limit(nchar(brohn_json(lapply(graph$nodes,`[[`,"provenance_context")),type="bytes"),16*1024^2,"graph_context_bytes",recovery="fewer_sources")
 result$source_identity_graph<-graph
 result$eda_displays<-lapply(m$eda_displays,function(meta){.brohn_rpk_source_pulse(pulse);b<-meta$record$body;original<-brohn_eda_read_json_file(meta$document$path,2*1024^2)
  brohn_require(.brohn_rpk_same(original,b[setdiff(names(b),"retained_document")]),"EDA display metadata differs from its sealed publication document.")
  report<-complete[[brohn_hash(meta$report_ref)]];evidence<-brohn_eda_read_json_file(meta$object$path,24*1024^2)
  .brohn_rpk_source_pulse(pulse)
  brohn_validate_eda_display_evidence(evidence,report,b,pulse)
  list(ref=meta$ref,body=b,evidence=meta$object,streams=.brohn_edd_streams(store,report))})
 result$related_eda_sources<-lapply(requirements$related_eda_refs,function(x){prepared<-Filter(function(d).brohn_rpk_same(d$report_ref,x$report_ref),m$eda_displays)
  list(source_ordinal=x$source_ordinal,report=complete[[brohn_hash(x$report_ref)]],required_by=x$required_by,parent_edges=x$parent_edges,prepared_ref=if(length(prepared)==1L)prepared[[1L]]$ref else NULL)})
 .brohn_rpk_source_pulse(pulse)
 result
}
.brohn_edd_validate_observation <- function(o,source_admission="task-choice-eda-findings/0.1") {
 required<-c("source_report_id","source_report_revision","source_report_hash","source_design_hash","source_container","source_row","source_row_hash","source_participant_id","source_session_id","source_recording_id","source_segment_id","source_exposure_id","stimulus_id","condition_id","modality","metric","outcome_id","unit","value","source_eligible","source_missing_reason","definition_hash","definition","support","origin","exposure_id","eligible")
 brohn_fields(o,required,c("participant_id","session_id","missing_reason"),"Saved combined EDA source observation")
 brohn_require(identical(o$modality,"eda")&&identical(o$source_container,"features")&&brohn_number(o$source_row,1,1e6,TRUE)&&brohn_number(o$source_report_revision,1,1e9,TRUE)&&all(vapply(o[c("source_report_hash","source_design_hash","source_row_hash","definition_hash")],.brohn_rpk_hash,logical(1)))&&identical(brohn_hash(o$definition),o$definition_hash)&&brohn_text(o$metric,200)&&brohn_text(o$unit,120)&&(is.null(o$value)||brohn_number(o$value))&&is.logical(o$source_eligible)&&length(o$source_eligible)==1L&&is.logical(o$eligible)&&length(o$eligible)==1L,"Saved EDA source observation types or provenance hashes changed.")
 brohn_fields(o$definition,c("recipe","dimensions","scope"),label="Original EDA measure definition")
 spec<-.brohn_edd_profile_spec(.brohn_edd_profile_from_admission(source_admission))
 .brohn_edd_recipe(o$definition$recipe,FALSE,spec)
 brohn_require(o$definition$scope %in% c("recording","recording_condition")&&!length(o$definition$dimensions),"This saved EDA synthesis definition is not registered.")
 if(identical(o$support$status,"descriptive_only")){
  .brohn_edd_constant_support(o$support,o$definition$recipe)
  raw<-identical(o$metric,"conductance_raw_mean")
  brohn_require(o$metric %in% c("tonic_mean","tonic_median","tonic_slope","conductance_raw_mean","scr_count","scr_rate","scr_amplitude_mean","scr_amplitude_median","phasic_area_signed","phasic_area_positive")&&identical(o$source_eligible,raw)&&identical(o$source_missing_reason,if(raw)NULL else"exact_constant_signal")&&(if(raw)brohn_number(o$value,0)else is.null(o$value))&&(!isTRUE(o$eligible)||raw),"Constant EDA synthesis changed descriptive versus unavailable response support.")
 }
 invisible(TRUE)
}
.brohn_edd_validate_source_edges <- function(complete,source_admission="task-choice-eda-findings/0.1") {
 for(report in complete)if(identical(report$complete_analysis$kind,"multimodal")){
  p<-report$saved_body$provenance
  brohn_require(identical(brohn_hash(p$crosswalk),p$crosswalk_hash),"The reviewed source identity crosswalk changed.")
  for(o in report$complete_analysis$observations)if(identical(o$modality,"eda")){
   .brohn_edd_validate_observation(o,source_admission)
   parent<-Filter(function(x)identical(x$state,"selected")&&identical(x$id,o$source_report_id)&&x$revision==o$source_report_revision&&identical(x$hash,o$source_report_hash),p$selection)
   brohn_require(length(parent)==1L,"A combined EDA observation has no unique exact selected parent.")
   ref<-list(kind="report",id=parent[[1L]]$id,revision=parent[[1L]]$revision,body_hash=parent[[1L]]$hash,project_id=report$ref$project_id)
   source<-complete[[brohn_hash(ref)]];brohn_require(!is.null(source)&&identical(source$complete_analysis$kind,"eda")&&o$source_row<=length(source$complete_analysis$features),"The complete original EDA parent row was not retained.")
   f<-source$complete_analysis$features[[o$source_row]];a<-source$complete_analysis
   brohn_require(identical(brohn_hash(f),o$source_row_hash)&&identical(source$saved_body$provenance$design_hash,o$source_design_hash)&&identical(brohn_eda_value_hash(f$value),brohn_eda_value_hash(o$value))&&identical(f$name,o$metric)&&identical(f$unit,o$unit)&&identical(f$recording_id,o$source_recording_id)&&identical(f$segment_id,o$source_segment_id)&&.brohn_rpk_same(f$group$participant_id,o$source_participant_id)&&.brohn_rpk_same(f$group$session_id,o$source_session_id),"Combined EDA value or original row/recording/person identity differs from its exact parent.")
   matching<-Filter(function(r)identical(r$recording_id,f$recording_id)&&(is.null(f$segment_id)||identical(r$segment_id,f$segment_id))&&(is.null(r$channel)||identical(r$channel,f$channel))&&(is.null(f$condition_id)||identical(r$condition_id,f$condition_id)),a$recordings)
   support<-if(length(matching)==1L)matching[[1L]]else list(status="unavailable")
   if(identical(support$status,"descriptive_only"))brohn_require(identical(o$source_eligible,f$eligible)&&identical(o$source_missing_reason,f$missing_reason),"Combined constant EDA eligibility differs from the original feature row.")
   brohn_require(identical(brohn_eda_value_hash(support),brohn_eda_value_hash(o$support))&&.brohn_rpk_same(o$definition$recipe,a$parameters[[f$recording_id]])&&identical(o$definition$scope,f$scope),"Combined EDA support/recipe differs from its exact original cell.")
   maps<-Filter(function(x)identical(x$report_id,ref$id)&&identical(x$source_participant_id,o$source_participant_id)&&identical(x$source_session_id,o$source_session_id),p$crosswalk)
   brohn_require(length(maps)<=1L,"The original reviewed EDA identity bridge is ambiguous.")
   if(length(maps))brohn_require(identical(o$participant_id,maps[[1L]]$participant_id)&&identical(o$session_id,maps[[1L]]$session_id),"Combined EDA reviewed person/session no longer matches the exact crosswalk.")else brohn_require(is.null(o$participant_id)&&is.null(o$session_id)&&identical(o$eligible,FALSE),"Unlinked EDA evidence cannot invent a reviewed identity.")
  }
 };invisible(TRUE)
}
.brohn_edd_metadata <- function(store,ref) {
 .brohn_rpk_ref_catalog(store,ref,"eda_display")
 row<-DBI::dbGetQuery(store$con,"SELECT length(CAST(body_json AS BLOB)) bytes FROM entity_versions WHERE kind='eda_display' AND id=? AND revision=? AND project_id=?",params=list(ref$id,ref$revision,ref$project_id))
 brohn_require(nrow(row)==1L&&row$bytes[[1L]]<=2*1024^2,"Saved EDA metadata exceeds its bounded reader.")
 record<-.brohn_rpk_record(store,ref,"eda_display");b<-record$body;spec<-.brohn_edd_profile_spec(b$preparation_profile)
 brohn_fields(b,c("schema","study_id","project_id","source_family","source","display_request","preparation_profile","implementation","implementation_hash","input_binding_hash","coverage","catalog","artifact","artifact_schema","retained_document","producer"),label="Saved EDA display")
 brohn_require(identical(b$schema,spec$body_schema)&&identical(b$artifact_schema,spec$evidence_schema)&&identical(b$preparation_profile,spec$profile)&&identical(b$implementation$profile,spec$profile)&&identical(b$project_id,ref$project_id)&&b$source_family %in% c("event","continuous")&&identical(b$implementation_hash,brohn_hash(b$implementation))&&.brohn_rpk_same(b$display_request,brohn_normalize_eda_display_request(b$display_request)),"Saved EDA display identity or window request is unsupported.")
 source<-.brohn_rpk_report_metadata(store,b$source$report_ref);.brohn_rpk_report_proof(store,source,source_admission=spec$admission)
 context<-.brohn_edd_source_closure(store,source)
 brohn_require(identical(b$study_id,source$study_id)&&identical(b$source_family,source$eda_source_family)&&.brohn_rpk_same(b$source$result_object,.brohn_td_object_ref(source$result_object))&&.brohn_rpk_same(b$source$dataset_ref,source$eda_dataset_ref)&&.brohn_rpk_same(b$source$original_stream_descriptors,source$artifacts),"Saved EDA preparation lost its exact original source.")
 object<-.brohn_rpk_object(store,b$artifact,24*1024^2);document<-.brohn_rpk_object(store,b$retained_document,2*1024^2)
 p<-b$producer;brohn_fields(p,c("job_id","attempt","request_hash","worker_result_hash"),label="EDA producer proof");j<-brohn_get_job(store,p$job_id)
 brohn_require(!is.null(j)&&identical(j$operation,"eda_display")&&identical(j$status,"succeeded")&&j$attempt==p$attempt&&identical(j$result$eda_display_id,ref$id)&&identical(j$result$output_hash,document$hash)&&identical(brohn_hash(j$request),p$request_hash)&&identical(j$request$schema,"brohn-eda-display-job/0.1")&&identical(j$request$preparation_profile,spec$profile)&&.brohn_rpk_same(j$request$report_ref,b$source$report_ref)&&.brohn_rpk_same(j$request$implementation,b$implementation)&&.brohn_rpk_same(j$request$display_request,b$display_request)&&identical(j$request$content_fingerprint,b$input_binding_hash),"Saved EDA display differs from its original successful worker proof.")
 frozen<-.brohn_edd_context(store,b$source$report_ref,spec$profile)$closure
 brohn_require(identical(b$source$source_closure_hash,brohn_hash(frozen))&&.brohn_rpk_same(j$request$original_closure,frozen)&&identical(j$request$content_fingerprint,brohn_hash(j$request[setdiff(names(j$request),c("authority","content_fingerprint"))])),"Saved EDA original source closure or producer fingerprint changed.")
 list(ref=ref,record=record,report_ref=b$source$report_ref,object=object,document=document,source_admission=spec$admission)
}
brohn_find_eda_display <- function(store,report_ref,display_request=NULL,preparation_profile="saved-eda-display/0.1",implementation_ref=brohn_eda_display_implementation_ref(preparation_profile)) {
 .brohn_rpk_ref_catalog(store,report_ref,"report");request<-brohn_normalize_eda_display_request(display_request)
 spec<-.brohn_edd_profile_spec(preparation_profile)
 brohn_require(identical(implementation_ref$profile,spec$profile)&&.brohn_rpk_hash(implementation_ref$hash),"Choose an exact EDA preparation identity.")
 rows<-DBI::dbGetQuery(store$con,paste("SELECT v.id,v.revision,v.body_hash,v.body_json FROM entities e JOIN entity_versions v ON e.kind=v.kind AND e.id=v.id AND e.revision=v.revision",
  "WHERE e.kind='eda_display' AND e.project_id=? AND json_extract(v.body_json,'$.source.report_ref.id')=? AND json_extract(v.body_json,'$.source.report_ref.revision')=?",
  "AND json_extract(v.body_json,'$.source.report_ref.body_hash')=? AND json_extract(v.body_json,'$.preparation_profile')=? AND json_extract(v.body_json,'$.implementation_hash')=? AND json_extract(v.body_json,'$.display_request')=json(?) ORDER BY e.updated_at DESC,e.id DESC LIMIT 1"),params=list(report_ref$project_id,report_ref$id,report_ref$revision,report_ref$body_hash,preparation_profile,implementation_ref$hash,brohn_json(request)))
 if(!nrow(rows))return(NULL)
 ref<-list(kind="eda_display",id=rows$id[[1L]],revision=rows$revision[[1L]],body_hash=rows$body_hash[[1L]],project_id=report_ref$project_id);.brohn_edd_metadata(store,ref);ref
}
brohn_eda_display_catalog <- function(store,display_ref,cursor=NULL,limit=25L) {
 meta<-.brohn_edd_metadata(store,display_ref);b<-meta$record$body
 brohn_require(brohn_number(limit,1,100,TRUE),"Choose a bounded EDA catalog page.");scope<-brohn_hash(display_ref);offset<-0L
 if(!is.null(cursor)){brohn_fields(cursor,c("scope","offset"),label="EDA catalog page");brohn_require(identical(cursor$scope,scope)&&brohn_number(cursor$offset,0,2000,TRUE),"Reopen this exact EDA preparation page.");offset<-cursor$offset}
 items<-if(offset>=length(b$catalog))list()else b$catalog[seq.int(offset+1L,min(length(b$catalog),offset+limit))]
 list(report_ref=b$source$report_ref,source_family=b$source_family,state="ready",prepared_ref=display_ref,display_request=b$display_request,display_request_hash=brohn_hash(b$display_request),items=items,cursor=cursor,next_cursor=if(offset+length(items)<length(b$catalog))list(scope=scope,offset=offset+length(items))else NULL,requires_display_preparation=FALSE,reason=NULL,dependency=NULL)
}
brohn_eda_source_windows <- function(store,report_ref,cursor=NULL,limit=25L) {
 context<-.brohn_edd_context(store,report_ref,"saved-eda-display/0.2");m<-context$selected
 brohn_require(identical(m$eda_source_family,"continuous")&&brohn_number(m$eda_cell_count,1,2000,TRUE)&&brohn_number(limit,1,100,TRUE),"Choose a bounded page from an exact saved continuous EDA source.")
 binding<-brohn_hash(context$closure);scope<-brohn_hash(list(report_ref=report_ref,source_binding_hash=binding));offset<-0L
 if(!is.null(cursor)){brohn_fields(cursor,c("scope","offset"),label="Original EDA window page");brohn_require(identical(cursor$scope,scope)&&brohn_number(cursor$offset,0,m$eda_cell_count,TRUE),"Reopen windows from this exact authorized EDA source.");offset<-cursor$offset}
 rows<-DBI::dbGetQuery(store$con,paste("SELECT CAST(j.key AS INTEGER)+1 source_record_index,",
  "json_extract(j.value,'$.recording_id') recording_id,json_extract(j.value,'$.segment_id') segment_id,json_extract(j.value,'$.channel') channel,",
  "json_extract(j.value,'$.status') status,json_extract(j.value,'$.reason') reason,",
  "json_extract(j.value,'$.start_time_s') start_time_s,json_extract(j.value,'$.end_time_s') end_time_s",
  "FROM entity_versions v,json_each(v.body_json,'$.analysis.recordings') j WHERE v.kind='report' AND v.id=? AND v.revision=? AND v.project_id=?",
  "ORDER BY CAST(j.key AS INTEGER) LIMIT ? OFFSET ?"),params=list(report_ref$id,report_ref$revision,report_ref$project_id,as.integer(limit),as.integer(offset)))
 scalar<-function(i,k){x<-rows[[k]][[i]];if(is.na(x))NULL else x}
 items<-lapply(seq_len(nrow(rows)),function(i){
  identity<-list(recording_id=scalar(i,"recording_id"),segment_id=scalar(i,"segment_id"),channel=scalar(i,"channel"));status<-scalar(i,"status");reason<-scalar(i,"reason")
  brohn_require(brohn_text(identity$recording_id,1024)&&brohn_text(identity$channel,1024)&&(is.null(identity$segment_id)||brohn_text(identity$segment_id,1024))&&status %in% c("computed","unavailable","descriptive_only"),"Original EDA window identity or status is unregistered.")
  focusable<-identical(status,"computed");bounds<-NULL
  if(status %in% c("computed","descriptive_only")){start<-scalar(i,"start_time_s");end<-scalar(i,"end_time_s");brohn_require(brohn_number(start)&&brohn_number(end)&&start<end,"Original EDA window bounds are unavailable.")
   bounds<-list(start_s=.brohn_edd_decimal_parts(.brohn_ecr_shortest(start))$canonical,end_s=.brohn_edd_decimal_parts(.brohn_ecr_shortest(end))$canonical)}
  list(kind="eda_source_window",key=brohn_eda_value_hash(list(report_ref=report_ref,source_family="continuous",identity=identity)),identity=identity,
   source_record_index=as.integer(rows$source_record_index[[i]]),label=paste(unlist(identity,use.names=FALSE),collapse=" | "),original_default_bounds=bounds,
   focusable=focusable,focus_reason=if(focusable)NULL else if(identical(status,"descriptive_only"))"exact_constant_signal"else brohn_default(reason,"no_processed_segment"),original_status=status)
 })
 brohn_require(.brohn_rpk_same(.brohn_edd_context(store,report_ref,"saved-eda-display/0.2")$closure,context$closure),"Original EDA source authority changed while reading its window bounds.")
 result<-list(schema="brohn-eda-source-windows/0.1",report_ref=report_ref,source_family="continuous",source_binding_hash=binding,total=m$eda_cell_count,
  items=items,cursor=cursor,next_cursor=if(offset+length(items)<m$eda_cell_count)list(scope=scope,offset=offset+length(items))else NULL)
 brohn_require(nchar(brohn_json(result),type="bytes")<=2*1024^2,"The bounded original EDA window page is too large.")
 result
}
.brohn_edd_selector_catalog <- function(store,report_ref,adapter,cursor=NULL,limit=25L,prepared_ref=NULL) {
 spec<-if(is.null(prepared_ref)).brohn_edd_profile_spec("saved-eda-display/0.2")else .brohn_edd_profile_spec(.brohn_edd_metadata(store,prepared_ref)$record$body$preparation_profile)
 m<-.brohn_rpk_report_metadata(store,report_ref);.brohn_rpk_report_proof(store,m,source_admission=spec$admission)
 brohn_require(identical(adapter,if(identical(m$eda_source_family,"event"))"eda-events"else"eda-continuous"),"Choose this exact saved EDA family.")
 ref<-if(is.null(prepared_ref))brohn_find_eda_display(store,report_ref,preparation_profile=spec$profile)else prepared_ref
 if(is.null(ref)){brohn_require(is.null(cursor)&&brohn_number(limit,1,100,TRUE),"Prepare this exact EDA source before opening catalog pages.")
  return(list(report_ref=report_ref,adapter=adapter,state="needs_preparation",source_family=m$eda_source_family,items=list(),cursor=NULL,next_cursor=NULL,requires_display_preparation=TRUE,prepared_ref=NULL,reason=NULL,dependency=NULL))}
 c<-brohn_eda_display_catalog(store,ref,cursor,limit);brohn_require(.brohn_rpk_same(c$report_ref,report_ref),"The EDA catalog belongs to another exact report.")
 c$items<-lapply(c$items,function(item)list(selector=list(scope="exact_cells",keys=list(item$key)),label=item$label,details=item));c$adapter<-adapter;c
}
brohn_release_eda_display_sources <- function(handle).brohn_rpk_release(handle)
brohn_eda_display_sources_current <- function(store,handle)brohn_report_package_sources_current(store,handle)
brohn_release_eda_display_resources <- function(handle) {
 if(is.environment(handle)&&inherits(handle,"brohn_eda_display_resources")&&is.environment(handle$state)&&!isTRUE(handle$state$closed)){state<-handle$state;state$closed<-TRUE;.brohn_rpk_release(handle$source_handle)};invisible(NULL)
}
brohn_open_eda_display_resources <- function(store,ref,project_id) {
 brohn_require(identical(ref$project_id,project_id),"Choose the saved EDA display's exact project.")
 meta<-.brohn_edd_metadata(store,ref);m<-.brohn_rpk_source_metadata(store,list(meta$report_ref),source_admission=meta$source_admission,eda_refs=list(ref));handle<-.brohn_rpk_hold_sources(store,m)
 ok<-FALSE;on.exit(if(!ok).brohn_rpk_release(handle),add=TRUE);full<-.brohn_rpk_complete_sources(store,handle)$eda_displays[[1L]]
 brohn_require(.brohn_rpk_same(.brohn_edd_metadata(store,ref),meta),"EDA source authority changed while opening its complete evidence.")
 h<-new.env(parent=emptyenv());class(h)<-"brohn_eda_display_resources";h$state<-new.env(parent=emptyenv());h$state$closed<-FALSE;h$ref<-ref;h$metadata<-meta;h$source_handle<-handle;h$workspace_id<-store$workspace_id
 lockEnvironment(h,bindings=TRUE);reg.finalizer(h,brohn_release_eda_display_resources,onexit=TRUE);ok<-TRUE
 list(record=meta$record,handle=h,evidence=brohn_eda_read_json_file(full$evidence$path,24*1024^2),artifact=c(list(file="eda-display.json"),meta$object))
}
brohn_eda_display_resources_current <- function(store,handle) {
 brohn_require(is.environment(handle)&&inherits(handle,"brohn_eda_display_resources")&&environmentIsLocked(handle)&&!isTRUE(handle$state$closed)&&identical(handle$workspace_id,store$workspace_id),"Reopen this closed or different-workspace EDA display.")
 brohn_report_package_sources_current(store,handle$source_handle);meta<-.brohn_edd_metadata(store,handle$ref);brohn_require(.brohn_rpk_same(meta,handle$metadata),"EDA current source permission or exact producer proof changed.")
 list(record=meta$record,artifact=c(list(file="eda-display.json"),meta$object))
}

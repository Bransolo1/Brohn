# Portable context for the separately registered saved cardiac package profile.
# Scientific bytes stay in the existing complete payloads; this module is pure.
.brohn_rpcc_provenance_record <- function(item,entry) {
  brohn_fields(item,c("ref","saved_body","complete_analysis"),label="Original cardiac provenance source")
  r<-item$ref;b<-item$saved_body;a<-item$complete_analysis
  .brohn_rpca_ref(r)
  brohn_fields(b,c("id","title","origin","analysis","provenance"),
    c("schema_version","created_at","status","study_id","dataset_id","project_id","processing","result_object","session_quality"),"Original cardiac report context")
  brohn_require(identical(r$body_hash,brohn_hash(b))&&identical(r$id,b$id)&&
    identical(r$project_id,entry$ref$project_id)&&identical(b$study_id,entry$body$study_id)&&
    a$kind %in% c("ecg","ppg")&&.brohn_rpca_same(b$analysis,a),"The original cardiac body, complete analysis, study or exact identity changed.")
  if("project_id"%in%names(b))brohn_require(identical(b$project_id,r$project_id),"The cardiac report project changed.")
  .brohn_rpcc_provenance_membership(item,entry)
  p<-b$provenance
  brohn_fields(p,c("design","design_hash"),c("engine","origin","study_id","study_revision","source","mapping","dataset_id","dataset_revision","dataset_hash","cardiac_review"),"Original cardiac scientific provenance")
  brohn_require(is.list(p$design)&&identical(brohn_hash(p$design),p$design_hash)&&
    identical(p$design$id,b$study_id)&&identical(p$design$project_id,r$project_id)&&identical(p$study_id,b$study_id)&&identical(p$origin,b$origin)&&
    identical(p$dataset_id,b$dataset_id),"The saved cardiac design, origin, dataset or study binding changed.")
  brohn_validate_design(p$design)
  if(!is.null(b$processing))brohn_fields(b$processing,c("recipe"),c("code_hashes","output_hash","request_hash","attempt","job_id","publication"),"Original cardiac producer")
  if(!is.null(p$source))brohn_fields(p$source,c("hash"),c("size","bytes","media_type","format","filename","path","name"),"Original cardiac source descriptor")
  # Preserve the saved descriptor spelling, but never copy a held object path.
  brohn_fields(b$result_object,c("hash","media_type"),c("size","bytes"),"Original cardiac result descriptor")
  o<-.brohn_td_object_ref(b$result_object)
  brohn_require(.brohn_rpk_hash(o$hash)&&brohn_number(o$bytes,1,16*1024^2,TRUE)&&
    identical(o$media_type,"application/json")&&
    (!("size"%in%names(b$result_object)&&"bytes"%in%names(b$result_object))||b$result_object$size==b$result_object$bytes),"The original cardiac result descriptor is invalid.")
  list(source_ref=r,saved_body_value_hash=brohn_eda_value_hash(b),analysis_hash=brohn_hash(a),
    analysis_value_hash=brohn_eda_value_hash(a),design_hash=p$design_hash,source_result_object=b$result_object)
}

.brohn_rpcc_portable_context <- function(b) {
  p<-b$provenance;omitted<-list()
  omit<-function(x,keys,path){actual<-intersect(keys,names(x));for(k in actual)omitted[[length(omitted)+1L]]<<-paste0(path,"/",k);x[setdiff(names(x),actual)]}
  assets<-function(x,path){
    if(!is.list(x))return(x)
    registered<-"^/provenance/design/(stimuli/[0-9]+/asset|blocks/[0-9]+/(materials/[0-9]+/asset|protocol_registry)|welcome/asset|questions/[0-9]+/illustration/asset|maxdiff/[0-9]+/items/[0-9]+/illustration/asset)$"
    if(grepl(registered,path))return(omit(x,c("filename","path"),path))
    if(is.null(names(x)))return(lapply(seq_along(x),function(i)assets(x[[i]],paste0(path,"/",i-1L))))
    for(k in names(x))x[k]<-list(assets(x[[k]],paste0(path,"/",k)))
    x
  }
  if(!is.null(p$source))p$source<-omit(p$source,c("filename","path","name"),"/provenance/source")
  p$design<-assets(p$design,"/provenance/design")
  if("project_id"%in%names(b))omitted[[length(omitted)+1L]]<-"/report/project_id"
  producer<-b$processing
  if(!is.null(producer))producer<-omit(producer,c("job_id","attempt","publication"),"/report/processing")
  value<-list(report=b[intersect(c("id","title","origin","schema_version","created_at","status","study_id","dataset_id"),names(b))],
    provenance=p,projected_design_value_hash=brohn_eda_value_hash(p$design),producer=producer,omitted_operational_fields=omitted)
  if("session_quality"%in%names(b))value["session_quality"]<-list(b$session_quality)
  value
}

.brohn_rpcc_provenance_model <- function(item,entry) {
  brohn_fields(item,c("ref","saved_body","complete_analysis"),label="Original cardiac provenance source")
  brohn_require(identical(item$ref$body_hash,brohn_hash(item$saved_body)),"The original cardiac provenance body changed before export.")
  brohn_report_package_cardiac_entry_validate(entry)
  bindings<-lapply(entry$source_reports,.brohn_rpcc_provenance_record,entry=entry)
  selected<-.brohn_rpca_one(entry$source_reports,function(x).brohn_rpca_same(x$ref,item$ref),"The exact original context is absent from this cardiac entry.")
  brohn_require(.brohn_rpca_same(item,selected)&&.brohn_rpca_same(item$ref,entry$evidence$source_ref)&&
    identical(brohn_hash(item$complete_analysis),entry$body$source$analysis_hash)&&
    identical(brohn_eda_value_hash(item$complete_analysis),entry$body$source$analysis_value_hash),"The exported cardiac context belongs to another original or prepared source.")
  .brohn_rpcc_provenance_value(item,entry,bindings)
}
.brohn_rpcc_provenance_value <- function(item,entry,bindings) {
  b<-item$saved_body;context<-.brohn_rpcc_portable_context(b)
  value<-list(schema="brohn-portable-cardiac-provenance/0.1",source_ref=item$ref,prepared_ref=entry$ref,
    source_body_hash=item$ref$body_hash,source_analysis_hash=entry$body$source$analysis_hash,
    source_analysis_value_hash=entry$body$source$analysis_value_hash,source_result_object=b$result_object,
    source_closure_hash=entry$evidence$closure_hash,display_request=entry$body$display_request,
    display_request_value_hash=entry$evidence$display_request_hash,source_report_bindings=bindings,
    report=context$report,provenance=context$provenance,projected_design_value_hash=context$projected_design_value_hash,producer=context$producer)
  if("session_quality"%in%names(b))value["session_quality"]<-list(b$session_quality)
  value$policy<-list(profile="saved-cardiac-provenance/0.1",identifier_mode="source_identifiers",
    scientific_values="Original analysis, typed streams, CSV tables, markers, exclusions and curation crosswalks remain in their unchanged complete payloads.",
    identifiers="Exact original source identifiers and free text are preserved. This is not anonymization.",
    omitted_operational_fields=context$omitted_operational_fields,original_raw_bytes_reverified=FALSE)
  value
}

.brohn_rpcc_write_provenance <- function(item,entry,export,json) {
  brohn_require(is.list(export)&&is.function(json)&&brohn_text(export$prefix,100)&&
    grepl("^evidence/cardiac/source-(00[1-9]|0[12][0-9]|03[0-2])/$",export$prefix),"The cardiac provenance export needs the exact bounded host prefix and JSON callback.")
  receipt<-export$receipt
  brohn_require(identical(receipt$schema,"brohn-cardiac-package-projection-result/0.1")&&
    .brohn_rpca_same(receipt$source_ref,item$ref)&&.brohn_rpca_same(receipt$prepared_ref,entry$ref)&&
    identical(receipt$source_closure_hash,entry$evidence$closure_hash)&&identical(receipt$identifier_mode,"source_identifiers")&&
    identical(receipt$coverage$complete,TRUE)&&identical(receipt$coverage$all_original_payload_bytes_equal,TRUE)&&
    .brohn_rpca_same(export$evidence,entry$evidence)&&.brohn_rpca_same(export$analysis,entry$analysis),"The cardiac provenance companion lost its completed payload/source binding.")
  files<-lapply(entry$body$payloads,function(p){p$path<-paste0(export$prefix,p$path);p})
  brohn_require(.brohn_rpca_same(export$files,files)&&.brohn_rpca_same(receipt$files,files),"The cardiac provenance companion refers to another completed payload inventory.")
  value<-.brohn_rpcc_provenance_model(item,entry)
  json(value,paste0(export$prefix,"source-provenance.json"),"complete_cardiac_provenance")
  invisible(value)
}

.brohn_rpcc_provenance_membership <- function(item,entry) {
  r<-item$ref;b<-item$saved_body;a<-item$complete_analysis
  m<-.brohn_rpca_one(entry$source_metadata$reports,function(x).brohn_rpca_same(x$ref,r),"The cardiac provenance source is absent from the exact closure.")
  .brohn_rpca_one(entry$source_metadata$closure$nodes,function(x).brohn_rpca_same(x$ref,r),"The original cardiac report reference is absent or duplicated in the bound closure.")
  brohn_require(identical(m$study_id,b$study_id)&&identical(m$kind,a$kind)&&m$record_count==length(a$recordings),"The original cardiac context differs from the retained closure metadata.")
  invisible(TRUE)
}

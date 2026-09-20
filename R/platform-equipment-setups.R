# Equipment definitions are reusable workspace records, never collection authority.
brohn_equipment_source <- function(observed) {
  brohn_require(is.list(observed)&&isTRUE(observed$supported)&&brohn_number(observed$channel_count,1,128,TRUE)&&
    brohn_array(observed$channels)&&length(observed$channels)==observed$channel_count,
    "Choose one supported source from a completed discovery.")
  brohn_require(brohn_text(observed$channel_metadata_sha256,64)&&grepl("^[a-f0-9]{64}$",observed$channel_metadata_sha256),
    "Find local sources again to obtain the complete channel metadata fingerprint before reusing equipment settings.")
  result<-list(adapter="brohn-lsl/1.0",name=observed$name,type=observed$type,source_id=observed$source_id,
    nominal_srate=observed$nominal_srate,value_type=observed$value_type,channel_count=observed$channel_count,
    channel_metadata_sha256=observed$channel_metadata_sha256,
    channels=lapply(seq_along(observed$channels),function(i)list(index=i-1L,label=observed$channels[[i]]$label,
      type=observed$channels[[i]]$type,unit=observed$channels[[i]]$unit,value_type=observed$value_type)))
  for(field in c("name","type","source_id","value_type"))brohn_require(brohn_text(result[[field]],1000),"The source descriptor is incomplete.")
  brohn_require(brohn_number(result$nominal_srate,0,1e9),"The source must declare its nominal cadence, including zero for an irregular stream.")
  result
}
brohn_equipment_configuration <- function(selection) {
  # Explicit projection prevents a run identity, approval flag, process or live UID
  # from entering the reusable body, even when the caller supplies extra fields.
  pick<-function(x,fields)x[intersect(fields,names(x))]
  channels<-lapply(selection$channels,function(x)pick(x,c("id","label","type","unit","value_type")))
  readiness<-pick(selection$readiness,c("schema","modality","preview_channels","reference","site","calibration","frame","gravity_policy","wavelengths","task_identity"))
  readiness$channels<-lapply(selection$readiness$channels,function(x)pick(x,c("id","role","rail_min","rail_max")))
  readiness$acquisition_checks<-lapply(selection$readiness$acquisition_checks,function(x)pick(x,c("id","name","version","source","rationale","unit","channel_id","kind","window_s","minimum_samples","minimum_span_s","maximum_age_s","accepted_values","minimum_fraction","lower","upper")))
  if(!is.null(selection$readiness$gaze))readiness$gaze<-pick(selection$readiness$gaze,c("eye","unit","frame","origin","valid_value","width","height"))
  result<-list(kind=selection$kind,clock_kind=selection$clock_kind,channels=channels,readiness=readiness)
  if(!is.null(selection$gap_threshold_s))result$gap_threshold_s<-selection$gap_threshold_s
  brohn_require(result$kind %in% c("signal","markers","unclassified")&&result$clock_kind %in% c("monotonic","unix","device","unspecified_epoch"),"Declare equipment stream and clock kinds.")
  brohn_require(brohn_array(channels)&&length(channels)>=1L&&length(channels)<=128L&&
    identical(vapply(channels,`[[`,character(1),"id"),paste0("channel-",seq_along(channels))),"Equipment channel settings must preserve the complete original order.")
  for(channel in channels)for(field in c("label","type","unit","value_type"))
    brohn_require(brohn_text(channel[[field]],500)||(field=="unit"&&is.null(channel$unit)&&channel$value_type=="string"),"Declare the original equipment channel fields.")
  brohn_require(identical(readiness$schema,"brohn-acquisition-readiness/1.1"),"Reusable equipment setups use readiness /1.1.")
  brohn_validate_acquisition_readiness(readiness,channels)
  brohn_require(is.null(result$gap_threshold_s)||brohn_number(result$gap_threshold_s,1e-6,3600),"Declare a supported source gap threshold.")
  result
}
.brohn_equipment_observed <- function(store,discovery_id,uid) {
  d<-brohn_get_entity(store,"acquisition_discovery",discovery_id)
  brohn_require(!is.null(d)&&identical(d$body$status,"ready")&&identical(d$body$result_hash,brohn_hash(d$body$result))&&
    identical(d$body$script_hash,.brohn_acq_hash(.brohn_acq_script())),"Find and review current source metadata before using an equipment setup.")
  found<-Filter(function(x)identical(x$uid,uid),d$body$result$streams)
  brohn_require(length(found)==1L&&isTRUE(found[[1L]]$supported),"Select one exact discovered source before applying equipment settings.")
  list(discovery=d,observed=found[[1L]])
}
brohn_equipment_setups <- function(store)brohn_list_entities(store,"equipment_setup",limit=1000L)
brohn_equipment_setup <- function(store,id,revision=NULL,hash=NULL) {
  record<-brohn_get_entity(store,"equipment_setup",id,revision)
  brohn_require(!is.null(record)&&identical(record$body$schema,"brohn-equipment-setup/1.0"),"Choose a saved equipment setup revision.")
  b<-record$body
  brohn_require(identical(b$source_hash,brohn_hash(b$source))&&identical(b$configuration_hash,brohn_hash(b$configuration))&&
    (is.null(hash)||identical(hash,brohn_hash(b))),"The saved equipment setup failed its immutable identity check.")
  brohn_require(identical(brohn_hash(brohn_equipment_configuration(b$configuration)),b$configuration_hash),"The saved equipment configuration contains unsupported fields.")
  record
}
brohn_save_equipment_setup <- function(store,title,discovery_id,uid,selection,id=NULL,expected_revision=0L) {
  brohn_require(brohn_text(title,200),"Name this reusable equipment setup.")
  current<-.brohn_equipment_observed(store,discovery_id,uid);source<-brohn_equipment_source(current$observed)
  configuration<-brohn_equipment_configuration(selection)
  brohn_require(length(configuration$channels)==source$channel_count&&all(vapply(configuration$channels,function(c)identical(c$value_type,source$value_type),logical(1))),"Equipment settings must cover this exact source layout and native type.")
  if(is.null(id)){brohn_require(identical(as.numeric(expected_revision),0),"New equipment setups start at revision zero.");id<-brohn_id("equipment-setup")}
  else {prior<-brohn_equipment_setup(store,id);brohn_require(identical(as.numeric(prior$revision),as.numeric(expected_revision)),"This equipment setup changed. Refresh its revision before saving.")}
  body<-list(schema="brohn-equipment-setup/1.0",id=id,title=title,source=source,source_hash=brohn_hash(source),
    configuration=configuration,configuration_hash=brohn_hash(configuration),saved_at=brohn_now())
  brohn_put_entity(store,"equipment_setup",id,body,expected_revision,project_id="default")
}
brohn_compare_equipment_source <- function(setup,observed) {
  current<-brohn_equipment_source(observed);saved<-setup$body$source;differences<-list()
  add<-function(field,a,b)if(!identical(brohn_hash(a),brohn_hash(b)))differences[[length(differences)+1L]]<<-list(field=field,saved=a,current=b)
  for(field in c("adapter","name","type","source_id","nominal_srate","value_type","channel_count"))add(field,saved[[field]],current[[field]])
  for(i in seq_len(max(length(saved$channels),length(current$channels)))) {
    a<-if(i<=length(saved$channels))saved$channels[[i]] else NULL;b<-if(i<=length(current$channels))current$channels[[i]] else NULL
    for(field in c("label","type","unit","value_type"))add(paste0("Channel ",i," ",field),a[[field]],b[[field]])
  }
  add("Complete channel metadata fingerprint",saved$channel_metadata_sha256,current$channel_metadata_sha256)
  list(matches=identical(setup$body$source_hash,brohn_hash(current)),differences=differences,current=current)
}
brohn_apply_equipment_setup <- function(store,id,revision,hash,discovery_id,uid) {
  setup<-brohn_equipment_setup(store,id,revision,hash);current<-.brohn_equipment_observed(store,discovery_id,uid)
  comparison<-brohn_compare_equipment_source(setup,current$observed)
  brohn_require(isTRUE(comparison$matches),"Source metadata differs from this setup. Review the differences and author settings for the current layout before saving a new revision.")
  list(configuration=setup$body$configuration,reference=list(id=setup$id,revision=setup$revision,hash=brohn_hash(setup$body),
    source_hash=setup$body$source_hash,configuration_hash=setup$body$configuration_hash),
    binding=list(discovery_id=discovery_id,discovery_hash=current$discovery$body$result_hash,uid=uid,metadata_sha256=current$observed$metadata_sha256))
}
brohn_validate_equipment_application <- function(store,reference,discovery,selection) {
  brohn_fields(reference,c("id","revision","hash","source_hash","configuration_hash"),label="Equipment setup reference")
  applied<-brohn_apply_equipment_setup(store,reference$id,reference$revision,reference$hash,discovery$id,selection$uid)
  brohn_require(identical(brohn_hash(reference),brohn_hash(applied$reference)),"The selected equipment setup reference changed.")
  # Settings may be edited after prefill, but the saved provenance records both
  # the exact original setup and the exact current reviewed request configuration.
  c(reference,list(applied_configuration_hash=brohn_hash(brohn_equipment_configuration(selection))))
}

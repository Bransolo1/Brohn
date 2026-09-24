# Pure source-bound trial-summary import. The coordinator verifies immutable CSV
# and registry object bytes. This adapter claims no event replay or device timing.
.brohn_task_import_profiles <- function() c("iat-gnb2003-d1/1.0","biat-nosek2014-goodfocal/1.0",
  "aat-keyboard-cue-balanced/1.0","rt-deary-liewald-simple/1.0","rt-deary-liewald-choice/1.0", "sciat-brohn-response-window-im100/1.0")
.brohn_task_import_columns <- function() paste0(c("participant","participant_linkage","session","attempt","protocol",
  "presentation_index","trial","presented","outcome","first_code","final_code","first_correct",
  "first_response_ms","final_correct_ms","missing_reason"),"_column")
.brohn_task_import_hash <- function(x) brohn_text(x,64)&&grepl("^[a-f0-9]{64}$",x)
.brohn_task_import_registry_ref <- function(ref) {
  brohn_fields(ref,c("hash","bytes","media_type","filename","canonical_hash","task_definition_hash"),label="Immutable protocol registry reference")
  brohn_require(.brohn_task_import_hash(ref$hash)&&.brohn_task_import_hash(ref$canonical_hash)&&.brohn_task_import_hash(ref$task_definition_hash)&&
    brohn_number(ref$bytes,1,16*1024^2,TRUE)&&identical(ref$media_type,"application/json")&&brohn_text(ref$filename,240)&&
    !grepl("[/\\\\]",ref$filename),"The protocol registry reference needs bounded JSON bytes, exact hashes and a display filename, never a source filepath.")
  invisible(ref)
}
.brohn_task_import_mapping <- function(metadata,columns) {
  required<-.brohn_task_import_columns()
  brohn_fields(metadata,c("task_id","source_collection_id","origin_statement","source_software","source_rt_definition",
    "terminal_response_rule","evidence_level",required),c("task_column","origin_column","protocol_registry"),"Implicit trial import mapping")
  if(!is.null(metadata$protocol_registry)).brohn_task_import_registry_ref(metadata$protocol_registry)
  brohn_require(brohn_valid_id(metadata$task_id)&&brohn_text(metadata$source_collection_id,240)&&brohn_text(metadata$origin_statement,4000),
    "Select the saved task and declare the original collection identity and source.")
  brohn_require(is.null(metadata$source_software)||brohn_text(metadata$source_software,1000),"Record the collection software/version, or retain an explicit null when it is unknown.")
  brohn_require(metadata$source_rt_definition %in% c("first_and_final_correct_ms_from_target_onset","unknown")&&
    brohn_text(metadata$source_rt_definition,96)&&brohn_text(metadata$terminal_response_rule,96)&&
    metadata$terminal_response_rule %in% c("first_response_or_fixed_deadline","corrected_response_or_fixed_deadline","unknown")&&
    identical(metadata$evidence_level,"declared_trial_summary"),"Choose the declared latency and terminal-response definitions. Trial summaries cannot claim journal replay.")
  brohn_require(is.character(columns)&&length(columns)>0L&&length(columns)<=1024L&&!anyNA(columns)&&!anyDuplicated(columns)&&all(nzchar(columns)),
    "Implicit source columns need distinct nonempty names.")
  mapped<-character()
  for(field in c(required,"task_column","origin_column")) {
    value<-metadata[[field]]
    if(!field %in% required&&(is.null(value)||identical(value,"")))next
    brohn_require(brohn_text(value,500)&&value %in% columns,paste("Map a distinct source column for",gsub("_"," ",field),"before analysis."))
    mapped<-c(mapped,value)
  }
  brohn_require(!anyDuplicated(mapped),"A source column cannot stand for multiple trial identities, responses or evidence fields.")
  invisible(metadata)
}
.brohn_task_import_task <- function(design,task_id) {
  brohn_require(is.list(design)&&brohn_array(design$blocks)&&!anyDuplicated(brohn_ids(design$blocks)),"Link the exact study revision containing the original task.")
  task<-brohn_find(design$blocks,task_id)
  brohn_require(!is.null(task)&&task$profile %in% .brohn_task_import_profiles(),"The selected task is absent or outside the registered trial-import profiles.")
  brohn_task_validate(task);task
}
.brohn_task_import_origin <- function(task,origin) {
  brohn_require(brohn_text(origin,30)&&origin %in% c("sample","preview","pilot","live","imported"),"The immutable trial source has an unsupported collection origin.")
  brohn_require(task$origin!="synthetic"||origin %in% c("sample","preview"),"Synthetic task materials must remain sample or preview data; importing cannot upgrade their origin.")
  invisible(origin)
}
brohn_validate_task_import_mapping <- function(dataset,design=NULL) {
  brohn_require(is.list(dataset)&&identical(dataset$modality,"implicit")&&dataset$source$format %in% c("csv","tsv"),
    "Implicit trial-summary import requires an explicitly mapped CSV or TSV source.")
  .brohn_task_import_mapping(dataset$metadata,unlist(dataset$columns,use.names=FALSE))
  brohn_require(!is.null(dataset$metadata$protocol_registry),"Attach and validate the immutable protocol registry before saving this trial mapping.")
  brohn_require(brohn_valid_id(dataset$study_id)&&brohn_number(dataset$study_revision,1,.Machine$integer.max,TRUE),
    "Pin the exact study revision before mapping implicit trial summaries.")
  if(!is.null(design)) {
    brohn_require(identical(design$id,dataset$study_id),"The supplied design does not belong to the pinned study.")
    task<-.brohn_task_import_task(design,dataset$metadata$task_id)
    .brohn_task_import_origin(task,dataset$origin)
    brohn_require(identical(brohn_hash(task),dataset$metadata$protocol_registry$task_definition_hash),"The registry reference belongs to a different task definition.")
  }
  invisible(dataset)
}
.brohn_task_import_registry <- function(registry,design,task_id) {
  brohn_fields(registry,c("schema","task","protocols"),label="Implicit protocol registry")
  brohn_require(identical(registry$schema,"brohn-implicit-protocol-registry/1.0")&&brohn_array(registry$protocols)&&
    length(registry$protocols)>=1L&&length(registry$protocols)<=1000L,"Choose a registered bounded array of frozen implicit protocols.")
  serialized<-brohn_json(registry)
  brohn_require(nchar(serialized,type="bytes")<=16*1024^2,"The protocol registry exceeds 16 MiB; split the source explicitly.")
  task<-.brohn_task_import_task(design,task_id);task_hash<-brohn_hash(task)
  brohn_task_validate(registry$task)
  brohn_require(identical(brohn_hash(registry$task),task_hash),"Registry materials or settings differ from the task in the pinned study revision.")
  ids<-character();hashes<-character();tables<-list()
  for(entry in registry$protocols) {
    brohn_fields(entry,c("id","compiled_hash","compiled"),label="Frozen implicit protocol entry")
    brohn_require(brohn_text(entry$id,96)&&!entry$id %in% ids&&.brohn_task_import_hash(entry$compiled_hash)&&
      !entry$compiled_hash %in% hashes,"Frozen protocol entries need unique identities and compiled hashes.")
    brohn_require(is.list(entry$compiled)&&brohn_number(entry$compiled$allocation_index,1,1e9,TRUE),"A frozen protocol needs its explicit original allocation index.")
    brohn_require(identical(brohn_hash(entry$compiled),entry$compiled_hash),"A frozen protocol's supplied hash does not match its complete table.")
    # Exactly once per registry entry, independent of participant/trial count.
    expected<-brohn_task_compile(task,entry$compiled$allocation_index)
    brohn_require(identical(brohn_hash(expected),entry$compiled_hash),"The supplied frozen table differs from this registered task/allocation compiler. Preserve the source and choose its compatible protocol; no table is reconstructed as observed history.")
    ids<-c(ids,entry$id);hashes<-c(hashes,entry$compiled_hash)
    tables[[entry$id]]<-list(compiled=entry$compiled,hash=entry$compiled_hash,
      trials=Filter(function(step)identical(step$type,"task_trial"),entry$compiled$timeline))
  }
  list(registry=registry,canonical_hash=digest::digest(charToRaw(enc2utf8(serialized)),algo="sha256",serialize=FALSE),
    task=task,task_hash=task_hash,tables=tables,size=nchar(serialized,type="bytes"))
}
brohn_validate_task_protocol_registry <- function(registry,design,task_id) {
  .brohn_task_import_registry(registry,design,task_id);invisible(registry)
}
.brohn_task_import_boolean <- function(value,label,row) {
  brohn_require(value %in% c("true","false","TRUE","FALSE","1","0"),paste("Source row",row,"has an invalid",label,"boolean. Use true/false or 1/0."))
  value %in% c("true","TRUE","1")
}
.brohn_task_import_decimal <- function(value,label,row) {
  if(identical(value,""))return(NULL)
  brohn_require(brohn_text(value,64)&&grepl("^[0-9]+([.][0-9]+)?([eE][+-]?[0-9]+)?$",value),paste("Source row",row,"needs an explicit nonnegative decimal",label,"(optional scientific notation) or an empty missing cell; NA/NaN/null are not missing values."))
  number<-suppressWarnings(as.numeric(value))
  brohn_require(is.finite(number)&&number<=1e12,paste("Source row",row,label,"is outside the supported finite range."))
  brohn_require(number!=0 || !grepl("[1-9]",sub("[eE].*$","",value)),paste("Source row",row,label,"is nonzero but too small for supported numeric precision; it cannot become zero."))
  number
}
.brohn_task_import_response <- function(cells,trial,row,timing_known) {
  require<-function(ok,message)brohn_require(ok,paste("Source row",row,message))
  nullable<-function(x)if(identical(x,""))NULL else x
  presented<-.brohn_task_import_boolean(cells$presented,"presented",row)
  first_correct<-.brohn_task_import_boolean(cells$first_correct,"first correctness",row)
  first<-nullable(cells$first_code);final<-nullable(cells$final_code)
  first_ms<-.brohn_task_import_decimal(cells$first_response_ms,"first-response time",row)
  final_ms<-.brohn_task_import_decimal(cells$final_correct_ms,"final-correct time",row)
  reason<-nullable(cells$missing_reason);outcome<-cells$outcome
  require(outcome %in% c("correct","incorrect","timeout","interrupted","not_presented"),"has an unsupported terminal outcome.")
  require(is.null(reason)||brohn_text(reason,4000),"has an invalid missing/outcome reason.")
  require(identical(is.null(first),is.null(first_ms))&&identical(is.null(final),is.null(final_ms)),"needs both key and latency for each recorded response, or neither.")
  require(is.null(first)||first %in% unlist(trial$allowed_codes),"has a first key outside this frozen trial's allowed keys.")
  require(is.null(final)||identical(final,trial$correct_code),"has a final key different from the frozen correct key.")
  require(identical(first_correct,!is.null(first)&&identical(first,trial$correct_code)),"first-response correctness contradicts the frozen key.")
  if(!is.null(final_ms))require(!is.null(first_ms)&&final_ms>=first_ms,"has a final-correct latency before its first response.")
  if(first_correct)require(!is.null(final_ms)&&abs(final_ms-first_ms)<.000001,"needs equal first/final latencies for a correct first response under this scoring profile.")
  if(timing_known)for(value in list(first_ms,final_ms))if(!is.null(value))require(value<=trial$timeout_ms+if(identical(trial$mode,"sciat_window"))0 else .002,"accepts a response after the frozen deadline.")
  if(!presented)require(outcome %in% c("not_presented","interrupted")&&is.null(first)&&is.null(final)&&!first_correct&&!is.null(reason),
    "cannot record an accepted response or completed outcome without presentation; retain its explicit reason.")
  if(outcome=="not_presented")require(!presented&&!is.null(reason),"marks an actually presented trial as not presented.")
  if(outcome=="interrupted")require(!is.null(reason),"needs an explicit interruption reason.")
  if(outcome=="correct")require(presented&&!is.null(first)&&!is.null(final)&&(trial$forced_correction||first_correct),
    "cannot claim a correct terminal response without its keys, or add a correction to a first-response task.")
  if(outcome=="incorrect")require(presented&&!trial$forced_correction&&!is.null(first)&&!first_correct&&is.null(final),
    "cannot claim incorrect completion without a genuine wrong first response in a non-correction task.")
  if(outcome=="timeout")require(presented&&is.null(final)&&(!first_correct)&&(trial$forced_correction||is.null(first)),
    "cannot combine a timeout with a terminal response in this procedure.")
  if(!trial$forced_correction&&!is.null(first)&&!first_correct)require(is.null(final),"cannot append a correction to a non-correction task.")
  list(trial_id=trial$id,outcome=outcome,response_code=first,final_code=final,first_correct=first_correct,
    first_response_ms=first_ms,final_correct_ms=final_ms,presented=presented,missing_reason=reason,
    first_response_ms_source=cells$first_response_ms,final_correct_ms_source=cells$final_correct_ms)
}
.brohn_task_import_trial_audit <- function(trial,response,source_row,profile,timing_known) {
  kind<-brohn_task_profile(profile)$kind
  latency<-if(is.null(response))NULL else if(kind %in% c("iat","biat"))response$final_correct_ms else response$first_response_ms
  disposition<-if(is.null(response))"missing_expected_source_row"else if(!response$presented)"not_presented"else if(response$outcome=="interrupted")"interrupted"else
    if(!isTRUE(trial$scored))"unscored_by_profile"else if(!timing_known)"timing_definition_unavailable"else if(response$outcome=="timeout")"timeout"else
    if(kind=="sciat_window"&&!is.null(latency)&&latency<350)"below_350_ms"else
    if(kind=="sciat_window"&&!response$first_correct)"error_replacement_in_saved_score"else
    if(!kind %in% c("iat","biat")&&!response$first_correct)"first_response_error"else if(is.null(latency))"missing_latency"else
    if(kind %in% c("iat","biat")&&latency>10000)"slow_final_correct_excluded"else if(!kind %in% c("iat","biat")&&
      (latency<if(kind=="aat")200 else 0||latency>if(kind=="aat")2000 else 5000))"outside_rt_window"else"candidate_for_task_scoring"
  list(trial_id=trial$id,source_row=source_row,derived=is.null(response),profile_scored=isTRUE(trial$scored),
    block_id=trial$block_id,score_block=trial$score_block,category_id=trial$category_id,action=trial$action,
    disposition=disposition,missing_reason=if(is.null(response))"Expected frozen trial has no source row."else response$missing_reason,
    declared_latency_ms=latency,original_fast_below_300=if(timing_known&&isTRUE(trial$scored)&&kind %in% c("iat","biat")&&!is.null(latency))latency<300 else NULL,
    scoring_latency_ms=if(disposition=="candidate_for_task_scoring")if(kind=="biat")min(2000,max(400,latency))else latency else NULL)
}

brohn_import_task_trials <- function(data,metadata,design,source,protocols) {
  brohn_require(is.data.frame(data)&&nrow(data)>=1L&&nrow(data)<=20000L&&ncol(data)<=1024L,
    "Implicit trial import accepts 1 to 20,000 source rows; split larger files explicitly, without truncation.")
  .brohn_task_import_mapping(metadata,names(data))
  brohn_require(all(vapply(data,function(column)is.character(column)&&!anyNA(column),logical(1))),
    "Read implicit CSV/TSV as character columns with na.strings=character(); inferred numbers, factors and R missing values lose source evidence.")
  brohn_fields(source,c("id","revision","hash","origin","registry_object_hash"),label="Immutable implicit import source")
  brohn_require(brohn_text(source$id,240)&&brohn_number(source$revision,1,.Machine$integer.max,TRUE)&&
    .brohn_task_import_hash(source$hash)&&.brohn_task_import_hash(source$registry_object_hash),"Pin source and registry object hashes plus the dataset identity/revision before analysis.")
  registry<-.brohn_task_import_registry(protocols,design,metadata$task_id)
  if(!is.null(metadata$protocol_registry))brohn_require(identical(metadata$protocol_registry$hash,source$registry_object_hash)&&
    identical(metadata$protocol_registry$canonical_hash,registry$canonical_hash)&&identical(metadata$protocol_registry$task_definition_hash,registry$task_hash),
    "The immutable registry reference does not match the supplied source object, canonical registry or pinned task.")
  .brohn_task_import_origin(registry$task,source$origin)
  forced<-brohn_task_profile(registry$task$profile)$kind %in% c("iat","biat")
  expected_rule<-if(forced)"corrected_response_or_fixed_deadline"else"first_response_or_fixed_deadline"
  brohn_require(metadata$terminal_response_rule %in% c(expected_rule,"unknown"),"The declared terminal-response rule contradicts this frozen task's correction procedure.")
  timing_known<-metadata$source_rt_definition!="unknown"&&metadata$terminal_response_rule!="unknown"
  mapped<-function(field)!is.null(metadata[[field]])&&!identical(metadata[[field]],"")
  task_values<-if(mapped("task_column"))data[[metadata$task_column]]else rep(metadata$task_id,nrow(data))
  selected<-task_values==metadata$task_id
  brohn_require(any(selected),"No source row matches the explicitly selected task.")
  origins<-if(mapped("origin_column"))data[[metadata$origin_column]]else rep(source$origin,nrow(data))
  brohn_require(all(origins[selected]==source$origin),"Selected row origins conflict with the immutable dataset origin; review the source rather than exclude conflicting origins.")
  evidence<-vector("list",nrow(data));parsed<-list();group_keys<-character()
  mapping_hash<-brohn_hash(metadata)
  for(i in seq_len(nrow(data))) {
    raw<-lapply(as.list(data[i,,drop=FALSE]),unname)
    row_id<-paste0("task-row-",brohn_hash(list(source_hash=source$hash,source_row=i)))
    evidence[[i]]<-list(source_row=i,id=row_id,source_row_hash=brohn_hash(raw),selected=selected[[i]],
      reason=if(selected[[i]])"selected_task"else"different_task",declared_task_id=task_values[[i]],
      declared_origin=if(mapped("origin_column"))origins[[i]]else NULL,original_cells=raw)
    if(!selected[[i]])next
    cells<-lapply(.brohn_task_import_columns(),function(field)data[[metadata[[field]]]][[i]])
    names(cells)<-sub("_column$","",.brohn_task_import_columns())
    for(field in c("participant","session","attempt"))brohn_require(brohn_text(cells[[field]],240),paste("Source row",i,"needs an explicit",field,"identity; none is inferred from row or filename."))
    brohn_require(brohn_text(cells$protocol,96)&&cells$protocol %in% names(registry$tables),paste("Source row",i,"refers to an unknown frozen protocol."))
    table<-registry$tables[[cells$protocol]];ids<-brohn_ids(table$trials)
    brohn_require(cells$trial %in% ids,paste("Source row",i,"has a trial ID absent from its exact frozen protocol."))
    ordinal<-match(cells$trial,ids)
    brohn_require(grepl("^[1-9][0-9]*$",cells$presentation_index)&&identical(as.numeric(cells$presentation_index),as.numeric(ordinal)),
      paste("Source row",i,"presentation index disagrees with its exact frozen trial order."))
    linkage<-.brohn_task_import_boolean(cells$participant_linkage,"participant linkage",i)
    response<-.brohn_task_import_response(cells,table$trials[[ordinal]],i,timing_known)
    key<-brohn_json(list(collection=metadata$source_collection_id,participant=cells$participant,session=cells$session,attempt=cells$attempt))
    parsed[[length(parsed)+1L]]<-list(source_row=i,row_id=row_id,participant_id=cells$participant,participant_linkage=linkage,
      session_id=cells$session,attempt_id=cells$attempt,protocol_id=cells$protocol,ordinal=ordinal,response=response)
    group_keys<-c(group_keys,key)
  }
  groups<-split(seq_along(parsed),factor(group_keys,levels=unique(group_keys)))
  expected_count<-sum(vapply(groups,function(indices)length(registry$tables[[parsed[[indices[[1L]]]]$protocol_id]]$trials),integer(1)))
  brohn_require(expected_count<=20000L,"The selected administrations exceed 20,000 expected trial positions including missing-row diagnostics. Split this sparse source explicitly; no diagnostic rows are truncated.")
  attempts<-list();scores<-list()
  for(indices in groups) {
    rows<-parsed[indices];first<-rows[[1L]]
    brohn_require(length(unique(vapply(rows,`[[`,character(1),"protocol_id")))==1L,"One participant/session/attempt refers to multiple frozen protocols.")
    brohn_require(length(unique(vapply(rows,`[[`,logical(1),"participant_linkage")))==1L,"Participant linkage changes inside a single administration.")
    ordinals<-vapply(rows,`[[`,integer(1),"ordinal")
    brohn_require(!anyDuplicated(ordinals),"An administration contains duplicate trial identities or presentation indices; repeated exports cannot add trials.")
    rows<-rows[order(ordinals)];table<-registry$tables[[first$protocol_id]]
    responses<-lapply(rows,`[[`,"response");ordinals<-vapply(rows,`[[`,integer(1),"ordinal")
    stopped<-FALSE
    for(response in responses) {
      brohn_require(!stopped||!response$presented,"An administration records later presented trials after an interruption, unpresented trial or unresolved forced correction.")
      if(!response$presented||response$outcome=="interrupted"||(forced&&response$outcome!="correct"))stopped<-TRUE
    }
    missing<-setdiff(seq_along(table$trials),ordinals)
    interrupted<-any(vapply(responses,function(r)r$outcome=="interrupted",logical(1)))
    complete<-!length(missing)&&!stopped&&all(vapply(responses,`[[`,logical(1),"presented"))
    completion<-if(complete)"completed"else if(interrupted)"interrupted"else"incomplete"
    logical_key<-brohn_hash(list(source_collection_id=metadata$source_collection_id,participant_id=first$participant_id,
      session_id=first$session_id,attempt_id=first$attempt_id,task_definition_hash=registry$task_hash))
    id<-paste0("task-attempt-",brohn_hash(list(original_source_hash=source$hash,logical_evidence_key=logical_key)))
    scoring_responses<-Filter(function(r)r$outcome!="not_presented",responses)
    if (identical(registry$task$profile,"sciat-brohn-response-window-im100/1.0"))
      scoring_responses<-lapply(scoring_responses,brohn_sciat_window_import_response)
    score<-brohn_task_score(table$compiled,scoring_responses,completed=complete&&timing_known)
    if(!timing_known)score$reason<-"The source latency or terminal-response definition is explicitly unknown; scoring is unavailable."
    score$title<-registry$task$title;score$participant_id<-first$participant_id;score$participant_linkage<-first$participant_linkage
    score$session_id<-first$session_id;score$attempt_id<-id;score$collection_origin<-source$origin;score$evidence_level<-metadata$evidence_level
    trial_audit<-lapply(seq_along(table$trials),function(j){at<-match(j,ordinals);row<-if(is.na(at))NULL else rows[[at]]
      .brohn_task_import_trial_audit(table$trials[[j]],row$response,row$source_row,registry$task$profile,timing_known)})
    source_rows<-vapply(rows,`[[`,integer(1),"source_row")
    attempts[[length(attempts)+1L]]<-list(schema="brohn-task-attempt/1.0",id=id,logical_evidence_key=logical_key,
      source_collection_id=metadata$source_collection_id,source_attempt_id=first$attempt_id,participant_id=first$participant_id,
      participant_linkage=first$participant_linkage,session_id=first$session_id,attempt_id=first$attempt_id,task_id=registry$task$id,
      task_definition_hash=registry$task_hash,protocol_id=first$protocol_id,compiled_hash=table$hash,profile=registry$task$profile,
      collection_origin=source$origin,material_origin=registry$task$origin,completion_status=completion,evidence_level=metadata$evidence_level,
      source=list(dataset_id=source$id,revision=source$revision,original_hash=source$hash,mapping_hash=mapping_hash,
        registry_object_hash=source$registry_object_hash,registry_canonical_hash=registry$canonical_hash,
        selected_original_rows=as.list(source_rows),selected_rows_hash=brohn_hash(evidence[source_rows])),
      responses=responses,trial_audit=trial_audit,score=score,
      timing_quality=list(definitions_known=timing_known,source_software=metadata$source_software,source_rt_definition=metadata$source_rt_definition,
        terminal_response_rule=metadata$terminal_response_rule,source_clock=NULL,onset_observations=NULL,key_history=NULL,
        anticipatory_count=NULL,frame_observations=NULL,journal_replayed=FALSE,physical_timing_qualified=FALSE),
      missing_reasons=as.list(unique(c(if(length(missing))"Expected frozen trials are absent from the source."else character(),
        vapply(Filter(function(r)!is.null(r$missing_reason),responses),`[[`,character(1),"missing_reason")))))
    scores[[length(scores)+1L]]<-score
  }
  linked<-all(vapply(attempts,`[[`,logical(1),"participant_linkage"))
  list(kind="implicit",title=paste("Implicit task:",registry$task$title),task_scores=scores,task_attempts=attempts,
    source_rows=evidence,source_rows_hash=brohn_hash(evidence),
    quality=list(source_row_count=nrow(data),selected_row_count=sum(selected),excluded_row_count=sum(!selected),
      expected_trial_count=expected_count,derived_missing_trial_count=sum(vapply(attempts,function(a)sum(vapply(a$trial_audit,`[[`,logical(1),"derived")),integer(1))),
      attempt_count=length(attempts),completed_attempt_count=sum(vapply(attempts,function(a)a$completion_status=="completed",logical(1))),
      eligible_attempt_count=sum(vapply(scores,function(s)isTRUE(s$eligible),logical(1))),
      participant_count=if(linked)length(unique(vapply(attempts,`[[`,character(1),"participant_id")))else NULL,
      participant_linkage=if(linked)"source_declared_not_identity_verified"else"unavailable",
      session_count=length(unique(vapply(attempts,function(a)brohn_json(list(a$participant_id,a$session_id)),character(1)))),
      usable=any(vapply(scores,function(s)isTRUE(s$eligible),logical(1))),scientifically_qualified=FALSE),
    parameters=list(schema="brohn-implicit-csv-import/1.0",mapping=metadata,source=source,selected_task_hash=registry$task_hash,
      registry_canonical_hash=registry$canonical_hash,registry_size=registry$size,row_limit=20000L,expected_trial_limit=20000L,
      registry_verification="Coordinator verifies immutable object bytes; this adapter checks canonical registry and exact compiled table/task/allocation identity.",
      identity_policy="original source hash plus logical collection/participant/session/attempt/task-definition identity",
      missing_cell_policy="Only empty nullable cells become null; source NA/NaN/null and apostrophe prefixes remain literal text.",
      source_row_order="Retained as provenance; explicit indices are checked against the frozen table, never inferred from file order.",
      origin_verification=if(mapped("origin_column"))"selected_rows_match_immutable_source"else"immutable_source_declaration_only"),
    limitations=list("Declared trial summaries do not establish onset clocks, accepted-key history, recorder version, physical timing or journal replay.",
      "Administration metrics retain profile-specific support. Aggregate eligibility never makes every metric eligible; no cohort inference or pooled-trial D is performed.",
      "Source-declared participant linkage applies only inside the declared collection; identical labels across sources need an explicit crosswalk.",
      "Registry equality qualifies local task-table compatibility, not original material validity, historical authorship or construct interpretation."))
}

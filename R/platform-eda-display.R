# Saved EDA display preparation. Original scientific values are never recomputed.
.brohn_edd_profile <- "saved-eda-display/0.1"
.brohn_edd_admission <- "task-choice-eda-findings/0.1"

# Closed versions preserve saved histories; no mutable "latest" grammar.
.brohn_edd_profile_spec <- function(preparation_profile="saved-eda-display/0.1") {
 brohn_require(brohn_text(preparation_profile,128)&&preparation_profile %in% c("saved-eda-display/0.1","saved-eda-display/0.2"),"Choose an exact registered EDA preparation profile.")
 new<-identical(preparation_profile,"saved-eda-display/0.2");version<-if(new)"0.2"else"0.1"
 list(profile=preparation_profile,body_schema=paste0("brohn-saved-eda-display/",version),evidence_schema=paste0("brohn-eda-display-evidence/",version),admission=paste0("task-choice-eda-findings/",version),
  continuous_recipes=c("eda-neurokit-highpass/1.0",if(new)"eda-neurokit-highpass/1.1"),continuous_models=c("brohn-eda-continuous-review/1.0",if(new)"brohn-eda-continuous-review/1.1"))
}
.brohn_edd_profile_from_admission <- function(admission) {
 brohn_require(brohn_text(admission,128)&&admission %in% c("task-choice-eda-findings/0.1","task-choice-eda-findings/0.2"),"Choose an exact EDA source admission.")
 if(identical(admission,"task-choice-eda-findings/0.2"))"saved-eda-display/0.2"else"saved-eda-display/0.1"
}
.brohn_edd_is_admission <- function(admission)is.character(admission)&&length(admission)==1L&&!is.na(admission)&&admission %in% c("task-choice-eda-findings/0.1","task-choice-eda-findings/0.2")
.brohn_edd_files <- c("R/platform-eda-display.R","R/platform-eda-display-sources.R",
 "R/platform-report-package-sources.R","R/platform-report-package-authority.R",
 "R/platform-eda-continuous-review.R",
 "R/platform-core.R","R/platform-catalog.R","R/platform-publication.R",
 "scripts/workers/eda_display.py","scripts/workers/eda_review.py",
 "scripts/workers/eda_continuous_review.py","scripts/workers/physiology_artifacts.py","scripts/readiness/report-package-runtime.json")
.brohn_edd_loaded <- stats::setNames(lapply(.brohn_edd_files,function(p)if(file.exists(p))digest::digest(file=p,algo="sha256")else NULL),.brohn_edd_files)
.brohn_edd_runtime <- list(R=as.character(getRversion()),jsonlite=as.character(utils::packageVersion("jsonlite")),digest=as.character(utils::packageVersion("digest")))
.brohn_edd_runtime_profile <- if(file.exists("scripts/readiness/report-package-runtime.json")&&file.info("scripts/readiness/report-package-runtime.json")$size<=8192)jsonlite::fromJSON("scripts/readiness/report-package-runtime.json",simplifyVector=FALSE)else NULL
.brohn_edd_runtime$Python <- .brohn_edd_runtime_profile$runtime$Python
brohn_eda_display_implementation <- function(preparation_profile="saved-eda-display/0.1") {
 spec<-.brohn_edd_profile_spec(preparation_profile)
 brohn_require(!any(vapply(.brohn_edd_loaded,is.null,logical(1)))&&identical(.brohn_edd_runtime_profile$schema,"brohn-report-package-runtime-profile/0.1")&&identical(.brohn_edd_runtime$Python$implementation,"CPython")&&brohn_text(.brohn_edd_runtime$Python$version,64),"EDA display code/runtime identity was not captured from a complete installation.")
 list(schema="brohn-eda-display-implementation/0.1",profile=spec$profile,sources=.brohn_edd_loaded,runtime=.brohn_edd_runtime)
}
brohn_eda_display_implementation_ref <- function(preparation_profile="saved-eda-display/0.1") .brohn_td_implementation_ref(brohn_eda_display_implementation(preparation_profile))
.brohn_edd_check_code <- function(x) {
 brohn_require(.brohn_td_same(x,brohn_eda_display_implementation(x$profile)),"EDA display preparation identity changed; explicitly prepare a new view.")
 for(p in names(x$sources))brohn_require(file.exists(p)&&identical(digest::digest(file=p,algo="sha256"),x$sources[[p]]),"EDA display code changed on disk after loading.")
 invisible(TRUE)
}

# Cross-language typed JSON digest. Empty object/array and signed zero differ.
brohn_eda_value_hash <- function(value) {
 con<-rawConnection(raw(),"wb");on.exit(close(con),add=TRUE)
 emit<-function(x)writeBin(charToRaw(x),con)
 string<-function(x){brohn_require(is.character(x)&&length(x)==1L&&!is.na(x)&&!is.na(iconv(x,from="",to="UTF-8",sub=NA)),"EDA digest needs valid UTF-8 scalar text.");x<-enc2utf8(x);emit(paste0("s",nchar(x,type="bytes"),":"));writeBin(charToRaw(x),con)}
 node<-function(x,depth=0L){
  brohn_require(depth<=63L,"EDA typed value exceeds the nesting limit.")
  if(is.null(x)){emit("n");return(invisible(NULL))}
  brohn_require(is.null(attr(x,"class"))&&is.null(dim(x)),"EDA digest rejects classed or dimensional non-JSON values.")
  if(is.logical(x)){brohn_require(length(x)==1L&&!is.na(x),"EDA digest needs one JSON boolean.");emit(if(x)"t"else"f");return(invisible(NULL))}
  if(is.numeric(x)){brohn_require(length(x)==1L&&is.finite(x)&&(!is.integer(x)||abs(x)<=2^53-1),"EDA digest needs one finite JSON number.");emit("d");writeBin(as.double(x),con,size=8L,endian="big");return(invisible(NULL))}
  if(is.character(x)){string(x);return(invisible(NULL))}
  brohn_require(is.list(x)&&is.null(attr(x,"class")),"EDA digest accepts only JSON values.")
  keys<-names(x)
  if(is.null(keys)){emit(paste0("a",length(x),":"));for(y in x)node(y,depth+1L)}else{
   brohn_require(length(keys)==length(x)&&!anyNA(keys)&&!anyDuplicated(enc2utf8(keys)),"EDA object keys must be unique valid text.")
   # Hex byte strings sort in UTF-8 byte order independently of LC_COLLATE.
   order_keys<-vapply(keys,function(k){brohn_require(!is.na(iconv(k,from="",to="UTF-8",sub=NA)),"Invalid UTF-8 object key.");paste(sprintf("%02x",as.integer(charToRaw(enc2utf8(k)))),collapse="")},character(1))
   emit(paste0("o",length(x),":"));for(i in order(order_keys,method="radix")){string(keys[[i]]);node(x[[i]],depth+1L)}
  };invisible(NULL)
 }
 emit("brohn-eda-value-hash/0.1\n");node(value)
 digest::digest(rawConnectionValue(con),algo="sha256",serialize=FALSE)
}

# The ordinary serializer emits negative zero as -0; preserve its numeric sign
# before either parser can interpret it as an integer zero. Skip JSON strings.
.brohn_edd_number_tokens <- function(text) {
 pattern<-'"(?:\\\\.|[^"\\\\])*"(*SKIP)(*FAIL)|-?(?:0|[1-9][0-9]*)(?:\\.[0-9]+)?(?:[eE][+-]?[0-9]+)?'
 regmatches(text,gregexpr(pattern,text,perl=TRUE,useBytes=TRUE))[[1L]]
}
.brohn_edd_json_text <- function(text) {
 tokens<-.brohn_edd_number_tokens(text)
 integers<-tokens[!grepl("[.eE]",tokens)];digits<-sub("^-","",integers);sizes<-nchar(digits)
 brohn_require(!any(sizes>16L|(sizes==16L&digits>"9007199254740991")),"EDA JSON contains an integer outside its exact supported domain.")
 result<-gsub('"(?:\\\\.|[^"\\\\])*"(*SKIP)(*FAIL)|(?<![0-9A-Za-z_.])-0(?![0-9.eE])',"-0.0",text,perl=TRUE,useBytes=TRUE)
 Encoding(result)<-"UTF-8";result
}
brohn_eda_read_json_file <- function(path,maximum=48*1024^2) {
 brohn_require(file.exists(path)&&file.info(path)$size<=maximum,"EDA JSON exceeds its bounded transport.")
 con<-file(path,"rb");on.exit(close(con),add=TRUE);text<-rawToChar(readBin(con,"raw",n=file.info(path)$size));Encoding(text)<-"UTF-8"
 brohn_parse(.brohn_edd_json_text(text),max_bytes=maximum+1024L)
}
brohn_eda_write_json_file <- function(value,path,maximum=48*1024^2) {
 text<-.brohn_edd_json_text(brohn_json(value));brohn_require(nchar(text,type="bytes")<=maximum,"EDA JSON exceeds its bounded transport.")
 con<-file(path,"wb");on.exit(close(con),add=TRUE);writeBin(charToRaw(enc2utf8(text)),con);invisible(path)
}

.brohn_edd_decimal_parts <- function(value) {
 brohn_require(is.character(value)&&length(value)==1L&&!is.na(value)&&nchar(value,type="bytes")<=96L&&
  grepl("^[+-]?(?:[0-9]+(?:\\.[0-9]*)?|\\.[0-9]+)(?:[eE][+-]?[0-9]+)?$",value,perl=TRUE),"Enter an exact decimal source time of at most 80 ASCII characters.")
 negative<-startsWith(value,"-");unsigned<-sub("^[+-]","",value)
 parts<-strsplit(unsigned,"[eE]")[[1L]];mantissa<-parts[[1L]];exponent<-0L
 if(length(parts)==2L){e<-parts[[2L]];digits<-sub("^[+-]","",e);digits<-sub("^0+","",digits);if(!nzchar(digits))digits<-"0"
  brohn_require(nchar(digits)<=4L&&(nchar(digits)<4L||digits<="1100"),"The source-time exponent exceeds its canonical transport bound.")
  exponent<-as.integer(digits)*if(startsWith(e,"-"))-1L else 1L
 }
 split<-strsplit(mantissa,".",fixed=TRUE)[[1L]];fraction<-if(length(split)>1L)nchar(split[[2L]])else 0L
 coefficient<-gsub(".","",mantissa,fixed=TRUE);coefficient<-sub("^0+","",coefficient)
 submitted_exponent<-exponent
 if(!nzchar(coefficient)){brohn_require(nchar(value,type="bytes")<=80L&&abs(submitted_exponent)<=1000L,"The submitted decimal exceeds 80 characters or exponent 1000.");return(list(sign=0L,coefficient="0",exponent=0L,canonical="0"))}
 trimmed<-sub("0+$","",coefficient);exponent<-exponent-fraction+nchar(coefficient)-nchar(trimmed);coefficient<-trimmed
 order<-nchar(coefficient)+exponent
 brohn_require(order<=13L&&(order<13L||(coefficient=="1"&&exponent==12L)),"Source time must be between -1e12 and 1e12 seconds.")
 canonical<-paste0(if(negative)"-"else"",coefficient,if(exponent)paste0("e",exponent)else"")
 brohn_require(nchar(canonical,type="bytes")<=96L,"Canonical source time exceeds its string bound.")
 brohn_require((nchar(value,type="bytes")<=80L&&abs(submitted_exponent)<=1000L)||identical(value,canonical),"Only already-canonical source-time strings may use the extended transport bound.")
 list(sign=if(negative)-1L else 1L,coefficient=coefficient,exponent=exponent,canonical=canonical)
}
brohn_eda_decimal_compare <- function(a,b) {
 a<-.brohn_edd_decimal_parts(a);b<-.brohn_edd_decimal_parts(b)
 if(a$sign!=b$sign)return(sign(a$sign-b$sign));if(a$sign==0L)return(0L)
 ea<-nchar(a$coefficient)+a$exponent;eb<-nchar(b$coefficient)+b$exponent
 if(ea!=eb)return(a$sign*sign(ea-eb))
 width<-max(nchar(a$coefficient),nchar(b$coefficient));x<-paste0(a$coefficient,strrep("0",width-nchar(a$coefficient)));y<-paste0(b$coefficient,strrep("0",width-nchar(b$coefficient)))
 if(identical(x,y))0L else a$sign*if(x<y)-1L else 1L
}
brohn_normalize_eda_display_request <- function(request=NULL) {
 if(is.null(request))return(list(schema="brohn-eda-display-request/0.1",continuous_windows=list()))
 brohn_fields(request,c("schema","continuous_windows"),label="EDA saved-window request")
 brohn_require(identical(request$schema,"brohn-eda-display-request/0.1")&&brohn_array(request$continuous_windows)&&length(request$continuous_windows)<=2000L,"Choose a bounded EDA display request.")
 windows<-lapply(request$continuous_windows,function(x){brohn_fields(x,c("key","start_s","end_s"),label="Exact EDA source window");brohn_require(.brohn_rpk_hash(x$key),"Choose an exact prepared EDA cell key.")
  start<-.brohn_edd_decimal_parts(x$start_s)$canonical;end<-.brohn_edd_decimal_parts(x$end_s)$canonical
  brohn_require(brohn_eda_decimal_compare(start,end)<0L,"The source window end must follow its start.");list(key=x$key,start_s=start,end_s=end)})
 keys<-vapply(windows,`[[`,character(1),"key");brohn_require(!anyDuplicated(keys),"A source cell can have only one requested time window.")
 list(schema="brohn-eda-display-request/0.1",continuous_windows=windows[order(keys,method="radix")])
}
brohn_validate_eda_refusal <- function(refusal) {
 brohn_fields(refusal,c("schema","reason_code","source","resource","measured","maximum","recovery_scope","message"),label="EDA preparation refusal")
 identifier<-function(x)is.character(x)&&length(x)==1L&&!is.na(x)&&nchar(x,type="bytes")<=100L&&grepl("^[a-z][a-z0-9_]*$",x)
 quantity<-function(x)is.null(x)||brohn_number(x,0)
 brohn_require(identical(refusal$schema,"brohn-eda-report-refusal/0.1")&&identifier(refusal$reason_code)&&identifier(refusal$resource)&&quantity(refusal$measured)&&quantity(refusal$maximum)&&
  refusal$recovery_scope %in% c("none","fewer_sources","smaller_window","fewer_figures","repair_source","new_preparation")&&brohn_text(refusal$message,2000),"The structured EDA refusal is invalid.")
 if(!is.null(refusal$source)).brohn_rpk_ref_valid(refusal$source,"report")
 invisible(TRUE)
}
brohn_stop_eda_refusal <- function(refusal) {
 brohn_validate_eda_refusal(refusal)
 stop(structure(list(message=refusal$message,call=NULL,refusal=refusal),class=c("brohn_eda_refusal","error","condition")))
}
.brohn_edd_limit <- function(measured,maximum,resource,source=NULL,recovery="none",message=NULL) {
 if(measured>maximum)brohn_stop_eda_refusal(list(schema="brohn-eda-report-refusal/0.1",reason_code=paste0(resource,"_limit"),source=source,resource=resource,measured=measured,maximum=maximum,recovery_scope=recovery,message=brohn_default(message,paste("Complete EDA evidence exceeds the",resource,"limit."))))
 invisible(TRUE)
}

.brohn_edd_family <- function(a) {
 brohn_require(identical(a$kind,"eda")&&identical(a$modality,"eda")&&identical(a$schema,"brohn-worker-result/1.0"),"Choose a registered original EDA analysis.")
 if(identical(a$operation,"eda_events"))"event"else{brohn_require(!"operation" %in% names(a),"Continuous EDA cannot invent an operation field.");"continuous"}
}
.brohn_edd_identity <- function(record,family) {
 fields<-if(family=="event")c("recording_id","event_id","channel")else c("recording_id","segment_id","channel")
 stats::setNames(lapply(fields,function(k)record[[k]]),fields)
}

.brohn_edd_constant_fields <- c("processing_branch","descriptive_status","response_status","response_reason","numerical_candidate_count","response_denominator")
.brohn_edd_constant_support <- function(r,p) {
 expected<-list(processing_branch="exact_constant_raw_description/1.0",descriptive_status="computed",response_status="unavailable",response_reason="exact_constant_signal",numerical_candidate_count=0L,response_denominator=NULL)
 brohn_require(identical(p$recipe,"eda-neurokit-highpass/1.1")&&identical(p$exact_constant_policy,"raw_description_only/1.0")&&identical(r$status,"descriptive_only")&&identical(r$exact_flatline,TRUE)&&all(.brohn_edd_constant_fields %in% names(r))&&.brohn_rpk_same(r[.brohn_edd_constant_fields],expected),"Constant EDA support is outside its exact registered recipe/branch.")
 brohn_require(brohn_number(r$samples,1,2^53-1,TRUE)&&brohn_number(r$sampling_rate,8,100000)&&brohn_number(p$edge_exclusion_s,10,120)&&brohn_number(r$filter_edge_samples,0,r$samples,TRUE)&&r$filter_edge_samples==2*ceiling(p$edge_exclusion_s*r$sampling_rate)&&r$retained_samples==r$samples-r$filter_edge_samples&&r$retained_duration_s==r$retained_samples/r$sampling_rate&&r$retained_duration_s>=20,"Constant EDA coordinate and retained edge support do not reconcile.")
 invisible(TRUE)
}
.brohn_edd_constant_features <- function(features,r,p,preview=list(),events=list()) {
 .brohn_edd_constant_support(r,p)
 keys<-c("tonic_mean","tonic_median","tonic_slope","conductance_raw_mean","scr_count","scr_rate","scr_amplitude_mean","scr_amplitude_median","phasic_area_signed","phasic_area_positive")
 units<-c("uS","uS","uS/s","uS","count","count/min","uS","uS","uS*s","uS*s")
 brohn_require(length(features)==10L&&identical(vapply(features,`[[`,character(1),"name"),keys)&&identical(vapply(features,`[[`,character(1),"unit"),units),"Constant EDA must preserve all ten original ordered features and units.")
 raw<-features[[4L]]$value;brohn_require(brohn_number(raw,0),"Constant raw conductance description must be finite and admissible.")
 for(i in seq_along(features)){f<-features[[i]];descriptive<-i==4L;amplitude<-i %in% c(7L,8L)
  brohn_require(identical(f$eligible,descriptive)&&identical(f$support_status,if(descriptive)"computed"else"unavailable")&&identical(f$missing_reason,if(descriptive)NULL else"exact_constant_signal")&&(if(descriptive)brohn_number(f$value,0)else is.null(f$value))&&identical("denominator" %in% names(f),amplitude)&&(!amplitude||is.null(f$denominator)),"Constant EDA features changed nulls, eligibility or conditional denominators.")
 }
 same_cell<-function(x)identical(x$recording_id,r$recording_id)&&identical(x$segment_id,r$segment_id)&&identical(x$channel,r$channel)
 for(x in Filter(same_cell,preview))brohn_require(brohn_number(x$raw_us,0)&&x$raw_us==raw&&all(vapply(x[c("clean_us","tonic_us","phasic_us")],is.null,logical(1))),"Constant EDA preview invented a processed value or changed its saved raw level.")
 brohn_require(!length(Filter(same_cell,events)),"Constant EDA cannot retain numerical candidate records.")
 invisible(TRUE)
}
# Strict original producer vocabulary. These checks inspect saved values/support;
# they do not call a filter, detector, estimator or scientific worker.
.brohn_edd_semantics <- function(a,family,spec=.brohn_edd_profile_spec()) {
 event<-identical(family,"event")
 text<-function(x,nullable=FALSE)brohn_require((nullable&&is.null(x))||brohn_text(x,4000),"Original EDA text/identity has an unsupported type.")
 number<-function(x,nullable=FALSE,minimum=-Inf,integer=FALSE)brohn_require((nullable&&is.null(x))||brohn_number(x,minimum,Inf,integer),"Original EDA numerical evidence has an unsupported type.")
 bool<-function(x,nullable=FALSE)brohn_require((nullable&&is.null(x))||(is.logical(x)&&length(x)==1L&&!is.na(x)),"Original EDA support flag is not a JSON boolean.")
 array<-function(x)brohn_require(brohn_array(x),"Original EDA collection must remain a JSON array.")
 texts<-function(x){array(x);for(v in x)text(v)}
 group<-function(x){brohn_fields(x,character(),c("participant_id","session_id","condition_id","exposure_id","segment_id",if(event)"source_recording_id"),"Original EDA source group");for(v in x)text(v)}
 scalars<-function(x,strings=character(),nullable_strings=character(),numbers=character(),nullable_numbers=character(),counts=character(),nullable_counts=character(),booleans=character(),nullable_booleans=character()){
  for(k in strings)text(x[[k]]);for(k in nullable_strings)text(x[[k]],TRUE)
  for(k in numbers)number(x[[k]]);for(k in nullable_numbers)number(x[[k]],TRUE)
  for(k in counts)number(x[[k]],minimum=0,integer=TRUE);for(k in nullable_counts)number(x[[k]],TRUE,0,TRUE)
  for(k in booleans)bool(x[[k]]);for(k in nullable_booleans)bool(x[[k]],TRUE)
 }
 quality_fields<-c("invalid_amplitude_samples","missing_samples","time_gap_count","time_gap_seconds","timestamp_tolerance_s",if(event)c("original_missing_source_samples","source_validity_excluded_samples"))
 channel_quality<-function(q){brohn_fields(q,quality_fields,label="Original EDA channel quality");for(k in quality_fields)number(q[[k]],minimum=0,integer=!k %in% c("time_gap_seconds","timestamp_tolerance_s"))}
 identity_fields<-c("recording_id","channel","group","segment_id",if(event)"origin")
 identity<-function(x,segment=TRUE){text(x$recording_id);text(x$channel);group(x$group);if(segment)text(x$segment_id);if(event)text(x$origin)}
 candidate_fields<-if(event)c("type","peak_time_s","peak_sample_index","peak_height_us","onset_time_s","amplitude_us","recovery_time_s","recovery_fraction","onset_supported","recovery_supported")else c("type","time_s","peak_height_us","onset_time_s","amplitude_us","recovery_time_s","recovery_fraction","rise_time_s","recovery_time_from_peak_s","missing_reason")
 candidate<-function(x,full=TRUE){
  extra<-if(full)c(identity_fields,"source_peak_sample",if(!event)"segment_peak_sample")else character()
  brohn_fields(x,c(candidate_fields,extra),label="Original EDA candidate")
  brohn_require(identical(x$type,if(event)"scr_candidate"else"scr")&&identical(as.numeric(x$recovery_fraction),.5),"Original EDA candidate type/recovery meaning changed.")
  scalars(x,numbers=c(if(event)"peak_time_s"else"time_s","peak_height_us","recovery_fraction"),nullable_numbers=c("onset_time_s","amplitude_us","recovery_time_s",if(!event)c("rise_time_s","recovery_time_from_peak_s")),counts=if(event)"peak_sample_index",booleans=if(event)c("onset_supported","recovery_supported"),nullable_strings=if(!event)"missing_reason")
  if(full){identity(x);number(x$source_peak_sample,minimum=0,integer=TRUE);if(!event)number(x$segment_peak_sample,minimum=0,integer=TRUE)}
  if(event)brohn_require(identical(x$onset_supported,!is.null(x$onset_time_s))&&identical(x$recovery_supported,!is.null(x$recovery_time_s)),"Original candidate missing endpoints and support flags disagree.")
 }
 window<-function(x){
  required<-c("requested_start_s","requested_end_s","complete","observed_start_s","observed_end_s","samples","duration_s","reason")
  bool(x$complete);brohn_fields(x,c(required,if(isTRUE(x$complete))c("segment_id","start_alignment_error_s","end_alignment_error_s")),label="Original EDA event-window support")
  scalars(x,numbers=c("requested_start_s","requested_end_s"),nullable_numbers=c("observed_start_s","observed_end_s","duration_s"),counts="samples",nullable_strings="reason")
  brohn_require(x$requested_start_s<x$requested_end_s,"Original EDA method window is not increasing.")
  if(isTRUE(x$complete)){scalars(x,strings="segment_id",numbers=c("start_alignment_error_s","end_alignment_error_s","observed_start_s","observed_end_s","duration_s"));brohn_require(is.null(x$reason)&&x$samples>=2&&x$duration_s>0,"Complete EDA window lost measured support.")}
  else brohn_require(is.null(x$observed_start_s)&&is.null(x$observed_end_s)&&is.null(x$duration_s)&&x$samples==0&&brohn_text(x$reason,4000),"Unavailable EDA window invented measured support.")
 }
 brohn_fields(a$engine,c("artifact_writer_sha256","name","packages","python","version","worker_sha256",if(event)"shared_io_sha256"),label="Original EDA engine")
 scalars(a$engine,strings=c("name","python","version"));for(k in c("artifact_writer_sha256","worker_sha256",if(event)"shared_io_sha256"))brohn_require(.brohn_rpk_hash(a$engine[[k]]),"Original EDA engine hash is invalid.")
 brohn_fields(a$engine$packages,c("neurokit2","numpy","scipy"),if(event)"cvxopt"else character(),"Original EDA dependencies");for(v in a$engine$packages)text(v)
 brohn_fields(a$source,c("bytes","group_columns","rows","sha256","source_format","time_unit",if(event)c("condition_exposure_do_not_split_preprocessing","preprocessing_group_columns")),label="Original EDA source metadata")
 number(a$source$bytes,minimum=1,integer=TRUE);number(a$source$rows,minimum=1,integer=TRUE);brohn_require(.brohn_rpk_hash(a$source$sha256)&&a$source$source_format %in% c("csv","tsv")&&a$source$time_unit %in% c("s","ms"),"Original EDA source format/clock is unsupported.")
 brohn_fields(a$source$group_columns,character(),c("participant_id","session_id","condition_id","exposure_id","segment_id"),"Original source column mapping");for(v in a$source$group_columns)text(v)
 if(event){brohn_require(identical(a$source$condition_exposure_do_not_split_preprocessing,TRUE),"Event context must retain continuous preprocessing.");brohn_fields(a$source$preprocessing_group_columns,c("participant","recording","session"),label="Original preprocessing groups");for(v in a$source$preprocessing_group_columns)text(v,TRUE)}
 brohn_require(is.list(a$parameters)&&!is.null(names(a$parameters))&&!anyDuplicated(names(a$parameters))&&setequal(names(a$parameters),unique(vapply(a$recordings,`[[`,character(1),"recording_id"))),"Original EDA recipe membership differs from its recordings.")
 for(p in a$parameters).brohn_edd_recipe(p,event,spec)
 new_recipe<-!event&&any(vapply(a$parameters,function(p)identical(p$recipe,"eda-neurokit-highpass/1.1"),logical(1)))
 base_segment<-c(identity_fields,"source_time_origin","source_row_start","source_row_end_exclusive","start_time_s","end_time_s","samples","sampling_rate","unit","source_unit","scale_factor","channel_quality","exact_flatline","status")
 segment<-function(x){
  brohn_require(x$status %in% c("computed","unavailable",if(!event&&identical(spec$profile,"saved-eda-display/0.2"))"descriptive_only"),"Unknown original EDA segment status.")
  constant<-identical(x$status,"descriptive_only");computed<-identical(x$status,"computed")||constant
  if(constant).brohn_edd_constant_support(x,a$parameters[[x$recording_id]])
  brohn_fields(x,c(base_segment,if(computed)if(event)c("retained_samples","retained_start_time_s","retained_end_time_s","scr_detector_error")else c("retained_samples","retained_duration_s","filter_edge_samples")else"reason",if(constant).brohn_edd_constant_fields),label="Original EDA continuous segment")
  identity(x);channel_quality(x$channel_quality);scalars(x,strings=c("source_time_origin","unit","source_unit"),numbers=c("start_time_s","end_time_s","sampling_rate","scale_factor"),counts=c("source_row_start","source_row_end_exclusive","samples"),booleans="exact_flatline")
  brohn_require(identical(x$unit,"uS")&&x$source_unit %in% c("S","uS")&&x$scale_factor==(if(x$source_unit=="S")1e6 else 1)&&x$sampling_rate>0&&x$end_time_s>=x$start_time_s&&x$samples==x$source_row_end_exclusive-x$source_row_start,"Original EDA units or measured segment boundaries disagree.")
  if(computed){number(x$retained_samples,minimum=1,integer=TRUE);brohn_require(x$retained_samples<=x$samples,"Retained EDA samples exceed source support.");if(event){scalars(x,numbers=c("retained_start_time_s","retained_end_time_s"),nullable_strings="scr_detector_error")}else scalars(x,numbers="retained_duration_s",counts="filter_edge_samples")}
  else text(x$reason)
 }
 for(r in a$recordings){
  if(!event){if(is.null(r$segment_id)){
    brohn_fields(r,c("recording_id","channel","group","status","reason",quality_fields),label="Original empty EDA channel");identity(r,FALSE);channel_quality(r[quality_fields]);brohn_require(identical(r$status,"unavailable"),"A channel without finite support cannot be computed.");text(r$reason)
   }else segment(r);next}
  fields<-c("recording_id","event_id","channel","condition_id","exposure_id","stimulus_id","group","origin","status","reason","scr_status","scr_reason","baseline_support","response_support","same_continuous_segment","overlapping_event_ids","response_candidates","selected_scr","recovery_missing_reason","nonresponse","time_s","requested_time_s","alignment_error_s","source_time_origin","source_sample_index","sampling_rate","source_unit","unit","scale_factor","channel_quality","participant_linkage","analysis_unit")
  brohn_fields(r,fields,label="Original EDA event cell");identity(r,FALSE);scalars(r,strings=c("event_id","condition_id","exposure_id","source_time_origin","source_unit","unit","participant_linkage","analysis_unit"),nullable_strings=c("stimulus_id","reason","scr_reason","recovery_missing_reason"),numbers=c("time_s","requested_time_s","alignment_error_s","sampling_rate","scale_factor"),counts="source_sample_index",nullable_counts="response_candidates",booleans="same_continuous_segment",nullable_booleans="nonresponse")
  window(r$baseline_support);window(r$response_support);channel_quality(r$channel_quality);texts(r$overlapping_event_ids);if(!is.null(r$selected_scr))candidate(r$selected_scr,FALSE)
  brohn_require(r$status %in% c("computed","unavailable")&&r$scr_status %in% c("computed","unavailable")&&identical(r$unit,"uS")&&identical(r$participant_linkage,"declared_source_identity")&&identical(r$analysis_unit,"event_within_person_session")&&identical(is.null(r$reason),r$status=="computed")&&identical(is.null(r$scr_reason),r$scr_status=="computed"),"Original EDA descriptive/SCR support meanings disagree.")
 }
 if(event){array(a$segments);for(r in a$segments)segment(r);array(a$source_masks)
  for(m in a$source_masks){gap<-identical(m$reason,"clock_gap");brohn_fields(m,c("recording_id","channel","group","reason",if(gap)c("source_row_before","source_row_after","before_time_s","after_time_s","unobserved_duration_s")else c("source_row_start","source_row_end_exclusive","start_time_s","end_time_s","samples")),label="Original EDA exclusion mask");text(m$recording_id);text(m$channel);group(m$group);brohn_require(m$reason %in% c("clock_gap","missing_source_signal","source_validity_exclusion","negative_conductance"),"Unknown original EDA exclusion mask.");scalars(m,numbers=if(gap)c("before_time_s","after_time_s","unobserved_duration_s")else c("start_time_s","end_time_s"),counts=if(gap)c("source_row_before","source_row_after")else c("source_row_start","source_row_end_exclusive","samples"))}
 }
 for(f in a$features){owner<-Filter(function(r)identical(r$recording_id,f$recording_id)&&identical(r$segment_id,f$segment_id)&&identical(r$channel,f$channel),a$recordings);constant<-!event&&length(owner)==1L&&identical(owner[[1L]]$status,"descriptive_only");extra<-if(event)c("event_id","condition_id","exposure_id","stimulus_id","eligible","support_status","missing_reason")else if(constant)c("eligible","support_status","missing_reason")else character();descriptive<-event&&f$name %in% c("tonic_baseline_mean","tonic_response_mean","tonic_response_minus_baseline","phasic_response_area_signed","phasic_response_area_positive");denominator<-f$name %in% if(event)c("scr_response_magnitude","scr_responder_amplitude")else c("scr_amplitude_mean","scr_amplitude_median")
  brohn_fields(f,c(if(event)setdiff(identity_fields,"segment_id")else identity_fields,"name","scope","unit","value",extra,if(descriptive)"interpretation",if(denominator)"denominator"),label="Original EDA complete feature")
  identity(f,!event);text(f$name);text(f$unit);number(f$value,TRUE);brohn_require(f$scope %in% if(event)"event"else c("recording","recording_condition"),"Unknown EDA feature scope.")
  if(event){scalars(f,strings=c("event_id","condition_id","exposure_id","support_status"),nullable_strings=c("stimulus_id","missing_reason"),booleans="eligible");brohn_require(identical(f$eligible,identical(f$support_status,"computed"))&&identical(is.null(f$value),!f$eligible)&&identical(is.null(f$missing_reason),f$eligible),"EDA feature eligibility/null support disagree.");if(descriptive)brohn_require(f$interpretation %in% c("descriptive_window_measure","event_window_measure"),"Unknown event feature interpretation.");if(denominator)brohn_require(identical(f$denominator,if(f$name=="scr_response_magnitude")"all_eligible_events_including_nonresponses"else"eligible_responder_events_only"),"EDA response denominator changed.")}
  else if(constant){
   raw<-identical(f$name,"conductance_raw_mean");brohn_require(identical(f$eligible,raw)&&identical(f$support_status,if(raw)"computed"else"unavailable")&&identical(f$missing_reason,if(raw)NULL else"exact_constant_signal")&&if(raw)brohn_number(f$value,0)else is.null(f$value),"Constant EDA feature eligibility/value support changed.")
   if(denominator)brohn_require(is.null(f$denominator),"Constant EDA response denominators must remain unavailable.")
  }else if(denominator)number(f$denominator,minimum=0,integer=TRUE)
 }
 for(e in a$events){if(!event||identical(e$type,"scr_candidate")){candidate(e);next}
  brohn_fields(e,c("recording_id","group","origin","id","type","time_s","requested_time_s","alignment_error_s","source_sample_index","code","condition_id","exposure_id"),"stimulus_id","Original measured EDA event")
  group(e$group);scalars(e,strings=c("recording_id","origin","id","type","code"),nullable_strings=c("condition_id","exposure_id"),numbers=c("time_s","requested_time_s","alignment_error_s"),counts="source_sample_index");if("stimulus_id" %in% names(e))text(e$stimulus_id,TRUE);brohn_require(e$type %in% c("stimulus_event","nuisance_event"),"Unknown measured event type.")
 }
 for(s in a$series){brohn_fields(s,c(identity_fields,"time_s","retained","raw_us","clean_us","tonic_us","phasic_us"),label="Original bounded EDA preview");identity(s);scalars(s,numbers="time_s",nullable_numbers=c("raw_us","clean_us","tonic_us","phasic_us"),booleans="retained")}
 quality_common<-c("usable","requires_research_review","scientifically_qualified","channel_samples_total","channel_samples_retained","series_samples_displayed","display_sampling","warnings","complete_processed_artifacts","raw_source_duplicated")
 quality_extra<-if(event)c("participant_inference_performed","requested_event_channel_cells","computed_window_cells","computed_scr_cells","unavailable_window_cells","source_events","scr_candidates")else c("computed_channel_segments","unavailable_channel_segments","missing_channel_samples","invalid_amplitude_channel_samples","retained_fraction","event_records_total","event_records_displayed","series_samples_total",if(new_recipe)"descriptive_channel_segments")
 brohn_fields(a$quality,c(quality_common,quality_extra),label="Original EDA aggregate support");texts(a$quality$warnings);text(a$quality$display_sampling);texts(a$limitations)
 flags<-c("usable","requires_research_review","scientifically_qualified","complete_processed_artifacts","raw_source_duplicated",if(event)"participant_inference_performed")
 for(k in flags)bool(a$quality[[k]]);for(k in setdiff(c(quality_common,quality_extra),c(flags,"warnings","display_sampling","retained_fraction")))number(a$quality[[k]],minimum=0,integer=TRUE)
 if(!event)number(a$quality$retained_fraction,TRUE,0)
 count<-sum(vapply(a$recordings,function(x)identical(x$status,"computed"),logical(1)))
 descriptive_count<-sum(vapply(a$recordings,function(x)identical(x$status,"descriptive_only"),logical(1)))
 if(new_recipe)brohn_require(a$quality$descriptive_channel_segments==descriptive_count,"Original descriptive EDA count differs from its exact segment statuses.")
 brohn_require(identical(a$quality$usable,count+descriptive_count>0)&&a$quality$series_samples_displayed==length(a$series)&&a$quality$channel_samples_retained<=a$quality$channel_samples_total&&identical(a$quality$scientifically_qualified,FALSE)&&identical(a$quality$requires_research_review,TRUE)&&identical(a$quality$raw_source_duplicated,FALSE),"Original EDA aggregate support or qualification meaning changed.")
 if(event)brohn_require(a$quality$computed_window_cells==count&&a$quality$unavailable_window_cells==length(a$recordings)-count&&a$quality$requested_event_channel_cells==length(a$recordings)&&a$quality$computed_scr_cells==sum(vapply(a$recordings,function(x)identical(x$scr_status,"computed"),logical(1)))&&identical(a$quality$participant_inference_performed,FALSE),"Original EDA event support counts disagree.")else brohn_require(a$quality$computed_channel_segments==count&&a$quality$unavailable_channel_segments==length(a$recordings)-count-descriptive_count&&a$quality$event_records_displayed==length(a$events)&&a$quality$event_records_total>=length(a$events),"Original EDA segment/candidate support counts disagree.")
 invisible(TRUE)
}
.brohn_edd_recipe <- function(p,event,spec=.brohn_edd_profile_spec()) {
 if(!event){brohn_require(p$recipe %in% spec$continuous_recipes,"This preparation profile does not admit the original continuous EDA recipe.");fixed<-list(recipe=p$recipe,cleaner="neurokit",clean_lowpass_hz=3,clean_order=4,decomposition="highpass",phasic_cutoff_hz=.05,recovery_fraction=.5,no_missing_value_imputation=TRUE,threshold_definition="candidate_prominence_relative_to_maximum_prominence")
  if(identical(p$recipe,"eda-neurokit-highpass/1.1"))fixed$exact_constant_policy<-"raw_description_only/1.0"
  brohn_fields(p,c(names(fixed),"edge_exclusion_s","amplitude_min_relative_prominence"),label="Original continuous EDA recipe")
  brohn_require(.brohn_rpk_same(p[names(fixed)],fixed)&&brohn_number(p$edge_exclusion_s,0)&&brohn_number(p$amplitude_min_relative_prominence,0,1),"Original continuous EDA recipe changed fixed semantics.");return(invisible(TRUE))}
 fields<-c("recipe","event_codes","nuisance_codes","event_source","settings_source","baseline_s","response_s","onset_latency_s","recovery_end_s","nuisance_effect_s","overlap_policy","response_selection","minimum_scr_amplitude_us","relative_prominence","edge_exclusion_s","minimum_segment_s","event_tolerance_s","effective")
 brohn_fields(p,fields,label="Original event EDA recipe");brohn_require(p$recipe %in% c("eda-event-highpass/1.0","eda-event-cvxeda-defaults/1.0")&&brohn_text(p$event_source,4000)&&brohn_text(p$settings_source,4000)&&p$overlap_policy %in% c("exclude","descriptive_only")&&p$response_selection %in% c("first_onset","largest_amplitude"),"Original event EDA recipe is unsupported.")
 for(k in c("baseline_s","response_s","onset_latency_s","nuisance_effect_s")){x<-p[[k]];brohn_require(brohn_array(x)&&length(x)==2L&&all(vapply(x,brohn_number,logical(1),-120,300))&&x[[1L]]<x[[2L]],"Original event method window is invalid.")}
 brohn_require(p$baseline_s[[2L]]<=0&&p$response_s[[1L]]>=0&&p$onset_latency_s[[1L]]>=p$response_s[[1L]]&&p$onset_latency_s[[2L]]<=p$response_s[[2L]]&&brohn_number(p$recovery_end_s,p$response_s[[2L]],300)&&brohn_number(p$minimum_scr_amplitude_us,.000001,100)&&brohn_number(p$relative_prominence,.001,1)&&brohn_number(p$edge_exclusion_s,10,300)&&brohn_number(p$minimum_segment_s,max(40,2*p$edge_exclusion_s+20),3600)&&brohn_number(p$event_tolerance_s,0),"Original event recipe bounds changed.")
 brohn_require(is.list(p$event_codes)&&!is.null(names(p$event_codes))&&length(p$event_codes)>=1L&&length(p$event_codes)<=100L&&!anyDuplicated(names(p$event_codes))&&all(vapply(c(as.list(names(p$event_codes)),unname(p$event_codes)),brohn_text,logical(1),128))&&brohn_array(p$nuisance_codes)&&length(p$nuisance_codes)<=100L&&all(vapply(p$nuisance_codes,brohn_text,logical(1),128))&&!anyDuplicated(unlist(p$nuisance_codes))&&!any(names(p$event_codes) %in% unlist(p$nuisance_codes)),"Original event/nuisance mapping is invalid.")
 high<-identical(p$recipe,"eda-event-highpass/1.0")
 effective<-list(cleaner="neurokit",clean_lowpass_hz=3,clean_order=4,decomposition=if(high)"highpass"else"cvxeda",phasic_cutoff_hz=if(high).05 else NULL,cvx_defaults=if(high)NULL else list(tau0=2,tau1=.7,delta_knot=10,alpha=.0008,gamma=.01,solver=NULL,reltol=1e-9),detector="neurokit",relative_threshold_definition="candidate_prominence_relative_to_segment_maximum_prominence",absolute_threshold_definition="phasic_onset_to_peak_amplitude_us",recovery_fraction=.5,integration="trapezoid_on_measured_endpoints",window_support="complete_same_continuous_segment",interpolation=FALSE,event_time_coordinates="seconds_relative_to_each_source_recording_first_timestamp")
 brohn_require(.brohn_rpk_same(p$effective,effective),"Original event decomposition defaults/measurement semantics changed.");invisible(TRUE)
}
.brohn_edd_validate_analysis <- function(report,spec=.brohn_edd_profile_spec()) {
 a<-report$complete_analysis;b<-report$saved_body;family<-.brohn_edd_family(a)
 fields<-c("schema","modality","status","engine","source","parameters","features","events","series","recordings","limitations","artifacts","quality","kind","title","observations","contrasts")
 if(family=="event")fields<-c(fields,"operation","segments","source_masks")
 brohn_fields(a,fields,if(length(a$artifacts))"artifact_verification"else character(),"Original EDA analysis")
 brohn_require(identical(brohn_hash(b),report$ref$body_hash)&&identical(b$analysis,a)&&identical(a$source$sha256,b$provenance$source$hash)&&brohn_text(a$title,2000)&&brohn_array(a$observations)&&!length(a$observations)&&brohn_array(a$contrasts)&&!length(a$contrasts),"Original EDA analysis/ref/source identity changed.")
 brohn_require(brohn_array(a$recordings)&&length(a$recordings)>0L&&brohn_array(a$features)&&brohn_array(a$series)&&brohn_array(a$events)&&brohn_array(a$artifacts)&&length(a$artifacts) %in% c(0L,2L),"Original EDA collections are malformed.")
 .brohn_edd_semantics(a,family,spec)
 .brohn_edd_limit(length(a$recordings),2000L,"source_cells",report$ref,"fewer_sources")
 for(artifact in a$artifacts).brohn_edd_descriptor(artifact)
 if(length(a$artifacts)){
  brohn_fields(a$artifact_verification,c("schema","status","artifacts"),label="Original EDA artifact verification")
  brohn_require(identical(a$artifact_verification$schema,"brohn-physiology-artifact-receipt/1.0")&&identical(a$artifact_verification$status,"verified")&&length(a$artifact_verification$artifacts)==2L,"Original EDA stream verification is incomplete.")
  for(i in seq_along(a$artifacts)){x<-a$artifacts[[i]];v<-a$artifact_verification$artifacts[[i]]
   brohn_fields(v,c("kind","schema","sha256","bytes","rows","tables","provenance_sha256","verified"),label="Original complete stream receipt")
   expected<-list(kind=x$kind,schema=x$schema,sha256=x$hash,bytes=x$size,rows=x$rows,tables=x$tables,provenance_sha256=x$provenance_sha256,verified=TRUE)
   brohn_require(.brohn_rpk_same(v,expected),"Original EDA processed-stream descriptor and verification disagree.")
  }
 }
 known<-if(family=="event")c("tonic_baseline_mean","tonic_response_mean","tonic_response_minus_baseline","phasic_response_area_signed","phasic_response_area_positive","scr_response_magnitude","scr_responder_amplitude","scr_qualifying_count","scr_nonresponse","scr_onset_latency","scr_peak_latency","scr_rise_time","scr_half_recovery_time")else c("tonic_mean","tonic_median","tonic_slope","conductance_raw_mean","scr_count","scr_rate","scr_amplitude_mean","scr_amplitude_median","phasic_area_signed","phasic_area_positive")
 ids<-character()
 for(cell in a$recordings){
  identity<-.brohn_edd_identity(cell,family);brohn_require(brohn_text(cell$recording_id,500)&&brohn_text(cell$channel,500)&&cell$status %in% c("computed","unavailable",if(family=="continuous"&&identical(spec$profile,"saved-eda-display/0.2"))"descriptive_only"),"Original EDA cell identity or status is unsupported.")
  if(family=="event")brohn_require(brohn_text(cell$event_id,500)&&cell$scr_status %in% c("computed","unavailable")&&brohn_number(cell$time_s)&&identical(cell$unit,"uS"),"Original measured EDA event support is invalid.")
  else if(!is.null(cell$segment_id))brohn_require(brohn_text(cell$segment_id,500)&&brohn_number(cell$start_time_s)&&brohn_number(cell$end_time_s)&&cell$end_time_s>=cell$start_time_s,"Original continuous segment bounds are invalid.")
  key<-brohn_eda_value_hash(identity);brohn_require(!key %in% ids,"Original EDA cells have duplicate exact identities.");ids<-c(ids,key)
  p<-a$parameters[[cell$recording_id]];allowed<-if(family=="event")c("eda-event-highpass/1.0","eda-event-cvxeda-defaults/1.0")else spec$continuous_recipes
  brohn_require(is.list(p)&&p$recipe %in% allowed,"The original EDA recipe is unsupported.")
  features<-Filter(function(f)all(vapply(names(identity),function(k)identical(f[[k]],identity[[k]]),logical(1))),a$features)
  if(family=="event"||cell$status %in% c("computed","descriptive_only"))brohn_require(length(features)==length(known)&&setequal(vapply(features,`[[`,character(1),"name"),known),"The original EDA cell lost a registered complete feature.")
  if(identical(cell$status,"descriptive_only")) .brohn_edd_constant_features(features,cell,p,a$series,a$events)
  for(f in features){brohn_require(f$name %in% known&&(is.null(f$value)||brohn_number(f$value))&&brohn_text(f$unit,100)&&is.list(f$group),"Original EDA feature types are unsupported.")
   if(family=="event")brohn_require(is.logical(f$eligible)&&length(f$eligible)==1L&&!is.na(f$eligible)&&f$support_status %in% c("computed","unavailable")&&(!is.null(f$value)||!is.null(f$missing_reason)),"Original EDA event eligibility or unavailable reason was lost.")
  }
 }
 if(!length(a$artifacts))brohn_require(!any(vapply(if(family=="event")a$segments else a$recordings,function(x)x$status %in% c("computed","descriptive_only"),logical(1))),"Computed or descriptive EDA source segments require both original typed streams.")
 invisible(TRUE)
}
.brohn_edd_source_binding <- function(report,context)list(report_ref=report$ref,analysis_hash=brohn_hash(report$complete_analysis),dataset_ref=context$selected$eda_dataset_ref,result_object=.brohn_td_object_ref(report$saved_body$result_object),original_stream_descriptors=report$complete_analysis$artifacts,source_closure_hash=brohn_hash(context$closure))
brohn_validate_eda_display_evidence <- function(evidence,report,body,pulse=NULL) {
 .brohn_rpk_source_pulse(pulse)
 spec<-.brohn_edd_profile_spec(body$implementation$profile)
 .brohn_edd_validate_analysis(report,spec);a<-report$complete_analysis;family<-.brohn_edd_family(a)
 # The exact complete analysis is unchanged across its cells. Hash it once.
 analysis_hash<-brohn_hash(a)
 brohn_fields(evidence,c("schema","source_family","source","display_request","implementation","cells","coverage"),label="Complete prepared EDA display")
 brohn_require(identical(evidence$schema,spec$evidence_schema)&&identical(evidence$source_family,family)&&.brohn_rpk_same(evidence$source,body$source)&&.brohn_rpk_same(evidence$implementation,body$implementation)&&.brohn_rpk_same(evidence$display_request,body$display_request)&&.brohn_rpk_same(evidence$display_request,brohn_normalize_eda_display_request(evidence$display_request))&&length(evidence$cells)==length(a$recordings),"Prepared EDA evidence changed source, request, implementation or complete cell membership.")
 brohn_require(.brohn_rpk_same(evidence$source$report_ref,report$ref)&&identical(evidence$source$analysis_hash,analysis_hash)&&.brohn_rpk_same(evidence$source$original_stream_descriptors,a$artifacts),"Prepared EDA source binding differs from its exact original analysis.")
 for(i in seq_along(evidence$cells)){.brohn_rpk_source_pulse(pulse);c<-evidence$cells[[i]];original<-a$recordings[[i]];identity<-.brohn_edd_identity(original,family)
  brohn_fields(c,c("key","identity","source_record_index","original_status","status","reason","selection","original_default_bounds","requested_bounds","original_support","feature_indices","model","model_hash","coverage"),label="Prepared EDA cell")
  key<-brohn_eda_value_hash(list(report_ref=report$ref,source_family=family,identity=identity))
  indices<-which(vapply(a$features,function(f)all(vapply(names(identity),function(k)identical(f[[k]],identity[[k]]),logical(1))),logical(1)))
  brohn_require(identical(c$key,key)&&c$source_record_index==i&&.brohn_rpk_same(c$identity,identity)&&identical(brohn_eda_value_hash(c$original_support),brohn_eda_value_hash(original))&&identical(c$original_status,original$status)&&.brohn_rpk_same(c$feature_indices,as.list(indices)),"Prepared EDA cell lost its exact original identity, support or feature membership.")
  if(is.null(c$model))brohn_require(is.null(c$model_hash)&&identical(c$status,"unavailable"),"Unavailable EDA evidence cannot invent a waveform.")else brohn_require(identical(c$model_hash,brohn_eda_value_hash(c$model))&&c$status %in% c("available","no_processed_samples",if(identical(spec$profile,"saved-eda-display/0.2"))"raw_description_only"),"Prepared EDA waveform model failed its typed-value binding.")
  .brohn_edd_validate_model(c,report,evidence,analysis_hash);.brohn_rpk_source_pulse(pulse)
 }
 brohn_fields(evidence$coverage,c("available_cells","cells","complete_processed_rows","complete_raw_series_included","features","original_artifacts","original_raw_preview_preserved","original_rows","original_stream_bytes","original_tables","scientific_processing","unavailable_cells",if(identical(spec$profile,"saved-eda-display/0.2"))c("descriptive_only_cells","complete_coordinate_rows","coordinate_only_rows")),label="Complete EDA coverage")
 expected<-list(available_cells=sum(vapply(evidence$cells,function(x)identical(x$status,"available"),logical(1))),cells=length(a$recordings),complete_processed_rows=TRUE,complete_raw_series_included=FALSE,features=length(a$features),original_artifacts=length(a$artifacts),original_raw_preview_preserved=TRUE,original_rows=sum(vapply(a$artifacts,`[[`,numeric(1),"rows")),original_stream_bytes=sum(vapply(a$artifacts,`[[`,numeric(1),"size")),original_tables=sum(vapply(a$artifacts,`[[`,numeric(1),"tables")),scientific_processing=FALSE,unavailable_cells=sum(vapply(evidence$cells,function(x)!identical(x$status,"available"),logical(1))))
 if(identical(spec$profile,"saved-eda-display/0.2")){
  expected$descriptive_only_cells<-sum(vapply(evidence$cells,function(x)identical(x$status,"raw_description_only"),logical(1)))
  expected$unavailable_cells<-sum(vapply(evidence$cells,function(x)x$status %in% c("unavailable","no_processed_samples"),logical(1)))
  expected$complete_coordinate_rows<-TRUE
  expected$coordinate_only_rows<-sum(vapply(Filter(function(x)identical(x$status,"descriptive_only"),a$recordings),function(x)x$samples,numeric(1)))
 }
 brohn_require(.brohn_rpk_same(evidence$coverage,expected),"Complete prepared EDA coverage differs from its original evidence.")
 if(!is.null(body$catalog))brohn_require(.brohn_rpk_same(body$catalog,.brohn_edd_catalog(evidence)),"Prepared EDA catalog differs from its full exact models.")
 .brohn_rpk_source_pulse(pulse)
 invisible(TRUE)
}
.brohn_edd_validate_model <- function(cell,report,evidence,analysis_hash=brohn_hash(report$complete_analysis)) {
 a<-report$complete_analysis;r<-cell$original_support;event<-identical(evidence$source_family,"event");p<-a$parameters[[r$recording_id]];constant<-identical(r$status,"descriptive_only")
 decimal<-function(x).brohn_edd_decimal_parts(.brohn_ecr_shortest(x))$canonical
 default<-if(event)list(start_s=decimal(p$baseline_s[[1L]]),end_s=decimal(p$recovery_end_s))else if(r$status %in% c("computed","descriptive_only"))list(start_s=decimal(r$start_time_s),end_s=decimal(r$end_time_s))else NULL
 override<-Filter(function(x)identical(x$key,cell$key),evidence$display_request$continuous_windows)
 brohn_require(!constant||!length(override),"An exact-constant source has no recoverable processed response window; retain its whole descriptive support.")
 requested<-if(length(override))override[[1L]][c("start_s","end_s")]else default
 brohn_require(.brohn_rpk_same(cell$original_default_bounds,default)&&.brohn_rpk_same(cell$requested_bounds,requested)&&(!length(override)||(!event&&!is.null(default)&&brohn_eda_decimal_compare(requested$start_s,default$start_s)>=0&&brohn_eda_decimal_compare(requested$end_s,default$end_s)<=0)),"EDA display window differs from its original/requested exact bounds.")
 selection<-cell$identity;if(!event&&!is.null(default))selection<-c(selection,requested)
 brohn_require(.brohn_rpk_same(cell$selection,selection)&&.brohn_rpk_same(cell$coverage,list(features=length(cell$feature_indices),scientific_processing=FALSE,source_record_preserved=TRUE)),"EDA display selection or complete feature coverage changed.")
 m<-cell$model;if(is.null(m))return(invisible(TRUE))
 fields<-c("schema","binding","candidates","counts","display_policy","features","markers","parameters","series","source_tables","status","unit","verification",if(event)c("event","range_s","source_events","source_masks")else c("endpoint_coverage","limitations","raw_available","recording","selection",if(constant)"processed_components"))
 brohn_fields(m,fields,label="Saved EDA display model")
 brohn_require(identical(m$schema,if(event)"brohn-eda-review/1.0"else if(identical(p$recipe,"eda-neurokit-highpass/1.1"))"brohn-eda-continuous-review/1.1"else"brohn-eda-continuous-review/1.0")&&identical(m$status,cell$status)&&identical(m$unit,"uS")&&brohn_text(m$display_policy,4000)&&.brohn_rpk_same(m$binding,list(report_ref=report$ref,analysis_hash=analysis_hash,origin=report$saved_body$origin,selection=cell$selection))&&.brohn_rpk_same(m$parameters,p)&&.brohn_rpk_same(m$features,a$features[unlist(cell$feature_indices)]),"EDA model lost its exact original binding, parameters or full measurements.")
 brohn_require(identical(brohn_eda_value_hash(if(event)m$event else m$recording),brohn_eda_value_hash(r)),"EDA model changed original cell support.")
 expected<-lapply(a$artifacts,function(x)list(kind=x$kind,sha256=x$hash,rows=x$rows,tables=x$tables));arrange<-function(x)x[order(vapply(x,`[[`,character(1),"kind"),method="radix")]
 brohn_require(.brohn_rpk_same(arrange(m$verification),arrange(expected)),"EDA model omitted original processed stream verification.")
 if(event){brohn_require(.brohn_rpk_same(m$range_s,list(p$baseline_s[[1L]],p$recovery_end_s)),"Event display changed its saved method windows.")
  events<-Filter(function(x)identical(x$recording_id,r$recording_id)&&x$type %in% c("stimulus_event","nuisance_event")&&((x$time_s>=r$time_s+p$baseline_s[[1L]]&&x$time_s<=r$time_s+p$recovery_end_s)||x$id %in% unlist(r$overlapping_event_ids)),a$events)
  masks<-Filter(function(x)identical(x$recording_id,r$recording_id)&&identical(x$channel,r$channel),a$source_masks)
  brohn_require(.brohn_rpk_same(m$source_events,events)&&.brohn_rpk_same(m$source_masks,masks),"Event display dropped original measured events or source exclusions.")
 }else brohn_require(.brohn_rpk_same(m$selection,selection)&&identical(m$raw_available,FALSE)&&brohn_array(m$limitations)&&all(vapply(m$limitations,brohn_text,logical(1),4000)),"Continuous display altered source time selection or raw-data scope.")
 if(constant){
  brohn_require(identical(cell$status,"raw_description_only")&&identical(cell$reason,"exact_constant_signal"),"Constant EDA display support changed its explanatory status.")
  .brohn_ecr_validate_constant_model(m,r,p,a$features[unlist(cell$feature_indices)],lapply(a$artifacts,function(x)list(kind=x$kind,rows=x$rows)),selection,FALSE)
  return(invisible(TRUE))
 }
 countfields<-if(event)c("complete_artifact_rows","excluded_rows","matched_channel_rows","retained_rows","selected_rows")else c("complete_event_artifact_rows","complete_sample_artifact_rows","excluded_samples","retained_samples","segment_amplitude_available","segment_candidates","segment_onset_missing","segment_recovery_missing","segment_retained_samples","segment_samples","selected_candidates","selected_samples")
 brohn_fields(m$counts,countfields,label="EDA display support counts");for(x in m$counts)brohn_require(brohn_number(x,0,2^53-1,TRUE),"EDA display counts must remain nonnegative integers.")
 counts<-m$counts;selected<-if(event)counts$selected_rows else counts$selected_samples;retained<-if(event)counts$retained_rows else counts$retained_samples;excluded<-if(event)counts$excluded_rows else counts$excluded_samples
 brohn_require(selected<=500000L&&retained+excluded==selected&&identical(m$status,if(selected>0)"available"else"no_processed_samples"),"EDA display support counts do not reconcile.")
 brohn_fields(m$series,c("clean_us","tonic_us","phasic_us"),label="EDA processed display components")
 for(groups in m$series){brohn_require(brohn_array(groups)&&length(groups)<=200L&&sum(vapply(groups,function(g)length(g$points),integer(1)))<=2000L&&sum(vapply(groups,function(g)g$source_rows,numeric(1)))==selected,"EDA trace groups exceed their actual-point bounds or omit source support.")
  for(g in groups){brohn_fields(g,c("points","retained","source_rows",if(event)"table_id"),label="EDA observed trace group");brohn_require(is.logical(g$retained)&&length(g$retained)==1L&&!is.na(g$retained)&&brohn_number(g$source_rows,length(g$points),500000,TRUE)&&brohn_array(g$points),"EDA trace retained/excluded support is invalid.");if(event)brohn_require(brohn_text(g$table_id,160),"EDA trace lost its original table.")
   for(pt in g$points){brohn_fields(pt,c("source_sample_index","time_s","value"),label="Original EDA display point");brohn_require(brohn_number(pt$source_sample_index,0,2^53-1,TRUE)&&brohn_number(pt$time_s)&&brohn_number(pt$value)&&brohn_eda_decimal_compare(decimal(pt$time_s),requested$start_s)>=0&&brohn_eda_decimal_compare(decimal(pt$time_s),requested$end_s)<=0,"EDA display point changed source index or exact window membership.")}
   if(length(g$points)>1L)brohn_require(all(diff(vapply(g$points,`[[`,numeric(1),"time_s"))>0),"EDA traces cannot join reversed/reset time.")
  }
 }
 brohn_require(brohn_array(m$candidates)&&length(m$candidates)<=if(event)20000L else 5000L,"EDA candidate display exceeds its registered bound.")
 if(event)brohn_require(length(m$markers)==3L*length(m$candidates),"Event display lost candidate endpoint states.")else brohn_require(length(m$candidates)==counts$selected_candidates&&counts$segment_samples==r$samples&&counts$segment_retained_samples==r$retained_samples,"Continuous candidate or whole-segment counts changed.")
 # Python independently verifies exact table/column/support grammar against the
 # sealed typed streams. Retain the full immutable headers here, not a preview.
 brohn_require(brohn_array(m$source_tables)&&brohn_array(m$markers),"EDA tables/markers must retain their original ordered arrays.")
 invisible(TRUE)
}

.brohn_edd_context <- function(store,report_ref,preparation_profile="saved-eda-display/0.1") {
 spec<-.brohn_edd_profile_spec(preparation_profile)
 metadata<-.brohn_rpk_source_metadata(store,list(report_ref),source_admission=spec$admission)
 selected<-Filter(function(x).brohn_rpk_same(x$ref,report_ref),metadata$reports)
 brohn_require(length(selected)==1L&&!is.null(selected[[1L]]$eda_source_family),"Choose an exact supported EDA report.")
 fields<-c("ref","study_id","origin","design_hash","eda_source_family","eda_dataset_ref","artifacts","result_object")
 closure<-list(reports=lapply(metadata$reports,function(x)stats::setNames(lapply(fields,function(k)x[[k]]),fields)),objects=lapply(metadata$objects,.brohn_td_object_ref),dataset=selected[[1L]]$eda_source_closure$dataset,
  ingestion=if(is.null(selected[[1L]]$eda_source_closure$ingestion))NULL else selected[[1L]]$eda_source_closure$ingestion$ref,lineage=selected[[1L]]$eda_source_closure$lineage$binding)
 list(metadata=metadata,selected=selected[[1L]],closure=closure)
}
.brohn_eda_display_request <- function(store,report_ref,display_request=NULL,implementation_ref=NULL,preparation_profile="saved-eda-display/0.1") {
 spec<-.brohn_edd_profile_spec(preparation_profile)
 authority<-brohn_report_package_queue_authority(store,"eda_display",report_ref$project_id)
 implementation<-brohn_eda_display_implementation(spec$profile);actual<-.brohn_td_implementation_ref(implementation)
 if(!is.null(implementation_ref))brohn_require(.brohn_rpk_same(actual,implementation_ref),"EDA preparation code changed. Review and prepare a new intent explicitly.")
 context<-.brohn_edd_context(store,report_ref,spec$profile);m<-context$selected;request<-brohn_normalize_eda_display_request(display_request)
 if(m$eda_source_family=="event")brohn_require(!length(request$continuous_windows),"Event method windows stay fixed to their saved scientific settings.")
 r<-list(schema="brohn-eda-display-job/0.1",project_id=report_ref$project_id,study_id=m$study_id,report_ref=report_ref,source_family=m$eda_source_family,display_request=request,original_closure=context$closure,preparation_profile=spec$profile,implementation=implementation,authority=authority)
 r$content_fingerprint<-brohn_hash(r[setdiff(names(r),"authority")]);r
}
brohn_queue_eda_display <- function(store,report_ref,display_request=NULL,retry=FALSE,implementation_ref=NULL,preparation_profile="saved-eda-display/0.1") {
 r<-.brohn_eda_display_request(store,report_ref,display_request,implementation_ref,preparation_profile)
 brohn_store_batch(store,function(){old<-.brohn_rpk_latest_job(store,"eda_display",r$content_fingerprint)
  if(!is.null(old)&&(!isTRUE(retry)||old$status %in% c("queued","running","succeeded")))return(old)
  brohn_enqueue_job(store,"eda_display",r,paste0("eda-display:",r$content_fingerprint,if(isTRUE(retry))paste0(":",brohn_id("retry"))else""))})
}
brohn_eda_display_input <- function(store,job,verify=FALSE) {
 store<-brohn_report_package_job_authorize(store,job);r<-job$request;spec<-.brohn_edd_profile_spec(r$preparation_profile)
 brohn_fields(r,c("schema","project_id","study_id","report_ref","source_family","display_request","original_closure","preparation_profile","implementation","authority","content_fingerprint"),label="EDA display request")
 brohn_require(identical(job$operation,"eda_display")&&identical(r$schema,"brohn-eda-display-job/0.1")&&identical(r$preparation_profile,spec$profile)&&.brohn_rpk_same(r$implementation,brohn_eda_display_implementation(spec$profile))&&identical(r$content_fingerprint,brohn_hash(r[setdiff(names(r),c("authority","content_fingerprint"))]))&&.brohn_rpk_same(r$display_request,brohn_normalize_eda_display_request(r$display_request)),"EDA preparation source, normalized window or loaded code changed.")
 context<-.brohn_edd_context(store,r$report_ref,spec$profile)
 brohn_require(.brohn_rpk_same(context$closure,r$original_closure)&&identical(r$source_family,context$selected$eda_source_family)&&identical(r$study_id,context$selected$study_id)&&identical(r$project_id,r$report_ref$project_id),"Original EDA source closure or current permission changed.")
 list(schema="brohn-analysis-input/1.0",operation="eda_display",project_id=r$project_id,report_ref=r$report_ref,content_fingerprint=r$content_fingerprint)
}
brohn_prepare_eda_display_execution <- function(store,job,input,scratch,pulse=NULL) {
 .brohn_rpk_source_pulse(pulse)
 store<-brohn_report_package_job_authorize(store,job);.brohn_edd_check_code(job$request$implementation)
 brohn_require(.brohn_rpk_same(input,brohn_eda_display_input(store,job,FALSE)),"EDA input changed before source preparation.")
 context<-.brohn_edd_context(store,job$request$report_ref,job$request$preparation_profile);handle<-.brohn_rpk_hold_sources(store,context$metadata,pulse);ok<-FALSE;on.exit(if(!ok).brohn_rpk_release(handle),add=TRUE)
 all<-.brohn_rpk_complete_sources(store,handle,TRUE,pulse)$reports
 for(report in all){.brohn_rpk_source_pulse(pulse);brohn_validate_complete_report_analysis(report,.brohn_edd_profile_spec(job$request$preparation_profile)$admission);.brohn_rpk_source_pulse(pulse)}
 report<-Filter(function(x).brohn_rpk_same(x$ref,job$request$report_ref),all)[[1L]]
 original<-context$selected$eda_source_closure$dataset$source
 request<-list(schema="brohn-eda-display-worker-request/0.1",report=report,source=.brohn_edd_source_binding(report,context),display_request=job$request$display_request,implementation=job$request$implementation,
  streams=.brohn_edd_streams(store,report),original_source=list(hash=original$hash,bytes=original$size,path=brohn_object_path(store,original$hash,FALSE)),sealed_objects=lapply(Filter(function(x)!identical(x$hash,original$hash),context$metadata$objects),function(x)x[c("hash","bytes","path")]))
 bundle<-list(schema="brohn-eda-display-input-bundle/0.1",worker_request=request,request_hash=brohn_hash(job$request))
 .brohn_rpk_source_pulse(pulse)
 path<-file.path(scratch,"eda-display-input.json");brohn_require(!file.exists(path),"The EDA display bundle already exists.");brohn_eda_write_json_file(bundle,path,48*1024^2)
 .brohn_rpk_source_pulse(pulse)
 state<-handle$state;state$extra_guards<-c(state$extra_guards,list(.brohn_qexplorer_hold(path,file.info(path)$size)))
 input$eda_display<-list(schema="brohn-eda-display-prepared-input/0.1",bundle=list(file="eda-display-input.json",sha256=digest::digest(file=path,algo="sha256"),bytes=as.numeric(file.info(path)$size)))
 brohn_report_package_sources_current(store,handle);brohn_report_package_job_authorize(store,job);.brohn_rpk_source_pulse(pulse);ok<-TRUE;list(input=input,handle=handle)
}
.brohn_edd_bundle <- function(input,scratch) {
 x<-input$eda_display;brohn_fields(x,c("schema","bundle"),label="Prepared EDA input");d<-x$bundle;brohn_fields(d,c("file","sha256","bytes"),label="Sealed EDA bundle")
 brohn_require(identical(x$schema,"brohn-eda-display-prepared-input/0.1")&&identical(d$file,"eda-display-input.json")&&.brohn_rpk_hash(d$sha256)&&brohn_number(d$bytes,1,48*1024^2,TRUE),"Prepared EDA input descriptor is invalid.")
 path<-normalizePath(file.path(scratch,d$file),winslash="/",mustWork=TRUE);root<-normalizePath(scratch,winslash="/",mustWork=TRUE);link<-Sys.readlink(path)
 brohn_require(identical(dirname(path),root)&&(is.na(link)||!nzchar(link))&&file.info(path)$size==d$bytes&&identical(digest::digest(file=path,algo="sha256"),d$sha256),"Prepared EDA bundle changed or left owned scratch.")
 b<-brohn_eda_read_json_file(path,48*1024^2);brohn_fields(b,c("schema","worker_request","request_hash"),label="Complete EDA input bundle")
 brohn_require(identical(b$schema,"brohn-eda-display-input-bundle/0.1")&&.brohn_rpk_same(b$worker_request$report$ref,input$report_ref),"Prepared EDA bundle belongs to another original report.");b
}
brohn_analyse_eda_display <- function(input,scratch) {
 b<-.brohn_edd_bundle(input,scratch);request<-b$worker_request;.brohn_edd_check_code(request$implementation);.brohn_edd_validate_analysis(request$report,.brohn_edd_profile_spec(request$implementation$profile))
 request_path<-file.path(scratch,"eda-display-worker-request.json");result_path<-file.path(scratch,"eda-display-worker-result.json");directory<-file.path(scratch,"artifacts")
 brohn_require(!file.exists(request_path)&&!file.exists(result_path)&&!dir.exists(directory),"EDA child output paths must be fresh.")
 brohn_eda_write_json_file(request,request_path,48*1024^2)
 child<-processx::run(brohn_python_profile("eda"),c("scripts/workers/eda_display.py","--request",request_path,"--output",result_path,"--artifacts",directory),timeout=15*60,error_on_status=FALSE,cleanup_tree=TRUE,windows_hide_window=TRUE)
 brohn_require(file.exists(result_path),paste("EDA display returned no bounded result.",substr(child$stderr,1,500)))
 result<-brohn_eda_read_json_file(result_path,3*1024^2)
 if(child$status!=0L){
  if(identical(result$schema,"brohn-eda-report-refusal/0.1")){brohn_validate_eda_refusal(result);return(list(eda_display=result))}
  brohn_stop(paste("EDA display preparation failed:",substr(brohn_default(result$error$message,substr(child$stderr,1,500)),1,1000)))
 }
 brohn_fields(result,c("schema","artifact","source_family","source","display_request","implementation","catalog","coverage","verification"),label="EDA display worker result")
 brohn_require(identical(result$schema,"brohn-eda-display-worker-result/0.1")&&.brohn_rpk_same(result$source,request$source)&&.brohn_rpk_same(result$display_request,request$display_request)&&.brohn_rpk_same(result$implementation,request$implementation)&&identical(result$verification$request_sha256,digest::digest(file=request_path,algo="sha256"))&&identical(result$verification$analysis_value_hash,brohn_eda_value_hash(request$report$complete_analysis)),"EDA child result changed its exact source/request/value binding.")
 result$input_binding_hash<-input$content_fingerprint;list(eda_display=result)
}

.brohn_edd_catalog <- function(evidence)lapply(evidence$cells,function(cell){
 model<-cell$model;support<-cell$original_support;family<-evidence$source_family;components<-c("clean_us","tonic_us","phasic_us")
 points<-stats::setNames(lapply(components,function(k)list(points=if(is.null(model))0L else sum(vapply(model$series[[k]],function(g)length(g$points),integer(1))),groups=if(is.null(model))0L else length(model$series[[k]]))),components)
 candidates<-length(model$candidates);markers<-brohn_default(model$markers,list())
 if(family=="event"){
  unobserved<-sum(vapply(markers,function(x)identical(x$support,"unobserved"),logical(1)));outside<-sum(vapply(markers,function(x)identical(x$support,"outside_view"),logical(1)));observed<-sum(vapply(markers,function(x)identical(x$support,"saved_candidate"),logical(1)))
 }else{unobserved<-length(model$endpoint_coverage$unobserved);outside<-sum(vapply(markers,function(x)identical(x$in_view,FALSE),logical(1)));observed<-sum(vapply(markers,function(x)identical(x$in_view,TRUE),logical(1)))}
 identity<-.brohn_edd_identity(support,family)
 list(kind="eda_cell",key=cell$key,source_family=family,identity=cell$identity,label=paste(unlist(identity,use.names=FALSE),collapse=" | "),source_record_index=cell$source_record_index,
  focusable=family=="continuous"&&identical(support$status,"computed"),focus_reason=if(family=="continuous"&&identical(support$status,"computed"))NULL else if(family=="event")"fixed_event_method_window"else if(identical(support$status,"descriptive_only"))"exact_constant_signal"else brohn_default(support$reason,"no_processed_segment"),
  original_default_bounds=cell$original_default_bounds,requested_bounds=cell$requested_bounds,status=cell$status,reason=cell$reason,original_status=cell$original_status,
  descriptive_status=if(family=="event")support$status else if(identical(evidence$schema,"brohn-eda-display-evidence/0.2"))if(identical(support$status,"descriptive_only"))support$descriptive_status else support$status else NULL,
  descriptive_reason=if(family=="event")support$reason else if(identical(evidence$schema,"brohn-eda-display-evidence/0.2")&&identical(support$status,"unavailable"))support$reason else NULL,
  scr_status=if(family=="event")support$scr_status else if(identical(evidence$schema,"brohn-eda-display-evidence/0.2"))if(identical(support$status,"descriptive_only"))support$response_status else support$status else NULL,
  scr_reason=if(family=="event")support$scr_reason else if(identical(evidence$schema,"brohn-eda-display-evidence/0.2"))if(identical(support$status,"descriptive_only"))support$response_reason else support$reason else NULL,
  model_hash=cell$model_hash,components=if(is.null(model)||cell$status %in% c("no_processed_samples","raw_description_only"))list()else as.list(components),feature_count=length(cell$feature_indices),candidate_count=candidates,marker_count=observed+outside+unobserved,
  observed_marker_count=observed,unobserved_marker_count=unobserved,out_of_view_marker_count=outside,component_counts=points,
  numerical_page_counts=list(points=lapply(points,function(x)ceiling(x$points/50)),candidates=ceiling(candidates/50)),marker_page_count=if(is.null(model)||cell$status %in% c("no_processed_samples","raw_description_only"))0L else max(1L,ceiling(candidates/50)))
})
brohn_publish_eda_display <- function(store,output,scratch,job,input,output_path,pulse=NULL) {
 .brohn_rpk_source_pulse(pulse)
 store<-brohn_report_package_job_authorize(store,job,"publish");.brohn_publication_job(store,job);.brohn_edd_check_code(job$request$implementation)
 .brohn_publication_output_identity(output,job$request$implementation$sources);brohn_eda_display_input(store,job,FALSE)
 .brohn_rpk_source_pulse(pulse)
 bundle<-.brohn_edd_bundle(input,scratch);.brohn_rpk_source_pulse(pulse);brohn_require(identical(bundle$request_hash,brohn_hash(job$request))&&.brohn_rpk_same(bundle$worker_request$implementation,job$request$implementation),"EDA prepared input lost its original queued identity.")
 context<-.brohn_edd_context(store,job$request$report_ref,job$request$preparation_profile);sources<-.brohn_rpk_hold_sources(store,context$metadata,pulse);on.exit(.brohn_rpk_release(sources),add=TRUE)
 report<-Filter(function(x).brohn_rpk_same(x$ref,job$request$report_ref),.brohn_rpk_complete_sources(store,sources,TRUE,pulse)$reports)[[1L]]
 brohn_require(identical(brohn_eda_value_hash(report$complete_analysis),brohn_eda_value_hash(bundle$worker_request$report$complete_analysis)),"EDA artifact source differs from its sealed original values.")
 .brohn_rpk_source_pulse(pulse)
 output_guard<-.brohn_qexplorer_hold(output_path,file.info(output_path)$size);on.exit(.brohn_qexplorer_release(output_guard),add=TRUE)
 brohn_require(.brohn_rpk_same(brohn_eda_read_json_file(output_path),output),"EDA worker output changed before publication.")
 .brohn_rpk_source_pulse(pulse)
 result<-output$report$eda_display
 if(identical(result$schema,"brohn-eda-report-refusal/0.1")){
  brohn_validate_eda_refusal(result);return(brohn_store_batch(store,function(){brohn_report_package_sources_current(store,sources);brohn_report_package_job_fence(store,job);.brohn_cm_guard_check(list(output_guard));error<-result;error$source_preserved<-TRUE;brohn_fail_job(store,job$id,job$worker,job$token,error)}))
 }
 brohn_fields(result,c("schema","artifact","source_family","source","display_request","implementation","catalog","coverage","verification","input_binding_hash"),label="EDA worker publication")
 brohn_require(identical(result$schema,"brohn-eda-display-worker-result/0.1")&&identical(result$input_binding_hash,job$request$content_fingerprint)&&.brohn_rpk_same(result$source,.brohn_edd_source_binding(report,context))&&.brohn_rpk_same(result$display_request,job$request$display_request)&&.brohn_rpk_same(result$implementation,job$request$implementation),"EDA worker source/preparation metadata differs from its frozen request.")
 a<-result$artifact;brohn_fields(a,c("path","sha256","bytes","media_type"),label="Complete EDA display artifact")
 brohn_require(identical(a$path,"eda-display.json")&&identical(a$media_type,"application/json")&&.brohn_rpk_hash(a$sha256)&&brohn_number(a$bytes,1,24*1024^2,TRUE),"The EDA evidence artifact descriptor is invalid.")
 path<-brohn_checked_artifact_path(store,file.path(scratch,"artifacts",a$path),scratch);guard<-.brohn_qexplorer_hold(path,a$bytes);on.exit(.brohn_qexplorer_release(guard),add=TRUE)
 brohn_require(file.info(path)$size==a$bytes&&identical(digest::digest(file=path,algo="sha256"),a$sha256),"Complete EDA display failed its exact byte identity.")
 .brohn_rpk_source_pulse(pulse)
 evidence<-brohn_eda_read_json_file(path,24*1024^2);.brohn_rpk_source_pulse(pulse);brohn_validate_eda_display_evidence(evidence,report,result,pulse)
 v<-result$verification;brohn_fields(v,c("schema","request_sha256","analysis_value_hash","evidence_sha256","evidence_bytes","original_streams","source_objects","complete","scientific_processing","runtime"),label="EDA display verification")
  brohn_require(identical(v$schema,"brohn-eda-display-verification/0.1")&&identical(v$evidence_sha256,a$sha256)&&v$evidence_bytes==a$bytes&&identical(v$analysis_value_hash,brohn_eda_value_hash(report$complete_analysis))&&identical(v$complete,TRUE)&&identical(v$scientific_processing,FALSE)&&.brohn_rpk_same(v$runtime$Python,job$request$implementation$runtime$Python)&&.brohn_rpk_same(.brohn_edd_catalog(evidence),result$catalog)&&.brohn_rpk_same(evidence$coverage,result$coverage),"EDA evidence, observed runtime, catalog or complete verification disagree.")
 expected_objects<-lapply(c(list(bundle$worker_request$original_source),bundle$worker_request$sealed_objects),function(x)x[c("hash","bytes")])
 brohn_require(.brohn_rpk_same(v$source_objects,expected_objects)&&length(v$original_streams)==length(report$complete_analysis$artifacts),"EDA verification omitted or substituted a held original object/stream.")
 mapping<-report$saved_body$provenance$mapping;requested<-mapping$parameters;mapping$parameters<-NULL;mapping$origin<-report$saved_body$origin
 expected_provenance<-list(engine=report$complete_analysis$engine,operation=if(result$source_family=="event")"eda_events"else"physiology",origin=report$saved_body$origin,parameters=list(requested=requested,source_mapping=mapping,source_evidence=report$complete_analysis$source),source_sha256=report$complete_analysis$source$sha256)
 for(i in seq_along(v$original_streams)){.brohn_rpk_source_pulse(pulse);stream<-v$original_streams[[i]];original<-report$complete_analysis$artifacts[[i]]
  brohn_fields(stream,c("schema","kind","rows","tables","verified","provenance"),label="Verified original EDA stream")
  brohn_require(identical(stream$schema,original$schema)&&identical(stream$kind,original$kind)&&stream$rows==original$rows&&stream$tables==original$tables&&identical(stream$verified,TRUE)&&identical(brohn_eda_value_hash(stream$provenance),brohn_eda_value_hash(expected_provenance)),"EDA stream verification changed its original scientific provenance or complete counts.")
 }
 .brohn_rpk_source_pulse(pulse)
 staged<-document<-NULL;committed<-FALSE
 on.exit({if(!is.null(document))brohn_close_publication(document$guard,committed);if(!is.null(staged))brohn_close_publication(staged$guard,committed)},add=TRUE)
 staged<-.brohn_publication_stage(store,job,list(list(key="eda-display",kind="eda-display",path=path,sha256=a$sha256,bytes=a$bytes,media_type=a$media_type)))
 id<-paste0("eda-display-",sub("^job[_-]","",job$id))
 spec<-.brohn_edd_profile_spec(job$request$preparation_profile)
 body<-list(schema=spec$body_schema,study_id=job$request$study_id,project_id=job$request$project_id,source_family=result$source_family,source=result$source,display_request=result$display_request,
  preparation_profile=spec$profile,implementation=result$implementation,implementation_hash=brohn_hash(result$implementation),input_binding_hash=job$request$content_fingerprint,artifact=.brohn_td_object_ref(staged$descriptors[[1L]]),artifact_schema=spec$evidence_schema,catalog=result$catalog,coverage=result$coverage,
  producer=list(job_id=job$id,attempt=job$attempt,request_hash=brohn_hash(job$request),worker_result_hash=digest::digest(file=output_path,algo="sha256")))
 .brohn_edd_limit(nchar(brohn_json(body),type="bytes"),2*1024^2,"catalog_bytes",report$ref,"fewer_sources")
 .brohn_rpk_source_pulse(pulse)
 document<-.brohn_publication_stage_json(store,job,body,file.path(scratch,"published-eda-display.json"))
 receipt<-brohn_store_batch(store,function(){brohn_report_package_sources_current(store,sources);brohn_report_package_job_fence(store,job)
  brohn_require(.brohn_rpk_same(.brohn_edd_context(store,job$request$report_ref,job$request$preparation_profile)$closure,job$request$original_closure),"EDA source authority changed before commit.")
  .brohn_cm_guard_check(list(output_guard,guard));.brohn_publication_register(store,staged);body$retained_document<-.brohn_td_object_ref(.brohn_publication_register(store,document)[[1L]])
  brohn_put_entity(store,"eda_display",id,body,0L,job$request$project_id)
  brohn_complete_job(store,job$id,job$worker,job$token,list(eda_display_id=id,report_id=job$request$report_ref$id,output_hash=body$retained_document$hash))})
 committed<-TRUE;receipt
}

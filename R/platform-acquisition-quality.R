# Descriptive, bounded equipment monitoring. This is not an automatic claim of
# physiological validity, calibration accuracy or physical device qualification.
brohn_acquisition_quality_profiles <- function() {
  list(
    unclassified=list(label="Unclassified source",units=character(),roles=c("signal"),needs=c("Measurement family","Original channel units"),notes="Review the source's measurement and channel meanings."),
    gaze=list(label="Eye tracking",units=c("normalized","px","deg","mm"),roles=c("gaze_x","gaze_y","validity","pupil","signal"),needs=c("Coordinate frame and units","Eye identity","Source validity code","Calibration reference for spatial accuracy"),notes="Position and source validity are observable; calibration accuracy needs independent target-reference evidence."),
    ecg=list(label="ECG",units=c("V","mV","uV","\u00b5V"),roles=c("signal","contact","signal_quality"),needs=c("Lead and polarity","Electrode/site declaration"),notes="A voltage waveform does not establish qualified R peaks or NN intervals. Use the named ECG analysis after preservation."),
    ppg=list(label="PPG / optical pulse",units=c("a.u.","count","counts","V","mV"),roles=c("signal","contact","motion","signal_quality"),needs=c("Optical/native unit","Sensor site"),notes="Pulse intervals are PPG-derived PRV. ECG HRV and oxygen saturation are not inferred."),
    eeg=list(label="EEG",units=c("V","mV","uV","\u00b5V"),roles=c("signal","impedance","contact","signal_quality"),needs=c("Acquisition reference","Channel/site identity"),notes="Impedance appears only for explicitly mapped source impedance channels; waveform appearance is not a contact measurement."),
    eda=list(label="Electrodermal activity",units=c("uS","\u00b5S","S"),roles=c("signal","contact","signal_quality"),needs=c("Conductance calibration / unit provenance","Electrode site"),notes="Negative declared conductance is flagged descriptively. No skin-conductance response threshold is inferred."),
    fnirs=list(label="fNIRS",units=c("count","counts","a.u.","V","mV"),roles=c("intensity","signal","contact","signal_quality"),needs=c("Exact wavelengths","Source-detector pairs and geometry"),notes="Positive raw intensity alone does not establish optical density, scalp coupling or haemoglobin concentration."),
    respiration=list(label="Respiration",units=c("V","mV","a.u.","L/s","mL/s","Pa"),roles=c("signal","contact","signal_quality"),needs=c("Belt/flow method and polarity","Sensor site"),notes="Raw belt or flow movement does not establish calibrated tidal volume or absent breathing."),
    emg=list(label="EMG",units=c("V","mV","uV","\u00b5V"),roles=c("signal","contact","signal_quality"),needs=c("Muscle/site and leads","Acquisition reference"),notes="Raw voltage is shown without inferring MVC, force or startle magnitude."),
    eog=list(label="EOG",units=c("V","mV","uV","\u00b5V"),roles=c("signal","contact","signal_quality"),needs=c("Lead orientation and polarity","Electrode sites"),notes="Raw voltage does not establish gaze angle without a calibration model."),
    temperature=list(label="Temperature",units=c("degC","\u00b0C","K","degF","\u00b0F"),roles=c("signal","ambient","contact","signal_quality"),needs=c("Calibration / sensor declaration","Contact/ambient context and acclimation"),notes="A temperature trace does not establish core temperature or physiological interpretation."),
    movement=list(label="Movement / IMU",units=c("m/s^2","g","deg/s","rad/s","m/s","mm","m"),roles=c("axis_x","axis_y","axis_z","signal","signal_quality"),needs=c("Signed axes and coordinate frame","Gravity policy / sensor placement"),notes="Acceleration, angular velocity and position units retain their source meanings; displacement is not inferred."),
    audio=list(label="Audio",units=c("FS","count","counts","Pa"),roles=c("signal","signal_quality"),needs=c("Sample rate and channel meaning","Full-scale rails or pressure calibration"),notes="A bounded waveform or level observation is not calibrated sound pressure, speech recognition or emotion."),
    camera=list(label="Camera telemetry",units=character(),roles=c("frame_index","confidence","face_count","signal"),needs=c("Frame arrival source","Named model and confidence meaning"),notes="Only supplied frame/model observations are shown. This numeric LSL monitor does not invent camera images or infer a face."),
    implicit=list(label="Implicit task / event telemetry",units=character(),roles=c("trial_index","input_event","timing","signal"),needs=c("Task and trial identity","Input and timing clock meaning"),notes="Observed task telemetry does not qualify screen timing or an implicit-effect estimate."))
}
brohn_validate_acquisition_checks <- function(spec,channels) {
  checks<-brohn_default(spec$acquisition_checks,list())
  brohn_require(brohn_array(checks)&&length(checks)<=8L,"Use at most eight named acquisition checks per source.")
  if(!length(checks))return(invisible(TRUE))
  brohn_require(identical(spec$schema,"brohn-acquisition-readiness/1.1")&&!identical(spec$modality,"unclassified"),"Named acquisition checks need an explicit measurement family and readiness /1.1.")
  ids<-vapply(channels,`[[`,character(1),"id");check_ids<-character()
  for(rule in checks) {
    brohn_require(is.list(rule)&&brohn_valid_id(rule$id)&&!rule$id %in% check_ids,"Acquisition check identifiers must be unique.");check_ids<-c(check_ids,rule$id)
    for(field in c("name","version","source","rationale","unit"))brohn_require(brohn_text(rule[[field]],if(field %in% c("source","rationale"))2000 else 100),paste("Declare the acquisition check",field,"from reviewed source evidence."))
    brohn_require(rule$channel_id %in% ids&&rule$channel_id %in% unlist(spec$preview_channels),"Each acquisition check needs a selected monitoring channel.")
    channel<-channels[[match(rule$channel_id,ids)]]
    brohn_require(identical(rule$unit,channel$unit)&&!rule$unit %in% c("unknown",""),"Each acquisition check requires the exact declared original unit.")
    brohn_require(rule$kind %in% c("source_code","finite_fraction","range_fraction","cadence")&&identical(as.numeric(rule$window_s),5),"Choose a supported check using the five-second committed window.")
    brohn_require(brohn_number(rule$minimum_samples,2,2000000,TRUE)&&brohn_number(rule$minimum_span_s,.001,5)&&brohn_number(rule$maximum_age_s,.001,3600),"Declare minimum samples, minimum observed span and maximum source age for this check.")
    if(rule$kind=="source_code")brohn_require(brohn_array(rule$accepted_values)&&length(rule$accepted_values)>=1L&&length(rule$accepted_values)<=8L&&
      all(vapply(rule$accepted_values,function(v)brohn_number(v,-1e300,1e300)||(brohn_text(v,64)&&nchar(v,type="bytes")<=64L),logical(1))),"Declare up to eight exact numeric or text source codes, each at most 64 UTF-8 bytes.")
    if(rule$kind=="source_code")brohn_require(all(vapply(rule$accepted_values,function(v)if(channel$value_type %in% c("string","int64"))is.character(v) else is.numeric(v),logical(1))),"The accepted source code type must match its original channel type.")
    if(rule$kind %in% c("source_code","finite_fraction","range_fraction"))brohn_require(brohn_number(rule$minimum_fraction,0,1),"Declare the minimum matching fraction for this acquisition check.")
    if(rule$kind %in% c("range_fraction","cadence"))brohn_require(brohn_number(rule$lower,-1e300,1e300)&&brohn_number(rule$upper,-1e300,1e300)&&rule$lower<rule$upper&&
      (rule$kind!="cadence"||rule$lower>0),"Declare increasing acquisition bounds; cadence bounds must be positive Hz.")
    if(rule$kind!="source_code")brohn_require(!channel$value_type %in% c("string","int64"),"Numeric checks require a native numeric channel; native categorical codes may remain text.")
  }
  invisible(TRUE)
}
brohn_acquisition_window <- function(live,indices) {
  tryCatch({
  w<-live$window
  if(!is.list(w)||!identical(w$schema,"brohn-acquisition-window/1.0")||!identical(w$algorithm,"source-time-first-min-max-last/1.0")||
    !brohn_number(w$committed_rows,0,2000000,TRUE)||!brohn_number(w$bucket_capacity,1,128,TRUE)||!brohn_number(w$plotted_points,0,4096,TRUE)||
    !brohn_array(w$channels)||length(w$channels)!=length(indices)||
    !identical(as.integer(vapply(w$channels,`[[`,numeric(1),"index")),as.integer(indices)))return(NULL)
  if(w$committed_rows>0&&(!brohn_number(w$actual_span_s,0,5.000001)||!all(vapply(c(w$source_start_s,w$source_end_s),.brohn_acq_quality_number,logical(1)))))return(NULL)
  valid<-all(vapply(w$channels,function(c)brohn_array(c$points)&&length(c$points)<=4*w$bucket_capacity&&
    all(vapply(c$points,function(p)is.list(p)&&length(p)==5L&&brohn_number(p[[1L]],1,2000000,TRUE)&&brohn_number(p[[2L]],1,2000000,TRUE)&&
      brohn_text(p[[3L]],128)&&.brohn_acq_quality_number(p[[4L]])&&brohn_number(p[[5L]],1,4000000,TRUE),logical(1)))&&
    brohn_number(c$finite,0,2000000,TRUE)&&brohn_number(c$unavailable_numeric,0,2000000,TRUE)&&brohn_number(c$omitted_fragments,0,4000000,TRUE),logical(1)))
  if(!valid||sum(vapply(w$channels,function(c)length(c$points),integer(1)))!=w$plotted_points)return(NULL)
  w
  },error=function(e)NULL)
}
brohn_acquisition_check_results <- function(spec,channels,window,age,connection) {
  lapply(brohn_default(spec$acquisition_checks,list()),function(rule) {
    result<-list(criterion=rule,status="unknown",reason="Current matching source evidence is unavailable.",observed=NULL,samples=NULL,span_s=NULL)
    if(is.null(window)||is.null(age)||!is.finite(age)||age>rule$maximum_age_s||!identical(connection,"subscribed")) {
      result$reason<-"Source is stale, closed, unavailable or lacks its declared age evidence.";return(result)
    }
    matches<-Filter(function(c)is.list(c)&&identical(brohn_hash(c$criterion),brohn_hash(rule)),window$checks)
    if(length(matches)!=1L)return(result)
    support<-matches[[1L]];result$samples<-support$samples;result$span_s<-window$actual_span_s
    if(!brohn_number(support$samples,2,2000000,TRUE)||support$samples!=window$committed_rows||support$samples<rule$minimum_samples||window$actual_span_s<rule$minimum_span_s) {
      result$reason<-"The declared minimum sample count or observed duration is not yet supported.";return(result)
    }
    if(rule$kind=="cadence") {
      if(!.brohn_acq_quality_number(support$observed_cadence_hz)||window$boundaries>0){result$reason<-"Cadence support is interrupted by a source boundary or is unavailable.";return(result)}
      result$observed<-support$observed_cadence_hz;passed<-result$observed>=rule$lower&&result$observed<=rule$upper
    } else {
      if(!brohn_number(support$passed,0,support$samples,TRUE))return(result)
      result$observed<-support$passed/support$samples;passed<-result$observed>=rule$minimum_fraction
    }
    result$status<-if(passed)"meets_selected_check" else "unmet"
    result$reason<-if(passed)"Meets this selected acquisition check; physiological validity is not established." else "Observed source data does not meet the selected acquisition check."
    result
  })
}
brohn_validate_acquisition_readiness <- function(spec,channels) {
  brohn_require(is.list(spec)&&spec$schema %in% c("brohn-acquisition-readiness/1.0","brohn-acquisition-readiness/1.1")&&
    spec$modality %in% names(brohn_acquisition_quality_profiles()),"Choose an explicit supported equipment measurement family.")
  profile<-brohn_acquisition_quality_profiles()[[spec$modality]];ids<-vapply(channels,`[[`,character(1),"id")
  brohn_require(brohn_array(spec$channels)&&length(spec$channels)==length(ids)&&
    identical(vapply(spec$channels,`[[`,character(1),"id"),ids),"Equipment roles must cover the original channel order exactly.")
  for(channel in spec$channels) {
    brohn_require(brohn_text(channel$role,60)&&channel$role %in% profile$roles,"A channel role is unsupported for this measurement family.")
    if(!is.null(channel$rail_min)||!is.null(channel$rail_max))brohn_require(brohn_number(channel$rail_min,-1e300,1e300)&&
      brohn_number(channel$rail_max,-1e300,1e300)&&channel$rail_min<channel$rail_max,"Declare both source rails in the original unit, with minimum below maximum.")
  }
  brohn_require(brohn_array(spec$preview_channels)&&length(spec$preview_channels)>=1L&&length(spec$preview_channels)<=8L&&
    !anyDuplicated(unlist(spec$preview_channels))&&all(unlist(spec$preview_channels) %in% ids),"Select one to eight original channels for the monitoring preview.")
  brohn_validate_acquisition_checks(spec,channels)
  for(field in c("source_notes","reference","site","calibration","frame","gravity_policy","wavelengths","task_identity"))
    brohn_require(is.null(spec[[field]])||brohn_text(spec[[field]],2000,empty=TRUE),"Equipment review notes must be bounded text.")
  if(!is.null(spec$gaze)) {
    gaze<-spec$gaze;roles<-vapply(spec$channels,`[[`,character(1),"role")
    brohn_require(identical(spec$modality,"gaze")&&all(vapply(c("gaze_x","gaze_y","validity"),function(role)sum(roles==role)==1L,logical(1)))&&
      gaze$eye %in% c("left","right","binocular","combined")&&gaze$unit %in% c("normalized","px","deg","mm")&&
      brohn_text(gaze$frame,1000)&&brohn_number(gaze$valid_value,-1e100,1e100),"Gaze display needs exact X/Y/validity channels, eye, unit, frame and source valid code.")
    if(gaze$unit=="px")brohn_require(brohn_number(gaze$width,1,100000,TRUE)&&brohn_number(gaze$height,1,100000,TRUE),"Pixel gaze needs the source coordinate frame width and height.")
    brohn_require(gaze$origin %in% c("top_left","bottom_left","unspecified"),"Declare the gaze coordinate origin.")
    brohn_require(all(vapply(channels[which(roles %in% c("gaze_x","gaze_y"))],function(channel)identical(channel$unit,gaze$unit),logical(1))),
      "Gaze coordinate display units must exactly match the declared original X/Y channel units.")
  }
  invisible(spec)
}
.brohn_acq_quality_number <- function(x) is.numeric(x)&&length(x)==1L&&!is.na(x)&&is.finite(x)
.brohn_acq_quality_field <- function(x) !is.null(x)&&is.character(x)&&length(x)==1L&&nzchar(trimws(x))
brohn_acquisition_quality <- function(record,now_epoch=as.numeric(Sys.time())) {
  b<-record$body;snapshot<-record$live_snapshot
  authority<-is.list(snapshot)&&identical(snapshot$recording_id,record$id)&&
    (is.null(b$python_request_hash)||identical(snapshot$request_sha256,b$python_request_hash))
  monitor<-if(authority)snapshot$monitoring else NULL
  available<-is.list(monitor)&&monitor$schema %in% c("brohn-acquisition-monitoring/1.0","brohn-acquisition-monitoring/2.0")&&
    .brohn_acq_quality_number(monitor$updated_epoch)&&.brohn_acq_quality_number(monitor$updated_monotonic_s)&&is.list(monitor$streams)
  profiles<-brohn_acquisition_quality_profiles()
  streams<-lapply(b$request$streams,function(selected) {
    spec<-selected$readiness
    declared_checks<-if(is.list(spec)&&brohn_array(spec$acquisition_checks)&&length(spec$acquisition_checks)<=8L)spec$acquisition_checks else list()
    validated<-!is.null(spec)&&!inherits(try(brohn_validate_acquisition_readiness(spec,selected$channels),silent=TRUE),"try-error")
    if(!validated)spec<-list(modality="unclassified",channels=lapply(selected$channels,function(channel)list(id=channel$id,role="signal")),acquisition_checks=declared_checks)
    profile<-profiles[[spec$modality]];live<-if(available)monitor$streams[[selected$id]] else NULL
    current<-is.list(live)&&identical(live$id,selected$id)&&is.list(live$channels)&&length(live$channels)==length(selected$channels)
    preview<-if(current&&brohn_array(live$preview)&&length(live$preview)<=16L)live$preview else list()
    indices<-if(current)unlist(live$preview_channel_indices,use.names=FALSE) else integer()
    if(length(indices)>8L||anyDuplicated(indices)||!all(indices %in% seq_along(selected$channels))) {indices<-integer();preview<-list()}
    valid_preview<-all(vapply(preview,function(row)is.list(row)&&brohn_number(row$sequence,1,2000000,TRUE)&&
      brohn_number(row$segment,1,2000000,TRUE)&&brohn_text(row$source_timestamp,128)&&
      brohn_array(row$values)&&brohn_array(row$states)&&length(row$values)==length(indices)&&length(row$states)==length(indices)&&
      all(vapply(row$values,function(value)is.null(value)||.brohn_acq_quality_number(value)||brohn_text(value,64,empty=TRUE),logical(1)))&&
      all(vapply(row$states,function(value)brohn_text(value,40),logical(1))),logical(1)))
    if(!valid_preview){indices<-integer();preview<-list()}
    window<-if(current&&identical(monitor$schema,"brohn-acquisition-monitoring/2.0"))brohn_acquisition_window(live,indices) else NULL
    age<-NULL
    if(current&&.brohn_acq_quality_number(live$last_received_monotonic_s)) {
      elapsed<-monitor$updated_monotonic_s-live$last_received_monotonic_s
      if(elapsed>=0&&now_epoch>=monitor$updated_epoch)age<-elapsed+(now_epoch-monitor$updated_epoch)
    }
    committed_age<-NULL
    if(current&&.brohn_acq_quality_number(live$last_committed_monotonic_s)) {
      elapsed<-monitor$updated_monotonic_s-live$last_committed_monotonic_s
      if(elapsed>=0&&now_epoch>=monitor$updated_epoch)committed_age<-elapsed+(now_epoch-monitor$updated_epoch)
    }
    channel_models<-lapply(seq_along(selected$channels),function(i) {
      channel<-selected$channels[[i]];role<-spec$channels[[i]]$role;stats<-if(current)live$channels[[i]] else NULL
      supported<-is.list(stats)&&identical(as.integer(stats$index),as.integer(i))&&
        all(vapply(c("finite","nonfinite","constant_transitions"),function(key)brohn_number(stats[[key]],0,2000000,TRUE),logical(1)))
      position<-match(i,indices)
      values<-if(!is.na(position))lapply(preview,function(row)if(.brohn_acq_quality_number(row$values[[position]]))row$values[[position]] else NULL) else list()
      latest_source<-if(!is.na(position)&&length(preview))tail(preview,1L)[[1L]]$values[[position]] else NULL
      warnings<-character()
      if(supported&&stats$nonfinite>0)warnings<-c(warnings,paste(stats$nonfinite,"committed nonfinite values"))
      if(supported&&stats$constant_transitions>0)warnings<-c(warnings,paste(stats$constant_transitions,"identical adjacent values (descriptive; no flatline threshold)"))
      unit<-brohn_default(channel$unit,"unknown")
      if(identical(unit,"unknown")||!nzchar(unit))warnings<-c(warnings,"Original unit is unknown")
      if(length(profile$units)&&role %in% c("signal","intensity","axis_x","axis_y","axis_z")&&!unit %in% profile$units)
        warnings<-c(warnings,"Original unit needs measurement-specific review; it is not converted by this monitor")
      if(supported&&identical(spec$modality,"eda")&&unit %in% c("uS","\u00b5S","S")&&.brohn_acq_quality_number(stats$minimum)&&stats$minimum<0)
        warnings<-c(warnings,"Negative source conductance observed")
      if(supported&&identical(spec$modality,"fnirs")&&identical(role,"intensity")&&.brohn_acq_quality_number(stats$minimum)&&stats$minimum<=0)
        warnings<-c(warnings,"Nonpositive optical intensity observed")
      declared<-spec$channels[[i]]
      if(supported&&!is.null(declared$rail_min)&&.brohn_acq_quality_number(stats$minimum)&&.brohn_acq_quality_number(stats$maximum)&&
        (stats$minimum<=declared$rail_min||stats$maximum>=declared$rail_max))warnings<-c(warnings,"Observed values reach or exceed a declared source rail")
      list(id=channel$id,label=channel$label,type=channel$type,unit=unit,role=role,stats=if(supported)stats else NULL,
        preview=values,window=if(!is.null(window)&&!is.na(position))window$channels[[position]] else NULL,
        window_support=if(!is.null(window))window[c("source_start_s","source_end_s","actual_span_s","committed_rows","bucket_width_s","algorithm")] else NULL,
        latest_source=latest_source,value_type=channel$value_type,warnings=as.list(warnings),source_auxiliary=role %in% c("impedance","contact","motion","signal_quality","confidence","face_count","frame_index","trial_index","input_event","timing"))
    })
    gaze<-NULL
    if(validated&&!is.null(spec$gaze)&&length(preview)) {
      roles<-vapply(spec$channels,`[[`,character(1),"role");positions<-match(match(c("gaze_x","gaze_y","validity"),roles),indices)
      if(!anyNA(positions)) {
        points<-lapply(preview,function(row){v<-row$values[positions];valid<-all(vapply(v,.brohn_acq_quality_number,logical(1)))&&identical(as.numeric(v[[3L]]),as.numeric(spec$gaze$valid_value))
          list(sequence=row$sequence,x=if(valid)v[[1L]] else NULL,y=if(valid)v[[2L]] else NULL,source_valid=valid)})
        gaze<-c(spec$gaze,list(points=points,valid_samples=sum(vapply(points,`[[`,logical(1),"source_valid")),window_samples=length(points),calibration_qualified=FALSE))
      }
    }
    observed_rate<-NULL
    if(length(preview)>=2L) {
      stamps<-suppressWarnings(vapply(preview,function(row)as.numeric(brohn_default(row$source_timestamp,NA_real_)),numeric(1)))
      segments<-vapply(preview,function(row)as.integer(brohn_default(row$segment,0L)),integer(1))
      delta<-diff(stamps);eligible<-is.finite(delta)&delta>0&diff(segments)==0L
      if(any(eligible))observed_rate<-list(hz=1/stats::median(delta[eligible]),intervals=sum(eligible),method="inverse_median_positive_interval_within_source_segment",scope="bounded monitoring window")
    }
    derived<-list()
    if(validated&&length(preview)&&spec$modality=="movement"&&.brohn_acq_quality_field(spec$frame)&&.brohn_acq_quality_field(spec$gravity_policy)) {
      roles<-vapply(spec$channels,`[[`,character(1),"role");axes<-match(c("axis_x","axis_y","axis_z"),roles);positions<-match(axes,indices)
      if(!anyNA(positions)&&length(unique(vapply(selected$channels[axes],`[[`,character(1),"unit")))==1L) {
        magnitudes<-lapply(preview,function(row){v<-row$values[positions];if(!all(vapply(v,.brohn_acq_quality_number,logical(1))))return(NULL)
          values<-unlist(v);scale<-max(abs(values));value<-if(scale==0)0 else scale*sqrt(sum((values/scale)^2));if(is.finite(value))value else NULL})
        derived$vector_magnitude<-list(values=magnitudes,unit=selected$channels[[axes[[1L]]]]$unit,
          method="Euclidean norm of explicitly mapped same-unit XYZ source values",frame=spec$frame,gravity_policy=spec$gravity_policy)
      }
    }
    if(validated&&spec$modality=="audio")derived$window_rms<-lapply(Filter(function(channel)length(channel$preview)>0,channel_models),function(channel){
      values<-unlist(Filter(.brohn_acq_quality_number,channel$preview));scale<-if(length(values))max(abs(values)) else NA_real_
      value<-if(!length(values))NULL else if(scale==0)0 else scale*sqrt(mean((values/scale)^2))
      list(channel_id=channel$id,value=value,unit=channel$unit,finite_samples=length(values),window_rows=length(preview),
        method="Root mean square of finite values in bounded raw monitoring window; no filter or pressure calibration")})
    notes<-as.list(unique(unlist(lapply(channel_models,`[[`,"warnings"),use.names=FALSE)))
    missing<-character()
    if(!validated)missing<-c(missing,"Explicit measurement and channel-role review")
    if(spec$modality %in% c("eeg","emg","eog","ecg")&&!.brohn_acq_quality_field(spec$reference))missing<-c(missing,"Lead / acquisition reference declaration")
    if(spec$modality %in% c("eda","ppg","ecg","eeg","emg","eog","respiration","temperature")&&!.brohn_acq_quality_field(spec$site))missing<-c(missing,"Sensor / electrode site declaration")
    if(spec$modality %in% c("eda","temperature")&&!.brohn_acq_quality_field(spec$calibration))missing<-c(missing,"Calibration / original-unit provenance")
    if(spec$modality=="fnirs"&&!.brohn_acq_quality_field(spec$wavelengths))missing<-c(missing,"Exact wavelengths and source-detector metadata")
    if(spec$modality=="movement"&&(!.brohn_acq_quality_field(spec$frame)||!.brohn_acq_quality_field(spec$gravity_policy)))missing<-c(missing,"Coordinate frame and gravity policy")
    if(spec$modality=="gaze"&&is.null(gaze))missing<-c(missing,"Explicit gaze mapping and observed X/Y/validity channels in preview")
    list(id=selected$id,modality=spec$modality,label=profile$label,monitoring_available=current,
      connection=if(current)brohn_default(live$connection,"unknown") else "unknown",received=if(current)live$received_samples else NULL,
      committed=if(current)live$committed_samples else NULL,last_sample_age_seconds=age,preview_rows=length(preview),channels=channel_models,
      preview=preview,window=window,last_committed_age_seconds=committed_age,
      checks=brohn_acquisition_check_results(spec,selected$channels,if(validated)window else NULL,committed_age,if(current)live$connection else "unknown"),
      observed_rate=observed_rate,gaze=gaze,derived=derived,quality_status=if(length(notes))"review_observations" else "unknown",
      quality_qualified=FALSE,observations=notes,missing_evidence=as.list(missing),required_evidence=as.list(profile$needs),notes=profile$notes,
      gaps=if(current)live$gaps else NULL,resets=if(current)live$resets else NULL)
  })
  list(schema="brohn-acquisition-quality-view/1.0",acquisition_id=record$id,origin=b$origin,status=b$status,
    monitoring_available=available,streams=streams,quality_qualified=FALSE,
    scope="Bounded monitoring copy of committed samples; complete original samples remain in the recording archive.",
    age_clock="Recorder monotonic sample age plus local wall-clock elapsed since the snapshot; hardware transport delay and cross-device synchronization are not measured.")
}

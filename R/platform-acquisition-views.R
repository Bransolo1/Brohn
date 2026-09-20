# Researcher-reviewed local acquisition; no device is started by rendering UI.
brohn_acquisition_quality_text <- function(inspection) {
  if(identical(inspection$quality_evidence,"verified_final_manifest") &&
     identical(inspection$quality_qualified,FALSE) && identical(inspection$signal_quality,"not_qualified"))
    "Signal quality: not qualified. Review the recorded signals before research analysis."
  else "Signal quality: not evaluated here. Final quality evidence is unavailable; review the preserved source before research analysis."
}
brohn_acquisition_preview_svg <- function(channel,rows) {
  if(!is.null(channel$window))return(brohn_acquisition_window_svg(channel))
  values<-vapply(channel$preview,function(x)if(.brohn_acq_quality_number(x))x else NA_real_,numeric(1))
  if(length(values)<2L||!any(is.finite(values)))return(shiny::p(class="brohn-muted","No bounded numeric waveform is available for this channel."))
  lower<-min(values,na.rm=TRUE);upper<-max(values,na.rm=TRUE)
  scale<-max(abs(values),na.rm=TRUE);if(scale==0)scale<-1
  span<-upper/scale-lower/scale;if(span==0)span<-1
  x<-seq(10,350,length.out=length(values));y<-70-(values/scale-lower/scale)/span*52
  segments<-vapply(rows,function(row)as.integer(brohn_default(row$segment,0L)),integer(1))
  path<-character();previous<-FALSE
  for(i in seq_along(values)) {
    if(!is.finite(values[[i]])){previous<-FALSE;next}
    command<-if(previous&&segments[[i]]==segments[[i-1L]])"L" else "M"
    path<-c(path,sprintf("%s %.2f %.2f",command,x[[i]],y[[i]]));previous<-TRUE
  }
  label<-paste(channel$label,"bounded waveform in",channel$unit,"by received sequence; gaps at unavailable values or source segment changes")
  shiny::tagList(shiny::HTML(paste0('<svg viewBox="0 0 360 88" width="100%" height="108" role="img" aria-label="',
    htmltools::htmlEscape(label,attribute=TRUE),'"><rect x="0" y="0" width="360" height="88" fill="#f2f5f7" rx="8"/>',
    '<path d="',paste(path,collapse=" "),'" fill="none" stroke="#216b8a" stroke-width="2"/></svg>')),
    shiny::p(class="brohn-muted",paste("Window range",format(lower,digits=6),"to",format(upper,digits=6),channel$unit,". Sequence axis; local scale, not a calibration assessment.")))
}
brohn_acquisition_window_svg <- function(channel) {
  w<-channel$window;support<-channel$window_support;points<-w$points
  if(!length(points))return(shiny::p(class="brohn-muted","No finite numeric values in this committed time window; original categorical codes remain available above."))
  values<-vapply(points,function(p)p[[4L]],numeric(1));time<-vapply(points,function(p)as.numeric(p[[3L]]),numeric(1))
  scale<-max(abs(values));if(scale==0)scale<-1
  low<-min(values/scale);span<-max(values/scale)-low;if(span==0)span<-1
  duration<-support$actual_span_s;x<-if(duration==0)rep(10,length(time)) else 10+340*(time-support$source_start_s)/duration
  y<-70-52*(values/scale-low)/span;path<-character()
  for(i in seq_along(points))path<-c(path,sprintf("%s %.2f %.2f",if(i>1L&&points[[i]][[2L]]==points[[i-1L]][[2L]]&&points[[i]][[5L]]==points[[i-1L]][[5L]])"L" else "M",x[[i]],y[[i]]))
  isolated<-vapply(seq_along(points),function(i)(i==1L||points[[i]][[5L]]!=points[[i-1L]][[5L]])&&
    (i==length(points)||points[[i]][[5L]]!=points[[i+1L]][[5L]]),logical(1))
  dots<-paste(vapply(which(isolated),function(i)sprintf('<circle cx="%.2f" cy="%.2f" r="2" fill="#216b8a"/>',x[[i]],y[[i]]),character(1)),collapse="")
  label<-paste(channel$label,"committed source-time waveform in",channel$unit,"over",format(duration,digits=4),"seconds; first minimum maximum last observed points; gaps remain disconnected")
  shiny::tagList(shiny::HTML(paste0('<svg viewBox="0 0 360 100" width="100%" height="124" role="img" aria-label="',htmltools::htmlEscape(label,attribute=TRUE),
    '"><rect width="360" height="100" fill="#f2f5f7" rx="8"/><path d="',paste(path,collapse=" "),'" fill="none" stroke="#216b8a" stroke-width="1.5"/>',dots,
    '<text x="10" y="94" fill="#263844" font-size="11">0 s</text><text x="350" y="94" text-anchor="end" fill="#263844" font-size="11">',format(duration,digits=4),' s</text></svg>')),
    shiny::p(class="brohn-muted",paste(support$committed_rows,"committed samples;",w$finite,"finite numeric values;",length(points),"actual points plotted.",
      "Range",format(min(values),digits=6),"to",format(max(values),digits=6),channel$unit,". Local scale; source timestamps retained.")),
    if(w$omitted_fragments>0)shiny::p(class="brohn-alert brohn-alert-warning",paste(w$omitted_fragments,"fragment portions could not be represented within the preview point budget. No connections are drawn across their boundaries; inspect the complete recording.")))
}
brohn_acquisition_checks_ui <- function(i,channels,count,values=list(),source_type="float64") {
  lapply(seq_len(count),function(j) {
    prefix<-paste0("acq_check_",i,"_",j,"_");id<-function(field)paste0(prefix,field)
    prior<-function(field,default)brohn_default(values[[id(field)]],default)
    shiny::tags$details(open=TRUE,shiny::tags$summary(paste("Acquisition check",j)),
      shiny::textInput(id("name"),"Check name from your acquisition protocol",prior("name","")),
      shiny::textInput(id("version"),"Protocol / criterion version",prior("version","")),
      shiny::selectInput(id("channel"),"Original channel",stats::setNames(seq_along(channels),vapply(seq_along(channels),function(k)brohn_default(channels[[k]]$label,paste("Channel",k)),character(1))),selected=prior("channel",1)),
      shiny::selectInput(id("kind"),"Source observation to check",c("Choose a check"="","Exact native validity / contact code"="source_code","Finite numeric fraction"="finite_fraction","Fraction within declared source range"="range_fraction","Observed source cadence (Hz)"="cadence"),selected=prior("kind","")),
      shiny::conditionalPanel(sprintf("input['%s'] === 'source_code'",id("kind")),
        shiny::selectInput(id("code_type"),"Native source code type (declared by the source)",if(source_type %in% c("string","int64"))c("Text code"="text") else c("Numeric code"="numeric")),
        shiny::textAreaInput(id("codes"),"Accepted exact source codes, one per line",prior("codes",""),rows=2)),
      shiny::conditionalPanel(sprintf("['source_code','finite_fraction','range_fraction'].includes(input['%s'])",id("kind")),
        shiny::numericInput(id("fraction"),"Minimum matching fraction (0 to 1), from reviewed evidence",prior("fraction",NA_real_),min=0,max=1)),
      shiny::conditionalPanel(sprintf("['range_fraction','cadence'].includes(input['%s'])",id("kind")),
        shiny::numericInput(id("lower"),"Inclusive lower bound (original unit; Hz for cadence)",prior("lower",NA_real_)),
        shiny::numericInput(id("upper"),"Inclusive upper bound (original unit; Hz for cadence)",prior("upper",NA_real_))),
      shiny::p("Checks use the complete committed support in the displayed window of at most five seconds. Waveform decimation never supplies check counts."),
      shiny::numericInput(id("minimum_samples"),"Minimum committed samples for this check",prior("minimum_samples",NA_real_),min=2,max=2000000),
      shiny::numericInput(id("minimum_span_s"),"Minimum observed source span (seconds, at most 5)",prior("minimum_span_s",NA_real_),min=.001,max=5),
      shiny::numericInput(id("maximum_age_s"),"Maximum age of committed data (seconds)",prior("maximum_age_s",NA_real_),min=.001,max=3600),
      shiny::textAreaInput(id("source"),"Source manual, protocol section or criterion evidence",prior("source",""),rows=2),
      shiny::textAreaInput(id("rationale"),"Why these settings apply to this measurement and setup",prior("rationale",""),rows=2),
      shiny::checkboxInput(id("reviewed"),"I reviewed this exact acquisition criterion; passing it does not establish physiological validity",prior("reviewed",FALSE)))
  })
}
brohn_acquisition_checks_input <- function(input,i,channels,require_review=TRUE,only=NULL) {
  count<-brohn_default(input[[paste0("acq_checks_count_",i)]],0)
  brohn_require(brohn_number(count,0,8,TRUE),"Choose zero to eight acquisition checks.")
  lapply(if(is.null(only))seq_len(count) else intersect(seq_len(count),only),function(j) {
    prefix<-paste0("acq_check_",i,"_",j,"_");value<-function(field)input[[paste0(prefix,field)]]
    position<-suppressWarnings(as.integer(value("channel")))
    brohn_require(length(position)==1L&&!is.na(position)&&position %in% seq_along(channels),"Choose each acquisition check's original channel.")
    if(require_review)brohn_require(isTRUE(value("reviewed")),"Review each named acquisition criterion before starting collection.")
    rule<-list(id=paste0("check-",j),name=value("name"),version=value("version"),channel_id=channels[[position]]$id,unit=channels[[position]]$unit,
      kind=brohn_default(value("kind"),""),window_s=5,minimum_samples=value("minimum_samples"),minimum_span_s=value("minimum_span_s"),maximum_age_s=value("maximum_age_s"),source=value("source"),rationale=value("rationale"))
    if(rule$kind=="source_code") {
      codes<-strsplit(brohn_default(value("codes"),""),"\n",fixed=TRUE)[[1L]];codes<-codes[nzchar(codes)]
      if(!channels[[position]]$value_type %in% c("string","int64")){codes<-suppressWarnings(as.numeric(codes));brohn_require(length(codes)>0L&&all(is.finite(codes)),"Numeric source codes must be finite numbers.")}
      rule$accepted_values<-as.list(codes)
    }
    if(rule$kind %in% c("source_code","finite_fraction","range_fraction"))rule$minimum_fraction<-value("fraction")
    if(rule$kind %in% c("range_fraction","cadence")){rule$lower<-value("lower");rule$upper<-value("upper")}
    rule
  })
}
brohn_acquisition_gaze_svg <- function(gaze) {
  if(is.null(gaze)||!length(gaze$points))return(NULL)
  point<-tail(gaze$points,1L)[[1L]]
  description<-paste(gaze$eye,"eye/source;",gaze$valid_samples,"of",gaze$window_samples,"preview samples match the declared valid code.")
  if(!isTRUE(point$source_valid))return(shiny::p(class="brohn-alert brohn-alert-warning",description," Latest gaze position is invalid or unavailable according to the mapped source code."))
  if(!gaze$unit %in% c("normalized","px")||identical(gaze$origin,"unspecified"))return(shiny::p(description,
    paste("Latest original position:",point$x,",",point$y,gaze$unit,"in",gaze$frame,". A screen-position display requires an explicit origin and normalized or pixel coordinates.")))
  width<-if(gaze$unit=="normalized")1 else gaze$width;height<-if(gaze$unit=="normalized")1 else gaze$height
  if(point$x<0||point$x>width||point$y<0||point$y>height)return(shiny::p(class="brohn-alert brohn-alert-warning",description," Latest source-valid gaze lies outside the declared coordinate frame."))
  y<-if(gaze$origin=="bottom_left")height-point$y else point$y
  label<-paste("Observed",gaze$eye,"gaze position",point$x,point$y,gaze$unit,"in",gaze$frame,". Spatial calibration accuracy is not established.")
  shiny::tagList(shiny::HTML(sprintf('<svg viewBox="0 0 %g %g" width="100%%" height="180" role="img" aria-label="%s"><rect width="%g" height="%g" fill="#eef3f5"/><circle cx="%g" cy="%g" r="%g" fill="#216b8a"/></svg>',
    width,height,htmltools::htmlEscape(label,attribute=TRUE),width,height,point$x,y,min(width,height)*.025)),
    shiny::p(description),shiny::p(class="brohn-muted",paste("Observed position in",gaze$frame,";",gaze$unit,"coordinates. Spatial calibration accuracy is not established.")))
}
brohn_acquisition_quality_ui <- function(model) {
  shiny::tags$section(`aria-label`=paste("Equipment and recording checks",model$acquisition_id),shiny::h4("Equipment and recording checks"),
    if(!isTRUE(model$monitoring_available))shiny::p(class="brohn-alert brohn-alert-warning","Live monitoring is unavailable for this recording. Missing telemetry does not mean the source or signal is healthy."),
    lapply(model$streams,function(stream)shiny::tags$details(open=TRUE,
      shiny::tags$summary(paste(stream$label,"-",stream$id)),
      shiny::div(class="brohn-toolbar",brohn_badge(paste("Subscription:",stream$connection),"neutral"),
        brohn_badge(if(is.null(stream$received))"Sample receipt: unknown" else paste("Received:",stream$received),"neutral"),
        brohn_badge(if(is.null(stream$committed))"Recording writes: unknown" else paste("Committed:",stream$committed),"neutral"),
        brohn_badge("Measurement quality: not qualified","warning")),
      if(!is.null(stream$last_sample_age_seconds))shiny::p(paste("Last sample reported",format(stream$last_sample_age_seconds,digits=3),"seconds ago.")),
      if(!is.null(stream$observed_rate))shiny::p(paste("Observed source cadence:",format(stream$observed_rate$hz,digits=6),"Hz across",stream$observed_rate$intervals,"positive intervals in this monitoring window.")),
      if(!is.null(stream$gaps))shiny::p(paste("Declared-threshold gaps:",stream$gaps,". Source resets/reversals:",stream$resets,".")),
      if(!is.null(stream$window))shiny::tagList(shiny::p(paste("Latest committed waveform window:",format(stream$window$actual_span_s,digits=4),"seconds, up to the requested 5 seconds. Source gaps remain disconnected.")),
        shiny::tags$details(shiny::tags$summary("Preview fidelity and source timing"),shiny::p(paste(
          "Bucket width",format(stream$window$bucket_width_s,digits=4),"s;",stream$window$plotted_points,"points across selected channels.",
          "First/minimum/maximum/last preserves observed extremes; only the current source-clock segment is shown.",stream$window$coverage_policy)))),
      if(length(stream$checks))lapply(stream$checks,function(check)shiny::tags$details(open=TRUE,
        shiny::tags$summary(paste(check$criterion$name,"-",switch(check$status,meets_selected_check="Meets selected acquisition check",unmet="Selected acquisition check unmet","Acquisition check unknown"))),
        shiny::p(check$reason),shiny::p(paste("Observed",brohn_default(check$observed,"unavailable"),if(check$criterion$kind=="cadence")"Hz" else "matching fraction",
          "from",brohn_default(check$samples,"unavailable"),"committed samples over",brohn_default(check$span_s,"unavailable"),"s.")),
        shiny::tags$details(shiny::tags$summary("Exact saved criterion"),
          brohn_table(list(check$criterion),label=paste("Exact selected acquisition criterion",model$acquisition_id,stream$id,check$criterion$id,check$criterion$name))))),
      if(!length(stream$checks))shiny::p(class="brohn-muted","No named acquisition checks were selected. Physiological signal quality remains unqualified."),
      if(length(stream$missing_evidence))shiny::p(class="brohn-alert brohn-alert-warning",paste("Still requires:",paste(unlist(stream$missing_evidence),collapse="; "))),
      brohn_acquisition_gaze_svg(stream$gaze),
      if(!is.null(stream$derived$vector_magnitude))shiny::p(paste("Latest source XYZ magnitude:",
        brohn_default(tail(stream$derived$vector_magnitude$values,1L)[[1L]],"unavailable"),stream$derived$vector_magnitude$unit,
        ".",stream$derived$vector_magnitude$method,"; gravity policy:",stream$derived$vector_magnitude$gravity_policy)),
      if(length(stream$derived$window_rms))lapply(stream$derived$window_rms,function(value)shiny::p(paste("Monitoring RMS:",
        value$channel_id,brohn_default(value$value,"unavailable"),value$unit,"over",value$finite_samples,"finite values in",value$window_rows,"preview rows.",value$method))),
      lapply(Filter(function(channel)length(channel$preview)>0,stream$channels),function(channel)shiny::div(
        shiny::h5(paste(channel$label,"-",channel$role,"-",channel$unit)),
        if(!is.null(channel$latest_source))shiny::p(paste("Latest source observation:",channel$latest_source,channel$unit,
          if(channel$value_type=="string")"(monitoring text is limited to 64 UTF-8 bytes; the full original is recorded)" else "")),
        brohn_acquisition_preview_svg(channel,stream$preview),
        if(length(channel$warnings))shiny::p(class="brohn-alert brohn-alert-warning",paste(unlist(channel$warnings),collapse="; ")))),
      shiny::tags$details(shiny::tags$summary("Every original channel and source-provided observations"),brohn_table(lapply(stream$channels,function(channel)list(
        channel=channel$label,role=channel$role,unit=channel$unit,latest_source=channel$latest_source,finite_numeric=channel$stats$finite,nonfinite=channel$stats$nonfinite,
        minimum=channel$stats$minimum,maximum=channel$stats$maximum,notes=paste(unlist(channel$warnings),collapse="; "))),maximum=128L,label=paste(stream$label,"channel observations",model$acquisition_id,stream$id))),
      shiny::p(class="brohn-muted",stream$notes))),
    shiny::p(class="brohn-muted",model$scope),shiny::tags$details(shiny::tags$summary("Monitoring clocks"),shiny::p(model$age_clock)))
}
brohn_acquisition_ui <- function(store, study) {
  brohn_card(title="Record local research streams", subtitle="Choose the sources, confirm their units and participant identity, then record into this study's history.",
    shiny::p(class="brohn-muted","This local profile supports one recording at a time. An LSL source application must already be running. Device calibration and physical timing still require their own evidence."),
    shiny::uiOutput("acquisition_manager_status"),
    shiny::textInput("acq_lsl_session","LSL session (must match the source application)","default"),
    shiny::textAreaInput("acq_source_ids","Exact source IDs, one per line (optional)","",rows=3),
    shiny::checkboxInput("acq_discovery_confirm","Discover metadata from local sources in this session",FALSE),
    shiny::actionButton("acq_discover","Find local sources",class="btn-primary"),
    shiny::uiOutput("acquisition_discovery_review"),shiny::uiOutput("acquisition_selection_review"),
    shiny::uiOutput("acquisition_recordings"))
}

brohn_acquisition_form_current <- function(state, input) {
  identical(state$page,"study") && identical(state$stage,"Collect") &&
    brohn_valid_id(state$study_id) &&
    identical(input$study_form_identity,paste(state$study_id,"Collect",sep=":"))
}
brohn_install_acquisition_server <- function(input,output,session,store,state,attempt,refresh,message,prepare_download) {
  reviewed_checks<-shiny::reactiveValues()
  current_study <- shiny::reactive({
    state$refresh; shiny::req(brohn_acquisition_form_current(state,input))
    brohn_study(store,state$study_id)
  })
  pulse <- shiny::reactive({shiny::invalidateLater(1000,session); Sys.time()})
  discoveries <- shiny::reactiveVal(list())
  shiny::observe({
    pulse(); s<-current_study(); current<-brohn_lsl_discoveries(store,s$id)
    # Keep reviewed inputs mounted while status polling continues elsewhere.
    if(!identical(current,shiny::isolate(discoveries()))) discoveries(current)
  })
  latest <- shiny::reactive({
    found <- Filter(function(d) identical(d$body$status,"ready"),discoveries())
    if(length(found)) found[[1L]] else NULL
  })
  chosen <- shiny::reactive({
    d <- latest(); shiny::req(!is.null(d))
    ids <- brohn_default(input$acq_selected_uids,character())
    Filter(function(s) s$uid %in% ids,d$body$result$streams)
  })
  output$acquisition_manager_status <- shiny::renderUI({
    pulse()
    if(brohn_acquisition_ready(store$root)) brohn_badge("Local recorder service available","neutral") else
      shiny::p(class="brohn-alert brohn-alert-warning","The local acquisition manager is unavailable. Start Brohn with its integrated launcher before recording; queued requests remain saved.")
  })
  shiny::observeEvent(input$acq_discover,attempt(function() {
    s<-current_study()
    sources<-trimws(strsplit(brohn_default(input$acq_source_ids,""),"\n",fixed=TRUE)[[1L]]);sources<-sources[nzchar(sources)]
    brohn_queue_lsl_discovery(store,s$id,input$acq_lsl_session,sources,isTRUE(input$acq_discovery_confirm))
    message("Local source metadata discovery queued. Recording starts only after your review.")
  }))
  output$acquisition_discovery_review <- shiny::renderUI({
    all<-discoveries(); d<-latest()
    shiny::tagList(
      if(length(all)) shiny::p(paste("Latest discovery:",all[[1L]]$body$status)),
      if(length(all) && !is.null(all[[1L]]$body$error)) shiny::p(class="brohn-alert brohn-alert-warning",all[[1L]]$body$error),
      if(length(all) && all[[1L]]$body$status %in% c("interrupted","failed"))
        brohn_command("Retry these sources","acq_retry_discovery",list(id=all[[1L]]$id,revision=all[[1L]]$revision,request_hash=all[[1L]]$body$request_hash)),
      if(!is.null(d)) {
        streams<-d$body$result$streams
        supported<-Filter(function(s) isTRUE(s$supported),streams)
        choices<-stats::setNames(vapply(supported,`[[`,character(1),"uid"),vapply(supported,function(s)
          paste(s$name,"-",s$type,"-",s$channel_count,"channels"),character(1)))
        shiny::tagList(
          if(!length(streams)) shiny::p("No matching local source was found. Check the source application's LSL session and source ID."),
          shiny::selectInput("acq_selected_uids","Sources to record",choices,selected=character(),multiple=TRUE),
          shiny::tags$details(shiny::tags$summary("Source metadata and transport support"),brohn_table(lapply(streams,function(s)
            list(name=s$name,type=s$type,uid=s$uid,source_id=s$source_id,channels=s$channel_count,format=s$value_type,
              nominal_hz=s$nominal_srate,source_origin=s$source_origin,supported=s$supported,reason=s$support_reason)),maximum=64L,label="Local LSL sources")))
      })
  })
  shiny::observeEvent(input$acq_retry_discovery,attempt(function() {
    s<-current_study();command<-input$acq_retry_discovery;prior<-brohn_get_entity(store,"acquisition_discovery",command$id)
    brohn_require(!is.null(prior) && identical(prior$body$study_id,s$id) && identical(prior$body$request_hash,command$request_hash),
      "This retry control belongs to a different study or discovery request.")
    brohn_retry_lsl_discovery(store,prior$id,command$revision)
    message("A new discovery of the same reviewed source scope is queued. The interrupted request remains in history.")
  }))
  # The selected form depends on discovery identity and selection, not on the
  # one-second status pulse; editing units must not reset their inputs.
  stable_discovery <- shiny::reactive({d<-latest(); if(is.null(d)) NULL else list(id=d$id,hash=d$body$result_hash)})
  output$acquisition_selection_review <- shiny::renderUI({
    key<-stable_discovery(); shiny::req(!is.null(key)); selected<-chosen(); if(!length(selected)) return(NULL)
    study<-current_study()
    shiny::tagList(
      shiny::div(style="display:none",shiny::textInput("acq_form_identity",NULL,paste(study$id,study$revision,key$id,key$hash,sep=":"))),
      lapply(seq_along(selected),function(i) {s<-selected[[i]]
        shiny::tags$fieldset(class="brohn-stack",style="min-width:0;max-width:100%;grid-template-columns:minmax(0,1fr)",shiny::tags$legend(s$name),
          shiny::p(paste("Source declares",brohn_default(s$source_origin,"no collection origin"),"and",s$value_type,"samples.")),
          shiny::selectInput(paste0("acq_kind_",i),"Stream role",c("Signal"="signal","Event markers"="markers","Unclassified"="unclassified"),selected=if(s$value_type=="string") "markers" else "signal"),
          shiny::textInput(paste0("acq_clock_",i),"Source clock identity",paste0("lsl-",s$uid)),
          shiny::selectInput(paste0("acq_clock_kind_",i),"Source timestamp clock",c("Epoch not established"="unspecified_epoch","Monotonic clock"="monotonic","Device clock"="device","Unix clock"="unix")),
          shiny::selectInput(paste0("acq_measurement_",i),"Equipment measurement family",stats::setNames(names(brohn_acquisition_quality_profiles()),
            vapply(brohn_acquisition_quality_profiles(),`[[`,character(1),"label")),selected="unclassified"),
          lapply(seq_along(s$channels),function(j) {channel<-s$channels[[j]]
            shiny::tags$details(open=TRUE,shiny::tags$summary(brohn_default(channel$label,paste("Channel",j))),
              shiny::textInput(paste0("acq_unit_",i,"_",j),"Original unit",brohn_default(channel$unit,if(s$value_type=="string") "marker" else "unknown")),
              shiny::selectInput(paste0("acq_role_",i,"_",j),"Explicit source channel role",unique(unlist(lapply(brohn_acquisition_quality_profiles(),`[[`,"roles"))),selected="signal"),
              shiny::numericInput(paste0("acq_rail_min_",i,"_",j),"Source-declared minimum rail (optional)",NA_real_),
              shiny::numericInput(paste0("acq_rail_max_",i,"_",j),"Source-declared maximum rail (optional)",NA_real_))}),
          shiny::selectInput(paste0("acq_preview_",i),"Monitoring channels (one to eight; all channels are recorded)",
            stats::setNames(seq_along(s$channels),vapply(seq_along(s$channels),function(j)brohn_default(s$channels[[j]]$label,paste("Channel",j)),character(1))),
            selected=head(seq_along(s$channels),8L),multiple=TRUE),
          shiny::tags$details(shiny::tags$summary("Measurement-specific source declarations"),
            shiny::textInput(paste0("acq_reference_",i),"Lead, polarity or acquisition reference",""),
            shiny::textInput(paste0("acq_site_",i),"Electrode / sensor site and contact context",""),
            shiny::textInput(paste0("acq_calibration_",i),"Unit calibration, ambient / acclimation evidence",""),
            shiny::textInput(paste0("acq_frame_",i),"Coordinate frame / axes",""),
            shiny::textInput(paste0("acq_gravity_",i),"Movement gravity policy",""),
            shiny::textInput(paste0("acq_wavelengths_",i),"fNIRS wavelengths and source-detector pairs",""),
            shiny::textInput(paste0("acq_task_identity_",i),"Task, trial and input/timing meaning","")),
          shiny::tags$details(shiny::tags$summary("Eye tracking position and source validity mapping"),
            shiny::checkboxInput(paste0("acq_gaze_enabled_",i),"Map explicit gaze X, Y and validity channels above",FALSE),
            shiny::selectInput(paste0("acq_gaze_eye_",i),"Source eye identity",c("left","right","binocular","combined")),
            shiny::selectInput(paste0("acq_gaze_unit_",i),"Original gaze coordinate unit",c("normalized","px","deg","mm")),
            shiny::selectInput(paste0("acq_gaze_origin_",i),"Source coordinate origin",c("unspecified","top_left","bottom_left")),
            shiny::numericInput(paste0("acq_gaze_valid_",i),"Source's explicit valid code",NA_real_),
            shiny::numericInput(paste0("acq_gaze_width_",i),"Pixel coordinate width (pixels only)",NA_real_,min=1,max=100000),
            shiny::numericInput(paste0("acq_gaze_height_",i),"Pixel coordinate height (pixels only)",NA_real_,min=1,max=100000)),
          shiny::numericInput(paste0("acq_gap_",i),"Gap threshold in seconds (optional)",NA_real_,min=.000001,max=3600),
          shiny::numericInput(paste0("acq_checks_count_",i),"Named acquisition checks for this measurement (optional)",0,min=0,max=8,step=1),
          shiny::uiOutput(paste0("acq_check_editors_",i)),shiny::uiOutput(paste0("acq_check_review_",i)))}),
      shiny::textInput("acq_participant","Participant ID (explicit linkage)",""),
      shiny::textInput("acq_session_identity","Recording session ID", ""),
      shiny::selectInput("acq_run_id","Optional explicit participant-run binding",{
        runs<-Filter(function(r) identical(brohn_hash(r$protocol$design),brohn_hash(study$body)),brohn_runs(store,study$id))
        c("No participant-run binding"="",stats::setNames(vapply(runs,`[[`,character(1),"id"),vapply(runs,function(r)
          paste(r$participant_alias,r$created_at,r$origin,sep=" - "),character(1))))
      }),
      shiny::selectInput("acq_origin","Collection origin",c("Choose the origin"="","Synthetic / sample"="sample","Pilot"="pilot","Live research"="live")),
      shiny::textAreaInput("acq_provenance","Source and unit review notes", "",rows=3),
      shiny::numericInput("acq_duration","Stop after at most this many seconds",600,min=.1,max=86400),
      shiny::tags$details(shiny::tags$summary("Recording limits"),
        shiny::numericInput("acq_max_samples","Maximum received samples across all selected sources",100000,min=1,max=2000000),
        shiny::numericInput("acq_max_mib","Maximum sample-data MiB (plus bounded manifest overhead)",64,min=1,max=512),
        shiny::numericInput("acq_chunk","Samples per pull",256,min=1,max=512),
        shiny::numericInput("acq_buffer","Native inlet buffer: seconds for regular streams, hundreds of samples for irregular streams",5,min=1,max=60)),
      shiny::checkboxInput("acq_reviewed","I reviewed source identities, every channel unit, source clocks, origin, participant/session IDs and the named acquisition checks",FALSE),
      shiny::actionButton("acq_start","Start reviewed recording",class="btn-primary"))
  })
  for(index in seq_len(16L))local({i<-index
    output[[paste0("acq_check_editors_",i)]]<-shiny::renderUI({
      streams<-chosen();shiny::req(length(streams)>=i)
      count<-brohn_default(input[[paste0("acq_checks_count_",i)]],0);shiny::req(brohn_number(count,0,8,TRUE))
      brohn_acquisition_checks_ui(i,streams[[i]]$channels,count,shiny::isolate(shiny::reactiveValuesToList(input)),streams[[i]]$value_type)
    })
    output[[paste0("acq_check_review_",i)]]<-shiny::renderUI({
      streams<-chosen();shiny::req(length(streams)>=i)
      count<-brohn_default(input[[paste0("acq_checks_count_",i)]],0);if(identical(as.numeric(count),0))return(NULL)
      tryCatch({
        channels<-lapply(seq_along(streams[[i]]$channels),function(j)list(id=paste0("channel-",j),label=streams[[i]]$channels[[j]]$label,
          unit=input[[paste0("acq_unit_",i,"_",j)]],value_type=streams[[i]]$value_type))
        rules<-brohn_acquisition_checks_input(input,i,channels,FALSE)
        brohn_validate_acquisition_checks(list(schema="brohn-acquisition-readiness/1.1",modality=input[[paste0("acq_measurement_",i)]],
          preview_channels=as.list(paste0("channel-",input[[paste0("acq_preview_",i)]])),acquisition_checks=rules),channels)
        shiny::tags$details(open=TRUE,shiny::tags$summary("Review the exact acquisition checks to freeze with this recording"),
          shiny::p("Passing these source checks does not establish physiological validity. Missing or stale support stays unknown."),
          brohn_table(rules,label=paste("Exact reviewed acquisition checks for source",i,streams[[i]]$name)))
      },error=function(e)shiny::p(class="brohn-muted",paste("Complete the acquisition check review:",conditionMessage(e))))
    })
  })
  check_signature<-function(i,j) {
    streams<-chosen();brohn_require(length(streams)>=i,"Choose the criterion's original source.");observed<-streams[[i]]
    channels<-lapply(seq_along(observed$channels),function(k)list(id=paste0("channel-",k),unit=input[[paste0("acq_unit_",i,"_",k)]],value_type=observed$value_type))
    rules<-brohn_acquisition_checks_input(input,i,channels,FALSE,j);brohn_require(length(rules)==1L,"Choose this criterion before review.")
    rule<-rules[[1L]]
    brohn_validate_acquisition_checks(list(schema="brohn-acquisition-readiness/1.1",modality=input[[paste0("acq_measurement_",i)]],
      preview_channels=as.list(paste0("channel-",input[[paste0("acq_preview_",i)]])),acquisition_checks=list(rule)),channels)
    brohn_hash(list(criterion=rule,uid=observed$uid,metadata_sha256=observed$metadata_sha256,modality=input[[paste0("acq_measurement_",i)]],
      role=input[[paste0("acq_role_",i,"_",match(rule$channel_id,vapply(channels,`[[`,character(1),"id")))]]))
  }
  for(stream_index in seq_len(16L))for(check_index in seq_len(8L))local({i<-stream_index;j<-check_index;key<-paste(i,j,sep="_");control<-paste0("acq_check_",key,"_reviewed")
    shiny::observeEvent(input[[control]],{
      reviewed_checks[[key]]<-if(isTRUE(input[[control]]))tryCatch(check_signature(i,j),error=function(e)NULL) else NULL
      if(isTRUE(input[[control]])&&is.null(reviewed_checks[[key]]))shiny::updateCheckboxInput(session,control,value=FALSE)
    },ignoreInit=TRUE)
    shiny::observe({prior<-reviewed_checks[[key]];if(is.null(prior))return()
      current<-tryCatch(check_signature(i,j),error=function(e)NULL)
      if(!identical(current,prior)){reviewed_checks[[key]]<-NULL;shiny::updateCheckboxInput(session,control,value=FALSE)}
    })
  })
  shiny::observeEvent(input$acq_start,attempt(function() {
    s<-current_study();d<-latest();selected<-chosen()
    brohn_require(!is.null(d) && identical(input$acq_form_identity,paste(s$id,s$revision,d$id,d$body$result_hash,sep=":")),"This discovery or study changed. Reopen and review the source form.")
    selections<-lapply(seq_along(selected),function(i) {
      observed<-selected[[i]]
      channels<-lapply(seq_along(observed$channels),function(j) list(id=paste0("channel-",j),label=brohn_default(observed$channels[[j]]$label,paste("Channel",j)),
        type=brohn_default(observed$channels[[j]]$type,brohn_default(observed$type,"unclassified")),unit=input[[paste0("acq_unit_",i,"_",j)]],value_type=observed$value_type))
      gap<-input[[paste0("acq_gap_",i)]];if(is.null(gap)||is.na(gap)) gap<-NULL
      readiness<-list(schema="brohn-acquisition-readiness/1.1",modality=input[[paste0("acq_measurement_",i)]],acquisition_checks=brohn_acquisition_checks_input(input,i,channels),
        channels=lapply(seq_along(channels),function(j){item<-list(id=channels[[j]]$id,role=input[[paste0("acq_role_",i,"_",j)]])
          for(rail in c("min","max")){value<-input[[paste0("acq_rail_",rail,"_",i,"_",j)]];if(!is.null(value)&&!is.na(value))item[[paste0("rail_",rail)]]<-value};item}),
        preview_channels=as.list(paste0("channel-",input[[paste0("acq_preview_",i)]])))
      for(field in c("reference","site","calibration","frame","gravity_policy","wavelengths","task_identity")) {
        key<-if(field=="gravity_policy")"gravity" else field;readiness[[field]]<-input[[paste0("acq_",key,"_",i)]]
      }
      if(isTRUE(input[[paste0("acq_gaze_enabled_",i)]]))readiness$gaze<-list(eye=input[[paste0("acq_gaze_eye_",i)]],
        unit=input[[paste0("acq_gaze_unit_",i)]],frame=readiness$frame,origin=input[[paste0("acq_gaze_origin_",i)]],
        valid_value=input[[paste0("acq_gaze_valid_",i)]])
      if(!is.null(readiness$gaze)&&identical(readiness$gaze$unit,"px")) {
        readiness$gaze$width<-input[[paste0("acq_gaze_width_",i)]];readiness$gaze$height<-input[[paste0("acq_gaze_height_",i)]]
      }
      brohn_validate_acquisition_readiness(readiness,channels)
      for(j in seq_along(readiness$acquisition_checks))brohn_require(identical(reviewed_checks[[paste(i,j,sep="_")]],check_signature(i,j)),
        "This acquisition criterion changed after review. Review its exact settings again before starting collection.")
      selection<-brohn_lsl_selection(d,observed$uid,paste0("stream-",i),input[[paste0("acq_clock_",i)]],input[[paste0("acq_clock_kind_",i)]],input[[paste0("acq_kind_",i)]],channels,input$acq_provenance,gap)
      selection$readiness<-readiness;selection
    })
    r<-brohn_queue_acquisition(store,s$id,d$id,selections,list(participant_id=input$acq_participant,session_id=input$acq_session_identity),input$acq_origin,input$acq_provenance,
      list(max_duration_s=input$acq_duration,max_samples=input$acq_max_samples,max_bytes=input$acq_max_mib*1024^2,chunk_samples=input$acq_chunk,inlet_buffer=input$acq_buffer),s$revision,isTRUE(input$acq_reviewed),
      run_id=if(is.null(input$acq_run_id)||!nzchar(input$acq_run_id)) NULL else input$acq_run_id)
    message("Recording queued for the independent local manager. Browser disconnection does not stop collection.");refresh()
  }))
  output$acquisition_recordings <- shiny::renderUI({
    pulse();s<-current_study();records<-brohn_acquisitions(store,s$id)
    if(!length(records)) return(NULL)
    shiny::tagList(shiny::h3("Recording history"),lapply(head(records,20L),function(record) {
      r<-brohn_acquisition(store,record$id);b<-r$body;snapshot<-r$live_snapshot
      brohn_card(title=b$title,subtitle=paste(b$created_at,"-",b$status),
        shiny::p(paste("Origin:",b$origin,". Participant:",b$request$identity$participant_id,". Session:",b$request$identity$session_id)),
        if(!is.null(snapshot)) shiny::p(paste(snapshot$samples,"committed samples;",snapshot$chunks,"committed chunks.")),
        brohn_acquisition_quality_ui(brohn_acquisition_quality(r)),
        if(is.null(b$original)) shiny::p("Signal quality still requires review; live counts do not establish valid research data."),
        if(!is.null(b$error)) shiny::p(class="brohn-alert brohn-alert-warning",b$error),
        if(b$status %in% c("queued","starting","recording","stopping")) shiny::div(class="brohn-toolbar",
          brohn_command("Stop and save","acq_stop",list(id=r$id,request_hash=b$request_hash,cancel=FALSE)),
          brohn_command("Cancel recording","acq_stop",list(id=r$id,request_hash=b$request_hash,cancel=TRUE))),
        if(!is.null(b$original)) shiny::tagList(
          shiny::p(paste("Original preserved:",b$inspection$samples,"samples;",b$completion_status,". Full raw evidence and clock observations are retained.")),
          shiny::p(brohn_acquisition_quality_text(b$inspection)),
          brohn_command("Download original recording","acq_download",list(id=r$id,hash=b$original$hash)),
          if(is.null(b$import_dataset_id)) brohn_command(if(b$completion_status=="completed") "Prepare separate datasets" else "Review and import this incomplete subset",
            "acq_review",list(id=r$id,original_hash=b$original$hash,allow_incomplete=b$completion_status!="completed")),
          if(!is.null(b$review)) shiny::p(paste("Dataset preparation:",b$review$status,brohn_default(b$review$error,""))),
          if(!is.null(b$import_dataset_id)) brohn_command("Open prepared recording","open_dataset",b$import_dataset_id)))
    }),if(length(records)>20L) shiny::p(paste(length(records)-20L,"older recordings are retained in the workspace catalog.")))
  })
  shiny::observeEvent(input$acq_stop,attempt(function() {
    command<-input$acq_stop;r<-brohn_acquisition(store,command$id)
    brohn_require(identical(r$body$study_id,current_study()$id) && identical(r$body$request_hash,command$request_hash),"This stop control belongs to another recording.")
    brohn_stop_acquisition(store,r$id,r$revision,isTRUE(command$cancel));message("Stop request saved for this exact recording.")
  }))
  shiny::observeEvent(input$acq_review,attempt(function() {
    command<-input$acq_review;r<-brohn_acquisition(store,command$id)
    brohn_require(identical(r$body$study_id,current_study()$id) && identical(r$body$original$hash,command$original_hash),"This review belongs to another original recording.")
    brohn_review_acquisition(store,r$id,r$revision,isTRUE(command$allow_incomplete));message("The verified original will be exported into separate curatable datasets, preserving clocks.")
  }))
  download <- shiny::reactiveVal(NULL)
  shiny::observeEvent(input$acq_download,attempt(function() {
    command<-input$acq_download;r<-brohn_acquisition(store,command$id)
    brohn_require(identical(r$body$study_id,current_study()$id)&&identical(r$body$original$hash,command$hash),"This download belongs to another original recording.")
    download(r);shiny::showModal(shiny::modalDialog(title="Download original recording",shiny::p("Includes the full original recording, explicit participant/session IDs and clock evidence. Keep it private."),
      shiny::downloadButton("acquisition_original_download","Download verified original",icon=NULL),easyClose=TRUE))
  }))
  output$acquisition_original_download <- shiny::downloadHandler(filename=function() paste0(download()$id,".brohn-acquisition.zip"),content=function(file) {
    prepare_download(function() {r<-download();shiny::req(!is.null(r));brohn_copy_object_download(store,r$body$original$hash,file)})
  },contentType="application/zip")
  invisible(NULL)
}

# Native facial outputs remain explicitly separate from inferred mental states.
brohn_facial_mapping_ui <- function(metadata) {
  m<-if(brohn_is_facial_profile(metadata))metadata else list()
  paths<-c(Sys.getenv("BROHN_PYTHON_FACIAL_AU"),Sys.getenv("BROHN_FACIAL_MODEL_DIR"),Sys.getenv("BROHN_FACIAL_FFMPEG_DIR"))
  configured<-length(paths)==3L&&all(nzchar(paths))&&all(file.exists(paths))
  shiny::div(class="brohn-facial-settings",
    shiny::p("Extract 20 native action-unit scores and seven expression-category scores with the optional local Py-Feat profile. Identity recognition, gaze and pose estimation are disabled."),
    shiny::p(class="brohn-muted","These are model outputs. A category labelled happiness is not a measurement of happiness, attention or preference."),
    brohn_badge(if(configured)"Optional installation configured"else "Optional installation needs setup",if(configured)"neutral"else "warning"),
    shiny::p(if(configured)"Selected model and shared FFmpeg files, Py-Feat source files and dependency versions are checked before inference."else "An operator must install the facial-au profile and configure its pinned model and shared FFmpeg directories. See docs/methods/FACIAL-AU-NATIVE-PROFILE.md. Your video remains saved if processing cannot start."),
    shiny::textAreaInput("map_facial_consent","Permission for facial processing",brohn_default(m$consent_statement,""),width="100%",rows=3,
      placeholder="Record the consent or other applicable permission covering this recording and the proposed facial analysis. Identify synthetic or licensed software-test material explicitly."),
    shiny::checkboxInput("map_facial_confirm","I have checked that the stated permission covers this local facial analysis",FALSE),
    shiny::tags$details(open=NA,shiny::tags$summary("Choose the video window and sampling"),
      shiny::div(class="brohn-form-grid",
        shiny::textInput("map_facial_start","Start after first video timestamp (decimal seconds)",brohn_default(m$start_s,"0")),
        shiny::textInput("map_facial_end","End after first video timestamp (blank for video end)",brohn_default(m$end_s,"")),
        shiny::numericInput("map_facial_stride","Analyse every Nth frame",brohn_default(m$frame_stride,1),min=1,max=120,step=1),
        shiny::numericInput("map_facial_gap","Largest supported frame interval (seconds)",brohn_default(m$max_support_gap_s,.25),min=.001,max=10)),
      shiny::p("Choose 2 to 300 analysed frames. Larger recordings need an explicit shorter window or frame stride; Brohn never silently skips frames. The current profile accepts videos up to 10 minutes and 512 MiB."),
      shiny::p("Original video presentation timestamps are retained. Missing faces, multiple faces and intervals above the declared support gap do not contribute to the supported-time average.")))
}
brohn_facial_mapping_input <- function(input,origin_statement) {
  brohn_require(isTRUE(input$map_facial_confirm),"Confirm that the stated permission covers local facial processing before continuing.")
  end<-trimws(brohn_default(input$map_facial_end,""))
  m<-list(profile=.brohn_facial_profile,origin_statement=origin_statement,consent_statement=input$map_facial_consent,
    start_s=trimws(brohn_default(input$map_facial_start,"0")),frame_stride=input$map_facial_stride,max_support_gap_s=input$map_facial_gap)
  if(nzchar(end))m$end_s<-end
  m
}
.brohn_facial_number <- function(x) if(is.null(x))"Unavailable"else format(signif(x,5),trim=TRUE,scientific=abs(x)>0&&abs(x)<1e-4)
.brohn_facial_exact <- function(x) if(is.null(x))"Unavailable"else sprintf("%.17g",x)
.brohn_facial_bars <- function(features,title,id) {
  escape<-function(x)as.character(htmltools::htmlEscape(as.character(x),attribute=TRUE))
  height<-54+length(features)*39;width<-360;left<-100;span<-160
  shapes<-c(sprintf('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 %d %d" role="img" aria-labelledby="%s-title %s-desc" style="display:block;width:100%%;height:auto;max-width:540px"><title id="%s-title">%s</title><desc id="%s-desc">Native model scores from zero to one. Arithmetic means include valid single-face frames only. Exact values and support are available in the adjacent table. These are not measured emotions or FACS intensities.</desc>',width,height,id,id,id,escape(title),id),
    '<g font-family="system-ui,sans-serif" fill="currentColor" font-size="16">',sprintf('<text x="%d" y="20">0</text><text x="%d" y="20">1</text>',left,left+span))
  for(i in seq_along(features)) {f<-features[[i]];y<-36+(i-1)*39;label<-if(f$family=="native_expression_category")tools::toTitleCase(f$metric)else f$metric
    shapes<-c(shapes,sprintf('<text x="4" y="%d">%s</text><rect x="%d" y="%d" width="%d" height="12" rx="4" fill="#293b47"/><text x="%d" y="%d">%s</text>',y+12,escape(label),left,y,span,left+span+10,y+12,escape(.brohn_facial_number(f$value))),
      if(!is.null(f$value))sprintf('<rect x="%d" y="%d" width="%.8f" height="12" rx="4" fill="#99cec3" data-metric="%s" data-value="%.17g"/>',left,y,max(0,f$value)*span,escape(f$metric),f$value))
  }
  paste0(c(shapes,"</g></svg>"),collapse="")
}
brohn_facial_report_ui <- function(a) {
  if(!brohn_facial_supported(a))return(NULL)
  q<-a$quality;p<-a$parameters
  rows<-lapply(a$features,function(f)list(measure=f$metric,mean_native_score=.brohn_facial_exact(f$value),time_supported_mean=.brohn_facial_exact(f$time_weighted_mean),eligible_frames=f$valid_frames,supported_seconds=.brohn_facial_exact(f$valid_time_s)))
  preview<-lapply(a$preview,function(x)list(source_frame=x$frame_index,original_pts=x$source_pts,time_base=x$source_time_base,relative_seconds=.brohn_facial_exact(x$time_s),
    state=gsub("_"," ",x$state),detected_faces=x$face_count,in_summary=if(x$eligible)"Yes"else "No"))
  shiny::tagList(
    brohn_card(title="Facial processing coverage",subtitle="Native outputs from the selected video window",
      brohn_badge(if(q$usable)"Single-face observations available"else "No eligible single-face observations",if(q$usable)"neutral"else "warning"),
      shiny::p(paste(q$eligible_single_face_frames,"of",q$analysed_frames,"analysed frames contribute to the score summaries.")),
      shiny::p(paste(brohn_default(q$states$no_face,0),"frames without a detected face;",brohn_default(q$states$multiple_faces,0),"with multiple faces;",brohn_default(q$states$invalid_native_output,0),"with incomplete native outputs.")),
      shiny::p(paste(.brohn_facial_number(q$eligible_time_s),"seconds of adjacent supported single-face observations. The recording contains",q$source_frames,"source frames;",q$skipped_interval_frames,"frames inside the selected window were skipped by the declared stride.")),
      shiny::p(paste("Window:",p$start_s,"to",brohn_default(p$end_s,"video end"),"seconds after the first presentation timestamp; every",p$frame_stride,"frame(s).")),
      shiny::p("Single-face frames are not proof that the same person remained present. No identity recognition or person tracking is performed."),
      shiny::tags$details(shiny::tags$summary("Inspect complete coverage settings"),shiny::tags$pre(brohn_json(q,TRUE)))),
    brohn_card(title="Native expression-category scores",subtitle="Preserved model labels; scores range from 0 to 1",
      shiny::p("Happiness, anger and the other names below are native classifier labels. They do not establish a participant's feelings, attention or liking."),
      htmltools::HTML(.brohn_facial_bars(Filter(function(f)f$family=="native_expression_category",a$features),"Native expression-category frame means","facial-categories")),
      shiny::tags$details(shiny::tags$summary("Exact category values and support"),brohn_table(tail(rows,7),maximum=7,label="Native category values and support"))),
    brohn_card(title="Native action-unit scores",subtitle="20 AU outputs; no conversion to FACS intensity",
      shiny::p("Scores are means across eligible sampled frames. AU07 uses a different native decision objective, so the scores are not interchangeable calibrated confidences."),
      htmltools::HTML(.brohn_facial_bars(Filter(function(f)f$family=="action_unit",a$features),"Native action-unit frame means","facial-aus")),
      shiny::tags$details(shiny::tags$summary("Exact action-unit values and support"),brohn_table(head(rows,20),maximum=20,label="Native action-unit values and support"))),
    brohn_card(title="Original frame timing and detection support",
      shiny::p(paste("Showing",length(preview),"of",q$analysed_frames,"analysed frames. Complete frame JSONL and face-wise CSV are available in Complete processing artifacts.")),
      shiny::p("A no-face CSV row has blank native scores. Multiple detected faces retain separate rows and local face ordinals, and are excluded from summaries."),
      shiny::tags$details(shiny::tags$summary("Inspect the frame preview"),brohn_table(preview,maximum=50,label="Original frame timing and face support"))))
}

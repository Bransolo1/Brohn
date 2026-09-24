# Researcher-facing collection routes, derived from actual protocol configuration.
# A selected measure is a research intention, not evidence of device connection.
brohn_collection_routes <- function(design) {
  labels <- c(gaze="Eye tracking", questionnaire="Questionnaires", eeg="EEG", eda="EDA", ecg="ECG / HRV", ppg="PPG",
    respiration="Respiration", emg="Muscle activity", eog="EOG", fnirs="fNIRS", temperature="Temperature", movement="Movement",
    webcam_gaze="Webcam gaze", facial_geometry="Face geometry", facial_expression="Facial expression", pose="Body and hand geometry",
    voice="Voice", rt="Reaction time", iat="IAT", biat="Brief IAT", sciat_window="Single-category IAT", gnat="Go/No-Go association", aat="Approach / avoidance", maxdiff="Best-worst choices")
  kinds <- vapply(design$blocks, function(block) brohn_task_profile(block$profile)$kind, character(1))
  actual_tasks <- unique(ifelse(kinds %in% c("simple_rt", "choice_rt"), "rt", kinds))
  questions <- sum(vapply(design$questions, function(q) q$type != "information", logical(1)))
  selected <- unique(c(unlist(design$measures, use.names=FALSE), if(questions) "questionnaire", actual_tasks, if(length(design$maxdiff)) "maxdiff"))
  brohn_require(all(selected %in% names(labels)), "The study contains an unregistered collection route.")
  row <- function(id, state, detail, automatic=FALSE) list(id=id,label=unname(labels[[id]]),state=state,detail=detail,participant_link=automatic)
  routes <- lapply(selected, function(measure) {
    if(measure=="maxdiff") return(row(measure,"In the participant study",
      "The saved best-worst sets run as explicit choices after timed tasks. Eligible completed sessions receive exposure counts and the configured aggregate paired-choice model.",TRUE))
    if(measure=="questionnaire") return(if(questions) row(measure,"In the participant study",
      paste(questions,if(questions==1L) "response question is" else "response questions are","included at their saved placements. Eligible completed sessions receive an automatic report."),TRUE) else
        row(measure,"Add questions","Open Questions to add the items participants will answer."))
    if(measure %in% c("rt","iat","biat","sciat_window","gnat","aat")) return(if(measure %in% actual_tasks) row(measure,"In the participant study",
      "The configured task uses its saved materials, practice, timing and scoring profile. Eligible completed sessions receive an automatic report.",TRUE) else
        row(measure,"Configure a task","Open Tasks and add a supported procedure before collecting this measure."))
    if(measure=="gaze") return(row(measure,"Separate gaze recording",
      "Record with your eye-tracking system, then import a supported gaze CSV or TSV. Map the recording to this study's stimuli, geometry and participant identities for analysis."))
    if(measure %in% c("eeg","eda","ecg","ppg","respiration","emg")) return(row(measure,"Import or reviewed lab recording",
      "Import a supported signal file, or use Record lab streams below to choose exact LSL sources and start recording explicitly. Review channels, units and identities before running the supported analysis recipe."))
    if(measure=="fnirs") return(row(measure,"Separate fNIRS recording",
      "Import a supported SNIRF recording and review its channel, wavelength and pathlength settings before analysis."))
    if(measure=="temperature") return(row(measure,"Calibrated temperature import",
      "Import CSV or TSV and confirm calibrated units, sensor placement, environmental conditions and settling time. The saved report describes supported intervals and any thresholds you explicitly define."))
    if(measure=="movement") return(row(measure,"Calibrated acceleration import",
      "Import three calibrated acceleration channels in their recorded axis order. Confirm signed axes, sensor placement and gravity handling before analysis. Other movement sensors retain separate method requirements."))
    if(measure=="voice") return(row(measure,"Separate acoustic analysis",
      "Import a WAV recording with its sample-rate, channel and collection context. Audio recorded with a webcam remains part of the original video until prepared for an acoustic analysis."))
    if(measure=="facial_geometry") return(if(identical(design$camera$analysis_profile,"face_geometry_v1")) row(measure,"After eligible camera recording",
      "The saved camera policy requests automatic face geometry after both the recording and participant session complete successfully. Results retain native geometry and blendshapes.",TRUE) else
        row(measure,"Import video or configure camera",
          "Import a supported video for face geometry, or open Plan and select face geometry in the camera policy for automatic processing of eligible recordings."))
    if(measure=="pose") return(row(measure,"Imported video geometry",
      "Import a supported video and select the face, body and hand geometry profile. Review frame coverage and model limitations in the saved report."))
    if(measure=="facial_expression") return(if(identical(design$camera$schema,"brohn-camera-policy/1.1")&&identical(design$camera$analysis_profile,"facial_au_expression_pyfeat_v1"))
      row(measure,"After eligible camera recording","The saved named camera agreement covers the selected local facial processing. Completed supported recordings automatically receive native action-unit and category scores for the explicit window and stride. These labels do not establish feelings or attention.",TRUE)else
      row(measure,"Reviewed video facial processing","Save an imported or participant-recorded video in Data, choose the optional facial action-unit and expression profile, and confirm permission and frame sampling. Or open Plan to request it in the named camera agreement for automatic processing of eligible recordings. Native labels do not establish feelings or attention."))
    if(measure=="webcam_gaze") return(row(measure,"Calibrated webcam gaze not enabled",
      "This build needs a calibrated webcam-to-screen gaze profile before that route can collect gaze. Supported eye-tracker files can be imported through Eye tracking."))
    row(measure,"Source retention available",
      "Keep the original recording in the Data library. Automated analysis for this selected family is still being implemented; choose an enabled method for scored results.")
  })
  if(!is.null(design$camera)) routes <- c(routes,list(list(id="camera",label=if(design$camera$audio) "Camera and microphone" else "Camera",
    state=if(design$camera$required) "Required participant setup" else "Optional participant setup",participant_link=TRUE,
    detail="The participant reviews the saved recording agreement and chooses whether to enable the requested channels before timed study steps. Capture status is retained for each visit.")))
  routes
}
brohn_collection_routes_ui <- function(design) {
  routes <- brohn_collection_routes(design)
  if(!length(routes)) return(NULL)
  brohn_card(title="Collection routes",subtitle="Review what the participant study collects and which recordings you supply separately.",
    lapply(routes,function(route) shiny::div(class="brohn-stack",
      shiny::div(class="brohn-toolbar",shiny::strong(route$label),brohn_badge(route$state)),shiny::p(route$detail))))
}

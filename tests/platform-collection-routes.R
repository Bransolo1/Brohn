# Protocol intentions cannot silently become claims of acquired sensor data.
source("R/platform-load.R",encoding="UTF-8");brohn_load(ui=TRUE)
source("R/platform-collection-routes.R",encoding="UTF-8")
local({
  checks<-0L;check<-function(name,value){if(!isTRUE(value))stop(name,call.=FALSE);checks<<-checks+1L}
  design<-brohn_new_design("Original route QA");design$questions<-list();design$blocks<-list();design$measures<-list("gaze","questionnaire","iat","facial_expression","webcam_gaze","eog")
  routes<-brohn_collection_routes(design);get<-function(id) Filter(function(r)r$id==id,routes)[[1L]]
  check("selected gaze needs its separate recording",!get("gaze")$participant_link && get("gaze")$state=="Separate gaze recording")
  check("an empty questionnaire is not advertised as collected",!get("questionnaire")$participant_link && get("questionnaire")$state=="Add questions")
  check("selected IAT without a block needs configuration",!get("iat")$participant_link && get("iat")$state=="Configure a task")
  check("facial processing is reviewed rather than automatic emotion collection",get("facial_expression")$state=="Reviewed video facial processing" && !get("facial_expression")$participant_link && grepl("do not establish feelings",get("facial_expression")$detail))
  check("calibrated webcam gaze remains separate",grepl("not enabled",get("webcam_gaze")$state))
  design$measures<-list("sciat_window"); routes<-brohn_collection_routes(design)
  check("SC-IAT intention requires a configured task",get("sciat_window")$state=="Configure a task" && !get("sciat_window")$participant_link)
  design$blocks<-list(brohn_task_new("sciat-brohn-response-window-im100/1.0")); routes<-brohn_collection_routes(design)
  check("saved SC-IAT provides the participant collection route",get("sciat_window")$participant_link)
  design$blocks<-list(); design$measures<-list("eog"); routes<-brohn_collection_routes(design)
  check("retained EOG does not claim an analysis",get("eog")$state=="Source retention available")
  design$measures<-list("temperature","movement"); routes<-brohn_collection_routes(design)
  check("temperature offers its calibrated import route",get("temperature")$state=="Calibrated temperature import" && !get("temperature")$participant_link)
  check("acceleration offers its exact three-axis route without generic movement claims",get("movement")$state=="Calibrated acceleration import" && grepl("Other movement sensors",get("movement")$detail,fixed=TRUE))
  q<-brohn_question(type="rating");design$questions<-list(q);design$measures<-list("eeg");design$blocks<-list(brohn_task_new("rt-deary-liewald-simple/1.0"))
  routes<-brohn_collection_routes(design)
  check("configured question appears even when intention checkbox is omitted",get("questionnaire")$participant_link)
  check("configured task appears even when intention checkbox is omitted",get("rt")$participant_link)
  check("EEG source selection remains an explicit separate action",!get("eeg")$participant_link && grepl("start recording explicitly",get("eeg")$detail))
  design$measures<-list("facial_geometry");design$camera<-list(audio=FALSE,required=FALSE,analysis_profile="none")
  routes<-brohn_collection_routes(design)
  check("camera policy is included even without a selected measure",get("camera")$participant_link && get("camera")$state=="Optional participant setup")
  check("recording alone does not imply automatic geometry",!get("facial_geometry")$participant_link)
  design$camera$analysis_profile<-"face_geometry_v1";routes<-brohn_collection_routes(design)
  check("geometry automation follows the actual frozen policy",get("facial_geometry")$participant_link)
  html<-htmltools::renderTags(brohn_collection_routes_ui(design))$html
  check("rendered checklist describes sources without claiming hardware readiness",grepl("Collection routes",html,fixed=TRUE) && !grepl("Device connected|Hardware ready",html))
  for(profile in names(brohn_task_profiles())) {
    one<-brohn_new_design("Collection registry contract");one$measures<-list();one$questions<-list();one$camera<-NULL
    one$blocks<-list(brohn_task_new(profile));actual<-brohn_collection_routes(one)
    check(paste("Every registered procedure has exactly one participant collection route",profile),
      length(actual)==1L&&isTRUE(actual[[1L]]$participant_link)&&nzchar(actual[[1L]]$label))
  }
  cat(sprintf("PASS: %d collection route assertions\n",checks))
})

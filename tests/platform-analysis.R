# Independent researcher arithmetic and identity/phase validation fixtures.
for (module in c("platform-core", "platform-store", "platform-delivery", "platform-analysis", "platform-jobs")) source(paste0("R/", module, ".R"), encoding = "UTF-8")
source("tests/fixtures/platform-analysis-fixture.R")
local({
  checks <- 0L; failures <- character()
  check <- function(name, expr) {
    checks <<- checks + 1L
    value <- tryCatch(isTRUE(force(expr)), error = function(e) {failures <<- c(failures, paste(name, conditionMessage(e), sep=": ")); NA})
    if (identical(value, FALSE)) failures <<- c(failures, name)
  }
  near <- function(a,b) is.numeric(a) && length(a)==1 && abs(a-b)<1e-9
  rejects <- function(expr) inherits(try(force(expr), silent=TRUE), "try-error")
  f <- researcher_analysis_fixture()
  before <- digest::digest(f)
  gaze <- brohn_gaze_analysis(f$gaze, f$gaze_mapping, f$design)
  check("gaze equal-person mean matches independent 10.833333 pp", near(gaze$contrasts[[1]]$estimate, 10.833333333333334))
  check("gaze has three eligible people and four paired sessions", gaze$contrasts[[1]]$participant_count==3 && gaze$contrasts[[1]]$paired_session_count==4)
  check("gaze incomplete session excluded only from pair", gaze$contrasts[[1]]$excluded_session_count==1)
  check("session-pooled 13.75 is not substituted for person estimand", !near(gaze$contrasts[[1]]$estimate,13.75))
  first <- Filter(function(x) x$participant_id=="P01" && x$session_id=="P01-S1" && x$stimulus_id=="stimulus-a", gaze$observations)[[1]]
  check("active response interval excluded from passive denominator", first$valid_ms==4000 && first$inside_ms==1000 && near(first$valid_share_percent,25))
  check("gaze gap does not become first fixation evidence", is.null(first$first_observed_aoi_contact_ms) && first$first_contact_status=="unavailable_incomplete_observation")
  absent <- Filter(function(x) x$participant_id=="P04" && x$stimulus_id=="stimulus-a",gaze$observations)[[1]]
  check("zero valid gaze gives null share, never zero score", is.null(absent$valid_share_percent) && absent$valid_ms==0)
  present <- Filter(function(x) x$participant_id=="P04" && x$stimulus_id=="stimulus-b",gaze$observations)[[1]]
  check("other valid presentation survives missing paired gaze", near(present$valid_share_percent,30))
  check("analysis leaves raw table and frozen design unchanged", identical(before,digest::digest(f)))
  check("method remains draft prepared-interval metric", gaze$parameters$method=="aoi-valid-gaze-time-share/0.1.0-draft")
  check("contrast direction names correct control/test", gaze$contrasts[[1]]$control_id=="condition-a" && gaze$contrasts[[1]]$test_id=="condition-b")
  reverse <- f$design; reverse$conditions[[1]]$role <- "test"; reverse$conditions[[2]]$role <- "control"
  check("reversed control reverses prespecified estimate", near(brohn_gaze_analysis(f$gaze,f$gaze_mapping,reverse)$contrasts[[1]]$estimate,-10.833333333333334))
  duplicate <- rbind(f$gaze,f$gaze[1,,drop=FALSE])
  check("duplicate/overlapping gaze intervals rejected",rejects(brohn_gaze_analysis(duplicate,f$gaze_mapping,f$design)))
  wrong <- f$gaze; wrong$stimulus[[1]] <- "unknown-stimulus"
  check("unknown stimulus identity rejected",rejects(brohn_gaze_analysis(wrong,f$gaze_mapping,f$design)))
  wrong <- f$gaze; wrong$condition[[1]] <- "condition-b"
  check("condition/stimulus disagreement rejected",rejects(brohn_gaze_analysis(wrong,f$gaze_mapping,f$design)))
  wrong <- f$gaze; wrong$session[[1]] <- ""
  check("missing session identity rejected",rejects(brohn_gaze_analysis(wrong,f$gaze_mapping,f$design)))
  wrong <- f$gaze; wrong$x[[1]] <- ""
  check("missing coordinate cannot be called valid gaze",rejects(brohn_gaze_analysis(wrong,f$gaze_mapping,f$design)))
  wrong <- f$gaze; wrong$valid[[1]] <- "maybe"
  check("unknown validity token rejected",rejects(brohn_gaze_analysis(wrong,f$gaze_mapping,f$design)))
  wrong <- f$gaze; wrong$end[[1]] <- wrong$start[[1]]
  check("zero-duration interval rejected",rejects(brohn_gaze_analysis(wrong,f$gaze_mapping,f$design)))
  outside <- f$gaze; outside$x[[1]] <- "2"
  outside_result <- brohn_gaze_analysis(outside,f$gaze_mapping,f$design)
  outside_first <- Filter(function(x) x$session_id=="P01-S1" && x$stimulus_id=="stimulus-a",outside_result$observations)[[1]]
  check("off-stimulus gaze stays valid outside AOI", outside_first$valid_ms==4000 && outside_first$inside_ms==0)
  mapping <- f$gaze_mapping; mapping$phase_column <- NULL; mapping$phase_value <- NULL
  check("undeclared source phase is rejected",rejects(brohn_gaze_analysis(f$gaze,mapping,f$design)))
  dataset <- list(modality="gaze",study_id=f$design$id,source=list(format="csv"),columns=as.list(names(f$gaze)),metadata=f$gaze_mapping)
  check("explicit mapping validates",!rejects(brohn_validate_dataset_mapping(dataset)))
  wrong_dataset <- dataset; wrong_dataset$metadata$unit <- "pixels"
  check("pixel coordinates cannot be mislabelled normalized",rejects(brohn_validate_dataset_mapping(wrong_dataset)))
  wrong_dataset <- dataset; wrong_dataset$metadata$time_unit <- "native_ticks"
  check("native ticks require explicit adapter rather than coercion",rejects(brohn_validate_dataset_mapping(wrong_dataset)))
  wrong_dataset <- dataset; wrong_dataset$metadata$phase_column <- "missing-phase-column"
  check("mapped phase column must exist",rejects(brohn_validate_dataset_mapping(wrong_dataset)))

  responses <- brohn_import_responses(f$responses,f$response_mapping,f$design)
  liking <- brohn_questionnaire_analysis(responses,f$design)
  check("liking mean matches independent 1.375 points",near(liking$contrasts[[1]]$estimate,1.375))
  check("liking retains four people and all five paired sessions",liking$contrasts[[1]]$participant_count==4 && liking$contrasts[[1]]$paired_session_count==5)
  check("missing gaze did not delete valid explicit responses",length(responses)==10)
  wrong <- f$responses; wrong$value[[1]] <- "99"
  check("out-of-range/undeclared rating code rejected",rejects(brohn_import_responses(wrong,f$response_mapping,f$design)))
  wrong <- f$responses; wrong$question[[1]] <- "unknown-question"
  check("unknown question identity rejected",rejects(brohn_import_responses(wrong,f$response_mapping,f$design)))
  wrong <- f$responses; wrong$stimulus[[1]] <- "unknown-stimulus"
  check("unknown response stimulus rejected",rejects(brohn_import_responses(wrong,f$response_mapping,f$design)))
  wrong <- f$responses; wrong$condition[[1]] <- "condition-b"
  check("response condition and stimulus cannot disagree",rejects(brohn_import_responses(wrong,f$response_mapping,f$design)))
  check("duplicate committed exposure response rejected",rejects(brohn_import_responses(rbind(f$responses,f$responses[1,,drop=FALSE]),f$response_mapping,f$design)))
  wrong <- f$responses; wrong$stimulus[[1]] <- ""
  check("after-each response requires actual stimulus",rejects(brohn_import_responses(wrong,f$response_mapping,f$design)))
  wrong_design <- f$design; wrong_design$questions[[1]]$scope <- "before"
  check("before-study response cannot acquire a stimulus condition",rejects(brohn_import_responses(f$responses,f$response_mapping,wrong_design)))
  missing <- f$responses; missing$value[[1]] <- ""
  retained <- brohn_import_responses(missing,f$response_mapping,f$design)
  check("missing imported response retains explicit null and reason",is.null(retained[[1]]$value) && retained[[1]]$missing_reason=="imported_missing")
  typed <- lapply(seq_along(list(FALSE,0,"0",NULL)),function(i) list(participant_id=paste0("typed-",i),session_id=paste0("typed-",i),question_id="typed",condition_id=NULL,prompt="Typed values",value=list(FALSE,0,"0",NULL)[[i]]))
  typed_result <- brohn_questionnaire_analysis(typed)
  check("false zero and string zero stay separate distribution bins",length(typed_result$features[[1]]$counts)==3 && typed_result$features[[1]]$answered_count==3)
  check("only numeric zero contributes to numeric code mean",near(typed_result$features[[1]]$numeric_response_mean,0))
  check("null retains separate missing count",typed_result$features[[1]]$missing_count==1)
  categorical_design <- f$design; categorical_design$questions[[1]]$type <- "single_choice"
  categorical <- brohn_questionnaire_analysis(brohn_import_responses(f$responses, f$response_mapping, categorical_design), categorical_design)
  check("numeric category codes cannot create a condition mean or contrast", all(vapply(categorical$features, function(s) is.null(s$numeric_response_mean), logical(1))) && length(categorical$contrasts)==0)

  # An original synthetic sealed-run arithmetic oracle, not fabricated browser
  # completion evidence. Full browser transport is tested in platform-integration.
  input <- list(schema="brohn-analysis-input/1.0",operation="analyse_cohort",design=f$design,runs=list(),events=list())
  for (session in unique(f$responses$session)) {
    rows <- f$responses[f$responses$session==session,,drop=FALSE]
    protocol <- brohn_compile(f$design,1)
    steps <- Filter(function(s) s$type=="question",protocol$timeline)
    id <- paste0("run-",session)
    input$runs[[length(input$runs)+1L]] <- list(id=id,participant_alias=rows$participant[[1]],participant_alias_supplied=TRUE,
      protocol=protocol,origin="sample",deployment_id="synthetic-cohort",allocation_index=1,acked_sequence=2,finalized_at="2026-09-08T00:00:00Z")
    input$events[[id]] <- lapply(seq_along(steps),function(i) list(type="response",step_id=steps[[i]]$id,sequence=i,
      payload=list(value=as.numeric(rows$value[rows$stimulus==steps[[i]]$stimulus_id]),response_time_ms=100)))
  }
  cohort <- brohn_analyse_runs(input)
  check("run cohort matches independent equal-person liking oracle",near(cohort$analysis$contrasts[[1]]$estimate,1.375))
  check("supplied aliases link repeats without treating sessions as people",cohort$analysis$quality$participant_count==4)
  unlinked <- input; unlinked$runs[[1]]$participant_alias <- "Participant 1"; unlinked$runs[[1]]$participant_alias_supplied <- FALSE
  unlinked_result <- brohn_analyse_runs(unlinked)
  check("generated display aliases do not imply unique participant count",is.null(unlinked_result$analysis$quality$participant_count))
  check("unlinked session suppresses unsupported person inference",length(unlinked_result$analysis$contrasts)==0 && unlinked_result$analysis$quality$unlinked_session_count==1)
  check("unlinked session retains all usable responses",length(unlinked_result$analysis$observations)==10)
  older <- input; older$runs[[1]]$participant_alias_supplied <- NULL
  check("old missing linkage flag defaults conservatively to unlinked",is.null(brohn_analyse_runs(older)$analysis$quality$participant_count))
  if (length(failures)) {cat(paste0(" - ",failures,collapse="\n"),"\n"); stop(sprintf("FAIL: %d of %d independent analysis assertions",length(failures),checks),call.=FALSE)}
  cat(sprintf("PASS: %d independent researcher analysis assertions (gaze, liking, phase, missingness, identity and typed values)\n",checks))
})

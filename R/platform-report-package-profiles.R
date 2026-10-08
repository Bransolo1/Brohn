# Exact report contracts. Outer report versions are distinct from unchanged
# modality preparation/algorithm versions. Every lookup returns a fresh value.
.brohn_rpk_profile_specs <- function() {
  row<-function(renderer,admission,selection_schema,plan_schema=NULL,eda_version=NULL,
    cardiac=FALSE,legacy_renderer=renderer,legacy_admission=admission,raw_gaze=FALSE) {
    eda_admission<-if(is.null(eda_version))NULL else paste0("task-choice-eda-findings/",eda_version)
    list(renderer=renderer,admission=admission,cardiac=cardiac,eda_version=eda_version,
      eda_preparation=if(is.null(eda_version))NULL else paste0("saved-eda-display/",eda_version),
      eda_admission=eda_admission,plan_schema=plan_schema,selection_schema=selection_schema,
      legacy_renderer=legacy_renderer,legacy_admission=legacy_admission,
      legacy_scientific_admission=if(is.null(eda_admission))admission else eda_admission,
      raw_gaze_profile=if(raw_gaze)"saved-raw-gaze-projection/0.1"else NULL)
  }
  list(
    row("controlled-gaze-explicit-paired/0.1","gaze-explicit-paired-findings/0.1","brohn-report-package-selection/0.1"),
    row("controlled-gaze-explicit-task-paired/0.1","task-findings/0.1","brohn-report-package-selection/0.2","brohn-task-report-execution-plan/0.1"),
    row("controlled-gaze-explicit-task-choice-paired/0.1","task-choice-findings/0.1","brohn-report-package-selection/0.2","brohn-task-choice-report-execution-plan/0.1"),
    row("controlled-gaze-explicit-task-choice-eda-paired/0.1","task-choice-eda-findings/0.1","brohn-report-package-selection/0.3","brohn-eda-report-execution-plan/0.1","0.1"),
    row("controlled-gaze-explicit-task-choice-eda-paired/0.2","task-choice-eda-findings/0.2","brohn-report-package-selection/0.3","brohn-eda-report-execution-plan/0.2","0.2"),
    row("controlled-gaze-explicit-task-choice-eda-paired/0.3","task-choice-eda-findings/0.3","brohn-report-package-selection/0.3","brohn-eda-report-execution-plan/0.3","0.2",raw_gaze=TRUE),
    row("controlled-gaze-explicit-task-choice-eda-cardiac-paired/0.1","task-choice-eda-cardiac-findings/0.1","brohn-report-package-selection/0.4","brohn-cardiac-report-execution-plan/0.1","0.2",TRUE,
      "controlled-gaze-explicit-task-choice-eda-paired/0.2","task-choice-eda-findings/0.2"),
    row("controlled-gaze-explicit-task-choice-eda-cardiac-paired/0.2","task-choice-eda-cardiac-findings/0.2","brohn-report-package-selection/0.4","brohn-cardiac-report-execution-plan/0.2","0.2",TRUE,
      "controlled-gaze-explicit-task-choice-eda-paired/0.3","task-choice-eda-findings/0.3",TRUE))
}
.brohn_rpk_profile_lookup <- function(value,key,required) {
  rows<-if(is.character(value)&&length(value)==1L&&!is.na(value))
    Filter(function(x)identical(x[[key]],value),.brohn_rpk_profile_specs())else list()
  if(!length(rows)&&!isTRUE(required))return(NULL)
  brohn_require(length(rows)==1L,"Choose an exact registered report renderer and source admission.")
  rows[[1L]]
}
.brohn_rpk_profile_spec <- function(renderer,required=TRUE) .brohn_rpk_profile_lookup(renderer,"renderer",required)
.brohn_rpk_admission_spec <- function(admission,required=TRUE) .brohn_rpk_profile_lookup(admission,"admission",required)
.brohn_rpk_eda_report_profile <- function(renderer) {
  spec<-.brohn_rpk_profile_spec(renderer,FALSE)
  !is.null(spec$eda_version)&&!isTRUE(spec$cardiac)
}

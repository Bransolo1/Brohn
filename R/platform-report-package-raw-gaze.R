# Explicit saved raw-gaze export registration. No detection or numerical work.
.brohn_rpg_profile <- "saved-raw-gaze-projection/0.1"
.brohn_rpg_method <- "brohn-adjacent-ray-ivt/0.1.0-draft"
.brohn_rpg_gaze_sha <- "0b1fc1ce5f2180143e6b7b2dbebb1c6694168b15f494f9e481b8ef4586fbe191"
.brohn_rpg_admission_profile <- function(admission) {
  .brohn_rpk_admission_spec(admission,FALSE)$raw_gaze_profile
}
.brohn_rpk_algorithm_admission <- function(admission) {
  spec<-.brohn_rpk_admission_spec(admission,FALSE)
  if(is.null(spec))admission else spec$legacy_scientific_admission
}

.brohn_rpg_node <- function(x,path="analysis",depth=0L) {
  brohn_require(depth<60L,"Scientific projection nesting exceeds its bound.")
  if(!is.list(x)){brohn_canonical(x);return(invisible(TRUE))}
  if(is.null(names(x))){
    for(v in x).brohn_rpg_node(v,paste0(path,"/*"),depth+1L)
    return(invisible(TRUE))
  }
  brohn_require(!anyDuplicated(names(x))&&all(nzchar(names(x))),"Scientific projection has duplicate/empty field names.")
  extra<-if(identical(path,"analysis/features/*"))c("angular_path_deg","classification")else
    if(identical(path,"analysis/parameters/thresholds"))"threshold_source"else character()
  unknown<-setdiff(names(x),c(.brohn_rp_scientific_keys,extra))
  brohn_require(!length(unknown),paste("Unsupported required scientific fields at",path,":",paste(unknown,collapse=", ")))
  for(k in names(x)){
    if(k %in% c("value","previous_value","invalidated_value","item_values","value_before_conversion")){brohn_canonical(x[[k]]);next}
    .brohn_rpg_node(x[[k]],paste0(path,"/",k),depth+1L)
  }
  invisible(TRUE)
}

brohn_validate_saved_raw_gaze_projection <- function(item,profile) {
  brohn_require(identical(profile,.brohn_rpg_profile),"Choose the exact registered raw-gaze projection profile.")
  brohn_fields(item,c("ref","saved_body","complete_analysis"),label="Complete saved raw-gaze source")
  .brohn_rpk_ref_valid(item$ref,"report")
  b<-item$saved_body;a<-item$complete_analysis
  brohn_require(identical(brohn_hash(b),item$ref$body_hash)&&identical(b$id,item$ref$id)&&
    identical(brohn_eda_value_hash(b$analysis),brohn_eda_value_hash(a)),"Raw-gaze export needs the exact original inline analysis and saved body.")
  brohn_fields(a,c("kind","features","observations","contrasts","parameters","quality","limitations"),
    c("title","schema","status","scales","questionnaire_revision","artifacts","task_scores","choice_tasks","recordings"),"Complete saved raw-gaze analysis")
  brohn_require(identical(a$kind,"gaze")&&identical(a$parameters$input,"raw_gaze_samples")&&
    identical(a$parameters$method,.brohn_rpg_method)&&
    identical(b$processing$recipe,"brohn-analysis/1.0.0-draft")&&
    identical(b$processing$code_hashes[["R/platform-gaze.R"]],.brohn_rpg_gaze_sha)&&
    identical(b$provenance$engine$name,"Brohn R")&&identical(b$provenance$engine$version,"1.0.0-draft")&&
    identical(a$parameters$blink_boundary_policy,"source-labelled-blink-boundaries/1.1"),
    "The saved gaze family, method, original producer or blink policy has no registered complete projection.")
  brohn_require(identical(a$parameters$coordinate_space,"stimulus_normalized")&&identical(a$parameters$time_unit,"ms")&&
    all(vapply(c("interpolation","smoothing","merging"),function(k)identical(a$parameters[[k]],"none"),logical(1)))&&
    identical(a$quality$qualified,FALSE),"This raw-gaze coordinate/method/qualification context differs from its registered producer.")
  brohn_require(!length(a$artifacts)&&!length(a$task_scores)&&!length(a$choice_tasks)&&
    brohn_array(a$features)&&brohn_array(a$observations)&&brohn_array(a$contrasts),
    "Raw-gaze projection requires complete inline collections without unsupported companions.")
  .brohn_rpg_node(a)
  thresholds<-a$parameters$thresholds
  brohn_require(brohn_text(thresholds$threshold_source,4000)&&
    identical(brohn_eda_value_hash(thresholds),brohn_eda_value_hash(b$provenance$mapping$parameters)),
    "Saved gaze thresholds must retain their exact declared source and original mapping parameters.")
  candidate_types<-c("fixation_candidate","saccade_candidate","short_unclassified_segment")
  for(row in a$features){
    brohn_require(is.list(row)&&!is.null(names(row)),"A raw-gaze feature must be an original named record.")
    has<-intersect(c("classification","angular_path_deg"),names(row))
    if(isTRUE(row$record_type %in% candidate_types)){
      brohn_require(length(has)==2L&&brohn_text(row$classification,32)&&row$classification %in% c("low_velocity","high_velocity")&&
        brohn_number(row$angular_path_deg,0)&&identical(row$qualified,FALSE),
        "Saved raw-gaze candidates need their original class, finite nonnegative angular path and unqualified status.")
      if(identical(row$record_type,"fixation_candidate"))brohn_require(identical(row$classification,"low_velocity"),"The saved fixation candidate class changed.")
      if(identical(row$record_type,"saccade_candidate"))brohn_require(identical(row$classification,"high_velocity"),"The saved saccade candidate class changed.")
    }else brohn_require(!length(has),"Candidate angular-path/class fields cannot occur on another saved record family.")
    if(identical(row$record_type,"source_labelled_blink"))brohn_require(identical(row$boundary_policy,"source-labelled-blink-boundaries/1.1"),"The saved blink record uses an unregistered boundary policy.")
  }
  invisible(TRUE)
}

brohn_saved_raw_gaze_projection_registration <- function(item,profile) {
  brohn_validate_saved_raw_gaze_projection(item,profile)
  list(schema="brohn-saved-raw-gaze-projection-registration/0.1",profile=profile,
    source_ref=item$ref,source_analysis_value_hash=brohn_eda_value_hash(item$complete_analysis),
    method=.brohn_rpg_method,producer_recipe="brohn-analysis/1.0.0-draft",producer_gaze_sha256=.brohn_rpg_gaze_sha,
    blink_boundary_policy="source-labelled-blink-boundaries/1.1",
    registered_fields=list(
      list(path="analysis/features/*/classification",type="string",nullable=FALSE,values=list("low_velocity","high_velocity")),
      list(path="analysis/features/*/angular_path_deg",type="float64",unit="degree",nullable=FALSE),
      list(path="analysis/parameters/thresholds/threshold_source",type="string",nullable=FALSE)),
    conservation="All saved scientific values retained; no angles, velocities, classifications or estimates recomputed.",
    interpretation="Original adjacent-ray I-VT candidates remain unqualified. Angular path is not necessarily endpoint displacement or a qualified saccade amplitude.")
}

brohn_report_package_raw_gaze_projection <- function(item,aliases,namespace,profile) {
  registration<-brohn_saved_raw_gaze_projection_registration(item,profile)
  # Reuse the exact classic projection/sanitization implementation, with one
  # private lexical validator for this already registered complete source.
  # No global function or vocabulary changes; no caller-controlled skip flag.
  scope<-new.env(parent=environment(.brohn_rp_projection))
  captured<-item$complete_analysis
  scope$.brohn_rp_validate_scientific<-function(x,path="analysis",depth=0L){
    brohn_require(identical(path,"analysis")&&identical(depth,0L)&&
      identical(x,captured,num.eq=FALSE,attrib.as.set=FALSE),"The registered raw-gaze projection received another analysis.")
    .brohn_rpg_node(x,path,depth)
  }
  project<-.brohn_rp_projection;environment(project)<-scope
  lockEnvironment(scope,bindings=TRUE)
  result<-project(item,aliases,namespace)
  result$provenance$projection_registration<-registration
  result
}

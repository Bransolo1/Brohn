# Optional, pinned local AU/category provider. No identity or construct inference.
.brohn_facial_profile <- "facial_au_expression_pyfeat_v1"
.brohn_facial_aus <- sprintf("AU%02d", c(1,2,4,5,6,7,9,10,11,12,14,15,17,20,23,24,25,26,28,43))
.brohn_facial_categories <- c("anger","disgust","fear","happiness","sadness","surprise","neutral")
.brohn_facial_states <- c("no_face","single_face","multiple_faces","invalid_native_output")
brohn_is_facial_profile <- function(metadata) identical(metadata$profile, .brohn_facial_profile)
brohn_facial_supported <- function(analysis) identical(analysis$schema,"brohn-facial-expression-result/1.0") && identical(analysis$kind,"facial_expression")
.brohn_facial_same <- function(a,b) identical(brohn_hash(a),brohn_hash(b))
.brohn_facial_sha <- function(x) brohn_text(x,64) && grepl("^[a-f0-9]{64}$",x)
.brohn_facial_decimal <- function(x) brohn_text(x,80) && grepl("^(0|[1-9][0-9]*)(\\.[0-9]+)?$",x) &&
  is.finite(suppressWarnings(as.numeric(x))) && .brohn_facial_compare(x,"600") <= 0L
.brohn_facial_compare <- function(a,b) {
  # Decimal comparison without rounding a researcher-authored boundary to double.
  parts<-function(x){v<-strsplit(x,".",fixed=TRUE)[[1]];list(i=v[[1]],f=if(length(v)>1L)v[[2]]else "")}
  x<-parts(a);y<-parts(b)
  if(nchar(x$i)!=nchar(y$i))return(sign(nchar(x$i)-nchar(y$i)))
  n<-max(nchar(x$f),nchar(y$f));xx<-paste0(x$i,x$f,strrep("0",n-nchar(x$f)));yy<-paste0(y$i,y$f,strrep("0",n-nchar(y$f)))
  if(identical(xx,yy))0L else if(xx>yy)1L else -1L
}
brohn_validate_facial_mapping <- function(dataset) {
  brohn_require(identical(dataset$modality,"video") && dataset$source$format %in% c("mp4","mov","mkv","webm","avi"),"Facial processing needs an imported MP4/MOV, Matroska/WebM or AVI video.")
  m<-dataset$metadata
  brohn_require(is.list(m)&&brohn_is_facial_profile(m)&&all(names(m)%in%c("profile","origin_statement","consent_statement","start_s","end_s","frame_stride","max_support_gap_s")),"Choose the registered local facial profile and its supported settings.")
  for(k in c("origin_statement","consent_statement"))brohn_require(brohn_text(m[[k]],4000)&&nzchar(trimws(m[[k]])),paste("Describe",gsub("_"," ",k),"before processing facial data."))
  start<-brohn_default(m$start_s,"0")
  brohn_require(.brohn_facial_decimal(start),"Facial window start needs decimal seconds from 0 to 600, without exponent notation.")
  if(!is.null(m$end_s))brohn_require(.brohn_facial_decimal(m$end_s)&&.brohn_facial_compare(m$end_s,start)>0L,"Facial window end needs decimal seconds after its start, up to 600.")
  brohn_require(brohn_number(brohn_default(m$frame_stride,1),1,120,TRUE),"Analyse every Nth frame with an integer from 1 to 120.")
  brohn_require(brohn_number(brohn_default(m$max_support_gap_s,.25),.001,10),"Largest supported frame interval must be from 0.001 to 10 seconds.")
  invisible(dataset)
}
brohn_facial_expression_request <- function(input,scratch) {
  brohn_validate_facial_mapping(input$dataset)
  brohn_require(identical(input$operation,"analyse_dataset"),"Facial processing requires a frozen imported dataset job.")
  directory<-file.path(scratch,"artifacts")
  brohn_require(dir.exists(directory)||dir.create(directory),"Cannot prepare the isolated facial artifact directory.")
  m<-input$dataset$metadata;m$start_s<-brohn_default(m$start_s,"0");m$frame_stride<-as.integer(brohn_default(m$frame_stride,1));m$max_support_gap_s<-brohn_default(m$max_support_gap_s,.25)
  list(schema="brohn-facial-expression-request/1.0",source_path=normalizePath(input$source_path,winslash="/",mustWork=TRUE),source_hash=input$dataset$source$hash,
    metadata=m,output_directory=normalizePath(directory,winslash="/",mustWork=TRUE))
}
brohn_validate_facial_artifact_manifest <- function(analysis) {
  a<-analysis$artifacts
  brohn_require(brohn_facial_supported(analysis)&&brohn_array(a)&&length(a)==2L&&setequal(vapply(a,`[[`,character(1),"kind"),c("facial-observations","facial-values")),"Facial processing needs both complete frame and CSV artifacts.")
  for(x in a)brohn_require(identical(x$schema,"brohn-facial-observations/1.0")&&isTRUE(x$complete)&&.brohn_facial_sha(x$sha256)&&brohn_number(x$bytes,1,64*1024^2,TRUE)&&
    identical(x$media_type,if(x$kind=="facial-values")"text/csv" else "application/x-ndjson"),"Facial artifact schema, type, size or completeness changed.")
  invisible(TRUE)
}
brohn_validate_facial_result <- function(a,request,verify_artifacts=TRUE) {
  brohn_require(brohn_facial_supported(a)&&identical(a$status,"completed")&&identical(a$source$sha256,request$source_hash)&&
    identical(as.numeric(a$source$bytes),as.numeric(file.info(request$source_path)$size)),"Facial result source or completion identity changed.")
  p<-a$parameters;e<-a$engine;q<-a$quality
  for(k in names(request$metadata))brohn_require(.brohn_facial_same(p[[k]],request$metadata[[k]]),paste("Facial worker changed the declared",k,"setting."))
  brohn_require(is.null(p$identity_model)&&is.null(p$gaze_model)&&is.null(p$pose_model)&&identical(p$device,"cpu")&&p$threads==1&&p$face_detection_threshold==.5,
    "Facial worker changed its disabled identity/gaze/pose or CPU policy.")
  files<-c(manifest_sha256="scripts/readiness/facial-models.json",runtime_manifest_sha256="scripts/readiness/facial-runtime.json",requirements_sha256="scripts/readiness/requirements-facial-au.txt",provider_sha256="scripts/workers/facial_expression.py",video_inspector_sha256="scripts/workers/vision.py")
  for(k in names(files))brohn_require(identical(e[[k]],digest::digest(file=files[[k]],algo="sha256")),"Facial provider/runtime identity changed during this job.")
  manifest<-brohn_read_json_file(files[["manifest_sha256"]])
  brohn_require(identical(e$name,"Py-Feat Detectorv1")&&identical(e$version,"2.0.0")&&.brohn_facial_same(e$models,manifest$files),"Facial model selection differs from the pinned modular profile.")
  requirements<-readLines(files[["requirements_sha256"]],warn=FALSE);requirements<-requirements[nzchar(requirements)&!startsWith(requirements,"#")]
  brohn_require(length(e$packages)==length(requirements)&&all(vapply(strsplit(requirements,"==",fixed=TRUE),function(x)identical(e$packages[[x[[1]]]],x[[2]]),logical(1))),"Facial dependency versions differ from the pinned installation.")
  brohn_require(brohn_number(q$source_frames,2,36000,TRUE)&&brohn_number(q$interval_frames,2,q$source_frames,TRUE)&&brohn_number(q$analysed_frames,2,300,TRUE)&&
    q$analysed_frames<=q$interval_frames&&q$skipped_interval_frames==q$interval_frames-q$analysed_frames&&q$analysed_frames==ceiling(q$interval_frames/p$frame_stride),"Facial source/window/stride counts do not reconcile.")
  brohn_require(is.list(q$states)&&all(names(q$states)%in%.brohn_facial_states)&&all(vapply(q$states,brohn_number,logical(1),0,300,TRUE))&&sum(unlist(q$states))==q$analysed_frames&&
    q$eligible_single_face_frames==brohn_default(q$states$single_face,0)&&brohn_number(q$face_observations,0,4800,TRUE)&&
    brohn_number(q$eligible_time_s,0,600)&&identical(q$identity_tracking,FALSE)&&isTRUE(q$pts_validated)&&identical(q$usable,q$eligible_single_face_frames>0),"Facial coverage or eligibility is inconsistent.")
  brohn_require(brohn_array(a$features)&&length(a$features)==27L&&identical(vapply(a$features,`[[`,character(1),"metric"),c(.brohn_facial_aus,.brohn_facial_categories)),"Facial native output vocabulary changed.")
  for(f in a$features)brohn_require(identical(f$family,if(f$metric%in%.brohn_facial_aus)"action_unit" else "native_expression_category")&&
    identical(f$unit,"native_model_score_0_1")&&identical(f$aggregation,"arithmetic_mean_eligible_sampled_frames")&&identical(f$scope,"selected_recording_window")&&
    f$valid_frames==q$eligible_single_face_frames&&f$valid_time_s==q$eligible_time_s&&
    (if(q$eligible_single_face_frames>0)brohn_number(f$value,0,1)else is.null(f$value))&&
    (if(q$eligible_time_s>0)brohn_number(f$time_weighted_mean,0,1)else is.null(f$time_weighted_mean)),"Facial score support, units or missing-value policy changed.")
  brohn_require(brohn_array(a$preview)&&length(a$preview)==min(50,q$analysed_frames)&&q$preview_frames==length(a$preview)&&identical(q$preview_truncated,q$analysed_frames>50),"Facial frame preview does not declare its complete support.")
  brohn_validate_facial_artifact_manifest(a)
  if(verify_artifacts) .brohn_verify_facial_values(a,request)
  invisible(a)
}
.brohn_verify_facial_values <- function(a,request) {
  paths<-lapply(a$artifacts,function(x){path<-normalizePath(x$path,winslash="/",mustWork=TRUE);directory<-normalizePath(request$output_directory,winslash="/",mustWork=TRUE)
    brohn_require(startsWith(tolower(path),paste0(tolower(directory),"/"))&&!dir.exists(path)&&as.numeric(file.info(path)$size)==x$bytes&&identical(digest::digest(file=path,algo="sha256"),x$sha256),"Facial artifact leaves the attempt or failed its complete-byte check.");path})
  names(paths)<-vapply(a$artifacts,`[[`,character(1),"kind")
  lines<-readLines(paths[["facial-observations"]],warn=FALSE,encoding="UTF-8")
  brohn_require(length(lines)==a$quality$analysed_frames,"Complete facial frame count differs from the report.")
  rows<-lapply(lines,function(x)jsonlite::fromJSON(x,simplifyVector=FALSE))
  brohn_require(.brohn_facial_same(head(rows,50),a$preview),"Facial preview differs from complete retained frames.")
  fields<-c("frame_index","source_pts","source_time_base","source_pts_s","source_time","relative_time","time_s","decoded_rgb_sha256","state","face_count","eligible","faces")
  for(row in rows) {
    brohn_require(setequal(names(row),fields)&&brohn_number(row$frame_index,0,a$quality$source_frames-1,TRUE)&&brohn_text(row$source_pts,40)&&grepl("^-?[0-9]+$",row$source_pts)&&
      identical(row$source_time_base,a$parameters$source_time_base)&&.brohn_facial_sha(row$decoded_rgb_sha256)&&row$state%in%.brohn_facial_states&&
      brohn_number(row$time_s,0,600)&&brohn_array(row$faces)&&length(row$faces)==row$face_count&&row$face_count<=16&&identical(row$eligible,row$state=="single_face"),"Complete facial frame schema or identity changed.")
    state<-if(!length(row$faces))"no_face"else if(length(row$faces)>1)"multiple_faces"else if(isTRUE(row$faces[[1]]$valid))"single_face"else "invalid_native_output"
    brohn_require(identical(state,row$state),"Facial per-frame face support is inconsistent.")
    for(i in seq_along(row$faces)) {face<-row$faces[[i]]
      brohn_require(setequal(names(face),c("face_ordinal","valid","detection_score","bbox","au_scores","expression_scores"))&&face$face_ordinal==i&&brohn_number(face$detection_score,.5,1)&&
        setequal(names(face$au_scores),.brohn_facial_aus)&&setequal(names(face$expression_scores),.brohn_facial_categories)&&setequal(names(face$bbox),c("FaceRectX","FaceRectY","FaceRectWidth","FaceRectHeight")),"Facial output contains an unsupported identity or vocabulary.")
      values<-c(face$au_scores,face$expression_scores)
      brohn_require(all(vapply(values,function(x)is.null(x)||brohn_number(x,0,1),logical(1)))&&identical(face$valid,all(vapply(c(face$bbox,values),function(x)!is.null(x),logical(1)))),"Facial native validity or missing scores changed.")
    }
  }
  indices<-vapply(rows,`[[`,numeric(1),"frame_index");times<-vapply(rows,`[[`,numeric(1),"time_s")
  brohn_require(all(diff(indices)==a$parameters$frame_stride)&&all(diff(times)>0),"Facial frame order, stride or timing changed.")
  states<-table(factor(vapply(rows,`[[`,character(1),"state"),levels=.brohn_facial_states))
  brohn_require(all(vapply(seq_along(states),function(i)as.numeric(states[[i]])==brohn_default(a$quality$states[[names(states)[[i]]]],0),logical(1)))&&
    sum(vapply(rows,`[[`,numeric(1),"face_count"))==a$quality$face_observations,"Complete face support differs from the saved summary.")
  eligible<-Filter(function(x)isTRUE(x$eligible),rows)
  if(length(eligible))for(f in a$features){vals<-vapply(eligible,function(x){face<-x$faces[[1]];c(face$au_scores,face$expression_scores)[[f$metric]]},numeric(1));brohn_require(abs(mean(vals)-f$value)<=1e-12,"Facial aggregate differs from all eligible complete native values.")}
  csv<-utils::read.csv(paths[["facial-values"]],colClasses="character",check.names=FALSE,na.strings=NULL,stringsAsFactors=FALSE)
  headers<-c("frame_index","source_pts","source_time_base","source_pts_s","relative_time_numerator","relative_time_denominator","time_s","state","face_count","eligible","face_ordinal","face_valid","FaceRectX","FaceRectY","FaceRectWidth","FaceRectHeight","FaceScore",.brohn_facial_aus,.brohn_facial_categories)
  brohn_require(identical(names(csv),headers)&&nrow(csv)==sum(vapply(rows,function(x)max(1,x$face_count),numeric(1))),"Complete facial CSV header or count differs from native frames.")
  index<-0L
  compare<-function(actual,expected){if(is.null(expected))return(identical(actual,""));if(is.logical(expected))return(identical(actual,if(expected)"True"else "False"));if(is.numeric(expected))return(isTRUE(suppressWarnings(as.numeric(actual))==expected));identical(actual,expected)}
  for(row in rows)for(face in if(length(row$faces))row$faces else list(NULL)) {
    index<-index+1L;expected<-row[c("frame_index","source_pts","source_time_base","source_pts_s","time_s","state","face_count","eligible")]
    expected$relative_time_numerator<-row$relative_time$numerator;expected$relative_time_denominator<-row$relative_time$denominator
    if(!is.null(face))expected<-c(expected,list(face_ordinal=face$face_ordinal,face_valid=face$valid,FaceScore=face$detection_score),face$bbox,face$au_scores,face$expression_scores)
    brohn_require(all(vapply(headers,function(k)compare(csv[[k]][[index]],expected[[k]]),logical(1))),"Complete facial CSV changed an exact source token, native value or missing cell.")
  }
  invisible(TRUE)
}
brohn_run_facial_expression <- function(input,scratch) {
  request<-brohn_facial_expression_request(input,scratch);request_path<-file.path(scratch,"facial-request.json");result_path<-file.path(scratch,"facial-result.json")
  brohn_write_json_file(request,request_path)
  process<-processx::run(brohn_python_profile("facial-au"),c("scripts/workers/facial_expression.py","--request",request_path,"--output",result_path),timeout=30*60,echo=FALSE,error_on_status=FALSE,cleanup_tree=TRUE,windows_hide_window=TRUE)
  brohn_require(file.exists(result_path),paste("The optional facial worker returned no result.",substr(process$stderr,1,1000)))
  result<-brohn_read_json_file(result_path)
  brohn_require(process$status==0&&identical(result$status,"completed"),paste("Local facial processing needs attention:",brohn_default(result$error$message,substr(process$stderr,1,1500))))
  brohn_validate_facial_result(result,request)
  result
}

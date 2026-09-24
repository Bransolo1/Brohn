# Hand-authored contract evidence. No inference or empirical model validation.
source("R/platform-load.R",encoding="UTF-8");brohn_load(ui=TRUE)
source("R/platform-facial-expression.R",encoding="UTF-8");source("R/platform-facial-expression-views.R",encoding="UTF-8")
args<-commandArgs(trailingOnly=TRUE);folder<-if(length(args))normalizePath(args[[1]],winslash="/",mustWork=FALSE)else tempfile("brohn-facial-domain-")
stopifnot(!dir.exists(folder));dir.create(folder,recursive=TRUE);dir.create(file.path(folder,"artifacts"))
checks<-character();check<-function(label,value){stopifnot(isTRUE(value));checks<<-c(checks,label);cat("PASS",label,"\n")}
rejects<-function(expr)inherits(try(force(expr),silent=TRUE),"try-error")
original<-file.path(folder,"original-contract-bytes.mkv");writeBin(charToRaw("Hand-authored source bytes for contract only; not a decodable video."),original)
m<-list(profile=.brohn_facial_profile,origin_statement="Original hand-written software contract.",consent_statement="Synthetic domain records without a human recording; no inference is performed.",start_s="0",frame_stride=1L,max_support_gap_s=.25)
dataset<-list(modality="video",source=list(format="mkv",hash=digest::digest(file=original,algo="sha256")),metadata=m)
input<-list(operation="analyse_dataset",dataset=dataset,source_path=original)
r<-brohn_facial_expression_request(input,folder)
check("Frozen request retains explicit permission and exact authored settings",.brohn_facial_same(r$metadata,m))
check("Ordinary decimal0.25 and exact600 are accepted",.brohn_facial_decimal("0.25")&&.brohn_facial_decimal("600"))
check("600.0001 is beyond the supported exact upper bound",!.brohn_facial_decimal("600.0001"))
for(field in c("consent_statement","origin_statement")){d<-dataset;d$metadata[[field]]<-" ";check(paste("Blank",field,"refused"),rejects(brohn_validate_facial_mapping(d)))}
for(pair in list(c("0.100000000000000001","0.100000000000000002"),c("599.999999999999999999","600"))){d<-dataset;d$metadata$start_s<-pair[[1]];d$metadata$end_s<-pair[[2]];check(paste("Exact decimal ordered window",pair[[1]]),!rejects(brohn_validate_facial_mapping(d)))}
for(bounds in list(c("600.0000000000000000000001","600"),c("0.100000000000000002","0.100000000000000001"),c("1e-2","1"))){d<-dataset;d$metadata$start_s<-bounds[[1]];d$metadata$end_s<-bounds[[2]];check(paste("Unsupported decimal boundary",bounds[[1]],"refused"),rejects(brohn_validate_facial_mapping(d)))}
d<-dataset;d$metadata$start_s<-.1;check("Numeric input cannot erase authored decimal precision",rejects(brohn_validate_facial_mapping(d)))
d<-dataset;d$metadata$emotion_score<-TRUE;check("Unregistered psychological field refused",rejects(brohn_validate_facial_mapping(d)))
d<-dataset;d$metadata$frame_stride<-1.5;check("Fractional frame stride refused",rejects(brohn_validate_facial_mapping(d)))
face<-function(i=1,valid=TRUE){aus<-stats::setNames(rep(list(0),20),.brohn_facial_aus);if(!valid)aus["AU01"]<-list(NULL)
  list(face_ordinal=i,valid=valid,detection_score=.9,bbox=list(FaceRectX=10,FaceRectY=5,FaceRectWidth=100,FaceRectHeight=100),au_scores=aus,
    expression_scores=stats::setNames(c(rep(list(0),6),list(1)),.brohn_facial_categories))}
faces<-list(list(),list(face()),list(face(),face(2)),list(face(valid=FALSE)),list(face()))
states<-c("no_face","single_face","multiple_faces","invalid_native_output","single_face")
rows<-lapply(0:4,function(i)list(frame_index=i,source_pts=as.character(2000+i*40),source_time_base="1/1000",source_pts_s=sprintf("%.2f",2+i*.04),
  source_time=list(numerator=as.character(2000+i*40),denominator="1000"),relative_time=list(numerator=as.character(i*40),denominator="1000"),
  time_s=i*.04,decoded_rgb_sha256=strrep("a",64),state=states[[i+1]],face_count=length(faces[[i+1]]),eligible=states[[i+1]]=="single_face",faces=faces[[i+1]]))
json_path<-file.path(folder,"artifacts/frames.jsonl");writeLines(vapply(rows,brohn_json,character(1)),json_path,useBytes=TRUE)
headers<-c("frame_index","source_pts","source_time_base","source_pts_s","relative_time_numerator","relative_time_denominator","time_s","state","face_count","eligible","face_ordinal","face_valid","FaceRectX","FaceRectY","FaceRectWidth","FaceRectHeight","FaceScore",.brohn_facial_aus,.brohn_facial_categories)
csv_rows<-list()
for(row in rows)for(f in if(length(row$faces))row$faces else list(NULL)){
  x<-row[intersect(names(row),headers)];x$relative_time_numerator<-row$relative_time$numerator;x$relative_time_denominator<-row$relative_time$denominator
  if(!is.null(f))x<-c(x,list(face_ordinal=f$face_ordinal,face_valid=f$valid,FaceScore=f$detection_score),f$bbox,f$au_scores,f$expression_scores)
  csv_rows[[length(csv_rows)+1L]]<-stats::setNames(vapply(headers,function(k){v<-x[[k]];if(is.null(v))""else if(is.logical(v))if(v)"True"else "False"else as.character(v)},character(1)),headers)
}
csv_path<-file.path(folder,"artifacts/values.csv");utils::write.csv(do.call(rbind,csv_rows),csv_path,row.names=FALSE,na="")
artifact<-function(path,kind,type)list(kind=kind,path=normalizePath(path,winslash="/"),sha256=digest::digest(file=path,algo="sha256"),bytes=as.numeric(file.info(path)$size),media_type=type,complete=TRUE,schema="brohn-facial-observations/1.0")
engine<-list(name="Py-Feat Detectorv1",version="2.0.0",models=brohn_read_json_file("scripts/readiness/facial-models.json")$files)
for(pair in list(c("manifest_sha256","scripts/readiness/facial-models.json"),c("runtime_manifest_sha256","scripts/readiness/facial-runtime.json"),c("requirements_sha256","scripts/readiness/requirements-facial-au.txt"),c("provider_sha256","scripts/workers/facial_expression.py"),c("video_inspector_sha256","scripts/workers/vision.py")))engine[[pair[[1]]]]<-digest::digest(file=pair[[2]],algo="sha256")
requirements<-readLines("scripts/readiness/requirements-facial-au.txt",warn=FALSE);requirements<-requirements[nzchar(requirements)&!startsWith(requirements,"#")];engine$packages<-list()
for(x in strsplit(requirements,"==",fixed=TRUE))engine$packages[[x[[1]]]]<-x[[2]]
a<-list(schema="brohn-facial-expression-result/1.0",status="completed",kind="facial_expression",source=list(sha256=r$source_hash,bytes=as.numeric(file.info(original)$size)),engine=engine,
  parameters=c(m,list(identity_model=NULL,gaze_model=NULL,pose_model=NULL,device="cpu",threads=1,face_detection_threshold=.5,source_time_base="1/1000")),
  quality=list(source_frames=5,interval_frames=5,analysed_frames=5,skipped_interval_frames=0,face_observations=5,eligible_single_face_frames=2,
    states=list(no_face=1,single_face=2,multiple_faces=1,invalid_native_output=1),eligible_time_s=0,eligible_time_exact=list(numerator="0",denominator="1"),identity_tracking=FALSE,pts_validated=TRUE,preview_frames=5,preview_truncated=FALSE,usable=TRUE),
  features=lapply(c(.brohn_facial_aus,.brohn_facial_categories),function(k)list(family=if(k%in%.brohn_facial_aus)"action_unit"else "native_expression_category",metric=k,value=if(k=="neutral")1 else 0,
    unit="native_model_score_0_1",aggregation="arithmetic_mean_eligible_sampled_frames",valid_frames=2,valid_time_s=0,time_weighted_mean=NULL,scope="selected_recording_window")),
  preview=rows,artifacts=list(artifact(json_path,"facial-observations","application/x-ndjson"),artifact(csv_path,"facial-values","text/csv")))
check("Complete original JSONL and every CSV cell reconcile across missing single multiple and invalid faces",!rejects(brohn_validate_facial_result(a,r)))
check("Valid zero AU values remain measured zeros",identical(a$features[[1]]$value,0)&&is.null(a$features[[1]]$time_weighted_mean))
for(k in c("provider_sha256","manifest_sha256","runtime_manifest_sha256","requirements_sha256","video_inspector_sha256")){b<-a;b$engine[[k]]<-strrep("b",64);check(paste("Changed",k,"refused"),rejects(brohn_validate_facial_result(b,r)))}
for(k in c("identity_model","gaze_model","pose_model")){b<-a;b$parameters[[k]]<-"enabled";check(paste("Unexpected",k,"refused"),rejects(brohn_validate_facial_result(b,r)))}
b<-a;b$parameters$consent_statement<-"Different";check("Changed processing permission refused",rejects(brohn_validate_facial_result(b,r)))
b<-a;b$source$sha256<-strrep("b",64);check("Substituted original video refused",rejects(brohn_validate_facial_result(b,r)))
b<-a;b$features[[1]]$value<-.1;check("Aggregate cannot replace measured zero with another value",rejects(brohn_validate_facial_result(b,r)))
b<-a;b$preview[[1]]$state<-"single_face";check("Preview cannot label missing face as supported",rejects(brohn_validate_facial_result(b,r)))
b<-a;b$artifacts[[2]]$complete<-FALSE;check("Partial CSV cannot be published as complete",rejects(brohn_validate_facial_result(b,r)))
b<-a;b$artifacts[[2]]$media_type<-"application/x-ndjson";check("CSV keeps its actual media type",rejects(brohn_validate_facial_result(b,r)))
original_csv<-readBin(csv_path,"raw",n=file.info(csv_path)$size);changed<-utils::read.csv(csv_path,colClasses="character",check.names=FALSE,na.strings=NULL);changed$AU01[[1]]<-"0";utils::write.csv(changed,csv_path,row.names=FALSE,na="")
b<-a;b$artifacts[[2]]<-artifact(csv_path,"facial-values","text/csv");check("Even a newly rehashed CSV cannot convert no-face missingness to zero",rejects(brohn_validate_facial_result(b,r)));writeBin(original_csv,csv_path)
ui<-as.character(brohn_facial_report_ui(a));check("Researcher view names coverage, native labels, complete downloads and exact values",all(vapply(c("Facial processing coverage","Native expression-category scores","Native action-unit scores","Complete processing artifacts","Exact category values and support"),function(x)grepl(x,ui,fixed=TRUE),logical(1))))
check("Accessible SVG exposes all27 original measures with unique title IDs",length(regmatches(ui,gregexpr('data-metric=',ui,fixed=TRUE))[[1]])==27L&&grepl('facial-categories-title',ui,fixed=TRUE)&&grepl('facial-aus-title',ui,fixed=TRUE))
check("Mapping requires explicit permission confirmation",rejects(brohn_facial_mapping_input(list(map_facial_confirm=FALSE),"test")))
check("Existing geometry results do not accidentally enter facial view",is.null(brohn_facial_report_ui(list(schema="brohn-vision-result/1.0",kind="video"))))
brohn_write_json_file(list(passed=TRUE,checks=as.list(checks),scope="Hand-authored domain records and exact artifact checks; no native inference, human recording or model-validity claim."),file.path(folder,"results.json"))
cat(length(checks),"facial domain checks passed\n")

# Exact application callback ASTs on a real Shiny HTTP dispatcher. Backend,
# selection and native-resource dependencies below are explicit synthetic spies.
args<-commandArgs(TRUE);stopifnot(length(args)==3L)
root<-normalizePath(args[[1L]],winslash="/",mustWork=TRUE)
out<-normalizePath(args[[2L]],winslash="/",mustWork=TRUE);port<-as.integer(args[[3L]])
app<-new.env(parent=globalenv())
for(name in c("core","http-response","gaze-trace-views"))sys.source(file.path(root,"R",paste0("platform-",name,".R")),envir=app)
stopifnot(!exists("$<-.brohn_http_identity_headers",globalenv(),inherits=FALSE))
registry<-list(
 c("answer-session","answer-session-views",1,"key"),c("audio-extraction","audio-extraction-views",1,"key"),
 c("audio-review","audio-review-views",1,"key"),c("clock-window","clock-dispatch-views",1,"key"),
 c("clock-plot","clock-plot-review-views",1,"key"),c("eda-continuous","eda-continuous-review-views",1,"key"),
 c("eda-event","eda-review-views",1,"key"),c("emg","emg-review-views",1,"key"),
 c("facial-image","facial-review-views",1,"key"),c("facial-csv","facial-review-views",2,"key"),
 c("gaze","gaze-trace-server",1,"trace_key"),c("linked","linked-review-views",1,"key"),
 c("material","material-views",1,"material_key"),c("media","media-review-views",1,"key"),
 c("paired","paired-plot-views",1,"paired_key"),c("respiration","respiration-review-views",1,"key"),
 c("signal","signal-value-views",1,"values_key"),c("vision-image","vision-explorer-views",1,"frame_key"),
 c("vision-csv","vision-explorer-views",2,"csv_key"))
extract<-function(path){found<-list();walk<-function(x){
 if(missing(x))return()
 if(!is.call(x)&&!is.expression(x)&&!is.pairlist(x))return()
 if(is.call(x)&&identical(x[[1L]],as.name("function"))&&identical(names(x[[2L]]),c("data","req"))&&grepl("REQUEST_METHOD",paste(deparse(x),collapse="\n"),fixed=TRUE))found[[length(found)+1L]]<<-x
 invisible(lapply(as.list(x),walk))
 };walk(parse(path,keep.source=FALSE));found}
body<-as.raw(rep(0:249,400L));stopifnot(length(body)==100000L)
file<-file.path(out,"synthetic-retained.bin");writeBin(body,file)
file_hash<-digest::digest(file=file,algo="sha256")
unicode<-enc2utf8(paste0("original ",intToUtf8(c(0x00E9,0x2014,0x1F9E0))))
gaze_view<-list(schema="brohn-gaze-trace-preview/1.0",trace_profile="gaze-pupil-source-trace/1.0",status="available",selected_rows=1,
 table=list(identity=list(participant_id=unicode),expected_rows=1,support=list(trace_profile="gaze-pupil-source-trace/1.0",generic_line_preview="forbidden_use_dedicated_gaze_adapter",pupil_column="pupil",pupil_unit="mm",baseline=list(mean=2))),
 rows=list(list(analysis_time_ms=10,row_index=0,source_row=1,effective_pupil_valid=TRUE,phase=unicode,pupil=2.5,pupil_minus_baseline=.5,passive=TRUE)),range=list(start_ms=10,end_ms=10))
gaze_svg<-app$brohn_gaze_trace_export_svg(gaze_view)
stopifnot(identical(charToRaw(gaze_svg),charToRaw(enc2utf8(gaze_svg))),grepl(unicode,gaze_svg,fixed=TRUE))
paired_svg<-enc2utf8(paste0('<svg xmlns="http://www.w3.org/2000/svg"><text>',unicode,'</text></svg>'))
writeBin(charToRaw(gaze_svg),file.path(out,"expected-gaze.svg"));writeBin(charToRaw(paired_svg),file.path(out,"expected-paired.svg"))
all_routes<-list();bindings<-list();extractions<-list();host<-new.env();host$allowed<-TRUE;host$checks<-0L
for(spec in registry){
 label<-spec[[1L]];module<-spec[[2L]];index<-as.integer(spec[[3L]]);query<-spec[[4L]]
 path<-file.path(root,"R",paste0("platform-",module,".R"));callbacks<-extract(path)
 expected_count<-if(module%in%c("facial-review-views","vision-explorer-views"))2L else 1L
 stopifnot(length(callbacks)==expected_count,index<=length(callbacks))
 callback_ast<-callbacks[[index]]
 stopifnot(grepl("brohn_http_identity_response",paste(deparse(callback_ast),collapse="\n"),fixed=TRUE)||label=="material")
 extractions[[label]]<-list(path=paste0("R/platform-",module,".R"),index=index,matched_callbacks=length(callbacks),source_sha256=digest::digest(file=path,algo="sha256"),callback_sha256=digest::digest(paste(deparse(callback_ast),collapse="\n"),algo="sha256",serialize=FALSE))
 variants<-switch(label,gaze=c("complete","window","svg"),paired=c("json","csv","means","differences"),"file")
 for(variant in variants)local({
  key<-paste(label,variant,sep="-");e<-new.env(parent=app);s<-new.env();s$allowed<-TRUE;s$authority_calls<-0L;s$native_calls<-0L;s$requests<-0L;s$errors<-character()
  gate<-function(value=NULL){s$authority_calls<-s$authority_calls+1L;stopifnot(s$allowed);value}
  e$store<-list(synthetic=TRUE);e$path<-file;e$name<-"synthetic.csv";e$o<-list(kind="synthetic");e$kind<-"synthetic";e$download<-TRUE;e$generation<-1L
  e$issue<-function(value){s$errors<-c(s$errors,as.character(value))}
  e$.Call<-function(...){s$native_calls<-s$native_calls+1L;gate(TRUE)}
  e$brohn_object_path<-function(...)file
  e$.brohn_sv_hash<-app$brohn_hash;e$.brohn_cm_same<-identical;e$.brohn_cm_ref<-function(x)x$ref
  id<-paste0("saved-",label);ref<-list(kind="saved",id=id,revision=1L,hash=file_hash,media_type="application/octet-stream")
  artifact<-list(kind="original",file="synthetic.bin",path=file,media_type="application/octet-stream")
  saved<-list(id=id,report_id="saved-report",download_token="fixture-token",ref=ref,
   body=list(request=list(artifact=list(sha256=file_hash)),result=gaze_view,result_object=list(hash=file_hash),csv_object=list(hash=file_hash)))
  e$a<-artifact;e$artifact<-artifact;e$descriptor<-artifact;e$ref<-ref
  e$r<-list(path=file,sha256=file_hash)
  guard<-list(native=list(check="explicit-synthetic-native-check"),pointer="explicit-synthetic-pointer")
  e$native<-list(guard=guard,plot_handle="synthetic-handle")
  e$checks<-list(preview=list(process=NULL,guards=list(guard)),export=list(process=NULL,record=saved,guards=list(guard)),csv="synthetic-csv")
  e$retained<-list(exports=list(json=list(path=file,size=as.numeric(length(body)),hash=file_hash),csv=list(path=file,size=as.numeric(length(body)),hash=file_hash)))
  e$v<-list(generation=1L,plot_pending=list())
  e$guard<-function(...)gate(saved);e$active<-function()gate(saved);e$current<-function(...)gate(saved)
  e$preview<-function()saved;e$exported<-function()saved;e$csv<-function()list(path=file,sha256=file_hash)
  e$csv_ready<-function()list(result=list(sha256=file_hash));e$unchanged<-function(...)gate(saved);e$download_guard<-function()gate(saved)
  e$image<-function()list(record=list(id=id),authority=list(path=file));e$detail<-function()list(frame=list(frame_index=1),observation=list(frame_index=1))
  e$input<-list(facial_frame=1)
  e$brohn_check_facial_frame_context<-function(...)gate(TRUE);e$brohn_check_vision_frame_context<-function(...)gate(TRUE)
  e$brohn_poll_facial_csv<-function(...)gate(list(path=file));e$brohn_poll_vision_csv<-function(...)gate(list(path=file))
  e$brohn_hosted_require_session<-function(...)gate(TRUE);e$brohn_signal_values_record<-function(...)gate(saved)
  e$brohn_clock_plot_resources_current<-function(...)gate(list(record=saved,artifact=artifact))
  e$people_page<-function(...)1L;e$brohn_paired_plot_svg<-function(...)paired_svg
  e$record<-function()gate(list(body=list()));e$dialog<-function()list(token="fixture-token")
  e$brohn_material_target<-function(...)list(material=list(asset=list(hash=file_hash,size=as.numeric(length(body)),media_type="application/octet-stream")))
  e$brohn_material_preview_type<-function(...)"image"
  if(label=="material"){
   expressions<-parse(path,keep.source=FALSE);hit<-Filter(function(x)is.call(x)&&identical(x[[1]],as.name("<-"))&&identical(x[[2]],as.name(".brohn_material_response")),as.list(expressions));stopifnot(length(hit)==1L);eval(hit[[1]],e)
  }
  if(label=="clock-window")e$active<-function()gate(list(record=saved,artifacts=list(artifact)))
  callback<-eval(callback_ast,e)
  data<-list(id=id,token="fixture-token",hash=if(label=="gaze")app$brohn_hash(saved$body)else if(label=="signal")app$brohn_hash(saved$body)else file_hash,kind=variant,ref=ref)
  if(label=="paired")data$token<-saved$download_token
  expected<-if(label=="gaze"&&variant=="svg")charToRaw(gaze_svg)else if(label=="paired"&&variant%in%c("means","differences"))charToRaw(paired_svg)else body
  expected_path<-if(label=="gaze"&&variant=="svg")"expected-gaze.svg"else if(label=="paired"&&variant%in%c("means","differences"))"expected-paired.svg"else"synthetic-retained.bin"
  bindings[[key]]<<-list(callback=callback,data=data,state=s,query=query)
  all_routes[[key]]<<-list(label=key,site=label,variant=variant,query=query,expected_file=expected_path,bytes=length(expected),sha256=digest::digest(expected,algo="sha256",serialize=FALSE))
 })
}
stopifnot(length(extractions)==19L,length(bindings)==24L)
host_path<-file.path(root,"R/platform-hosted-profile-views.R");host_ast<-Filter(function(x)is.call(x)&&identical(x[[1]],as.name("<-"))&&identical(x[[2]],as.name("brohn_guard_hosted_http")),as.list(parse(host_path,keep.source=FALSE)));stopifnot(length(host_ast)==1L)
host_env<-new.env(parent=app);host_env$brohn_hosted_require_session<-function(...){host$checks<-host$checks+1L
 if(!host$allowed)writeLines(jsonlite::toJSON(list(hosted_checks=host$checks,requests=lapply(bindings,function(b)b$state$requests)),auto_unbox=TRUE),file.path(out,"hosted-refusal-counters.json"),useBytes=TRUE)
 stopifnot(host$allowed);TRUE};eval(host_ast[[1]],host_env)
manifest<-list(schema="brohn-http-routes-fixture/0.1",sites=extractions,routes=all_routes,hosted_source_sha256=digest::digest(file=host_path,algo="sha256"),helper_sha256=digest::digest(file=file.path(root,"R/platform-http-response.R"),algo="sha256"),gaze_svg_encoding=Encoding(gaze_svg),scope="Exact extracted application callbacks and actual hosted guard installer on real Shiny HTTP. Backend/current-selection/native dependencies are declared synthetic spies; no genuine native publication or authorization qualification.")
writeLines(jsonlite::toJSON(manifest,auto_unbox=TRUE,pretty=TRUE),file.path(out,"fixture.json"),useBytes=TRUE)
ui<-shiny::fluidPage(shiny::uiOutput("links"))
server<-function(input,output,session){
 links<-lapply(names(bindings),function(key){b<-bindings[[key]]
  wrapped<-function(data,req){b$state$requests<-b$state$requests+1L;b$callback(data,req)}
  url<-session$registerDataObj(key,b$data,wrapped)
  shiny::tags$a(key,id=key,href=paste0(url,"&",b$query,"=",b$data$token))})
 control<-session$registerDataObj("fixture-control",list(),function(data,req){q<-shiny::parseQueryString(req$QUERY_STRING)
  if(identical(q$action,"revoke"))bindings[[q$site]]$state$allowed<-FALSE
  if(identical(q$action,"hosted-revoke"))host$allowed<-FALSE
  states<-lapply(bindings,function(b)as.list(b$state));app$brohn_http_identity_response(structure(list(status=200L,content_type="application/json",content=as.character(jsonlite::toJSON(list(states=states,hosted_checks=host$checks),auto_unbox=TRUE)),headers=list()),class="httpResponse"))})
 links[[length(links)+1L]]<-shiny::tags$a("control",id="fixture-control",href=control)
 output$links<-shiny::renderUI(shiny::tagList(links))
 host_env$brohn_guard_hosted_http(session,list(hosted_profile=list(synthetic=TRUE)))
}
later::later(function()quit(save="no",status=0),90)
shiny::runApp(list(ui=ui,server=server),host="127.0.0.1",port=port,launch.browser=FALSE)

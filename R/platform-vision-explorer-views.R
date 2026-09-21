# Saved video measurements: bounded complete-index access and genuine recorded pixels.
.brohn_vui_family<-function(x)switch(x,face="Face geometry",pose="Body pose",hands="Hand geometry",x)
.brohn_vui_label<-function(x)gsub("_"," ",gsub("([a-z])([A-Z])","\\1 \\2",x))
.brohn_vui_action<-function(label,action,payload=list(),primary=FALSE)shiny::tags$button(type="button",class=if(primary)"btn btn-primary"else"btn btn-outline-secondary",
  `data-vision-action`=action,`data-vision-payload`=brohn_json(payload),label)
.brohn_vui_table<-function(rows,label)shiny::tagList(shiny::p(class="brohn-muted","Scroll horizontally for every exact value. Keyboard: focus the table and use the arrow keys."),brohn_table(rows,label=label))
.brohn_vui_metric_label<-function(metric)paste(.brohn_vui_label(sub("^[^.]+[.]","",metric$id)),"(",metric$unit,")")
.brohn_vui_number<-function(x)format(x,digits=5,trim=TRUE,scientific=FALSE)

brohn_vision_plot_svg<-function(plot,width=820) {
  width<-max(280,min(900,width));left<-58;right<-width-15;top<-22;bottom<-210
  points<-unlist(lapply(plot$fragments,`[[`,"points"),recursive=FALSE)
  stamps<-unlist(lapply(plot$states,function(s)c(as.numeric(s$first_time_text),as.numeric(s$last_time_text))))
  if(!length(stamps))return(shiny::p("No analysed frames fall in this exact range."))
  xr<-range(stamps);if(diff(xr)==0)xr<-xr+c(-.01,.01)
  ys<-vapply(points,function(p)p$y,numeric(1));yr<-if(length(ys))range(ys)else c(0,1)
  if(diff(yr)==0)yr<-yr+c(-1,1)*max(.001,abs(yr[[1]])*.05)
  sx<-function(x)left+(x-xr[[1]])/diff(xr)*(right-left);sy<-function(y)bottom-(y-yr[[1]])/diff(yr)*(bottom-top)
  numeric<-if(length(points))shiny::tags$svg(xmlns="http://www.w3.org/2000/svg",viewBox=paste(0,0,width,262),width="100%",role="img",
    `aria-label`=paste("Saved",brohn_default(plot$metric$id,"measurement"),"over recording-relative seconds"),class="vision-chart",
    shiny::tags$desc("Only original saved values passing the metric's saved rules are plotted. Separate paths preserve missing observations, skipped frames and saved support gaps."),
    lapply(seq(yr[[1]],yr[[2]],length.out=4),function(y)shiny::tagList(shiny::tags$line(x1=left,x2=right,y1=sy(y),y2=sy(y),stroke="#3f5058"),shiny::tags$text(x=left-5,y=sy(y)+4,`text-anchor`="end",fill="#d2dedd",`font-size`=10,.brohn_vui_number(y)))),
    lapply(plot$fragments,function(f){p<-f$points;xy<-vapply(p,function(x)paste(sx(x$x),sy(x$y),sep=","),character(1));shiny::tagList(
      shiny::tags$polyline(points=paste(xy,collapse=" "),fill="none",stroke="#a7e9d3",`stroke-width`=1.8),
      if(length(p)==1L)shiny::tags$circle(cx=sx(p[[1]]$x),cy=sy(p[[1]]$y),r=3,fill="#a7e9d3"))}),
    lapply(seq(xr[[1]],xr[[2]],length.out=if(width<500)2 else 5),function(x)shiny::tags$text(x=sx(x),y=231,`text-anchor`="middle",fill="#d2dedd",`font-size`=11,.brohn_vui_number(x))),
    shiny::tags$text(x=left,y=13,fill="#edf5f3",`font-size`=11,brohn_default(plot$metric$unit,"Saved value")),
    shiny::tags$text(x=(left+right)/2,y=254,`text-anchor`="middle",fill="#edf5f3",`font-size`=12,"Recording-relative time (s)"))else shiny::p("No values pass this metric's saved rules in the selected range. The observed frame states remain available.")
  timeline<-shiny::tags$svg(xmlns="http://www.w3.org/2000/svg",viewBox=paste(0,0,width,100),width="100%",role="img",`aria-label`="Observed frame states over recording-relative time",class="vision-chart",
    shiny::tags$desc("Each mark represents observed frames in a time bucket; empty intervals are left blank. Mixed buckets are distinct. Counts, not filled duration, define this timeline."),
    lapply(plot$states,function(s){mixed<-length(s$states)>1L;good<-s$valid_frames==s$frames;color<-if(mixed)"#b8b0ea"else if(good)"#a7e9d3"else"#e8c87a"
      shiny::tags$rect(x=sx(as.numeric(s$first_time_text))-1.5,y=15,width=max(3,sx(as.numeric(s$last_time_text))-sx(as.numeric(s$first_time_text))),height=35,fill=color,
        shiny::tags$title(paste(s$frames,"frames;",paste(paste(names(s$states),unlist(s$states)),collapse=", "),";",s$first_time_text,"to",s$last_time_text,"seconds")))}),
    lapply(seq(xr[[1]],xr[[2]],length.out=if(width<500)2 else 5),function(x)shiny::tags$text(x=sx(x),y=69,`text-anchor`="middle",fill="#d2dedd",`font-size`=11,.brohn_vui_number(x))),
    shiny::tags$text(x=(left+right)/2,y=92,`text-anchor`="middle",fill="#edf5f3",`font-size`=12,"Recording-relative time (s)"))
  shiny::tagList(numeric,shiny::h4("Observed frame states"),timeline,shiny::p("Mint: every observed frame passes saved geometry rules. Amber: other saved states. Purple: mixed states. Blank space carries no invented duration."))
}
brohn_vision_native_points<-function(detail,channel) {
  row<-detail$observation[[channel]];if(is.null(row))return(list())
  groups<-if(channel=="hands")lapply(row$hands,function(h)list(label=paste("Hand",h$frame_index,h$handedness),points=h$landmarks,valid=rep(isTRUE(h$valid),length(h$landmarks))))else
    list(list(label=.brohn_vui_family(channel),points=row$landmarks,valid=if(channel=="pose")unlist(row$landmark_valid_mask)else rep(isTRUE(row$valid),length(row$landmarks))))
  unlist(lapply(groups,function(g)lapply(seq_along(g$points),function(i)c(list(group=g$label,point=i-1L,passes_saved_point_rule=if(length(g$valid)>=i)isTRUE(g$valid[[i]])else FALSE),g$points[[i]]))),recursive=FALSE)
}
brohn_vision_geometry_svg<-function(detail,channel,image_url=NULL,show_points=TRUE) {
  width<-detail$parameters$width;height<-detail$parameters$height;points<-brohn_vision_native_points(detail,channel)
  title<-if(is.null(image_url))"No recorded frame shown: saved normalized geometry only"else"Exact recorded frame with saved model landmarks"
  shiny::tagList(shiny::p(class="vision-image-status",title),shiny::tags$svg(xmlns="http://www.w3.org/2000/svg",viewBox=paste(0,0,width,height),width="100%",role="img",`aria-label`=title,
    preserveAspectRatio="xMidYMid meet",class="vision-recorded-frame",style="display:block;max-height:65vh;background:#1b2830;overflow:hidden",
    shiny::tags$desc("Image and coordinates use the original encoded dimensions, with no mirroring or rotation. Dots show actual saved native landmarks. Amber dots do not pass the saved point rule. Native model z is not physical depth."),
    if(!is.null(image_url))shiny::tags$image(href=image_url,x=0,y=0,width=width,height=height,preserveAspectRatio="none"),
    if(show_points)lapply(points,function(p){x<-as.numeric(p$x);y<-as.numeric(p$y);if(length(x)!=1L||length(y)!=1L||!is.finite(x)||!is.finite(y)||x<0||x>1||y<0||y>1)return(NULL)
      shiny::tags$circle(cx=x*width,cy=y*height,r=max(1.5,min(width,height)/220),fill=if(isTRUE(p$passes_saved_point_rule))"#83f4cb"else"#ffcc75",stroke="#14212a",`stroke-width`=.6,
        shiny::tags$title(paste(p$group,"point",p$point,"x",p$x,"y",p$y)))})),
    shiny::p("Saved native landmarks are rendering and image-geometry observations. They do not establish identity, emotion, attention, calibrated gaze or physical depth. Points outside the encoded image remain in exact values and are not drawn."))
}
brohn_begin_vision_csv<-function(store,opened,selection) {
  c<-opened$context;brohn_check_vision_index_context(store,opened,c$report_id,c$report_revision,c$report_hash,c$project_id)
  brohn_require(is.list(selection)&&identical(sort(names(selection)),c("metric","range"))&&!is.null(selection$metric),"Choose an exact saved measurement to export.")
  directory<-tempfile("brohn-video-export-",tmpdir=file.path(store$root,"work"));brohn_require(dir.create(directory,recursive=TRUE),"Cannot prepare the exact video export.")
  directory<-.brohn_store_contained(store,directory);parent<-normalizePath(file.path(store$root,"work"),winslash="/",mustWork=TRUE)
  brohn_require(identical(tolower(dirname(directory)),tolower(parent))&&startsWith(basename(directory),"brohn-video-export-"),"Video export work leaves its workspace.")
  success<-FALSE;held<-list();on.exit(if(!success){for(g in held).brohn_qexplorer_release(g);unlink(directory,recursive=TRUE,force=TRUE)},add=TRUE)
  b<-opened$record$body;request<-c(list(schema="brohn-vision-explorer-request/1.0",operation="export_csv",index_path=opened$authority$path,
    index=list(sha256=b$index$hash,bytes=b$index$size,manifest_sha256=b$index$manifest_sha256),binding_sha256=b$request$binding_sha256,guarded_verified=TRUE,output_path=file.path(directory,"values.csv")),selection)
  held[[1L]]<-.brohn_qexplorer_hold(opened$authority$path,b$index$size)
  request_path<-file.path(directory,"request.json");output_path<-file.path(directory,"result.json");brohn_write_json_file(request,request_path)
  process<-processx::process$new(.brohn_publication_python(),c("-B","scripts/workers/vision_explorer.py","--request",request_path,"--output",output_path),stdout="|",stderr="|",cleanup_tree=TRUE,windows_hide_window=TRUE)
  pending<-new.env(parent=emptyenv());pending$opened<-opened;pending$selection<-selection;pending$directory<-directory;pending$request<-request;pending$output_path<-output_path
  pending$state<-new.env(parent=emptyenv());pending$state$process<-process;pending$state$guards<-held;pending$state$phase<-"build";pending$state$closed<-FALSE;pending$state$result<-NULL
  lockEnvironment(pending,bindings=TRUE);success<-TRUE;pending
}
brohn_close_vision_csv<-function(pending) {
  if(!is.environment(pending)||!environmentIsLocked(pending)||isTRUE(pending$state$closed))return(invisible(NULL))
  s<-pending$state;if(!is.null(s$process)&&s$process$is_alive()){s$process$kill_tree();s$process$wait(2000)}
  for(g in s$guards).brohn_qexplorer_release(g)
  # Only begin's verified fresh direct child of workspace/work is a cleanup target.
  unlink(pending$directory,recursive=TRUE,force=TRUE);s$closed<-TRUE;invisible(NULL)
}
brohn_poll_vision_csv<-function(store,pending) {
  brohn_require(is.environment(pending)&&environmentIsLocked(pending)&&!isTRUE(pending$state$closed),"Prepare the complete selected video CSV first.")
  success<-FALSE;on.exit(if(!success)brohn_close_vision_csv(pending),add=TRUE);s<-pending$state;c<-pending$opened$context
  brohn_check_vision_index_context(store,pending$opened,c$report_id,c$report_revision,c$report_hash,c$project_id)
  for(g in s$guards).Call(g$native$check,g$pointer)
  if(identical(s$phase,"ready")){success<-TRUE;return(s$result)}
  if(s$process$is_alive()){success<-TRUE;return(NULL)}
  stderr<-s$process$read_all_error();stdout<-s$process$read_all_output()
  brohn_require(s$process$get_exit_status()==0L,paste("Complete video CSV needs attention:",substr(stderr,1,1000)))
  if(identical(s$phase,"build")) {
    result<-brohn_read_json_file(pending$output_path,2*1024^2)
    brohn_require(identical(result$schema,"brohn-vision-numeric-export/1.0")&&identical(result$binding_sha256,pending$request$binding_sha256)&&
      identical(result$metric,pending$selection$metric)&&identical(brohn_hash(result$range),brohn_hash(pending$selection$range))&&
      brohn_number(result$rows,0,36000,TRUE)&&brohn_number(result$bytes,1,256*1024^2,TRUE)&&.brohn_vexplorer_hash(result$sha256)&&
      identical(normalizePath(result$path,winslash="/",mustWork=TRUE),normalizePath(pending$request$output_path,winslash="/",mustWork=TRUE)),"The prepared CSV changed its exact source or selection.")
    s$guards[[length(s$guards)+1L]]<-.brohn_qexplorer_hold(result$path,result$bytes);s$result<-result
    code<-"import hashlib,sys;f=open(sys.argv[1],'rb');print(hashlib.file_digest(f,'sha256').hexdigest());f.close()"
    s$process<-processx::process$new(.brohn_publication_python(),c("-B","-c",code,result$path),stdout="|",stderr="|",cleanup_tree=TRUE,windows_hide_window=TRUE);s$phase<-"verify"
    success<-TRUE;return(NULL)
  }
  brohn_require(identical(trimws(stdout),s$result$sha256),"The prepared complete CSV failed verification under its native read seal.")
  s$phase<-"ready";s$process<-NULL;success<-TRUE;s$result
}
brohn_vision_csv_manifest<-function(pending) {
  brohn_require(is.environment(pending)&&!isTRUE(pending$state$closed)&&identical(pending$state$phase,"ready"),"Verify the complete CSV first.")
  b<-pending$opened$record$body;r<-pending$state$result;metric<-Filter(function(x)identical(x$id,r$metric),b$manifest$metrics)
  list(schema="brohn-vision-numeric-export-manifest/1.0",csv=list(sha256=r$sha256,bytes=r$bytes,rows=r$rows,media_type="text/csv; charset=utf-8"),
    source=b$binding,index=list(id=b$id,sha256=b$index$hash),metric=metric[[1L]],range=r$range,number_encoding=r$number_encoding,missing_value=r$missing_value,
    parameters=b$manifest$parameters,engine=b$manifest$engine,columns=list(frame_index="original zero-based decoded frame",source_pts_s="original decimal presentation seconds",
      recording_relative_s_exact="exact decimal source PTS minus declared recording origin",saved_time_s="original saved relative-time numeric token",model_timestamp_ms="saved model milliseconds",
      metric="exact saved metric identifier",value=paste("original numeric token in",metric[[1L]]$unit),states_json="original indexed channel states"))
}

brohn_install_vision_explorer<-function(input,output,session,store,state,attempt,message,prepare_download,
    register_resource=function(name,data,filter)session$registerDataObj(name,data,filter)) {
  active<-shiny::reactiveVal(NULL);selection<-shiny::reactiveVal(NULL);page<-shiny::reactiveVal(NULL);plotted<-shiny::reactiveVal(NULL);detail<-shiny::reactiveVal(NULL)
  image<-shiny::reactiveVal(NULL);image_url<-shiny::reactiveVal(NULL);job<-shiny::reactiveVal(NULL);frame_job<-shiny::reactiveVal(NULL)
  issue<-shiny::reactiveVal(NULL);epoch<-shiny::reactiveVal(brohn_token());point_offset<-shiny::reactiveVal(0L);page_history<-shiny::reactiveVal(list());current_cursor<-shiny::reactiveVal(NULL)
  checks<-new.env(parent=emptyenv());checks$index<-NULL;checks$image<-NULL;checks$csv<-NULL
  csv_ready<-shiny::reactiveVal(NULL);csv_url<-shiny::reactiveVal(NULL)
  clear_csv<-function(){if(!is.null(checks$csv))brohn_close_vision_csv(checks$csv);checks$csv<-NULL;csv_ready(NULL);csv_url(NULL)}
  current_report<-function(){brohn_require(identical(state$page,"report")&&!is.null(state$report_id),"Open a saved video report.");brohn_get_entity(store,"report",state$report_id)}
  source_key<-function(){r<-current_report();paste(r$project_id,r$id,r$revision,brohn_hash(r$body),sep=":")}
  eligible<-function()tryCatch(identical(current_report()$body$analysis$kind,"video"),error=function(e)FALSE)
  clear_image<-function(){if(!is.null(checks$image))brohn_cancel_vision_frame_open(checks$image);checks$image<-NULL
    if(!is.null(image()))brohn_close_vision_frame(image());image(NULL);image_url(NULL);frame_job(NULL)}
  clear<-function(){clear_csv();clear_image();if(!is.null(checks$index))brohn_cancel_vision_index_open(checks$index);checks$index<-NULL
    if(!is.null(active()))brohn_close_vision_index(active());active(NULL);selection(NULL);page(NULL);plotted(NULL);detail(NULL);job(NULL);epoch(brohn_token());page_history(list());current_cursor(NULL);point_offset(0L)}
  session$onSessionEnded(function(){if(!is.null(checks$csv))brohn_close_vision_csv(checks$csv);if(!is.null(checks$image))brohn_cancel_vision_frame_open(checks$image);if(!is.null(checks$index))brohn_cancel_vision_index_open(checks$index)
    shiny::isolate({if(!is.null(image()))brohn_close_vision_frame(image());if(!is.null(active()))brohn_close_vision_index(active())})})
  shiny::observeEvent(list(state$page,state$report_id),{clear();issue(NULL)},ignoreInit=FALSE,priority=100)
  protect<-function(fn)attempt(function(){issue(NULL);tryCatch(fn(),error=function(e){issue(conditionMessage(e));stop(e)})})
  guard<-function(){v<-active();brohn_require(!is.null(v),"Open and verify this saved video view first.");r<-current_report()
    brohn_check_vision_index_context(store,v,r$id,r$revision,brohn_hash(r$body),r$project_id);v}
  command<-function(cmd){brohn_require(is.list(cmd)&&identical(cmd$source,source_key())&&identical(cmd$epoch,epoch()),"Those controls belong to an earlier video view. Use this report's current controls.")}
  parse_selection<-function(fields){v<-guard();m<-v$record$body$manifest
    brohn_require(is.list(fields)&&fields$channel%in%names(m$channels),"Choose a saved geometry channel.")
    metric<-if(!nzchar(fields$metric))NULL else fields$metric
    brohn_require(is.null(metric)||any(vapply(m$metrics,function(x)identical(x$id,metric)&&identical(x$channel,fields$channel),logical(1))),"Choose a metric saved for this channel.")
    bounds<-NULL
    if(nzchar(fields$start)||nzchar(fields$end)){
      pattern<-"^[+-]?([0-9]+([.][0-9]*)?|[.][0-9]+)([eE][+-]?[0-9]+)?$"
      brohn_require(nchar(fields$start)<=128L&&nchar(fields$end)<=128L&&grepl(pattern,fields$start)&&grepl(pattern,fields$end),"Enter both finite decimal range bounds, or leave both empty.")
      bounds<-list(fields$start,fields$end)
    }
    brohn_require(fields$limit%in%c("25","50","100"),"Choose a supported page size.")
    list(channel=fields$channel,metric=metric,range=bounds,limit=as.integer(fields$limit))}
  unchanged<-function(fields){s<-parse_selection(fields);brohn_require(identical(brohn_hash(s),brohn_hash(selection())),"Apply the visible channel, metric and range changes first.");s}
  read_page<-function(cursor=NULL){v<-guard();s<-selection();value<-brohn_vision_index_read(store,v,"page",list(metric=s$metric,range=s$range,limit=s$limit,cursor=cursor))
    page(value);current_cursor(cursor);clear_image();detail(NULL);point_offset(0L);value}
  show_frame<-function(index){v<-guard();value<-brohn_vision_index_read(store,v,"detail",list(frame_index=index));clear_image();detail(value);point_offset(0L);shiny::updateTextInput(session,"vision_frame_index",value=as.character(index))}
  apply_selection<-function(s){v<-guard();clear_csv();plot<-brohn_vision_index_read(store,v,"plot",list(channel=s$channel,metric=s$metric,range=s$range,max_points=2000L))
    selection(s);plotted(plot);page_history(list());p<-read_page();if(length(p$rows))show_frame(p$rows[[1L]]$frame_index)}
  activate<-function(v){active(v);m<-v$record$body$manifest;family<-names(m$channels)[[1L]];metrics<-Filter(function(x)identical(x$channel,family),m$metrics)
    apply_selection(list(channel=family,metric=if(length(metrics))metrics[[1L]]$id else NULL,range=NULL,limit=25L))}
  output$vision_explorer<-shiny::renderUI({if(!eligible())return(NULL);r<-current_report()
    shiny::div(id="vision-explorer",class="brohn-stack",`data-source`=source_key(),`data-epoch`=epoch(),style="min-width:0;grid-template-columns:minmax(0,1fr)",
      shiny::tags$script(src="vision-explorer-ui.js"),shiny::tags$style(shiny::HTML("#vision-explorer .brohn-stack{grid-template-columns:minmax(0,1fr)}#vision-explorer .shiny-html-output{min-width:0}#vision-explorer p{overflow-wrap:anywhere}#vision-explorer button,#vision-explorer select,#vision-explorer a,#vision-explorer summary{min-height:44px}#vision-explorer summary{display:flex;align-items:center}#vision-explorer .brohn-table{max-width:100%;overflow-x:auto}#vision-explorer .brohn-table table{min-width:720px;table-layout:auto}#vision-explorer th,#vision-explorer td{white-space:nowrap;overflow-wrap:normal;word-break:normal}#vision-explorer pre{max-width:100%;overflow:auto;white-space:pre;max-height:30rem}#vision-explorer .vision-chart{display:block;max-width:100%;background:#131d24;font-family:system-ui,sans-serif}#vision-explorer .vision-recorded-frame{max-width:100%;border:1px solid #52666f}#vision-explorer .vision-image-status{font-weight:600}")),
      brohn_card(title="Explore saved video measurements",subtitle="Browse the complete saved frame observations, then inspect an exact recorded frame and its native model geometry.",
        shiny::p(paste("Saved report:",r$body$title,"|",r$body$origin,"source")),
        shiny::div(class="brohn-toolbar",.brohn_vui_action(if(is.null(active()))"Explore video measurements"else"Reopen saved video view","open",primary=TRUE),.brohn_vui_action("Rebuild derived video index","rebuild")),
        shiny::p(class="brohn-muted","Model geometry is not identity, emotion, attention, calibrated gaze or physical measurement accuracy. Original observations remain unchanged.")),
      shiny::uiOutput("vision_progress"),shiny::uiOutput("vision_controls"),shiny::uiOutput("vision_plot"),shiny::uiOutput("vision_csv_ready"),shiny::uiOutput("vision_page"),shiny::uiOutput("vision_detail"))
  })
  output$vision_controls<-shiny::renderUI({v<-active();if(is.null(v))return(NULL);m<-v$record$body$manifest;s<-shiny::isolate(selection());metrics<-Filter(function(x)identical(x$channel,s$channel),m$metrics)
    brohn_card(title="Channel and recording-relative range",shiny::p(paste(m$frames,"complete analysed frames;",length(m$metrics),"saved metrics. Source PTS origin:",m$parameters$source_pts_origin_s,"seconds.")),
      shiny::div(class="brohn-form-grid",shiny::selectInput("vision_channel","Geometry channel",setNames(names(m$channels),vapply(names(m$channels),.brohn_vui_family,character(1))),s$channel,selectize=FALSE),
        shiny::selectInput("vision_metric","Saved measurement",c("Frame states only"="",setNames(vapply(metrics,`[[`,character(1),"id"),vapply(metrics,.brohn_vui_metric_label,character(1)))),brohn_default(s$metric,""),selectize=FALSE)),
      shiny::div(class="brohn-form-grid",shiny::textInput("vision_start","First recording-relative second (included)",""),shiny::textInput("vision_end","Last recording-relative second (included)",""),
        shiny::selectInput("vision_limit","Exact rows per page",c("25"="25","50"="50","100"="100"),"25",selectize=FALSE)),
      .brohn_vui_action("Apply video view","apply",primary=TRUE),shiny::p(id="vision-pending-copy",role="status",""),
      shiny::p("Leave both bounds empty for all analysed frames. Decimal source PTS determines boundaries; the plotted coordinates are only a display."),
      shiny::tags$details(shiny::tags$summary("Saved source and model settings"),shiny::tags$pre(tabindex="0",`aria-label`="Saved video model and source settings",brohn_json(list(binding=v$record$body$binding,parameters=m$parameters,engine=m$engine),TRUE))))
  })
  shiny::observeEvent(input$vision_channel,{v<-active();if(is.null(v))return();metrics<-Filter(function(x)identical(x$channel,input$vision_channel),v$record$body$manifest$metrics)
    current<-shiny::isolate(input$vision_metric);ids<-vapply(metrics,`[[`,character(1),"id");chosen<-if(length(current)==1L&&current%in%c("",ids))current else if(length(ids))ids[[1L]]else""
    shiny::updateSelectInput(session,"vision_metric",choices=c("Frame states only"="",setNames(ids,vapply(metrics,.brohn_vui_metric_label,character(1)))),selected=chosen)},ignoreNULL=TRUE)
  shiny::observeEvent(input$vision_action,protect(function(){cmd<-input$vision_action;command(cmd);action<-cmd$action
    if(action%in%c("open","rebuild")){r<-current_report();clear();j<-brohn_queue_vision_index(store,r$id,r$revision,brohn_hash(r$body),r$project_id,rebuild=action=="rebuild")
      if(j$status%in%c("failed","cancelled"))j<-brohn_retry_processing(store,j$id);job(list(id=j$id,source=source_key(),epoch=epoch()));return()}
    if(action=="cancel"){j<-if(cmd$kind=="frame")frame_job()else job();brohn_require(!is.null(j),"No current video job.");brohn_cancel_job(store,j$id);return()}
    if(action=="retry"){j<-if(cmd$kind=="frame")frame_job()else job();brohn_require(!is.null(j),"No current video job.");brohn_retry_processing(store,j$id);return()}
    if(action=="apply"){apply_selection(parse_selection(cmd$fields));return()}
    s<-unchanged(cmd$fields)
    if(action=="export"){clear_csv();checks$csv<-brohn_begin_vision_csv(store,guard(),list(metric=s$metric,range=s$range));csv_ready(list(status="preparing"));return()}
    if(action=="cancel_export"){clear_csv();return()}
    if(action=="next"){p<-page();brohn_require(!is.null(p$next_cursor),"This is the final exact frame page.");history<-page_history();history[[length(history)+1L]]<-list(cursor=current_cursor());page_history(history);read_page(p$next_cursor);return()}
    if(action=="previous"){history<-page_history();brohn_require(length(history)>0L,"This is the first exact frame page.");old<-history[[length(history)]];page_history(head(history,-1L));read_page(old$cursor);return()}
    if(action=="frame"){text<-brohn_default(cmd$frame_index,cmd$fields$frame);brohn_require(grepl("^[0-9]{1,5}$",text),"Enter the original zero-based frame number.");show_frame(as.integer(text));return()}
    if(action%in%c("point_next","point_previous")){n<-length(brohn_vision_native_points(detail(),s$channel));point_offset(max(0L,min(max(0L,n-1L),point_offset()+if(action=="point_next")100L else -100L)));return()}
    if(action=="extract"){d<-detail();brohn_require(!is.null(d)&&identical(as.character(d$frame$frame_index),cmd$fields$frame),"Show the exact visible frame number before preparing its image.")
      clear_image();j<-brohn_queue_vision_frame(store,guard(),d$frame$frame_index);if(j$status%in%c("failed","cancelled"))j<-brohn_retry_processing(store,j$id)
      frame_job(list(id=j$id,source=source_key(),epoch=epoch(),frame_index=d$frame$frame_index));return()}
    stop("Unsupported saved video action.")
  }))
  shiny::observe({shiny::invalidateLater(600,session);shiny::isolate({
    if(!is.null(checks$csv)&&is.null(csv_ready()$result))tryCatch({r<-brohn_poll_vision_csv(store,checks$csv);if(!is.null(r))csv_ready(list(status="ready",result=r))},error=function(e){clear_csv();issue(conditionMessage(e))})
    for(kind in c("index","frame")){
      pending<-if(kind=="index")job()else frame_job();if(is.null(pending))next
      if(!eligible()||!identical(pending$source,source_key())||!identical(pending$epoch,epoch())){clear();next}
      j<-brohn_get_job(store,pending$id);if(!identical(j$status,"succeeded"))next
      tryCatch({if(kind=="index"){
          if(!is.null(active()))next
          if(is.null(checks$index)){r<-current_report();checks$index<-brohn_begin_vision_index_open(store,j$result$vision_index_id,j$result$index_hash,r$id,r$revision,brohn_hash(r$body),r$project_id)}
          opened<-brohn_poll_vision_index_open(store,checks$index);if(!is.null(opened)){checks$index<-NULL;activate(opened)}
        }else{
          if(!is.null(image()))next
          if(is.null(checks$image))checks$image<-brohn_begin_vision_frame_open(store,guard(),j$result$vision_frame_id,j$result$frame_hash,pending$frame_index)
          opened<-brohn_poll_vision_frame_open(store,checks$image);if(!is.null(opened)){checks$image<-NULL;image(opened)}
        }},error=function(e){issue(conditionMessage(e));if(kind=="index"){if(!is.null(checks$index))brohn_cancel_vision_index_open(checks$index);checks$index<-NULL;job(NULL)}else{clear_image()}})
    }
  })})
  shiny::observeEvent(image(),{saved<-image();if(is.null(saved))return();token<-brohn_token();id<-saved$record$id;selected_frame<-detail()$frame$frame_index
    url<-register_resource("brohn-recorded-video-frame",list(token=token,id=id),function(data,req)shiny::isolate(tryCatch({
      brohn_require(req$REQUEST_METHOD%in%c("GET","HEAD")&&identical(shiny::parseQueryString(brohn_default(req$QUERY_STRING,""))$frame_key,data$token)&&!is.null(image())&&identical(image()$record$id,data$id),"This recorded-frame link is no longer active.")
      brohn_check_vision_frame_context(store,image(),guard(),detail()$frame$frame_index)
      structure(list(status=200L,content_type="image/png",content=list(file=image()$authority$path,owned=FALSE),headers=list("Cache-Control"="no-store","X-Content-Type-Options"="nosniff")),class="httpResponse")
    },error=function(e)structure(list(status=404L,content_type="text/plain",content="This exact recorded frame is unavailable; reopen the selected source."),class="httpResponse"))))
    image_url(paste0(url,"&frame_key=",token))},ignoreNULL=TRUE)
  output$vision_progress<-shiny::renderUI({shiny::invalidateLater(800,session);items<-Filter(Negate(is.null),list(index=job(),frame=frame_job()))
    shiny::tagList(if(!is.null(issue()))shiny::div(role="alert",class="brohn-notice",issue()),lapply(names(items),function(kind){p<-items[[kind]];j<-brohn_get_job(store,p$id)
      done<-if(kind=="index")!is.null(active())else!is.null(image());if(done)return(NULL)
      shiny::div(class="brohn-toolbar",shiny::p(paste(if(kind=="index")"Complete video index"else"Exact recorded frame",":",if(j$status=="succeeded")"verifying saved bytes in the background"else gsub("_"," ",j$status))),
        if(!is.null(j$error$message))shiny::p(j$error$message),if(j$status%in%c("queued","running")) .brohn_vui_action("Cancel video job","cancel",list(kind=kind)),
        if(j$status%in%c("failed","cancelled")) .brohn_vui_action("Retry video job","retry",list(kind=kind))) }))
  })
  output$vision_plot<-shiny::renderUI({p<-plotted();if(is.null(p))return(NULL);s<-selection();support<-p$support
    brohn_card(title=paste(.brohn_vui_family(s$channel),"saved observations"),subtitle=if(is.null(s$metric))"Frame states only"else s$metric,
      shiny::p(paste(support$frames,"analysed frames in range;",support$channel_valid_frames,"pass saved channel rules;",support$metric_valid_frames,"have this metric.",
        support$metric_valid_time_s_text,"seconds of adjacent metric support;",support$displayed_points,"displayed original points in",support$fragment_count,"separate fragments.")),
      brohn_vision_plot_svg(p,brohn_default(input$vision_width,820)),shiny::p(p$sampling),
      .brohn_vui_table(lapply(names(support$state_counts),function(n)list(State=.brohn_vui_label(n),Frames=support$state_counts[[n]])),"Complete saved frame-state counts"),
      shiny::div(class="brohn-toolbar",if(!is.null(s$metric)).brohn_vui_action("Prepare every selected numeric row","export"),shiny::downloadButton("vision_figure","Download labelled figure (HTML)",icon=NULL)))
  })
  output$vision_page<-shiny::renderUI({p<-page();if(is.null(p))return(NULL)
    rows<-lapply(p$rows,function(r)list("Original frame"=as.character(r$frame_index),"Source PTS (s)"=r$source_pts_s,"Relative time (s, exact)"=r$relative_exact_text,
      "Saved numeric token"=brohn_default(r$value_text,"Unavailable (saved null)"),"States"=paste(vapply(names(r$states),function(c)paste(c,r$states[[c]]$state),character(1)),collapse="; ")))
    brohn_card(title="Exact frame values",subtitle=paste(p$returned,"rows on this page from",p$total,"selected analysed frames"),.brohn_vui_table(rows,"Exact saved video frame values"),
      shiny::div(class="brohn-toolbar",if(length(page_history())) .brohn_vui_action("Previous frame page","previous"),if(!is.null(p$next_cursor)) .brohn_vui_action("Next frame page","next")),
      shiny::div(class="brohn-form-grid",shiny::textInput("vision_frame_index","Original frame number (zero-based)",if(length(p$rows))as.character(p$rows[[1L]]$frame_index)else""),.brohn_vui_action("Show exact frame","frame",primary=TRUE)),
      shiny::p("Choose a frame from the complete analysed recording. Its saved timestamp and native values are shown below; no frame is interpolated from a plot."))
  })
  output$vision_detail<-shiny::renderUI({d<-detail();if(is.null(d))return(NULL);s<-selection();points<-brohn_vision_native_points(d,s$channel);start<-point_offset();shown<-head(if(start<length(points))points[seq.int(start+1L,length(points))]else list(),100L)
    rows<-lapply(shown,function(p)list(Group=p$group,"Point index"=p$point,"x (normalized)"=brohn_default(p$x,"Not supplied"),"y (normalized)"=brohn_default(p$y,"Not supplied"),
      "z (native model)"=brohn_default(p$z,"Not supplied"),Visibility=brohn_default(p$visibility,"Not supplied"),Presence=brohn_default(p$presence,"Not supplied"),"Passes saved point rule"=p$passes_saved_point_rule))
    brohn_card(title=paste("Original frame",d$frame$frame_index),subtitle=paste("Source PTS",d$frame$source_pts_s,"s | recording-relative",d$frame$relative_exact_text,"s | model",d$frame$model_timestamp_ms,"ms"),
      shiny::p(paste("Saved state:",brohn_json(d$frame$states[[s$channel]]))),
      shiny::div(class="brohn-toolbar",.brohn_vui_action("Prepare exact recorded frame","extract",primary=TRUE),shiny::downloadButton("vision_frame_json","Download exact original frame JSON",icon=NULL),
        if(!is.null(image_url()))shiny::downloadButton("vision_png","Download original frame PNG",icon=NULL)),
      shiny::checkboxInput("vision_landmarks","Show saved native landmarks",shiny::isolate(brohn_default(input$vision_landmarks,TRUE))),shiny::uiOutput("vision_geometry"),
      shiny::tags$details(shiny::tags$summary(paste("Exact native landmark values:",length(points),"saved points")),
        shiny::p(paste("Showing",length(shown),"points beginning at",start,"in this display. Point indices are native to each saved face, pose or hand.")),
        .brohn_vui_table(rows,"Exact native video landmark tokens"),shiny::div(class="brohn-toolbar",if(start>0L).brohn_vui_action("Previous landmark page","point_previous"),if(start+length(shown)<length(points)).brohn_vui_action("Next landmark page","point_next"))),
      shiny::tags$details(shiny::tags$summary("Exact original frame record"),shiny::tags$pre(tabindex="0",`aria-label`="Exact original video observation JSON",d$original_json)))
  })
  output$vision_geometry<-shiny::renderUI({d<-detail();if(is.null(d))return(NULL);brohn_vision_geometry_svg(d,selection()$channel,image_url(),brohn_default(input$vision_landmarks,TRUE))})
  download_guard<-function(){v<-guard();fields<-list(channel=input$vision_channel,metric=input$vision_metric,start=input$vision_start,end=input$vision_end,limit=input$vision_limit)
    unchanged(fields);v}
  shiny::observeEvent(csv_ready(),{r<-csv_ready();if(is.null(r$result))return();token<-brohn_token();identity<-r$result$sha256
    uri<-register_resource("brohn-saved-video-csv",list(token=token,hash=identity),function(data,req)shiny::isolate(tryCatch({
      brohn_require(req$REQUEST_METHOD%in%c("GET","HEAD")&&identical(shiny::parseQueryString(brohn_default(req$QUERY_STRING,""))$csv_key,data$token),"This CSV link is no longer active.")
      download_guard();brohn_require(!is.null(checks$csv)&&identical(csv_ready()$result$sha256,data$hash),"Prepare the current exact CSV again.")
      result<-brohn_poll_vision_csv(store,checks$csv);brohn_require(!is.null(result),"Complete CSV verification is still pending.")
      structure(list(status=200L,content_type="text/csv; charset=utf-8",content=list(file=result$path,owned=FALSE),headers=list("Content-Disposition"='attachment; filename="saved-video-values.csv"',"Cache-Control"="no-store","X-Content-Type-Options"="nosniff")),class="httpResponse")
    },error=function(e)structure(list(status=404L,content_type="text/plain",content="This exact video CSV is unavailable. Prepare the current selection again."),class="httpResponse"))))
    csv_url(paste0(uri,"&csv_key=",token))},ignoreNULL=TRUE)
  output$vision_csv_ready<-shiny::renderUI({ready<-csv_ready();if(is.null(ready))return(NULL)
    if(is.null(ready$result))return(shiny::div(role="status",shiny::p("Preparing and verifying the complete selected CSV in the background."),.brohn_vui_action("Cancel CSV preparation","cancel_export")))
    manifest<-brohn_vision_csv_manifest(checks$csv);brohn_card(title="Complete selected numeric CSV ready",shiny::p(paste(manifest$csv$rows,"source rows;",manifest$csv$bytes,"bytes;",manifest$metric$id,"in",manifest$metric$unit)),
      shiny::p("Download the companion manifest for exact report/source identity, units, recording origin, column definitions and the CSV digest."),
      shiny::div(class="brohn-toolbar",if(!is.null(csv_url()))shiny::tags$a(class="btn btn-primary",href=csv_url(),download="saved-video-values.csv","Download complete selected CSV"),shiny::downloadButton("vision_csv_manifest","Download CSV source and units manifest",icon=NULL)))
  })
  output$vision_csv_manifest<-shiny::downloadHandler(filename=function()"saved-video-values-manifest.json",content=function(file)prepare_download(function(){download_guard();brohn_poll_vision_csv(store,checks$csv);brohn_write_json_file(brohn_vision_csv_manifest(checks$csv),file)}))
  output$vision_frame_json<-shiny::downloadHandler(filename=function()paste0("original-frame-",detail()$frame$frame_index,".json"),content=function(file)prepare_download(function(){download_guard();d<-detail()
    brohn_require(!is.null(d)&&identical(as.character(d$frame$frame_index),input$vision_frame_index),"Show the visible frame number before downloading it.");writeBin(charToRaw(enc2utf8(d$original_json)),file)}))
  output$vision_png<-shiny::downloadHandler(filename=function()paste0("original-frame-",detail()$frame$frame_index,".png"),content=function(file)prepare_download(function(){v<-download_guard()
    brohn_require(identical(as.character(detail()$frame$frame_index),input$vision_frame_index),"Show the visible frame before downloading its image.")
    brohn_check_vision_frame_context(store,image(),v,detail()$frame$frame_index);brohn_require(file.copy(image()$authority$path,file,overwrite=TRUE),"Cannot deliver this exact image.")}))
  output$vision_figure<-shiny::downloadHandler(filename=function()paste0("saved-video-view-",active()$context$report_id,".html"),content=function(file)prepare_download(function(){v<-download_guard();p<-plotted()
    html<-shiny::tags$html(shiny::tags$head(shiny::tags$meta(charset="utf-8"),shiny::tags$title("Saved video measurement figure")),shiny::tags$body(style="max-width:900px;margin:2rem auto;font-family:system-ui;background:#131d24;color:#edf5f3",shiny::h1("Saved video measurement figure"),
      shiny::p(paste(v$context$report_id,"|",.brohn_vui_family(p$channel),"|",brohn_default(p$metric$id,"Frame states only"))),brohn_vision_plot_svg(p,820),shiny::p(p$sampling),
      shiny::tags$pre(brohn_json(list(source=v$record$body$binding,range=p$range,metric=p$metric,support=p$support,time_support_policy=p$time_support_policy),TRUE))))
    writeLines(paste0("<!doctype html>",as.character(html)),file,useBytes=TRUE)}))
  invisible(list(clear=clear,active=active,selection=selection,detail=detail,image=image))
}

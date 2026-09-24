# Complete retained native outputs and source pixels; no new model inference.
brohn_facial_review_entry_ui<-function(record) {
  if(!brohn_facial_supported(record$body$analysis))return(NULL)
  shiny::uiOutput("facial_review")
}
.brohn_fr_label<-function(x)if(startsWith(x,"AU"))paste(x,"native action-unit score")else paste(x,"native category score")
.brohn_fr_state<-function(x)switch(x,no_face="No detected face",single_face="One valid detected face",multiple_faces="Multiple faces (frame-local)",invalid_native_output="Incomplete native output",x)
.brohn_fr_exact<-function(r)paste0(r$relative_time$numerator,"/",r$relative_time$denominator)
.brohn_fr_axis<-function(x) {
  for(digits in 3:17){labels<-format(signif(x,digits),digits=digits,trim=TRUE,scientific=FALSE);if(!anyDuplicated(labels))return(labels)}
  sprintf("%.17g",x)
}
brohn_facial_review_svg<-function(plot,frame=NULL,width=820) {
  width<-max(280,min(900,as.numeric(width)));left<-54;right<-width-18;compact<-width<500
  pts<-plot$points;if(!length(pts))return(shiny::p("No analysed frames fall in this exact range. The original results remain unchanged."))
  stamps<-vapply(pts,function(x)as.numeric(x$time_s),numeric(1));xr<-range(stamps);if(diff(xr)==0)xr<-xr+c(-.01,.01)
  sx<-function(x)left+(x-xr[[1L]])/diff(xr)*(right-left);sy<-function(y)210-170*y;ticks<-seq(xr[[1L]],xr[[2L]],length.out=3);labels<-.brohn_fr_axis(ticks)
  shiny::tags$svg(xmlns="http://www.w3.org/2000/svg",viewBox=paste("0 0",width,340),width="100%",role="img",`aria-label`=paste("Saved",plot$metric,"scores and detection states"),style="display:block;background:#131d24;max-width:100%",
    shiny::tags$desc("Native model scores from zero to one. Only saved eligible single-face samples are connected within the original support-gap limit. This does not establish the same person's identity. Missing or multiple faces have state marks, never zero scores. Exact values are in the table."),
    lapply(seq(0,1,.25),function(y)shiny::tagList(shiny::tags$line(x1=left,x2=right,y1=sy(y),y2=sy(y),stroke="#40535a"),shiny::tags$text(x=left-8,y=sy(y)+4,`text-anchor`="end",fill="#d2dedd",`font-size`=13,format(y,trim=TRUE)))),
    lapply(seq_along(pts),function(i){r<-pts[[i]];x<-sx(as.numeric(r$time_s));color<-if(r$state=="single_face")"#a7e9d3"else if(r$state=="multiple_faces")"#c5b7f5"else"#f0ce83"
      shiny::tagList(if(i>1L&&r$connection=="adjacent_supported_sample")shiny::tags$line(x1=sx(as.numeric(pts[[i-1L]]$time_s)),y1=sy(as.numeric(pts[[i-1L]]$value)),x2=x,y2=sy(as.numeric(r$value)),stroke="#a7e9d3",`stroke-width`=2),
        if(!is.null(r$value))shiny::tags$circle(cx=x,cy=sy(as.numeric(r$value)),r=4,fill=color,shiny::tags$title(paste("Frame",r$frame_index,"exact saved score",r$value))),
        shiny::tags$rect(x=x-3,y=258,width=6,height=18,fill=color,shiny::tags$title(paste("Frame",r$frame_index,.brohn_fr_state(r$state),"relative",.brohn_fr_exact(r),"s"))))}),
    if(!is.null(frame)&&any(vapply(pts,function(p)identical(as.character(p$frame_index),as.character(frame$frame_index)),logical(1))))shiny::tags$line(x1=sx(as.numeric(frame$time_s)),x2=sx(as.numeric(frame$time_s)),y1=22,y2=280,stroke="#fff",`stroke-dasharray`="4 4"),
    shiny::tags$text(x=left,y=20,fill="#edf5f3",`font-size`=12,"Native model score (0 to 1)"),shiny::tags$text(x=left,y=247,fill="#edf5f3",`font-size`=12,if(compact)"Observed detection states"else"Detection states (observed frames only)"),
    lapply(seq_along(ticks),function(i)shiny::tags$text(x=sx(ticks[[i]]),y=303,`text-anchor`="middle",fill="#d2dedd",`font-size`=12,labels[[i]])),
    shiny::tags$text(x=(left+right)/2,y=330,`text-anchor`="middle",fill="#edf5f3",`font-size`=12,"Recording-relative time (s)"))
}
brohn_install_facial_review<-function(input,output,session,store,state,attempt,message,prepare_download) {
  active<-shiny::reactiveVal(NULL);selection<-shiny::reactiveVal(NULL);plot<-shiny::reactiveVal(NULL);detail<-shiny::reactiveVal(NULL);offset<-shiny::reactiveVal(0L)
  image<-shiny::reactiveVal(NULL);image_url<-shiny::reactiveVal(NULL);csv<-shiny::reactiveVal(NULL);csv_url<-shiny::reactiveVal(NULL);csv_pending<-shiny::reactiveVal(FALSE);issue<-shiny::reactiveVal(NULL)
  index_job<-shiny::reactiveVal(NULL);frame_job<-shiny::reactiveVal(NULL);wanted_frame<-shiny::reactiveVal(NULL);automatic<-new.env(parent=emptyenv());automatic$job<-NULL;checks<-new.env(parent=emptyenv());checks$index<-NULL;checks$image<-NULL;checks$csv<-NULL
  current<-function(){brohn_require(identical(state$page,"report")&&!is.null(state$report_id),"Open the original facial report.");brohn_report_for_review(store,state$report_id)}
  guard<-function(){v<-active();r<-current();brohn_require(!is.null(v),"Prepare and verify the saved facial view first.");brohn_check_facial_review_context(store,v,r$id,r$revision,brohn_hash(r$body),r$project_id);v}
  clear_csv<-function(){if(!is.null(checks$csv))brohn_close_facial_csv(checks$csv);checks$csv<-NULL;csv(NULL);csv_url(NULL);csv_pending(FALSE)}
  clear_image<-function(){wanted_frame(NULL);if(!is.null(checks$image))brohn_cancel_facial_frame_open(checks$image);checks$image<-NULL;if(!is.null(image()))brohn_close_facial_frame(image());image(NULL);image_url(NULL);frame_job(NULL)}
  clear<-function(){clear_csv();clear_image();if(!is.null(checks$index))brohn_cancel_facial_review_open(checks$index);checks$index<-NULL;if(!is.null(active()))brohn_close_facial_review(active());active(NULL);selection(NULL);plot(NULL);detail(NULL);offset(0L);index_job(NULL)}
  session$onSessionEnded(function()shiny::isolate(clear()))
  shiny::observeEvent(list(state$page,state$report_id),{clear();issue(NULL)},priority=100,ignoreInit=FALSE)
  safe<-function(f)attempt(function(){issue(NULL);tryCatch(f(),error=function(e){issue(conditionMessage(e));stop(e)})})
  fields<-function(){metric<-input$facial_metric;start<-brohn_default(input$facial_start,"");end<-brohn_default(input$facial_end,"");brohn_require(metric%in%unlist(guard()$record$body$manifest$metrics),"Choose a retained native score.");bounds<-NULL
    if(nzchar(start)||nzchar(end)){brohn_require(.brohn_facial_decimal(start)&&.brohn_facial_decimal(end)&&.brohn_facial_compare(start,end)<=0L,"Use both decimal bounds from 0 to 600, with the last at or after the first.");bounds<-list(start,end)}
    list(metric=metric,range=bounds)}
  unchanged<-function(){v<-guard();brohn_require(identical(brohn_hash(fields()),brohn_hash(selection())),"Apply the visible score and range before inspecting or downloading it.");v}
  show_frame<-function(index){v<-guard();clear_image();detail(brohn_facial_review_read(store,v,"detail",list(frame_index=as.numeric(index))))
    if(nzchar(Sys.getenv("BROHN_FACIAL_FFMPEG_DIR")))wanted_frame(list(index_hash=v$context$index_hash,frame=as.numeric(index)))}
  apply<-function(s){v<-guard();clear_csv();clear_image();detail(NULL);offset(0L);p<-brohn_facial_review_read(store,v,"plot",s);selection(s);plot(p)
    ids<-vapply(p$points,function(x)as.character(x$frame_index),character(1));labels<-vapply(p$points,function(x)paste(x$time_s,"s |",.brohn_fr_state(x$state)),character(1))
    shiny::updateSelectInput(session,"facial_frame",choices=stats::setNames(ids,labels),selected=if(length(ids))ids[[1L]]else character())
    if(length(ids))show_frame(ids[[1L]])}
  output$facial_review<-shiny::renderUI({r<-tryCatch(current(),error=function(e)NULL);if(is.null(r)||!brohn_facial_supported(r$body$analysis))return(NULL)
    shiny::div(id="facial-review",shiny::tags$script(src="facial-review-ui.js"),class="brohn-stack",style="min-width:0;grid-template-columns:minmax(0,1fr)",
      shiny::tags$style(shiny::HTML("#facial-review .brohn-stack{grid-template-columns:minmax(0,1fr)}#facial-review .shiny-html-output{min-width:0}#facial-review p,#facial-review pre{overflow-wrap:anywhere}#facial-review pre{white-space:pre-wrap;max-height:28rem;overflow:auto}#facial-review button,#facial-review select,#facial-review a,#facial-review summary{min-height:44px}#facial-review .brohn-table{max-width:100%;overflow:auto}#facial-review table{min-width:720px}#facial-review th,#facial-review td{white-space:nowrap}")),
      brohn_card(title="Explore saved facial outputs",subtitle="Review every analysed frame and the original pixels behind its native scores.",
        shiny::actionButton("facial_open","Explore saved facial outputs",class="btn-primary"),
        shiny::p("Uses complete saved outputs without rerunning a model. Native categories are not measurements of inner emotion, happiness, attention or preference. Face numbers only identify rows within one frame.")),
      shiny::uiOutput("facial_progress"),shiny::uiOutput("facial_controls"),shiny::uiOutput("facial_plot"),shiny::uiOutput("facial_export_status"),shiny::uiOutput("facial_detail"),shiny::uiOutput("facial_values"))
  })
  shiny::observeEvent(input$facial_open,safe(function(){r<-current();clear();j<-brohn_queue_facial_review(store,r$id,r$revision,brohn_hash(r$body),r$project_id);if(j$status%in%c("failed","cancelled"))j<-brohn_retry_processing(store,j$id);index_job(j$id)}))
  output$facial_controls<-shiny::renderUI({v<-active();if(is.null(v))return(NULL);m<-v$record$body$manifest;metrics<-unlist(m$metrics)
    brohn_card(title="Score and exact time range",shiny::p(paste(m$frames,"complete analysed frames. Original source PTS origin:",m$parameters$source_pts_origin_s,"seconds. Stride:",m$parameters$frame_stride,"source frames.")),
      shiny::selectInput("facial_metric","Saved native score",stats::setNames(metrics,vapply(metrics,.brohn_fr_label,character(1))),"AU01",selectize=FALSE),
      shiny::div(class="brohn-form-grid",shiny::textInput("facial_start","First recording-relative second (included)",""),shiny::textInput("facial_end","Last recording-relative second (included)","")),
      shiny::actionButton("facial_apply","Apply facial view",class="btn-primary"),shiny::p("Leave both bounds empty for all analysed frames. Exact rational source timestamps decide membership; chart positions are a display only."),
      shiny::uiOutput("facial_cursor"),
      shiny::tags$details(shiny::tags$summary("Original permission, source and model settings"),shiny::tags$pre(tabindex="0",brohn_json(list(binding=v$record$body$binding,parameters=m$parameters,engine=m$engine),TRUE))))
  })
  output$facial_cursor<-shiny::renderUI({p<-plot();if(is.null(p))return(NULL);ids<-vapply(p$points,function(x)as.character(x$frame_index),character(1));labels<-vapply(p$points,function(x)paste(x$time_s,"s |",.brohn_fr_state(x$state)),character(1));shiny::selectInput("facial_frame","Inspect recording time",stats::setNames(ids,labels),if(length(ids))ids[[1L]]else character(),selectize=FALSE)})
  shiny::observeEvent(input$facial_apply,safe(function()apply(fields())))
  # Debounce BEFORE bounded row lookup: rapid keyboard selection must not spawn
  # either one reader process or one heavy decode for every transient option.
  settled_cursor<-shiny::debounce(shiny::reactive(input$facial_frame),500)
  settled_frame<-shiny::debounce(shiny::reactive(wanted_frame()),500)
  queue_settled_frame<-function(){target<-settled_frame()
    if(is.null(target)||is.null(wanted_frame())||!identical(brohn_hash(target),brohn_hash(wanted_frame()))||!is.null(frame_job())||!is.null(image()))return(invisible(NULL))
    if(!is.null(automatic$job)){prior<-brohn_get_job(store,automatic$job);if(prior$status%in%c("queued","running"))return(invisible(NULL));automatic$job<-NULL}
    v<-guard();brohn_require(identical(v$context$index_hash,target$index_hash)&&!is.null(detail())&&identical(as.numeric(detail()$observation$frame_index),target$frame),"Choose the current exact recording time.")
    j<-brohn_queue_facial_frame(store,v,target$frame);if(j$status%in%c("failed","cancelled"))j<-brohn_retry_processing(store,j$id)
    automatic$job<-if(j$status%in%c("queued","running"))j$id else NULL;frame_job(j$id)
  }
  shiny::observeEvent(settled_frame(),safe(queue_settled_frame),ignoreNULL=TRUE)
  shiny::observeEvent(input$facial_frame,{if(!is.null(detail())&&!identical(detail()$observation$frame_index,input$facial_frame)){clear_image();detail(NULL)}},ignoreNULL=TRUE,priority=5)
  shiny::observeEvent(settled_cursor(),{chosen<-settled_cursor();if(is.null(active())||!nzchar(brohn_default(chosen,"")))return();safe(function(){unchanged();brohn_require(identical(chosen,input$facial_frame)&&chosen%in%vapply(plot()$points,function(x)as.character(x$frame_index),character(1)),"Choose an analysed frame in the applied exact range.");if(is.null(detail())||!identical(detail()$observation$frame_index,chosen))show_frame(chosen)})})
  shiny::observeEvent(input$facial_extract,safe(function(){v<-unchanged();d<-detail();brohn_require(!is.null(d)&&identical(d$observation$frame_index,input$facial_frame),"Choose the applied original frame first.");clear_image();wanted_frame(list(index_hash=v$context$index_hash,frame=as.numeric(d$observation$frame_index)))}))
  for(kind in c("index","frame"))local({k<-kind
    shiny::observeEvent(input[[paste0("facial_cancel_",k)]],safe(function(){id<-if(k=="index")index_job()else frame_job();brohn_require(!is.null(id),"Choose a current job.");brohn_cancel_job(store,id)}))
    shiny::observeEvent(input[[paste0("facial_retry_",k)]],safe(function(){id<-if(k=="index")index_job()else frame_job();j<-brohn_retry_processing(store,id);if(k=="index")index_job(j$id)else{frame_job(j$id);automatic$job<-j$id}}))})
  shiny::observe({shiny::invalidateLater(500,session);shiny::isolate({
    tryCatch(queue_settled_frame(),error=function(e){issue(conditionMessage(e));wanted_frame(NULL)})
    if(!is.null(checks$csv)&&is.null(csv()))tryCatch({r<-brohn_poll_facial_csv(store,checks$csv);if(!is.null(r))csv(r)},error=function(e){clear_csv();issue(conditionMessage(e))})
    for(k in c("index","frame")){id<-if(k=="index")index_job()else frame_job();if(is.null(id))next;j<-brohn_get_job(store,id);if(j$status!="succeeded")next
      tryCatch({if(k=="index"){
        if(!is.null(active()))next
        if(is.null(checks$index)){r<-current();checks$index<-brohn_begin_facial_review_open(store,j$result$facial_review_id,j$result$index_hash,r$id,r$revision,brohn_hash(r$body),r$project_id)}
        v<-brohn_poll_facial_review_open(store,checks$index);if(!is.null(v)){checks$index<-NULL;active(v);apply(list(metric="AU01",range=NULL))}
      }else{
        if(!is.null(image()))next
        if(is.null(checks$image))checks$image<-brohn_begin_facial_frame_open(store,guard(),j$result$facial_frame_id,j$result$frame_hash,as.numeric(detail()$observation$frame_index))
        v<-brohn_poll_facial_frame_open(store,checks$image);if(!is.null(v)){checks$image<-NULL;image(v)}
      }},error=function(e){issue(conditionMessage(e));if(k=="index"){if(!is.null(checks$index))brohn_cancel_facial_review_open(checks$index);checks$index<-NULL;index_job(NULL)}else clear_image()})
    }
  })})
  output$facial_progress<-shiny::renderUI({shiny::invalidateLater(800,session);shiny::tagList(if(!is.null(issue()))shiny::div(role="alert",class="brohn-notice",issue()),if(!is.null(wanted_frame())&&is.null(frame_job()))shiny::p(role="status",if(is.null(automatic$job))"Preparing the settled recording-time selection."else"Finishing the current recorded frame before preparing the latest selected time."),lapply(c("index","frame"),function(k){id<-if(k=="index")index_job()else frame_job();if(is.null(id)||(k=="index"&&!is.null(active()))||(k=="frame"&&!is.null(image())))return(NULL);j<-brohn_get_job(store,id)
    shiny::div(role="status",shiny::p(paste(if(k=="index")"Complete facial index"else"Exact recorded frame",if(j$status=="succeeded")"verifying retained bytes"else j$status)),if(!is.null(j$error$message))shiny::p(j$error$message),
      if(j$status%in%c("queued","running"))shiny::actionButton(paste0("facial_cancel_",k),"Cancel facial job"),if(j$status%in%c("failed","cancelled"))shiny::actionButton(paste0("facial_retry_",k),"Retry facial job"))}))})
  output$facial_plot<-shiny::renderUI({p<-plot();if(is.null(p))return(NULL);saved<-p$saved_global_feature
    brohn_card(title=.brohn_fr_label(p$metric),subtitle=paste(p$frames,"analysed frames in the applied view"),brohn_facial_review_svg(p,detail()$observation,brohn_default(input$facial_width,820)),
      shiny::p("Mint: one valid face. Purple: multiple faces. Amber: no face or incomplete native output. Blank intervals contain no invented observations. Dashed white cursor: selected frame."),
      shiny::p(paste("Original report mean across its full analysed window:",brohn_default(saved$value,"Unavailable"),"|",saved$valid_frames,"eligible frames. This range does not rescore the report.")),
      shiny::actionButton("facial_export","Prepare complete selected CSV"),shiny::downloadButton("facial_figure","Download labelled figure",icon=NULL))})
  shiny::observeEvent(input$facial_export,safe(function(){unchanged();clear_csv();checks$csv<-brohn_begin_facial_csv(store,guard(),selection());csv_pending(TRUE)}))
  shiny::observeEvent(input$facial_export_cancel,safe(clear_csv))
  output$facial_values<-shiny::renderUI({p<-plot();if(is.null(p))return(NULL);o<-offset();rows<-head(if(o<length(p$points))p$points[seq.int(o+1L,length(p$points))]else list(),25L)
    brohn_card(title="Exact saved frame values",subtitle=paste(length(rows),"rows beginning at",o,"of",p$frames,"analysed frames"),
      brohn_table(lapply(rows,function(r)list(Frame=r$frame_index,"Relative time (rational seconds)"=.brohn_fr_exact(r),"Saved time token"=r$time_s,"Native score token"=brohn_default(r$value,"Unavailable"),State=.brohn_fr_state(r$state),"Local faces"=r$face_count)),label="Exact native facial frame values"),
      shiny::div(class="brohn-toolbar",if(o>0)shiny::actionButton("facial_previous","Previous frame page"),if(o+25<p$frames)shiny::actionButton("facial_next","Next frame page")),
      shiny::p("The CSV also includes each separate face from multiple-face frames. Such values remain excluded from the single-face timeline and original summaries."))})
  shiny::observeEvent(input$facial_next,safe(function(){unchanged();offset(min(25L*floor(max(0,plot()$frames-1)/25),offset()+25L))}))
  shiny::observeEvent(input$facial_previous,safe(function(){unchanged();offset(max(0L,offset()-25L))}))
  output$facial_detail<-shiny::renderUI({d<-detail();if(is.null(d))return(NULL);r<-d$observation
    brohn_card(title=paste("Recording at",r$time_s,"seconds"),subtitle=.brohn_fr_state(r$state),
      shiny::tags$details(shiny::tags$summary("Exact source frame and timing"),shiny::p(paste("Original frame",r$frame_index,"| integer PTS",r$source_pts,"x",r$source_time_base,"| relative",.brohn_fr_exact(r),"seconds"))),shiny::uiOutput("facial_prepare_button"),
      shiny::downloadButton("facial_json","Download original observation JSON",icon=NULL),shiny::uiOutput("facial_pixels"),
      shiny::tags$details(shiny::tags$summary(paste("Exact native values for",r$face_count,"frame-local faces")),brohn_table(unlist(lapply(r$faces,function(face)lapply(names(c(face$au_scores,face$expression_scores)),function(metric)list("Frame-local face"=face$face_ordinal,Valid=face$valid,Metric=metric,"Original token"=brohn_default(c(face$au_scores,face$expression_scores)[[metric]],"Unavailable")))),recursive=FALSE),label="Every original native facial score")),
      shiny::tags$details(shiny::tags$summary("Exact original observation record"),shiny::tags$pre(tabindex="0",d$original_json)))})
  shiny::observeEvent(image(),{saved<-image();if(is.null(saved))return();token<-brohn_token();id<-saved$record$id
    url<-session$registerDataObj("brohn-facial-pixels",list(token=token,id=id),function(data,req)shiny::isolate(tryCatch({
      brohn_require(req$REQUEST_METHOD%in%c("GET","HEAD")&&identical(shiny::parseQueryString(brohn_default(req$QUERY_STRING,""))$key,data$token)&&!is.null(image())&&identical(image()$record$id,data$id),"This image link is no longer active.")
      v<-unchanged();brohn_require(identical(input$facial_frame,detail()$observation$frame_index),"Select the exact frame again.");brohn_check_facial_frame_context(store,image(),v,as.numeric(detail()$observation$frame_index))
      structure(list(status=200L,content_type="image/png",content=list(file=image()$authority$path,owned=FALSE),headers=list("Cache-Control"="no-store","X-Content-Type-Options"="nosniff")),class="httpResponse")
    },error=function(e)structure(list(status=404L,content_type="text/plain",content="This exact frame is unavailable; reopen its source."),class="httpResponse"))))
    image_url(paste0(url,"&key=",token))},ignoreNULL=TRUE)
  output$facial_prepare_button<-shiny::renderUI({if(is.null(image())&&is.null(frame_job())&&is.null(wanted_frame()))shiny::actionButton("facial_extract","Prepare exact recorded frame",class="btn-primary")})
  output$facial_pixels<-shiny::renderUI({uri<-image_url();if(is.null(uri))return(shiny::p("Preparing or verifying the exact original pixels in the background. If the optional decoder is unavailable, configure the original facial FFmpeg runtime and choose Prepare exact recorded frame. No model inference is rerun."))
    shiny::tagList(shiny::tags$img(src=uri,alt=paste("Exact original recorded pixels for analysed frame",detail()$observation$frame_index),style="max-width:100%;max-height:65vh;object-fit:contain;display:block"),shiny::p("Verified against the original saved decoded RGB hash. Encoded orientation, no crop, resize or mirroring."),shiny::downloadButton("facial_png","Download original frame PNG",icon=NULL))})
  shiny::observeEvent(csv(),{r<-csv();if(is.null(r))return();token<-brohn_token();url<-session$registerDataObj("brohn-facial-csv",list(token=token,hash=r$sha256),function(data,req)shiny::isolate(tryCatch({
    brohn_require(req$REQUEST_METHOD%in%c("GET","HEAD")&&identical(shiny::parseQueryString(brohn_default(req$QUERY_STRING,""))$key,data$token),"This CSV link is no longer active.");unchanged();brohn_require(!is.null(csv())&&identical(csv()$sha256,data$hash),"Prepare this selection again.");r<-brohn_poll_facial_csv(store,checks$csv)
    structure(list(status=200L,content_type="text/csv; charset=utf-8",content=list(file=r$path,owned=FALSE),headers=list("Content-Disposition"='attachment; filename="saved-facial-values.csv"',"Cache-Control"="no-store","X-Content-Type-Options"="nosniff")),class="httpResponse")
  },error=function(e)structure(list(status=404L,content_type="text/plain",content="This exact CSV is unavailable; prepare the current selection."),class="httpResponse"))))
    csv_url(paste0(url,"&key=",token))},ignoreNULL=TRUE)
  output$facial_export_status<-shiny::renderUI({if(!csv_pending())return(NULL);r<-csv();if(is.null(r))return(shiny::div(role="status","Preparing complete selected values in the background.",shiny::actionButton("facial_export_cancel","Cancel CSV preparation")))
    brohn_card(title="Complete selected CSV ready",shiny::p(paste(r$rows,"source rows from",r$frames,"frames; original numeric tokens, including every frame-local face.")),
      shiny::tags$a(class="btn btn-primary",href=csv_url(),download="saved-facial-values.csv","Download complete selected CSV"),shiny::downloadButton("facial_manifest","Download CSV source manifest",icon=NULL))})
  output$facial_manifest<-shiny::downloadHandler(filename=function()"saved-facial-values-manifest.json",content=function(file)prepare_download(function(){unchanged();brohn_poll_facial_csv(store,checks$csv);brohn_write_json_file(brohn_facial_csv_manifest(checks$csv),file)}))
  output$facial_json<-shiny::downloadHandler(filename=function()paste0("original-facial-frame-",detail()$observation$frame_index,".json"),content=function(file)prepare_download(function(){unchanged();brohn_require(identical(input$facial_frame,detail()$observation$frame_index),"Select the displayed frame first.");writeBin(charToRaw(enc2utf8(detail()$original_json)),file)}))
  output$facial_png<-shiny::downloadHandler(filename=function()paste0("original-facial-frame-",detail()$observation$frame_index,".png"),content=function(file)prepare_download(function(){v<-unchanged();brohn_require(identical(input$facial_frame,detail()$observation$frame_index),"Select the displayed frame first.");brohn_check_facial_frame_context(store,image(),v,as.numeric(detail()$observation$frame_index));brohn_copy_object_download(store,image()$record$body$frame$image$hash,file)}))
  output$facial_figure<-shiny::downloadHandler(filename=function()"saved-facial-view.html",content=function(file)prepare_download(function(){v<-unchanged();p<-plot();frame<-detail()$observation
    css<-"*{box-sizing:border-box}body{max-width:920px;margin:0 auto;padding:16px;background:#131d24;color:#edf5f3;font-family:system-ui;line-height:1.5}h1{font-size:1.5rem}p,pre{overflow-wrap:anywhere}pre{white-space:pre-wrap}summary{min-height:44px;cursor:pointer}.facial-figure-medium,.facial-figure-wide{display:none}@media(min-width:500px){.facial-figure-compact{display:none}.facial-figure-medium{display:block}}@media(min-width:850px){.facial-figure-medium{display:none}.facial-figure-wide{display:block}}"
    html<-shiny::tagList(shiny::tags$head(shiny::tags$meta(charset="utf-8"),shiny::tags$meta(name="viewport",content="width=device-width, initial-scale=1"),shiny::tags$title("Saved native facial observations"),shiny::tags$style(shiny::HTML(css))),
      shiny::tags$body(shiny::tags$main(shiny::h1("Saved native facial observations"),shiny::p(.brohn_fr_label(p$metric)),
        shiny::div(class="facial-figure-compact",brohn_facial_review_svg(p,frame,280)),shiny::div(class="facial-figure-medium",brohn_facial_review_svg(p,frame,460)),shiny::div(class="facial-figure-wide",brohn_facial_review_svg(p,frame,820)),
        shiny::p("Mint: one valid face. Purple: multiple faces. Amber: no face or incomplete output. Blank intervals have no invented observations. The white dashed cursor marks the selected recording time."),
        shiny::p("Native model outputs; no new inference, identity tracking or selected-window rescoring. Native categories do not establish measured inner emotion, happiness or attention."),
        shiny::tags$details(shiny::tags$summary("Exact source, selection and original settings"),shiny::tags$pre(brohn_json(list(source=v$record$body$binding,selection=selection(),parameters=v$record$body$manifest$parameters),TRUE))))))
    rendered<-htmltools::renderTags(html)
    writeLines(paste0('<!doctype html><html lang="en"><head>',rendered$head,"</head>",rendered$html,"</html>"),file,useBytes=TRUE)}))
  invisible(list(clear=clear,active=active,selection=selection,detail=detail,image=image))
}

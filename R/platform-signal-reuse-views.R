brohn_install_signal_interval_reuse_ui <- function(input,output,session,store,state,protect,message,context,catalog,table,activate) {
  chosen<-shiny::reactiveVal(NULL);review<-shiny::reactiveVal(NULL)
  target_key<-function(){r<-context();c<-catalog();t<-table();paste(r$id,c$id,c$revision,brohn_hash(c$body),t$table_id,sep=":")}
  clear<-function(){chosen(NULL);review(NULL)}
  shiny::observeEvent(list(state$page,state$report_id,input$signal_table),clear(),ignoreInit=FALSE,priority=100)
  shiny::observeEvent(list(input$interval_reuse_version,input$interval_reuse_title,input$interval_reuse_source_anchor,
    input$interval_reuse_target_anchor,input$interval_reuse_reason,input$interval_reuse_choice),{
      previous<-review();if(is.null(previous))return()
      current<-tryCatch(from_form(),error=function(e)NULL)
      if(is.null(current)||!identical(brohn_hash(current),brohn_hash(previous)))review(NULL)
    },ignoreInit=TRUE,priority=100)
  output$signal_interval_reuse<-shiny::renderUI({r<-context();c<-catalog();t<-table()
    if(!identical(t$coordinates$axis,"time")||!identical(t$coordinate_column$unit,"s"))return(NULL)
    sources<-brohn_list_entities(store,"signal_annotations",r$project_id,limit=100L)
    sources<-Filter(function(s)length(s$body$intervals)>0L,sources)
    if(!length(sources))return(NULL)
    choices<-c("Choose original intervals"="",setNames(vapply(sources,`[[`,character(1),"id"),
      vapply(sources,function(s)paste(s$body$title,"|",s$body$table$identity$recording_id,"| version",s$revision),character(1))))
    shiny::tags$details(shiny::tags$summary("Reuse saved intervals on this recording"),
      shiny::p("Choose saved labels and windows, then review how their times map onto this recording. The original set and its results stay preserved."),
      shiny::tags$input(id="interval_reuse_target_identity",type="text",class="shiny-input-text",value=target_key(),hidden=NA),
      shiny::selectInput("interval_reuse_choice","Original interval set (up to 100 most recent)",choices,selectize=FALSE),
      shiny::actionButton("choose_interval_reuse","Choose interval source"),
      shiny::uiOutput("signal_interval_reuse_form"),shiny::uiOutput("signal_interval_reuse_preview"))
  })
  shiny::observeEvent(input$choose_interval_reuse,protect(function(){
    brohn_require(identical(input$interval_reuse_target_identity,target_key()),"Reopen the target recording before choosing intervals.")
    s<-brohn_signal_annotations(store,input$interval_reuse_choice)
    brohn_require(identical(s$project_id,context()$project_id)&&length(s$body$intervals)>0L,"Choose a nonempty interval set from this project.")
    chosen(list(record=s,target=target_key()));review(NULL)
  }))
  pinned<-function(){x<-chosen();brohn_require(!is.null(x)&&identical(x$target,target_key()),"Choose original intervals for the current recording.")
    brohn_require(identical(input$interval_reuse_choice,x$record$id),"Choose the newly selected interval source before previewing it.")
    latest<-brohn_signal_annotations(store,x$record$id)
    brohn_require(identical(.brohn_interval_identity(latest),.brohn_interval_identity(x$record)),"The original intervals changed. Choose their source again.")
    x$record
  }
  output$signal_interval_reuse_form<-shiny::renderUI({if(is.null(chosen()))return(NULL);s<-pinned();t<-table()
    shiny::tagList(shiny::tags$script(src="signal-reuse-ui.js"),shiny::tags$h3(paste("Reuse",s$body$title)),
      shiny::tags$input(id="interval_reuse_form_identity",type="text",class="shiny-input-text",value=.brohn_interval_identity(s),hidden=NA),
      shiny::div(class="brohn-form-grid",
        shiny::numericInput("interval_reuse_version","Original saved version",s$revision,min=1,max=s$revision,step=1),
        shiny::textInput("interval_reuse_title","New interval set name on this recording",paste("Reused",s$body$title)),
        shiny::numericInput("interval_reuse_source_anchor","Matching time in original recording (seconds)",0),
        shiny::numericInput("interval_reuse_target_anchor","Matching time in this recording (seconds)",0)),
      shiny::p("Identify the same event in both recordings, or enter 0 for both only when you intend to keep the same numeric boundaries. Brohn applies a time shift; it does not verify synchronization or correct clock drift."),
      shiny::textAreaInput("interval_reuse_reason","Reason these times correspond","",rows=2),
      shiny::tags$details(shiny::tags$summary("Recording clocks and sources"),
        shiny::p(paste("Original:",s$body$report_id,"|",s$body$origin)),
        shiny::p(paste("Target:",context()$id,"|",context()$body$origin)),
        brohn_table(list(list(recording="Original",clock=brohn_json(s$body$table$coordinates)),list(recording="Target",clock=brohn_json(t$coordinates))),label="Original and target declared clocks")),
      shiny::actionButton("preview_interval_reuse","Preview mapped intervals",class="btn-primary"))
  })
  from_form<-function(){s<-pinned();c<-catalog();t<-table()
    brohn_require(identical(input$interval_reuse_form_identity,.brohn_interval_identity(s)),"Wait for the selected original interval version.")
    brohn_require(brohn_number(input$interval_reuse_version,1,s$revision,TRUE),"Choose an available original saved version.")
    original<-brohn_signal_annotations(store,s$id,as.integer(input$interval_reuse_version))
    brohn_preview_signal_interval_reuse(store,original$id,original$revision,brohn_hash(original$body),c$id,c$revision,brohn_hash(c$body),t$table_id,
      input$interval_reuse_title,input$interval_reuse_source_anchor,input$interval_reuse_target_anchor,input$interval_reuse_reason)
  }
  shiny::observeEvent(input$preview_interval_reuse,protect(function(){review(NULL);review(from_form())}))
  output$signal_interval_reuse_preview<-shiny::renderUI({v<-review();if(is.null(v))return(NULL)
    rows<-lapply(v$intervals,function(i)list(label=i$label,category=i$category,note=i$note,original_start=brohn_signal_exact_number(i$source_start_s),original_end=brohn_signal_exact_number(i$source_end_s),
      target_start=brohn_signal_exact_number(i$start_s),target_end=brohn_signal_exact_number(i$end_s),support=switch(i$extent,within_observed_extent="Within observed time range",
        extends_beyond_observed_extent="Extends beyond observed time range",outside_observed_extent="Outside observed time range",unknown_target_extent="Target time range unavailable")))
    outside<-sum(vapply(v$intervals,function(i)i$extent!="within_observed_extent",logical(1)))
    shiny::div(class="brohn-stack",shiny::tags$h3("Review mapped intervals"),
      shiny::p(paste("Original version",v$source$annotation$revision,"to",v$title,"| Time shift:",brohn_signal_exact_number(v$mapping$offset_s),"seconds.")),
      shiny::p(v$mapping$rationale),
      if(outside>0L)shiny::div(class="brohn-alert",role="status",paste(outside,"interval(s) extend beyond the target's observed times or have unknown coverage. Boundaries are preserved. Summaries will report their actual available samples.")),
      brohn_table(rows,columns=c("label","category","original_start","original_end","target_start","target_end","support","note"),
        labels=c("Interval","Category","Original start (s)","Original end (s)","Target start (s)","Target end (s)","Observed extent","Notes"),maximum=64L,label="Every mapped half-open interval"),
      shiny::p("The start is included; the end is excluded. This copies labels and boundaries only. New summaries use this recording's data. Changing the form requires a new preview."),
      brohn_command("Save mapped intervals as a new set","apply_interval_reuse",list(hash=brohn_hash(v))))
  })
  shiny::observeEvent(input$apply_interval_reuse,protect(function(){v<-review();cmd<-input$apply_interval_reuse
    brohn_require(!is.null(v)&&identical(cmd$hash,brohn_hash(v))&&identical(brohn_hash(from_form()),brohn_hash(v)),"The mapping changed. Preview the current inputs again before saving.")
    value<-brohn_apply_signal_interval_reuse(store,v,cmd$hash);clear();activate(value);message("Mapped intervals saved as a new set on this recording. Calculate summaries to use its data.")
  }))
  invisible(list(chosen=chosen,preview=review))
}

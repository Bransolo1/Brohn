brohn_explicit_distribution_entry_ui <- function(report) {

  if(!identical(report$analysis$kind,"questionnaire"))return(NULL)

  shiny::tagList(brohn_card(title="Response distributions",shiny::p("Review complete response and scale distributions with their missingness and assessment support."),

    brohn_command("Explore response distributions","open_explicit_distributions",list(report_id=report$id,report_hash=brohn_hash(report)))),

    shiny::uiOutput("ed_progress"),shiny::uiOutput("ed_controls"),shiny::uiOutput("ed_result"))

}

.brohn_ed_number <- function(x) if(is.null(x))"Unavailable"else format(x,digits=8,trim=TRUE,big.mark=",")

.brohn_ed_rows <- function(group) {

  if(group$quantitative)lapply(group$bins,function(b)list(label=if(b$lower==b$upper).brohn_ed_number(b$lower)else paste0("[",.brohn_ed_number(b$lower),", ",.brohn_ed_number(b$upper),if(b$upper_inclusive)"]"else")"),

    type="numeric_bin",value_json=brohn_json(b[c("lower","upper","upper_inclusive")]),count=b$count))else

    lapply(group$categories,function(c)list(label=c$label,type=c$value_kind,value_json=c$value_json,count=c$count))

}

brohn_explicit_distribution_svg <- function(group,offset=0L,width=720L,binding=NULL) {

  rows<-.brohn_ed_rows(group);visible<-head(tail(rows,max(0L,length(rows)-offset)),20L)

  if(!length(visible))return(NULL)

  # Labels remain horizontal and short; complete typed values accompany the plot.

  height<-100+length(visible)*36;left<-155;right<-64;maximum<-max(1,vapply(rows,`[[`,numeric(1),"count"))

  nodes<-lapply(seq_along(visible),function(i){r<-visible[[i]];y<-48+(i-1)*36;label<-if(nchar(r$label)>19)paste0(substr(r$label,1,18),"\u2026")else r$label

    shiny::tagList(shiny::tags$text(x=left-8,y=y+17,`text-anchor`="end",fill="#edf5f3",`font-size`=12,label),

      shiny::tags$rect(x=left,y=y,width=(width-left-right)*r$count/maximum,height=24,fill="#99d6c6",shiny::tags$title(paste(r$type,r$label,"\u2014",r$count,"of",group$usable_records,"eligible records"))),

      shiny::tags$text(x=left+(width-left-right)*r$count/maximum+6,y=y+17,fill="#edf5f3",`font-size`=12,r$count))})

  shiny::tags$svg(xmlns="http://www.w3.org/2000/svg",viewBox=paste(0,0,width,height),width="100%",role="img",`aria-label`=paste("Saved record counts for",group$label,group$condition_label),

    style="display:block;background:#131d24;font-family:system-ui,sans-serif;border-radius:12px",shiny::tags$title(paste(group$label,group$condition_label,group$unit)),

    shiny::tags$metadata(brohn_json(list(source=binding,group_id=group$id,unit=group$unit,offset=offset,shown=length(visible),full_distribution_rows=length(rows),record_denominator=group$usable_records))),

    shiny::tags$desc(paste("Displayed categories",offset+1,"to",offset+length(visible),"of",length(rows),". Counts describe saved records, not independent people. Complete exact values are in the accompanying table and CSV.")),

    shiny::tags$text(x=if(width<560)12 else left,y=25,fill="#edf5f3",`font-size`=13,"Eligible saved record count"),nodes,

    shiny::tags$text(x=if(width<560)12 else left,y=height-18,fill="#b4c9ca",`font-size`=12,paste("Record denominator:",group$usable_records)))

}

brohn_explicit_distribution_csv <- function(record,group,file) {

  rows<-.brohn_ed_rows(group);binding<-record$body$result$binding

  # Bound the whole export before repeating source metadata across rows. Twice
  # the UTF-8 cell bytes also covers worst-case CSV quote escaping.
  common<-c(binding$report_id,binding$report_hash,binding$analysis_sha256,group$id,group$family,group$unit,group$item_id,
    brohn_json(group$condition_id),brohn_json(group$states),brohn_json(binding))
  export_bound<-4096+length(rows)*(2048+2*sum(nchar(enc2utf8(common),type="bytes")))+
    2*sum(vapply(rows,function(r)sum(nchar(enc2utf8(c(r$label,r$type,r$value_json)),type="bytes")),numeric(1)))
  brohn_require(export_bound<=32*1024^2,"This complete CSV exceeds the bounded 32 MiB export profile. Use the complete distribution JSON; no partial CSV was exported.")
  protect<-function(x)if(grepl("^[[:space:]]*[=+@-]",x))paste0("'",x)else x

  table<-do.call(rbind,lapply(rows,function(r)data.frame(report_id=binding$report_id,report_hash=binding$report_hash,analysis_sha256=binding$analysis_sha256,

    group_id=group$id,family=group$family,unit=group$unit,item_id=protect(group$item_id),condition_json=brohn_json(group$condition_id),label=protect(r$label),value_kind=r$type,

    exact_value_json=r$value_json,count=r$count,eligible_record_denominator=group$usable_records,source_records=group$source_records,

    assessment_count=if(is.null(group$assessment_count))NA_integer_ else group$assessment_count,participant_count=if(is.null(group$participant_count))NA_integer_ else group$participant_count,

    invalid_or_unsupported=group$invalid_or_unsupported,unassigned_records=group$unassigned_records,repeated_assessment_records=group$repeated_assessment_records,
    participant_linkage_complete=group$participant_linkage_complete,missingness_json=brohn_json(group$states),source_binding_json=brohn_json(binding),stringsAsFactors=FALSE)))
  if(is.null(table))table<-data.frame(report_id=character(),report_hash=character(),analysis_sha256=character(),group_id=character(),family=character(),unit=character(),item_id=character(),condition_json=character(),label=character(),value_kind=character(),exact_value_json=character(),count=integer(),eligible_record_denominator=integer(),source_records=integer(),assessment_count=integer(),participant_count=integer(),invalid_or_unsupported=integer(),unassigned_records=integer(),repeated_assessment_records=integer(),participant_linkage_complete=logical(),missingness_json=character(),source_binding_json=character())
  # Windows C locale write.csv transliterates Unicode even with fileEncoding.
  # Encode complete quoted fields as UTF-8 bytes, preserving canonical JSON.
  con<-file(file,"wb");on.exit(close(con),add=TRUE)
  write_row<-function(cells)writeBin(charToRaw(enc2utf8(paste0(paste(paste0('"',gsub('"','""',enc2utf8(cells),fixed=TRUE),'"'),collapse=","),"\r\n"))),con)
  write_row(names(table))
  for(i in seq_len(nrow(table)))write_row(vapply(table,function(column){x<-column[[i]];if(is.na(x))""else if(is.character(x))x else brohn_json(x)},character(1)))
  invisible(file)
}

brohn_install_explicit_distribution_server <- function(input,output,session,store,state,attempt,message,prepare_download) {

  job<-shiny::reactiveVal(NULL);ready<-shiny::reactiveVal(NULL);issue<-shiny::reactiveVal(NULL);page<-shiny::reactiveVal(0L)

  clear<-function(){job(NULL);ready(NULL);issue(NULL);page(0L)}

  shiny::observeEvent(list(state$page,state$report_id),clear(),ignoreInit=FALSE,priority=110)

  require_current<-function(){r<-ready();brohn_require(!is.null(r)&&identical(state$page,"report")&&identical(state$report_id,r$body$report_id),"Open this saved report's current distribution.")

    brohn_explicit_distribution_record(store,r$id,brohn_hash(r$body))}

  guarded<-function(fn)attempt(function(){tryCatch({issue(NULL);fn()},error=function(e){ready(NULL);issue(conditionMessage(e));stop(e)})})

  shiny::observeEvent(input$open_explicit_distributions,guarded(function(){cmd<-input$open_explicit_distributions

    brohn_require(identical(state$page,"report")&&identical(state$report_id,cmd$report_id),"Open the report before reviewing its distributions.")

    j<-brohn_queue_explicit_distributions(store,cmd$report_id,cmd$report_hash);ready(NULL);job(j);page(0L);message("Reading complete saved responses and scale assessments in the background.")}))

  shiny::observe({j<-job();if(is.null(j)||!is.null(ready()))return();shiny::invalidateLater(1000,session)

    tryCatch(shiny::isolate({fresh<-brohn_get_job(store,j$id);job(fresh)

      if(identical(fresh$status,"succeeded")){ready(brohn_explicit_distribution_record(store,fresh$result$explicit_distributions_id));message("Complete distributions are ready. Choose an item and condition.")}}),error=function(e){issue(conditionMessage(e));job(NULL);ready(NULL)})})

  # Metadata-only authority check while open; do not repeatedly hydrate records.

  shiny::observe({r<-ready();if(is.null(r))return();shiny::invalidateLater(2000,session);shiny::isolate(tryCatch({req<-r$body$request

    brohn_project(store,req$project_id);brohn_require(identical(.brohn_qexplorer_catalog(store,"report",req$report_id,req$report_revision,req$project_id),req$catalog_hash),"The saved source authority changed.")

  },error=function(e){ready(NULL);issue(conditionMessage(e))}))})

  shiny::observeEvent(input$ed_retry,guarded(function(){j<-job();brohn_require(!is.null(j)&&j$status %in% c("failed","cancelled"),"Only failed or cancelled distribution work can be retried.")

    job(brohn_queue_explicit_distributions(store,j$request$report_id,j$request$report_hash,retry=TRUE))}))

  shiny::observeEvent(input$ed_cancel,guarded(function(){j<-job();brohn_require(!is.null(j)&&j$status %in% c("queued","running"),"Only active distribution work can be cancelled.");brohn_cancel_job(store,j$id);job(brohn_get_job(store,j$id))}))

  output$ed_progress<-shiny::renderUI({j<-job();shiny::tagList(if(!is.null(issue()))shiny::div(role="alert",class="brohn-alert brohn-alert-error",issue()),

    if(!is.null(j)&&j$status!="succeeded")brohn_card(title="Preparing response distributions",shiny::p(role="status",switch(j$status,queued="Queued; the original report is available.",running="Reading all saved responses, including states beyond the report preview.",cancelled="Cancelled; saved sources are unchanged.",failed=paste("Needs attention:",j$error$message),j$status)),

      if(j$status %in% c("queued","running"))shiny::actionButton("ed_cancel","Cancel distribution review")else shiny::actionButton("ed_retry","Retry distribution review")))})

  output$ed_controls<-shiny::renderUI({r<-ready();if(is.null(r))return(NULL);groups<-r$body$result$groups

    if(!length(groups))return(shiny::p("This complete source has no question or scale records to distribute."))

    shiny::div(class="brohn-ed-controls",shiny::tags$style(shiny::HTML(".brohn-ed-controls button,.brohn-ed-controls select,.brohn-ed-result button,.brohn-ed-result a{min-height:44px}.brohn-ed-controls,.brohn-ed-result{min-width:0;max-width:100%}.brohn-ed-result pre{white-space:pre-wrap;overflow-wrap:anywhere}.brohn-ed-chart-wide{display:block}.brohn-ed-chart-narrow{display:none}@media(max-width:600px){.brohn-ed-chart-wide{display:none}.brohn-ed-chart-narrow{display:block}}")),

      shiny::selectInput("ed_group","Question or scale and condition",stats::setNames(vapply(groups,`[[`,character(1),"id"),vapply(groups,function(g)paste(if(g$family=="scale")"Scale:"else"Question:",g$label,"\u2014",g$condition_label),character(1))),selectize=FALSE),

      shiny::p("Each selection uses one item and exact saved condition. Repeated visits are records or assessments, not extra people."))})

  group<-shiny::reactive({r<-ready();shiny::req(r,input$ed_group);g<-brohn_find(r$body$result$groups,input$ed_group);shiny::req(g);g})

  shiny::observeEvent(input$ed_group,page(0L),ignoreInit=FALSE)

  shiny::observeEvent(input$ed_next,guarded(function(){require_current();g<-group();brohn_require(page()+20L<length(.brohn_ed_rows(g)),"No further distribution rows.");page(page()+20L)}))

  shiny::observeEvent(input$ed_previous,guarded(function(){require_current();page(max(0L,page()-20L))}))

  output$ed_result<-shiny::renderUI({g<-group();offset<-page();rows<-.brohn_ed_rows(g);visible<-head(tail(rows,max(0L,length(rows)-offset)),20L)

    shiny::div(id="explicit-distribution",class="brohn-ed-result",`data-ed-group`=g$id,brohn_card(title=g$label,subtitle=paste(g$condition_label,"\u00b7",g$unit),
      shiny::p(shiny::strong(paste(g$source_records,"complete source records;",g$usable_records,"eligible for this distribution."))),

      shiny::p(paste("Explicit assessments:",.brohn_ed_number(g$assessment_count),"; linked people:",.brohn_ed_number(g$participant_count),"; records without explicit assessment identity:",g$unassigned_records,"; repeated records within a known assessment:",g$repeated_assessment_records,".")),

      if(!g$participant_linkage_complete)shiny::p("Unique-person counts are unavailable because at least one saved record lacks explicit person linkage."),

      if(g$invalid_or_unsupported>0)shiny::p(paste(g$invalid_or_unsupported,"answered/scored records have invalid or unsupported values and are excluded from the distribution, while their source states remain counted below.")),

      if(!is.null(g$summary))shiny::p(paste("Descriptive record-weighted mean:",.brohn_ed_number(g$summary$mean),"; median:",.brohn_ed_number(g$summary$median),"; range:",.brohn_ed_number(g$summary$minimum),"to",.brohn_ed_number(g$summary$maximum),"."))else shiny::p("No numeric mean is inferred from category codes, typed text or unavailable scores."),

      shiny::p("These are descriptive saved-record distributions. No independent-person inference, reliability estimate or population benchmark is implied."),

      shiny::h3("Missingness and recorded states"),brohn_table(g$states,label="All saved response states"),

      if(g$quantitative)shiny::p("Histogram bins cover the complete eligible range. Bins include their lower bound; only the final bin includes its upper bound.")else shiny::p("Counts describe complete typed response values. Structured values remain whole saved values, including their order; counts are not individual option or matrix-item frequencies."),

      if(length(rows))shiny::tagList(shiny::div(class="brohn-ed-chart-wide",brohn_explicit_distribution_svg(g,offset,720L)),shiny::div(class="brohn-ed-chart-narrow",brohn_explicit_distribution_svg(g,offset,320L)))else shiny::p("No eligible values are available; no zero-valued score or chart was invented."),

      shiny::p(role="status",paste("Distribution rows",if(length(visible))offset+1L else 0L,"to",offset+length(visible),"of",length(rows),". The table and chart show this page; CSV includes every distribution row.")),

      brohn_table(visible,label="Exact distribution counts"),

      shiny::div(class="brohn-toolbar",if(offset>0)shiny::actionButton("ed_previous","Previous distribution rows"),if(offset+20L<length(rows))shiny::actionButton("ed_next","Next distribution rows")),

      shiny::div(class="brohn-toolbar",shiny::downloadButton("ed_csv","Download distribution CSV",icon=NULL),if(length(rows))shiny::downloadButton("ed_svg","Download distribution chart",icon=NULL),shiny::downloadButton("ed_json","Download distribution and provenance",icon=NULL))))})

  output$ed_csv<-shiny::downloadHandler(filename=function()paste0(group()$id,".csv"),contentType="text/csv",content=function(file)prepare_download(function(){r<-require_current();g<-brohn_find(r$body$result$groups,input$ed_group);brohn_require(!is.null(g),"Choose the current distribution.");brohn_explicit_distribution_csv(r,g,file)}))

  output$ed_svg<-shiny::downloadHandler(filename=function()paste0(group()$id,"-page-",page()+1L,".svg"),contentType="image/svg+xml",content=function(file)prepare_download(function(){r<-require_current();g<-brohn_find(r$body$result$groups,input$ed_group);brohn_require(!is.null(g),"Choose the current distribution.");svg<-brohn_explicit_distribution_svg(g,page(),binding=r$body$result$binding);brohn_require(!is.null(svg),"No eligible distribution chart is available.");writeLines(enc2utf8(as.character(svg)),file,useBytes=TRUE)}))
  output$ed_json<-shiny::downloadHandler(filename=function()paste0(group()$id,".json"),contentType="application/json",content=function(file)prepare_download(function(){r<-require_current();g<-brohn_find(r$body$result$groups,input$ed_group);brohn_require(!is.null(g),"Choose the current distribution.");brohn_write_json_file(list(schema="brohn-explicit-distribution-export/1.0",binding=r$body$result$binding,group=g,policy=r$body$result$policy),file)}))

  invisible(list(clear=clear,ready=ready,job=job))

}

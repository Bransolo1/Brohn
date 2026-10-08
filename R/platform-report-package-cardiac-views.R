# Cardiac builder presentation/state helpers. No scientific or display jobs.
.brohn_rpcv_profile <- "controlled-gaze-explicit-task-choice-eda-cardiac-paired/0.2"
.brohn_rpcv_is_profile <- function(profile)isTRUE(.brohn_rpk_profile_spec(profile,FALSE)$cardiac)
.brohn_rpcv_row <- function(row)isTRUE(row$kind %in% c("ecg","ppg"))&&"cardiac" %in% unlist(row$adapters,use.names=FALSE)
.brohn_rpcv_rows <- function(rows)Filter(.brohn_rpcv_row,rows)
.brohn_rpcv_has <- function(rows)length(.brohn_rpcv_rows(rows))>0L
.brohn_rpcv_chapters <- function(mode,numbers,current=NULL) {
  if(is.null(mode))return(brohn_normalize_cardiac_figure_chapters(current))
  brohn_require(length(mode)==1L&&mode %in% c("first","selected","all"),"Choose the first, selected or all cardiac chapters.")
  values<-list()
  if(mode=="selected") {
    text<-trimws(brohn_default(numbers,""))
    brohn_require(nchar(text)<=1024L&&grepl("^[0-9]+(\\s*,\\s*[0-9]+)*$",text),"Enter chapter numbers separated by commas, for example 1, 2.")
    values<-as.list(as.numeric(trimws(strsplit(text,",",fixed=TRUE)[[1L]])))
  }
  brohn_normalize_cardiac_figure_chapters(list(schema="brohn-cardiac-figure-chapters/0.1",cells_per_chapter=10,
    chapters=list(mode=mode,numbers=values)))
}
.brohn_rpcv_request <- function(requests,ref) {
  found<-Filter(function(x).brohn_rpv_same(x$report_ref,ref),requests)
  if(length(found))found[[1L]]$display_request else brohn_normalize_cardiac_display_request()
}
.brohn_rpcv_override <- function(requests,ref,key) {
  request<-.brohn_rpcv_request(requests,ref)
  found<-Filter(function(x)identical(x$cell_key,key),request$cell_overrides)
  if(length(found))return(found[[1L]])
  first<-list(mode="first",numbers=list())
  list(cell_key=key,time_focus=NULL,waveform_windows=first,marker_pages=list(mode="all",numbers=list()),
    interval_pages=first,numerical_pages=first)
}
.brohn_rpcv_set_override <- function(requests,ref,key,value=NULL) {
  request<-.brohn_rpcv_request(requests,ref)
  request$cell_overrides<-Filter(function(x)!identical(x$cell_key,key),request$cell_overrides)
  if(!is.null(value))request$cell_overrides<-c(request$cell_overrides,list(value))
  request<-brohn_normalize_cardiac_display_request(request)
  others<-Filter(function(x)!.brohn_rpv_same(x$report_ref,ref),requests)
  if(length(request$cell_overrides))c(others,list(list(report_ref=ref,display_request=request)))else others
}
.brohn_rpcv_controls <- function(s) {
  if(!identical(s$adapter,"cardiac"))return(NULL)
  shiny::tagList(shiny::checkboxGroupInput(paste0("rpk_cardiac_components_",s$id),"Waveforms",
    c("Original input"="raw","Cleaned waveform"="clean"),selected=unlist(s$display$components)),
    shiny::checkboxInput(paste0("rpk_cardiac_intervals_",s$id),"Show saved detected intervals",s$display$show_intervals),
    shiny::checkboxInput(paste0("rpk_cardiac_spectrum_",s$id),"Show saved interval spectrum or its unavailable reason",s$display$show_spectrum))
}
.brohn_rpcv_capture_section <- function(s,input) {
  components<-input[[paste0("rpk_cardiac_components_",s$id)]]
  if(is.null(components)&&!paste0("rpk_cardiac_components_",s$id)%in%names(input))components<-unlist(s$display$components)
  brohn_require(length(components)>0L&&length(components)<=2L&&!anyDuplicated(components)&&all(components %in% c("raw","clean")),
    "Choose at least one cardiac waveform, or remove the figure section to keep evidence only.")
  s$display$components<-as.list(c("raw","clean")[c("raw","clean") %in% components])
  for(pair in list(c("intervals","show_intervals"),c("spectrum","show_spectrum"))) {
    value<-brohn_default(input[[paste0("rpk_cardiac_",pair[[1L]],"_",s$id)]],s$display[[pair[[2L]]]])
    brohn_require(is.logical(value)&&length(value)==1L&&!is.na(value),"Choose whether each saved cardiac chart is shown.")
    s$display[[pair[[2L]]]]<-value
  };s
}
brohn_report_package_cardiac_editor_summary <- function(store,rows,chapters,requests=list()) {
  cardiac<-.brohn_rpcv_rows(rows);refs<-lapply(cardiac,`[[`,"ref")
  if(!length(refs))return(NULL)
  resolved<-brohn_cardiac_chapter_requests(store,refs,chapters,lapply(refs,function(ref).brohn_rpcv_request(requests,ref)))
  empty<-lapply(Filter(function(s)s$record_count==0L,resolved$plan$sources),function(s) {
    m<-brohn_cardiac_source_metadata(store,s$report_ref)
    list(report_ref=s$report_ref,status=m$selected$status,reason=m$selected$quality$reason)
  })
  list(resolution=resolved,reports=cardiac,empty_outcomes=empty)
}
brohn_report_package_cardiac_draft_ui <- function(draft) {
  if(!isTRUE(draft$cardiac_active))return(NULL)
  chapters<-brohn_normalize_cardiac_figure_chapters(draft$cardiac_figure_chapters)
  shiny::tags$section(class="brohn-card",style="overflow-wrap:anywhere",`aria-labelledby`="rpk_cardiac_heading",
    shiny::h2(id="rpk_cardiac_heading",tabindex="-1","Cardiac findings"),
    shiny::uiOutput("rpk_cardiac_summary"),
    shiny::selectInput("rpk_cardiac_chapter_mode","Recordings to illustrate",
      c("First chapter (up to ten recordings)"="first","Choose chapters"="selected","All chapters"="all"),selected=chapters$chapters$mode),
    shiny::conditionalPanel("input.rpk_cardiac_chapter_mode === 'selected'",
      shiny::textInput("rpk_cardiac_chapter_numbers","Chapter numbers",paste(unlist(chapters$chapters$numbers),collapse=", "))),
    shiny::p("Chapter changes keep saved findings and recording view choices."),
    shiny::checkboxInput("rpk_cardiac_source_identifiers","I choose to include original participant and session identifiers",isTRUE(draft$cardiac_identifier_confirmed)),
    shiny::p("Original identifiers remain in the complete evidence. Aliases are not available for this report. Offline copies cannot be revoked."),
    shiny::uiOutput("rpk_cardiac_view_editor"))
}
brohn_report_package_cardiac_summary_ui <- function(summary,sections,requests=list(),issue=NULL) {
  if(!is.null(issue))return(shiny::p(role="status",issue," Review the chapter choice before preparing."))
  if(is.null(summary))return(shiny::p("Original recording membership is not currently available. Reopen the saved source choices before preparing."))
  resolved<-summary$resolution;p<-resolved$plan
  chapter_text<-if(!p$total_chapters)"No recording chapters"else paste(if(length(p$selected_chapters)==1L)"Chapter"else"Chapters",
    paste(unlist(p$selected_chapters),collapse=", "),"of",p$total_chapters)
  active<-Filter(function(s)identical(s$adapter,"cardiac"),sections)
  active_ref<-function(ref)any(vapply(active,function(s).brohn_rpv_same(s$source_report_ref,ref),logical(1)))
  active_count<-sum(vapply(resolved$reports,function(r)if(active_ref(r$report_ref))length(r$selected_cells)else 0L,integer(1)))
  title<-function(ref){x<-Filter(function(r).brohn_rpv_same(r$ref,ref),summary$reports);if(length(x))x[[1L]]$title else"Original saved report"}
  membership<-lapply(resolved$reports,function(r){
    cells<-lapply(r$selected_cells,function(cell){
      overridden<-length(Filter(function(x)identical(x$cell_key,cell$key),.brohn_rpcv_request(requests,r$report_ref)$cell_overrides))>0L
      shiny::div(class="brohn-stack",shiny::strong(paste("Original recording",cell$source_record_index)),
        shiny::p(paste(unlist(cell$identity,use.names=FALSE),collapse=" / ")),
        shiny::p(paste("Saved status:",cell$source_status,brohn_default(cell$original_reason,""))),
        brohn_command("View options","rpk_cardiac_view_open",list(ref=r$report_ref,key=cell$key),
          `aria-label`=paste("View options for original recording",cell$source_record_index,"from",title(r$report_ref))),
        if(!isTRUE(cell$focusable))shiny::p(brohn_default(cell$focus_reason,"This original recording has no supported waveform to focus.")),
        if(overridden)shiny::p("Saved view override retained.",brohn_command("Reset view choices","rpk_cardiac_view_reset",list(ref=r$report_ref,key=cell$key),
          `aria-label`=paste("Reset view choices for original recording",cell$source_record_index,"from",title(r$report_ref)))))
    })
    shiny::div(shiny::h3(title(r$report_ref)),if(!length(cells))shiny::p("No recording from this report is in the selected chapters; complete evidence remains included."),cells)
  })
  shiny::tagList(shiny::p(paste0(chapter_text,": ",p$selected_cells," of ",.brohn_guidance_count(p$total_cells,"original recording")," across ",.brohn_guidance_count(length(summary$reports),"saved report"),".")),
    shiny::p(if(length(active))paste0("Figures include ",.brohn_guidance_count(active_count,"recording outcome"),". Complete saved evidence stays included.")else"No cardiac figures are selected. Complete saved evidence stays included."),
    lapply(summary$empty_outcomes,function(x)shiny::p(paste(title(x$report_ref),"has no surviving saved recording records.",brohn_default(x$reason,"Its saved outcome and complete exclusion/source evidence remain included.")))),
    shiny::tags$details(shiny::tags$summary("Exact recordings and view choices"),
      shiny::p("Chapters count original recording/run records in selected-report order. ECG shows detected RR intervals; PPG shows detected pulse intervals (PRV). Neither establishes normal-to-normal beats or a stress score."),membership),
    if(sum(vapply(requests,function(x)length(x$display_request$cell_overrides),integer(1))))
      shiny::p(paste(sum(vapply(requests,function(x)length(x$display_request$cell_overrides),integer(1))),"recording view overrides retained, including recordings outside this chapter.")))
}
brohn_report_package_cardiac_view_editor_ui <- function(editor) {
  if(is.null(editor))return(NULL)
  choice<-editor$choice;first<-is.null(choice$time_focus)
  labels<-c(waveform_windows="Waveform windows",marker_pages="Detection marker pages",interval_pages="Interval pages",numerical_pages="Numerical table pages")
  shiny::div(class="brohn-card",style="overflow-wrap:anywhere",shiny::h3("Recording view options",id="rpk_cardiac_view_heading",tabindex="-1"),
    shiny::p(paste("Original recording",editor$cell$source_record_index,"|",paste(unlist(editor$cell$identity,use.names=FALSE),collapse=" / "))),
    shiny::div(hidden=NA,shiny::textInput("rpk_cardiac_view_identity",NULL,editor$token)),
    if(isTRUE(editor$cell$focusable))shiny::tagList(
      shiny::p(paste("Exact original bounds:",editor$cell$original_bounds$start_s,"to",editor$cell$original_bounds$end_s,"seconds.")),
      shiny::checkboxInput("rpk_cardiac_focus_enabled","Choose an exact time focus",!first),
      shiny::conditionalPanel("input.rpk_cardiac_focus_enabled === true",
        shiny::textInput("rpk_cardiac_focus_start","Start (original seconds)",if(first)editor$cell$original_bounds$start_s else choice$time_focus$start_s),
        shiny::textInput("rpk_cardiac_focus_end","End (original seconds)",if(first)editor$cell$original_bounds$end_s else choice$time_focus$end_s)))else
      shiny::p(paste("Time focus unavailable:",brohn_default(editor$cell$focus_reason,editor$cell$original_reason))),
    lapply(names(labels),function(field)shiny::tagList(
      shiny::selectInput(paste0("rpk_cardiac_view_",field),labels[[field]],c("First page"="first","All pages"="all","Choose pages"="selected"),selected=choice[[field]]$mode),
      shiny::conditionalPanel(sprintf("input['rpk_cardiac_view_%s'] === 'selected'",field),
        shiny::textInput(paste0("rpk_cardiac_view_",field,"_numbers"),paste(labels[[field]],"numbers"),paste(unlist(choice[[field]]$numbers),collapse=", "))))),
    shiny::p("A time focus uses one waveform window. Choose a range containing saved samples; reset the focus if the prepared range is empty. These choices affect figures and displayed pages, not complete evidence or saved measurements."),
    shiny::div(class="brohn-toolbar",shiny::actionButton("rpk_cardiac_view_apply","Save view choices"),shiny::actionButton("rpk_cardiac_view_cancel","Cancel view edit")))
}

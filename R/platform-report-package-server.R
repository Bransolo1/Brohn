# This controller owns a view, never durable prerequisite state or authority.
`$<-.brohn_rpk_response_headers` <- function(x,name,value) {
  if(identical(name,"Content-Length")&&!is.null(value)) {
    if(is.numeric(value)) {
      stopifnot(length(value)==1L,!is.na(value),is.finite(value),value>=0,value==trunc(value))
      value<-format(value,scientific=FALSE,trim=TRUE,decimal.mark=".")
    }
    stopifnot(is.character(value),length(value)==1L,grepl("^[0-9]+$",value))
  }
  classes<-class(x);class(x)<-NULL;x[[name]]<-value;class(x)<-classes;x
}
# Shiny overwrites HEAD length after the callback. Keep only this response's
# headers typed so the later file.info() double is serialized as decimal digits.
registerS3method("$<-","brohn_rpk_response_headers",`$<-.brohn_rpk_response_headers`,envir=asNamespace("base"))
.brohn_rpk_download_response <- function(req,artifact=NULL,kind=NULL) {
  missing<-is.null(artifact);body<-charToRaw("Reopen the saved report to download its current evidence.")
  headers<-list("Cache-Control"="no-store","X-Content-Type-Options"="nosniff",
    "Content-Encoding"="identity","Content-Length"=format(if(missing)length(body)else artifact$bytes,scientific=FALSE,trim=TRUE,decimal.mark="."))
  if(!missing)headers[["Content-Disposition"]]<-paste0('attachment; filename="',
    switch(kind,html="report.html",zip="report.brohn-report.zip","manifest.json"),'"')
  # Shiny can normalize HEAD to GET before this callback. Identity encoding also
  # prevents its subsequently empty HEAD body from becoming a gzip payload.
  content<-if(identical(req$REQUEST_METHOD,"HEAD"))raw(0)else if(missing)body else list(file=artifact$path,owned=FALSE)
  structure(list(status=if(missing)404L else 200L,content_type=if(missing)"text/plain; charset=UTF-8"else artifact$media_type,
    content=content,headers=structure(headers,class=c("brohn_rpk_response_headers","list"))),class="httpResponse")
}
brohn_install_report_package_server <- function(input,output,session,store,state,current,attempt=NULL,
                                                message=NULL,refresh=NULL) {
  v<-shiny::reactiveValues(scope=NULL,choices=NULL,rows=list(),sections=list(),labels=list(),draft=NULL,
    editor_tick=0L,form_identity=NULL,intent=NULL,history=NULL,selector=NULL,issue=NULL,
    generation=0L,pending=NULL,focus_token=NULL,phase="idle",automatic=FALSE,dirty=FALSE,
    opened=NULL,urls=list(),open_attempt_key=NULL,request_command=NULL,request_snapshot=NULL,recommendation_note=NULL,
    task_options=list(),metadata_key=NULL,eda_display_requests=list(),window_editor=NULL,
    cardiac_display_requests=list(),cardiac_figure_chapters=brohn_normalize_cardiac_figure_chapters(),
    cardiac_summary=NULL,cardiac_issue=NULL,cardiac_editor=NULL,source_outcomes=list())
  native<-new.env(parent=emptyenv());native$handle<-NULL
  cursors<-new.env(parent=emptyenv());cursors$sources<-list();cursors$history<-list();cursors$selector<-list()
  active<-function()identical(state$page,"report_package")&&!is.null(v$scope)
  require_active<-function(){brohn_require(active(),"Open this study's report preparation again.");brohn_hosted_require_session(store)}
  release<-function(){if(!is.null(native$handle))brohn_release_report_package_resources(native$handle)
    native$handle<-NULL;v$opened<-NULL;v$urls<-list()}
  clear_view<-function(){v$generation<-v$generation+1L;v$pending<-NULL;v$automatic<-FALSE;v$window_editor<-NULL;v$cardiac_editor<-NULL;release()}
  fail<-function(e){release();v$issue<-substr(conditionMessage(e),1L,1000L);v$phase<-"failed";v$pending<-NULL;v$automatic<-FALSE}
  safe<-function(fn)tryCatch({require_active();fn()},error=fail)
  session$onSessionEnded(function(){if(!is.null(native$handle))brohn_release_report_package_resources(native$handle);native$handle<-NULL})
  shiny::observeEvent(state$page,{if(!identical(state$page,"report_package")&&!is.null(v$scope)){clear_view();v$scope<-NULL}},ignoreNULL=FALSE,priority=150)
  ref_key<-function(ref).brohn_rpv_key(ref)
  require_form<-function()brohn_require(identical(input$rpk_form_identity,v$form_identity),"Wait for the current report choices to appear.")
  load_history<-function(cursor=NULL){v$history<-brohn_report_package_catalog(store,v$scope$study_id,v$scope$project_id,cursor=cursor)}
  load_choices<-function(cursor=NULL){if(source_pending())restore_source_pending();v$choices<-brohn_report_package_choice_descriptors(store,v$scope$study_id,v$scope$project_id,cursor=cursor)}
  normalize_sections<-function(sections)lapply(seq_along(sections),function(i){s<-sections[[i]];s$order<-as.integer(i);s})
  make_draft<-function(title,policy=.brohn_rpv_policy())list(title=title,contents_policy=policy,cardiac_identifier_confirmed=FALSE)
  editor<-function(){v$form_identity<-brohn_token();v$editor_tick<-v$editor_tick+1L}
  pages<-function(value){value<-trimws(brohn_default(value,""));if(!nzchar(value))return(NULL)
    brohn_require(nchar(value)<=512L&&grepl("^[0-9]+(\\s*,\\s*[0-9]+)*$",value),"Use page numbers separated by commas, or leave blank for all pages.")
    p<-as.numeric(trimws(strsplit(value,",",fixed=TRUE)[[1]]))
    brohn_require(length(p)<=100L&&!anyDuplicated(p)&&all(is.finite(p)&p>=1&p<=100000&p==floor(p)),"Choose distinct positive figure pages.")
    as.list(as.integer(p))}
  capture<-function(commit=TRUE){require_form();d<-v$draft
    if(commit)brohn_require(is.null(v$window_editor)&&is.null(v$cardiac_editor),"Apply or cancel the open recording-view edit before changing or preparing this report.")
    title<-trimws(brohn_default(input$rpk_title,d$title));brohn_require(nzchar(title)&&nchar(title)<=200L,"Give this report a title of 1 to 200 characters.")
    d$title<-title
    if(.brohn_rpcv_has(v$rows)){
      d$cardiac_identifier_confirmed<-isTRUE(brohn_default(input$rpk_cardiac_source_identifiers,d$cardiac_identifier_confirmed))
      d$contents_policy$identifier_mode<-if(d$cardiac_identifier_confirmed)"source_identifiers"else"package_aliases"
    }else d$contents_policy$identifier_mode<-if(isTRUE(input$rpk_source_identifiers))"source_identifiers"else"package_aliases"
    d$contents_policy$stimulus_images<-if(isTRUE(input$rpk_images))"included"else"excluded_by_choice"
    sections<-lapply(v$sections,function(s){
      if(s$adapter=="gaze-context"){
        limit<-brohn_default(input[[paste0("rpk_limit_",s$id)]],s$display$candidate_limit)
        brohn_require(brohn_number(limit,1,1000,TRUE),"Choose between 1 and 1,000 illustrated gaze candidates per exposure.")
        s$display$candidate_limit<-as.integer(limit)
      }else if(identical(s$adapter,"cardiac")){
        s<-.brohn_rpcv_capture_section(s,input)
      }else{
        page_input<-input[[paste0("rpk_pages_",s$id)]]
        if(!is.null(page_input)){
          selected<-pages(page_input)
          s$display$pages<-if(is.null(selected))"all"else"selected"
          s$display$offsets<-NULL;s$display$page_numbers<-NULL
          if(s$adapter%in%c("task-trials","task-people","choice-counts","choice-utilities","eda-events","eda-continuous"))s$display$page_numbers<-list()
          if(!is.null(selected))if(s$adapter=="explicit-distribution")s$display$offsets<-lapply(selected,function(p)(p-1L)*20L)else s$display$page_numbers<-if(.brohn_rpv_eda_adapter(s$adapter))as.list(sort(unlist(selected)))else selected
        }
        if(s$adapter=="paired-findings"){
          charts<-brohn_default(input[[paste0("rpk_charts_",s$id)]],unlist(s$display$charts))
          brohn_require(length(charts)>0L&&length(charts)<=2L&&!anyDuplicated(charts)&&all(charts%in%c("means","differences")),"Choose at least one paired figure.")
          s$display$charts<-as.list(charts)
        }
        if(s$adapter=="task-trials"){
          option<-v$task_options[[s$id]]
          scope<-brohn_default(input[[paste0("rpk_task_scope_",s$id)]],s$display$trial_scope)
          brohn_require(length(scope)==1L&&scope%in%c("all","scored"),"Choose all expected or profile test/scoring positions.")
          s$display$trial_scope<-scope
          if(!is.null(option)&&!startsWith(s$selector$scope,"all_")){
            measure<-brohn_default(input[[paste0("rpk_task_measure_",s$id)]],s$display$measure)
            brohn_require(length(measure)==1L&&measure%in%c("profile_default",unlist(option$compatible_measures)),"Choose a recorded-response measure available for this exact administration.")
            s$display$measure<-measure
            mode<-brohn_default(input[[paste0("rpk_task_mode_",s$id)]],if(identical(s$display$charts,"profile_default"))"profile_default"else"selected")
            brohn_require(length(mode)==1L&&mode%in%c("profile_default","selected"),"Choose task defaults or specific figure types.")
            if(mode=="profile_default")s$display$charts<-"profile_default"else{
              charts<-input[[paste0("rpk_task_charts_",s$id)]]
              if(is.null(charts)&&!identical(s$display$charts,"profile_default"))charts<-unlist(s$display$charts)
              brohn_require(length(charts)>0L&&!anyDuplicated(charts)&&all(charts%in%unlist(option$compatible_charts)),"Choose at least one available task figure.")
              s$display$charts<-as.list(charts)
            }
          }
        }
        if(.brohn_rpv_eda_adapter(s$adapter)){
          components<-input[[paste0("rpk_eda_components_",s$id)]]
          if(is.null(components))components<-unlist(s$display$components)
          allowed<-c("clean_us","tonic_us","phasic_us")
          brohn_require(length(components)>0L&&!anyDuplicated(components)&&all(components%in%allowed),"Choose at least one processed signal component.")
          s$display$components<-as.list(allowed[allowed%in%components])
          marker_input<-input[[paste0("rpk_eda_markers_",s$id)]]
          if(!is.null(marker_input)){
            selected<-pages(marker_input)
            s$display$marker_pages<-list(pages=if(is.null(selected))"all"else"selected",page_numbers=if(is.null(selected))list()else as.list(sort(unlist(selected))))
          }
          brohn_require("phasic_us"%in%components||identical(s$display$marker_pages,list(pages="all",page_numbers=list())),"Candidate marker pages require a phasic figure. Clear the marker-page field or include the phasic component.")
        }
      };s})
    result<-list(draft=d,sections=normalize_sections(sections))
    if(commit){v$draft<-d;v$sections<-result$sections};result}
  dirty<-function(){clear_view();v$dirty<-TRUE;v$issue<-NULL;v$phase<-"idle";v$request_command<-NULL;v$request_snapshot<-NULL;v$recommendation_note<-NULL}
  history_form_values<-function(){
    # Compare raw editor values, including invalid drafts, without validating or
    # capturing them. Command buttons and acknowledgements are not form edits.
    values<-shiny::reactiveValuesToList(input)
    pattern<-paste0("^rpk_(title$|form_identity$|source_identifiers$|images$|",
      "limit_|pages_|charts_|task_scope_|task_measure_|task_mode_|task_charts_|",
      "eda_components_|eda_markers_|cardiac_components_|cardiac_intervals_|",
      "cardiac_spectrum_|cardiac_source_identifiers$|cardiac_chapter_mode$|cardiac_chapter_numbers$)")
    keys<-sort(names(values)[grepl(pattern,names(values))]);values[keys]
  }
  history_edited<-function(p)!identical(history_form_values(),p$payload$form_values)
  preserve_history_edit<-function(){dirty();v$issue<-"Your edits are kept. Select the saved preparation again to replace them."}
  source_pending<-function()!is.null(v$pending)&&identical(v$pending$action,"include_source")
  restore_source_pending<-function(note=NULL){p<-v$pending
    if(!source_pending())return(invisible(NULL))
    v$pending<-NULL;v$phase<-p$payload$prior_phase;v$focus_token<-p$payload$prior_focus
    v$issue<-if(is.null(note))p$payload$prior_issue else note
    invisible(NULL)}
  source_scope_current<-function(){require_active();.brohn_rpk_study(store,v$scope$study_id,v$scope$project_id)
    if(!is.null(native$handle)){
      fresh<-brohn_report_package_resources_current(store,native$handle)
      brohn_require(.brohn_rpv_same(fresh$record,v$opened),"The currently opened report changed. Reopen its saved history.")
    };invisible(NULL)}
  source_safe<-function(fn,admission=FALSE)tryCatch({require_active();.brohn_rpk_study(store,v$scope$study_id,v$scope$project_id);fn()},error=function(e){
    # Preserve the old view only after its original current authority still holds.
    # Source/domain failures must not hide revoked session/project/reader access.
    tryCatch({source_scope_current();note<-substr(conditionMessage(e),1L,1000L)
      if(source_pending()){
        if(admission){ref<-v$pending$payload$ref;key<-ref_key(ref);outcomes<-v$source_outcomes
          outcomes[[key]]<-NULL;outcomes[[key]]<-list(ref=ref,reason=note)
          # Display-only failures are bounded; none confer source admission.
          v$source_outcomes<-tail(outcomes,100L)}
        restore_source_pending(note)
      }else v$issue<-note
    },error=fail)
  })
  begin_source<-function(ref){
    found<-Filter(function(row).brohn_rpv_same(row$ref,ref),v$choices$reports)
    brohn_require(length(found)==1L,"Choose findings from the current catalogue page.")
    brohn_require(length(v$rows)<8L,"This report supports up to eight saved sources.")
    brohn_require(is.null(v$window_editor)&&is.null(v$cardiac_editor),"Apply or cancel the open recording-view edit before including findings.")
    captured<-capture(FALSE)
    if(source_pending()){
      if(.brohn_rpv_same(v$pending$payload$ref,ref)&&!history_edited(v$pending))return(invisible(NULL))
      restore_source_pending()
    }
    brohn_require(is.null(v$pending),"Wait for the current preparation step before including findings.")
    payload<-list(ref=ref,scope=v$scope,cursor=v$choices$cursor,form_values=history_form_values(),
      captured=captured,prior_phase=v$phase,prior_focus=v$focus_token,prior_issue=v$issue)
    v$issue<-NULL;v$focus_token<-brohn_token()
    v$pending<-list(ticket=brohn_token(),generation=v$generation,action="include_source",payload=payload,
      label="Checking these saved findings before adding them.",passive=FALSE)
    v$phase<-"preparing"
  }
  include_source<-function(p){
    if(!is.null(v$window_editor)||!is.null(v$cardiac_editor)){
      restore_source_pending("Your recording-view edit is kept. Apply or cancel it before adding findings.");return(invisible(NULL))
    }
    brohn_require(.brohn_rpv_same(p$payload$scope,v$scope)&&.brohn_rpv_same(p$payload$cursor,v$choices$cursor)&&
      any(vapply(v$choices$reports,function(row).brohn_rpv_same(row$ref,p$payload$ref),logical(1))),
      "The source catalogue changed. Select these findings again.")
    if(history_edited(p)){dirty();v$issue<-"Your edits are kept. Select the findings again to include them.";return(invisible(NULL))}
    row<-brohn_report_package_admit_catalog_choice(store,p$payload$ref,v$scope$study_id,v$scope$project_id)
    brohn_require(length(row$adapters)>0L,brohn_default(row$reason,"These saved findings need a supported report adapter. Their existing report and exports remain available."))
    brohn_require(!any(vapply(v$rows,function(x).brohn_rpv_same(x$ref,row$ref),logical(1)))&&length(v$rows)<8L,
      "The selected findings changed. Review the current report choices.")
    had_cardiac<-.brohn_rpcv_has(v$rows);next_rows<-c(v$rows,list(row))
    next_sections<-normalize_sections(c(p$payload$captured$sections,.brohn_rpv_default_sections(list(row))))
    summary<-brohn_report_package_cardiac_editor_summary(store,next_rows,v$cardiac_figure_chapters,v$cardiac_display_requests)
    .brohn_rpk_choice_descriptor(store,row$ref,v$scope$study_id,v$scope$project_id)
    brohn_require(is.null(v$window_editor)&&is.null(v$cardiac_editor),"Apply or cancel the open recording-view edit before including findings.")
    dirty();v$draft<-p$payload$captured$draft;v$rows<-next_rows;v$sections<-next_sections;v$selector<-NULL
    v$source_outcomes[[ref_key(row$ref)]]<-NULL;v$cardiac_summary<-summary;v$cardiac_issue<-NULL
    if(!had_cardiac&&.brohn_rpcv_has(next_rows))v$draft$cardiac_identifier_confirmed<-FALSE
    if(had_cardiac||.brohn_rpcv_has(next_rows))editor()
  }
  request<-function(commit=TRUE,new_profile=FALSE){captured<-capture(commit);brohn_require(length(v$rows)>0L&&length(v$rows)<=8L,"Choose between one and eight saved reports.")
    # Reads/history retain their original version. Only an explicit new intent
    # derives a profile from the independent components of its selected sources.
    profile<-if(!new_profile&&!is.null(v$intent))v$intent$request else .brohn_rpv_profiles(v$rows)
    cardiac<-.brohn_rpcv_is_profile(profile$renderer_profile)
    brohn_require(length(captured$sections)>0L||.brohn_rpv_eda_profile(profile$renderer_profile)||cardiac,"Choose at least one supported figure section.")
    result<-list(schema="brohn-report-package-intent-request/0.1",study_id=v$scope$study_id,project_id=v$scope$project_id,
      title=captured$draft$title,report_refs=unname(lapply(v$rows,`[[`,"ref")),requested_sections=unname(captured$sections),
      contents_policy=captured$draft$contents_policy,limits_profile=profile$limits_profile,renderer_profile=profile$renderer_profile)
    if(.brohn_rpv_eda_profile(profile$renderer_profile)||cardiac)result$eda_display_requests<-.brohn_rpk_normalize_eda_requests(v$eda_display_requests,result$report_refs)
    if(cardiac){
      brohn_require(isTRUE(captured$draft$cardiac_identifier_confirmed),"Choose whether to include original participant and session identifiers before preparing this cardiac report.")
      result$schema<-"brohn-report-package-intent-request/0.2"
      result$cardiac_display_requests<-.brohn_rpcc_normalize_requests(v$cardiac_display_requests,lapply(.brohn_rpcv_rows(v$rows),`[[`,"ref"))
      result$cardiac_figure_chapters<-.brohn_rpcv_chapters(input$rpk_cardiac_chapter_mode,input$rpk_cardiac_chapter_numbers,v$cardiac_figure_chapters)
      brohn_require(is.null(v$cardiac_issue),brohn_default(v$cardiac_issue,"Review the cardiac chapter choices."))
      brohn_require(.brohn_rpv_same(result$cardiac_figure_chapters,v$cardiac_figure_chapters),"Wait for the chosen chapter membership to appear before preparing.")
    }
    result}
  start<-function(action,payload=NULL,label,passive=FALSE){require_active();release();v$issue<-NULL
    if(!passive)v$focus_token<-brohn_token()
    if(action=="open")v$open_attempt_key<-.brohn_rpv_key(payload$package_ref)
    v$pending<-list(ticket=brohn_token(),generation=v$generation,action=action,payload=payload,label=label,passive=passive)
    v$phase<-"preparing"}
  adopt<-function(view){brohn_require(identical(view$request$study_id,v$scope$study_id)&&identical(view$request$project_id,v$scope$project_id),"This preparation belongs to another study.")
    v$intent<-view;v$dirty<-FALSE;v$phase<-if(view$status%in%c("failed","cancelled","needs_attention","needs_authority","superseded"))"failed"else if(view$status=="succeeded")"ready"else"waiting"
    if(view$status=="succeeded")v$automatic<-FALSE
    refresh_prepared(view)
    invisible(view)}
  hydrate<-function(view){v$recommendation_note<-NULL;v$rows<-lapply(view$request$report_refs,function(ref)brohn_report_package_report_choice(store,ref))
    cardiac<-.brohn_rpcv_is_profile(view$request$renderer_profile)
    v$eda_display_requests<-if(.brohn_rpv_eda_profile(view$request$renderer_profile)||cardiac).brohn_rpk_normalize_eda_requests(view$request$eda_display_requests,view$request$report_refs)else list()
    v$cardiac_display_requests<-if(cardiac).brohn_rpcc_normalize_requests(view$request$cardiac_display_requests,lapply(.brohn_rpcv_rows(v$rows),`[[`,"ref"))else list()
    v$cardiac_figure_chapters<-brohn_normalize_cardiac_figure_chapters(if(cardiac)view$request$cardiac_figure_chapters else NULL)
    v$cardiac_editor<-NULL
    v$window_editor<-NULL
    v$sections<-view$request$requested_sections;v$draft<-make_draft(view$request$title,view$request$contents_policy)
    v$draft$cardiac_identifier_confirmed<-cardiac&&identical(view$request$contents_policy$identifier_mode,"source_identifiers")
    v$labels<-list();v$task_options<-list();v$selector<-NULL;refresh_cardiac();editor();refresh_prepared(view)}
  refresh_cardiac<-function(){
    v$cardiac_issue<-NULL
    v$cardiac_summary<-tryCatch(brohn_report_package_cardiac_editor_summary(store,v$rows,v$cardiac_figure_chapters,v$cardiac_display_requests),
      error=function(e){v$cardiac_issue<-substr(conditionMessage(e),1L,1000L);NULL})
    invisible(NULL)}
  prepared_sources<-function(view){if(is.null(view))return(list())
    prepared<-view$preparation$prepared_sources
    if(!is.null(prepared))return(prepared)
    # Legacy intents saved exact distribution references in their dependencies.
    # Preserve those identities; opening history must not discover a newer one.
    if(identical(view$request$renderer_profile,"controlled-gaze-explicit-paired/0.1"))return(lapply(
      Filter(function(d)!is.null(d$result_ref)&&!is.null(d$report_ref),view$dependencies),function(d)
        list(adapter="explicit-distribution",source_report_ref=d$report_ref,prepared_ref=d$result_ref)))
    list()}
  selector_preparation<-function(ref,adapter){
    if(identical(adapter,"explicit-distribution"))return("explicit-distribution")
    if(.brohn_rpv_task_adapter(adapter))return("task-display")
    if(.brohn_rpv_choice_adapter(adapter))return("choice-display")
    if(.brohn_rpv_eda_adapter(adapter))return("eda-display")
    row<-Filter(function(row).brohn_rpv_same(row$ref,ref),v$rows)
    if(!identical(adapter,"paired-findings")||length(row)!=1L)return(NULL)
    # Component identity determines the companion, never asynchronous job order.
    if(.brohn_rpv_component(row[[1]],"task"))"task-display"else if(.brohn_rpv_component(row[[1]],"choice"))"choice-display"else NULL}
  refresh_prepared<-function(view){prepared<-prepared_sources(view)
    # A history adoption precedes hydration. Do not refresh the previous editor's
    # unrelated sources under the new intent, which may have different access.
    if(!.brohn_rpv_same(unname(lapply(v$rows,`[[`,"ref")),view$request$report_refs)){v$metadata_key<-NULL;return(invisible(NULL))}
    if(!length(prepared)){
      if(!is.null(v$metadata_key)||view$status%in%c("failed","needs_attention","needs_authority")){
        v$metadata_key<-NULL;v$task_options<-list()
        if(is.null(v$selector$source_windows)){
          v$window_editor<-NULL
          if(!is.null(v$selector)&&!is.null(selector_preparation(v$selector$report_ref,v$selector$adapter)))v$selector<-NULL
        }
      }
      return(invisible(NULL))
    }
    key<-.brohn_rpv_key(list(view$intent_ref$id,prepared))
    if(identical(key,v$metadata_key))return(invisible(NULL))
    # Refresh only bounded source/catalog metadata. Never replace the requested
    # scopes/default policies with frozen resolved models during this repaint.
    v$rows<-lapply(v$rows,function(row)brohn_report_package_report_choice(store,row$ref))
    if(!is.null(v$selector)&&!is.null(selector_preparation(v$selector$report_ref,v$selector$adapter))){
      selected<-Filter(function(p)identical(p$adapter,selector_preparation(v$selector$report_ref,v$selector$adapter))&&
        .brohn_rpv_same(p$source_report_ref,v$selector$report_ref),prepared)
      binding<-if(length(selected)==1L)selected[[1L]]$prepared_ref else NULL
      cursor<-v$selector$cursor
      if(!is.null(v$window_editor)&&!.brohn_rpv_same(v$window_editor$prepared_ref,binding)){
        v$window_editor<-NULL;v$issue<-"The exact prepared view changed. Reopen the display-window editor; your saved overrides are retained."
      }
      if(!.brohn_rpv_same(v$selector$prepared_ref,binding)){cursor<-NULL;cursors$selector<-list()}
      selector_load(v$selector$report_ref,v$selector$adapter,cursor)}
    v$metadata_key<-key
    invisible(NULL)}
  open_package<-function(view){require_active();brohn_require(!is.null(view$package_ref)&&view$status=="succeeded","This report package is not ready to open.")
    opened<-brohn_open_report_package_resources(store,view$package_ref,v$scope$project_id)
    native$handle<-opened$handle;v$opened<-opened$record
    generation<-v$generation;intent_id<-view$intent_ref$id;ref<-view$package_ref;token<-brohn_token()
    urls<-lapply(names(opened$artifacts),function(kind){artifact<-opened$artifacts[[kind]]
      uri<-session$registerDataObj(paste0("report-package-",kind),list(token=token),function(data,req)shiny::isolate(tryCatch({
        require_active();brohn_require(req$REQUEST_METHOD%in%c("GET","HEAD")&&identical(generation,v$generation)&&!isTRUE(v$dirty)&&
          !is.null(v$intent)&&identical(intent_id,v$intent$intent_ref$id)&&.brohn_rpv_same(ref,v$intent$package_ref)&&
          identical(shiny::parseQueryString(brohn_default(req$QUERY_STRING,""))$key,data$token)&&
          .brohn_rpv_same(request(FALSE),v$intent$request),"This report download has expired.")
        fresh<-brohn_report_package_resources_current(store,native$handle)
        brohn_require(.brohn_rpv_same(fresh$record,opened$record)&&.brohn_rpv_same(fresh$artifacts[[kind]],artifact),"This report package no longer matches the opened evidence.")
        .brohn_rpk_download_response(req,artifact,kind)
      },error=function(e).brohn_rpk_download_response(req))))
      paste0(uri,"&key=",token)})
    v$urls<-stats::setNames(urls,names(opened$artifacts));v$phase<-"ready";v$pending<-NULL}
  advance<-function(action="advance"){view<-brohn_continue_report_package_intent(store,v$intent$intent_ref,action=action);adopt(view)
    if(view$status=="succeeded")start("open",view,"Opening the saved report and checking current access.",passive=TRUE)}
  shiny::observeEvent(input$rpk_enter,tryCatch({brohn_hosted_require_session(store);command<-input$rpk_enter
    brohn_fields(command,c("study_id","project_id","report_ref"),label="Report preparation entry")
    clear_view();v$scope<-list(study_id=command$study_id,project_id=command$project_id);state$page<-"report_package"
    v$intent<-NULL;v$rows<-list();v$sections<-list();v$labels<-list();v$selector<-NULL;v$dirty<-FALSE;v$issue<-NULL;v$open_attempt_key<-NULL
    v$task_options<-list();v$metadata_key<-NULL;v$eda_display_requests<-list();v$window_editor<-NULL
    v$cardiac_display_requests<-list();v$cardiac_figure_chapters<-brohn_normalize_cardiac_figure_chapters();v$cardiac_editor<-NULL
    v$source_outcomes<-list();cursors$sources<-list();cursors$history<-list();load_choices();load_history()
    entry<-if(!is.null(command$report_ref))brohn_report_package_report_choice(store,command$report_ref)else NULL
    refs<-if(is.null(entry))v$choices$recommended_refs else if(is.null(entry$recommended_refs))list(command$report_ref)else entry$recommended_refs
    v$recommendation_note<-if(is.null(entry))NULL else entry$recommendation_reason
    v$rows<-lapply(refs,function(ref)if(!is.null(entry)&&.brohn_rpv_same(ref,entry$ref))entry else brohn_report_package_report_choice(store,ref))
    v$sections<-.brohn_rpv_default_sections(v$rows)
    v$draft<-make_draft(paste(v$choices$study$title,"report"));refresh_cardiac();editor();v$phase<-"idle"
    session$onFlushed(function()session$sendCustomMessage("brohn-focus","brohn-main"),once=TRUE)
  },error=fail))
  source_limit<-function(rows=v$rows).brohn_rpv_single_source_limit(v$intent,rows)||.brohn_rpv_constant_coordinate_limit(v$intent,rows)
  source_limit_message<-function()if(.brohn_rpv_constant_coordinate_refusal(v$intent$preparation)).brohn_rpv_constant_coordinate_message()else .brohn_rpv_single_source_limit_message()
  prepare<-function(new_version=FALSE){
    if(source_pending())return(invisible(NULL))
    brohn_require(!source_limit(),source_limit_message())
    r<-request(new_profile=new_version||isTRUE(v$dirty)||is.null(v$intent))
    if(new_version)brohn_require(!is.null(v$intent)&&identical(v$intent$next_action,"review"),"Review this preparation before creating a new version.")
    if(!new_version&&!is.null(v$intent)&&.brohn_rpv_same(r,v$intent$request)&&!isTRUE(v$dirty)){
      if(v$intent$status=="succeeded")start("open",v$intent,"Opening your saved report.")else v$issue<-"These choices already have a saved preparation. Review its status or use Resume below."
      return()
    }
    if(!is.null(v$pending)&&v$pending$action=="save"&&.brohn_rpv_same(v$pending$payload$request,r))return()
    if(new_version)clear_view()
    if(new_version||is.null(v$request_snapshot)||!.brohn_rpv_same(r,v$request_snapshot)){v$request_command<-brohn_token();v$request_snapshot<-r}
    prior<-if(!is.null(v$intent))v$intent$intent_ref else NULL
    start("save",list(command_id=v$request_command,request=r,prior=prior),"Saving your report choices.")
  }
  shiny::observeEvent(input$rpk_prepare,safe(function()prepare()))
  shiny::observeEvent(input$rpk_prepare_new,safe(function()prepare(TRUE)))
  shiny::observeEvent(input$rpk_prepare_ack,{p<-v$pending
    if(!active()||is.null(p)||p$generation!=v$generation||!identical(p$ticket,input$rpk_prepare_ack)||v$phase!="preparing")return()
    if(p$action=="include_source"){source_safe(function()include_source(p),admission=TRUE);return()}
    safe(function(){
      if(p$action=="history"&&history_edited(p)){preserve_history_edit();return()}
      v$pending<-NULL
      if(p$action=="save"){
        x<-p$payload;view<-brohn_save_report_package_intent(store,x$command_id,x$request,
          expected_revision=if(is.null(x$prior))NULL else x$prior$revision,prior_intent_ref=x$prior)
        adopt(view);v$automatic<-TRUE;advance("advance");load_history()
      }else if(p$action=="history"){
        # History hydration can read large saved sources. Let the ordinary
        # feedback acknowledgement arrive before starting that work. The
        # ticket/generation/session checks above apply to this step as well.
        view<-brohn_read_report_package_intent(store,p$payload$ref$id,v$scope$project_id)
        adopt(view);hydrate(view);v$selector<-NULL
        if(view$status=="succeeded")start("open",view,"Opening the exact saved report.")
        else{v$focus_token<-NULL;v$automatic<-FALSE}
      }else if(p$action=="open")open_package(p$payload)
      else if(p$action%in%c("resume","retry")){v$automatic<-TRUE;advance(brohn_default(p$payload$action,p$action));load_history()}
    })})
  shiny::observe({shiny::invalidateLater(1000,session);if(!active()||is.null(v$intent)||isTRUE(v$dirty)||!is.null(v$pending))return()
    safe(function(){view<-brohn_read_report_package_intent(store,v$intent$intent_ref$id,v$scope$project_id)
      if(!.brohn_rpv_same(view,v$intent)){adopt(view);load_history(if(is.null(v$history))NULL else v$history$cursor)}
      if(view$status=="succeeded"&&is.null(native$handle)&&!identical(v$open_attempt_key,.brohn_rpv_key(view$package_ref))){start("open",view,"Opening the saved report and checking current access.",passive=TRUE);return()}
      if(isTRUE(v$automatic)&&view$next_action=="continue")advance("advance")
      if(!is.null(native$handle))brohn_report_package_resources_current(store,native$handle)
    })})
  shiny::observeEvent(input$rpk_resume,safe(function(){
    # Resume operates on the saved intent, never the replacement draft sources.
    original_rows<-lapply(v$intent$request$report_refs,function(ref)list(ref=ref))
    brohn_require(!source_limit(original_rows),source_limit_message())
    brohn_require(!is.null(v$intent)&&v$intent$next_action%in%c("resume","retry","continue"),"Review this preparation's available next step.")
    action<-if(v$intent$next_action=="retry")"retry"else"resume"
    start(action,list(action=if(v$intent$next_action=="continue")"advance"else action),if(action=="retry")"Retrying the saved report choices."else"Resuming the saved report choices.")
  }))
  shiny::observeEvent(input$rpk_reopen,safe(function(){brohn_require(!is.null(v$intent)&&v$intent$status=="succeeded","Choose a completed saved report.")
    start("open",v$intent,"Reopening the saved report and checking current access.")}))
  shiny::observeEvent(input$rpk_cancel,safe(function(){
    if(source_pending()){source_scope_current();restore_source_pending("Findings were not added. Your current choices are unchanged.");return()}
    if(!is.null(v$pending)){clear_view();v$phase<-"idle";v$issue<-"This preparation step was cancelled. Saved history is unchanged.";return()}
    brohn_require(!is.null(v$intent),"There is no saved preparation to cancel yet.")
    clear_view();adopt(brohn_cancel_report_package_intent(store,v$intent$intent_ref));load_history()}))
  shiny::observeEvent(input$rpk_back,safe(function(){id<-v$scope$study_id;study<-brohn_study(store,id);clear_view();current$study<-study;state$study_id<-id;state$page<-"study";state$stage<-"Results"
    if(is.function(refresh))refresh();session$sendCustomMessage("brohn-focus","brohn-main")}))
  shiny::observeEvent(input$rpk_source_toggle,source_safe(function(){ref<-input$rpk_source_toggle
    found<-which(vapply(v$rows,function(row).brohn_rpv_same(row$ref,ref),logical(1)))
    if(!length(found)){begin_source(ref);return(invisible(NULL))}
    brohn_require(length(found)==1L,"Choose one selected saved source.")
    capture();had_cardiac<-.brohn_rpcv_has(v$rows);dirty()
    v$rows<-v$rows[-found];v$sections<-normalize_sections(Filter(function(section)!.brohn_rpv_same(section$source_report_ref,ref),v$sections))
    v$eda_display_requests<-Filter(function(x)!.brohn_rpv_same(x$report_ref,ref),v$eda_display_requests)
    v$cardiac_display_requests<-Filter(function(x)!.brohn_rpv_same(x$report_ref,ref),v$cardiac_display_requests)
    v$selector<-NULL;refresh_cardiac();if(had_cardiac||.brohn_rpcv_has(v$rows))editor()
  }))
  shiny::observeEvent(input$rpk_section_remove,safe(function(){capture();brohn_require(input$rpk_section_remove%in%vapply(v$sections,`[[`,character(1),"id"),"Choose a current figure section.")
    dirty();v$sections<-normalize_sections(Filter(function(s)s$id!=input$rpk_section_remove,v$sections))}))
  shiny::observeEvent(input$rpk_section_move,safe(function(){capture();x<-input$rpk_section_move;i<-which(vapply(v$sections,function(s)identical(s$id,x$id),logical(1)))
    brohn_require(length(i)==1L&&x$direction%in%c(-1L,1L)&&i+x$direction>=1L&&i+x$direction<=length(v$sections),"Choose a valid section position.")
    dirty();order<-seq_along(v$sections);order[c(i,i+x$direction)]<-order[c(i+x$direction,i)];v$sections<-normalize_sections(v$sections[order])}))
  selector_load<-function(ref,adapter,cursor=NULL){brohn_require(any(vapply(v$rows,function(r).brohn_rpv_same(r$ref,ref)&&adapter%in%unlist(r$adapters),logical(1))),"Choose a supported selected report.")
    preparation<-selector_preparation(ref,adapter)
    prepared<-Filter(function(p)identical(p$adapter,preparation)&&.brohn_rpv_same(p$source_report_ref,ref),prepared_sources(v$intent))
    saved_source<-!is.null(v$intent)&&any(vapply(v$intent$request$report_refs,function(r).brohn_rpv_same(r,ref),logical(1)))
    pinned_required<-isTRUE(preparation%in%c("task-display","choice-display","eda-display"))||(!is.null(preparation)&&!is.null(v$intent)&&
      (.brohn_rpk_task_profile(v$intent$request)||.brohn_rpk_choice_profile(v$intent$request)))
    if(saved_source&&pinned_required&&!length(prepared)){
      v$selector<-list(report_ref=ref,adapter=adapter,items=list(),cursor=NULL,next_cursor=NULL,
        requires_display_preparation=TRUE,state="needs_preparation",prepared_ref=NULL,locked=TRUE,
        reason=paste("This saved preparation's exact views are not available for focused figure choices. Its requested choices are retained.",brohn_default(v$intent$reason,"Follow the preparation status above.")))
    }else if(!is.null(preparation)&&length(prepared)){
      brohn_require(length(prepared)==1L,"This source has ambiguous prepared evidence. Review the saved preparation.")
      page<-brohn_report_package_selector_catalog(store,ref,adapter,cursor=cursor,prepared_ref=prepared[[1]]$prepared_ref)
      # The generic catalog need not echo its optional input reference. Retain
      # the exact verified input to keep subsequent page refreshes bound to it.
      page$prepared_ref<-prepared[[1]]$prepared_ref;v$selector<-page
    }else v$selector<-brohn_report_package_selector_catalog(store,ref,adapter,
      cursor=if(!is.null(v$selector$source_windows)&&.brohn_rpv_same(v$selector$report_ref,ref))NULL else cursor)
    # Original window metadata can be read before a display exists, including
    # after a size refusal. It is never used as a prepared figure catalog.
    if(identical(adapter,"eda-continuous")&&!length(prepared)&&
       (isTRUE(v$selector$locked)||isTRUE(v$selector$requires_display_preparation))){
      windows<-brohn_eda_source_windows(store,ref,cursor=cursor)
      brohn_require(identical(windows$schema,"brohn-eda-source-windows/0.1")&&
        identical(windows$source_family,"continuous")&&.brohn_rpv_same(windows$report_ref,ref),
        "The original recording windows do not match this selected saved source.")
      v$selector$source_windows<-windows;v$selector$cursor<-windows$cursor;v$selector$next_cursor<-windows$next_cursor
    }
    if(.brohn_rpv_task_adapter(adapter)||.brohn_rpv_choice_adapter(adapter)||.brohn_rpv_eda_adapter(adapter))for(s in v$sections)if(.brohn_rpv_same(s$source_report_ref,ref)&&identical(s$adapter,adapter)&&!startsWith(s$selector$scope,"all_")){
      item<-Filter(function(item).brohn_rpv_same(item$selector,s$selector),v$selector$items)
      if(length(item)==1L){v$labels[[s$id]]<-item[[1]]$label;v$task_options[[s$id]]<-item[[1]]$details}
    }
  }
  shiny::observeEvent(input$rpk_selector_open,safe(function(){capture();x<-input$rpk_selector_open;cursors$selector<-list();selector_load(x$ref,x$adapter)}))
  shiny::observeEvent(input$rpk_selector_close,safe(function(){v$selector<-NULL;v$window_editor<-NULL}))
  set_selector<-function(x,all=FALSE){capture();p<-v$selector;brohn_require(!is.null(p)&&.brohn_rpv_same(x$ref,p$report_ref)&&identical(x$adapter,p$adapter),"Choose a view from the current figure list.")
    item<-if(all)NULL else Filter(function(item).brohn_rpv_same(item$selector,x$selector),p$items)
    brohn_require(!isTRUE(p$locked)&&!isTRUE(p$state%in%c("unavailable_source","needs_authority"))&&(all||length(item)==1L),"Choose an available saved view from this page.")
    s<-.brohn_rpv_section(x$ref,x$adapter,if(all)NULL else x$selector);dirty()
    keep<-Filter(function(old)!(.brohn_rpv_same(old$source_report_ref,x$ref)&&old$adapter==x$adapter&&
      (all||startsWith(old$selector$scope,"all_")||old$id==s$id)),v$sections)
    v$sections<-normalize_sections(c(keep,list(s)));v$labels[[s$id]]<-if(all)NULL else item[[1]]$label
    if(.brohn_rpv_task_adapter(s$adapter))v$task_options[[s$id]]<-if(all)NULL else item[[1]]$details}
  shiny::observeEvent(input$rpk_selector_choose,safe(function()set_selector(input$rpk_selector_choose)))
  shiny::observeEvent(input$rpk_selector_all,safe(function()set_selector(input$rpk_selector_all,TRUE)))
  window_request<-function(ref){found<-Filter(function(x).brohn_rpv_same(x$report_ref,ref),v$eda_display_requests)
    if(length(found))found[[1]]$display_request else brohn_normalize_eda_display_request()}
  window_focus<-function(){target<-if(is.null(v$selector))"brohn-main"else"rpk_selector_heading"
    session$onFlushed(function()session$sendCustomMessage("brohn-focus",target),once=TRUE)}
  window_change<-function(ref,key,bounds=NULL){r<-window_request(ref)
    r$continuous_windows<-Filter(function(x)!identical(x$key,key),r$continuous_windows)
    if(!is.null(bounds))r$continuous_windows<-c(r$continuous_windows,list(list(key=key,start_s=bounds$start_s,end_s=bounds$end_s)))
    r<-brohn_normalize_eda_display_request(r)
    entries<-Filter(function(x)!.brohn_rpv_same(x$report_ref,ref),v$eda_display_requests)
    entries<-c(entries,list(list(report_ref=ref,display_request=r)))
    entries<-.brohn_rpk_normalize_eda_requests(entries,lapply(v$rows,`[[`,"ref"))
    if(!.brohn_rpv_same(entries,v$eda_display_requests)){dirty();v$eda_display_requests<-entries}else v$window_editor<-NULL
    window_focus()
  }
  shiny::observeEvent(input$rpk_eda_window_open,safe(function(){capture();x<-input$rpk_eda_window_open;p<-v$selector
    brohn_fields(x,c("ref","key"),label="Continuous display window")
    brohn_require(!is.null(p)&&identical(p$adapter,"eda-continuous")&&.brohn_rpv_same(p$report_ref,x$ref),"Choose a continuous cell from the current exact saved catalog.")
    metadata<-p$source_windows
    if(!is.null(metadata)){
      items<-Filter(function(item)identical(item$key,x$key),metadata$items)
      brohn_require(length(items)==1L&&isTRUE(items[[1]]$focusable),"This saved recording has no editable continuous display window.")
      d<-items[[1]];label<-d$label
    }else{
      brohn_require(!isTRUE(p$locked),"The exact prepared view is not available for this edit.")
      items<-Filter(function(item)identical(item$details$key,x$key),p$items)
      brohn_require(length(items)==1L&&isTRUE(items[[1]]$details$focusable),"This saved cell has no editable continuous display window.")
      d<-items[[1]]$details;label<-items[[1]]$label
    }
    overrides<-Filter(function(w)identical(w$key,x$key),window_request(x$ref)$continuous_windows)
    v$window_editor<-list(token=brohn_token(),ref=x$ref,key=x$key,prepared_ref=p$prepared_ref,label=label,
      source_binding_hash=metadata$source_binding_hash,source_cursor=metadata$cursor,
      bounds=d$original_default_bounds,requested=if(length(overrides))overrides[[1]][c("start_s","end_s")]else d$original_default_bounds)
    session$onFlushed(function()session$sendCustomMessage("brohn-focus","rpk_eda_window_heading"),once=TRUE)
  }))
  window_editor_current<-function(){require_form();e<-v$window_editor
    brohn_require(!is.null(e)&&identical(input$rpk_eda_window_identity,e$token)&&!is.null(v$selector)&&
      .brohn_rpv_same(e$ref,v$selector$report_ref)&&.brohn_rpv_same(e$prepared_ref,v$selector$prepared_ref)&&
      any(vapply(v$rows,function(row).brohn_rpv_same(row$ref,e$ref),logical(1))),"Reopen the current display-window edit.")
    if(!is.null(e$source_binding_hash)){
      brohn_require(identical(e$source_binding_hash,v$selector$source_windows$source_binding_hash)&&
        .brohn_rpv_same(e$source_cursor,v$selector$source_windows$cursor),"Reopen the current original recording window.")
      fresh<-brohn_eda_source_windows(store,e$ref,cursor=e$source_cursor)
      items<-Filter(function(item)identical(item$key,e$key),fresh$items)
      brohn_require(.brohn_rpv_same(fresh$report_ref,e$ref)&&identical(fresh$source_binding_hash,e$source_binding_hash)&&
        length(items)==1L&&isTRUE(items[[1]]$focusable)&&.brohn_rpv_same(items[[1]]$original_default_bounds,e$bounds),
        "The saved source windows changed or are no longer accessible. Reopen the current original recording window.")
    }
    e}
  shiny::observeEvent(input$rpk_eda_window_apply,safe(function(){e<-window_editor_current()
    normalized<-brohn_normalize_eda_display_request(list(schema="brohn-eda-display-request/0.1",continuous_windows=list(list(key=e$key,start_s=input$rpk_eda_start,end_s=input$rpk_eda_end))))
    bounds<-normalized$continuous_windows[[1]]
    brohn_require(brohn_eda_decimal_compare(bounds$start_s,e$bounds$start_s)>=0L&&brohn_eda_decimal_compare(bounds$end_s,e$bounds$end_s)<=0L,"Choose display bounds within this saved segment's original bounds.")
    window_change(e$ref,e$key,normalized$continuous_windows[[1]])
  }))
  shiny::observeEvent(input$rpk_eda_window_reset,safe(function(){e<-window_editor_current();window_change(e$ref,e$key)}))
  shiny::observeEvent(input$rpk_eda_window_cancel,safe(function(){require_form();v$window_editor<-NULL;window_focus()}))
  shiny::observeEvent(input$rpk_eda_override_reset,safe(function(){capture();x<-input$rpk_eda_override_reset
    brohn_fields(x,c("ref","key"),label="Saved display window reset")
    brohn_require(any(vapply(window_request(x$ref)$continuous_windows,function(w)identical(w$key,x$key),logical(1))),"Choose a current saved display override.")
    window_change(x$ref,x$key)
  }))
  cardiac_focus<-function(target="rpk_cardiac_heading")session$onFlushed(function()session$sendCustomMessage("brohn-focus",target),once=TRUE)
  cardiac_restore_chapters<-function(){
    shiny::updateSelectInput(session,"rpk_cardiac_chapter_mode",selected=v$cardiac_figure_chapters$chapters$mode)
    shiny::updateTextInput(session,"rpk_cardiac_chapter_numbers",value=paste(unlist(v$cardiac_figure_chapters$chapters$numbers),collapse=", "))
  }
  shiny::observeEvent(input$rpk_cardiac_choices,safe(function(){capture();cardiac_focus()}))
  shiny::observeEvent(list(input$rpk_cardiac_chapter_mode,input$rpk_cardiac_chapter_numbers),{
    if(!active()||!.brohn_rpcv_has(v$rows)||!identical(input$rpk_form_identity,v$form_identity))return()
    tryCatch({require_active()
      chapters<-.brohn_rpcv_chapters(input$rpk_cardiac_chapter_mode,input$rpk_cardiac_chapter_numbers,v$cardiac_figure_chapters)
      if(.brohn_rpv_same(chapters,v$cardiac_figure_chapters)&&is.null(v$cardiac_issue))return()
      brohn_require(is.null(v$cardiac_editor),"Save or cancel the recording-view edit before changing chapters.")
      summary<-brohn_report_package_cardiac_editor_summary(store,v$rows,chapters,v$cardiac_display_requests)
      capture();dirty();v$cardiac_figure_chapters<-chapters;v$cardiac_summary<-summary;v$cardiac_issue<-NULL
    },error=function(e){v$cardiac_issue<-substr(conditionMessage(e),1L,1000L)})
  },ignoreInit=TRUE)
  shiny::observeEvent(input$rpk_cardiac_section_add,safe(function(){capture();ref<-input$rpk_cardiac_section_add
    brohn_require(any(vapply(.brohn_rpcv_rows(v$rows),function(r).brohn_rpv_same(r$ref,ref),logical(1))),"Choose a selected cardiac report.")
    if(!any(vapply(v$sections,function(s)identical(s$adapter,"cardiac")&&.brohn_rpv_same(s$source_report_ref,ref),logical(1)))){
      dirty();v$sections<-normalize_sections(c(v$sections,list(.brohn_rpv_section(ref,"cardiac"))))}
  }))
  shiny::observeEvent(input$rpk_cardiac_view_open,safe(function(){capture();x<-input$rpk_cardiac_view_open
    brohn_fields(x,c("ref","key"),label="Cardiac recording view")
    refresh_cardiac();brohn_require(is.null(v$cardiac_issue),brohn_default(v$cardiac_issue,"Reopen this source."))
    reports<-Filter(function(r).brohn_rpv_same(r$report_ref,x$ref),v$cardiac_summary$resolution$reports)
    brohn_require(length(reports)==1L,"Choose a selected original cardiac report.")
    cells<-Filter(function(cell)identical(cell$key,x$key),reports[[1L]]$selected_cells)
    brohn_require(length(cells)==1L,"Choose an original recording in the current chapter.")
    v$cardiac_editor<-list(token=brohn_token(),ref=x$ref,cell=cells[[1L]],closure_hash=reports[[1L]]$closure_hash,
      choice=.brohn_rpcv_override(v$cardiac_display_requests,x$ref,x$key))
    cardiac_focus("rpk_cardiac_view_heading")
  }))
  cardiac_editor_current<-function(){require_form();e<-v$cardiac_editor
    brohn_require(!is.null(e)&&identical(input$rpk_cardiac_view_identity,e$token)&&
      any(vapply(.brohn_rpcv_rows(v$rows),function(r).brohn_rpv_same(r$ref,e$ref),logical(1))),"Reopen the current recording-view edit.")
    offset<-floor((e$cell$source_record_index-1)/100)*100
    cursor<-if(!offset)NULL else list(scope=brohn_eda_value_hash(list(report_ref=e$ref,closure_hash=e$closure_hash)),offset=offset)
    fresh<-brohn_cardiac_source_windows(store,e$ref,cursor,100L)
    cells<-Filter(function(cell)identical(cell$key,e$cell$key),fresh$items)
    brohn_require(.brohn_rpv_same(fresh$source_ref,e$ref)&&identical(fresh$closure_hash,e$closure_hash)&&length(cells)==1L&&
      .brohn_rpv_same(cells[[1L]],e$cell),
      "The original cardiac recording changed or is no longer accessible. Reopen the recording-view edit.")
    e}
  shiny::observeEvent(input$rpk_cardiac_view_apply,safe(function(){e<-cardiac_editor_current();captured<-capture(FALSE)
    choice<-e$choice
    choice["time_focus"]<-list(if(isTRUE(e$cell$focusable)&&isTRUE(input$rpk_cardiac_focus_enabled))list(start_s=input$rpk_cardiac_focus_start,end_s=input$rpk_cardiac_focus_end)else NULL)
    for(field in c("waveform_windows","marker_pages","interval_pages","numerical_pages")){
      mode<-brohn_default(input[[paste0("rpk_cardiac_view_",field)]],choice[[field]]$mode)
      numbers<-if(identical(mode,"selected"))pages(input[[paste0("rpk_cardiac_view_",field,"_numbers")]])else list()
      choice[[field]]<-list(mode=mode,numbers=brohn_default(numbers,list()))
    }
    entries<-.brohn_rpcv_set_override(v$cardiac_display_requests,e$ref,e$cell$key,choice)
    normalized<-.brohn_rpcv_override(entries,e$ref,e$cell$key)
    if(!is.null(normalized$time_focus))brohn_require(brohn_eda_decimal_compare(normalized$time_focus$start_s,e$cell$original_bounds$start_s)>=0L&&
      brohn_eda_decimal_compare(normalized$time_focus$end_s,e$cell$original_bounds$end_s)<=0L,
      "Choose a time focus within this original recording's exact bounds.")
    # Saving an editor changes transient choices only. Preparation is explicit.
    v$draft<-captured$draft;v$sections<-captured$sections
    dirty();v$cardiac_display_requests<-entries;refresh_cardiac();cardiac_restore_chapters();cardiac_focus()
  }))
  shiny::observeEvent(input$rpk_cardiac_view_cancel,safe(function(){require_form();v$cardiac_editor<-NULL;v$cardiac_issue<-NULL;cardiac_restore_chapters();cardiac_focus()}))
  shiny::observeEvent(input$rpk_cardiac_view_reset,safe(function(){capture();x<-input$rpk_cardiac_view_reset
    brohn_fields(x,c("ref","key"),label="Cardiac view reset")
    brohn_require(any(vapply(.brohn_rpcv_rows(v$rows),function(r).brohn_rpv_same(r$ref,x$ref),logical(1)))&&
      any(vapply(.brohn_rpcv_request(v$cardiac_display_requests,x$ref)$cell_overrides,function(o)identical(o$cell_key,x$key),logical(1))),
      "Choose a current saved recording override.")
    entries<-.brohn_rpcv_set_override(v$cardiac_display_requests,x$ref,x$key)
    dirty();v$cardiac_display_requests<-entries;refresh_cardiac();cardiac_focus()
  }))
  page_next<-function(kind){capture_if<-kind!="history";if(capture_if)capture()
    p<-switch(kind,sources=v$choices,history=v$history,selector=v$selector);if(is.null(p)||is.null(p$next_cursor))return()
    cursors[[kind]]<-c(cursors[[kind]],list(p$cursor));switch(kind,sources=load_choices(p$next_cursor),history=load_history(p$next_cursor),selector=selector_load(p$report_ref,p$adapter,p$next_cursor))}
  page_previous<-function(kind){stack<-cursors[[kind]];if(!length(stack))return();if(kind!="history")capture()
    cursor<-stack[[length(stack)]];cursors[[kind]]<-head(stack,-1L)
    switch(kind,sources=load_choices(cursor),history=load_history(cursor),selector=selector_load(v$selector$report_ref,v$selector$adapter,cursor))}
  for(kind in c("sources","history","selector"))local({k<-kind
    shiny::observeEvent(input[[paste0("rpk_",k,"_next")]],safe(function()page_next(k)))
    shiny::observeEvent(input[[paste0("rpk_",k,"_previous")]],safe(function()page_previous(k)))})
  shiny::observeEvent(input$rpk_history_latest,safe(function(){cursors$history<-list();load_history()}))
  shiny::observeEvent(input$rpk_history_open,safe(function(){ref<-input$rpk_history_open
    brohn_require(any(vapply(v$history$items,function(item).brohn_rpv_same(item$intent_ref,ref),logical(1))),"Choose a preparation from the current history page.")
    clear_view();start("history",list(ref=ref,form_values=history_form_values()),"Opening this saved preparation.")
  }))
  shiny::observe({
    if(!active())return()
    if(source_pending()){
      if(history_edited(v$pending)){dirty();v$issue<-"Your edits are kept. Select the findings again to include them."}
      return()
    }
    if(!is.null(v$pending)&&v$pending$action=="history"){
      if(history_edited(v$pending))preserve_history_edit()
      return()
    }
    if(isTRUE(v$dirty)||!is.null(v$cardiac_editor)||!identical(input$rpk_form_identity,v$form_identity))return()
    expected<-if(!is.null(v$pending)&&v$pending$action=="save")v$pending$payload$request else if(!is.null(v$intent))v$intent$request else NULL
    if(is.null(expected))return()
    fresh<-tryCatch(request(FALSE,new_profile=!is.null(v$pending)&&v$pending$action=="save"),error=function(e)NULL)
    if(is.null(fresh)||!.brohn_rpv_same(fresh,expected))dirty()
  },priority=100)
  output$rpk_context<-shiny::renderUI({if(!active()||is.null(v$choices))return(NULL)
    shiny::p(paste("Study:",v$choices$study$title,". Saved report versions determine the design and findings in this package."))})
  output$rpk_editor<-shiny::renderUI({if(!active())return(NULL);v$editor_tick
    shiny::isolate({if(is.null(v$draft))NULL else{d<-v$draft;d$form_identity<-v$form_identity
      d$cardiac_active<-.brohn_rpcv_has(v$rows);d$cardiac_figure_chapters<-v$cardiac_figure_chapters;brohn_report_package_editor_ui(d)}})})
  output$rpk_prepare_action<-shiny::renderUI({if(!active()||is.null(v$draft)||source_limit())return(NULL)
    shiny::actionButton("rpk_prepare","Prepare report",class="btn-primary",disabled=if(source_pending())"disabled"else NULL)})
  output$rpk_contents<-shiny::renderUI({if(!active())return(NULL)
    task<-.brohn_rpv_has_component(v$rows,"task");choice<-.brohn_rpv_has_component(v$rows,"choice")
    shiny::tagList(shiny::p(paste(.brohn_guidance_count(length(v$rows),"saved report"),"and",.brohn_guidance_count(length(v$sections),"figure section"),"selected. Complete numerical collections stay included, even when only selected figure pages are shown.")),
      if(choice)shiny::tagList(shiny::p("Saved best-worst results and choice models, task views, liking and other answers are included where applicable. Every selected source's complete numerical evidence stays included, even when a figure section is hidden."),
        shiny::p("These findings are shown together; no relationship between choice results, task scores and liking has been calculated. Saved models are displayed without refitting."))else if(task)shiny::tagList(shiny::p("Task scores and response patterns, liking and other answers, and saved comparisons are included where applicable. Task details are checked during preparation."),
        shiny::p("These findings are shown together; no relationship between task scores and liking has been calculated.")),
      if(.brohn_rpv_has_eda(v$rows))shiny::tagList(
        shiny::p("Skin-conductance reports retain complete saved analysis, processed streams, candidates and unavailable results for every selected or required EDA source. Related EDA sources are included as evidence without adding figures automatically."),
        shiny::p("Complete raw conductance series and raw input bytes are excluded. Any bounded raw preview and raw-derived measurements already in the saved analysis remain included."),
        shiny::p("Saved measurements are displayed without repeating decomposition or peak detection. This report does not calculate a new EDA-liking relationship.")),
      if(!is.null(v$recommendation_note))shiny::p(v$recommendation_note))})
  output$rpk_sources<-shiny::renderUI({if(!active()||is.null(v$choices))return(NULL);brohn_report_package_sources_ui(v$choices,v$rows,v$source_outcomes)})
  output$rpk_selected<-shiny::renderUI({if(!active())return(NULL);shiny::tags$ul(lapply(v$rows,function(row)shiny::tags$li(row$title," | ",row$origin," | saved version ",row$ref$revision,
    brohn_command(paste("Remove",row$title),"rpk_source_toggle",row$ref),
    if(.brohn_rpcv_row(row))brohn_command("Include cardiac figures","rpk_cardiac_section_add",row$ref),
    if(.brohn_rpv_has_eda(v$rows))lapply(Filter(function(a)!identical(a,"cardiac"),row$adapters),function(adapter)brohn_command(paste("Choose",.brohn_rpv_adapter_label(adapter)),"rpk_selector_open",list(ref=row$ref,adapter=adapter))))))})
  output$rpk_figures<-shiny::renderUI({if(!active())return(NULL)
    if(!length(v$sections)&&(.brohn_rpv_has_eda(v$rows)||.brohn_rpcv_has(v$rows)))return(shiny::p("No figures selected; complete numerical evidence is included. Choose saved views from a selected source to add figures again."))
    brohn_report_package_figures_ui(v$sections,v$labels,v$task_options,v$rows)})
  output$rpk_material_scope<-shiny::renderUI({if(!active())return(NULL)
    gaze<-any(vapply(v$rows,function(row)"gaze-context"%in%unlist(row$adapters),logical(1)))
    task<-.brohn_rpv_has_component(v$rows,"task");choice<-.brohn_rpv_has_component(v$rows,"choice")
    shiny::tagList(shiny::p(if(gaze)"This option embeds supported PNG/JPEG gaze stimulus images."else
      "No gaze source is selected. The gaze image option does not apply to this report."),
      if(choice)shiny::p("Task and choice material definitions and hashes are included as saved references. Task and choice material image bytes are not embedded in this report version. Original study design and asset exports remain available from the study.")else
      if(task)shiny::p("Task material definitions and hashes are included as saved references. Task material image bytes are not embedded in this report version. Original study design and asset exports remain available from the study."))})
  output$rpk_selector<-shiny::renderUI({if(!active()||is.null(v$selector))return(NULL);brohn_report_package_selector_ui(v$selector)})
  output$rpk_cardiac_summary<-shiny::renderUI({if(!active()||!.brohn_rpcv_has(v$rows))return(NULL)
    brohn_report_package_cardiac_summary_ui(v$cardiac_summary,v$sections,v$cardiac_display_requests,v$cardiac_issue)})
  output$rpk_cardiac_view_editor<-shiny::renderUI({if(!active())return(NULL);brohn_report_package_cardiac_view_editor_ui(v$cardiac_editor)})
  output$rpk_eda_window<-shiny::renderUI({if(!active())return(NULL);brohn_report_package_eda_window_ui(v$window_editor)})
  output$rpk_eda_windows<-shiny::renderUI({if(!active()||!length(v$eda_display_requests))return(NULL)
    shiny::tags$section(`aria-labelledby`="rpk_eda_overrides_heading",shiny::h3("Saved display-window overrides",id="rpk_eda_overrides_heading"),
      shiny::p("These source settings remain in the draft when you remove figures or choose all views. Apply prepares no data; use Prepare report after changing the draft."),
      lapply(v$eda_display_requests,function(x){row<-Filter(function(row).brohn_rpv_same(row$ref,x$report_ref),v$rows)
        shiny::div(shiny::strong(if(length(row))row[[1]]$title else"Saved source"),lapply(x$display_request$continuous_windows,function(w)
          shiny::p(paste("Cell",substr(w$key,1L,12L),"|",w$start_s,"to",w$end_s,"seconds"),brohn_command("Reset this display window","rpk_eda_override_reset",list(ref=x$report_ref,key=w$key)))))}))})
  output$rpk_history<-shiny::renderUI({if(!active()||is.null(v$history))return(NULL);brohn_report_package_history_ui(v$history)})
  output$rpk_feedback<-shiny::renderUI({if(!active())return(NULL);p<-v$pending;i<-v$intent;limited<-source_limit()
    label<-if(!is.null(v$issue))v$issue else if(!is.null(p))p$label else if(limited)"Complete source evidence exceeds this report's capacity."else if(isTRUE(v$dirty))"Report choices changed. Prepare them to create a new saved version."else if(!is.null(i))paste(.brohn_rpv_status(i$status,i$dependencies),brohn_default(i$reason,""))else"Review the contents, then prepare your report."
    shiny::div(id="rpk_status",role="status",`aria-live`="polite",tabindex="-1",
      `data-rpk-ticket`=if(is.null(p))NULL else p$ticket,`data-rpk-focus`=v$focus_token,
      `data-rpk-phase`=v$phase,`data-rpk-passive`=if(!is.null(p)&&isTRUE(p$passive))"true"else"false",
       shiny::p(label),
       if(!is.null(i)&&!isTRUE(v$dirty)&&identical(i$preparation$reason_code,"panel_limit"))shiny::p(paste(
         "These choices need",i$preparation$resolved_panel_count,"illustrated panels; the limit is",paste0(i$preparation$maximum_panels,"."),
         if(.brohn_rpv_eda_profile(i$request$renderer_profile))"Open Change contents to choose fewer figure views, components or candidate marker pages. Numerical table pages do not reduce EDA figures. Complete numerical evidence remains included."else
           "Open Change contents to choose fewer figure views or pages. Complete numerical evidence remains included.")),
        if(!is.null(i)&&(!isTRUE(v$dirty)||limited)&&.brohn_rpv_eda_profile(i$request$renderer_profile)).brohn_rpv_eda_refusal(i$preparation,v$rows,single_source_limit=limited),
        if(!limited&&!is.null(i)&&!isTRUE(v$dirty)&&identical(i$next_action,"review"))shiny::tagList(
         shiny::p("Review the reason above. A new version uses current preparation code and keeps earlier saved versions available."),
         shiny::actionButton("rpk_prepare_new","Prepare these choices as a new version")),
        if(!limited&&!is.null(i)&&!isTRUE(v$dirty)&&i$next_action%in%c("resume","retry","continue"))
        shiny::actionButton("rpk_resume",if(i$next_action=="retry")"Retry preparation"else"Resume preparation"),
      if(!is.null(i)&&i$status=="succeeded"&&is.null(native$handle)&&is.null(p)&&!isTRUE(v$dirty))shiny::actionButton("rpk_reopen","Reopen saved report"),
       if(!is.null(p)||(!is.null(i)&&i$status%in%c("prepared","waiting_for_display","ready_to_freeze","assembly_queued","needs_authority","failed","needs_attention")))shiny::actionButton("rpk_cancel","Cancel preparation"))})
  output$rpk_ready<-shiny::renderUI({if(!active())return(NULL);urls<-v$urls
    if(is.null(native$handle)||!length(urls)||isTRUE(v$dirty))return(NULL)
    shiny::tagList(shiny::h2("Your report is ready",tabindex="-1",`data-rpk-complete`=v$focus_token),
      shiny::p("The HTML contains the selected figures and bounded tables. The ZIP also contains every row in the included numerical collections and its evidence inventory."),
      shiny::div(class="brohn-toolbar",shiny::tags$a(class="btn btn-primary",href=urls$html,"Download report"),
        shiny::tags$a(class="btn btn-outline-secondary",href=urls$zip,"Download report + evidence")))})
  invisible(list(state=v))
}

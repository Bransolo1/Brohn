# Pure original choice projection and presentation. No store, replay or fitting.
.brohn_rpc_profile <- function(selection)isTRUE(selection$renderer_profile%in%c("controlled-gaze-explicit-task-choice-paired/0.1","controlled-gaze-explicit-task-choice-eda-paired/0.1","controlled-gaze-explicit-task-choice-eda-paired/0.2"))
brohn_report_package_choice_limits <- function(){x<-brohn_report_package_limits();x$profile<-"controlled-task-choice-report-package/0.1";x}
.brohn_rpc_model <- function(exercise,kind)exercise[[if(kind=="adjusted")"counts_model"else"utilities_model"]]
.brohn_rpc_catalog_model <- function(item,kind)item[[if(kind=="adjusted")"counts"else"utilities"]]
brohn_resolve_choice_report_section <- function(section,catalog) {
  s<-section;brohn_require(s$adapter%in%c("choice-counts","choice-utilities")&&brohn_array(catalog)&&length(catalog)>0L&&length(catalog)<=20L,"Choose an exact prepared choice catalog.")
  for(i in seq_along(catalog)){
    item<-catalog[[i]]
    brohn_fields(item,c("kind","key","index","exercise_id","title","profile","result_hash","design_hash","responses_hash","item_count","exposure_count","counts","utilities","compatible_adapters"),label="Choice catalog item")
    brohn_require(brohn_number(item$index,i,i,TRUE)&&brohn_valid_id(item$exercise_id)&&brohn_text(item$title,500)&&
      identical(item$profile,"object-case-paired-maxdiff/1.0")&&.brohn_rp_hash(item$design_hash)&&.brohn_rp_hash(item$responses_hash)&&brohn_number(item$exposure_count,0,20000,TRUE)&&
      identical(item$compatible_adapters,list("choice-counts","choice-utilities")),"Choice catalog order, supported profile or original identity is invalid.")
    for(kind in c("adjusted","utility")){
      model<-.brohn_rpc_catalog_model(item,kind)
      brohn_fields(model,c("model_hash","status","reason","row_count","available_count","unavailable_count","panel_cost"),label="Choice model support metadata")
      brohn_require(is.null(model$reason)||brohn_text(model$reason,10000),"Choice model support reason must be exact saved text or null.")
    }
  }
  keys<-vapply(catalog,`[[`,character(1),"key");brohn_require(!anyDuplicated(keys)&&all(vapply(catalog,function(c)identical(c$kind,"exercise")&&.brohn_rp_hash(c$key)&&.brohn_rp_hash(c$result_hash),logical(1))),"Choice catalog identities must be complete and unique.")
  brohn_fields(s$selector,"scope",if(identical(s$selector$scope,"exact_exercises"))"keys"else character(),"Choice selector")
  brohn_require(s$selector$scope%in%c("all_exercises","exact_exercises"),"Choose all or exact saved exercises.")
  selected<-catalog
  if(s$selector$scope=="exact_exercises"){
    requested<-s$selector$keys;brohn_require(brohn_array(requested)&&length(requested)>0L&&!anyDuplicated(unlist(requested))&&all(vapply(requested,.brohn_rp_hash,logical(1)))&&all(unlist(requested)%in%keys),"A selected exercise is absent from this exact prepared catalog.")
    selected<-catalog[keys%in%unlist(requested)]
  }
  brohn_fields(s$display,c("pages","page_numbers"),label="Choice numerical pages")
  kind<-if(s$adapter=="choice-counts")"adjusted"else"utility"
  resolved<-lapply(selected,function(c){m<-.brohn_rpc_catalog_model(c,kind)
    brohn_require(.brohn_rp_hash(m$model_hash)&&brohn_number(c$item_count,3,60,TRUE)&&brohn_number(m$row_count,0,60,TRUE)&&
      brohn_number(m$available_count,0,m$row_count,TRUE)&&brohn_number(m$unavailable_count,0,m$row_count,TRUE)&&m$available_count+m$unavailable_count==m$row_count&&
      brohn_number(m$panel_cost,1,1,TRUE)&&m$status%in%if(kind=="adjusted")c("available","no_complete_pairs")else c("estimated","not_requested","unavailable"),"Prepared choice support metadata is inconsistent.")
    brohn_require(if(kind=="adjusted"||m$status=="estimated")m$row_count==c$item_count else m$row_count==0L,"Choice catalog row count differs from its model status.")
    .brohn_rpt_pages(s$display,m$row_count)
    list(key=c$key,result_hash=c$result_hash,model_hash=m$model_hash,kind=kind,status=m$status,panel_cost=1L)
  })
  s$resolved_models<-resolved;list(section=s,panel_count=length(resolved))
}
.brohn_rpc_entry <- function(entry,item) {
  brohn_fields(entry,c("ref","body","evidence"),label="Prepared choice source");.brohn_rp_ref(entry$ref,"choice_display")
  brohn_fields(entry$body,c("schema","study_id","project_id","source_family","source","preparation_profile","implementation","implementation_hash","input_binding_hash","coverage","catalog","companion_catalog","artifact","artifact_schema","retained_document","producer"),label="Saved choice display metadata")
  brohn_require(identical(entry$ref$body_hash,brohn_hash(entry$body))&&identical(entry$body$schema,"brohn-saved-choice-display/0.1")&&
    identical(entry$body$study_id,item$saved_body$study_id)&&identical(entry$body$project_id,item$ref$project_id)&&identical(entry$ref$project_id,item$ref$project_id)&&
    identical(entry$body$source_family,entry$evidence$source_family)&&identical(entry$body$preparation_profile,"saved-choice-display/0.1")&&
    identical(entry$body$artifact_schema,"brohn-choice-display-evidence/0.1")&&identical(entry$body$implementation_hash,brohn_hash(entry$evidence$implementation))&&
    .brohn_rp_same(entry$body$source,entry$evidence$source)&&.brohn_rp_same(entry$body$implementation,entry$evidence$implementation)&&
    .brohn_rp_same(entry$body$coverage,entry$evidence$coverage),"Prepared choice metadata differs from its exact complete artifact.")
  brohn_validate_choice_display_evidence(entry$evidence,item)
  catalog<-entry$body$catalog;exercises<-entry$evidence$exercises
  brohn_require(brohn_array(catalog)&&length(catalog)==length(exercises)&&.brohn_rp_same(lapply(catalog,`[[`,"key"),lapply(exercises,`[[`,"key")),"Choice catalog does not cover complete exercises in saved order.")
  for(i in seq_along(exercises)){
    e<-exercises[[i]];c<-catalog[[i]];r<-e$original_result;b<-e$result_binding
    brohn_require(c$index==i&&c$index==b$index&&identical(c$result_hash,b$hash)&&identical(c$exercise_id,b$exercise_id)&&
      identical(c$title,r$design$title)&&identical(c$profile,r$profile)&&identical(c$design_hash,r$design_hash)&&identical(c$responses_hash,r$responses_hash)&&
      c$item_count==length(r$items)&&c$exposure_count==length(r$exposures)&&identical(c$compatible_adapters,list("choice-counts","choice-utilities")),"Choice catalog binding or count differs from original evidence.")
    for(kind in c("adjusted","utility")){
      m<-.brohn_rpc_model(e,kind);cm<-.brohn_rpc_catalog_model(c,kind);available<-sum(vapply(m$rows,function(row)!is.null(row$value),logical(1)))
      brohn_require(identical(cm$model_hash,brohn_hash(m))&&identical(cm$status,m$status)&&.brohn_rp_same(cm$reason,m$reason)&&
        cm$row_count==length(m$rows)&&cm$available_count==available&&cm$unavailable_count==length(m$rows)-available&&cm$panel_cost==1L,"Choice catalog support does not match its complete prepared model.")
    }
  };invisible(entry)
}
.brohn_rpc_find_entry <- function(bundle,item) {
  brohn_require(brohn_array(bundle$choice_displays),"Prepared choice sources must be an ordered array.")
  hits<-Filter(function(e).brohn_rp_same(e$evidence$source$report_ref,item$ref),bundle$choice_displays)
  brohn_require(length(hits)==as.integer(length(item$complete_analysis$choice_tasks)>0L),"Each choice-bearing report requires exactly one complete prepared choice artifact.")
  if(!length(hits))return(NULL)
  .brohn_rpc_entry(hits[[1L]],item);hits[[1L]]
}
.brohn_rpc_result <- function(result,aliases,ns) {
  out<-result
  out$exposures<-lapply(result$exposures,function(r).brohn_rp_project(r,aliases,ns,"choice/exposures/*",r$participant_id,r$session_id))
  if("collection_evidence"%in%names(result))out["collection_evidence"]<-list(lapply(result$collection_evidence,function(t){
    matches<-Filter(function(r)identical(r$id,t$response_id),result$exposures)
    brohn_require(length(matches)==1L&&identical(t$run_id,matches[[1L]]$session_id),"Choice timing has no unique matching original exposure/run.")
    r<-matches[[1L]];.brohn_rp_project(t,aliases,ns,"choice/collection_evidence/*",r$participant_id,r$session_id)
  }))
  out
}
.brohn_rpc_analysis <- function(item,projected,aliases,ns) {
  original<-item$complete_analysis
  projected$choice_tasks<-lapply(original$choice_tasks,.brohn_rpc_result,aliases=aliases,ns=ns)
  if(identical(original$kind,"explicit_choice")){
    brohn_require(length(original$choice_tasks)==1L&&.brohn_rp_same(original$observations,original$choice_tasks[[1L]]$exposures),"Imported choice observations differ from the original exposure sequence.")
    projected$observations<-projected$choice_tasks[[1L]]$exposures
    mapping<-original$parameters$mapping;responses<-original$observations;aliased<-projected$observations
    projected$source_rows<-lapply(original$source_rows,function(row){
      out<-row
      if(isTRUE(row$selected)){
        at<-which(vapply(responses,function(r)identical(r$id,row$response_id),logical(1)));brohn_require(length(at)==1L,"Selected original choice row has no unique response.")
        for(role in c("participant","session","exposure")){
          column<-mapping[[paste0(role,"_column")]];field<-paste0(role,"_id")
          brohn_require(identical(row$mapped_cells[[column]],responses[[at]][[field]]),"Mapped identity cell differs from its original response.")
          out$mapped_cells[column]<-list(aliased[[at]][[field]])
        }
      }else brohn_require(is.null(row$response_id)&&!"mapped_cells"%in%names(row),"Excluded choice rows cannot acquire invented mapped cells.")
      out
    })
  };projected
}
.brohn_rpc_write_complete <- function(entry,item,projection,aliases,ns,json,csv) {
  evidence<-entry$evidence;projected<-evidence;collections<-list()
  projected$exercises<-lapply(seq_along(evidence$exercises),function(i){e<-evidence$exercises[[i]];e$original_result<-projection$analysis$choice_tasks[[i]];e})
  json(list(schema="brohn-portable-choice-display/0.1",source_ref=entry$ref,source_report_ref=item$ref,original_artifact=entry$body$artifact,
    identifier_mode=aliases$mode,evidence=projected,projection_policy="Complete original scientific values with named person/session/exposure/step/clock aliases. Opaque producer response IDs and all original hash bindings remain unchanged; projection bytes have their own manifest hashes. No fit or score was rerun."),
    paste0("evidence/choices/",ns,".json"),"complete_choice_display_projection")
  for(i in seq_along(projected$exercises)){
    r<-projected$exercises[[i]]$original_result;stem<-paste0("data/choices/",ns,"-exercise-",sprintf("%03d",i))
    values<-list(items=r$items,exposures=r$exposures,utilities=r$model$utilities)
    if("probabilities"%in%names(r$model))values["probabilities"]<-list(r$model$probabilities)
    if("collection_evidence"%in%names(r))values["timing"]<-list(r$collection_evidence)
    for(field in c("items","exposures","utilities","probabilities","timing")){
      present<-field%in%names(values);path<-if(present)paste0(stem,"-",field,".csv")else NULL
      if(present)csv(values[[field]],path,paste0("complete_choice_",field))
      collections[[length(collections)+1L]]<-list(exercise_index=i,collection=field,state=if(!present)"absent_by_schema"else if(!length(values[[field]]))"present_empty"else"complete",rows=if(present)length(values[[field]])else NULL,path=path)
    }
  }
  if("source_rows"%in%names(projection$analysis))csv(projection$analysis$source_rows,paste0("data/choices/",ns,"-source-rows.csv"),"complete_choice_source_rows")
  list(entry=entry,projected=projected,collections=collections)
}
.brohn_rpc_explanation <- function(model) {
  if(identical(model$kind,"adjusted"))return(if(model$status=="available")
    list(title="Best-worst counts are available",reason="Complete recorded best-worst pairs contribute to each item's denominator.")else
    list(title="Best-worst counts are unavailable",reason="No complete best-worst pair was recorded. Missing responses are retained and are not interpreted as indifference."))
  if(model$status=="estimated")return(list(title="Saved choice utilities are available",reason="These are the existing aggregate relative utilities, with their original saved support."))
  if(model$status=="not_requested")return(list(title="Choice utilities were not requested",reason="Aggregate fitting was disabled in the saved study, so no utility values were created."))
  reason<-switch(brohn_default(model$reason,""),
    no_complete_pairs="No complete best-worst pair was recorded, so no choice utilities could be estimated.",
    disconnected_answered_item_design="The recorded comparisons do not connect all items, so the saved model could not place them on one common scale.",
    "complete_or_quasi_separation; no finite unpenalised aggregate MLE"="The recorded choices do not support a finite aggregate estimate.",
    numerical_failure="An error prevented the saved model from producing an estimate.",
    nonconvergence="The saved model did not meet its convergence requirements.",
    insufficient_numerical_information="The saved model had insufficient numerical information for a stable estimate.",
    "The saved model did not supply an available estimate. Its original diagnostic reason remains in the complete evidence.")
  list(title="Choice utilities are unavailable",reason=reason)
}
.brohn_rpc_unavailable_svg <- function(model) {
  explanation<-.brohn_rpc_explanation(model);title<-explanation$title;reason<-explanation$reason
  lines<-strwrap(reason,width=68L);height<-max(220L,120L+length(lines)*24L);id<-paste0("choice-unavailable-",substr(brohn_hash(model),1,16))
  shiny::tags$svg(xmlns="http://www.w3.org/2000/svg",viewBox=paste(0,0,820,height),role="img",focusable="false",`aria-labelledby`=paste(id,paste0(id,"-desc")),style="display:block;width:100%;height:auto;max-width:100%;background:#131d24;font-family:system-ui,sans-serif",
    shiny::tags$title(id=id,title),shiny::tags$desc(id=paste0(id,"-desc"),paste(reason,"No utility, zero value or uncertainty was invented.")),
    shiny::tags$text(x=24,y=42,fill="#edf2f2",`font-size`=20,title),lapply(seq_along(lines),function(i)shiny::tags$text(x=24,y=60+i*24,fill="#edf2f2",`font-size`=16,lines[[i]])),
    shiny::tags$text(x=24,y=height-28L,fill="#bdcbd0",`font-size`=14,"Complete saved counts and model evidence remain in the numerical companions."))
}
.brohn_rpc_label_items <- function(svg) {
  # Duplicate researcher labels remain separate exact items. Keep chart text and
  # geometry unchanged, and expose the immutable item key in each accessible title.
  visit<-function(node){if(inherits(node,"shiny.tag")){
    id<-node$attribs[["data-item-id"]]
    if(!is.null(id))node$children<-lapply(node$children,function(child){
      if(inherits(child,"shiny.tag")&&identical(child$name,"title"))child$children<-c(list(paste0("Item ",id,": ")),child$children)
      child
    })
    node$children<-lapply(node$children,visit)
  }else if(is.list(node))node<-lapply(node,visit);node};visit(svg)
}
.brohn_rpc_section <- function(s,p,prefix,figure,json,csv,friendly) {
  choice<-p$choice;brohn_require(!is.null(choice)&&.brohn_rp_same(choice$entry$ref,s$source_ref),"Choice section is not bound to its exact prepared artifact.")
  resolved<-brohn_resolve_choice_report_section(s,choice$entry$body$catalog)
  brohn_require(.brohn_rp_same(s$resolved_models,resolved$section$resolved_models),"Frozen choice models or statuses changed.")
  nodes<-list(shiny::tags$style(shiny::HTML(paste0(.brohn_rpt_scroll_style,".brohn-choice-chart-canvas{min-width:820px;width:100%}"))))
  available_panels<-unavailable_panels<-0L
  for(index in seq_along(s$resolved_models)){
    selected<-s$resolved_models[[index]];hits<-Filter(function(e)identical(e$key,selected$key),choice$entry$evidence$exercises)
    brohn_require(length(hits)==1L,"Choice exercise does not resolve uniquely.");e<-hits[[1L]];model<-.brohn_rpc_model(e,selected$kind);rows<-model$rows
    key<-paste0(prefix,"-choice-",sprintf("%03d",e$result_binding$index));title<-e$original_result$design$title
    unavailable<-selected$kind=="utility"&&model$status!="estimated";explanation<-.brohn_rpc_explanation(model)
    nodes<-c(nodes,list(shiny::h3(paste("Exercise",e$result_binding$index,":",title)),
      shiny::p(if(selected$kind=="adjusted")"Best choices minus worst choices, divided by complete-pair exposures containing each item. Zero means equal observed counts; no complete pair means unavailable."
        else "Saved aggregate relative logit utilities. Each complete observed pair contributes equally; these are not individual preferences or population estimates."),
      shiny::h4(explanation$title),shiny::p(explanation$reason),
      shiny::p(if(unavailable)"This is an explanatory panel, with no utility marks or numerical values. The full item definitions, recorded counts, exposures and saved model evidence remain in the evidence ZIP."
        else "The figure includes every saved item. Numerical page choices affect this table only. Full labels, exact values, exposure order and saved model evidence remain in the evidence ZIP.")))
    svg<-if(unavailable).brohn_rpc_unavailable_svg(model)else .brohn_rpc_label_items(brohn_maxdiff_svg(e$original_result,selected$kind,820L,"choice"))
    brohn_require(inherits(svg,"shiny.tag"),"A selected choice exercise must have an actual figure or explicit unavailable panel.")
    node<-figure(svg,key,list(source=choice$entry$ref,source_report=p$item$ref,exercise_key=e$key,result_hash=e$result_binding$hash,model_hash=selected$model_hash,kind=selected$kind,status=model$status,reason=model$reason,rows=rows))
    node$children[[1L]]<-.brohn_rpt_scroll(shiny::div(class="brohn-choice-chart-canvas",node$children[[1L]]),key,paste("Saved choice",selected$kind,"exercise",e$result_binding$index),"chart")
    nodes<-c(nodes,list(node,shiny::p("Chart labels may be shortened and displayed values rounded; the numerical alternatives retain the full item labels. Complete CSV typed records and SVG metadata retain exact saved values.")))
    if(unavailable)unavailable_panels<-unavailable_panels+1L else available_panels<-available_panels+1L
    pages<-.brohn_rpt_pages(s$display,length(rows))
    for(page in pages){start<-(page-1L)*50L;page_rows<-utils::head(utils::tail(rows,max(0L,length(rows)-start)),50L)
      nodes<-c(nodes,list(shiny::tags$details(shiny::tags$summary(paste("View complete item labels and values: numerical page",page)),
        .brohn_rpt_table(page_rows,paste("Saved choice item values, page",page),paste0(key,"-page-",page),c("item_id","label","value","unit","best_count","worst_count","complete_pair_exposures","missing_exposures","presented_exposures"),50L,friendly))))
    }
  }
  list(nodes=nodes,coverage=list(full_exercises=length(choice$entry$evidence$exercises),selected_exercises=length(s$resolved_models),plotted_panels=available_panels,explanatory_panels=unavailable_panels,numerical_pages_only=TRUE,complete_source_trimmed=FALSE))
}

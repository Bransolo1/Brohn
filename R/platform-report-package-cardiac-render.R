# Pure combined rendering seams. Native source ownership stays with the host.
.brohn_rpcc_render_legacy_selection <- function(s) {
  cardiac<-s$cardiac_source_requirements$selected_refs
  x<-s[setdiff(names(s),c("cardiac_display_requests","cardiac_figure_chapters","cardiac_source_requirements","cardiac_chapter_resolution"))]
  x$schema<-"brohn-report-package-selection/0.3"
  x$renderer_profile<-.brohn_rpk_profile_spec(s$renderer_profile)$legacy_renderer
  x$limits_profile<-"controlled-task-choice-eda-report-package/0.1"
  x$report_refs<-Filter(function(ref)!any(vapply(cardiac,function(c).brohn_rpca_same(c,ref),logical(1))),s$report_refs)
  x$prepared_sources<-Filter(function(p)p$adapter!="cardiac-display",s$prepared_sources)
  x$sections<-Filter(function(p)p$adapter!="cardiac",s$sections)
  x
}

.brohn_rpcc_selection_valid <- function(s) {
  brohn_fields(s,c("schema","id","intent_ref","study_id","project_id","title","report_refs","prepared_sources","sections","contents_policy","limits_profile","renderer_profile","frozen_at","coverage",
    "eda_display_requests","related_eda_refs","source_identity_graph_binding","cardiac_display_requests","cardiac_figure_chapters","cardiac_source_requirements","cardiac_chapter_resolution"),"generation","Frozen combined selection")
  brohn_require(identical(s$schema,"brohn-report-package-selection/0.4")&&brohn_report_package_cardiac_profile(s)&&
    identical(s$limits_profile,"controlled-task-choice-eda-cardiac-report-package/0.1")&&brohn_array(s$report_refs)&&length(s$report_refs)>0L&&length(s$report_refs)<=8L,
    "Use the closed combined cardiac selection and bounded exact report order.")
  .brohn_rp_contents(s$contents_policy)
  brohn_require(identical(s$contents_policy$identifier_mode,"source_identifiers"),"Combined cardiac aliases are not qualified; source identifiers must be explicit.")
  keys<-vapply(s$report_refs,.brohn_rpca_key,character(1));brohn_require(!anyDuplicated(keys),"The combined selection repeats an exact report.")
  for(ref in s$report_refs){.brohn_rpca_ref(ref);brohn_require(identical(ref$project_id,s$project_id),"A selected report belongs to another project.")}
  r<-s$cardiac_source_requirements
  brohn_fields(r,c("schema","source_admission","study_id","project_id","selected_refs","related_refs","sources","closure_bindings","requirements_hash"),label="Frozen cardiac requirements")
  brohn_require(identical(r$source_admission,.brohn_rpk_profile_spec(s$renderer_profile)$admission)&&identical(r$study_id,s$study_id)&&identical(r$project_id,s$project_id)&&
    brohn_array(r$selected_refs)&&length(r$selected_refs)>0L&&brohn_array(r$related_refs)&&brohn_array(r$sources)&&brohn_array(r$closure_bindings),"The complete cardiac requirements differ from this study/selection.")
  cardiac_keys<-vapply(r$selected_refs,.brohn_rpca_key,character(1))
  brohn_require(!anyDuplicated(cardiac_keys)&&.brohn_rpca_same(Filter(function(ref).brohn_rpca_key(ref)%in%cardiac_keys,s$report_refs),r$selected_refs),"Cardiac selected sources lost their global relative order.")
  for(v in r$sources)brohn_fields(v,c("report_ref","study_id","kind","record_count","source_ordinal","selected","required_by"),label="Frozen complete cardiac source")
  for(v in r$closure_bindings)brohn_fields(v,c("report_ref","closure_hash","closure"),label="Frozen cardiac closure")
  x<-s$cardiac_chapter_resolution
  brohn_fields(x,c("schema","plan","reports"),label="Frozen global cardiac chapters")
  brohn_require(brohn_array(x$reports)&&.brohn_rpca_same(s$cardiac_figure_chapters,brohn_normalize_cardiac_figure_chapters(s$cardiac_figure_chapters))&&
    .brohn_rpca_same(x$plan$request,s$cardiac_figure_chapters),"The frozen chapter plan differs from the selected chapter policy.")
  for(v in x$reports)brohn_fields(v,c("report_ref","closure_hash","display_request","selected_cells"),label="Resolved cardiac source chapter")
  brohn_require(.brohn_rpca_same(s$cardiac_display_requests,.brohn_rpcc_normalize_requests(s$cardiac_display_requests,r$selected_refs)),"The frozen per-source display choices are not normalized.")
  for(v in x$reports){choices<-Filter(function(d).brohn_rpca_same(d$report_ref,v$report_ref),s$cardiac_display_requests)
    wanted<-if(length(choices))choices[[1L]]$display_request else brohn_normalize_cardiac_display_request()
    wanted$figure_cells<-v$display_request$figure_cells
    brohn_require(.brohn_rpca_same(wanted,v$display_request),"The resolved chapter changed the original per-cell display choices.")}
  brohn_require(brohn_array(s$prepared_sources)&&brohn_array(s$sections)&&length(s$sections)<=100L&&
    !anyDuplicated(vapply(s$sections,`[[`,character(1),"id"))&&!anyDuplicated(vapply(s$sections,`[[`,numeric(1),"order")),"Keep exact prepared sources and distinct ordered sections.")
  cp<-Filter(function(p)identical(p$adapter,"cardiac-display"),s$prepared_sources)
  brohn_require(length(cp)==length(r$sources)&&!anyDuplicated(vapply(cp,function(p).brohn_rpca_key(p$source_report_ref),character(1)))&&
    setequal(vapply(cp,function(p).brohn_rpca_key(p$source_report_ref),character(1)),vapply(r$sources,function(v).brohn_rpca_key(v$report_ref),character(1))),"Every selected and required cardiac source needs exactly one saved preparation.")
  checked_impl<-character()
  for(p in cp){brohn_fields(p,c("adapter","source_report_ref","prepared_ref","implementation_ref"),label="Frozen cardiac preparation");.brohn_rpca_ref(p$source_report_ref);.brohn_rpca_ref(p$prepared_ref,"cardiac_display")
    ik<-brohn_eda_value_hash(p$implementation_ref)
    if(!ik%in%checked_impl){brohn_report_package_cardiac_dependencies(r,x,p$implementation_ref);checked_impl<-c(checked_impl,ik)}}
  for(h in Filter(function(h)identical(h$adapter,"cardiac"),s$sections)) {
    brohn_fields(h,c("id","adapter","adapter_version","source_report_ref","source_ref","selector","display","order","cardiac_section"),label="Frozen cardiac host section")
    .brohn_rpcc_requested_section(h[c("id","adapter","adapter_version","source_report_ref","selector","display","order")],r$selected_refs)
    p<-.brohn_rpca_one(cp,function(p).brohn_rpca_same(p$source_report_ref,h$source_report_ref),"A cardiac section has no exact preparation.")
    d<-.brohn_rpca_one(x$reports,function(v).brohn_rpca_same(v$report_ref,h$source_report_ref),"A cardiac section has no global chapter resolution.")
    expected<-c(list(schema="brohn-cardiac-report-section/0.1",id=h$id,adapter="cardiac",source_report_ref=h$source_report_ref,prepared_ref=p$prepared_ref,
      figure_cells=d$display_request$figure_cells,complete_source_evidence=TRUE),h$display,list(display_request_hash=brohn_eda_value_hash(d$display_request)))
    brohn_require(.brohn_rpca_same(h$source_ref,p$prepared_ref)&&.brohn_rpca_same(h$cardiac_section,expected),"The nested cardiac section differs from its frozen prepared/global chapter choices.")
  }
  legacy<-.brohn_rpcc_render_legacy_selection(s);.brohn_rp_selection(legacy)
  for(h in legacy$sections)brohn_require(any(vapply(legacy$report_refs,function(ref).brohn_rpca_same(ref,h$source_report_ref),logical(1))),"A noncardiac section points outside its selected subtree.")
  if(!length(legacy$report_refs))brohn_require(!length(legacy$prepared_sources)&&!length(legacy$sections)&&!length(legacy$eda_display_requests)&&!length(legacy$related_eda_refs),"Cardiac-only selection contains unrelated noncardiac dependencies.")
  legacy
}

.brohn_rpcc_render_state <- function(bundle) .brohn_rpcc_render_state_core(bundle,.brohn_rpca_same,brohn_report_package_cardiac_entry_validate)
.brohn_rpcc_render_state_core <- function(bundle,same,validate_entry) {
  brohn_fields(bundle,c("schema","selection","reports","distributions","assets","implementation","limits","task_displays","choice_displays","eda_displays","related_eda_sources","source_identity_graph",
    "cardiac_displays","related_cardiac_sources","cardiac_source_requirements","cardiac_chapter_resolution"),label="Combined report render input")
  brohn_require(identical(bundle$schema,"brohn-report-package-render-input/0.1"),"Unsupported combined render input.")
  s<-bundle$selection;legacy_selection<-.brohn_rpcc_selection_valid(s)
  brohn_require(same(bundle$cardiac_source_requirements,s$cardiac_source_requirements)&&same(bundle$cardiac_chapter_resolution,s$cardiac_chapter_resolution)&&
    brohn_array(bundle$reports)&&same(lapply(bundle$reports,`[[`,"ref"),s$report_refs)&&brohn_array(bundle$cardiac_displays)&&brohn_array(bundle$related_cardiac_sources),"Combined bundle lost its frozen ordered source or chapter binding.")
  legacy<-NULL
  if(length(legacy_selection$report_refs)) {
    legacy<-bundle[setdiff(names(bundle),c("cardiac_displays","related_cardiac_sources","cardiac_source_requirements","cardiac_chapter_resolution"))]
    legacy$selection<-legacy_selection;legacy$reports<-Filter(function(item)any(vapply(legacy_selection$report_refs,function(ref)same(ref,item$ref),logical(1))),bundle$reports)
    legacy$limits<-bundle$limits[names(brohn_report_package_eda_limits())];legacy$limits$profile<-legacy_selection$limits_profile
    .brohn_rpt_prepared_bindings(legacy,.brohn_rpe_lookup(legacy))
  }else brohn_require(!length(bundle$distributions)&&!length(bundle$task_displays)&&!length(bundle$choice_displays)&&!length(bundle$eda_displays)&&!length(bundle$related_eda_sources)&&!length(bundle$assets),"Cardiac-only bundle contains unexpected noncardiac payloads.")
  requirements<-s$cardiac_source_requirements;entries<-bundle$cardiac_displays
  brohn_require(length(entries)==length(requirements$sources)&&same(lapply(entries,function(e)e$evidence$source_ref),lapply(requirements$sources,`[[`,"report_ref")),"Cardiac entries differ from the complete requirements order.")
  dependency_sets<-list()
  for(e in entries){validate_entry(e)
    p<-.brohn_rpca_one(s$prepared_sources,function(p)p$adapter=="cardiac-display"&&same(p$source_report_ref,e$evidence$source_ref),"Missing exact cardiac prepared source.")
    brohn_require(same(e$ref,p$prepared_ref)&&identical(e$body$implementation_hash,p$implementation_ref$hash)&&identical(e$body$preparation_profile,p$implementation_ref$profile),"The render cardiac entry changed its exact saved preparation or implementation.")
    ik<-brohn_eda_value_hash(p$implementation_ref)
    if(is.null(dependency_sets[[ik]]))dependency_sets[[ik]]<-brohn_report_package_cardiac_dependencies(requirements,s$cardiac_chapter_resolution,p$implementation_ref)
    deps<-dependency_sets[[ik]]
    dep<-.brohn_rpca_one(deps,function(d)same(d$report_ref,e$evidence$source_ref),"Missing frozen cardiac dependency.")
    brohn_require(same(e$body$display_request,dep$display_request),"The saved preparation does not match the global chapter request.")
  }
  lookup<-function(ref_or_item){ref<-if("ref"%in%names(ref_or_item))ref_or_item$ref else ref_or_item
    hits<-Filter(function(e)same(e$evidence$source_ref,ref),entries);brohn_require(length(hits)<=1L,"Duplicate exact cardiac entry.");if(length(hits))hits[[1L]]else NULL}
  metadata<-lapply(requirements$selected_refs,function(ref)lookup(ref)$source_metadata)
  brohn_require(same(brohn_report_package_cardiac_requirements(metadata,requirements$selected_refs,s$study_id,s$project_id,source_admission=.brohn_rpk_profile_spec(s$renderer_profile)$admission),requirements),"The complete cardiac metadata differs from the frozen closure requirements.")
  brohn_require(same(lapply(bundle$related_cardiac_sources,function(x)x$report$ref),requirements$related_refs),"The required cardiac parent export membership changed.")
  for(v in bundle$related_cardiac_sources){brohn_fields(v,c("source_ordinal","report","required_by","prepared_ref"),label="Required cardiac source")
    req<-.brohn_rpca_one(requirements$sources,function(r)same(r$report_ref,v$report$ref),"Unexpected related cardiac source.")
    brohn_require(v$source_ordinal==req$source_ordinal&&same(v$required_by,req$required_by)&&same(v$prepared_ref,lookup(v$report$ref)$ref),"The related cardiac source binding changed.")}
  all<-c(bundle$reports,lapply(bundle$related_eda_sources,`[[`,"report"),lapply(bundle$related_cardiac_sources,`[[`,"report"))
  brohn_require(length(all)<=32L&&!anyDuplicated(vapply(all,function(i).brohn_rpca_key(i$ref),character(1))),"The complete report union is duplicate or oversized.")
  for(item in all){brohn_fields(item,c("ref","saved_body","complete_analysis"),label="Complete original source")
    brohn_require(identical(item$ref$body_hash,brohn_hash(item$saved_body))&&identical(item$ref$id,item$saved_body$id)&&identical(item$ref$project_id,s$project_id)&&identical(item$saved_body$study_id,s$study_id),"An original report lost its exact study/body binding.")
    e<-lookup(item$ref);if(!is.null(e))brohn_require(same(item,.brohn_rpca_one(e$source_reports,function(x)same(x$ref,item$ref),"The cardiac source entry omits its original report.")),"The original cardiac report differs from its complete held entry.")}
  artifacts<-unlist(lapply(all,function(i)if(i$complete_analysis$kind%in%c("ecg","ppg","eda"))i$complete_analysis$artifacts else list()),recursive=FALSE)
  physical<-if(length(artifacts))artifacts[!duplicated(vapply(artifacts,`[[`,character(1),"hash"))]else list()
  usage<-list(sources=length(all),stream_bytes=sum(vapply(physical,`[[`,numeric(1),"size")),rows=sum(vapply(artifacts,`[[`,numeric(1),"rows")),tables=sum(vapply(artifacts,`[[`,numeric(1),"tables")),
    prepared_bytes=sum(vapply(entries,function(e)e$body$artifact$bytes,numeric(1)))+sum(vapply(bundle$eda_displays,function(e)e$evidence$bytes,numeric(1))),
    cardiac_projection_bytes=sum(vapply(entries,function(e)sum(vapply(e$body$payloads,`[[`,numeric(1),"bytes")),numeric(1))))
  for(n in c("stream_bytes","rows","tables","prepared_bytes","cardiac_projection_bytes"))brohn_require(usage[[n]]<=switch(n,stream_bytes=96*1024^2,rows=1000000,tables=256,prepared_bytes=48*1024^2,cardiac_projection_bytes=192*1024^2),paste("The complete shared",n,"budget is exceeded; select fewer sources. Figures cannot trim complete evidence."))
  legacy_all<-if(is.null(legacy))list()else .brohn_rpe_all_reports(legacy)
  namespace<-function(ref){at<-which(vapply(legacy_all,function(i)same(i$ref,ref),logical(1)));brohn_require(length(at)==1L,"No unique exact noncardiac namespace exists for this source.");sprintf("report-%02d",at)}
  list(legacy_bundle=legacy,cardiac_lookup=lookup,all_reports=all,noncardiac_namespace=namespace,usage=usage)
}

.brohn_rpcc_panel_preflight <- function(bundle,state) {
  old<-if(is.null(state$legacy_bundle))list(section_counts=list())else brohn_report_package_panel_preflight(state$legacy_bundle,.brohn_rpe_lookup(state$legacy_bundle))
  counts<-c(old$section_counts,lapply(Filter(function(h)h$adapter=="cardiac",bundle$selection$sections),function(h)list(section_id=h$id,panel_count=brohn_resolve_cardiac_report_section(h$cardiac_section,state$cardiac_lookup(h$source_report_ref))$panel_count)))
  total<-sum(vapply(counts,`[[`,numeric(1),"panel_count"));maximum<-bundle$limits$max_panels
  if(total>maximum)return(list(schema="brohn-report-package-refusal/0.1",reason_code="panel_limit",resolved_panel_count=total,maximum_panels=maximum,section_counts=counts))
  list(schema="brohn-report-package-panel-preflight/0.1",passed=TRUE,resolved_panel_count=total,maximum_panels=maximum,section_counts=counts)
}
.brohn_rpcc_write_cardiac <- function(bundle,entry,global_ordinal,out,private,json,add)brohn_report_package_cardiac_write_complete(bundle,entry,global_ordinal,out,private,json,add)

.brohn_rpcc_markers <- function(entry) {
  out<-list()
  for(i in seq_along(entry$evidence$cells)){
    cell<-entry$evidence$cells[[i]];wanted<-unique(unlist(lapply(cell$waveform_views,function(v)unlist(lapply(Filter(function(p)p$number%in%unlist(v$markers$resolved_page_numbers),v$markers$pages),`[[`,"event_rows"),recursive=FALSE)),use.names=FALSE))
    if(!length(wanted))next
    p<-entry$payloads[[sprintf("cell-%04d-markers.ndjson",i)]]
    brohn_require(!is.null(p)&&file.exists(p$object_path)&&file.info(p$object_path)$size==p$bytes&&identical(digest::digest(file=p$object_path,algo="sha256"),p$hash),"A held marker companion changed before rendering.")
    con<-file(p$object_path,"rt",encoding="UTF-8");rows<-list();seen<-numeric()
    tryCatch(repeat{line<-readLines(con,n=1L,warn=FALSE);if(!length(line))break
      brohn_require(nchar(line,type="bytes")<=2*1024^2,"A marker row exceeds the bounded render transport.")
      m<-brohn_parse(.brohn_edd_json_text(line),max_bytes=2*1024^2+1024L)
      if(m$event_row_index%in%wanted){brohn_require(!m$event_row_index%in%seen,"A selected marker row is duplicated.");seen<-c(seen,m$event_row_index);rows[[length(rows)+1L]]<-m}
    },finally=close(con))
    brohn_require(setequal(seen,wanted)&&identical(digest::digest(file=p$object_path,algo="sha256"),p$hash),"The exact selected marker rows are missing or changed.")
    out[[cell$catalogue$key]]<-rows
  };out
}

.brohn_rpcc_render_cardiac_section <- function(hostsection,entry,prefix,figure,chapterresolution,payload_prefix) {
  resolved<-brohn_resolve_cardiac_report_section(hostsection$cardiac_section,entry)
  .brohn_rpcc_render_section_core(hostsection,entry,prefix,figure,chapterresolution,payload_prefix,resolved,
    brohn_report_package_cardiac_overview(entry,chapterresolution))
}
.brohn_rpcc_render_section_core <- function(hostsection,entry,prefix,figure,chapterresolution,payload_prefix,resolved,overview) {
  s<-hostsection$cardiac_section
  brohn_require(.brohn_rpca_same(hostsection$source_ref,entry$ref)&&.brohn_rpca_same(hostsection$source_report_ref,entry$evidence$source_ref)&&is.function(figure)&&
    grepl("^evidence/cardiac/source-[0-9]{3}/$",payload_prefix),"The cardiac renderer needs its exact host section and public evidence prefix.")
  selected<-vapply(Filter(function(m)m$selected,resolved$models),`[[`,character(1),"key");captured<-list();coverage<-list()
  callback<-function(svg,key,metadata){keep<-metadata$cell_key%in%selected&&switch(metadata$kind,waveform=metadata$component%in%unlist(s$components),intervals=s$show_intervals,spectrum=s$show_spectrum,FALSE)
    if(keep){captured[[length(captured)+1L]]<<-list(node=figure(svg,key,metadata),metadata=metadata);coverage[[length(coverage)+1L]]<<-c(list(key=key),metadata)};NULL}
  brohn_cardiac_report_figures(entry$evidence,.brohn_rpcc_markers(entry),entry$analysis,prefix,callback)
  brohn_require(length(captured)==resolved$panel_count,"Actual cardiac figures differ from the complete-model preflight count.")
  text_value<-function(v)if(is.null(v))"Unavailable"else if(is.numeric(v))if(v==trunc(v)&&abs(v)<1e6)format(v,trim=TRUE,scientific=FALSE)else .brohn_rpc_label(v)else as.character(v)
  chapter<-chapterresolution$plan
  nodes<-list(shiny::h2(overview$title),shiny::p(class="cardiac-support",paste(overview$basis,"|",overview$total_cells,"saved runs;",length(selected),"in this section's figure chapter.")),
    shiny::p(class="cardiac-caption","Source identifiers are retained. Every saved run and measure is included below and in the complete evidence. Display labels are rounded; the evidence retains exact values."))
  if(!is.null(overview$outcome))nodes<-c(nodes,list(shiny::p(overview$outcome)))
  if(!is.null(chapter))nodes<-c(nodes,list(shiny::p(class="cardiac-caption",paste("Global chapters:",if(length(chapter$selected_chapters))paste(unlist(chapter$selected_chapters),collapse=", ")else "none","of",chapter$total_chapters,";",chapter$selected_cells,"of",chapter$total_cells,"original runs selected.")),shiny::tags$details(shiny::tags$summary("Exact global chapter membership"),shiny::tags$pre(brohn_json(chapter,TRUE)))))
  for(c in overview$cells){table_id<-paste0(prefix,"-measures-",c$index)
    table_context<-paste("report section",hostsection$order,"- source",as.integer(sub("^evidence/cardiac/source-([0-9]{3})/$","\\1",payload_prefix)),"-",c$label)
    rows<-lapply(c$measures,function(m)shiny::tags$tr(shiny::tags$th(scope="row",m$label),shiny::tags$td(text_value(m$value)),shiny::tags$td(if(is.null(m$unit))""else m$unit),shiny::tags$td(if(is.null(m$reason))""else gsub("_"," ",m$reason))))
    primary<-which(vapply(c$measures,function(m)sub("^detected_(rr|prv)_","",m$name)%in%c("mean_interval","rmssd"),logical(1)))
    table<-function(selected,id,caption)shiny::div(class="cardiac-measure-scroll",role="region",tabindex="0",`aria-labelledby`=id,shiny::tags$table(shiny::tags$caption(id=id,caption),shiny::tags$thead(shiny::tags$tr(lapply(c("Measure","Saved value","Unit","Unavailable reason"),function(x)shiny::tags$th(scope="col",x)))),shiny::tags$tbody(selected)))
    figs<-Filter(function(f)identical(f$metadata$cell_key,c$key),captured)
    detail<-shiny::tags$details(class="cardiac-source-context",shiny::tags$summary("Exact source, support and original measure fields"),shiny::tags$pre(brohn_json(list(identity=c$identity,counts=c$counts,measures=lapply(c$measures,`[[`,"original")),TRUE)))
    card<-list(shiny::h3(c$label),shiny::p(class="cardiac-support",paste("Saved status:",gsub("_"," ",c$source_status))),if(!is.null(c$reason))shiny::p(c$reason),
      if(identical(c$source_status,"computed"))shiny::p(class="cardiac-caption",paste(c$counts$peaks,"saved detections;",c$counts$intervals,"intervals;",c$counts$null_interval_rows,"rows without an interval.")),
      if(length(primary))table(rows[primary],table_id,paste("Saved measures",table_context,"scroll horizontally when needed",sep=" \u2014 ")),
      if(length(rows))shiny::tags$details(class="cardiac-all-measures",shiny::tags$summary(paste("All",length(rows),"saved measures and unavailable reasons")),table(rows,paste0(table_id,"-all"),paste("Complete saved measures",table_context,sep=" \u2014 "))),detail)
    if(length(figs))for(f in figs){m<-f$metadata;title<-switch(m$kind,waveform=if(m$component=="raw")"Input waveform"else"Cleaned waveform",intervals="Saved intervals",spectrum="Saved interval power spectrum")
      caption<-switch(m$kind,waveform=paste(m$window$requested$start_s,"to",m$window$requested$end_s,"original seconds; detection page",if(is.null(m$marker_page))"none"else m$marker_page),intervals=paste("Interval page",m$page),spectrum="Exact saved density bins; unavailable values are not invented.")
      card<-c(card,list(shiny::h4(title),shiny::p(class="cardiac-caption",caption),f$node))
      if(m$kind=="waveform"){
        cell<-entry$evidence$cells[[c$index]];view<-.brohn_rpca_one(cell$waveform_views,function(v)v$window$number==m$window$number,"Missing exact plotted waveform window.")
        card<-c(card,list(shiny::tags$details(shiny::tags$summary("Waveform scale, marks and complete support"),
          shiny::p(if(view$scale_mode=="shared")paste("Input and cleaned waveforms share the saved vertical scale in",c$unit)else paste("Input and cleaned waveforms use separate labelled vertical scales in",c$unit,"; compare axis values, not trace heights.")),
          shiny::p("Solid: retained samples. Dashed: excluded processing edges. Gaps stay disconnected. Open circles: exact saved detections from the cleaned waveform."),
          shiny::p(paste(view$markers$in_window,"detections in this window;",view$markers$source_total,"in the complete source;",view$markers$outside_window,"outside. Omitted marker pages:",if(length(view$markers$omitted_page_numbers))paste(unlist(view$markers$omitted_page_numbers),collapse=", ")else "none")),
          shiny::tags$pre(brohn_json(m$window,TRUE)))))
      }
    }else card<-c(card,list(shiny::p(if(c$key%in%selected)"No supported figure is available for this saved run."else"This run is outside the selected figure chapter. Its complete saved findings remain included.")))
    nodes<-c(nodes,list(shiny::tags$section(class="cardiac-cell",card)))
  }
  nodes<-c(nodes,list(shiny::tags$details(class="cardiac-method",shiny::tags$summary("Saved method, source outcome and interpretation limits"),shiny::tags$pre(brohn_json(list(outcome=entry$evidence$outcome,details=overview$details),TRUE))),
    shiny::p(shiny::tags$a(href=paste0(payload_prefix,"cardiac-display.json"),"Complete cardiac display evidence")," \u00b7 ",shiny::tags$a(href=paste0(payload_prefix,"projection-receipt.json"),"Complete payload inventory"))))
  list(nodes=list(shiny::div(class="cardiac-report cardiac-package",nodes)),coverage=list(cells=resolved$models,figures=coverage,figure_count=length(captured),complete_cells=resolved$complete_cells,complete_features=resolved$complete_features,identifiers="source_identifiers_preserved",scientific_values_changed=FALSE),panel_count=length(captured))
}
.brohn_rpcc_style <- function()paste0(brohn_cardiac_figure_style()," .cardiac-package{min-width:0}.cardiac-measure-scroll{max-width:100%;overflow-x:auto;overscroll-behavior-x:contain;margin:.7rem 0}.cardiac-measure-scroll:focus{outline:3px solid #155e75;outline-offset:2px}.cardiac-measure-scroll table{border-collapse:collapse;min-width:32rem;width:100%}.cardiac-measure-scroll th,.cardiac-measure-scroll td{text-align:left;vertical-align:top;padding:.5rem;border-bottom:1px solid #cbd5e1}.cardiac-measure-scroll caption{text-align:left;font-size:.9rem}.cardiac-package pre{white-space:pre-wrap;overflow-wrap:anywhere}.cardiac-package details{margin:.6rem 0}.cardiac-package .cardiac-cell{margin:1rem 0 1.5rem}")

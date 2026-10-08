# Pure saved EDA projection, catalog resolution and report assembly support.
# No source lookup, queue, scientific estimator or source-time process.
.brohn_rpe_profile <- function(selection) .brohn_rpk_eda_report_profile(selection$renderer_profile)
.brohn_rpe_version <- function(selection) {
  brohn_require(.brohn_rpe_profile(selection),"Choose an exact registered EDA report profile.")
  .brohn_rpk_profile_spec(selection$renderer_profile)$eda_version
}
.brohn_rpe_admission <- function(selection) {
  brohn_require(.brohn_rpe_profile(selection),"Choose an exact registered EDA report profile.")
  .brohn_rpk_profile_spec(selection$renderer_profile)$admission
}
brohn_report_package_eda_limits <- function() {
  x<-brohn_report_package_limits();x$profile<-"controlled-task-choice-eda-report-package/0.1"
  c(x,list(max_eda_stream_bytes=64*1024^2,max_eda_line_bytes=2*1024^2,
    max_eda_source_bytes=96*1024^2,max_eda_source_rows=1000000L,max_eda_source_tables=256L,
    max_eda_catalog_bytes=2*1024^2,max_eda_cells=2000L,max_eda_evidence_bytes=24*1024^2,
    max_eda_evidence_total_bytes=48*1024^2,max_eda_window_samples=500000L,
    max_eda_continuous_candidates=5000L,max_eda_event_candidates=20000L,
    max_eda_component_points=2000L,max_eda_component_groups=200L,
    max_eda_projection_bytes=192*1024^2,max_source_identity_context_bytes=16*1024^2,
    eda_marker_page_size=50L,eda_numerical_page_size=50L))
}
.brohn_rpe_components <- c("clean_us","tonic_us","phasic_us")
.brohn_rpe_page_policy <- function(value,label) {
  brohn_fields(value,c("pages","page_numbers"),label=label)
  brohn_require(value$pages%in%c("all","selected")&&brohn_array(value$page_numbers),paste(label,"requires all or exact page numbers."))
  numbers<-unlist(value$page_numbers,use.names=FALSE)
  brohn_require(all(vapply(value$page_numbers,function(n)brohn_number(n,1,400,TRUE),logical(1)))&&!anyDuplicated(numbers),paste(label,"contains an invalid or duplicate page."))
  brohn_require(if(value$pages=="all")length(numbers)==0L else length(numbers)>0L,paste(label,"has inconsistent all/selected pages."))
  value$page_numbers<-as.list(sort(numbers));value
}
.brohn_rpk_eda_section <- function(section) {
  s<-section;brohn_require(s$adapter%in%c("eda-events","eda-continuous"),"Choose a registered saved EDA report adapter.")
  brohn_fields(s$selector,"scope",if(identical(s$selector$scope,"exact_cells"))"keys"else character(),"EDA cell selector")
  brohn_require(s$selector$scope%in%c("all_cells","exact_cells"),"Choose all or exact saved EDA cells.")
  if(s$selector$scope=="exact_cells")brohn_require(brohn_array(s$selector$keys)&&length(s$selector$keys)>0L&&length(s$selector$keys)<=2000L&&
    all(vapply(s$selector$keys,.brohn_rp_hash,logical(1)))&&!anyDuplicated(unlist(s$selector$keys)),"Choose distinct exact EDA cell keys.")
  brohn_fields(s$display,c("components","pages","page_numbers","marker_pages"),label="EDA figure display")
  brohn_require(brohn_array(s$display$components)&&length(s$display$components)>0L&&
    all(vapply(s$display$components,function(x)brohn_text(x,32)&&x%in%.brohn_rpe_components,logical(1)))&&
    !anyDuplicated(unlist(s$display$components)),"Choose saved cleaned, tonic or phasic components.")
  s$display$components<-as.list(.brohn_rpe_components[.brohn_rpe_components%in%unlist(s$display$components)])
  numerical<-.brohn_rpe_page_policy(s$display[c("pages","page_numbers")],"EDA numerical pages")
  s$display$pages<-numerical$pages;s$display$page_numbers<-numerical$page_numbers
  s$display$marker_pages<-.brohn_rpe_page_policy(s$display$marker_pages,"EDA candidate marker pages")
  brohn_require("phasic_us"%in%unlist(s$display$components)||identical(s$display$marker_pages$pages,"all"),"Candidate marker pages require an illustrated phasic component.")
  s
}
.brohn_rpe_pages <- function(policy,total) {
  available<-if(total>0L)seq_len(total)else integer()
  as.list(if(policy$pages=="all")available else available[available%in%unlist(policy$page_numbers)])
}
brohn_resolve_eda_report_section <- function(section,catalog) {
  s<-.brohn_rpk_eda_section(section)
  brohn_require(brohn_array(catalog)&&length(catalog)>0L&&length(catalog)<=2000L,"Choose the exact bounded saved EDA catalog.")
  family<-if(s$adapter=="eda-events")"event"else"continuous"
  fields<-c("kind","key","source_family","identity","label","source_record_index","focusable","focus_reason","original_default_bounds","requested_bounds",
    "status","reason","original_status","descriptive_status","descriptive_reason","scr_status","scr_reason","model_hash","components","feature_count","candidate_count",
    "marker_count","observed_marker_count","unobserved_marker_count","out_of_view_marker_count","component_counts","numerical_page_counts","marker_page_count")
  keys<-character()
  for(i in seq_along(catalog)){
    item<-catalog[[i]];brohn_fields(item,fields,label="Prepared EDA catalog cell")
    brohn_require(identical(item$kind,"eda_cell")&&identical(item$source_family,family)&&.brohn_rp_hash(item$key)&&
      brohn_number(item$source_record_index,i,i,TRUE)&&brohn_text(item$label,4000)&&item$status%in%c("available","no_processed_samples","unavailable","raw_description_only")&&
      (is.null(item$model_hash)||.brohn_rp_hash(item$model_hash)),"The EDA catalog changed its exact identity, order or model status.")
    has_trace<-!is.null(item$model_hash)&&identical(item$status,"available")
    if(identical(item$status,"raw_description_only"))brohn_require(identical(family,"continuous")&&.brohn_rp_hash(item$model_hash)&&
      identical(item$original_status,"descriptive_only")&&identical(item$reason,"exact_constant_signal")&&identical(item$focusable,FALSE)&&identical(item$focus_reason,"exact_constant_signal")&&
      identical(item$descriptive_status,"computed")&&is.null(item$descriptive_reason)&&identical(item$scr_status,"unavailable")&&identical(item$scr_reason,"exact_constant_signal")&&
      brohn_number(item$feature_count,10,10,TRUE)&&brohn_number(item$candidate_count,0,0,TRUE),"Constant catalog must retain raw description and withhold response support.")
    brohn_require(brohn_array(item$components)&&identical(item$components,if(has_trace)as.list(.brohn_rpe_components)else list()),"Prepared component coverage is inconsistent.")
    brohn_fields(item$component_counts,.brohn_rpe_components,label="EDA component counts")
    brohn_fields(item$numerical_page_counts,c("points","candidates"),label="EDA numerical page counts")
    brohn_fields(item$numerical_page_counts$points,.brohn_rpe_components,label="EDA point page counts")
    for(k in .brohn_rpe_components){c<-item$component_counts[[k]];brohn_fields(c,c("points","groups"),label="EDA component support")
      brohn_require(brohn_number(c$points,0,2000,TRUE)&&brohn_number(c$groups,0,200,TRUE)&&
        brohn_number(item$numerical_page_counts$points[[k]],ceiling(c$points/50),ceiling(c$points/50),TRUE),"EDA point counts/pages are inconsistent.")}
    cap<-if(family=="event")20000L else 5000L
    brohn_require(brohn_number(item$feature_count,0,100000,TRUE)&&brohn_number(item$candidate_count,0,cap,TRUE)&&
      brohn_number(item$marker_count,0,3*cap,TRUE)&&all(vapply(item[c("observed_marker_count","unobserved_marker_count","out_of_view_marker_count")],function(n)brohn_number(n,0,3*cap,TRUE),logical(1)))&&
      item$observed_marker_count+item$unobserved_marker_count+item$out_of_view_marker_count==item$marker_count&&
      brohn_number(item$numerical_page_counts$candidates,ceiling(item$candidate_count/50),ceiling(item$candidate_count/50),TRUE)&&
      brohn_number(item$marker_page_count,if(has_trace)max(1L,ceiling(item$candidate_count/50))else 0,if(has_trace)max(1L,ceiling(item$candidate_count/50))else 0,TRUE),"EDA candidate/marker page coverage is inconsistent.")
    keys<-c(keys,item$key)
  }
  brohn_require(!anyDuplicated(keys),"The prepared EDA catalog repeats a cell identity.")
  selected<-catalog
  if(s$selector$scope=="exact_cells"){
    brohn_require(all(unlist(s$selector$keys)%in%keys),"A selected EDA cell is absent from this exact preparation.")
    selected<-catalog[keys%in%unlist(s$selector$keys)]
  }
  numerical_policy<-s$display[c("pages","page_numbers")];seen_num<-integer();seen_marker<-integer()
  resolved<-lapply(selected,function(item){
    has_trace<-!is.null(item$model_hash)&&identical(item$status,"available")
    components<-if(has_trace)s$display$components else list()
    points<-setNames(lapply(unlist(components),function(k).brohn_rpe_pages(numerical_policy,item$numerical_page_counts$points[[k]])),unlist(components))
    if(!length(points))points<-structure(list(),names=character())
    candidates<-.brohn_rpe_pages(numerical_policy,item$numerical_page_counts$candidates)
    marker<-if("phasic_us"%in%unlist(components)).brohn_rpe_pages(s$display$marker_pages,item$marker_page_count)else list()
    seen_num<<-c(seen_num,unlist(points,use.names=FALSE),unlist(candidates,use.names=FALSE));seen_marker<<-c(seen_marker,unlist(marker,use.names=FALSE))
    cost<-if(has_trace)length(setdiff(unlist(components),"phasic_us"))+length(marker)else 1L
    list(key=item$key,model_hash=item$model_hash,status=item$status,components=components,
      numerical_pages=list(points=points,candidates=candidates),marker_pages=marker,panel_count=cost)
  })
  if(numerical_policy$pages=="selected")brohn_require(all(unlist(numerical_policy$page_numbers)%in%seen_num),"A numerical page is absent from every applicable selected EDA table.")
  if(s$display$marker_pages$pages=="selected")brohn_require(all(unlist(s$display$marker_pages$page_numbers)%in%seen_marker),"A marker page is absent from every selected phasic EDA view.")
  s$resolved_models<-resolved;list(section=s,panel_count=sum(vapply(resolved,`[[`,numeric(1),"panel_count")))
}

.brohn_rpe_same <- function(a,b) identical(brohn_eda_value_hash(a),brohn_eda_value_hash(b))
.brohn_rpe_csv <- function(rows,path) {
  original_json<-brohn_json;write<-.brohn_rp_csv
  environment(write)<-list2env(list(brohn_json=function(...) .brohn_edd_json_text(original_json(...))),parent=environment(.brohn_rp_csv))
  write(rows,path)
}
.brohn_rpe_family <- function(item) if(identical(item$complete_analysis$operation,"eda_events"))"event"else"continuous"
.brohn_rpe_all_reports <- function(bundle) c(bundle$reports,lapply(bundle$related_eda_sources,`[[`,"report"))
.brohn_rpe_alias_context <- function(bundle) {
  reports<-.brohn_rpe_all_reports(bundle);context_reports<-reports
  for(n in bundle$source_identity_graph$nodes)if(is.null(n$source_ordinal))context_reports[[length(context_reports)+1L]]<-list(ref=n$ref,saved_body=list(provenance=n$provenance_context),complete_analysis=list())
  aliases<-.brohn_rp_alias_context(bundle$selection$contents_policy$identifier_mode,context_reports);states<-list()
  for(i in seq_along(reports))if(identical(reports[[i]]$complete_analysis$kind,"eda")){
    ns<-sprintf("report-%02d",i);states[[ns]]<-.brohn_rpe_aliases(reports[[i]],aliases,ns)
  };aliases$eda_states<-states;aliases
}
.brohn_rpe_relationships <- function(bundle,aliases) {
  graph<-bundle$source_identity_graph;next_ordinal<-length(.brohn_rpe_all_reports(bundle))
  nodes<-lapply(graph$nodes,function(n){
    ns<-if(!is.null(n$source_ordinal))sprintf("report-%02d",n$source_ordinal)else{next_ordinal<<-next_ordinal+1L;sprintf("report-%02d",next_ordinal)}
    context<-n$provenance_context
    if("crosswalk"%in%names(context))context$crosswalk<-.brohn_rp_project(context$crosswalk,aliases,ns,"provenance/crosswalk")
    list(ref=n$ref,source_ordinal=n$source_ordinal,analysis_kind=n$analysis_kind,original_context_hash=n$context_hash,
      projected_provenance_context=context,projected_context_value_hash=brohn_eda_value_hash(context))
  })
  list(schema="brohn-report-eda-identity-relationships/0.1",identifier_mode=bundle$selection$contents_policy$identifier_mode,
    root_refs=graph$root_refs,nodes=nodes,edges=graph$edges,
    interpretation="Only retained reviewed source relationships connect labels. Context-only intermediate sources are identity proof, not a claim that their full numerical data is exported.")
}
.brohn_rpe_prepared_bindings <- function(bundle,eda_lookup=NULL) {
  for(k in c("eda_displays","related_eda_sources","task_displays","choice_displays","distributions"))brohn_require(brohn_array(bundle[[k]]),paste("Prepared",k,"must be an ordered array."))
  graph<-bundle$source_identity_graph;brohn_fields(graph,c("schema","root_refs","nodes","edges"),label="Exact source identity graph")
  brohn_require(identical(graph$schema,"brohn-report-source-identity-graph/0.1")&&.brohn_rp_same(graph$root_refs,bundle$selection$report_refs),"Source graph roots changed.")
  stripped<-graph
  for(i in seq_along(graph$nodes)){
    n<-graph$nodes[[i]];brohn_fields(n,c("ref","analysis_kind","source_ordinal","retained_report","provenance_context","context_hash"),label="Source identity node")
    .brohn_rp_ref(n$ref,"report");brohn_require(identical(brohn_hash(n$provenance_context),n$context_hash),"Source graph original identity context changed.")
    brohn_fields(n$provenance_context,character(),c("selection","source_reports",if(identical(n$analysis_kind,"multimodal"))c("crosswalk","crosswalk_hash","identity_source")),"Registered original identity context")
    if(!is.null(n$provenance_context$crosswalk))brohn_require(identical(brohn_hash(n$provenance_context$crosswalk),n$provenance_context$crosswalk_hash),"Reviewed source crosswalk changed its original hash.")
    stripped$nodes[[i]]<-n[setdiff(names(n),c("provenance_context","context_hash"))]
  }
  node_keys<-vapply(graph$nodes,function(n)brohn_hash(n$ref),character(1))
  brohn_require(brohn_array(graph$nodes)&&length(node_keys)<=32L&&!anyDuplicated(node_keys)&&brohn_array(graph$edges),"Source identity graph nodes/edges are invalid.")
  edge_keys<-character()
  for(edge in graph$edges){
    brohn_fields(edge,c("child_ref","parent_ref","parent_slot","parent_index"),label="Original source parent edge")
    child<-match(brohn_hash(edge$child_ref),node_keys);parent<-match(brohn_hash(edge$parent_ref),node_keys)
    brohn_require(!is.na(child)&&!is.na(parent)&&edge$parent_slot%in%c("provenance.selection","provenance.source_reports")&&brohn_number(edge$parent_index,1,1000,TRUE),"Source edge leaves its exact registered graph.")
    context<-graph$nodes[[child]]$provenance_context;slot<-sub("^provenance\\.","",edge$parent_slot);rows<-context[[slot]]
    brohn_require(length(rows)>=edge$parent_index,"Source edge parent index is absent from original provenance.")
    row<-rows[[edge$parent_index]]
    expected<-list(kind="report",id=row$id,revision=row$revision,body_hash=if(slot=="selection")row$hash else row$body_hash,project_id=edge$child_ref$project_id)
    brohn_require((slot!="selection"||identical(row$state,"selected"))&&.brohn_rp_same(expected,edge$parent_ref),"Source edge differs from the exact original parent reference.")
    edge_keys<-c(edge_keys,brohn_hash(edge))
  }
  brohn_require(!anyDuplicated(edge_keys),"Source graph repeats a parent edge.")
  visited<-character()
  visit<-function(ref,active=character()){
    key<-brohn_hash(ref);brohn_require(key%in%node_keys&&!key%in%active,"Source identity graph contains an absent node or cycle.")
    if(key%in%visited)return(invisible(NULL))
    for(edge in graph$edges)if(identical(brohn_hash(edge$child_ref),key))visit(edge$parent_ref,c(active,key))
    visited<<-c(visited,key);invisible(NULL)
  }
  for(ref in graph$root_refs)visit(ref)
  brohn_require(setequal(visited,node_keys),"Source identity graph contains an unbound extra node.")
  brohn_require(.brohn_rp_same(stripped,bundle$selection$source_identity_graph_binding),"Supervised source graph differs from its frozen small binding.")
  expected_related<-lapply(bundle$related_eda_sources,function(x){brohn_fields(x,c("source_ordinal","report","required_by","parent_edges","prepared_ref"),label="Complete related EDA source")
    list(source_ordinal=x$source_ordinal,report_ref=x$report$ref,required_by=x$required_by,parent_edges=x$parent_edges)})
  brohn_require(.brohn_rp_same(expected_related,bundle$selection$related_eda_refs),"Complete related EDA sources changed their frozen membership or order.")
  all<-.brohn_rpe_all_reports(bundle);brohn_require(length(all)<=32L,"Complete EDA closure exceeds32 sources.")
  eda_reports<-Filter(function(x)identical(x$complete_analysis$kind,"eda"),all)
  artifacts<-unlist(lapply(eda_reports,function(x)x$complete_analysis$artifacts),recursive=FALSE,use.names=FALSE)
  .brohn_edd_limit(sum(vapply(artifacts,function(x)x$size,numeric(1))),bundle$limits$max_eda_source_bytes,"source_stream_bytes",NULL,"fewer_sources")
  .brohn_edd_limit(sum(vapply(artifacts,function(x)x$rows,numeric(1))),bundle$limits$max_eda_source_rows,"source_rows",NULL,"fewer_sources")
  .brohn_edd_limit(sum(vapply(artifacts,function(x)x$tables,numeric(1))),bundle$limits$max_eda_source_tables,"source_tables",NULL,"fewer_sources")
  .brohn_edd_limit(sum(vapply(bundle$eda_displays,function(x)x$evidence$bytes,numeric(1))),bundle$limits$max_eda_evidence_total_bytes,"prepared_evidence_total_bytes",NULL,"fewer_sources")
  for(i in seq_along(all)){
    hits<-Filter(function(n).brohn_rp_same(n$ref,all[[i]]$ref),graph$nodes)
    brohn_require(length(hits)==1L&&identical(as.numeric(hits[[1L]]$source_ordinal),as.numeric(i))&&identical(hits[[1L]]$analysis_kind,all[[i]]$complete_analysis$kind),"Complete source ordinal or kind differs from its exact graph node.")
    original_context<-all[[i]]$saved_body$provenance
    keys<-intersect(c("selection","source_reports"),names(original_context))
    if(identical(all[[i]]$complete_analysis$kind,"multimodal"))keys<-c(keys,intersect(c("crosswalk","crosswalk_hash","identity_source"),names(original_context)))
    original_context<-original_context[keys];if(!length(original_context))original_context<-structure(list(),names=character())
    brohn_require(.brohn_rpe_same(original_context,hits[[1L]]$provenance_context),"Graph context differs from its complete original report.")
  }
  legacy<-bundle;legacy$selection$prepared_sources<-Filter(function(x)x$adapter!="eda-display",bundle$selection$prepared_sources)
  # Use the unchanged earlier prepared-family matcher with its exact profile.
  legacy$selection$renderer_profile<-"controlled-gaze-explicit-task-choice-paired/0.1";legacy$selection$schema<-"brohn-report-package-selection/0.2"
  .brohn_rpt_prepared_bindings(legacy)
  actual<-list();eda_count<-0L
  for(item in all){
    if(any(vapply(bundle$reports,function(r).brohn_rp_same(r$ref,item$ref),logical(1))))actual<-c(actual,Filter(function(x).brohn_rp_same(x$source_report_ref,item$ref),legacy$selection$prepared_sources))
    if(identical(item$complete_analysis$kind,"eda")){
      d<-if(is.null(eda_lookup)).brohn_rpe_find(bundle,item)else eda_lookup(item);eda_count<-eda_count+1L
      related<-Filter(function(x).brohn_rp_same(x$report$ref,item$ref),bundle$related_eda_sources)
      if(length(related))brohn_require(length(related)==1L&&.brohn_rp_same(related[[1L]]$prepared_ref,d$ref),"Related EDA source points to a different preparation.")
      actual[[length(actual)+1L]]<-list(adapter="eda-display",source_report_ref=item$ref,prepared_ref=d$ref,implementation_ref=list(profile=d$body$implementation$profile,hash=brohn_hash(d$body$implementation)))
      request<-Filter(function(x).brohn_rp_same(x$report_ref,item$ref),bundle$selection$eda_display_requests)
      brohn_require(length(request)<=1L,"EDA view request repeats a source.")
      wanted<-if(length(request))request[[1L]]$display_request else list(schema="brohn-eda-display-request/0.1",continuous_windows=list())
      brohn_require(.brohn_rpe_same(wanted,d$complete_evidence$display_request),"Prepared EDA view differs from the frozen exact window request.")
    }
  }
  brohn_require(eda_count==length(bundle$eda_displays)&&.brohn_rp_same(actual,bundle$selection$prepared_sources),"Prepared EDA union differs from the frozen dependency sequence.")
  invisible(TRUE)
}
.brohn_rpe_find <- function(bundle,item) {
  if(!identical(item$complete_analysis$kind,"eda"))return(NULL)
  hits<-Filter(function(d).brohn_rp_same(d$body$source$report_ref,item$ref),bundle$eda_displays)
  brohn_require(length(hits)==1L,"Every selected or required EDA source needs one exact complete preparation.")
  entry<-hits[[1L]];brohn_fields(entry,c("ref","body","evidence","streams"),label="Complete prepared EDA source")
  .brohn_rp_ref(entry$ref,"eda_display");brohn_require(identical(entry$ref$body_hash,brohn_hash(entry$body)),"Saved EDA catalog body changed.")
  version<-.brohn_rpe_version(bundle$selection)
  brohn_require(identical(entry$body$schema,paste0("brohn-saved-eda-display/",version))&&
    identical(entry$body$implementation$profile,paste0("saved-eda-display/",version)),"Prepared EDA profile differs from the exact frozen renderer generation.")
  d<-entry$evidence;brohn_fields(d,c("hash","bytes","media_type","path"),label="Sealed EDA evidence")
  brohn_require(.brohn_rpe_same(d[c("hash","bytes","media_type")],entry$body$artifact),"Complete EDA evidence descriptor differs from its exact saved artifact.")
  brohn_require(brohn_array(entry$streams)&&length(entry$streams)==length(item$complete_analysis$artifacts),"Complete EDA stream membership changed.")
  for(i in seq_along(entry$streams)){
    stream<-entry$streams[[i]];brohn_fields(stream,c("original","original_verification","path"),label="Complete source EDA stream")
    brohn_require(.brohn_rpe_same(stream$original,item$complete_analysis$artifacts[[i]])&&.brohn_rpe_same(stream$original_verification,item$complete_analysis$artifact_verification$artifacts[[i]]),"Supplied EDA stream is not the complete original analysis artifact and receipt.")
  }
  .brohn_edd_limit(d$bytes,24*1024^2,"prepared_evidence_bytes",item$ref,"smaller_window")
  brohn_require(.brohn_rp_hash(d$hash)&&brohn_number(d$bytes,1,24*1024^2,TRUE)&&identical(d$media_type,"application/json")&&file.exists(d$path)&&
    identical(as.numeric(file.info(d$path)$size),as.numeric(d$bytes))&&identical(digest::digest(file=d$path,algo="sha256"),d$hash),"Complete EDA evidence bytes changed.")
  evidence<-brohn_eda_read_json_file(d$path,24*1024^2)
  brohn_validate_eda_display_evidence(evidence,item,entry$body)
  entry$complete_evidence<-evidence;entry
}

# One render owns this closure. Reuse a completely validated model only for the
# same exact input and unchanged sealed bytes; independent calls start fresh.
# No source/permission checks or publication holds are cached here.
.brohn_rpe_lookup <- function(bundle) {
  entries<-list()
  function(item) {
    if(!identical(item$complete_analysis$kind,"eda"))return(NULL)
    at<-which(vapply(entries,function(x)identical(x$item,item,num.eq=FALSE,attrib.as.set=FALSE),logical(1)))
    if(length(at)){
      entry<-entries[[at[[1L]]]]$entry;d<-entry$evidence
      brohn_require(file.exists(d$path)&&identical(as.numeric(file.info(d$path)$size),as.numeric(d$bytes))&&
        identical(digest::digest(file=d$path,algo="sha256"),d$hash),"Complete EDA evidence bytes changed.")
      return(entry)
    }
    entry<-.brohn_rpe_find(bundle,item)
    entries[[length(entries)+1L]]<<-list(item=item,entry=entry)
    entry
  }
}

# Source-scoped registered EDA identity domains. This state is made from full
# original collections before any figure selection; never from displayed pages.
.brohn_rpe_aliases <- function(item,aliases,ns) {
  a<-item$complete_analysis;recordings<-list()
  for(row in c(a$recordings,a$segments,a$features,a$events,a$series,a$source_masks)){
    id<-row$recording_id;if(is.null(id)||is.null(row$group))next
    context<-row$group[intersect(c("participant_id","session_id"),names(row$group))]
    if(!is.null(recordings[[id]]))brohn_require(.brohn_rpe_same(recordings[[id]],context),"A generated EDA recording changes its original person/session context.")else recordings[[id]]<-context
  }
  label<-function(kind,id,recording=NULL,channel=NULL,group=NULL){
    if(is.null(id)||identical(id,""))return(id)
    if(aliases$mode=="source_identifiers")return(id)
    g<-if(!is.null(group))group else if(!is.null(recording))recordings[[recording]] else NULL
    person<-g$participant_id;session<-g$session_id
    if(kind=="person")return(aliases$label(ns,"person",id))
    if(kind=="session")return(aliases$label(ns,"session",id,person))
    if(kind=="recording")return(aliases$label(ns,"recording",id,person,session))
    if(kind=="segment"){
      brohn_require(!is.null(recording)&&!is.null(channel),"An EDA generated segment has no exact recording/channel scope.")
      id<-brohn_json(list(recording,channel,id))
    }else if(kind%in%c("event","exposure")){
      brohn_require(!is.null(recording),"An EDA event/exposure has no exact recording scope.");id<-brohn_json(list(recording,id))
    }
    aliases$label(ns,kind,id,person,session)
  }
  project<-function(x,path="analysis",recording=NULL,channel=NULL,group=NULL){
    if(!is.list(x))return(x)
    if(is.null(names(x)))return(lapply(x,project,path=paste0(path,"/*"),recording=recording,channel=channel,group=group))
    r<-brohn_default(x$recording_id,recording);ch<-brohn_default(x$channel,channel);g<-brohn_default(x$group,group)
    if(is.null(g)&&!is.null(r))g<-recordings[[r]]
    out<-x
    for(k in names(x)){
      # Original descriptors, verification/source metadata and method/code maps
      # remain evidence. They must not be traversed as identity containers.
      if(k%in%c("artifacts","artifact_verification","engine","verification","parameters","columns","coordinates","display_policy","endpoint_coverage")||(k=="source"&&!grepl("/support$",path)))next
      if(k=="recording_id")out[k]<-list(label("recording",x[[k]],r,ch,g))
      else if(k=="segment_id")out[k]<-list(label(if(grepl("/group$",path))"source-segment"else"segment",x[[k]],r,ch,g))
      else if(k=="source_recording_id"&&grepl("/group$",path))out[k]<-list(label("source-recording",x[[k]],r,ch,g))
      else if(k=="participant_id")out[k]<-list(label("person",x[[k]],r,ch,g))
      else if(k%in%c("session_id","run_id"))out[k]<-list(label("session",x[[k]],r,ch,g))
      else if(k=="exposure_id")out[k]<-list(label("exposure",x[[k]],r,ch,g))
      else if(k=="event_id"||(k=="id"&&!is.null(x$type)&&x$type%in%c("stimulus_event","nuisance_event")))out[k]<-list(label("event",x[[k]],r,ch,g))
      else if(k=="overlapping_event_ids")out[k]<-list(lapply(x[[k]],label,kind="event",recording=r,channel=ch,group=g))
      else out[k]<-list(project(x[[k]],paste0(path,"/",k),r,ch,g))
    };out
  }
  analysis<-function(){out<-project(a)
    if(length(a$parameters)){
      original_names<-names(a$parameters);brohn_require(all(original_names%in%names(recordings)),"EDA parameter keys have no registered recording.")
      names(out$parameters)<-vapply(original_names,function(id)label("recording",id,id),character(1))
      brohn_require(!anyDuplicated(names(out$parameters)),"EDA recording aliases collide.")
    };out
  }
  mapping<-function(value){
    if(is.null(value)||aliases$mode=="source_identifiers")return(value)
    out<-value
    # Only the registered explicit event array consumes literal identifiers in
    # these EDA CSV producers. Other declared metadata and column names remain
    # literal; equal text alone is not evidence of an identity relationship.
    if("events"%in%names(value)&&!is.null(value$events))out$events<-lapply(value$events,function(e){
      brohn_fields(e,c("time_s","code"),c("exposure_id","recording_id","condition_id","stimulus_id"),"Original explicit EDA event")
      recording<-if("recording_id"%in%names(e))e$recording_id else if(length(recordings)==1L)names(recordings)[[1L]]else NULL
      brohn_require(!is.null(recording)&&recording%in%names(recordings),"Explicit EDA event has no unique original recording binding.")
      matches<-Filter(function(x)x$type%in%c("stimulus_event","nuisance_event")&&identical(x$recording_id,recording)&&
        identical(x$code,e$code)&&.brohn_rpe_same(x$requested_time_s,e$time_s)&&
        all(vapply(intersect(c("exposure_id","condition_id","stimulus_id"),names(e)),function(k).brohn_rpe_same(x[[k]],e[[k]]),logical(1))),a$events)
      brohn_require(length(matches)==1L,"Explicit EDA event does not join one original measured source event.")
      projected<-e
      if("recording_id"%in%names(e))projected["recording_id"]<-list(label("recording",e$recording_id,recording))
      if("exposure_id"%in%names(e))projected["exposure_id"]<-list(label("exposure",e$exposure_id,recording))
      projected
    })
    out
  }
  metadata<-function(stream){
    out<-stream[c("header","tables")]
    out$tables<-lapply(stream$tables,function(t){v<-t;r<-t$identity$recording_id;ch<-t$identity$channel;g<-t$identity$group
      v$identity<-project(t$identity,"table/identity",r,ch,g)
      v$support$source<-project(t$support$source,"table/support/source",r,ch,g);v})
    if("source_mapping"%in%names(stream$header$provenance$parameters))out$header$provenance$parameters["source_mapping"]<-list(mapping(stream$header$provenance$parameters$source_mapping))
    out
  }
  # Preallocate collection aliases in fixed source order, independent of views.
  projected_analysis<-analysis()
  list(label=label,project=project,analysis=projected_analysis,metadata=metadata,mapping=mapping,recordings=recordings)
}

.brohn_rpe_projection <- function(item,state,aliases,ns,source_admission="task-choice-eda-findings/0.1") {
  body<-item$saved_body;a<-item$complete_analysis
  spec<-.brohn_rpk_admission_spec(source_admission)
  brohn_require(!isTRUE(spec$cardiac)&&!is.null(spec$eda_version),"Choose an exact EDA source admission.")
  brohn_validate_complete_report_analysis(item,source_admission)
  provenance<-body$provenance
  if(!is.null(provenance$source))provenance$source<-provenance$source[intersect(c("hash","size","bytes","media_type","format"),names(provenance$source))]
  for(i in seq_along(provenance$design$stimuli))if(!is.null(provenance$design$stimuli[[i]]$asset))provenance$design$stimuli[[i]]$asset<-provenance$design$stimuli[[i]]$asset[setdiff(names(provenance$design$stimuli[[i]]$asset),c("filename","path"))]
  # The literal source mapping follows the same separately registered policy as
  # stream headers. Column names and authored labels remain literal.
  if("mapping"%in%names(provenance))provenance["mapping"]<-list(state$mapping(provenance$mapping))
  list(schema="brohn-portable-numerical-evidence/0.1",source_ref=item$ref,source_analysis_sha256=brohn_hash(a),source_analysis_value_hash=brohn_eda_value_hash(a),
    source_result_object=body$result_object,projection_profile="scientific-values-and-local-labels/0.1",identifier_mode=aliases$mode,
    counts=lapply(a[intersect(c("features","observations","contrasts","recordings","segments","events","series","source_masks"),names(a))],length),
    report=body[intersect(c("id","title","origin","schema_version","created_at","status","study_id","dataset_id"),names(body))],
    analysis=state$analysis,provenance=provenance,producer=body$processing[intersect(c("recipe","code_hashes","output_hash","request_hash"),names(body$processing))],
    session_quality=.brohn_rp_project(body$session_quality,aliases,ns,"session_quality"),
    policy=list(scientific_values="Every saved numerical collection is retained; no new signal processing or inference.",identifiers="Exact source-scoped aliases; authored labels and clock origins stay verbatim. This is not anonymization.",
      complete_processed_streams=TRUE,complete_raw_series_included=FALSE,original_partial_raw_preview_preserved=TRUE,original_raw_bytes_reverified=FALSE))
}

.brohn_rpe_child <- function(bundle,request,private,name,inspect=FALSE) {
  helper<-file.path(dirname(bundle$implementation$archive_script),"report_package_eda.py")
  brohn_require(file.exists(helper)&&identical(digest::digest(file=helper,algo="sha256"),bundle$implementation$sources[["scripts/workers/report_package_eda.py"]]),"EDA complete-stream helper identity changed.")
  q<-file.path(private,paste0(name,"-q.json"));r<-file.path(private,paste0(name,"-r.json"))
  brohn_eda_write_json_file(request,q)
  args<-c("-B",helper,if(inspect)"--inspect"else"--request",q,"--output",r)
  if(!inspect)args<-c(args,"--artifacts",file.path(private,paste0(name,"-files")))
  child<-processx::run(bundle$implementation$archive_python,args,timeout=120,error_on_status=FALSE,stdout=file.path(private,paste0(name,"-out.log")),stderr=file.path(private,paste0(name,"-err.log")),cleanup_tree=TRUE,windows_hide_window=TRUE)
  brohn_require(file.exists(r),"EDA stream helper returned no bounded receipt.");value<-brohn_eda_read_json_file(r)
  if(identical(value$schema,"brohn-eda-report-refusal/0.1"))brohn_stop_eda_refusal(value)
  brohn_require(child$status==0L,paste("Complete EDA stream export refused:",value$message))
  brohn_require(.brohn_rp_same(value$verified_runtime$Python,bundle$implementation$runtime$Python),"Complete EDA stream helper runtime changed.")
  value
}

.brohn_rpe_write_complete <- function(bundle,entry,item,state,ordinal,output_dir,private,json,add) {
  family<-.brohn_rpe_family(item);stem<-sprintf("eda-%03d",ordinal)
  version<-.brohn_rpe_version(bundle$selection)
  inspection<-.brohn_rpe_child(bundle,list(schema=paste0("brohn-eda-stream-inspection-request/",version),source_report_ref=item$ref,source_family=family,streams=entry$streams),private,paste0(stem,"-i"),TRUE)
  check<-inspection;check$value_hash<-NULL;brohn_require(identical(brohn_eda_value_hash(check),inspection$value_hash),"Complete stream metadata typed hash changed.")
  metadata<-lapply(inspection$streams,state$metadata)
  result<-.brohn_rpe_child(bundle,list(schema=paste0("brohn-eda-stream-projection-request/",version),inspection=inspection,source_family=family,source_report_ref=item$ref,
    identifier_mode=bundle$selection$contents_policy$identifier_mode,streams=entry$streams,projected_metadata=metadata,projection_implementation=.brohn_rp_implementation(bundle$implementation)),private,paste0(stem,"-p"))
  brohn_require(identical(result$schema,paste0("brohn-eda-stream-projection-result/",version))&&isTRUE(result$coverage$complete)&&.brohn_rpe_same(result$source_report_ref,item$ref),"Complete stream projection returned an invalid binding.")
  prefix<-sprintf("evidence/eda/source-%03d/",ordinal)
  for(f in result$files){
    brohn_require(grepl("^(series|candidates)\\.(csv|ndjson)$",f$path),"Unexpected EDA projection artifact path.")
    original<-file.path(private,paste0(stem,"-p-files"),f$path);target<-paste0(prefix,"streams/",f$path)
    brohn_require(identical(digest::digest(file=original,algo="sha256"),f$sha256)&&file.info(original)$size==f$bytes,"Projected EDA artifact changed.")
    dir.create(dirname(file.path(output_dir,target)),recursive=TRUE,showWarnings=FALSE)
    brohn_require(!file.exists(file.path(output_dir,target))&&file.copy(original,file.path(output_dir,target),overwrite=FALSE),"Could not retain the complete EDA stream.")
    add(target,f$media_type,f$role)
  }
  evidence<-entry$complete_evidence;projected<-evidence
  projected$cells<-lapply(evidence$cells,function(c){o<-c;r<-c$identity$recording_id;ch<-c$identity$channel;g<-c$original_support$group
    for(k in c("identity","selection","original_support","model"))o[k]<-list(state$project(c[[k]],paste0("eda_display/",k),r,ch,g))
    o["projected_model_value_hash"]<-list(if(is.null(o$model))NULL else brohn_eda_value_hash(o$model));o})
  json(projected,paste0(prefix,"display.json"),"complete_saved_eda_display")
  result$package_files<-lapply(result$files,function(f)c(list(helper_relative_path=f$path),list(path=paste0(prefix,"streams/",f$path)),f[setdiff(names(f),"path")]))
  json(result,paste0(prefix,"projection-receipt.json"),"complete_eda_stream_projection_receipt")
  list(entry=entry,state=state,display=projected,streams=result,source_ordinal=ordinal)
}

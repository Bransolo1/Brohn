# One private child-render lifetime. No store authority, persistent cache or
# scientific work lives here. Public standalone facades still validate fully.
.brohn_rpcc_session_json <- function(value,depth=0L) {
  brohn_require(depth<=63L,"Render-session JSON exceeds the typed depth limit.")
  attrs<-names(attributes(value))
  brohn_require(!length(setdiff(attrs,if(is.list(value))"names"else character())),"Render-session values cannot carry non-JSON attributes or mutable references.")
  if(is.null(value))return(invisible(TRUE))
  if(is.logical(value)){brohn_require(length(value)==1L&&!is.na(value),"Render-session JSON needs scalar booleans.");return(invisible(TRUE))}
  if(is.numeric(value)){brohn_require(length(value)==1L&&is.finite(value)&&(!is.integer(value)||abs(value)<=2^53-1),"Render-session JSON needs finite scalar binary64 numbers.");return(invisible(TRUE))}
  if(is.character(value)){brohn_require(length(value)==1L&&!is.na(value)&&!is.na(iconv(value,from="",to="UTF-8",sub=NA)),"Render-session JSON needs valid UTF-8 scalar text.");return(invisible(TRUE))}
  brohn_require(is.list(value)&&identical(typeof(value),"list"),"Render-session captures only JSON trees, never pairlists, functions, environments or external pointers.")
  keys<-names(value)
  if(!is.null(keys))brohn_require(length(keys)==length(value)&&!anyNA(keys)&&!anyDuplicated(enc2utf8(keys))&&
    all(!is.na(iconv(keys,from="",to="UTF-8",sub=NA))),"Render-session object keys must be unique valid UTF-8 text.")
  for(x in value).brohn_rpcc_session_json(x,depth+1L)
  invisible(TRUE)
}

# Both operands come from the factory's already domain-checked immutable JSON
# tree. The strict fast path preserves signed zero and object/array attributes;
# the original typed comparison handles alternate key order or numeric R types.
.brohn_rpcc_session_same <- function(a,b) {
  if(identical(a,b,num.eq=FALSE,attrib.as.set=FALSE))TRUE else .brohn_rpca_same(a,b)
}

.brohn_rpcc_render_session <- function(bundle) {
  .brohn_rpcc_session_json(bundle)
  captured<-bundle
  state<-.brohn_rpcc_render_state_core(captured,.brohn_rpcc_session_same,
    function(entry).brohn_rpca_entry_core(entry,.brohn_rpcc_session_same))
  limits<-.brohn_rp_limits(captured$limits)
  entries<-captured$cardiac_displays;entry_keys<-vapply(entries,function(e).brohn_rpca_key(e$evidence$source_ref),character(1))
  brohn_require(!anyDuplicated(entry_keys),"The render session has duplicate exact cardiac sources.")
  names(entries)<-entry_keys
  original<-list();bindings<-list();by_entry<-list();ordinals<-list()
  all_keys<-vapply(state$all_reports,function(x).brohn_rpca_key(x$ref),character(1))
  for(key in entry_keys){entry<-entries[[key]];at<-which(all_keys==key)
    brohn_require(length(at)==1L,"The render session lost an exact original global ordinal.");ordinals[[key]]<-at
    for(item in entry$source_reports){rk<-.brohn_rpca_key(item$ref)
      if(is.null(original[[rk]])){
        bindings[[rk]]<-.brohn_rpcc_provenance_record(item,entry);original[[rk]]<-item
      }else{
        brohn_require(.brohn_rpcc_session_same(original[[rk]],item),"A repeated exact original report has different complete values.")
        .brohn_rpcc_provenance_membership(item,entry)
      }
    }
    item<-original[[key]];proof<-bindings[[key]]
    brohn_require(!is.null(item)&&identical(proof$analysis_hash,entry$body$source$analysis_hash)&&
      identical(proof$analysis_value_hash,entry$body$source$analysis_value_hash),"The captured original cardiac analysis differs from its prepared native or typed binding.")
    by_entry[[key]]<-lapply(entry$source_reports,function(x)bindings[[.brohn_rpca_key(x$ref)]])
  }
  requested<-captured$selection$sections[order(vapply(captured$selection$sections,`[[`,numeric(1),"order"))]
  sections<-list();section_counts<-list();prefixes<-list();counts<-list()
  for(i in seq_along(requested)){h<-requested[[i]];if(!identical(h$adapter,"cardiac"))next
    key<-.brohn_rpca_key(h$source_report_ref);entry<-entries[[key]]
    brohn_require(!is.null(entry),"A captured cardiac section has no exact preparation.")
    resolved<-.brohn_rpca_section_core(h$cardiac_section,entry)
    sections[[h$id]]<-h;prefixes[[h$id]]<-sprintf("section-%03d",i);counts[[h$id]]<-resolved$panel_count
  }
  # Keep existing preflight ordering; never cache a sections-by-all-cells matrix.
  old<-if(is.null(state$legacy_bundle))list(section_counts=list())else
    brohn_report_package_panel_preflight(state$legacy_bundle,.brohn_rpe_lookup(state$legacy_bundle))
  section_counts<-c(old$section_counts,lapply(Filter(function(h)identical(h$adapter,"cardiac"),captured$selection$sections),
    function(h)list(section_id=h$id,panel_count=counts[[h$id]])))
  total<-sum(vapply(section_counts,`[[`,numeric(1),"panel_count"))
  preflight<-if(total>limits$max_panels)list(schema="brohn-report-package-refusal/0.1",reason_code="panel_limit",resolved_panel_count=total,
    maximum_panels=limits$max_panels,section_counts=section_counts)else
    list(schema="brohn-report-package-panel-preflight/0.1",passed=TRUE,resolved_panel_count=total,maximum_panels=limits$max_panels,section_counts=section_counts)
  stage<-new.env(parent=emptyenv());stage$exports<-list();stage$provenance<-character();stage$sections<-character()
  lookup<-function(ref){.brohn_rpca_ref(ref);key<-.brohn_rpca_key(ref)
    brohn_require(key%in%entry_keys&&.brohn_rpcc_session_same(ref,entries[[key]]$evidence$source_ref),"Choose an exact captured cardiac source.");key}
  require_export<-function(key){result<-stage$exports[[key]]
    brohn_require(!is.null(result),"Complete this session's exact source export before provenance or figures.");result}
  api<-new.env(parent=emptyenv());class(api)<-"brohn_cardiac_render_session"
  api$panel_preflight<-function()preflight
  api$write_complete<-function(source_ref,ordinal,out,private,json,add){key<-lookup(source_ref)
    brohn_require(isTRUE(preflight$passed),"The captured figure plan exceeds the unchanged panel limit.")
    brohn_require(brohn_number(ordinal,1,32,TRUE)&&ordinal==ordinals[[key]]&&is.function(json)&&is.function(add),"Use this captured source's exact global ordinal and host callbacks.")
    brohn_require(is.null(stage$exports[[key]]),"This session already completed that exact source export.")
    entry<-entries[[key]];request<-.brohn_rpca_export_request_core(entry,captured$selection$contents_policy$identifier_mode)
    result<-.brohn_rpca_write_complete_core(captured,entry,ordinal,out,private,json,add,request)
    brohn_require(identical(result$prefix,sprintf("evidence/cardiac/source-%03d/",ordinals[[key]])),"The completed source export lost its captured global prefix.")
    stage$exports[[key]]<-result;result
  }
  api$write_provenance<-function(source_ref,json){key<-lookup(source_ref);export<-require_export(key)
    brohn_require(is.function(json)&&!key%in%stage$provenance,"Use one provenance write per captured source with the host JSON callback.")
    value<-.brohn_rpcc_provenance_value(original[[key]],entries[[key]],by_entry[[key]])
    json(value,paste0(export$prefix,"source-provenance.json"),"complete_cardiac_provenance")
    stage$provenance<-c(stage$provenance,key);invisible(value)
  }
  api$render_section<-function(section_id,prefix,figure,payload_prefix){
    brohn_require(brohn_text(section_id,500)&&section_id%in%names(sections)&&!section_id%in%stage$sections,"Choose one captured declared cardiac section, rendered once.")
    h<-sections[[section_id]];key<-lookup(h$source_report_ref);export<-require_export(key)
    brohn_require(is.function(figure)&&identical(prefix,prefixes[[section_id]])&&identical(payload_prefix,export$prefix),"Use this captured section's exact figure and completed source payload prefixes.")
    entry<-entries[[key]];resolved<-.brohn_rpca_section_core(h$cardiac_section,entry)
    brohn_require(resolved$panel_count==counts[[section_id]],"The captured section changed its preflight panel count.")
    result<-.brohn_rpcc_render_section_core(h,entry,prefix,figure,captured$selection$cardiac_chapter_resolution,payload_prefix,
      resolved,.brohn_rpca_overview_core(entry,captured$selection$cardiac_chapter_resolution))
    brohn_require(result$panel_count==counts[[section_id]],"Rendered figures differ from the captured exact panel count.")
    stage$sections<-c(stage$sections,section_id);result
  }
  lockEnvironment(api,bindings=TRUE)
  state$session<-api;state
}

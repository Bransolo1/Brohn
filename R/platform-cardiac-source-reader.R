# Private operation-local acceleration. No public/default reader is replaced.
# The only captured proof inputs are reference-free JSON values; current rows,
# authority, producer state and all native guard/byte fences still run normally.
.brohn_csp_value <- function(x, depth=0L) {
  if(depth>64L)return(FALSE)
  if(is.null(x))return(TRUE)
  a<-attributes(x)
  if(typeof(x)=="list"&&!is.object(x)){
    if(!is.null(a)&&!identical(names(a),"names"))return(FALSE)
    if(!is.null(a)&&(!is.character(a$names)||!is.null(attributes(a$names))))return(FALSE)
    return(all(vapply(x,.brohn_csp_value,logical(1),depth=depth+1L)))
  }
  is.null(a)&&(is.character(x)||is.logical(x)||is.integer(x)||is.double(x))
}
.brohn_cardiac_source_reader <- function(store,pulse=NULL) {
  .brohn_store_ready(store)
  workspace<-store$workspace_id;root<-normalizePath(store$root,winslash="/",mustWork=TRUE)
  parent<-environment(.brohn_cardiac_source_reader)
  scope<-new.env(parent=parent);state<-new.env(parent=emptyenv())
  state$closed<-FALSE;state$records<-list();state$values<-list()
  state$record_bytes<-0;state$value_bytes<-0
  state$hits<-c(record=0L,value=0L);state$misses<-c(record=0L,value=0L)
  maximum<-24*1024^2;entries<-64L
  strict<-function(a,b)identical(a,b,num.eq=FALSE,attrib.as.set=FALSE)
  assert<-function(current=store){
    brohn_require(!isTRUE(state$closed),"Reopen this closed cardiac source reader.")
    .brohn_store_ready(current)
    brohn_require(identical(current$workspace_id,workspace)&&identical(current$con,store$con)&&
      identical(normalizePath(current$root,winslash="/",mustWork=TRUE),root),
      "This cardiac source reader belongs to another workspace or store.")
    invisible(TRUE)
  }
  close<-function(){state$closed<-TRUE;state$records<-list();state$values<-list();state$record_bytes<-0;state$value_bytes<-0;invisible(NULL)}
  # A cap affects reuse only. Unsupported inputs and cache exhaustion follow
  # the original implementation, so admission and validation are unchanged.
  memo<-function(domain,original){force(domain);force(original);function(x){
    brohn_require(!isTRUE(state$closed),"Reopen this closed cardiac source reader.")
    for(entry in state$values)if(identical(entry$domain,domain)&&strict(x,entry$input)){
      state$hits[["value"]]<-state$hits[["value"]]+1L;return(entry$output)
    }
    state$misses[["value"]]<-state$misses[["value"]]+1L
    value<-original(x)
    if(length(state$values)<entries&&as.numeric(object.size(x))>=2048&&.brohn_csp_value(x)&&.brohn_csp_value(value)){
      size<-as.numeric(object.size(list(x,value,domain)))
      if(size<=maximum-state$value_bytes){
        state$values[[length(state$values)+1L]]<-list(domain=domain,input=x,output=value)
        state$value_bytes<-state$value_bytes+size
      }
    }
    value
  }}
  for(n in c("brohn_hash","brohn_json","brohn_eda_value_hash","brohn_canonical"))
    assign(n,memo(n,get(n,envir=parent,inherits=TRUE)),envir=scope)
  read<-function(current,ref,kind=NULL){
    assert(current);.brohn_rpk_source_pulse(pulse)
    .brohn_rpk_ref_catalog(current,ref,kind)
    row<-DBI::dbGetQuery(current$con,"SELECT * FROM entity_versions WHERE kind=? AND id=? AND revision=?",
      params=list(ref$kind,ref$id,ref$revision))
    brohn_require(nrow(row)==1L,"The saved source differs from its exact reference.")
    if(!is.null(current$hosted_profile))brohn_hosted_require_project(current,row$project_id[[1L]])
    cached<-NULL
    for(entry in state$records)if(strict(entry$ref,ref)){
      brohn_require(identical(row$body_hash[[1L]],entry$raw_hash)&&
        identical(charToRaw(row$body_json[[1L]]),charToRaw(entry$text)),
        "The saved source bytes changed during this held operation.")
      cached<-entry;break
    }
    if(is.null(cached)){
      state$misses[["record"]]<-state$misses[["record"]]+1L
      record<-.brohn_store_entity(row)
      brohn_require(!is.null(record)&&.brohn_rpk_same(.brohn_rpk_ref(record),ref),
        "The saved source differs from its exact reference.")
      entry<-list(ref=ref,text=row$body_json[[1L]],raw_hash=row$body_hash[[1L]],body=record$body)
      size<-as.numeric(object.size(entry))
      if(length(state$records)<entries&&size<=maximum-state$record_bytes&&.brohn_csp_value(entry)){
        state$records[[length(state$records)+1L]]<-entry;state$record_bytes<-state$record_bytes+size
      }
    }else{
      state$hits[["record"]]<-state$hits[["record"]]+1L
      record<-list(id=row$id[[1L]],kind=row$kind[[1L]],project_id=row$project_id[[1L]],revision=as.integer(row$revision[[1L]]),
        body=cached$body,created_at=row$created_at[[1L]],updated_at=row$updated_at[[1L]])
      brohn_require(identical(record$id,ref$id)&&identical(record$kind,ref$kind)&&
        identical(record$project_id,ref$project_id)&&record$revision==ref$revision,
        "The saved source differs from its exact reference.")
    }
    .brohn_rpk_source_pulse(pulse);record
  }
  assign(".brohn_rpk_record",read,envir=scope)
  # Each function is copied before rebinding its environment. Original public
  # functions retain their exact body, formals and environment. The allowlist
  # excludes publication, producer execution, payload algorithms and serializers.
  allowed<-c(".brohn_rpk_ref",".brohn_rpk_same",".brohn_cds_record",".brohn_cds_job",
    ".brohn_cds_report_metadata","brohn_cardiac_source_metadata",
    "brohn_cardiac_display_sources_current","brohn_open_cardiac_display_sources",
    "brohn_cardiac_display_metadata","brohn_open_cardiac_display_resources",
    "brohn_cardiac_display_resources_current",".brohn_rpcc_selection_sources")
  for(n in allowed){f<-get(n,envir=parent,inherits=TRUE);brohn_require(is.function(f),"The cardiac reader implementation is incomplete.")
    environment(f)<-scope;assign(n,f,envir=scope)}
  lockEnvironment(scope,bindings=TRUE)
  invoke<-function(name){force(name);function(current,...){
    result<-NULL
    tryCatch({assert(current);.brohn_rpk_source_pulse(pulse)
      result<-get(name,envir=scope,inherits=FALSE)(current,...);.brohn_rpk_source_pulse(pulse);result},
      error=function(e){
        if(identical(name,"brohn_open_cardiac_display_resources")&&!is.null(result$handle))
          tryCatch(brohn_release_cardiac_display_resources(result$handle),error=function(cleanup)NULL)
        close();stop(e)
      })
  }}
  reader<-new.env(parent=emptyenv())
  reader$selection<-invoke(".brohn_rpcc_selection_sources")
  reader$open<-invoke("brohn_open_cardiac_display_resources")
  reader$current<-invoke("brohn_cardiac_display_resources_current")
  reader$close<-close
  # Diagnostics contain counts only, never cached values or reusable proofs.
  reader$diagnostics<-function()list(closed=state$closed,hits=state$hits,misses=state$misses,
    records=length(state$records),values=length(state$values),record_bytes=state$record_bytes,value_bytes=state$value_bytes)
  lockEnvironment(reader,bindings=TRUE);reader
}

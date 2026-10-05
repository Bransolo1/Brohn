# Pure flat evidence ancestry. No source reads, stores, compiler calls or authority.
# Candidate02 remains the independently validating current-capsule dependency.
.brohn_mea_size <- function(x) {
  required <- nchar(.brohn_meb_json(x),type="bytes")
  maximum <- 16L*1024L*1024L
  .brohn_meb_need(required<=maximum,paste0("Evidence wrapper requires ",required," bytes; maximum is ",maximum," bytes. No ancestry was removed."))
  invisible(required)
}
.brohn_mea_hash <- function(value,prefix) {
  encoded <- .brohn_meb_json(brohn_method_evidence_tag(value))
  digest::digest(c(charToRaw(paste0(prefix,"\n")),charToRaw(enc2utf8(encoded))),algo="sha256",serialize=FALSE)
}
.brohn_mea_id <- function(x) .brohn_me_text(x,96L)&&grepl("^[A-Za-z][A-Za-z0-9_-]*$",x)
.brohn_mea_ref <- function(x,kind) {
  .brohn_meb_fields(x,c("kind","id","project_id","revision","body_hash"),"Original catalog reference")
  .brohn_meb_need(identical(x$kind,kind)&&.brohn_mea_id(x$id)&&.brohn_mea_id(x$project_id)&&
    typeof(x$revision)%in%c("integer","double")&&length(x$revision)==1L&&!is.na(x$revision)&&
    is.finite(x$revision)&&x$revision>=1&&x$revision<=.Machine$integer.max&&x$revision==floor(x$revision)&&
    .brohn_me_sha(x$body_hash),"Original reference requires exact kind, IDs, positive revision and stored-body SHA256.")
  invisible(TRUE)
}
.brohn_mea_source <- function(x) {
  .brohn_meb_fields(x,c("origin_workspace_id","design_ref","design_value_hash"),"Original design provenance")
  .brohn_meb_need(.brohn_mea_id(x$origin_workspace_id)&&.brohn_me_sha(x$design_value_hash),"Original workspace and design-value hash are required; destination provenance cannot be substituted.")
  .brohn_mea_ref(x$design_ref,"study")
  invisible(TRUE)
}
.brohn_mea_via <- function(operation,via) {
  .brohn_meb_need(.brohn_me_text(operation,40L)&&operation%in%c("clone_design","use_template","import_design"),"Unsupported single-source inheritance operation.")
  if(identical(operation,"clone_design")) {
    .brohn_meb_fields(via,"kind","Clone route")
    .brohn_meb_need(identical(via$kind,"direct_clone"),"Clone provenance needs the direct_clone route.")
  }else if(identical(operation,"use_template")) {
    .brohn_meb_fields(via,c("kind","template_ref"),"Template route")
    .brohn_meb_need(identical(via$kind,"template"),"Template provenance needs an exact template route.")
    .brohn_mea_ref(via$template_ref,"template")
  }else {
    .brohn_meb_fields(via,c("kind","archive_sha256","manifest_sha256"),"Portable route")
    .brohn_meb_need(identical(via$kind,"portable_package")&&.brohn_me_sha(via$archive_sha256)&&.brohn_me_sha(via$manifest_sha256),"Import provenance needs exact original archive and manifest SHA256 values.")
  }
  invisible(TRUE)
}
.brohn_mea_edges <- function(edges,label) {
  .brohn_meb_need(.brohn_me_array(edges)&&length(edges)<=1L,paste(label,"requires zero or one source edge; merging is unsupported."))
  for(edge in edges) {
    .brohn_meb_fields(edge,c("node_id","operation","via"),"Ancestry edge")
    .brohn_meb_need(.brohn_me_sha(edge$node_id),"Ancestry edge needs its exact node SHA256.")
    .brohn_mea_via(edge$operation,edge$via)
  }
  invisible(TRUE)
}
.brohn_mea_node_shape <- function(node) {
  .brohn_meb_fields(node,c("node_id","source","current","parents"),"Ancestry node")
  .brohn_meb_need(.brohn_me_sha(node$node_id),"Ancestry node needs its exact SHA256.")
  .brohn_mea_source(node$source);.brohn_mea_edges(node$parents,"Original node parents")
  invisible(TRUE)
}
.brohn_mea_node_id <- function(node) .brohn_mea_hash(node[c("source","current","parents")],"brohn-method-evidence-ancestry-node/0.1")
.brohn_mea_header <- function(wrapper) {
  .brohn_meb_domain(wrapper);.brohn_mea_size(wrapper)
  .brohn_meb_fields(wrapper,c("schema","current","ancestry"),"Method evidence wrapper")
  .brohn_meb_need(identical(wrapper$schema,"brohn-study-method-evidence-envelope/0.1"),"Unsupported evidence wrapper schema.")
  a<-wrapper$ancestry
  .brohn_meb_fields(a,c("schema","roots","nodes"),"Flat evidence ancestry")
  .brohn_meb_need(identical(a$schema,"brohn-method-evidence-ancestry/0.1"),"Unsupported ancestry schema.")
  .brohn_mea_edges(a$roots,"Ancestry roots")
  .brohn_meb_need(.brohn_me_array(a$nodes),"Ancestry nodes must be a flat array.")
  for(node in a$nodes).brohn_mea_node_shape(node)
  ids<-vapply(a$nodes,`[[`,character(1),"node_id")
  .brohn_meb_need(!anyDuplicated(ids)&&identical(ids,.brohn_meb_sort(ids)),"Historical node inventory needs unique canonical node-ID order.")
  # Sole-parent topology is checked before payload hashing, so cycles and orphans
  # have explicit refusals rather than relying on a hash mismatch to reject them.
  next_id<-if(length(a$roots))a$roots[[1L]]$node_id else NULL
  visited<-character()
  while(!is.null(next_id)) {
    .brohn_meb_need(!next_id%in%visited,"Ancestry cycle is unsupported.")
    index<-match(next_id,ids)
    .brohn_meb_need(!is.na(index),"Ancestry references a missing original node.")
    visited<-c(visited,next_id)
    parents<-a$nodes[[index]]$parents
    next_id<-if(length(parents))parents[[1L]]$node_id else NULL
  }
  .brohn_meb_need(length(visited)==length(ids),"Ancestry contains orphan nodes; no original node may be silently discarded.")
  invisible(TRUE)
}
.brohn_mea_capsule_validator <- function() {
  # This private memo exists only during one public call and is never returned.
  # Its keys refer to whole fully validated capsules, not unchecked registry pins.
  checked<-new.env(parent=emptyenv())
  function(current) {
    encoded<-.brohn_meb_json(brohn_method_evidence_tag(current))
    key<-digest::digest(charToRaw(enc2utf8(encoded)),algo="sha256",serialize=FALSE)
    if(exists(key,envir=checked,inherits=FALSE)) {
      .brohn_meb_need(identical(get(key,envir=checked,inherits=FALSE),encoded),"Conflicting captured values share a capsule digest.")
      return(invisible(TRUE))
    }
    brohn_method_evidence_binding_validate(current)
    assign(key,encoded,envir=checked)
    invisible(TRUE)
  }
}
.brohn_mea_validate <- function(wrapper,additional_current=list()) {
  .brohn_mea_header(wrapper)
  validate_current<-.brohn_mea_capsule_validator()
  validate_current(wrapper$current)
  for(current in additional_current)validate_current(current)
  origins<-new.env(parent=emptyenv())
  for(node in wrapper$ancestry$nodes) {
    s<-node$source;r<-s$design_ref
    key<-.brohn_mea_hash(list(origin_workspace_id=s$origin_workspace_id,project_id=r$project_id,id=r$id,revision=r$revision),"brohn-method-evidence-source-identity/0.1")
    .brohn_meb_need(!exists(key,envir=origins,inherits=FALSE),"Conflicting ancestry nodes declare the same original study revision.")
    assign(key,node$node_id,envir=origins)
    validate_current(node$current)
    .brohn_meb_need(identical(node$node_id,.brohn_mea_node_id(node)),"Original node values differ from their canonical typed node hash.")
  }
  invisible(wrapper)
}
.brohn_mea_normalize <- function(nodes) {
  .brohn_meb_need(.brohn_me_array(nodes),"Ancestry node input must be a flat array.")
  kept<-list();seen<-new.env(parent=emptyenv())
  for(node in nodes) {
    .brohn_mea_node_shape(node)
    encoded<-.brohn_meb_json(brohn_method_evidence_tag(node))
    id<-node$node_id
    if(exists(id,envir=seen,inherits=FALSE)) {
      .brohn_meb_need(identical(get(id,envir=seen,inherits=FALSE),encoded),"Repeated node ID carries conflicting original values.")
    }else {
      assign(id,encoded,envir=seen);kept[[length(kept)+1L]]<-node
    }
  }
  if(length(kept))kept<-kept[order(vapply(kept,`[[`,character(1),"node_id"),method="radix")]
  kept
}

# This is a value hash, never a catalog raw-byte hash or source-authority proof.
brohn_method_evidence_design_value_hash <- function(design) {
  .brohn_meb_domain(design)
  .brohn_mea_hash(design,"brohn-method-evidence-design-value/0.1")
}
brohn_method_evidence_envelope <- function(current,roots=list(),nodes=list()) {
  raw<-list(schema="brohn-study-method-evidence-envelope/0.1",current=current,
    ancestry=list(schema="brohn-method-evidence-ancestry/0.1",roots=roots,nodes=nodes))
  .brohn_meb_domain(raw);.brohn_mea_size(raw)
  raw$ancestry$nodes<-.brohn_mea_normalize(nodes)
  .brohn_mea_validate(raw);raw
}
brohn_method_evidence_envelope_validate <- function(wrapper) .brohn_mea_validate(wrapper)
brohn_method_evidence_envelope_update <- function(wrapper,current) {
  # Updating current evidence is not cloning and never creates a self-edge.
  .brohn_mea_header(wrapper)
  out<-wrapper;out$current<-current
  # The private operation memo also validates the replaced original current.
  # Invalid source wrappers cannot heal; unchanged capsules are checked once.
  .brohn_mea_validate(out,list(wrapper$current))
  out
}
brohn_method_evidence_inherit <- function(source_wrapper,source,destination_current,operation,via) {
  # Source authority and matching this capsule to the actual enclosing design
  # are explicit facade obligations. This function cannot prove either claim.
  .brohn_mea_header(source_wrapper)
  .brohn_meb_domain(source);.brohn_mea_source(source);.brohn_meb_domain(via);.brohn_mea_via(operation,via)
  node<-list(source=source,current=source_wrapper$current,parents=source_wrapper$ancestry$roots)
  node<-c(list(node_id=.brohn_mea_node_id(node)),node)
  edge<-list(node_id=node$node_id,operation=operation,via=via)
  out<-brohn_method_evidence_envelope(destination_current,list(edge),c(source_wrapper$ancestry$nodes,list(node)))
  .brohn_meb_need(.brohn_meb_equal(source_wrapper$current$registry_capture$value$registry_ref,destination_current$registry_capture$value$registry_ref),
    "A derived study must initially retain the exact inherited registry pin; a later explicit reference update is a separate operation.")
  out
}

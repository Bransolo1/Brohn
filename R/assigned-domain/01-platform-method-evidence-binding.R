# Prospective pure computational bindings. No store, current-file or science calls.
.brohn_meb_need <- function(ok, message) if (!isTRUE(ok)) stop(message, call. = FALSE)
.brohn_meb_fields <- function(x, names, label) {.brohn_meb_plain(x);.brohn_me_fields(x, names, label)}
.brohn_meb_json <- function(x) {
  canonical <- function(v) {
    if(typeof(v)!="list")return(v)
    if(!is.null(names(v)))v<-v[order(enc2utf8(names(v)),method="radix")]
    lapply(v,canonical)
  }
  as.character(jsonlite::toJSON(canonical(x),auto_unbox=TRUE,null="null",digits=17,force=TRUE))
}
.brohn_meb_sort <- function(x) x[order(enc2utf8(x), method="radix")]
.brohn_meb_plain <- function(x) {
  a <- attributes(x)
  .brohn_meb_need(is.null(a) || (typeof(x)=="list" && identical(names(a),"names")), "Captured values require plain JSON types without attributes.")
}

.brohn_meb_domain <- function(value) {
  count<-0L
  walk<-function(x,depth=0L) {
    count<<-count+1L;.brohn_meb_need(depth<64L&&count<=200000L,"Evidence value exceeds bounded JSON depth/node limits.")
    .brohn_meb_plain(x)
    if(is.null(x))return(invisible(TRUE))
    if(typeof(x)=="list") {
      n<-names(x)
      if(!is.null(n)).brohn_meb_need(!anyNA(n)&&all(nzchar(n))&&all(validUTF8(n))&&!anyDuplicated(enc2utf8(n)),"Evidence object keys require unique UTF-8.")
      for(v in x)walk(v,depth+1L)
      return(invisible(TRUE))
    }
    .brohn_meb_need(typeof(x)%in%c("character","logical","integer","double")&&length(x)==1L&&!is.na(x),"Evidence values require finite plain JSON scalars.")
    if(is.character(x)).brohn_meb_need(validUTF8(x)&&nchar(x,type="bytes")<=2L*1024L*1024L,"Evidence text exceeds UTF-8/byte limits.")
    if(is.numeric(x)).brohn_meb_need(is.finite(x),"Evidence numbers must be finite.")
    invisible(TRUE)
  }
  walk(value);invisible(TRUE)
}

brohn_method_evidence_tag <- function(value) {
  count <- 0L
  walk <- function(x, depth=0L) {
    count <<- count+1L
    .brohn_meb_need(depth<48L && count<=200000L, "Captured projection exceeds depth/node limits.")
    .brohn_meb_plain(x)
    if (is.null(x)) return(list(t="null"))
    if (typeof(x)=="list") {
      n <- names(x)
      if (is.null(n)) return(list(t="array", items=lapply(x, walk, depth=depth+1L)))
      .brohn_meb_need(!anyNA(n) && all(nzchar(n)) && all(validUTF8(n)) && !anyDuplicated(enc2utf8(n)), "Captured object keys must be unique valid UTF-8.")
      order <- order(enc2utf8(n), method="radix")
      fields <- lapply(order, function(i) list(key=enc2utf8(n[[i]]), value=walk(x[[i]], depth+1L)))
      return(list(t="object", fields=fields))
    }
    .brohn_meb_need(typeof(x)%in%c("character","logical","integer","double"),"Unsupported captured reference or primitive type.")
    .brohn_meb_need(length(x)==1L && !is.na(x), "Captured primitive values must be scalar and not NA.")
    if (typeof(x)=="character") {
      .brohn_meb_need(validUTF8(x) && nchar(x,type="bytes")<=2L*1024L*1024L, "Captured text must be bounded valid UTF-8.")
      return(list(t="string", value=enc2utf8(x)))
    }
    if (typeof(x)=="logical") return(list(t="boolean", value=x))
    .brohn_meb_need(typeof(x)%in%c("integer","double") && is.finite(x), "Captured numbers require finite binary64 values.")
    list(t="binary64", hex=paste(format(writeBin(as.double(x),raw(),size=8L,endian="big")),collapse=""))
  }
  result <- walk(value)
  .brohn_meb_need(nchar(.brohn_meb_json(result),type="bytes")<=12L*1024L*1024L, "Captured tagged projection exceeds 12 MiB.")
  result
}

brohn_method_evidence_untag <- function(tree) {
  .brohn_meb_domain(tree)
  count <- 0L
  walk <- function(x, depth=0L) {
    count <<- count+1L
    .brohn_meb_need(depth<48L && count<=200000L, "Tagged projection exceeds depth/node limits.")
    .brohn_meb_plain(x)
    .brohn_meb_need(typeof(x)=="list" && .brohn_me_text(x$t,20L), "Tagged projection needs an exact type.")
    type <- x$t
    if (type=="null") {.brohn_meb_fields(x,"t","Tagged null");return(NULL)}
    if (type=="array") {
      .brohn_meb_fields(x,c("t","items"),"Tagged array");.brohn_meb_need(.brohn_me_array(x$items),"Tagged array needs array items.")
      return(lapply(x$items,walk,depth=depth+1L))
    }
    if (type=="object") {
      .brohn_meb_fields(x,c("t","fields"),"Tagged object");.brohn_meb_need(.brohn_me_array(x$fields),"Tagged object needs array fields.")
      n <- vapply(x$fields,function(f){.brohn_meb_fields(f,c("key","value"),"Tagged object field");.brohn_meb_need(.brohn_me_text(f$key,20000L),"Tagged key must be nonempty UTF-8.");f$key},character(1))
      .brohn_meb_need(!anyDuplicated(enc2utf8(n)) && identical(n,.brohn_meb_sort(n)), "Tagged object fields need unique UTF-8 byte order.")
      out <- setNames(vector("list",length(n)),n)
      for (i in seq_along(n)) out[i] <- list(walk(x$fields[[i]]$value,depth+1L))
      return(out)
    }
    if (type=="binary64") {
      .brohn_meb_fields(x,c("t","hex"),"Tagged number")
      .brohn_meb_need(is.character(x$hex) && length(x$hex)==1L && !is.na(x$hex) && grepl("^[0-9a-f]{16}$",x$hex),"Tagged binary64 needs sixteen lowercase hexadecimal digits.")
      bytes <- as.raw(strtoi(substring(x$hex,seq.int(1L,15L,2L),seq.int(2L,16L,2L)),16L))
      out <- readBin(bytes,"double",n=1L,size=8L,endian="big")
      .brohn_meb_need(is.finite(out),"Tagged nonfinite numbers are not allowed.")
      return(out)
    }
    .brohn_meb_fields(x,c("t","value"),"Tagged scalar")
    .brohn_meb_plain(x$value)
    if(type=="boolean") {.brohn_meb_need(is.logical(x$value)&&length(x$value)==1L&&!is.na(x$value),"Tagged boolean needs true/false.");return(x$value)}
    .brohn_meb_need(type=="string" && typeof(x$value)=="character"&&length(x$value)==1L&&!is.na(x$value)&&validUTF8(x$value),"Unknown tagged type or invalid string.")
    enc2utf8(x$value)
  }
  out <- walk(tree)
  canonical <- brohn_method_evidence_tag(out)
  .brohn_meb_need(identical(.brohn_meb_json(tree),.brohn_meb_json(canonical)),"Tagged projection is not in canonical form.")
  out
}

brohn_method_evidence_projection_hash <- function(tree) {
  value <- brohn_method_evidence_untag(tree)
  digest::digest(c(charToRaw("brohn-captured-input/0.1\n"),charToRaw(.brohn_meb_json(brohn_method_evidence_tag(value)))),algo="sha256",serialize=FALSE)
}
.brohn_meb_equal <- function(a,b) identical(brohn_method_evidence_tag(a),brohn_method_evidence_tag(b))
.brohn_meb_storable <- function(x) {
  .brohn_meb_need(exists("brohn_json",mode="function")&&exists(".brohn_store_json",mode="function"),"Capture needs the actual protocol and store encoders for round-trip validation.")
  target <- brohn_method_evidence_tag(x)
  for (encode in list(brohn_json,.brohn_store_json)) {
    recovered <- jsonlite::fromJSON(encode(x),simplifyVector=FALSE)
    .brohn_meb_need(identical(target,brohn_method_evidence_tag(recovered)),"Captured input does not round-trip through stored JSON exactly; no normalized binding was created.")
  }
  invisible(TRUE)
}
.brohn_meb_ref <- function(ref) {
  .brohn_meb_fields(ref,c("registry_id","revision","sha256"),"Pinned registry ref")
  .brohn_meb_need(.brohn_me_text(ref$registry_id,200L)&&.brohn_me_text(ref$revision,100L)&&.brohn_me_sha(ref$sha256),"Registry pin needs exact ID/revision/SHA256.")
}
.brohn_meb_registry <- function(capture) {
  .brohn_meb_domain(capture)
  .brohn_meb_fields(capture,c("kind","value"),"Registry capture")
  x <- capture$value
  if(identical(capture$kind,"reference_unavailable")) {
    .brohn_meb_fields(x,c("registry_ref","reason"),"Unavailable reference");.brohn_meb_ref(x$registry_ref)
    .brohn_meb_need(.brohn_me_text(x$reason,2000L),"Unavailable reference needs a bounded reason.")
    return(list(ref=x$registry_ref,text=NULL,registry=NULL))
  }
  if(identical(capture$kind,"claim_snapshot")) {
    brohn_method_evidence_reopen(x)
  }else {
    .brohn_meb_need(identical(capture$kind,"registry_context"),"Unsupported registry capture kind.")
    .brohn_meb_fields(x,c("schema","registry_ref","registry_text"),"Registry context")
    .brohn_meb_need(identical(x$schema,"brohn-method-evidence-registry-context/0.1"),"Unsupported registry context schema.")
  }
  .brohn_meb_ref(x$registry_ref)
  registry <- .brohn_me_parse(x$registry_text)
  .brohn_meb_need(identical(.brohn_me_ref(registry,x$registry_text),x$registry_ref),"Captured registry bytes or identity differ from the pin.")
  list(ref=x$registry_ref,text=x$registry_text,registry=registry)
}

brohn_method_evidence_registry_context <- function(registry_ref, registry_text=NULL, unavailable_reason=NULL) {
  .brohn_meb_ref(registry_ref)
  if(is.null(registry_text)) result <- list(kind="reference_unavailable",value=list(registry_ref=registry_ref,reason=unavailable_reason)) else {
    .brohn_meb_need(is.null(unavailable_reason),"Available registry cannot carry an unavailable reason.")
    result <- list(kind="registry_context",value=list(schema="brohn-method-evidence-registry-context/0.1",registry_ref=registry_ref,registry_text=registry_text))
  }
  .brohn_meb_registry(result);result
}
.brohn_meb_context <- function(x) {
  .brohn_meb_fields(x,c("population","task","device","setting"),"Declared context")
  for(v in x) {
    .brohn_meb_fields(v,c("state","value"),"Context field")
    .brohn_meb_need((identical(v$state,"not_supplied")&&is.null(v$value)) ||
      (identical(v$state,"declared")&&.brohn_me_text(v$value,4000L)),"Context must be explicitly unknown or declared text.")
  }
  invisible(TRUE)
}
.brohn_meb_implementation <- function(x) {
  .brohn_meb_fields(x,c("schema","resolver","source_manifest_sha256"),"Binding implementation ref")
  .brohn_meb_need(identical(x$schema,"brohn-method-evidence-resolver-implementation/0.1") &&
    identical(x$resolver,"brohn-task-evidence-resolver/0.1") && .brohn_me_sha(x$source_manifest_sha256),"Invalid resolver implementation identity.")
}
# Frozen resolver0.1 semantic helpers. Future resolver versions need separate
# decision/shape/coverage functions selected by saved envelope identity.
.brohn_meb_targets_0_1 <- function() list(
  "iat-procedure"=c("iat-gnb2003-d1/1.0","task.profile","/profile"),
  "biat-procedure"=c("biat-nosek2014-goodfocal/1.0","task.profile","/profile"),
  "procedure-rt-deary-liewald-simple"=c("rt-deary-liewald-simple/1.0","task.profile","/profile"),
  "procedure-rt-deary-liewald-choice"=c("rt-deary-liewald-choice/1.0","task.profile","/profile"),
  "sciat-response-window"=c("sciat-brohn-response-window-im100/1.0","task.profile","/profile"),
  "gnat-procedure"=c("gnat-brohn-single-target/1.0","task.profile","/profile"),
  "aat-rt-window"=c("aat-keyboard-cue-balanced/1.0","compiled.scoring","/rt_min_ms"))
.brohn_meb_decisions_0_1 <- function(projection,registry) {
  block <- projection$block;bindings<-list();gaps<-list()
  gap <- function(id,reason) {gaps[[length(gaps)+1L]]<<-list(claim_id=id,reason=reason)}
  if(is.null(registry)) {gap(NULL,"reference_unavailable");return(list(bindings=bindings,gaps=gaps))}
  claims <- Filter(function(c) block$profile %in% unlist(c$method_refs),registry$claims)
  if(!length(claims)) gap(NULL,"method_not_catalogued")
  claims <- claims[order(vapply(claims,`[[`,character(1),"id"),method="radix")]
  targets <- .brohn_meb_targets_0_1()
  for(claim in claims) {
    target<-targets[[claim$id]];b<-claim$binding
    if(is.null(target)||!identical(c(block$profile,b$input_scope,b$option_path),unname(target))||!identical(b$current_value_role,"fixed_recipe_value")) {gap(claim$id,"resolver_unavailable");next}
    if(identical(target[[2]],"task.profile")) actual<-block$profile else {
      if(is.null(projection$compiled_scoring)||!"rt_min_ms"%in%names(projection$compiled_scoring)) {gap(claim$id,"resolver_unavailable");next}
      actual<-projection$compiled_scoring$rt_min_ms
    }
    if(!.brohn_meb_equal(actual,b$current_value)) {gap(claim$id,"claim_input_mismatch");next}
    bindings[[length(bindings)+1L]]<-list(claim_id=claim$id,input_scope=b$input_scope,option_path=b$option_path,
      resolver=if(target[[2]]=="task.profile")"brohn-task-profile-input/0.1"else"brohn-aat-compiled-scoring-input/0.1",
      status="inputs_bound",actual=brohn_method_evidence_tag(actual))
  }
  list(bindings=bindings,gaps=gaps)
}
.brohn_meb_coverage_0_1 <- function(tasks) list(task_binding=if(!length(tasks))"no_task_blocks"else if(any(vapply(tasks,function(t)length(t$bindings)>0L,logical(1))))"partial_option_coverage"else"no_supported_task_bindings",
  template_and_nontask_options="outside_resolver_coverage",scientific_applicability="unresolved")
.brohn_meb_claim_ids <- function(tasks) as.list(.brohn_meb_sort(unique(as.character(unlist(lapply(tasks,function(t)lapply(t$bindings,`[[`,"claim_id")),use.names=FALSE)))))
.brohn_meb_capture <- function(original,tasks) {
  r<-.brohn_meb_registry(original);ids<-.brohn_meb_claim_ids(tasks)
  if(is.null(r$registry))return(original)
  if(!length(ids))return(brohn_method_evidence_registry_context(r$ref,r$text))
  list(kind="claim_snapshot",value=list(schema="brohn-method-evidence-snapshot/0.1",registry_ref=r$ref,selected_claim_ids=ids,registry_text=r$text))
}

.brohn_meb_scoring_shape_0_1 <- function(profile,x) {
  if(!identical(profile,"aat-keyboard-cue-balanced/1.0")) {.brohn_meb_need(is.null(x),"Non-AAT projection has no compiled scoring in this resolver version.");return(invisible(TRUE))}
  .brohn_meb_fields(x,c("description","first_response_and_corrections_retained","rt_min_ms","rt_max_ms"),"Complete original AAT scoring metadata")
  .brohn_meb_need(.brohn_me_text(x$description,4000L)&&identical(x$first_response_and_corrections_retained,TRUE)&&
    typeof(x$rt_min_ms)%in%c("integer","double")&&length(x$rt_min_ms)==1L&&is.finite(x$rt_min_ms)&&
    typeof(x$rt_max_ms)%in%c("integer","double")&&length(x$rt_max_ms)==1L&&is.finite(x$rt_max_ms)&&x$rt_min_ms>=0&&x$rt_max_ms>x$rt_min_ms,
    "Captured AAT scoring metadata is incomplete or invalid.")
  invisible(TRUE)
}

.brohn_meb_scoring <- function(block) {
  if(!identical(block$profile,"aat-keyboard-cue-balanced/1.0"))return(NULL)
  existed<-exists(".Random.seed",envir=.GlobalEnv,inherits=FALSE)
  prior<-if(existed)get(".Random.seed",envir=.GlobalEnv,inherits=FALSE)else NULL
  kind<-RNGkind()
  on.exit({do.call(RNGkind,as.list(kind));if(existed)assign(".Random.seed",prior,envir=.GlobalEnv)else if(exists(".Random.seed",envir=.GlobalEnv,inherits=FALSE))rm(".Random.seed",envir=.GlobalEnv)},add=TRUE)
  values<-lapply(c(1L,2L),function(allocation)brohn_task_compile(block,allocation_index=allocation)$scoring)
  .brohn_meb_need(.brohn_meb_equal(values[[1L]],values[[2L]]),"AAT compiler scoring metadata changes with allocation; binding unavailable.")
  .brohn_meb_need(identical(RNGkind(),kind)&&identical(exists(".Random.seed",envir=.GlobalEnv,inherits=FALSE),existed)&&
    (!existed||identical(get(".Random.seed",envir=.GlobalEnv,inherits=FALSE),prior)),"AAT compiler changed caller RNG state; binding refused and state restored.")
  values[[1L]]
}

brohn_method_evidence_bind <- function(blocks,context,registry_capture,implementation_ref,captured_at,previous=NULL) {
  .brohn_meb_domain(blocks);.brohn_meb_domain(context);.brohn_meb_domain(implementation_ref)
  .brohn_meb_need(.brohn_me_array(blocks)&&length(blocks)<=200L,"Binding needs the bounded ordered task array.")
  .brohn_meb_context(context);.brohn_meb_storable(context);.brohn_meb_implementation(implementation_ref)
  registry<-.brohn_meb_registry(registry_capture)$registry
  if(length(blocks)) .brohn_meb_need(!anyDuplicated(vapply(blocks,`[[`,character(1),"id")),"Duplicate captured task IDs.")
  tasks<-lapply(blocks,function(block){
    brohn_task_validate(block);.brohn_meb_storable(block)
    scoring<-.brohn_meb_scoring(block);.brohn_meb_scoring_shape_0_1(block$profile,scoring);.brohn_meb_storable(scoring)
    projection<-list(block=block,compiled_scoring=scoring,context=context)
    tagged<-brohn_method_evidence_tag(projection);decisions<-.brohn_meb_decisions_0_1(projection,registry)
    list(task_id=block$id,method_ref=block$profile,input_projection=tagged,input_hash=brohn_method_evidence_projection_hash(tagged),bindings=decisions$bindings,gaps=decisions$gaps)
  })
  out<-list(schema="brohn-study-method-evidence/0.1",registry_capture=.brohn_meb_capture(registry_capture,tasks),
    implementation_ref=implementation_ref,captured_at=captured_at,context=brohn_method_evidence_tag(context),tasks=tasks,
    coverage=.brohn_meb_coverage_0_1(tasks),inherited_references=list())
  brohn_method_evidence_binding_validate(out)
  if(!is.null(previous)) {
    brohn_method_evidence_binding_validate(previous)
    a<-out;b<-previous;a$captured_at<-b$captured_at<-NULL
    # Reuse an intact prior binding when meaning has not changed, even if the
    # installed implementation receipt changes; no current-code equality gate.
    a$implementation_ref<-b$implementation_ref<-NULL
    if(.brohn_meb_equal(a,b))return(previous)
  }
  .brohn_meb_storable(out);out
}

brohn_method_evidence_binding_validate <- function(envelope) {
  .brohn_meb_domain(envelope)
  x<-envelope
  .brohn_meb_fields(x,c("schema","registry_capture","implementation_ref","captured_at","context","tasks","coverage","inherited_references"),"Study method evidence")
  .brohn_meb_need(identical(x$schema,"brohn-study-method-evidence/0.1"),"Unsupported study method evidence schema.")
  .brohn_meb_implementation(x$implementation_ref)
  .brohn_meb_need(.brohn_me_text(x$captured_at,40L)&&grepl("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(\\.[0-9]{1,6})?Z$",x$captured_at),"Capture needs an explicit UTC timestamp.")
  instant<-strptime(x$captured_at,format="%Y-%m-%dT%H:%M:%OSZ",tz="UTC")
  .brohn_meb_need(!is.na(instant)&&identical(format(instant,"%Y-%m-%dT%H:%M:%S",tz="UTC"),substr(x$captured_at,1L,19L)),"Capture timestamp is not a valid UTC instant.")
  context<-brohn_method_evidence_untag(x$context);.brohn_meb_context(context)
  r<-.brohn_meb_registry(x$registry_capture)
  .brohn_meb_need(.brohn_me_array(x$tasks)&&length(x$tasks)<=200L,"Historical task bindings need a bounded array.")
  .brohn_meb_need(.brohn_me_array(x$inherited_references)&&length(x$inherited_references)==0L,"Inherited provenance is not admitted by this first pure binding slice.")
  seen<-character()
  for(t in x$tasks) {
    .brohn_meb_fields(t,c("task_id","method_ref","input_projection","input_hash","bindings","gaps"),"Captured task")
    .brohn_meb_need(.brohn_me_text(t$task_id,80L)&&!t$task_id%in%seen&&.brohn_me_text(t$method_ref,200L),"Captured task identity is missing or repeated.");seen<-c(seen,t$task_id)
    p<-brohn_method_evidence_untag(t$input_projection)
    .brohn_meb_fields(p,c("block","compiled_scoring","context"),"Captured input projection")
    .brohn_meb_need(typeof(p$block)=="list"&&identical(p$block$id,t$task_id)&&identical(p$block$profile,t$method_ref),"Captured task identity differs from its projection.")
    .brohn_meb_need(.brohn_meb_equal(context,p$context)&&identical(t$input_hash,brohn_method_evidence_projection_hash(t$input_projection)),"Captured input/context hash mismatch.")
    .brohn_meb_scoring_shape_0_1(t$method_ref,p$compiled_scoring)
    expected<-.brohn_meb_decisions_0_1(p,r$registry)
    .brohn_meb_need(.brohn_meb_equal(t$bindings,expected$bindings)&&.brohn_meb_equal(t$gaps,expected$gaps),"Bindings/gaps do not match original captured inputs and claim targets.")
  }
  expected_capture<-.brohn_meb_capture(x$registry_capture,x$tasks)
  .brohn_meb_need(.brohn_meb_equal(expected_capture,x$registry_capture),"Registry capture selection differs from the successful bound claims.")
  .brohn_meb_need(.brohn_meb_equal(x$coverage,.brohn_meb_coverage_0_1(x$tasks)),"Coverage does not match actual task bindings.")
  .brohn_meb_need(nchar(.brohn_meb_json(x),type="bytes")<=16L*1024L*1024L,"Evidence envelope exceeds the store body ceiling.")
  invisible(envelope)
}

# Enclosing source/domain validators must use this in addition to internal
# capsule integrity. No current compiler is involved in historical matching.
brohn_method_evidence_binding_matches <- function(envelope, blocks, context) {
  brohn_method_evidence_binding_validate(envelope)
  .brohn_meb_domain(blocks);.brohn_meb_domain(context);.brohn_meb_context(context)
  .brohn_meb_need(.brohn_me_array(blocks)&&length(blocks)==length(envelope$tasks),"Evidence task count differs from the enclosing source.")
  .brohn_meb_need(.brohn_meb_equal(context,brohn_method_evidence_untag(envelope$context)),"Evidence context differs from the enclosing source.")
  for(i in seq_along(blocks)) {
    p<-brohn_method_evidence_untag(envelope$tasks[[i]]$input_projection)
    .brohn_meb_need(.brohn_meb_equal(blocks[[i]],p$block),"Evidence task inputs/order differ from the enclosing source.")
  }
  invisible(TRUE)
}

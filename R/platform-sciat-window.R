# Original, isolated Brohn response-window SC-IAT core. Registration is separate.
brohn_sciat_window_profile <- function() list(
  id="sciat-brohn-response-window-im100/1.0",label="Brohn response-window SC-IAT",
  roles=as.list(c("target","attribute_positive","attribute_negative")),
  trial_counts=as.list(c(24L,72L,24L,72L)),keys=list(positive="KeyE",negative="KeyI"),
  quotas=list(A=list(practice=as.list(c(7L,7L,10L)),test=as.list(c(21L,21L,30L))),
    B=list(practice=as.list(c(7L,10L,7L)),test=as.list(c(21L,30L,21L)))),
  response_window_ms=1500L,response_feedback_ms=150L,omission_feedback_ms=500L,post_feedback_blank_ms=250L,
  response_policy="first_trusted_unmodified_nonheld_key; event_timestamp_inclusive_deadline",
  late_dispatch_policy="pending_omission_accepts_eligible_timestamp; after_seal_interrupts",
  sampling="park_miller_16807_fisher_yates/1.0; category_quota_shuffle; exemplar_cycles_reset_each_block",
  order="odd_allocation_A_then_B; even_allocation_B_then_A; positive_always_E",
  scoring_binding="sciat-response-window-im100/0.1-candidate",
  reference_commit="41b3812ab1d94f624113eb3e11028cf50fff6b2c",
  source="https://myscp.org/wp-content/uploads/2023/03/2007-proceedings.pdf#page=149",
  qualification="Named Brohn adaptation; no original-2006 or vendor equivalence; physical timing unqualified")

brohn_sciat_window_new <- function(title="Sample Brohn response-window SC-IAT",id=brohn_id("task")) {
  roles<-c("target","attribute_positive","attribute_negative")
  labels<-c("Fictional product","Pleasant","Unpleasant")
  text<-list(c("Fictional package","Fictional product display"),c("Joy","Pleasure"),c("Pain","Misery"))
  categories<-lapply(seq_along(roles),function(i)list(id=gsub("_","-",roles[i]),label=labels[i],role=roles[i]))
  materials<-unlist(lapply(seq_along(roles),function(i)lapply(seq_along(text[[i]]),function(j)
    list(id=paste0(categories[[i]]$id,"-item-",j),category_id=categories[[i]]$id,type="text",content=text[[i]][j],asset=NULL))),recursive=FALSE)
  list(schema_version="brohn-task-block/1.0",id=id,title=title,profile=brohn_sciat_window_profile()$id,
    seed=104729L,origin="synthetic",materials_rights="Original synthetic demonstration; replace with reviewed research materials.",
    categories=categories,materials=materials,settings=list(
      control_rationale="Declare the single target and attribute comparison; this does not create an experimental control product.",
      language="en",procedure=brohn_sciat_window_profile()))
}

brohn_sciat_window_validate <- function(block) {
  brohn_fields(block,c("schema_version","id","title","profile","seed","origin","materials_rights","categories","materials","settings"),label="SC-IAT block")
  brohn_require(identical(block$schema_version,"brohn-task-block/1.0")&&brohn_valid_id(block$id)&&nchar(block$id)<=70&&
    brohn_text(block$title,240)&&identical(block$profile,brohn_sciat_window_profile()$id),"Invalid SC-IAT block identity or named procedure.")
  brohn_require(brohn_number(block$seed,1,2147483646,TRUE)&&is.character(block$origin)&&length(block$origin)==1L&&
    block$origin %in% c("synthetic","researcher_supplied")&&brohn_text(block$materials_rights,4000),"Declare the seed, origin and material rights.")
  brohn_fields(block$settings,c("control_rationale","language","procedure"),label="SC-IAT settings")
  brohn_require(brohn_text(block$settings$control_rationale,4000)&&brohn_text(block$settings$language,80)&&
    identical(brohn_hash(block$settings$procedure),brohn_hash(brohn_sciat_window_profile())),"The named procedure is immutable; declare language and comparison rationale.")
  brohn_require(brohn_array(block$categories)&&length(block$categories)==3L&&brohn_array(block$materials)&&length(block$materials)<=400,
    "SC-IAT requires exactly three categories and bounded materials.")
  for(c in block$categories) {
    brohn_fields(c,c("id","label","role"),label="SC-IAT category")
    brohn_require(brohn_valid_id(c$id)&&brohn_text(c$label,240)&&brohn_text(c$role,80),"Invalid SC-IAT category.")
  }
  roles<-vapply(block$categories,`[[`,character(1),"role")
  brohn_require(setequal(roles,unlist(brohn_sciat_window_profile()$roles))&&!anyDuplicated(roles)&&!anyDuplicated(brohn_ids(block$categories)),
    "Use one target, one positive attribute and one negative attribute, without a dummy target.")
  for(m in block$materials) {
    brohn_fields(m,c("id","category_id","type","content","asset"),"image_alt","SC-IAT material")
    brohn_require(brohn_valid_id(m$id)&&brohn_text(m$category_id,96)&&m$category_id %in% brohn_ids(block$categories)&&
      is.character(m$type)&&length(m$type)==1L&&m$type %in% c("text","image")&&brohn_text(m$content,4000,m$type=="image"),"Invalid SC-IAT material.")
    if(m$type=="text")brohn_require(is.null(m$asset)&&is.null(m$image_alt),"Text material cannot hide image fields.") else {
      brohn_fields(m$asset,c("hash","size","media_type"),c("filename","width","height"),"SC-IAT asset")
      brohn_require(brohn_text(m$asset$hash,64)&&grepl("^[a-f0-9]{64}$",m$asset$hash)&&brohn_number(m$asset$size,1,20*1024^2,TRUE)&&
        brohn_text(m$asset$media_type,80)&&m$asset$media_type %in% c("image/png","image/jpeg","image/webp")&&brohn_text(m$image_alt,2000),
        "Images need immutable asset identity and reviewed alternative text.")
    }
  }
  brohn_require(!anyDuplicated(brohn_ids(block$materials)),"SC-IAT materials need unique identities.")
  for(c in block$categories)brohn_require(sum(vapply(block$materials,function(m)identical(m$category_id,c$id),logical(1)))>=2,
    "Supply at least two reviewed exemplars per category; this operational minimum does not establish stimulus validity.")
  invisible(block)
}

brohn_sciat_window_compile <- function(block,allocation_index=1L) {
  brohn_sciat_window_validate(block)
  brohn_require(brohn_number(allocation_index,1,1e9,TRUE),"SC-IAT allocation must be a positive whole number.")
  profile<-brohn_sciat_window_profile();phash<-brohn_hash(profile)
  # Products are exact integers below 2^53, with no dependency on R's RNG state.
  rng<-((block$seed+allocation_index-2)%%2147483646)+1
  shuffle<-function(x){if(length(x)>1L)for(i in length(x):2L){rng<<-(rng*16807)%%2147483647;j<-floor(rng/2147483647*i)+1L;v<-x[i];x[i]<-x[j];x[j]<-v};x}
  categories<-lapply(unlist(profile$roles),function(r)Filter(function(c)c$role==r,block$categories)[[1L]])
  names(categories)<-unlist(profile$roles);pool<-lapply(categories,function(c)Filter(function(m)m$category_id==c$id,block$materials))
  maps<-rep(if(allocation_index%%2L==1L)c("A","B")else c("B","A"),each=2L)
  blocks<-timeline<-list()
  for(b in 1:4) {
    phase<-if(b%%2L==1L)"practice"else"test";mapping<-maps[b];quota<-unlist(profile$quotas[[mapping]][[phase]])
    roles<-shuffle(rep(unlist(profile$roles),quota));remaining<-setNames(rep(list(integer()),3L),unlist(profile$roles))
    block_id<-paste0(block$id,"-b",b);trial_ids<-paste0(block_id,"-t",seq_along(roles))
    label<-function(side)paste(vapply(Filter(function(c)if(c$role=="target")side==if(mapping=="A")"KeyE"else"KeyI"else side==if(c$role=="attribute_positive")"KeyE"else"KeyI",categories),`[[`,character(1),"label"),collapse=" or ")
    left<-label("KeyE");right<-label("KeyI")
    timeline[[length(timeline)+1L]]<-list(id=paste0(block_id,"-instructions"),type="task_instructions",task_id=block$id,
      task_profile=profile$id,block_id=block_id,block_index=b,phase="instructions",mapping=mapping,
      text=paste(if(phase=="practice")"Practice."else"Test.","Use E for",left,"and I for",right,
        ". Respond quickly and accurately within 1.5 seconds. Your first key is final; do not correct an error. Release each key between responses."))
    for(i in seq_along(roles)) {
      r<-roles[i];if(!length(remaining[[r]]))remaining[[r]]<-shuffle(seq_along(pool[[r]]))
      selected<-remaining[[r]][1L];remaining[[r]]<-remaining[[r]][-1L];m<-pool[[r]][[selected]]
      correct<-if(r=="target")if(mapping=="A")"KeyE"else"KeyI"else if(r=="attribute_positive")"KeyE"else"KeyI"
      timeline[[length(timeline)+1L]]<-list(id=trial_ids[i],type="task_trial",task_id=block$id,task_profile=profile$id,
        procedure_hash=phash,block_id=block_id,block_index=b,trial_index=i,phase=phase,mode="sciat_window",mapping=mapping,
        scored=phase=="test",category_id=categories[[r]]$id,category_role=r,material=m,
        correct_code=correct,allowed_codes=as.list(c("KeyE","KeyI")),left_label=left,right_label=right,
        forced_correction=FALSE,timeout_ms=1500L,response_feedback_ms=150L,omission_feedback_ms=500L,post_feedback_blank_ms=250L)
    }
    blocks[[b]]<-list(id=block_id,index=b,mapping=mapping,phase=phase,trial_count=length(roles),
      category_quotas=setNames(as.list(quota),unlist(profile$roles)),trial_ids=as.list(trial_ids))
  }
  list(schema_version="brohn-compiled-task/1.0",id=block$id,profile=profile$id,title=block$title,origin=block$origin,
    design_hash=brohn_hash(block),procedure=profile,procedure_hash=phash,allocation_index=allocation_index,seed=block$seed,
    assignment=list(initial_mapping=maps[1L],positive_attribute_key="KeyE",negative_attribute_key="KeyI"),
    categories=block$categories,blocks=blocks,timeline=timeline,sequence_hash=brohn_hash(timeline),source_block=block,
    provenance=list(materials_rights=block$materials_rights,control_rationale=block$settings$control_rationale,language=block$settings$language))
}

brohn_sciat_window_validate_compiled <- function(compiled) {
  brohn_require(is.list(compiled)&&identical(compiled$profile,brohn_sciat_window_profile()$id),"Unsupported SC-IAT compiled profile.")
  expected<-brohn_sciat_window_compile(compiled$source_block,compiled$allocation_index)
  brohn_require(identical(brohn_hash(compiled),brohn_hash(expected)),"Frozen SC-IAT sequence differs from its source, allocation or named procedure.")
  invisible(compiled)
}

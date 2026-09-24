# Original isolated GNAT domain, reducer and evidence replay. Registration is separate.
brohn_gnat_profile <- function() list(
  id="gnat-brohn-single-target/1.0",label="Brohn single-target GNAT",
  roles=as.list(c("target","context","attribute_positive","attribute_negative")),
  context_kinds=as.list(c("generic","single_category","superordinate")),stimulus_mode="text",go_code="Space",
  training_blocks=4L,training_trials_per_block=20L,training_go_no_go_counts=list(10L,10L),
  training_signal_noise_deadline_ms=list(1000L,1000L),
  round_signal_noise_deadlines_ms=list(list(750L,750L),list(600L,600L)),
  pairings_per_round=list("target_positive","target_negative"),
  pairing_practice_role_counts=list(4L,4L,4L,4L),pairing_test_role_counts=list(15L,15L,15L,15L),
  practice_policy="one_pass_no_threshold_no_repeat",response_interval="onset_inclusive_deadline_exclusive",
  stimulus_offset="first_eligible_space_or_deadline",feedback_ms=100L,offset_to_next_onset_min_ms=500L,
  require_space_release=TRUE,late_dispatch_after_seal="interrupt_preserve_evidence",timed_restart="forbidden",
  scoring_binding="brohn-gnat-single-target-score/1.0",arithmetic_rule="gnat-brohn-endpoint005/1.0",endpoint_rates=list(.005,.995),interior_rate_adjustment="none",
  cell_required_test_signal_noise=list(30L,30L),nonpositive_sensitivity="retain_with_support_flag",
  contrast="target_positive_minus_target_negative_within_round",pool_deadlines=FALSE,additional_rt_trimming="none",
  sampling="park_miller16807_fisher_yates; training_then_round_draws; phase_quota_then_used_role_decks; reset_each_phase/1.0",
  text_comparison="unicode_white_space_explicit_codepoints; ascii_case_fold; no_unicode_normalization/1.0",
  source="https://banaji.sites.fas.harvard.edu/research/publications/articles/2001_Nosek_SC.pdf",
  qualification="Named Brohn adaptation; no historical/vendor equivalence or physical timing, material or population reliability claim")

.brohn_gnat_text_key <- function(text) {
  brohn_require(brohn_text(text,4000),"GNAT material text is empty or too large.")
  cp<-utf8ToInt(enc2utf8(text));brohn_require(!anyNA(cp),"GNAT text must be valid Unicode.")
  white<-c(9:13,32,133,160,5760,8192:8202,8232,8233,8239,8287,12288)
  cp[cp %in% white]<-32L;upper<-cp>=65&cp<=90;cp[upper]<-cp[upper]+32L
  cp<-cp[c(TRUE,diff(cp)!=0L)|cp!=32L]
  while(length(cp)&&cp[1L]==32L)cp<-cp[-1L]
  while(length(cp)&&cp[length(cp)]==32L)cp<-cp[-length(cp)]
  intToUtf8(cp)
}

brohn_gnat_new <- function(title="Sample Brohn single-target GNAT",id=brohn_id("task")) {
  roles<-unlist(brohn_gnat_profile()$roles);labels<-c("Writing tools","Other things","Pleasant","Unpleasant")
  words<-list(c("Pencil","Marker","Fountain pen","Chalk"),c("Ladder","Blanket","Scooter","Pebble"),
    c("Pleasant","Joyful","Superb","Kind"),c("Awful","Cruel","Grim","Nasty"))
  categories<-lapply(seq_along(roles),function(i)list(id=gsub("_","-",roles[i]),label=labels[i],role=roles[i]))
  materials<-unlist(lapply(seq_along(roles),function(i)lapply(seq_along(words[[i]]),function(j)
    list(id=paste0(categories[[i]]$id,"-item-",j),category_id=categories[[i]]$id,type="text",content=words[[i]][j],asset=NULL))),recursive=FALSE)
  list(schema_version="brohn-task-block/1.0",id=id,title=title,profile=brohn_gnat_profile()$id,seed=104729L,
    origin="synthetic",materials_rights="Original software demonstration; replace with reviewed research materials.",
    categories=categories,materials=materials,settings=list(context_kind="generic",
      context_rationale="Authored unrelated objects for software rehearsal; not a validated neutral context.",
      control_rationale="One target is classified with positive and negative attributes against the declared context.",
      language="en",procedure=brohn_gnat_profile()))
}

brohn_gnat_validate <- function(block) {
  brohn_fields(block,c("schema_version","id","title","profile","seed","origin","materials_rights","categories","materials","settings"),label="GNAT block")
  brohn_require(identical(block$schema_version,"brohn-task-block/1.0")&&brohn_valid_id(block$id)&&nchar(block$id)<=70&&
    brohn_text(block$title,240)&&identical(block$profile,brohn_gnat_profile()$id),"Invalid GNAT block or procedure identity.")
  brohn_require(brohn_number(block$seed,1,2147483646,TRUE)&&brohn_text(block$origin,40)&&block$origin %in% c("synthetic","researcher_supplied")&&
    brohn_text(block$materials_rights,4000),"Declare GNAT seed, material origin and rights.")
  brohn_fields(block$settings,c("context_kind","context_rationale","control_rationale","language","procedure"),label="GNAT settings")
  brohn_require(brohn_text(block$settings$context_kind,40)&&block$settings$context_kind %in% unlist(brohn_gnat_profile()$context_kinds)&&
    brohn_text(block$settings$context_rationale,4000)&&brohn_text(block$settings$control_rationale,4000)&&brohn_text(block$settings$language,80)&&
    identical(brohn_hash(block$settings$procedure),brohn_hash(brohn_gnat_profile())),"Declare context/language; the named GNAT procedure is immutable.")
  brohn_require(brohn_array(block$categories)&&length(block$categories)==4L&&brohn_array(block$materials)&&length(block$materials)<=256L,
    "GNAT requires four roles and at most 64 materials per role.")
  for(c in block$categories) {
    brohn_fields(c,c("id","label","role"),label="GNAT category")
    brohn_require(brohn_valid_id(c$id)&&brohn_text(c$label,240)&&brohn_text(c$role,80),"Invalid GNAT category.")
  }
  roles<-vapply(block$categories,`[[`,character(1),"role")
  brohn_require(setequal(roles,unlist(brohn_gnat_profile()$roles))&&!anyDuplicated(roles)&&!anyDuplicated(brohn_ids(block$categories)),
    "GNAT needs one target, context, positive and negative role.")
  for(m in block$materials) {
    brohn_fields(m,c("id","category_id","type","content","asset"),label="GNAT material")
    brohn_require(brohn_valid_id(m$id)&&brohn_text(m$category_id,96)&&m$category_id %in% brohn_ids(block$categories)&&
      identical(m$type,"text")&&is.null(m$asset)&&brohn_text(m$content,4000)&&nzchar(.brohn_gnat_text_key(m$content)),
      "GNAT 1.0 uses nonempty text with explicit category identity, without image assets.")
  }
  brohn_require(!anyDuplicated(brohn_ids(block$materials))&&!anyDuplicated(vapply(block$materials,function(m).brohn_gnat_text_key(m$content),character(1))),
    "GNAT material identifiers and normalized texts must be unique within and across roles.")
  for(c in block$categories) {
    n<-sum(vapply(block$materials,function(m)identical(m$category_id,c$id),logical(1)))
    brohn_require(n>=2L&&n<=64L,"Supply 2 to 64 reviewed exemplars per role; this operational bound does not establish validity.")
  }
  invisible(block)
}

brohn_gnat_compile <- function(block,allocation_index=1L) {
  brohn_gnat_validate(block);brohn_require(brohn_number(allocation_index,1,1e9,TRUE),"GNAT allocation must be a positive whole number.")
  profile<-brohn_gnat_profile();phash<-brohn_hash(profile);roles<-unlist(profile$roles)
  rng<-((block$seed+allocation_index-2)%%2147483646)+1
  draw<-function(){rng<<-(rng*16807)%%2147483647;rng/2147483647}
  shuffle<-function(x){if(length(x)>1L)for(i in length(x):2L){j<-floor(draw()*i)+1L;v<-x[i];x[i]<-x[j];x[j]<-v};x}
  training_order<-shuffle(roles);round_order<-lapply(1:2,function(i)if(draw()<.5)c("target_positive","target_negative")else c("target_negative","target_positive"))
  categories<-setNames(lapply(roles,function(r)Filter(function(c)c$role==r,block$categories)[[1L]]),roles)
  pool<-lapply(categories,function(c)Filter(function(m)m$category_id==c$id,block$materials))
  phases<-lapply(training_order,function(r) {
    opposite<-c(target="context",context="target",attribute_positive="attribute_negative",attribute_negative="attribute_positive")[[r]]
    list(phase="training",round_id=NULL,cell_id=NULL,pairing=NULL,training_go_role=r,go_roles=r,
      quotas=setNames(ifelse(roles %in% c(r,opposite),10L,0L),roles),timeout_ms=1000L)
  })
  for(round in 1:2)for(pair in round_order[[round]])for(phase in c("practice","test")) {
    phases[[length(phases)+1L]]<-list(phase=phase,round_id=paste0("r",round),cell_id=paste0("r",round,"-",if(pair=="target_positive")"positive"else"negative"),
      pairing=pair,training_go_role=NULL,go_roles=c("target",if(pair=="target_positive")"attribute_positive"else"attribute_negative"),
      quotas=setNames(rep(if(phase=="practice")4L else 15L,4),roles),timeout_ms=if(round==1L)750L else 600L)
  }
  blocks<-timeline<-list()
  for(b in seq_along(phases)) {
    p<-phases[[b]];ordered_roles<-shuffle(rep(roles,p$quotas));decks<-setNames(rep(list(integer()),4),roles)
    for(r in roles[p$quotas>0])decks[[r]]<-shuffle(seq_along(pool[[r]]))
    block_id<-paste0(block$id,"-b",b);go_labels<-as.list(vapply(categories[p$go_roles],`[[`,character(1),"label"))
    header<-list(task_id=block$id,task_profile=profile$id,procedure_hash=phash,block_id=block_id,block_index=b,
      phase=p$phase,round_id=p$round_id,cell_id=p$cell_id,pairing=p$pairing,training_go_role=p$training_go_role)
    timeline[[length(timeline)+1L]]<-c(list(id=paste0(block_id,"-instructions"),type="task_instructions"),header,
      list(go_roles=as.list(p$go_roles),go_labels=unname(go_labels),text=paste(
        if(p$phase=="test")"Test."else"Practice.","Press Space for",paste(unlist(go_labels),collapse=" or "),
        ". Do nothing for other items. Respond quickly and accurately; release Space between items. Each first response is final.")))
    trial_ids<-paste0(block_id,"-t",seq_along(ordered_roles))
    for(i in seq_along(ordered_roles)) {
      r<-ordered_roles[i];if(!length(decks[[r]]))decks[[r]]<-shuffle(seq_along(pool[[r]]))
      selected<-decks[[r]][1L];decks[[r]]<-decks[[r]][-1L]
      timeline[[length(timeline)+1L]]<-c(list(id=trial_ids[i],type="task_trial"),header,
        list(trial_index=i,mode="gnat",scored=p$phase=="test",category_id=categories[[r]]$id,category_role=r,material=pool[[r]][[selected]],
          expected_action=if(r %in% p$go_roles)"go"else"nogo",allowed_codes=list("Space"),go_roles=as.list(p$go_roles),go_labels=unname(go_labels),
          forced_correction=FALSE,timeout_ms=p$timeout_ms,feedback_ms=100L,offset_to_next_onset_min_ms=500L))
    }
    blocks[[b]]<-c(list(id=block_id,index=b),p[c("phase","round_id","cell_id","pairing","training_go_role")],
      list(trial_count=length(ordered_roles),category_quotas=as.list(p$quotas),go_roles=as.list(p$go_roles),timeout_ms=p$timeout_ms,trial_ids=as.list(trial_ids)))
  }
  list(schema_version="brohn-compiled-task/1.0",id=block$id,profile=profile$id,title=block$title,origin=block$origin,
    design_hash=brohn_hash(block),procedure=profile,procedure_hash=phash,allocation_index=allocation_index,seed=block$seed,
    assignment=list(training_order=unname(as.list(training_order)),round_pairing_order=lapply(round_order,as.list)),
    categories=block$categories,blocks=blocks,timeline=timeline,sequence_hash=brohn_hash(timeline),source_block=block,
    provenance=list(materials_rights=block$materials_rights,context_kind=block$settings$context_kind,context_rationale=block$settings$context_rationale,
      control_rationale=block$settings$control_rationale,language=block$settings$language))
}

brohn_gnat_validate_compiled <- function(compiled) {
  brohn_require(is.list(compiled)&&identical(compiled$profile,brohn_gnat_profile()$id),"Unsupported compiled GNAT profile.")
  expected<-brohn_gnat_compile(compiled$source_block,compiled$allocation_index)
  brohn_require(identical(brohn_hash(compiled),brohn_hash(expected)),"Frozen GNAT sequence differs from its source, allocation or named procedure.")
  invisible(compiled)
}

.brohn_gnat_rates <- function(hits,misses,false_alarms,correct_rejections) {
  counts<-list(hits=hits,misses=misses,false_alarms=false_alarms,correct_rejections=correct_rejections)
  brohn_require(all(vapply(counts,brohn_number,logical(1),min=0,max=1e7,integer=TRUE)),"GNAT outcome counts must be finite nonnegative whole numbers.")
  signal<-hits+misses;noise<-false_alarms+correct_rejections
  result<-c(counts,list(signal=signal,noise=noise,status="unavailable",reason="Both signal and noise observations are required.",
    raw_rates=list(hit=NULL,false_alarm=NULL),corrected_rates=list(hit=NULL,false_alarm=NULL),
    endpoint_adjustments=list(hit=FALSE,false_alarm=FALSE),d_prime=NULL,criterion=NULL))
  if(!signal||!noise)return(result)
  h<-hits/signal;f<-false_alarms/noise;correct<-function(p)if(p==0).005 else if(p==1).995 else p
  hc<-correct(h);fc<-correct(f)
  result$status<-"available";result["reason"]<-list(NULL);result$raw_rates<-list(hit=h,false_alarm=f);result$corrected_rates<-list(hit=hc,false_alarm=fc)
  result$endpoint_adjustments<-list(hit=h!=hc,false_alarm=f!=fc)
  result
}

brohn_gnat_sensitivity <- function(hits,misses,false_alarms,correct_rejections) {
  result<-.brohn_gnat_rates(hits,misses,false_alarms,correct_rejections)
  if(result$status=="available") {
    h<-qnorm(result$corrected_rates$hit);f<-qnorm(result$corrected_rates$false_alarm)
    result$d_prime<-h-f;result$criterion<--.5*(h+f)
  }
  result
}

.brohn_gnat_bool <- function(x)is.logical(x)&&length(x)==1L&&!is.na(x)
.brohn_gnat_same <- function(a,b)if(is.null(a)||is.null(b))is.null(a)&&is.null(b)else
  brohn_number(a)&&brohn_number(b)&&a==b
# Native page timestamps and their derived arithmetic are serialized to six
# decimal milliseconds. Normalize derived operands only; never widen the raw
# half-open event window or round an early observed duration into compliance.
.brohn_gnat_ms <- function(value) round(value,6L)
.brohn_gnat_outcome <- function(action,responded)if(action=="go")if(responded)"hit"else"miss"else if(responded)"false_alarm"else"correct_rejection"
.brohn_gnat_rt <- function(rows,outcome) {
  values<-vapply(Filter(function(r)identical(r$outcome,outcome),rows),function(r)r$response_ms,numeric(1))
  list(n=length(values),mean_ms=if(length(values))mean(values)else NULL,median_ms=if(length(values))median(values)else NULL,
    sd_ms=if(length(values)>1L)sd(values)else NULL)
}

brohn_gnat_score <- function(compiled,responses,completed=TRUE,timing_known=TRUE) {
  brohn_gnat_validate_compiled(compiled);brohn_require(brohn_array(responses)&&.brohn_gnat_bool(completed)&&.brohn_gnat_bool(timing_known),
    "GNAT scoring requires explicit response records, completion status and timing-definition status.")
  trials<-Filter(function(t)t$type=="task_trial",compiled$timeline);ids<-brohn_ids(trials)
  received<-vapply(responses,function(r)brohn_default(r$trial_id,""),character(1))
  brohn_require(!anyDuplicated(received)&&all(received %in% ids),"GNAT records contain unknown or duplicate trials.")
  rows<-lapply(seq_along(responses),function(i) {
    r<-responses[[i]];t<-trials[[match(received[i],ids)]]
    brohn_require(all(c("trial_id","outcome","response_outcome","response_code","response_ms","correct") %in% names(r))&&
      brohn_text(r$outcome,40)&&r$outcome %in% c("hit","miss","false_alarm","correct_rejection","interrupted"),"Keep explicit GNAT outcome, key, latency and accuracy cells.")
    responded<-!is.null(r$response_code)
    if(responded) {
      brohn_require(identical(r$response_code,"Space")&&brohn_number(r$response_ms,0,1e12),"GNAT reported responses need Space and a finite nonnegative millisecond value.")
      if(timing_known)brohn_require(r$response_ms<t$timeout_ms,"GNAT responses must be Space strictly before the frozen deadline.")
    }else brohn_require(is.null(r$response_ms),"Withholding cannot contain a fabricated response latency.")
    if(r$outcome=="interrupted") {
      brohn_require(is.null(r$correct)&&(is.null(r$response_outcome)||identical(r$response_outcome,.brohn_gnat_outcome(t$expected_action,responded))),"An interrupted trial retains no qualified accuracy.")
    }else {
      expected<-.brohn_gnat_outcome(t$expected_action,responded)
      brohn_require(identical(r$outcome,expected)&&identical(r$response_outcome,expected)&&identical(r$correct,expected %in% c("hit","correct_rejection")),
        "GNAT outcome or accuracy differs from the frozen expected action and explicit response.")
    }
    c(list(trial_id=t$id,block_id=t$block_id,phase=t$phase,round_id=t$round_id,cell_id=t$cell_id,category_role=t$category_role,expected_action=t$expected_action),
      r[c("outcome","response_outcome","response_code","response_ms","correct")])
  })
  complete<-timing_known&&completed&&setequal(ids,received)&&!any(vapply(rows,function(r)r$outcome=="interrupted",logical(1)))
  result<-list(schema_version="brohn-task-score/1.0",task_id=compiled$id,profile=compiled$profile,origin=compiled$origin,design_hash=compiled$design_hash,
    scoring_recipe="brohn-gnat-single-target-score/1.0",procedure_hash=compiled$procedure_hash,sequence_hash=compiled$sequence_hash,
    status=if(complete)"computed"else"unavailable",eligible=complete,metrics=list(),
    counts=list(expected=384L,received=length(received),expected_training=80L,expected_practice=64L,expected_test=240L,
      training=sum(vapply(rows,function(r)r$phase=="training",logical(1))),practice=sum(vapply(rows,function(r)r$phase=="practice",logical(1))),
      test=sum(vapply(rows,function(r)r$phase=="test",logical(1))),interrupted=sum(vapply(rows,function(r)r$outcome=="interrupted",logical(1)))),
    reason=if(!timing_known)"The declared response-time or terminal-response definition is unknown; GNAT scoring is unavailable."else
      if(complete)NULL else"Complete uninterrupted evidence for all 384 assigned trials is required.",limitations=as.list(c(
      "Named Brohn single-target adaptation; not original or vendor GNAT equivalence.",
      "Context-dependent discrimination contrast, without individual preference bands or diagnoses.",
      "Software arithmetic does not establish physical timing, stimulus validity or population reliability.")))
  cells<-list();rounds<-list();metrics<-list()
  for(round in 1:2)for(sign in c("positive","negative")) {
    id<-paste0("r",round,"-",sign);observed<-Filter(function(r)r$phase=="test"&&identical(r$cell_id,id),rows)
    valid<-Filter(function(r)r$outcome!="interrupted",observed);count<-function(k)sum(vapply(valid,function(r)r$outcome==k,logical(1)))
    rate_fn<-if(timing_known)brohn_gnat_sensitivity else .brohn_gnat_rates
    arithmetic<-rate_fn(count("hit"),count("miss"),count("false_alarm"),count("correct_rejection"))
    cell_complete<-length(valid)==60L&&arithmetic$signal==30L&&arithmetic$noise==30L
    cell<-c(list(id=id,round_id=paste0("r",round),pairing=paste0("target_",sign),deadline_ms=if(round==1L)750L else 600L,
      status=if(cell_complete&&timing_known)"available"else"unavailable",reason=if(!timing_known)"Declared timing definition is unknown; sensitivity and criterion are unavailable."else
        if(cell_complete)NULL else"All 30 signal and 30 noise test trials are required.",
      expected_signal=30L,expected_noise=30L,received_test=length(observed)),arithmetic[c("hits","misses","false_alarms","correct_rejections","raw_rates","corrected_rates","endpoint_adjustments")],
      list(d_prime=if(cell_complete&&timing_known)arithmetic$d_prime else NULL,criterion=if(cell_complete&&timing_known)arithmetic$criterion else NULL,
        response_rt=list(hit=.brohn_gnat_rt(valid,"hit"),false_alarm=.brohn_gnat_rt(valid,"false_alarm")),flags=list()))
    if(!cell_complete)cell$flags<-c(cell$flags,list("incomplete_cell"))
    if(!timing_known)cell$flags<-c(cell$flags,list("declared_timing_unknown"))
    if(any(unlist(arithmetic$endpoint_adjustments)))cell$flags<-c(cell$flags,list("endpoint_rate_correction"))
    if(cell_complete&&timing_known&&arithmetic$d_prime<=0)cell$flags<-c(cell$flags,list("little_or_reversed_discrimination"))
    if(length(valid)&&count("hit")+count("false_alarm")==length(valid))cell$flags<-c(cell$flags,list("all_go"))
    if(length(valid)&&count("miss")+count("correct_rejection")==length(valid))cell$flags<-c(cell$flags,list("all_no_go"))
    cells[[length(cells)+1L]]<-cell
    for(metric in c("d_prime","criterion"))metrics[[length(metrics)+1L]]<-list(name=paste0("GNAT_r",round,"_",sign,"_",metric),
      value=if(complete)cell[[metric]]else NULL,unit="dimensionless",direction=if(metric=="d_prime")"Higher means better signal/noise discrimination in this declared pairing."else"Positive means more conservative Go responding.",
      support=list(cell_id=id,deadline_ms=cell$deadline_ms,signal=arithmetic$signal,noise=arithmetic$noise,eligible=complete))
  }
  for(round in 1:2) {
    p<-cells[[(round-1L)*2L+1L]];n<-cells[[(round-1L)*2L+2L]];available<-p$status=="available"&&n$status=="available"
    contrast<-if(available)p$d_prime-n$d_prime else NULL
    rounds[[round]]<-list(id=paste0("r",round),deadline_ms=p$deadline_ms,pairing_order=compiled$assignment$round_pairing_order[[round]],
      positive_cell=p$id,negative_cell=n$id,contrast=contrast,status=if(available)"available_descriptive"else"unavailable")
    metrics[[length(metrics)+1L]]<-list(name=paste0("GNAT_r",round,"_target_positive_contrast"),value=if(complete)contrast else NULL,unit="dimensionless",
      direction="Target-positive minus target-negative sensitivity within this deadline and context.",support=list(deadline_ms=p$deadline_ms,test_trials=120L,eligible=complete))
  }
  result$metrics<-metrics
  context<-Filter(function(c)c$role=="context",compiled$categories)[[1L]]
  target<-Filter(function(c)c$role=="target",compiled$categories)[[1L]]
  result$scoring_audit<-list(schema="brohn-gnat-single-target-audit/1.0",endpoint_recipe="gnat-brohn-endpoint005/1.0",
    round_order=compiled$assignment$round_pairing_order,training_order=compiled$assignment$training_order,timing_known=timing_known,
    target=list(id=target$id,label=target$label),
    context=list(kind=compiled$provenance$context_kind,rationale=compiled$provenance$context_rationale,label=context$label),
    cells=cells,rounds=rounds,rows=rows)
  result
}

.brohn_gnat_require <- function(ok,message) {
  if(exists(".brohn_delivery_require",mode="function")) .brohn_delivery_require(ok,message,422L,"invalid_gnat_evidence")else brohn_require(ok,message)
}
.brohn_gnat_clock <- function(clock,instance=NULL,origin=NULL) {
  brohn_fields(clock,c("id","unit","value","instance_id","time_origin_ms"),label="GNAT clock")
  .brohn_gnat_require(identical(clock$id,"browser-monotonic")&&identical(clock$unit,"ms")&&
    brohn_text(clock$value,64)&&grepl("^[0-9]+([.][0-9]+)?$",clock$value)&&
    brohn_text(clock$time_origin_ms,64)&&grepl("^[0-9]+([.][0-9]+)?$",clock$time_origin_ms)&&
    brohn_text(clock$instance_id,128)&&brohn_number(as.numeric(clock$value),0,1e12),"GNAT needs a decimal page-monotonic clock and origin.")
  .brohn_gnat_require((is.null(instance)||identical(instance,clock$instance_id))&&(is.null(origin)||identical(origin,clock$time_origin_ms)),
    "GNAT cannot continue across a changed page clock.")
  as.numeric(clock$value)
}
.brohn_gnat_delivery_new <- function()list(cursor=1L,active=NULL,last_clock=NULL,clock_instance=NULL,clock_origin=NULL,
  boundary_time=NULL,last_trial_id=NULL,last_instruction_id=NULL,interrupted=FALSE,interruption=NULL,incomplete=FALSE,completed=list(),responses=list(),sealed=list())

.brohn_gnat_release_wait <- function(wait,onset,boundary,final_held=NULL,interrupted=FALSE) {
  require<-.brohn_gnat_require;bool<-.brohn_gnat_bool
  brohn_fields(wait,c("start_ms","end_ms","held_codes","keys","visibility"),label="GNAT pre-onset release wait")
  require(brohn_number(wait$start_ms,boundary,onset)&&.brohn_gnat_same(wait$end_ms,onset)&&brohn_array(wait$held_codes)&&
    length(wait$held_codes)<=128L&&!anyDuplicated(unlist(wait$held_codes))&&all(vapply(wait$held_codes,brohn_text,logical(1),max=64))&&
    brohn_array(wait$keys)&&length(wait$keys)<=5000L&&brohn_array(wait$visibility)&&length(wait$visibility)>=2L&&length(wait$visibility)<=1000L,
    "Keep the bounded pre-onset wait, initial held keys and visibility through the onset frame.")
  held<-unlist(wait$held_codes,use.names=FALSE);last_event<-NULL;last_observed<-wait$start_ms
  for(k in wait$keys) {
    brohn_fields(k,c("type","code","event_ms","observed_ms","repeat","trusted","modifiers"),label="GNAT release-wait key")
    require(brohn_text(k$type,8)&&k$type %in% c("down","up")&&brohn_text(k$code,64)&&brohn_number(k$event_ms,0,onset)&&
      brohn_number(k$observed_ms,last_observed,onset)&&k$event_ms<=k$observed_ms&&bool(k[["repeat"]])&&bool(k$trusted)&&bool(k$modifiers)&&
      (interrupted||is.null(last_event)||k$event_ms>=last_event),"GNAT release-wait key state or clock is invalid.")
    if(k$trusted) {
      if(!interrupted)require(!(k$code=="Space"&&!"Space" %in% held&&(k$type=="up"||k[["repeat"]])),"Impossible Space state during release wait prevents stimulus onset.")
      if(k$type=="up")held<-setdiff(held,k$code)else held<-union(held,k$code)
    }
    last_event<-k$event_ms;last_observed<-k$observed_ms
  }
  last_visibility<-wait$start_ms
  for(i in seq_along(wait$visibility)) {
    v<-wait$visibility[[i]];brohn_fields(v,c("observed_ms","visible","focused"),label="GNAT release-wait visibility")
    require(brohn_number(v$observed_ms,last_visibility,onset)&&bool(v$visible)&&bool(v$focused)&&
      (interrupted||(v$visible&&v$focused)),
      "Interrupted pre-onset visibility cannot be presented as a completed release wait.")
    if(i==1L)require(.brohn_gnat_same(v$observed_ms,wait$start_ms),"Release-wait visibility must begin at its actual start.")
    last_visibility<-v$observed_ms
  }
  require(.brohn_gnat_same(last_visibility,onset)&&(interrupted||(!"Space" %in% held&&setequal(held,unlist(final_held,use.names=FALSE)))),
    "The onset held-key snapshot differs from the completed observed release wait.")
  invisible(TRUE)
}

.brohn_gnat_contradiction <- function(contradiction,sealed,now) {
  require<-.brohn_gnat_require
  brohn_fields(contradiction,c("trial_id","key"),label="GNAT sealed-trial contradiction")
  previous<-Filter(function(x)identical(x$trial_id,contradiction$trial_id),sealed)
  require(length(previous)==1L,"A late-key contradiction must name one previously sealed trial.")
  p<-previous[[1L]];k<-contradiction$key
  require(p$outcome %in% c("hit","miss","false_alarm","correct_rejection")&&!is.null(p$response_closed_ms),"Only a completed sealed trial can have this late-key contradiction.")
  brohn_fields(k,c("type","code","event_ms","observed_ms","repeat","trusted","modifiers","response_open","accepted","ignored_reason"),label="GNAT contradictory key")
  require(identical(k$type,"down")&&identical(k$code,"Space")&&identical(k$trusted,TRUE)&&identical(k[["repeat"]],FALSE)&&
    identical(k$modifiers,FALSE)&&identical(k$response_open,FALSE)&&identical(k$accepted,FALSE)&&identical(k$ignored_reason,"eligible_key_after_seal")&&
    brohn_number(k$event_ms,p$onset_ms,p$deadline_ms)&&k$event_ms<p$deadline_ms&&brohn_number(k$observed_ms,p$finished_ms,now)&&
    k$event_ms<=k$observed_ms&&(is.null(p$first_event_ms)||k$event_ms<p$first_event_ms),
    "The retained late key does not contradict the previously sealed withholding or first response.")
  invisible(TRUE)
}

.brohn_gnat_trial_replay <- function(data,onset,trial,observed) {
  require<-.brohn_gnat_require;same<-.brohn_gnat_same;bool<-.brohn_gnat_bool
  brohn_fields(data,c("task_id","trial_id","block_id","procedure_hash","clock","outcome","response_outcome","response_code","response_ms","correct",
    "onset_ms","deadline_ms","deadline_timer_ms","deadline_frame_ms","response_closed_ms","feedback_start_ms","feedback_end_ms","blank_end_ms",
    "keys","visibility","interruption_reason","frame_count","max_frame_gap_ms"),label="GNAT trial result")
  require(same(data$onset_ms,onset$time)&&same(data$deadline_ms,.brohn_gnat_ms(onset$time+trial$timeout_ms))&&brohn_text(data$outcome,40)&&
    data$outcome %in% c("hit","miss","false_alarm","correct_rejection","interrupted")&&brohn_array(data$keys)&&length(data$keys)<=5000L&&
    brohn_array(data$visibility)&&length(data$visibility)>=1L&&length(data$visibility)<=1000L&&
    brohn_number(data$frame_count,1,1e8,TRUE)&&brohn_number(data$max_frame_gap_ms,0,3600000),"GNAT outcome, timing or bounded observations are invalid.")
  closed<-data$response_closed_ms;timer<-data$deadline_timer_ms;settled<-data$deadline_frame_ms
  require(is.null(closed)||brohn_number(closed,onset$time,observed),"GNAT response window closed outside its observation interval.")
  require(is.null(timer)||brohn_number(timer,data$deadline_ms,observed),"The deadline timer cannot precede the deadline.")
  require(is.null(settled)||(!is.null(timer)&&brohn_number(settled,timer,observed)),"The deadline animation frame needs the observed timer first.")
  held<-unlist(onset$held,use.names=FALSE);first<-NULL;last_event<-NULL;last_observed<-onset$time;conflict<-FALSE
  for(k in data$keys) {
    brohn_fields(k,c("type","code","event_ms","observed_ms","repeat","trusted","modifiers","response_open","accepted","ignored_reason"),label="GNAT key observation")
    require(brohn_text(k$type,8)&&k$type %in% c("down","up")&&brohn_text(k$code,64)&&
      brohn_number(k$event_ms,0,observed)&&brohn_number(k$observed_ms,last_observed,observed)&&k$event_ms<=k$observed_ms&&
      bool(k[["repeat"]])&&bool(k$trusted)&&bool(k$modifiers)&&bool(k$response_open)&&bool(k$accepted),"GNAT key type, times or literal flags are invalid.")
    require(if(k$response_open)is.null(closed)||k$observed_ms<=closed else !is.null(closed)&&k$observed_ms>=closed,
      "GNAT key observation contradicts response-window closure.")
    reversed<-!is.null(last_event)&&k$event_ms<last_event;last_event<-k$event_ms;last_observed<-k$observed_ms
    impossible_space<-k$trusted&&k$code=="Space"&&!"Space" %in% held&&(k$type=="up"||k[["repeat"]])
    reason<-if(!k$trusted)"synthetic_key_event"else if(k$modifiers)"modified_key"else if(reversed)"event_clock_reversed"else
      if(k$type=="up")"key_release"else if(k$code!="Space")"other_key"else if(k[["repeat"]])"key_repeat"else
        if(k$code %in% held)"key_held_from_previous_phase"else if(k$event_ms<onset$time)"anticipatory"else
          if(k$event_ms>=data$deadline_ms)"after_deadline"else if(!is.null(first))"after_first_response"else
            if(!k$response_open)"eligible_key_after_seal"else NULL
    require(identical(k$ignored_reason,reason)&&identical(k$accepted,is.null(reason)),"GNAT key classification differs from independent replay.")
    if(k$trusted){if(k$type=="up")held<-setdiff(held,k$code)else held<-union(held,k$code)}
    if(is.null(reason))first<-k
    if(impossible_space||(!is.null(reason)&&reason %in% c("event_clock_reversed","eligible_key_after_seal","anticipatory")))conflict<-TRUE
  }
  visibility_time<-onset$time;visible_bad<-FALSE
  for(i in seq_along(data$visibility)) {
    v<-data$visibility[[i]];brohn_fields(v,c("observed_ms","visible","focused"),label="GNAT visibility observation")
    require(brohn_number(v$observed_ms,visibility_time,observed)&&bool(v$visible)&&bool(v$focused),"GNAT visibility observation is invalid.")
    if(i==1L)require(same(v$observed_ms,onset$time)&&v$visible&&v$focused,"Visibility evidence must begin at the received visible, focused onset.")
    visibility_time<-v$observed_ms;if(!v$visible||!v$focused)visible_bad<-TRUE
  }
  provisional<-if(!is.null(first)) .brohn_gnat_outcome(trial$expected_action,TRUE)else if(!is.null(closed)).brohn_gnat_outcome(trial$expected_action,FALSE)else NULL
  require(identical(data$response_outcome,provisional)&&identical(data$response_code,if(is.null(first))NULL else "Space")&&
    same(data$response_ms,if(is.null(first))NULL else .brohn_gnat_ms(first$event_ms-onset$time)),"GNAT response summary differs from its observed eligible key or withholding.")
  if(!is.null(closed)) {
    if(is.null(first)) require(!is.null(timer)&&!is.null(settled)&&closed>=settled&&closed>=data$deadline_ms,
      "Withholding requires an actual timer, subsequent animation frame and complete deadline window.")else
      require(closed>=first$observed_ms,"A response cannot close before its eligible key was observed.")
  }
  feedback<-data$feedback_start_ms;end<-data$feedback_end_ms;blank<-data$blank_end_ms
  if(!is.null(feedback))require(!is.null(closed)&&same(feedback,closed),"GNAT feedback starts at the observed stimulus-removal transition.")
  if(!is.null(end))require(!is.null(feedback)&&brohn_number(end,.brohn_gnat_ms(feedback+100),observed),"GNAT feedback is shorter than 100 ms.")
  if(!is.null(blank))require(!is.null(end)&&brohn_number(blank,max(.brohn_gnat_ms(end+400),.brohn_gnat_ms(closed+500)),observed),"GNAT offset-to-onset interval or blank is incomplete.")
  if(data$outcome=="interrupted")require(brohn_text(data$interruption_reason,500)&&is.null(data$correct),"An interrupted GNAT trial needs its reason and null qualified accuracy.")else {
    require(!conflict&&!visible_bad&&!"Space" %in% held&&identical(data$outcome,provisional)&&!is.null(blank)&&
      visibility_time>=blank&&is.null(data$interruption_reason)&&identical(data$correct,provisional %in% c("hit","correct_rejection")),
      "Complete GNAT evidence needs uninterrupted visibility, correct key state, full feedback/blank and derived accuracy.")
  }
  list(trial_id=trial$id,block_id=trial$block_id,phase=trial$phase,round_id=trial$round_id,cell_id=trial$cell_id,
    expected_action=trial$expected_action,scored=trial$scored,outcome=data$outcome,response_outcome=data$response_outcome,
    response_code=data$response_code,response_ms=data$response_ms,correct=data$correct)
}

.brohn_gnat_delivery_apply <- function(state,event,step) {
  require<-.brohn_gnat_require;compiled<-step$task;t<-state$active$task
  require(!is.null(t)&&!t$interrupted&&identical(compiled$profile,brohn_gnat_profile()$id),"GNAT is absent or already interrupted.")
  brohn_fields(event$payload,c("kind","data"),c("clock_segment_id","time_origin_ms"),"GNAT task envelope")
  d<-event$payload$data;kind<-event$payload$kind
  require(brohn_text(kind,64)&&kind %in% c("task_instructions","task_trial_started","task_trial_finished","task_interrupted"),"Unsupported GNAT event.")
  require(is.list(d)&&identical(d$task_id,compiled$id)&&identical(d$procedure_hash,compiled$procedure_hash),"GNAT event belongs to another frozen procedure.")
  outer<-.brohn_gnat_clock(event$clock,state$active$instance);now<-.brohn_gnat_clock(d$clock,state$active$instance,event$clock$time_origin_ms)
  require(now>=state$active$time&&now<=outer&&(is.null(t$last_clock)||now>=t$last_clock)&&
    (is.null(t$clock_origin)||identical(t$clock_origin,d$clock$time_origin_ms)),"GNAT clock reversed or left its current step.")
  t$clock_instance<-d$clock$instance_id;t$clock_origin<-d$clock$time_origin_ms;t$last_clock<-now
  expected<-if(t$cursor<=length(compiled$timeline))compiled$timeline[[t$cursor]]else NULL
  if(kind=="task_interrupted") {
    brohn_fields(d,c("task_id","step_id","procedure_hash","reason","clock"),c("contradiction","release_wait"),label="GNAT interruption")
    if(!is.null(d$release_wait)) {
      require(is.null(t$active)&&!is.null(expected)&&expected$type=="task_trial","Interrupted release wait belongs before its pending trial, without an invented onset.")
      .brohn_gnat_release_wait(d$release_wait,now,brohn_default(t$boundary_time,state$active$time),interrupted=TRUE)
    }
    if(!is.null(d$contradiction)) {
      .brohn_gnat_contradiction(d$contradiction,t$sealed,now)
      require(identical(d$step_id,d$contradiction$trial_id)&&identical(d$reason,"eligible_key_after_seal"),"A retained contradiction must identify its actual sealed trial and cause.")
    }
    require(brohn_text(d$reason,500)&&((is.null(d$step_id)&&t$cursor==1L)||(!is.null(d$step_id)&&d$step_id %in% c(expected$id,t$last_trial_id,t$last_instruction_id,d$contradiction$trial_id))),
      "GNAT interruption must name its actual boundary.")
    t$interrupted<-TRUE;t$interruption<-list(reason=d$reason,step_id=d$step_id,clock=d$clock,contradiction=d$contradiction,release_wait=d$release_wait)
    state$active$task<-t;return(state)
  }
  require(!t$incomplete&&!is.null(expected),"GNAT is incomplete or already finished.")
  if(kind=="task_instructions") {
    brohn_fields(d,c("task_id","step_id","block_id","procedure_hash","clock"),label="GNAT instructions")
    require(is.null(t$active)&&expected$type=="task_instructions"&&identical(d$step_id,expected$id)&&identical(d$block_id,expected$block_id),"GNAT instructions are out of order.")
    t$last_instruction_id<-expected$id;t$boundary_time<-now;t$cursor<-t$cursor+1L;state$active$task<-t;return(state)
  }
  require(expected$type=="task_trial"&&identical(d$trial_id,expected$id)&&identical(d$block_id,expected$block_id),"GNAT trial identity or order differs from its frozen sequence.")
  if(kind=="task_trial_started") {
    brohn_fields(d,c("task_id","trial_id","block_id","procedure_hash","clock","held_codes","timing_reference","viewport","stimulus_rect","visible","focused","release_wait"),label="GNAT onset")
    require(is.null(t$active)&&now>=brohn_default(t$boundary_time,state$active$time)&&identical(d$timing_reference,"requestAnimationFrame_before_paint")&&
      brohn_array(d$held_codes)&&length(d$held_codes)<=128L&&!anyDuplicated(unlist(d$held_codes))&&
      all(vapply(d$held_codes,brohn_text,logical(1),max=64))&&!"Space" %in% unlist(d$held_codes)&&identical(d$visible,TRUE)&&identical(d$focused,TRUE),
      "GNAT onset needs a visible focused page and released Space key.")
    .brohn_gnat_release_wait(d$release_wait,now,brohn_default(t$boundary_time,state$active$time),d$held_codes)
    brohn_fields(d$viewport,c("width","height","device_pixel_ratio"),label="GNAT viewport")
    brohn_fields(d$stimulus_rect,c("x","y","width","height"),label="GNAT stimulus rectangle")
    require(brohn_number(d$viewport$width,1,100000)&&brohn_number(d$viewport$height,1,100000)&&brohn_number(d$viewport$device_pixel_ratio,.1,20)&&
      brohn_number(d$stimulus_rect$x,-100000,100000)&&brohn_number(d$stimulus_rect$y,-100000,100000)&&
      brohn_number(d$stimulus_rect$width,.001,100000)&&brohn_number(d$stimulus_rect$height,.001,100000),"GNAT onset geometry is invalid.")
    t$active<-list(id=expected$id,time=now,held=d$held_codes);state$active$task<-t;return(state)
  }
  require(!is.null(t$active),"GNAT completion requires a previously received onset.")
  record<-.brohn_gnat_trial_replay(d,t$active,expected,now)
  t$sealed[[length(t$sealed)+1L]]<-list(trial_id=expected$id,onset_ms=t$active$time,deadline_ms=d$deadline_ms,
    outcome=record$outcome,response_closed_ms=d$response_closed_ms,finished_ms=now,first_event_ms=if(is.null(d$response_ms))NULL else .brohn_gnat_ms(t$active$time+d$response_ms))
  t$responses[[length(t$responses)+1L]]<-record;t$completed[[length(t$completed)+1L]]<-expected$id
  t$last_trial_id<-expected$id;t$active<-NULL;t$cursor<-t$cursor+1L;t$boundary_time<-now;t$incomplete<-record$outcome=="interrupted"
  state$active$task<-t;state
}

.brohn_gnat_delivery_complete <- function(state,step,event) {
  t<-state$active$task
  .brohn_gnat_require(!is.null(t)&&!t$interrupted&&!t$incomplete&&is.null(t$active)&&t$cursor>length(step$task$timeline)&&
    length(t$responses)==384L&&identical(state$active$instance,event$clock$instance_id),"All 384 GNAT trials with their observed feedback and blank must be received before task completion.")
  invisible(TRUE)
}

brohn_gnat_replay <- function(compiled,events) {
  brohn_gnat_validate_compiled(compiled)
  brohn_require(brohn_array(events)&&length(events)>0L&&length(events)<=1000L,"Supply bounded received GNAT task events.")
  first<-events[[1L]];start<-.brohn_gnat_clock(first$payload$data$clock,first$clock$instance_id,first$clock$time_origin_ms)
  state<-list(active=list(time=start,instance=first$clock$instance_id,task=.brohn_gnat_delivery_new()))
  for(e in events) {
    brohn_require(identical(e$type,"task_event"),"Pure GNAT replay accepts nested events only; consent and session authority remain separate.")
    state<-.brohn_gnat_delivery_apply(state,e,list(task=compiled))
  }
  complete<-isTRUE(tryCatch({.brohn_gnat_delivery_complete(state,list(task=compiled),events[[length(events)]]);TRUE},error=function(e)FALSE))
  list(complete=complete,outer_session_qualified=FALSE,state=state$active$task,procedure_hash=compiled$procedure_hash,sequence_hash=compiled$sequence_hash)
}

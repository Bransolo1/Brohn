# Inactive saved-table reader 0.1. No compiler, sampler, registry IO or scoring.
# Internal saved IDs use the explicitly retained brohn-protocol-json/0.1 value codec.
# This is NOT a hash of the original file, nor an authority check.
.brohn_ph_canonical <- function(x) {
  if (is.list(x)) {
    if (!is.null(names(x))) x <- x[order(names(x), method = "radix")]
    return(lapply(x, .brohn_ph_canonical))
  }
  if (is.character(x)) return(enc2utf8(x))
  if (is.numeric(x)) return(as.double(x))
  x
}
.brohn_ph_equal <- function(a, b) identical(.brohn_ph_canonical(a), .brohn_ph_canonical(b), num.eq = FALSE)
.brohn_ph_expect <- function(actual, expected, label) {
  brohn_require(.brohn_ph_equal(actual, expected), paste("Saved protocol differs:", label))
  invisible(TRUE)
}
.brohn_ph_json <- function(x) as.character(jsonlite::toJSON(.brohn_ph_canonical(x), auto_unbox = TRUE,
  null = "null", digits = 17, pretty = FALSE, force = TRUE))
.brohn_ph_hash <- function(x) {
  text <- .brohn_ph_json(x)
  digest::digest(charToRaw(enc2utf8(text)), algo = "sha256", serialize = FALSE)
}
.brohn_ph_sha <- function(x) brohn_text(x,64) && grepl("^[0-9a-f]{64}$",x)
.brohn_ph_ids <- function(x, label = "member order") {
  brohn_require(brohn_array(x) && all(vapply(x,brohn_text,logical(1),max=240)), paste("Invalid saved",label))
  unlist(x,use.names=FALSE)
}
.brohn_ph_permutation <- function(actual, expected, label) {
  a <- .brohn_ph_ids(actual,label); e <- unlist(expected,use.names=FALSE)
  brohn_require(length(a)==length(e) && !anyDuplicated(a) && setequal(a,e),paste("Invalid saved",label))
  invisible(a)
}
.brohn_ph_decks <- function(trials, source) {
  for (category in source$categories) {
    pool <- brohn_ids(Filter(function(m) identical(m$category_id,category$id),source$materials))
    uses <- Filter(function(t) identical(t$category_id,category$id),trials)
    if (!length(uses)) next
    ids <- vapply(uses,function(t)t$material$id,character(1))
    brohn_require(length(pool)>0L,"Saved material has no original category pool.")
    for (start in seq.int(1L,length(ids),by=length(pool))) {
      deck <- ids[seq.int(start,min(length(ids),start+length(pool)-1L))]
      brohn_require(!anyDuplicated(deck) && all(deck %in% pool),"Saved exemplar cycle repeats or changes an original material.")
    }
  }
}
.brohn_ph_material <- function(trial, source) {
  brohn_require(brohn_text(trial$category_id,96) && trial$category_id %in% brohn_ids(source$categories),"Saved trial has an unknown category.")
  brohn_require(is.list(trial$material) && brohn_text(trial$material$id,96),"Saved trial has no exact original material.")
  original <- brohn_find(source$materials,trial$material$id)
  brohn_require(!is.null(original) && identical(original$category_id,trial$category_id),"Saved material/category binding differs.")
  .brohn_ph_expect(trial$material,original,"complete original material")
}
.brohn_ph_quota <- function(actual, members, counts, label) {
  brohn_require(length(actual)==sum(counts) && all(actual %in% members) &&
    identical(as.integer(tabulate(match(actual,members),nbins=length(members))),as.integer(counts)),paste("Saved quota differs:",label))
}

# Exact versioned definitions are appended from the inspected source11 constants.
.brohn_ph_profiles_v1 <- function() {
  profiles <- list(
  "iat-gnb2003-d1/1.0" = list(label = "Seven-block IAT", kind = "iat", trial_counts = c(20L,20L,20L,40L,20L,20L,40L),
    source = "https://faculty.washington.edu/agg/pdf/GN%26B.JPSP.2003.pdf", scoring = "Final-correct D1; combined practice and test; positive means faster in mapping A"),
  "biat-nosek2014-goodfocal/1.0" = list(label = "Good-focal Brief IAT", kind = "biat", trial_counts = c(16L,20L,20L,20L,20L),
    source = "https://journals.plos.org/plosone/article?id=10.1371/journal.pone.0110938", scoring = "Exclude warm-up and first four TARGET-category trials; original fast fraction then 400-2000 ms bounded D"),
  "aat-keyboard-cue-balanced/1.0" = list(label = "Keyboard approach-avoidance cue task", kind = "aat", trial_counts = c(16L,80L),
    source = "https://pmc.ncbi.nlm.nih.gov/articles/PMC10990989/", scoring = "Brohn keyboard initiation-latency recipe; control contrast in push-minus-pull means; not physical joystick AAT"),
  "rt-deary-liewald-simple/1.0" = list(label = "Simple reaction time", kind = "simple_rt", trial_counts = c(8L,20L),
    source = "https://doi.org/10.3758/s13428-010-0024-1", scoring = "Correct first-response test latencies; no age norms or cognitive labels"),
  "rt-deary-liewald-choice/1.0" = list(label = "Four-choice reaction time", kind = "choice_rt", trial_counts = c(8L,40L),
    source = "https://doi.org/10.3758/s13428-010-0024-1", scoring = "Correct first-response test latencies and errors; no age norms or cognitive labels"),
  "sciat-brohn-response-window-im100/1.0" = list(label = "Brohn response-window SC-IAT", kind = "sciat_window", trial_counts = c(24L,72L,24L,72L),
    source = "https://myscp.org/wp-content/uploads/2023/03/2007-proceedings.pdf#page=149",
    scoring = "One target with two attributes; first response within 1.5 seconds. Named Brohn procedure with explicit error replacement, omissions and test-only D scoring."))
  profiles[["gnat-brohn-single-target/1.0"]] <- list(
    label = "Brohn single-target GNAT", kind = "gnat", trial_counts = c(rep(20L, 4L), rep(c(16L, 60L), 4L)),
    source = "https://banaji.sites.fas.harvard.edu/research/publications/articles/2001_Nosek_SC.pdf",
    scoring = "One target with positive and negative attributes; separate 750 ms and 600 ms rounds. Four Go/No-Go outcomes, sensitivity and response criterion; withholding has no response time.")
  profiles
}

.brohn_ph_sciat_v1 <- function() list(
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

.brohn_ph_gnat_v1 <- function() list(
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

.brohn_ph_task_validated <- function(t, source, allocation) {
  definitions <- .brohn_ph_profiles_v1()
  brohn_require(brohn_text(t$profile,96) && t$profile %in% names(definitions),"Unsupported saved task profile version.")
  def <- definitions[[t$profile,exact=TRUE]]; mode <- def$kind
  special <- mode %in% c("sciat_window","gnat")
  brohn_fields(t,c("schema_version","id","profile","title","origin","design_hash","allocation_index","seed",
    "assignment","categories","blocks","timeline","provenance",if(special)c("procedure","procedure_hash","sequence_hash","source_block")else"scoring"),label="Saved task")
  common <- c("id","profile","title","origin","seed","categories")
  .brohn_ph_expect(t[common],source[common],"task original fields")
  .brohn_ph_expect(t$schema_version,"brohn-compiled-task/1.0","task schema")
  .brohn_ph_expect(t$allocation_index,allocation,"task allocation")
  .brohn_ph_expect(t$design_hash,.brohn_ph_hash(source),"original task-block hash")
  brohn_require(brohn_array(t$blocks)&&length(t$blocks)==length(def$trial_counts)&&brohn_array(t$timeline)&&
    length(t$timeline)==sum(def$trial_counts)+length(def$trial_counts),"Saved task block/trial cardinality differs.")
  if (special) {
    procedure <- if(mode=="gnat") .brohn_ph_gnat_v1() else .brohn_ph_sciat_v1()
    .brohn_ph_expect(t$procedure,procedure,"frozen procedure1.0")
    .brohn_ph_expect(source$settings$procedure,procedure,"source procedure1.0")
    .brohn_ph_expect(t$source_block,source,"retained original task block")
    .brohn_ph_expect(t$procedure_hash,.brohn_ph_hash(procedure),"procedure hash")
    .brohn_ph_expect(t$sequence_hash,.brohn_ph_hash(t$timeline),"retained sequence hash")
    if(mode=="gnat") .brohn_ph_gnat_table(t,source) else .brohn_ph_sciat_table(t,source)
  } else .brohn_ph_legacy_table(t,source,def)
  invisible(t)
}
brohn_validate_saved_task_table <- function(compiled, source_block, allocation_index) {
  .brohn_meb_domain(compiled); .brohn_meb_domain(source_block)
  brohn_require(brohn_number(allocation_index,1,1e9,TRUE),"Saved task requires its original allocation.")
  brohn_require(brohn_text(source_block$profile,96)&&source_block$profile %in% names(.brohn_ph_profiles_v1()),"Unsupported original task profile version.")
  brohn_task_validate(source_block)
  .brohn_ph_task_validated(compiled,source_block,allocation_index)
}
.brohn_ph_legacy_table <- function(t,s,def) {
  mode<-def$kind; allocation<-t$allocation_index; initial<-if(allocation%%2==1)"A"else"B"
  positive_left<-if(mode=="iat")floor((allocation-1)/2)%%2==0 else allocation%%2==1
  positive<-if(positive_left)"KeyE"else"KeyI"; negative<-if(positive_left)"KeyI"else"KeyE"
  .brohn_ph_expect(t$assignment,list(initial_mapping=if(mode %in% c("iat","biat"))initial else NULL,
    positive_attribute_key=if(mode=="iat")positive else if(mode=="biat")"KeyI"else NULL,
    approach_cue=if(mode=="aat")if(positive_left)"landscape"else"portrait"else NULL),"task assignment")
  .brohn_ph_expect(t$scoring,list(description=def$scoring,first_response_and_corrections_retained=TRUE,
    rt_min_ms=if(mode=="aat")200 else 0,rt_max_ms=if(mode=="aat")2000 else if(mode %in% c("simple_rt","choice_rt"))5000 else 10000),"scoring support metadata")
  .brohn_ph_expect(t$provenance,list(source=def$source,materials_rights=s$materials_rights,control_rationale=s$settings$control_rationale,
    implementation="Original Brohn runner; browser timing observed, physical timing not qualified; no percentile or individual-preference labels."),"task provenance")
  role<-function(r)Filter(function(c)identical(c$role,r),s$categories)[[1L]]
  offset<-0L
  for(b in seq_along(def$trial_counts)) {
    n<-def$trial_counts[[b]]; bid<-paste0(s$id,"-b",b); ids<-paste0(bid,"-t",seq_len(n))
    map<-if(mode=="iat")if(b<=4)initial else if(initial=="A")"B"else"A" else if(mode=="biat")if(b==1)"A"else if(b%%2==0)initial else if(initial=="A")"B"else"A" else NULL
    phase<-if(mode=="iat")if(b %in% c(4,7))"test"else"practice" else if(mode=="biat")if(b==1)"practice"else"test" else if(b==1)"practice"else"test"
    score_block<-if(mode=="iat")if(b %in% c(3,6))paste0(map,"p")else if(b %in% c(4,7))paste0(map,"t")else NULL else if(mode=="biat"&&b>1)paste0(map,if(b<=3)"p"else"t")else NULL
    pair<-if(mode=="iat")if(b %in% c(3,6))1L else if(b %in% c(4,7))2L else NULL else if(mode=="biat"&&b>1)if(b<=3)1L else 2L else NULL
    .brohn_ph_expect(t$blocks[[b]],list(id=bid,index=b,phase=phase,mapping=map,trial_count=n,trial_ids=as.list(ids)),"task block")
    trials<-t$timeline[seq.int(offset+2L,offset+n+1L)]; left<-right<-""; keys<-character()
    if(mode %in% c("iat","biat")) {
      ta<-role(if(mode=="biat"&&b==1)"warmup_a"else"target_a")$id
      tb<-role(if(mode=="biat"&&b==1)"warmup_b"else"target_b")$id
      good<-role("attribute_positive")$id; bad<-role("attribute_negative")$id
      if(mode=="iat") {
        keys<-setNames(c(if(map=="A")positive else negative,if(map=="A")negative else positive,positive,negative),c(ta,tb,good,bad))
        subset<-if(b %in% c(1,5))c(ta,tb)else if(b==2)c(good,bad)else c(ta,tb,good,bad)
        label<-function(k)paste(vapply(Filter(function(c)c$id %in% subset&&keys[[c$id]]==k,s$categories),`[[`,character(1),"label"),collapse=" or ")
        left<-label("KeyE");right<-label("KeyI")
      } else {
        focal<-if(map=="A")ta else tb
        keys<-setNames(c(if(ta==focal)"KeyI"else"KeyE",if(tb==focal)"KeyI"else"KeyE","KeyI","KeyE"),c(ta,tb,good,bad))
        subset<-c(ta,tb,good,bad);left<-"Anything else";right<-paste(brohn_find(s$categories,focal)$label,"or",role("attribute_positive")$label)
      }
      cats<-vapply(trials,function(x)x$category_id,character(1))
      if(mode=="iat"&&length(subset)==2) .brohn_ph_quota(cats,subset,rep(n/2,2),"IAT single-role block") else {
        prefix<-if(mode=="biat")4L else 0L
        if(prefix) .brohn_ph_quota(head(cats,prefix),c(ta,tb),c(2,2),"BIAT target prefix")
        remaining<-cats[seq.int(prefix+1L,n)]
        .brohn_ph_quota(remaining[seq.int(1L,length(remaining),by=2L)],c(ta,tb),rep((n-prefix)/4,2),"alternating targets")
        .brohn_ph_quota(remaining[seq.int(2L,length(remaining),by=2L)],c(good,bad),rep((n-prefix)/4,2),"alternating attributes")
      }
    }
    text<-if(mode %in% c("iat","biat"))paste("Use E for",left,"and I for",right,". Work quickly and accurately. If you make a mistake, correct it with the other key. Release each key before the next response.")else
      if(mode=="aat")paste("Respond to the FRAME orientation, not the product. Press",if(positive_left)"Down for a landscape frame (approach) and Up for a portrait frame (avoid)."else"Down for a portrait frame (approach) and Up for a landscape frame (avoid).","The image will grow for approach and shrink for avoidance. This is a keyboard task.")else
      if(mode=="simple_rt")"Wait for X in the box, then press B as quickly and accurately as you can. Do not press before X appears. Release the key between responses."else
        "Wait for X in one of four boxes. Press C, V, N or M for the first, second, third or fourth box. Do not press before X appears. Release the key between responses."
    .brohn_ph_expect(t$timeline[[offset+1L]],list(id=paste0(bid,"-instructions"),type="task_instructions",task_id=s$id,task_profile=s$profile,
      block_id=bid,block_index=b,phase="instructions",text=paste(if(phase=="practice")"Practice."else"Test.",text)),"task instruction")
    for(i in seq_len(n)) {
      a<-trials[[i]]; rt<-mode %in% c("simple_rt","choice_rt")
      if(!rt) .brohn_ph_material(a,s)
      action<-cue<-NULL; correct<-NULL
      if(mode %in% c("iat","biat"))correct<-unname(keys[[a$category_id]])
      if(mode=="aat") {
        brohn_require(a$category_id %in% c(role("target_a")$id,role("target_b")$id)&&brohn_text(a$action,20)&&a$action %in% c("approach","avoid"),"Invalid retained AAT cell.")
        action<-a$action;correct<-if(action=="approach")"ArrowDown"else"ArrowUp";cue<-if((action=="approach")==positive_left)"landscape"else"portrait"
      }
      position<-if(mode=="choice_rt")a$position else 1L
      brohn_require(brohn_number(position,1,4,TRUE),"Invalid retained choice position.")
      if(rt)correct<-if(mode=="simple_rt")"KeyB"else c("KeyC","KeyV","KeyN","KeyM")[[position]]
      foreperiod<-if(rt)a$foreperiod_ms else 0L
      if(rt)brohn_require(brohn_number(foreperiod,1000,3000,TRUE),"Invalid retained foreperiod.")
      expected<-list(id=ids[[i]],type="task_trial",task_id=s$id,task_profile=s$profile,block_id=bid,block_index=b,trial_index=i,
        phase=phase,mode=mode,mapping=map,score_block=score_block,pair=pair,scored=if(mode=="iat")b %in% c(3,4,6,7)else if(mode=="biat")b>1&&i>4 else phase=="test",
        category_id=if(rt)NULL else a$category_id,material=if(rt)NULL else a$material,correct_code=correct,
        allowed_codes=as.list(if(mode %in% c("iat","biat"))c("KeyE","KeyI")else if(mode=="aat")c("ArrowUp","ArrowDown")else if(mode=="simple_rt")"KeyB"else c("KeyC","KeyV","KeyN","KeyM")),
        left_label=left,right_label=right,forced_correction=mode %in% c("iat","biat"),foreperiod_ms=foreperiod,
        intertrial_ms=s$settings$intertrial_ms,timeout_ms=s$settings$trial_timeout_ms,action=action,cue=cue,position=position,
        box_count=if(mode=="choice_rt")4L else if(mode=="simple_rt")1L else 0L,zoom_duration_ms=if(mode=="aat")150L else 0L)
      .brohn_ph_expect(a,expected,"complete retained task trial")
    }
    if(mode=="aat") .brohn_ph_quota(vapply(trials,function(a)paste(a$category_id,a$action),character(1)),
      as.vector(outer(c(role("target_a")$id,role("target_b")$id),c("approach","avoid"),paste)),rep(n/4,4),"AAT category/action cells")
    if(mode=="choice_rt") .brohn_ph_quota(vapply(trials,function(a)as.character(a$position),character(1)),as.character(1:4),rep(n/4,4),"choice positions")
    .brohn_ph_decks(trials,s);offset<-offset+n+1L
  }
}
.brohn_ph_sciat_table <- function(t,s) {
  p<-.brohn_ph_sciat_v1();ph<-.brohn_ph_hash(p);roles<-unlist(p$roles,use.names=FALSE)
  categories<-setNames(lapply(roles,function(r)Filter(function(c)c$role==r,s$categories)[[1L]]),roles)
  maps<-rep(if(t$allocation_index%%2==1)c("A","B")else c("B","A"),each=2L)
  .brohn_ph_expect(t$assignment,list(initial_mapping=maps[[1]],positive_attribute_key="KeyE",negative_attribute_key="KeyI"),"SC-IAT assignment")
  .brohn_ph_expect(t$provenance,list(materials_rights=s$materials_rights,control_rationale=s$settings$control_rationale,language=s$settings$language),"SC-IAT provenance")
  offset<-0L
  for(b in 1:4) {
    phase<-if(b%%2==1)"practice"else"test";map<-maps[[b]];quota<-unlist(p$quotas[[map]][[phase]],use.names=FALSE)
    n<-sum(quota);bid<-paste0(s$id,"-b",b);ids<-paste0(bid,"-t",seq_len(n));trials<-t$timeline[seq.int(offset+2L,offset+n+1L)]
    .brohn_ph_expect(t$blocks[[b]],list(id=bid,index=b,mapping=map,phase=phase,trial_count=n,category_quotas=setNames(as.list(quota),roles),trial_ids=as.list(ids)),"SC-IAT block")
    correct<-function(r)if(r=="target")if(map=="A")"KeyE"else"KeyI"else if(r=="attribute_positive")"KeyE"else"KeyI"
    label<-function(k)paste(vapply(Filter(function(c)correct(c$role)==k,categories),`[[`,character(1),"label"),collapse=" or ")
    left<-label("KeyE");right<-label("KeyI")
    .brohn_ph_expect(t$timeline[[offset+1L]],list(id=paste0(bid,"-instructions"),type="task_instructions",task_id=s$id,task_profile=s$profile,
      block_id=bid,block_index=b,phase="instructions",mapping=map,text=paste(if(phase=="practice")"Practice."else"Test.","Use E for",left,"and I for",right,
      ". Respond quickly and accurately within 1.5 seconds. Your first key is final; do not correct an error. Release each key between responses.")),"SC-IAT instruction")
    for(i in seq_len(n)) {
      a<-trials[[i]];.brohn_ph_material(a,s);r<-a$category_role
      brohn_require(brohn_text(r,80)&&r %in% roles,"Unknown saved SC-IAT category role.")
      .brohn_ph_expect(a,list(id=ids[[i]],type="task_trial",task_id=s$id,task_profile=s$profile,procedure_hash=ph,
        block_id=bid,block_index=b,trial_index=i,phase=phase,mode="sciat_window",mapping=map,scored=phase=="test",
        category_id=categories[[r]]$id,category_role=r,material=a$material,correct_code=correct(r),allowed_codes=list("KeyE","KeyI"),
        left_label=left,right_label=right,forced_correction=FALSE,timeout_ms=1500L,response_feedback_ms=150L,
        omission_feedback_ms=500L,post_feedback_blank_ms=250L),"complete SC-IAT trial")
    }
    .brohn_ph_quota(vapply(trials,`[[`,character(1),"category_role"),roles,quota,"SC-IAT roles")
    .brohn_ph_decks(trials,s);offset<-offset+n+1L
  }
}
.brohn_ph_gnat_table <- function(t,s) {
  p<-.brohn_ph_gnat_v1();ph<-.brohn_ph_hash(p);roles<-unlist(p$roles,use.names=FALSE)
  categories<-setNames(lapply(roles,function(r)Filter(function(c)c$role==r,s$categories)[[1L]]),roles)
  brohn_fields(t$assignment,c("training_order","round_pairing_order"),label="Saved GNAT assignment")
  .brohn_ph_permutation(t$assignment$training_order,p$roles,"GNAT training order")
  brohn_require(brohn_array(t$assignment$round_pairing_order)&&length(t$assignment$round_pairing_order)==2L,"GNAT needs two retained rounds.")
  for(order in t$assignment$round_pairing_order) .brohn_ph_permutation(order,p$pairings_per_round,"GNAT pair order")
  .brohn_ph_expect(t$provenance,list(materials_rights=s$materials_rights,context_kind=s$settings$context_kind,context_rationale=s$settings$context_rationale,
    control_rationale=s$settings$control_rationale,language=s$settings$language),"GNAT provenance")
  phases<-lapply(t$assignment$training_order,function(r) {
    other<-c(target="context",context="target",attribute_positive="attribute_negative",attribute_negative="attribute_positive")[[r]]
    list(phase="training",round_id=NULL,cell_id=NULL,pairing=NULL,training_go_role=r,go_roles=r,
      quotas=setNames(ifelse(roles %in% c(r,other),10L,0L),roles),timeout_ms=1000L)
  })
  for(round in 1:2) for(pair in t$assignment$round_pairing_order[[round]]) for(phase in c("practice","test"))
    phases[[length(phases)+1L]]<-list(phase=phase,round_id=paste0("r",round),cell_id=paste0("r",round,"-",if(pair=="target_positive")"positive"else"negative"),
      pairing=pair,training_go_role=NULL,go_roles=c("target",if(pair=="target_positive")"attribute_positive"else"attribute_negative"),
      quotas=setNames(rep(if(phase=="practice")4L else 15L,4),roles),timeout_ms=if(round==1L)750L else 600L)
  offset<-0L
  for(b in seq_along(phases)) {
    q<-phases[[b]];n<-sum(q$quotas);bid<-paste0(s$id,"-b",b);ids<-paste0(bid,"-t",seq_len(n))
    trials<-t$timeline[seq.int(offset+2L,offset+n+1L)]
    labels<-unname(as.list(vapply(categories[q$go_roles],`[[`,character(1),"label")))
    header<-list(task_id=s$id,task_profile=s$profile,procedure_hash=ph,block_id=bid,block_index=b,
      phase=q$phase,round_id=q$round_id,cell_id=q$cell_id,pairing=q$pairing,training_go_role=q$training_go_role)
    .brohn_ph_expect(t$blocks[[b]],c(list(id=bid,index=b),q[c("phase","round_id","cell_id","pairing","training_go_role")],
      list(trial_count=n,category_quotas=as.list(q$quotas),go_roles=as.list(q$go_roles),timeout_ms=q$timeout_ms,trial_ids=as.list(ids))),"GNAT block")
    .brohn_ph_expect(t$timeline[[offset+1L]],c(list(id=paste0(bid,"-instructions"),type="task_instructions"),header,
      list(go_roles=as.list(q$go_roles),go_labels=labels,text=paste(if(q$phase=="test")"Test."else"Practice.","Press Space for",paste(unlist(labels),collapse=" or "),
      ". Do nothing for other items. Respond quickly and accurately; release Space between items. Each first response is final."))),"GNAT instruction")
    for(i in seq_len(n)) {
      a<-trials[[i]];.brohn_ph_material(a,s);r<-a$category_role
      brohn_require(brohn_text(r,80)&&r %in% roles,"Unknown saved GNAT category role.")
      .brohn_ph_expect(a,c(list(id=ids[[i]],type="task_trial"),header,list(trial_index=i,mode="gnat",scored=q$phase=="test",
        category_id=categories[[r]]$id,category_role=r,material=a$material,expected_action=if(r %in% q$go_roles)"go"else"nogo",
        allowed_codes=list("Space"),go_roles=as.list(q$go_roles),go_labels=labels,forced_correction=FALSE,timeout_ms=q$timeout_ms,
        feedback_ms=100L,offset_to_next_onset_min_ms=500L)),"complete GNAT trial")
    }
    .brohn_ph_quota(vapply(trials,`[[`,character(1),"category_role"),roles,q$quotas,"GNAT signal/noise roles")
    .brohn_ph_decks(trials,s);offset<-offset+n+1L
  }
}

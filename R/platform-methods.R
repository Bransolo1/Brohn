# Original Brohn task construction and arithmetic. No third-party task code or
# materials are embedded. Published procedures are cited in each named profile.
brohn_task_profiles <- function() list(
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

brohn_task_profile <- function(profile) {
  result <- brohn_task_profiles()[[profile]]
  brohn_require(!is.null(result), "Unsupported task profile. Choose a registered version.")
  result
}
brohn_task_clone <- function(block) {
  brohn_task_validate(block)
  category_ids <- setNames(vapply(block$categories, function(x) brohn_id("category"), character(1)), brohn_ids(block$categories))
  block$id <- brohn_id("task")
  block$categories <- lapply(block$categories, function(c) {c$id <- unname(category_ids[[c$id]]); c})
  block$materials <- lapply(block$materials, function(m) {m$id <- brohn_id("material"); m$category_id <- unname(category_ids[[m$category_id]]); m})
  brohn_task_validate(block); block
}

brohn_task_new <- function(profile = "iat-gnb2003-d1/1.0", title = NULL, id = brohn_id("task")) {
  if (identical(profile, "sciat-brohn-response-window-im100/1.0")) return(brohn_sciat_window_new(brohn_default(title, "Sample Brohn response-window SC-IAT"), id))
  definition <- brohn_task_profile(profile)
  roles <- if (definition$kind %in% c("simple_rt","choice_rt")) character() else
    c("target_a","target_b", if (definition$kind != "aat") c("attribute_positive","attribute_negative"), if (definition$kind == "biat") c("warmup_a","warmup_b"))
  labels <- c(target_a="Product A", target_b="Product B", attribute_positive="Good", attribute_negative="Bad", warmup_a="Mammals", warmup_b="Birds")
  exemplars <- list(target_a=c("Product A package","Product A display"), target_b=c("Product B package","Product B display"),
    attribute_positive=c("Pleasant","Joy"), attribute_negative=c("Awful","Pain"), warmup_a=c("Cat","Horse"), warmup_b=c("Robin","Eagle"))
  categories <- lapply(roles, function(role) list(id=gsub("_","-",role),label=unname(labels[[role]]),role=role))
  materials <- if(length(categories)) unlist(lapply(categories, function(category) lapply(seq_along(exemplars[[category$role]]), function(i)
    list(id=paste0(category$id,"-item-",i),category_id=category$id,type="text",content=exemplars[[category$role]][i],asset=NULL))),recursive=FALSE)else list()
  list(schema_version="brohn-task-block/1.0",id=id,title=brohn_default(title,paste("Sample",definition$label)),profile=profile,
    seed=104729L,origin="synthetic",materials_rights="Original synthetic demonstration exemplars; replace with reviewed research materials.",
    categories=categories,materials=materials,
    settings=list(intertrial_ms=250L,trial_timeout_ms=if(definition$kind %in% c("iat","biat")) 30000L else 5000L,
                  control_rationale="Synthetic demonstration. Specify the target/control relationship and relevant stimulus matching for the research study."))
}

brohn_task_validate <- function(block) {
  if (identical(block$profile, "sciat-brohn-response-window-im100/1.0")) return(brohn_sciat_window_validate(block))
  brohn_fields(block,c("schema_version","id","title","profile","seed","origin","materials_rights","categories","materials","settings"),label="Task block")
  brohn_require(identical(block$schema_version,"brohn-task-block/1.0") && brohn_valid_id(block$id) && nchar(block$id)<=80 && brohn_text(block$title,240),"Invalid task schema, identity or title (task IDs allow 80 characters to preserve trial-ID space).")
  definition <- brohn_task_profile(block$profile)
  brohn_require(brohn_number(block$seed,1,.Machine$integer.max,TRUE),"Task seed must be a positive supported integer.")
  brohn_require(block$origin %in% c("synthetic","researcher_supplied") && brohn_text(block$materials_rights,4000),"Task origin and material rights/provenance must be explicit.")
  brohn_fields(block$settings,c("intertrial_ms","trial_timeout_ms","control_rationale"),label="Task settings")
  brohn_require(brohn_number(block$settings$intertrial_ms,100,2000,TRUE),"Intertrial interval must be 100 to 2000 whole milliseconds.")
  brohn_require(brohn_number(block$settings$trial_timeout_ms,if(definition$kind %in% c("iat","biat"))10001 else 1000,60000,TRUE),"Task abandonment timeout is outside this profile's supported range.")
  brohn_require(brohn_text(block$settings$control_rationale,4000),"Record the task comparison/control rationale.")
  brohn_require(brohn_array(block$categories) && brohn_array(block$materials) && length(block$materials)<=400,"Task categories/materials must be bounded arrays.")
  required_roles <- if(definition$kind %in% c("simple_rt","choice_rt")) character() else
    c("target_a","target_b",if(definition$kind!="aat")c("attribute_positive","attribute_negative"),if(definition$kind=="biat")c("warmup_a","warmup_b"))
  for(category in block$categories) {
    brohn_fields(category,c("id","label","role"),label="Task category")
    brohn_require(brohn_valid_id(category$id) && brohn_text(category$label,240),"Task category needs an identity and label.")
  }
  roles <- vapply(block$categories,function(category)category$role,character(1))
  brohn_require(setequal(roles,required_roles) && !anyDuplicated(roles) && !anyDuplicated(brohn_ids(block$categories)),"The selected profile needs exactly its named category roles.")
  for(material in block$materials) {
    brohn_fields(material,c("id","category_id","type","content","asset"),optional="image_alt",label="Task material")
    brohn_require(brohn_valid_id(material$id) && material$category_id %in% brohn_ids(block$categories) && material$type %in% c("text","image"),"Task material identity/category/type is invalid.")
    if("image_alt" %in% names(material))brohn_require(material$type=="image" && brohn_text(material$image_alt,2000),"A task image description must be nonempty supported text and belong to an image.")
    brohn_require(brohn_text(material$content,4000,material$type=="image"),"Task material text is missing or too long.")
    if(material$type=="image") {
      brohn_fields(material$asset,c("hash","size","media_type"),c("filename","width","height"),"Task image asset")
      brohn_require(brohn_text(material$asset$hash,64) && grepl("^[a-f0-9]{64}$",material$asset$hash) &&
        material$asset$media_type %in% c("image/png","image/jpeg","image/webp") && brohn_number(material$asset$size,1,20*1024^2,TRUE),"Task image asset must have an immutable supported image manifest.")
    } else brohn_require(is.null(material$asset),"Text task material cannot hide an attached asset.")
  }
  brohn_require(!anyDuplicated(brohn_ids(block$materials)),"Task material IDs must be unique.")
  for(category in block$categories) brohn_require(sum(vapply(block$materials,function(item)identical(item$category_id,category$id),logical(1)))>=2,"Provide at least two exemplars for each category.")
  if(!length(required_roles)) brohn_require(!length(block$materials),"The reaction-time profile uses its own X/box stimulus; arbitrary exemplars would change the procedure.")
  invisible(block)
}

brohn_task_compile <- function(block, allocation_index=1L) {
  if (identical(block$profile, "sciat-brohn-response-window-im100/1.0")) return(brohn_sciat_window_compile(block, allocation_index))
  brohn_task_validate(block)
  brohn_require(brohn_number(allocation_index,1,1e9,TRUE),"Task allocation index must be a positive whole integer.")
  definition <- brohn_task_profile(block$profile)
  brohn_seeded(((block$seed+allocation_index-2)%%(.Machine$integer.max-1))+1,function() {
    role <- function(name) Filter(function(category)category$role==name,block$categories)[[1]]
    initial <- if(allocation_index%%2==1) "A" else "B"
    positive_left <- if(definition$kind=="aat")allocation_index%%2==1 else floor((allocation_index-1)/2)%%2==0
    positive_key <- if(positive_left)"KeyE" else "KeyI"
    negative_key <- if(positive_left)"KeyI" else "KeyE"
    timeline <- list(); blocks <- list()
    material_pool <- setNames(lapply(block$categories,function(category)Filter(function(item)item$category_id==category$id,block$materials)),brohn_ids(block$categories))
    draw_remaining <- new.env(parent=emptyenv())
    draw <- function(category_id) {
      pool<-material_pool[[category_id]]
      remaining<-draw_remaining[[category_id]]
      if(!length(remaining))remaining<-sample.int(length(pool))
      selected<-remaining[1];draw_remaining[[category_id]]<-remaining[-1]
      pool[[selected]]
    }
    balanced <- function(categories,n) {
      brohn_require(n%%length(categories)==0,"Internal profile count is not category-balanced.")
      sample(rep(categories,each=n/length(categories)))
    }
    combined <- function(targets,attributes,n,prefix=0L) {
      categories<-if(prefix)balanced(targets,prefix)else character()
      remaining<-n-prefix
      interleaved<-as.vector(rbind(balanced(targets,remaining/2),balanced(attributes,remaining/2)))
      c(categories,interleaved)
    }
    append_block <- function(index,count,phase,mapping=NULL,score_block=NULL,pair=NULL) {
      block_id<-paste0(block$id,"-b",index)
      for(category in names(material_pool))draw_remaining[[category]]<-integer()
      trial_ids<-paste0(block_id,"-t",seq_len(count))
      mode<-definition$kind
      category_map<-character(); left_label<-""; right_label<-""; category_order<-character()
      if(mode %in% c("iat","biat")) {
        ta<-role("target_a")$id; tb<-role("target_b")$id
        good<-role("attribute_positive")$id; bad<-role("attribute_negative")$id
        if(mode=="iat") {
          target_a_key<-if(mapping=="A")positive_key else negative_key
          target_b_key<-if(mapping=="A")negative_key else positive_key
          category_map<-setNames(c(target_a_key,target_b_key,positive_key,negative_key),c(ta,tb,good,bad))
          subset<-if(index %in% c(1,5))c(ta,tb)else if(index==2)c(good,bad)else c(ta,tb,good,bad)
          category_order<-if(length(subset)==2)balanced(subset,count)else combined(c(ta,tb),c(good,bad),count)
          label_for<-function(key) paste(vapply(Filter(function(category)category$id %in% subset && category_map[[category$id]]==key,block$categories),function(category)category$label,character(1)),collapse=" or ")
          left_label<-label_for("KeyE"); right_label<-label_for("KeyI")
        } else {
          if(index==1) {ta<-role("warmup_a")$id;tb<-role("warmup_b")$id}
          focal<-if(mapping=="A")ta else tb
          category_map<-setNames(c(if(ta==focal)"KeyI"else"KeyE",if(tb==focal)"KeyI"else"KeyE","KeyI","KeyE"),c(ta,tb,good,bad))
          # Primary source correction: the excluded prefix is TARGET-only, not attribute-only.
          category_order<-combined(c(ta,tb),c(good,bad),count,prefix=4L)
          left_label<-"Anything else"
          right_label<-paste(brohn_find(block$categories,focal)$label,"or",role("attribute_positive")$label)
        }
      }
      instructions<-if(mode %in% c("iat","biat"))paste("Use E for",left_label,"and I for",right_label,". Work quickly and accurately. If you make a mistake, correct it with the other key. Release each key before the next response.")else
        if(mode=="aat")paste("Respond to the FRAME orientation, not the product. Press",if(positive_left)"Down for a landscape frame (approach) and Up for a portrait frame (avoid)."else"Down for a portrait frame (approach) and Up for a landscape frame (avoid).","The image will grow for approach and shrink for avoidance. This is a keyboard task.")else
        if(mode=="simple_rt")"Wait for X in the box, then press B as quickly and accurately as you can. Do not press before X appears. Release the key between responses."else
          "Wait for X in one of four boxes. Press C, V, N or M for the first, second, third or fourth box. Do not press before X appears. Release the key between responses."
      timeline[[length(timeline)+1L]]<<-list(id=paste0(block_id,"-instructions"),type="task_instructions",task_id=block$id,task_profile=block$profile,
        block_id=block_id,block_index=index,phase="instructions",text=paste(if(phase=="practice")"Practice."else"Test.",instructions))
      aat_cells<-if(mode=="aat")sample(rep(c("A-approach","A-avoid","B-approach","B-avoid"),each=count/4))else character()
      positions<-if(mode=="choice_rt")sample(rep(1:4,each=count/4))else rep(1L,count)
      for(i in seq_len(count)) {
        category_id<-if(length(category_order))category_order[i]else NULL
        material<-if(!is.null(category_id))draw(category_id)else NULL
        action<-NULL;cue<-NULL
        correct<-if(mode %in% c("iat","biat"))unname(category_map[[category_id]])else if(mode=="simple_rt")"KeyB"else if(mode=="choice_rt")c("KeyC","KeyV","KeyN","KeyM")[positions[i]]else NULL
        if(mode=="aat") {
          cell<-strsplit(aat_cells[i],"-",fixed=TRUE)[[1]]
          category_id<-role(if(cell[1]=="A")"target_a"else"target_b")$id;material<-draw(category_id)
          action<-cell[2];correct<-if(action=="approach")"ArrowDown"else"ArrowUp"
          cue<-if((action=="approach")==positive_left)"landscape"else"portrait"
        }
        scored<-if(mode=="iat")index %in% c(3,4,6,7)else if(mode=="biat")index>1 && i>4 else phase=="test"
        trial<-list(id=trial_ids[i],type="task_trial",task_id=block$id,task_profile=block$profile,block_id=block_id,block_index=index,trial_index=i,
          phase=phase,mode=mode,mapping=mapping,score_block=score_block,pair=pair,scored=scored,category_id=category_id,material=material,
          correct_code=correct,allowed_codes=as.list(if(mode %in% c("iat","biat"))c("KeyE","KeyI")else if(mode=="aat")c("ArrowUp","ArrowDown")else if(mode=="simple_rt")"KeyB"else c("KeyC","KeyV","KeyN","KeyM")),
          left_label=left_label,right_label=right_label,forced_correction=mode %in% c("iat","biat"),
          foreperiod_ms=if(mode %in% c("simple_rt","choice_rt"))sample(1000:3000,1)else 0L,
          intertrial_ms=block$settings$intertrial_ms,timeout_ms=block$settings$trial_timeout_ms,
          action=action,cue=cue,position=positions[i],box_count=if(mode=="choice_rt")4L else if(mode=="simple_rt")1L else 0L,
          zoom_duration_ms=if(mode=="aat")150L else 0L)
        timeline[[length(timeline)+1L]]<<-trial
      }
      blocks[[length(blocks)+1L]]<<-list(id=block_id,index=index,phase=phase,mapping=mapping,trial_count=count,trial_ids=as.list(trial_ids))
    }
    if(definition$kind=="iat") {
      second<-if(initial=="A")"B"else"A"
      maps<-c(rep(initial,4),rep(second,3))
      for(i in 1:7)append_block(i,definition$trial_counts[i],if(i %in% c(4,7))"test"else"practice",maps[i],
        if(i %in% c(3,6))paste0(maps[i],"p")else if(i %in% c(4,7))paste0(maps[i],"t")else NULL,
        if(i %in% c(3,6))1L else if(i %in% c(4,7))2L else NULL)
    } else if(definition$kind=="biat") {
      maps<-c("A",if(initial=="A")c("A","B","A","B")else c("B","A","B","A"))
      for(i in 1:5)append_block(i,definition$trial_counts[i],if(i==1)"practice"else"test",maps[i],
        if(i>1)paste0(maps[i],if(i<=3)"p"else"t")else NULL,if(i>1)if(i<=3)1L else 2L else NULL)
    } else for(i in 1:2)append_block(i,definition$trial_counts[i],if(i==1)"practice"else"test")
    list(schema_version="brohn-compiled-task/1.0",id=block$id,profile=block$profile,title=block$title,origin=block$origin,
      design_hash=brohn_hash(block),allocation_index=allocation_index,seed=block$seed,
      assignment=list(initial_mapping=if(definition$kind %in% c("iat","biat"))initial else NULL,positive_attribute_key=if(definition$kind=="iat")positive_key else if(definition$kind=="biat")"KeyI"else NULL,
        approach_cue=if(definition$kind=="aat")if(positive_left)"landscape"else"portrait"else NULL),
      categories=block$categories,blocks=blocks,timeline=timeline,
      scoring=list(description=definition$scoring,first_response_and_corrections_retained=TRUE,
        rt_min_ms=if(definition$kind=="aat")200 else 0,rt_max_ms=if(definition$kind=="aat")2000 else if(definition$kind %in% c("simple_rt","choice_rt"))5000 else 10000),
      provenance=list(source=definition$source,materials_rights=block$materials_rights,control_rationale=block$settings$control_rationale,
        implementation="Original Brohn runner; browser timing observed, physical timing not qualified; no percentile or individual-preference labels."))
  })
}

brohn_iat_d1 <- function(trials, completed=TRUE, biat=FALSE) {
  brohn_require(is.data.frame(trials) && all(c("score_block","latency_ms") %in% names(trials)),"D scoring needs score_block and final-correct latency_ms columns.")
  selected<-trials[trials$score_block %in% c("Ap","At","Bp","Bt"),,drop=FALSE]
  result<-list(eligible=FALSE,value=NULL,unit="D",reason=NULL,original_count=nrow(selected),retained_count=0L,
    slow_count=0L,fast_numerator=0L,fast_denominator=0L,fast_fraction=NULL,pairs=list(),
    direction="Positive means faster in declared mapping A; no individual preference bands.")
  if(!isTRUE(completed)){result$reason<-"Task incomplete or interrupted";return(result)}
  if(!is.numeric(selected$latency_ms)||any(!is.finite(selected$latency_ms))||any(selected$latency_ms<=0)) {
    result$reason<-"Missing, nonfinite or nonpositive final-correct response time";return(result)
  }
  result$slow_count<-sum(selected$latency_ms>10000)
  selected<-selected[selected$latency_ms<=10000,,drop=FALSE]
  result$retained_count<-nrow(selected);result$fast_numerator<-sum(selected$latency_ms<300)
  result$fast_denominator<-nrow(selected)
  if(nrow(selected)==0){result$reason<-"No retained scored trials";return(result)}
  result$fast_fraction<-result$fast_numerator/result$fast_denominator
  if(result$fast_fraction>.10){result$reason<-"More than 10% of retained scored trials are faster than 300 ms";return(result)}
  if(biat)selected$latency_ms<-pmin(2000,pmax(400,selected$latency_ms))
  scores<-numeric()
  for(suffix in c("p","t")) {
    a<-selected$latency_ms[selected$score_block==paste0("A",suffix)]
    b<-selected$latency_ms[selected$score_block==paste0("B",suffix)]
    if(!length(a)||!length(b)){result$reason<-"A required paired block has no retained trials";return(result)}
    denominator<-stats::sd(c(a,b))
    if(!is.finite(denominator)||denominator==0){result$reason<-"A paired block has zero or unavailable sample SD";return(result)}
    score<-(mean(b)-mean(a))/denominator;scores<-c(scores,score)
    result$pairs[[length(result$pairs)+1L]]<-list(pair=if(suffix=="p")1L else 2L,mapping_a_mean_ms=mean(a),mapping_b_mean_ms=mean(b),
      combined_sample_sd_ms=denominator,mapping_a_n=length(a),mapping_b_n=length(b),d=score)
  }
  result$eligible<-TRUE;result$value<-mean(scores);result
}

brohn_task_score <- function(compiled,responses,completed=TRUE) {
  if (identical(compiled$profile, "sciat-brohn-response-window-im100/1.0")) return(brohn_sciat_window_score(compiled, responses, completed))
  brohn_require(identical(compiled$schema_version,"brohn-compiled-task/1.0") && brohn_array(responses),"Task scorer needs a compiled task and response-record array.")
  definition<-brohn_task_profile(compiled$profile)
  trials<-Filter(function(step)step$type=="task_trial",compiled$timeline)
  expected<-brohn_ids(trials)
  response_ids<-vapply(responses,function(response)brohn_default(response$trial_id,""),character(1))
  brohn_require(!anyDuplicated(response_ids)&&all(response_ids %in% expected),"Responses contain duplicate or unknown frozen trial IDs.")
  result<-list(schema_version="brohn-task-score/1.0",task_id=compiled$id,profile=compiled$profile,origin=compiled$origin,
    design_hash=compiled$design_hash,status="unavailable",eligible=FALSE,metrics=list(),counts=list(expected=length(trials),received=length(responses)),
    reason=NULL,limitations=c("Participant/task-level descriptive scoring; no population inference from trial rows.","Material validity, device timing and population applicability require their own evidence."))
  if(definition$kind %in% c("simple_rt","choice_rt")) {
    # Collection profiles remain frozen. New analyses explicitly identify the
    # corrected support policy; existing /1.0 report objects are never rewritten.
    result$schema_version<-"brohn-task-score/1.1"
    result$scoring_recipe<-"brohn-rt-metric-support/1.0"
    result$support_policy<-list(complete_trial_evidence_required=TRUE,
      aggregate_eligible_definition="At least one metric is supported; use each metric's eligibility for analysis or aggregation.",
      mean_median_minimum_correct=1L,sample_sd_minimum_correct=2L,
      compatibility="Earlier brohn-task-score/1.0 results required two retained correct responses before emitting any RT-task metric. This recipe permits one-response mean/median and independently supported rates; task collection, RT windows and previously published results are unchanged.")
  }
  if(!isTRUE(completed)||!setequal(response_ids,expected)){result$reason<-"Complete uninterrupted task evidence is required";return(result)}
  ordered<-responses[match(expected,response_ids)]
  rows<-lapply(seq_along(trials),function(i) {
    trial<-trials[[i]];response<-ordered[[i]]
    brohn_require(response$outcome %in% c("correct","incorrect","timeout","interrupted"),"Unsupported task response outcome.")
    brohn_require(is.logical(response$first_correct)&&length(response$first_correct)==1&&!is.na(response$first_correct),"Task response needs explicit first-response accuracy.")
    brohn_require(is.null(response$response_code)||response$response_code %in% unlist(trial$allowed_codes),"A recorded response key is not allowed in this trial.")
    brohn_require(identical(response$first_correct,!is.null(response$response_code)&&identical(response$response_code,trial$correct_code)),"First-response accuracy disagrees with the frozen correct key.")
    if(response$outcome=="correct")brohn_require(identical(response$final_code,trial$correct_code)&&!is.null(response$final_correct_ms),"Correct outcome requires the frozen correct key and final latency.")
    for(field in c("first_response_ms","final_correct_ms")) brohn_require(is.null(response[[field]])||brohn_number(response[[field]],0,trial$timeout_ms+2500),paste("Invalid",field))
    brohn_require(identical(is.null(response$response_code),is.null(response$first_response_ms)),"A first response needs both key and latency, or neither.")
    if(!is.null(response$final_correct_ms))brohn_require(!is.null(response$first_response_ms)&&response$final_correct_ms>=response$first_response_ms,"Final-correct latency cannot precede the first response.")
    if(response$first_correct)brohn_require(response$outcome=="correct"&&!is.null(response$first_response_ms)&&!is.null(response$final_correct_ms)&&abs(response$first_response_ms-response$final_correct_ms)<.000001,"A correct first response needs equal first/final latencies.")
    data.frame(trial_id=trial$id,score_block=brohn_default(trial$score_block,""),scored=trial$scored,
      category_id=brohn_default(trial$category_id,""),action=brohn_default(trial$action,""),
      latency_ms=if(definition$kind %in% c("iat","biat"))brohn_default(response$final_correct_ms,NA_real_)else brohn_default(response$first_response_ms,NA_real_),
      first_correct=response$first_correct,responded=!is.null(response$first_response_ms),outcome=response$outcome,stringsAsFactors=FALSE)
  })
  data<-do.call(rbind,rows)
  if(any(data$outcome=="interrupted")){result$reason<-"Task contains an interrupted trial";return(result)}
  result$counts$first_response_errors<-sum(data$responded & !data$first_correct)
  result$counts$timeouts<-sum(data$outcome=="timeout")
  if(definition$kind %in% c("iat","biat")) {
    if(any(data$outcome!="correct")){result$reason<-"Correction-inclusive tasks require a final correct response to every trial";return(result)}
    d<-brohn_iat_d1(data[data$scored,,drop=FALSE],completed=TRUE,biat=definition$kind=="biat")
    result$eligible<-d$eligible;result$status<-if(d$eligible)"computed"else"excluded";result$reason<-d$reason
    result$metrics<-list(list(name=if(definition$kind=="iat")"IAT_D1"else"BIAT_D",value=d$value,unit="D",direction=d$direction))
    result$scoring_audit<-d;return(result)
  }
  scored<-data[data$scored,,drop=FALSE]
  valid<-scored$first_correct & scored$outcome=="correct" & is.finite(scored$latency_ms) &
    scored$latency_ms>=compiled$scoring$rt_min_ms & scored$latency_ms<=compiled$scoring$rt_max_ms
  retained<-scored[valid,,drop=FALSE]
  result$counts$scored<-nrow(scored);result$counts$retained_correct<-nrow(retained)
  result$counts$errors<-sum(scored$responded & !scored$first_correct);result$counts$outside_rt_window<-sum(scored$first_correct & !valid)
  metric<-function(name,value,unit="ms",...)list(name=name,value=if(length(value)&&is.finite(value))unname(value)else NULL,unit=unit,...)
  if(definition$kind=="aat") {
    categories<-vapply(c("target_a","target_b"),function(role)Filter(function(category)category$role==role,compiled$categories)[[1]]$id,character(1))
    cells<-list();bias<-numeric()
    for(category in categories) {
      approach<-retained$latency_ms[retained$category_id==category & retained$action=="approach"]
      avoid<-retained$latency_ms[retained$category_id==category & retained$action=="avoid"]
      if(length(approach)<4||length(avoid)<4){result$reason<-"Each target-by-action cell needs at least four retained correct trials in this keyboard recipe";return(result)}
      difference<-mean(avoid)-mean(approach);bias<-c(bias,difference)
      cells[[length(cells)+1L]]<-list(category_id=category,approach_n=length(approach),avoid_n=length(avoid),approach_mean_ms=mean(approach),avoid_mean_ms=mean(avoid),avoid_minus_approach_ms=difference)
    }
    result$metrics<-list(metric("keyboard_aat_relative_approach_advantage",bias[1]-bias[2],direction="(avoid - approach) target A minus (avoid - approach) target B"))
    result$cells<-cells;result$limitations<-c(result$limitations,"Keyboard cue/zoom response measures key initiation, not joystick movement or execution time. The Brohn counts/windows are a named research recipe, not universal AAT defaults.")
  } else {
    n_correct<-nrow(retained);n_answered<-sum(scored$responded)
    n_errors<-sum(scored$responded & !scored$first_correct);n_test<-nrow(scored)
    n_omitted<-sum(scored$outcome=="timeout")
    result$counts$scored_responded<-n_answered;result$counts$scored_timeouts<-n_omitted
    rt_metric<-function(name,value,minimum,reason,sd=FALSE) {
      eligible<-n_correct>=minimum
      metric(name,if(eligible)value else NULL,eligible=eligible,
        reason=if(eligible)NULL else reason,
        support=list(eligible_count=n_correct,minimum_count=minimum,
          population="retained_correct_test_responses",numerator=NULL,denominator=n_correct,
          denominator_definition="Correct first responses in scored test trials within the frozen RT window; practice trials are excluded.",
          sample_sd_divisor=if(sd)max(0L,n_correct-1L)else NULL,
          rt_min_ms=compiled$scoring$rt_min_ms,rt_max_ms=compiled$scoring$rt_max_ms))
    }
    rate_metric<-function(name,numerator,denominator,population,description,reason) {
      eligible<-denominator>0L
      metric(name,if(eligible)numerator/denominator else NULL,"proportion",
        eligible=eligible,reason=if(eligible)NULL else reason,
        support=list(eligible_count=denominator,minimum_count=1L,population=population,
          numerator=numerator,denominator=denominator,denominator_definition=description))
    }
    result$metrics<-list(
      rt_metric("correct_test_rt_mean",if(n_correct)mean(retained$latency_ms)else NULL,1L,
        "No correct test response falls within the frozen RT window."),
      rt_metric("correct_test_rt_median",if(n_correct)stats::median(retained$latency_ms)else NULL,1L,
        "No correct test response falls within the frozen RT window."),
      rt_metric("correct_test_rt_sd",if(n_correct>=2L)stats::sd(retained$latency_ms)else NULL,2L,
        "At least two retained correct test responses are required for a sample standard deviation.",sd=TRUE),
      rate_metric("test_first_response_error_rate",n_errors,n_answered,"answered_test_trials",
        "Wrong first responses divided by all answered scored test trials, including responses outside the RT window; practice and no-response timeouts are excluded.",
        "No scored test trial has a recorded first response; the error rate is unavailable."),
      rate_metric("test_omission_rate",n_omitted,n_test,"all_scored_test_trials",
        "No-response timeouts divided by all scored test trials in the complete frozen task; practice trials are excluded.",
        "No scored test trial is available for the omission denominator."))
    available<-vapply(result$metrics,function(m)isTRUE(m$eligible),logical(1))
    result$eligible<-any(available)
    result$status<-if(all(available))"computed"else if(any(available))"partial"else"unavailable"
    if(!all(available))result$reason<-"Some metrics have insufficient support. Each available value retains its own trial population and denominator."
    return(result)
  }
  result$eligible<-TRUE;result$status<-"computed";result
}

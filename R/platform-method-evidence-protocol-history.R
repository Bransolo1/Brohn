# Inactive pure saved brohn-protocol/1.1.0 reader. All orders below are READ
# from retained tables; this module never calls a compiler, sampler or registry.
.brohn_ph_domain <- function(value) {
  count<-0L;minimum_bytes<-0;limit<-16*1024^2
  add_bytes<-function(n){minimum_bytes<<-minimum_bytes+n;brohn_require(minimum_bytes<=limit,"Saved protocol exceeds16 MiB.")}
  walk<-function(x,depth=0L) {
    count<<-count+1L
    brohn_require(depth<64L&&count<=2000000L,"Saved protocol exceeds JSON depth/node bounds.")
    if(is.null(x)){add_bytes(4L);return(invisible(NULL))}
    brohn_require(is.null(attributes(x)) || (typeof(x)=="list"&&identical(names(attributes(x)),"names")),"Saved protocol must contain plain JSON values.")
    if(typeof(x)=="list") {
      add_bytes(2L)
      n<-names(x)
      if(!is.null(n)){
        brohn_require(!anyNA(n)&&all(validUTF8(n))&&all(nzchar(n))&&!anyDuplicated(enc2utf8(n)),"Saved object keys must be unique valid UTF-8.")
        add_bytes(sum(nchar(enc2utf8(n),type="bytes"))+3*length(n))
      }
      for(v in x)walk(v,depth+1L)
    } else {
      brohn_require(length(x)==1L&&((is.character(x)&&!is.na(x)&&validUTF8(x))||
        (is.logical(x)&&!is.na(x))||(typeof(x) %in% c("integer","double")&&is.finite(x))),"Saved scalar is outside the JSON domain.")
      add_bytes(if(is.character(x))nchar(enc2utf8(x),type="bytes")+2L else if(is.logical(x))if(x)4L else 5L else 1L)
    }
    invisible(NULL)
  }
  walk(value)
  brohn_require(nchar(.brohn_ph_json(value),type="bytes")<=limit,"Saved protocol exceeds16 MiB after JSON escaping.")
  invisible(TRUE)
}
.brohn_ph_order <- function(actual,sources,label) {
  .brohn_ph_permutation(actual,as.list(brohn_ids(sources)),label)
  ids<-unlist(actual,use.names=FALSE)
  for(i in seq_along(sources)) if(sources[[i]]$placement=="fixed")
    brohn_require(identical(ids[[i]],sources[[i]]$id),paste("Fixed saved position differs:",label))
  lapply(ids,function(id)brohn_find(sources,id))
}
.brohn_ph_assignment <- function(a,d,allocation,scope,stimulus,design_hash) {
  sid<-if(is.null(stimulus))NULL else stimulus$id
  config<-d$questionnaire_sections
  context<-list(schema_version="brohn-questionnaire-assignment/1.0",assignment=config$assignment,design_hash=design_hash,
    sections_hash=.brohn_ph_hash(config),seed=sprintf("%.0f",d$seed),allocation_index=sprintf("%.0f",allocation),scope=scope,stimulus_id=sid)
  aid<-paste0("questionnaire-",.brohn_ph_hash(context))
  brohn_fields(a,c(names(context),"assignment_id","realized_section_order","sections","realized_question_order"),label="Saved questionnaire assignment")
  .brohn_ph_expect(a[names(context)],context,"section source context")
  .brohn_ph_expect(a$assignment_id,aid,"section assignment ID")
  selected<-.brohn_ph_order(a$realized_section_order,Filter(function(s)s$scope==scope,config$sections),"section order")
  brohn_require(brohn_array(a$sections)&&length(a$sections)==length(selected),"Saved section cardinality differs.")
  entries<-list()
  for(si in seq_along(selected)) {
    s<-selected[[si]];r<-a$sections[[si]]
    brohn_fields(r,c("id","label","placement","position","realized_group_order","groups"),label="Saved section")
    groups<-.brohn_ph_order(r$realized_group_order,s$groups,"group order")
    brohn_require(brohn_array(r$groups)&&length(r$groups)==length(groups),"Saved group cardinality differs.")
    expected_groups<-list()
    for(gi in seq_along(groups)) {
      g<-groups[[gi]];expected_groups[[gi]]<-list(id=g$id,label=g$label,placement=g$placement,position=gi,question_ids=g$question_ids)
      for(qi in seq_along(g$question_ids))entries[[length(entries)+1L]]<-list(question=brohn_find(d$questions,g$question_ids[[qi]]),
        questionnaire=list(schema_version="brohn-questionnaire-step/1.0",assignment_id=aid,section_id=s$id,section_label=s$label,
          section_position=si,group_id=g$id,group_label=g$label,group_position=gi,question_position=qi,scope=scope,stimulus_id=sid))
    }
    .brohn_ph_expect(r,list(id=s$id,label=s$label,placement=s$placement,position=si,
      realized_group_order=as.list(brohn_ids(groups)),groups=expected_groups),"complete section/groups")
  }
  .brohn_ph_expect(a$realized_question_order,as.list(vapply(entries,function(e)e$question$id,character(1))),"section question membership/order")
  entries
}
.brohn_ph_refs <- function(rule) {
  if(is.null(rule))return(character())
  if(rule$op %in% c("and","or"))return(unique(unlist(lapply(rule$rules,.brohn_ph_refs),use.names=FALSE)))
  if(rule$op=="not")return(.brohn_ph_refs(rule[["rule",exact=TRUE]]))
  rule$question_id
}
.brohn_ph_occurrence <- function(p,members,scope,anchor,manifest) {
  ids<-vapply(members,function(s)s$question$id,character(1))
  brohn_require(!anyDuplicated(ids)&&length(ids)<=200L,"Saved occurrence has repeated/too many questions.")
  dependencies<-lapply(members,function(s)list(question_id=s$question$id,references=as.list(.brohn_ph_refs(s$question$show_if)),rule_hash=.brohn_ph_hash(s$question$show_if)))
  for(i in seq_along(members))for(ref in .brohn_ph_refs(members[[i]]$question$show_if)) {
    q<-brohn_find(p$design$questions,ref)
    brohn_require(!is.null(q)&&((q$scope=="before"&&scope!="before")||ref %in% head(ids,i-1L)),"Saved conditional driver does not precede its dependent question.")
  }
  identity<-list(schema="brohn-questionnaire-occurrence/1.0",design_hash=p$design_hash,scope=scope,
    stimulus_step_id=if(scope=="after_each")anchor$id else NULL,question_step_ids=as.list(brohn_ids(members)),
    policy_hash=.brohn_ph_hash(p$design$questionnaire_navigation))
  hash<-.brohn_ph_hash(identity);id<-paste0("qocc-",hash);review<-paste0("qreview-",hash)
  bindings<-unique(Filter(Negate(is.null),lapply(members,function(s)s[["questionnaire",exact=TRUE]][["assignment_id",exact=TRUE]])))
  brohn_require(length(bindings)<=1L,"Saved occurrence mixes section assignments.")
  .brohn_ph_expect(manifest,c(identity,list(id=id,first_question_step_id=members[[1L]]$id,
    stimulus_id=members[[1L]]$stimulus_id,condition_id=members[[1L]]$condition_id,review_step_id=review,
    section_assignment_id=if(length(bindings))bindings[[1L]]else NULL,dependencies=dependencies,dependency_graph_hash=.brohn_ph_hash(dependencies))),"complete occurrence/dependency graph")
  for(s in members).brohn_ph_expect(s$questionnaire_occurrence_id,id,"question occurrence link")
  list(id=review,type="questionnaire_review",phase="active_response",questionnaire_occurrence_id=id,
    stimulus_id=members[[1L]]$stimulus_id,condition_id=members[[1L]]$condition_id)
}
.brohn_ph_equipment <- function(p) {
  d<-p$design;e<-d$participant_equipment
  tasks<-Filter(function(s)s$type=="task",p$timeline)
  codes<-sort(unique(unlist(lapply(tasks,function(s)unlist(lapply(s$task$timeline,function(t)t[["allowed_codes",exact=TRUE]]))),use.names=FALSE)))
  list(schema="brohn-participant-equipment-requirements/1.0",policy_hash=.brohn_ph_hash(e),freshness_ms=e$freshness_ms,first_write_wait_ms=e$first_write_wait_ms,
    camera=isTRUE(e$camera)&&!is.null(d$camera),audio=isTRUE(e$camera)&&isTRUE(d$camera$audio),required_codes=if(isTRUE(e$keyboard))as.list(codes)else list(),
    controls=isTRUE(e$controls)&&any(vapply(p$timeline,function(s)s$type %in% c("question","maxdiff")&&!identical(s[["question",exact=TRUE]]$type,"information"),logical(1))))
}
.brohn_ph_choice_trial_id <- function(value,hash,allocation,position) {
  prefix<-paste0("md-",hash,"-");suffix<-paste0("-",position)
  brohn_require(brohn_text(value,160)&&startsWith(value,prefix)&&endsWith(value,suffix),"Saved choice trial identity differs.")
  token<-substr(value,nchar(prefix)+1L,nchar(value)-nchar(suffix))
  # Original paste0 could retain integer decimal or double scientific spelling
  # (the accepted allocation1e9 fixture uses 1e+09). Never rewrite that token
  # from a decoded integer or today's scipen option.
  brohn_require(grepl("^[1-9][0-9]*$|^[1-9](\\.[0-9]*[1-9])?e\\+[0-9]{2}$",token)&&
    isTRUE(suppressWarnings(as.numeric(token))==allocation),"Saved choice allocation token differs.")
  value
}
brohn_validate_saved_evidence_protocol <- function(protocol) {
  .brohn_ph_domain(protocol)
  brohn_fields(protocol,c("schema_version","design","design_hash","allocation_index","realized_stimulus_order","timeline","timing_evidence"),
    c("questionnaire_assignments","questionnaire_occurrences","equipment"),"Saved evidence protocol")
  brohn_require(identical(protocol$schema_version,"brohn-protocol/1.1.0"),"This reader accepts only saved evidence protocol1.1.")
  brohn_validate_evidence_design(protocol$design,publish=TRUE)
  d<-protocol$design;p<-protocol
  brohn_require(.brohn_ph_sha(p$design_hash)&&brohn_number(p$allocation_index,1,1e9,TRUE),"Keep the original full-design hash and allocation.")
  .brohn_ph_expect(p$design_hash,.brohn_ph_hash(d),"complete retained design protocol-json/0.1 binding")
  .brohn_ph_expect(p$timing_evidence,"browser_observation_not_physical_qualification","timing evidence status")
  sectioned<-"questionnaire_sections" %in% names(d);navigation<-"questionnaire_navigation" %in% names(d)
  for(f in c("questionnaire_assignments","questionnaire_occurrences","equipment")) {
    expected<-switch(f,questionnaire_assignments=sectioned,questionnaire_occurrences=navigation,equipment=!is.null(d[["participant_equipment",exact=TRUE]]))
    brohn_require(identical(f %in% names(p),expected),paste("Saved optional field presence differs:",f))
    if(expected&&f!="equipment")brohn_require(brohn_array(p[[f,exact=TRUE]]),paste("Saved",f,"must be an array."))
  }
  brohn_require(brohn_array(p$timeline)&&length(p$timeline)<=20000L,"Saved timeline exceeds the supported step bound.")
  for(s in p$timeline)brohn_require(is.list(s)&&brohn_text(s$type,64)&&brohn_valid_id(s$id),"Saved step has no valid identity/type.")
  brohn_require(!anyDuplicated(brohn_ids(p$timeline)),"Saved timeline repeats a step identity.")
  .brohn_ph_permutation(p$realized_stimulus_order,as.list(brohn_ids(d$stimuli)),"stimulus order")
  order<-unlist(p$realized_stimulus_order,use.names=FALSE)
  if(d$order=="fixed") .brohn_ph_expect(p$realized_stimulus_order,as.list(brohn_ids(d$stimuli)),"fixed stimulus order")
  if(length(order)&&d$order=="counterbalanced") {
    ids<-brohn_ids(d$stimuli);expected<-c(ids,ids)[seq.int(((p$allocation_index-1L)%%length(ids))+1L,length.out=length(ids))]
    .brohn_ph_expect(p$realized_stimulus_order,as.list(expected),"cyclic stimulus order")
  }
  .brohn_ph_timeline_validated(protocol, order)
}
# Internal timeline walk only. Each public entry validates its complete original
# design, schema, hash, optional fields and exact admitted order before this call.
.brohn_ph_timeline_validated <- function(protocol, order) {
  d<-protocol$design;p<-protocol
  sectioned<-"questionnaire_sections" %in% names(d);navigation<-"questionnaire_navigation" %in% names(d)
  cursor<-0L;original_index<-0L;assignment_index<-0L;occurrence_index<-0L
  take<-function() {cursor<<-cursor+1L;brohn_require(cursor<=length(p$timeline),"Saved timeline is incomplete.");p$timeline[[cursor]]}
  check_step<-function(expected,actual=NULL) {
    if(is.null(actual))actual<-take()
    original_index<<-original_index+1L;expected$id<-paste0("step-",original_index)
    .brohn_ph_expect(actual,expected,"complete original step")
    actual
  }
  questions<-function(scope,stimulus=NULL,anchor=NULL) {
    sid<-if(is.null(stimulus))NULL else stimulus$id;cid<-if(is.null(stimulus))NULL else stimulus$condition_id
    if(sectioned) {
      assignment_index<<-assignment_index+1L
      brohn_require(assignment_index<=length(p$questionnaire_assignments),"Saved section assignment is missing.")
      entries<-.brohn_ph_assignment(p$questionnaire_assignments[[assignment_index]],d,p$allocation_index,scope,stimulus,p$design_hash)
    } else entries<-lapply(Filter(function(q)q$scope==scope,d$questions),function(q)list(question=q,questionnaire=NULL))
    members<-list()
    for(entry in entries) {
      actual<-take();q<-entry$question
      brohn_require(identical(actual$type,"question")&&is.list(actual$question),"Saved questionnaire order/type differs.")
      assigned<-actual$question
      if(isTRUE(q$randomize_options)) {
        brohn_require(brohn_array(assigned$options)&&length(assigned$options)==length(q$options),"Saved option cardinality differs.")
        .brohn_ph_permutation(as.list(vapply(assigned$options,.brohn_ph_hash,character(1))),as.list(vapply(q$options,.brohn_ph_hash,character(1))),"complete option membership")
        q$options<-assigned$options
      }
      expected<-list(type="question",phase="active_response",question=q,stimulus_id=sid,condition_id=cid)
      if(!is.null(entry$questionnaire))expected$questionnaire<-entry$questionnaire
      if(navigation) {
        brohn_require(brohn_text(actual[["questionnaire_occurrence_id",exact=TRUE]],80),"Saved question occurrence link is missing.")
        expected$questionnaire_occurrence_id<-actual$questionnaire_occurrence_id
      }
      members[[length(members)+1L]]<-check_step(expected,actual)
    }
    if(navigation&&length(members)) {
      occurrence_index<<-occurrence_index+1L
      brohn_require(occurrence_index<=length(p$questionnaire_occurrences),"Saved occurrence manifest is missing.")
      review<-.brohn_ph_occurrence(p,members,scope,anchor,p$questionnaire_occurrences[[occurrence_index]])
      .brohn_ph_expect(take(),review,"questionnaire review step")
    }
    invisible(NULL)
  }
  if(nzchar(trimws(d$instructions)))check_step(list(type="instructions",phase="instructions",text=d$instructions))
  questions("before")
  for(id in order) {
    s<-brohn_find(d$stimuli,id)
    for(kind in c("baseline","fixation"))if(d[[paste0(kind,"_ms")]]>0)
      check_step(list(type=kind,phase=kind,duration_ms=d[[paste0(kind,"_ms")]],stimulus_id=s$id,condition_id=s$condition_id))
    anchor<-check_step(list(type="stimulus",phase="passive_viewing",stimulus=s,stimulus_id=s$id,condition_id=s$condition_id,duration_ms=s$duration_ms))
    questions("after_each",s,anchor)
  }
  for(block in d$blocks) {
    s<-take();brohn_require(identical(s$type,"task")&&is.list(s$task),"Saved task step is missing.")
    .brohn_ph_task_validated(s$task,block,p$allocation_index)
    check_step(list(type="task",phase="implicit_task",task=s$task),s)
  }
  for(exercise in d[["maxdiff",exact=TRUE]]) {
    seen<-character();hash<-.brohn_ph_hash(exercise)
    for(i in seq_along(exercise$sets)) {
      s<-take();c<-s[["choice",exact=TRUE]]
      brohn_require(identical(s$type,"maxdiff")&&is.list(c)&&brohn_text(c$set_id,96),"Saved choice step is missing.")
      set<-brohn_find(exercise$sets,c$set_id)
      brohn_require(!is.null(set)&&!c$set_id %in% seen,"Saved choice set is unknown or duplicated.")
      if(exercise$settings$set_order=="fixed").brohn_ph_expect(c$set_id,exercise$sets[[i]]$id,"fixed set order")
      .brohn_ph_permutation(c$item_order,set$item_ids,"choice item order")
      if(exercise$settings$item_order=="fixed").brohn_ph_expect(c$item_order,set$item_ids,"fixed item order")
      choice<-list(exercise_id=exercise$id,design_hash=hash,set_id=set$id,trial_id=.brohn_ph_choice_trial_id(c$trial_id,hash,p$allocation_index,i),position=i,
        item_order=c$item_order,items=lapply(c$item_order,function(id)brohn_find(exercise$items,id)),prompt=exercise$settings$prompt,
        best_label=exercise$settings$best_label,worst_label=exercise$settings$worst_label,required=exercise$settings$required)
      check_step(list(type="maxdiff",phase="explicit_choice",choice=choice),s);seen<-c(seen,set$id)
    }
  }
  questions("end")
  brohn_require(cursor==length(p$timeline)&&assignment_index==length(p[["questionnaire_assignments",exact=TRUE]])&&
    occurrence_index==length(p[["questionnaire_occurrences",exact=TRUE]]),"Saved timeline or manifest contains extra records.")
  total<-length(p$timeline)+sum(vapply(Filter(function(s)s$type=="task",p$timeline),function(s)length(s$task$timeline),integer(1)))
  brohn_require(total<=20000L,"Saved protocol exceeds the complete 20,000-step bound.")
  if("equipment" %in% names(p)).brohn_ph_expect(p$equipment,.brohn_ph_equipment(p),"equipment requirements")
  invisible(protocol)
}
brohn_evidence_revision_context <- function(protocol, original_protocol_hash) {
  brohn_require(.brohn_ph_sha(original_protocol_hash),"Supply the declared original protocol-byte SHA256.")
  brohn_validate_saved_evidence_protocol(protocol)
  brohn_require("questionnaire_navigation" %in% names(protocol$design),"This protocol uses forward-only questionnaire delivery.")
  .brohn_revision_context_maps(protocol,original_protocol_hash,.brohn_ph_hash(protocol$design$questionnaire_navigation))
}

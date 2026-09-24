# Synthetic received journals through the actual receiver, not real participants.
brohn_answer_session_fixture <- function(store,n=8L,finish=TRUE) {
  d<-brohn_new_design("Original saved answer session fixture","survey");d$instructions<-"";d$participant_equipment<-NULL
  d$questions<-lapply(seq_len(n),function(i)brohn_question(paste("Original product response",i),"long_text","end",paste0("original-item-",i)))
  d$questionnaire_navigation<-brohn_questionnaire_navigation();brohn_put_entity(store,"study",d$id,d)
  release<-brohn_publish(store,d$id,origin="sample",quota=5L)
  first<-.brohn_delivery_start(store,release$token,list(consented=TRUE,client_id=brohn_id("synthetic-client"),participant_alias="SYNTHETIC-ANSWER-SESSION",operation_id=brohn_id("start")))
  p<-first$protocol;ctx<-.brohn_delivery_revision_context(p);state<-.brohn_delivery_revision_initial(.brohn_delivery_initial_state(),ctx)
  manifest<-p$questionnaire_occurrences[[1L]];journal<-list();occ<-function()state$questionnaire$occurrences[[manifest$id]]
  emit<-function(kind,sid,extra){item<-occ();step<-brohn_find(p$timeline,sid);seq<-length(journal)+1L
    e<-list(sequence=seq,id=paste0("original-event-",seq),type="questionnaire_event",step_id=sid,stimulus_id=step$stimulus_id,condition_id=step$condition_id,
      question_id=if(step$type=="question")step$question$id else NULL,phase=step$phase,
      clock=list(id="browser-monotonic",unit="ms",value=as.character(seq*100),instance_id="original-synthetic-page",time_origin_ms="1000000"),
      payload=c(list(schema="brohn-questionnaire-event/1.0",kind=kind,occurrence_id=manifest$id,state_version=if(is.null(item))0L else item$version),extra))
    state<<-.brohn_delivery_apply(state,e,p,ctx);journal[[length(journal)+1L]]<<-e
  }
  visit<-function(sid,reason)emit("visit",sid,list(visit_id=paste0("original-visit-",length(journal)+1L),reason=reason,from_visit_id=occ()$visit$id))
  ids<-unlist(manifest$question_step_ids,use.names=FALSE)
  for(pass in 1:2){visit(ids[[1L]],if(pass==1L)"enter"else"edit")
    for(i in seq_along(ids)){row<-occ()$records[[ids[[i]]]];emit("commit",ids[[i]],list(visit_id=occ()$visit$id,previous_answer_event_id=row$last_answer_event_id,
      dependency_generation=row$dependency_generation,value=paste0(if(i==1L)strrep("\u00e9\u6f22<safe>\n",600L)else"Original answer ",pass,"/",i),response_time_ms=if(pass==1L)100 else NULL,active_segment_response_ms=100,resumed=FALSE))
      visit(if(i<length(ids))ids[[i+1L]]else manifest$review_step_id,"next")}}
  packet<-.brohn_delivery_receive(store,first$run_id,first$access_token,list(operation_id=brohn_id("batch"),events=journal))$questionnaire
  emit("seal",manifest$review_step_id,list(visit_id=occ()$visit$id,projection_hash=packet$latest_occurrence$projection_hash))
  .brohn_delivery_receive(store,first$run_id,first$access_token,list(operation_id=brohn_id("seal"),events=tail(journal,1L)))
  e<-list(sequence=length(journal)+1L,id="original-ending",type="run_finished",step_id=NULL,stimulus_id=NULL,condition_id=NULL,question_id=NULL,phase="session",
    clock=list(id="browser-monotonic",unit="ms",value=as.character((length(journal)+1L)*100),instance_id="original-synthetic-page",time_origin_ms="1000000"),payload=list(outcome="completed"))
  .brohn_delivery_receive(store,first$run_id,first$access_token,list(operation_id=brohn_id("end"),events=list(e)));journal<-c(journal,list(e))
  if(finish){.brohn_delivery_finish(store,first$run_id,first$access_token,list(operation_id=brohn_id("finish"),outcome="completed",final_sequence=e$sequence))
    job<-brohn_list_jobs(store,request_filters=list(run_id=first$run_id))[[1L]];brohn_cancel_job(store,job$id)}
  list(design=d,run_id=first$run_id,release_id=release$id,journal=journal,protocol=p,source_hash=brohn_hash(journal))
}

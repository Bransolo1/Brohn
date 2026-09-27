# Bind researcher event choices to the precise original page and recording.
# Choices never contain authority-bearing typed timestamp replacements.
.brohn_clock_choice <- function(x) {
  brohn_fields(x,c("page","sequence"),label="Chosen original event")
  .brohn_cm_ref_valid(x$page)
  brohn_require(brohn_number(x$sequence,1,2000000,TRUE),"Choose an original event row from its saved page.")
  x
}
brohn_clock_event_label <- function(event,maximum=90L) {
  value<-brohn_default(event$value_json,"Unavailable original value")
  if(nchar(value,type="chars")>maximum)value<-paste0(substr(value,1L,maximum),"\u2026")
  paste(value,paste("row",event$source_sequence),paste(brohn_default(event$source_timestamp,"No original time"),event$timestamp_unit),sep=" | ")
}
brohn_clock_selected_preview <- function(store,source,reference,anchors,checks,review,project_id,enqueue=FALSE,retry=FALSE) {
  brohn_require(brohn_array(anchors)&&length(anchors)==2L&&brohn_array(checks)&&length(checks)<=16L,
    "Match the two defining event pairs and at most sixteen independent checks.")
  # The immediate transaction keeps page and recording catalog reads on one
  # consistent snapshot until the prepared job is enqueued. Original bytes are
  # reverified later under the unchanged supervised source guards.
  brohn_store_batch(store,function(){
    selections<-list(source=source,reference=reference)
    recordings<-lapply(selections,function(s).brohn_clock_select_recording(store,s,project_id))
    pages<-new.env(parent=emptyenv())
    resolve<-function(choice,side) {
      choice<-.brohn_clock_choice(choice);key<-brohn_hash(choice$page)
      if(!exists(key,envir=pages,inherits=FALSE))pages[[key]]<-brohn_clock_events_record(store,choice$page,project_id,FALSE)
      page<-pages[[key]]
      brohn_require(.brohn_cm_same(page$body$request$selection,selections[[side]])&&
        .brohn_cm_same(page$body$request$recording,recordings[[side]]),
        "A chosen event belongs to an earlier recording or channel selection. Load its current recorded events and choose the pair again.")
      events<-Filter(function(e)e$source_sequence==choice$sequence,page$body$result$events)
      brohn_require(length(events)==1L&&isTRUE(events[[1L]]$selectable),"This exact original event is absent or cannot define an anchor.")
      events[[1L]]
    }
    evidence<-lapply(c(anchors,checks),function(pair){brohn_fields(pair,c("source","reference"),label="Original event correspondence")
      list(source=resolve(pair$source,"source"),reference=resolve(pair$reference,"reference"))})
    pairs<-lapply(evidence,function(pair)list(source_sequence=pair$source$source_sequence,reference_sequence=pair$reference$source_sequence))
    defining<-pairs[1:2];held_out<-if(length(pairs)>2L)pairs[-c(1L,2L)]else list()
    preview<-brohn_prepare_clock_preview(store,source,reference,defining,held_out,review,project_id)
    brohn_require(.brohn_cm_same(preview$recordings,recordings),"The original recordings changed while preparing this matched-event preview.")
    if(isTRUE(enqueue))return(brohn_queue_clock_preview(store,source,reference,defining,held_out,review,project_id,retry))
    list(request=preview,events=evidence,choices=list(anchors=anchors,checks=checks))
  })
}

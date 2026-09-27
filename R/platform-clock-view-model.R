# Small, bounded researcher-facing models. Original event/measurement values
# stay strings; display approximations never become input coordinates.
.brohn_clock_integer_divide <- function(value,divisor) {
  digits<-utf8ToInt(value)-48L;carry<-0L;out<-integer(length(digits))
  for(i in seq_along(digits)){v<-carry*10L+digits[[i]];out[[i]]<-v%/%divisor;carry<-v%%divisor}
  quotient<-sub("^0+(?=[0-9])","",paste0(out,collapse=""),perl=TRUE)
  list(quotient=quotient,remainder=carry)
}
.brohn_clock_integer_multiply <- function(value,multiplier) {
  digits<-rev(utf8ToInt(value)-48L);carry<-0L;out<-integer(length(digits))
  for(i in seq_along(digits)){v<-digits[[i]]*multiplier+carry;out[[i]]<-v%%10L;carry<-v%/%10L}
  paste0(if(carry)as.character(carry)else"",paste0(rev(out),collapse=""))
}
brohn_clock_exact_decimal <- function(fraction) {
  brohn_fields(fraction,c("numerator","denominator"),label="Exact clock fraction")
  n<-fraction$numerator;d<-fraction$denominator
  brohn_require(brohn_text(n,2048)&&grepl("^-?(0|[1-9][0-9]*)$",n)&&
    brohn_text(d,2048)&&grepl("^[1-9][0-9]*$",d),"Retain the accepted exact clock fraction.")
  negative<-startsWith(n,"-");n<-sub("^-","",n);twos<-0L;fives<-0L
  # Accepted anchor coordinates and declared scales are finite decimals. Fail
  # rather than round if a different future profile supplies another fraction.
  repeat {part<-.brohn_clock_integer_divide(d,2L);if(part$remainder!=0L)break;d<-part$quotient;twos<-twos+1L}
  repeat {part<-.brohn_clock_integer_divide(d,5L);if(part$remainder!=0L)break;d<-part$quotient;fives<-fives+1L}
  brohn_require(identical(d,"1"),"This exact span needs explicit supported window bounds; it cannot be rounded into a default.")
  places<-max(twos,fives)
  for(i in seq_len(places-twos))n<-.brohn_clock_integer_multiply(n,2L)
  for(i in seq_len(places-fives))n<-.brohn_clock_integer_multiply(n,5L)
  if(places>0L){if(nchar(n)<=places)n<-paste0(strrep("0",places+1L-nchar(n)),n)
    at<-nchar(n)-places;n<-paste0(substr(n,1L,at),".",substring(n,at+1L));n<-sub("0+$","",n);n<-sub("\\.$","",n)}
  if(negative&&n!="0")n<-paste0("-",n)
  n
}
brohn_clock_initial_window <- function(mapping) {
  end<-brohn_clock_exact_decimal(mapping$reference_span_seconds)
  brohn_require(brohn_text(end,120)&&!startsWith(end,"-")&&end!="0","Choose a supported positive alignment span.")
  list(start_s="0",end_s=end,offset=0L)
}
brohn_clock_channel_choices <- function(store,dataset_ref,import_ref,project_id) {
  dataset<-.brohn_cm_pin(store,"dataset",dataset_ref,project_id)
  imported<-.brohn_cm_pin(store,"stream_import",import_ref,project_id)
  brohn_require(identical(imported$body$dataset_id,dataset$id),"Choose a preserved import belonging to this recording.")
  streams<-lapply(as.list(imported$body$stream_ids),function(id){r<-brohn_get_entity(store,"stream",id)
    if(is.null(r)||!identical(r$project_id,project_id)||isTRUE(r$body$archived))return(NULL);r})
  choices<-list(marker=character(),tracks=character())
  for(stream in Filter(Negate(is.null),streams)) {
    s<-stream$body$manifest;if(!s$kind %in% c("markers","signal"))next
    for(channel in s$channels){if(s$kind=="signal"&&!channel$value_type %in% c("float64","float32","int64","int32","int16","int8"))next
      value<-brohn_json(list(stream_id=stream$id,channel_id=channel$id))
      label<-paste(stream$body$title,channel$label,brohn_default(channel$unit,"unit not declared"),paste("clock",s$clock$id),sep=" | ")
      name<-if(s$kind=="markers")"marker"else"tracks"
      choices[[name]]<-c(choices[[name]],stats::setNames(value,label))}
  }
  choices
}
brohn_clock_preview_summary <- function(record) {
  r<-record$body$result;m<-r$mapping
  list(span_seconds=brohn_clock_exact_decimal(m$reference_span_seconds),
    checks=lapply(r$checks,function(check)list(source_row=check$source$source_sequence,reference_row=check$reference$source_sequence,
      signed_residual_seconds=paste(check$comparison$signed_mapped_minus_reference_residual_seconds$numerator,
        check$comparison$signed_mapped_minus_reference_residual_seconds$denominator,sep="/"),
      approximate_residual_seconds=check$comparison$display_approx_residual_seconds,
      within_anchor_span=isTRUE(check$comparison$reference_within_anchor_span))),
    evidence=m,uncertainty="Physical timing uncertainty is unknown. The defining pair fits by construction; held-out events are separate checks.")
}

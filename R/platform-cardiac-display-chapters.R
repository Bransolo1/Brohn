# One chapter spans selected reports in their frozen selection order. Required
# parent reports support lineage but are never added to this figure sequence.
brohn_cardiac_chapter_plan <- function(sources, chapters=NULL) {
  brohn_require(brohn_array(sources)&&length(sources)<=8L,"Choose at most eight original cardiac reports for these chapters.")
  chapters <- brohn_normalize_cardiac_figure_chapters(chapters)
  identities <- character();total <- 0
  for(source in sources) {
    brohn_fields(source,c("report_ref","closure_hash","record_count"),label="Cardiac chapter source")
    .brohn_rpk_ref_valid(source$report_ref,"report")
    brohn_require(.brohn_rpk_hash(source$closure_hash)&&brohn_number(source$record_count,0,2000,TRUE),"A cardiac chapter source has invalid closure or record counts.")
    identities <- c(identities,brohn_eda_value_hash(source$report_ref))
    total <- total+source$record_count
  }
  brohn_require(!anyDuplicated(identities)&&total<=2000L,"Choose each original report once within the complete cardiac record limit.")
  count <- ceiling(total/10)
  policy <- chapters$chapters
  numbers <- if(!count)list()else if(policy$mode=="all")as.list(seq_len(count))else if(policy$mode=="first")list(1)else policy$numbers
  if(policy$mode=="selected")brohn_require(all(unlist(policy$numbers,use.names=FALSE)<=count),"A selected cardiac chapter does not exist in these original reports.")
  membership <- list();offset <- 0L
  for(i in seq_along(sources)) {
    source <- sources[[i]];indices <- numeric()
    for(chapter in numbers) {
      start <- max(offset+1,10*(chapter-1)+1)
      end <- min(offset+source$record_count,10*chapter)
      if(start<=end) {
        indices <- c(indices,seq.int(start-offset,end-offset))
        membership[[length(membership)+1L]] <- list(chapter=chapter,report_ref=source$report_ref,
          source_record_start=start-offset,source_record_end=end-offset,study_record_start=start,study_record_end=end)
      }
    }
    sources[[i]]$selected_record_indices <- as.list(as.double(indices))
    offset <- offset+source$record_count
  }
  list(schema="brohn-cardiac-chapter-plan/0.1",request=chapters,total_cells=total,total_chapters=count,
    selected_chapters=numbers,selected_cells=sum(vapply(sources,function(s)length(s$selected_record_indices),integer(1))),
    membership=membership,sources=sources,complete_evidence_retained=TRUE)
}

brohn_cardiac_chapter_requests <- function(store,report_refs,chapters=NULL,display_requests=NULL,pulse=NULL) {
  brohn_require(brohn_array(report_refs)&&length(report_refs)<=8L,"Choose the ordered original cardiac reports.")
  if(is.null(display_requests))display_requests <- rep(list(NULL),length(report_refs))
  brohn_require(brohn_array(display_requests)&&length(display_requests)==length(report_refs),"Each cardiac report needs its own saved display choices.")
  sources <- lapply(report_refs,function(ref) {
    .brohn_rpk_source_pulse(pulse);m <- brohn_cardiac_source_metadata(store,ref)
    list(report_ref=ref,closure_hash=m$closure_hash,record_count=m$selected$record_count)
  })
  plan <- brohn_cardiac_chapter_plan(sources,chapters)
  resolved <- lapply(seq_along(plan$sources),function(i) {
    source <- plan$sources[[i]];indices <- unlist(source$selected_record_indices,use.names=FALSE)
    keys <- character();items <- list();pages <- unique(floor((indices-1)/100))
    for(page in pages) {
      .brohn_rpk_source_pulse(pulse)
      cursor <- if(page==0)NULL else list(scope=brohn_eda_value_hash(list(report_ref=source$report_ref,closure_hash=source$closure_hash)),offset=page*100)
      result <- brohn_cardiac_source_windows(store,source$report_ref,cursor,100L)
      brohn_require(identical(result$closure_hash,source$closure_hash)&&result$total==source$record_count,"The original source changed while resolving the cardiac chapter.")
      chosen <- Filter(function(x)x$source_record_index %in% indices,result$items)
      items <- c(items,chosen);keys <- c(keys,vapply(chosen,`[[`,character(1),"key"))
    }
    brohn_require(length(keys)==length(indices)&&!anyDuplicated(keys),"The selected chapter did not resolve every original cardiac record.")
    request <- brohn_normalize_cardiac_display_request(display_requests[[i]])
    # Chapters own the combined package figure membership. Per-cell time and
    # numerical choices remain unchanged, including those for evidence-only cells.
    request$figure_cells <- list(scope=if(length(keys))"exact_cells"else"no_cells",keys=as.list(keys))
    list(report_ref=source$report_ref,closure_hash=source$closure_hash,
      display_request=brohn_normalize_cardiac_display_request(request),selected_cells=items)
  })
  for(source in sources){.brohn_rpk_source_pulse(pulse);brohn_require(identical(brohn_cardiac_source_metadata(store,source$report_ref)$closure_hash,source$closure_hash),"A selected cardiac source changed before chapter resolution completed.")}
  list(schema="brohn-cardiac-resolved-chapters/0.1",plan=plan,reports=resolved)
}

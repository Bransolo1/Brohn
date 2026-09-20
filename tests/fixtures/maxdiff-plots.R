# Exact paired-logit likelihood frequencies proportional to exp(u_best-u_worst).
brohn_original_maxdiff_plot_fixture <- function() {
  d<-brohn_maxdiff_new("Original three-feature choice evidence","original-plot-exercise")
  d$items<-head(d$items,3);d$items[[1]]$label<-"Researcher <b>original</b> feature with a long exact label"
  d$items[[2]]$label<-"Second feature";d$items[[3]]$label<-"Third feature"
  d$sets<-list(list(id="all",item_ids=as.list(brohn_ids(d$items))))
  pairs<-list(c(1,2,9),c(1,3,18),c(2,1,4),c(2,3,12),c(3,1,2),c(3,2,3));rows<-list()
  for(pair in pairs)for(j in seq_len(pair[3])){
    i<-length(rows)+1L;rows[[i]]<-list(id=paste0("response-",i),participant_id="anonymous-one",participant_linkage=FALSE,session_id="original-session",exposure_id=paste0("exposure-",i),
      design_hash=brohn_hash(d),set_id="all",item_order=d$sets[[1]]$item_ids,presented=TRUE,status="answered",best_id=paste0("item-",pair[1]),worst_id=paste0("item-",pair[2]),missing_reason=NULL)
  }
  missing<-rows[[1]];missing$id<-"missing";missing$exposure_id<-"missing";missing$status<-"missing";missing[c("best_id","worst_id")]<-list(NULL,NULL);missing$missing_reason<-"Original omitted choice"
  result<-brohn_maxdiff_analysis(d,c(rows,list(missing)))
  empty<-brohn_maxdiff_analysis(d,list(missing))
  list(result=result,empty=empty,expected_utilities=as.list(log(c(3,2,1))-mean(log(c(3,2,1)))))
}

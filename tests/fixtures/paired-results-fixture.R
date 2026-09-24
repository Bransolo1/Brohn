# Original synthetic arithmetic, written before any plotted output exists.
# P1: visit differences 2 and 6 -> person difference 4; P2=8; P3=12.
# P4 has no test value. Equal-person B-A estimate=8; pooled visits=7.
researcher_paired_fixture <- function() {
  d<-brohn_new_design("Original paired-results researcher QA",id="qa-paired-study")
  d$questions<-list(brohn_question("How much do you like this concept?","number","after_each","q-liking"))
  d$questions[[1]]$min<-0;d$questions[[1]]$max<-100;d$questions[[1]]$step<-1;d$questions[[1]]$required<-FALSE
  d$conditions[[3]]<-list(id="condition-c",label="Alternative concept",role="test")
  d$stimuli[[3]]<-d$stimuli[[2]];d$stimuli[[3]]$id<-"stimulus-c";d$stimuli[[3]]$condition_id<-"condition-c";d$stimuli[[3]]$title<-"Alternative concept"
  for(i in 1:3){d$stimuli[[i]]$content<-paste("Original concept",i);d$stimuli[[i]]$aois<-list(list(id=paste0("logo-",i),label="Logo",x=0,y=0,width=.5,height=1))}
  original<-list(c("P1","V1","a","10"),c("P1","V1","a","14"),c("P1","V1","b","14"),c("P1","V1","c","18"),
    c("P1","V2","a","10"),c("P1","V2","b","16"),c("P1","V2","c","22"),
    c("P2","V3","a","10"),c("P2","V3","b","18"),c("P2","V3","c","24"),
    c("P3","V4","a","10"),c("P3","V4","b","22"),c("P3","V4","c","26"),
    c("P4","V5","a","10"),c("P4","V5","b",NA_character_),c("P4","V5","c",NA_character_))
  responses<-lapply(seq_along(original),function(i){r<-original[[i]];list(participant_id=r[1],session_id=r[2],
    condition_id=paste0("condition-",r[3]),stimulus_id=paste0("stimulus-",r[3]),exposure_id=paste0("exposure-",i),
    question_id="q-liking",prompt=d$questions[[1]]$prompt,value=if(is.na(r[4]))NULL else as.numeric(r[4]),
    missing_reason=if(is.na(r[4]))"optional_omission"else NULL)})
  gaze<-lapply(responses,function(r)c(r[c("participant_id","session_id","condition_id","stimulus_id","exposure_id")],
    list(aoi_id=paste0("logo-",match(r$condition_id,paste0("condition-",letters[1:3]))),aoi_label="Logo",
      valid_share_percent=r$value,valid_ms=if(is.null(r$value))0 else 1000,inside_ms=if(is.null(r$value))0 else r$value*10,
      denominator="valid gaze interval time; off-stimulus observations retained")))
  list(design=d,responses=responses,gaze=gaze,expected=list(person_ids=list("P1","P2","P3"),person_differences=list(4,8,12),
    control_means=list(11,10,10),test_means=list(15,18,22),estimate=8,paired_people=3,paired_visits=4,unpaired_visits=1,
    alternative_estimate=13,selected_sources=11,source_total=16))
}

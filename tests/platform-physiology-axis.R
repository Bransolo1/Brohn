# Display-label regression: source positions and saved numerical values do not change.
source("R/platform-load.R",encoding="UTF-8");brohn_load(ui=TRUE)
args<-commandArgs(trailingOnly=TRUE);folder<-if(length(args))args[[1]]else tempfile("brohn-physiology-axis-")
stopifnot(!dir.exists(folder));dir.create(folder,recursive=TRUE)
checks<-character();check<-function(label,value){stopifnot(isTRUE(value));checks<<-c(checks,label);cat("PASS",label,"\n")}
for(family in c("respiration","emg")) {
  tick<-get(paste0(".brohn_",if(family=="emg")"mr"else"rr","_axis_ticks"))
  for(bounds in list(c(100,101),c(500,501))) {
    axis<-tick(bounds[[1]],bounds[[2]],TRUE)
    check(paste(family,"retains distinct half-second labels at",bounds[[1]]),identical(axis$values,seq(bounds[[1]],bounds[[2]],length.out=3))&&
      length(unique(axis$labels))==3&&is.null(axis$offset)&&identical(as.numeric(axis$labels),axis$values))
  }
  for(bounds in list(c(1e12-1,1e12-.999),c(1,1+.Machine$double.eps))) {
    axis<-tick(bounds[[1]],bounds[[2]],TRUE)
    check(paste(family,"large-origin or adjacent-float labels disclose their base",format(bounds[[1]],digits=17)),
      identical(axis$values,unique(seq(bounds[[1]],bounds[[2]],length.out=3)))&&!anyDuplicated(axis$labels)&&identical(axis$offset,bounds[[1]])&&max(nchar(axis$labels))<=12)
  }
  for(bounds in list(c(0,60),c(0,1e-9))) {
    axis<-tick(bounds[[1]],bounds[[2]],FALSE)
    check(paste(family,"wide labels retain distinct positions at span",bounds[[2]]),length(axis$values)==5&&!anyDuplicated(axis$labels)&&is.null(axis$offset))
  }
  value_labels<-get(paste0(".brohn_",if(family=="emg")"mr"else"rr","_axis_labels"))
  for(values in list(c(4.339,4.340,4.341),c(.2936,.2938,.294),c(1e12,1e12+.001,1e12+.002))) {
    axis<-value_labels(values,8L)
    check(paste(family,"narrow Y labels distinguish retained positions",format(values[[1]],digits=17)),identical(axis$values,values)&&!anyDuplicated(axis$labels)&&max(nchar(axis$labels))<=8L)
    if(!is.null(axis$offset))check(paste(family,"large Y origin retains an explicit exact base"),identical(axis$offset,values[[1]]))
  }
  number<-get(paste0(".brohn_",if(family=="emg")"mr"else"rr","_number"))
  check(paste(family,"human settings use shortest round-tripping display"),identical(number(.05),"0.05")&&identical(number(.1),"0.1")&&identical(number(59.998),"59.998"))
  fixture<-list(binding=list(fixture="display-only"),selection=list(start_s="100",end_s="101"),recording=list(start_time_s=0,end_time_s=65),
    parameters=list(burst_threshold_uv=NULL),counts=list(),cycles=list(),bursts=list(),markers=list(),series=list(),verification=list(),unit="L",raw_available=TRUE)
  svg<-get(paste0("brohn_",family,"_review_svg"))(fixture,320L)
  check(paste(family,"standalone SVG keeps explicit source positions and corrected100.5 label"),grepl('data-time-tick="100.5"',svg,fixed=TRUE)&&grepl('>100.5</text>',svg,fixed=TRUE))
  writeLines(svg,file.path(folder,paste0(family,"-100.svg")),useBytes=TRUE)
  fixture$selection<-list(start_s="999999999999",end_s="999999999999.001")
  svg<-get(paste0("brohn_",family,"_review_svg"))(fixture,320L)
  check(paste(family,"standalone SVG declares the exact time offset base"),grepl('data-time-offset="999999999999"',svg,fixed=TRUE)&&grepl('Source time offset (s)',svg,fixed=TRUE)&&grepl('Add 999999999999 s to labels',svg,fixed=TRUE))
  writeLines(svg,file.path(folder,paste0(family,"-offset.svg")),useBytes=TRUE)
  fixture$selection<-list(start_s="100",end_s="101")
  points<-lapply(seq_len(3),function(i){p<-list(time_s=100+(i-1)/2);p[[if(family=="emg")"value"else"clean"]]<-1e12+(i-1)*.001;p})
  groups<-list(list(retained=TRUE,points=points))
  fixture$series<-if(family=="emg")stats::setNames(rep(list(groups),3),c("raw_uv","clean_uv","rms_uv"))else groups
  svg<-get(paste0("brohn_",family,"_review_svg"))(fixture,320L)
  check(paste(family,"SVG discloses Y base and exact original value positions"),grepl('data-value-tick="',svg,fixed=TRUE)&&grepl('data-value-offset="',svg,fixed=TRUE)&&grepl('to Y labels',svg,fixed=TRUE))
  writeLines(svg,file.path(folder,paste0(family,"-y-offset.svg")),useBytes=TRUE)

}
files<-c("R/platform-emg-review-views.R","R/platform-respiration-review-views.R")
brohn_write_json_file(list(passed=TRUE,checks=as.list(checks),code_hashes=stats::setNames(lapply(files,function(f)digest::digest(file=f,algo="sha256")),files),scope="Display-only vectors and SVG labels; no source processing or scoring."),file.path(folder,"results.json"))

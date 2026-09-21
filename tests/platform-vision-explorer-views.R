# Actual saved-index exports and pure production renderers. No inference rerun.
source("R/platform-load.R",encoding="UTF-8");brohn_load(ui=TRUE);source("R/platform-vision-explorer-views.R",encoding="UTF-8")
args<-commandArgs(trailingOnly=TRUE);stopifnot(length(args)==2L,!dir.exists(args[[2L]]))
local({
  baseline<-brohn_read_json_file(file.path(args[[1L]],"acceptance.json"));folder<-normalizePath(args[[2L]],winslash="/",mustWork=FALSE);dir.create(folder,recursive=TRUE)
  processx::run(.brohn_publication_python(),c("-B","-c","import shutil,sys;shutil.copytree(sys.argv[1],sys.argv[2])",baseline$workspace,file.path(folder,"workspace")),windows_hide_window=TRUE)
  store<-brohn_open_store(file.path(folder,"workspace"));opened<-list();exports<-list();checks<-character()
  on.exit({for(x in exports)try(brohn_close_vision_csv(x),silent=TRUE);for(x in opened)try(brohn_close_vision_index(x),silent=TRUE);brohn_close_store(store)})
  check<-function(ok,label){stopifnot(isTRUE(ok));checks<<-c(checks,label);cat("PASS",label,"\n");flush.console()}
  rejected<-function(x)inherits(tryCatch({force(x);NULL},error=identity),"error")
  await<-function(p){for(i in seq_len(100L)){s<-p$state;if(!is.null(s$process))s$process$wait(10000);r<-brohn_poll_vision_csv(store,p);if(!is.null(r))return(r)};stop("CSV did not finish")}
  for(family in names(baseline$cases)){
    c<-baseline$cases[[family]];v<-brohn_open_vision_index(store,c$index_id,c$index_hash,c$report_id,c$report_revision,c$report_hash,"default");opened[[length(opened)+1L]]<-v
    metric<-v$record$body$manifest$metrics[[1L]];selection<-list(metric=metric$id,range=NULL)
    p<-brohn_begin_vision_csv(store,v,selection);exports[[length(exports)+1L]]<-p
    check(rejected(brohn_vision_csv_manifest(p)),paste(family,"pending CSV cannot expose an unverified manifest"))
    result<-await(p);manifest<-brohn_vision_csv_manifest(p);rows<-read.csv(result$path,colClasses="character",check.names=FALSE)
    check(nrow(rows)==4L&&identical(rows$source_pts_s,c("2.000000","2.200000","2.400000","2.600000")),paste(family,"complete async CSV preserves all original PTS lexemes"))
    check(manifest$metric$unit==metric$unit&&manifest$csv$rows==4L&&manifest$csv$sha256==digest::digest(file=result$path,algo="sha256")&&
      manifest$source$report_id==c$report_id&&manifest$source$original_source$hash==v$record$body$binding$original_source$hash,paste(family,"companion manifest binds complete bytes, exact source and metric units"))
    expected_path<-file.path(folder,paste0(family,"-oracle.json"));code<-paste("import json,sys;rows=[json.loads(x,parse_int=str,parse_float=str) for x in open(sys.argv[1])];parts=sys.argv[2].split('.');family=parts[0];values=[]",
      "for r in rows:"," if family=='face':value=r[family]['blendshapes'][parts[2]] if parts[1]=='blendshape' else r[family]['geometry'][parts[1]]",
      " elif family=='pose':value=r[family]['geometry'][parts[1]]"," else:value=next(h['geometry'][parts[2]] for h in r[family]['hands'] if h['handedness']==parts[1])",
      " values.append(value)","open(sys.argv[3],'w').write(json.dumps(values))",sep="\n")
    processx::run(.brohn_publication_python(),c("-B","-c",code,v$authority$artifact_path,metric$id,expected_path),windows_hide_window=TRUE)
    check(identical(rows$value,unlist(brohn_read_json_file(expected_path),use.names=FALSE)),paste(family,"every exported metric token equals its native original field"))
    detail<-brohn_vision_index_read(store,v,"detail",list(frame_index=2L));points<-brohn_vision_native_points(detail,family)
    check(length(points)==switch(family,face=478L,pose=33L,hands=21L),paste(family,"geometry renderer uses every saved native point without invented joints"))
    markup<-as.character(brohn_vision_geometry_svg(detail,family));check(grepl("No recorded frame shown",markup,fixed=TRUE)&&!grepl("<image",markup,fixed=TRUE),paste(family,"coordinate-only fallback cannot imply a recorded image"))
    plot<-brohn_vision_index_read(store,v,"plot",list(channel=family,metric=metric$id));figure<-as.character(brohn_vision_plot_svg(plot,300))
    check(grepl("Recording-relative time",figure,fixed=TRUE)&&grepl("Observed frame states",figure,fixed=TRUE)&&grepl(metric$unit,figure,fixed=TRUE),paste(family,"narrow figure preserves units, source clock and state view"))
    directory<-p$directory;brohn_close_vision_csv(p)
    check(!dir.exists(directory)&&rejected(brohn_poll_vision_csv(store,p)),paste(family,"closing async export releases and removes only its owned work"))
    cancelled<-brohn_begin_vision_csv(store,v,selection);exports[[length(exports)+1L]]<-cancelled;brohn_close_vision_csv(cancelled)
    check(!dir.exists(cancelled$directory)&&rejected(brohn_vision_csv_manifest(cancelled)),paste(family,"cancelled CSV never becomes downloadable"))
    brohn_close_vision_index(v)
  }
  brohn_write_json_file(list(checks=checks,workspace=store$root),file.path(folder,"results.json"));cat("PASS",length(checks),"vision UI helper checks\n")
})

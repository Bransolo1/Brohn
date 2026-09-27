# Pure detached report assembly; caller owns and holds source/asset resources.
.brohn_rp_style <- paste0(
  "*{box-sizing:border-box}body{margin:auto;max-width:1080px;padding:28px;background:#11171c;color:#edf2f2;font:16px/1.6 system-ui,sans-serif;overflow-wrap:anywhere}",
  "main,section,figure{min-width:0}h1,h2,h3{line-height:1.25}h1{font-size:2rem}h2{font-size:1.5rem}h3{font-size:1.15rem}",
  "section{background:#192229;border:1px solid #415057;border-radius:14px;padding:24px;margin:24px 0}.muted{color:#bdcbd0}a{color:#ade9d7}",
  "a:focus-visible,summary:focus-visible{outline:3px solid #ade9d7;outline-offset:4px}.skip{display:inline-block}table{border-collapse:collapse;width:100%;font-size:.9rem}",
  "td,th{padding:8px;text-align:left;border-bottom:1px solid #52636c;vertical-align:top;overflow-wrap:anywhere}caption{text-align:left;color:#bdcbd0;padding:8px 0}",
  ".table-scroll{overflow:auto;max-width:100%}img,svg{max-width:100%;height:auto}figure{margin:16px 0}figcaption{color:#bdcbd0}summary{cursor:pointer}pre{white-space:pre-wrap;overflow-wrap:anywhere}",
  ".notice{border-left:3px solid #ade9d7;padding-left:16px}.compact{display:none}@media(max-width:560px){body{padding:14px}section{padding:16px}h1{font-size:1.6rem}.wide{display:none}.compact{display:block}}",
  "@media print{body{background:white;color:#111;padding:0}section{background:white;border-color:#666;break-inside:avoid}a,.muted,caption,figcaption{color:#222}svg{max-height:none!important}}")
.brohn_rp_number <- function(x)if(is.null(x))"Unavailable"else if(is.numeric(x)&&length(x)==1L)
  if(x==trunc(x))format(x,digits=17,trim=TRUE,scientific=FALSE)else
    format(signif(x,4),digits=4,trim=TRUE,scientific=abs(x)>=1e6||(x!=0&&abs(x)<.001))else as.character(x)
.brohn_rp_text <- function(x)if(is.null(x))"Unavailable"else if(is.character(x)&&length(x)==1L)x else if(is.numeric(x)&&length(x)==1L).brohn_rp_number(x)else brohn_json(x)
.brohn_rp_friendly <- function(x) {
  if(!is.character(x)||length(x)!=1L||!grepl("^report-[0-9]+-(person|session|exposure)-[0-9]+$",x))return(x)
  kind<-sub("^report-[0-9]+-([a-z]+)-[0-9]+$","\\1",x)
  paste(switch(kind,person="Person",session="Visit",exposure="Exposure"),as.integer(sub("^.*-([0-9]+)$","\\1",x)))
}
.brohn_rp_paired_svg <- function(model,page,chart,width,friendly=FALSE) {
  # Bind only the human label formatter locally. Coordinates, model metadata,
  # saved evidence and the full-precision CSV formatter remain unchanged.
  render<-brohn_paired_plot_svg
  environment(render)<-list2env(list(.brohn_pp_num=.brohn_rp_number),parent=environment(brohn_paired_plot_svg))
  svg<-render(model,page,chart,width)
  if(friendly){
    display<-function(node){if(inherits(node,"shiny.tag")){
      person<-node$attribs[["data-person"]]
      if(!is.null(person))node$children<-lapply(node$children,function(child){
        if(inherits(child,"shiny.tag")&&child$name=="title")child$children<-lapply(child$children,function(text){
          if(is.character(text)&&length(text)==1L&&startsWith(text,paste0(person," ")))paste0(.brohn_rp_friendly(person),substring(text,nchar(person)+1L))else text
        });child
      })
      node$children<-lapply(node$children,display)
    }else if(is.list(node))node<-lapply(node,display);node};svg<-display(svg)
  };svg
}
.brohn_rp_table <- function(rows,title,columns=NULL,maximum=12L,friendly=FALSE) {
  if(is.null(columns))columns<-unique(unlist(lapply(rows,names),use.names=FALSE))
  shown<-head(rows,maximum)
  if(!length(rows))return(shiny::p(paste(title,": no saved records; no values were invented.")))
  shiny::div(class="table-scroll",shiny::tags$table(shiny::tags$caption(paste(title,"\u2014",length(shown),"of",length(rows),"saved rows shown. Non-integer summaries are rounded to four significant figures; exact values and complete collections are in the evidence ZIP.")),
    shiny::tags$thead(shiny::tags$tr(lapply(columns,function(k)shiny::tags$th(scope="col",gsub("_"," ",k))))),
    shiny::tags$tbody(lapply(shown,function(row)shiny::tags$tr(lapply(columns,function(k){
      identity<-friendly&&k%in%c("participant_id","person_id","session_id","exposure_id")
      shiny::tags$td(`data-saved-id`=if(identity)row[[k]]else NULL,.brohn_rp_text(if(identity).brohn_rp_friendly(row[[k]])else row[[k]]))
    }))))))
}
.brohn_rp_namespace_svg <- function(svg,prefix) {
  brohn_require(inherits(svg,"shiny.tag")&&identical(svg$name,"svg")&&grepl("^[a-z][a-z0-9-]*$",prefix),"A figure must contain an actual trusted SVG root.")
  ids<-character()
  collect<-function(node){if(inherits(node,"shiny.tag")){
    brohn_require(!tolower(node$name)%in%c("script","foreignobject"),"Executable SVG content is not allowed.")
    if(!is.null(node$attribs$id))ids<<-c(ids,node$attribs$id)
    for(child in node$children)collect(child)
  }else if(is.list(node))for(child in node)collect(child)}
  collect(svg);brohn_require(!anyDuplicated(ids)&&all(grepl("^[A-Za-z][A-Za-z0-9_-]*$",ids)),"SVG contains duplicate or malformed identifiers.")
  mapped<-setNames(paste0(prefix,"-",seq_along(ids)),ids)
  replace<-function(node){if(inherits(node,"shiny.tag")){
    if(!is.null(node$attribs$id))node$attribs$id<-unname(mapped[[node$attribs$id]])
    for(k in names(node$attribs)){
      value<-node$attribs[[k]]
      brohn_require(!grepl("^on",k,ignore.case=TRUE),"SVG event handlers are not allowed.")
      if(k%in%c("aria-labelledby","aria-describedby")){
        refs<-strsplit(value," +")[[1L]];brohn_require(all(refs%in%ids),"SVG accessibility reference is unresolved.")
        node$attribs[[k]]<-paste(unname(mapped[refs]),collapse=" ")
      }else if(k%in%c("href","xlink:href")){
        if(startsWith(value,"#")){ref<-substring(value,2L);brohn_require(ref%in%ids,"SVG local reference is unresolved.");node$attribs[[k]]<-paste0("#",mapped[[ref]])}
        else brohn_require(node$name=="image"&&grepl("^data:image/(png|jpeg);base64,[A-Za-z0-9+/=]+$",value),"Only verified inline raster references are allowed.")
      }
    }
    node$children<-lapply(node$children,replace)
  }else if(is.list(node))node<-lapply(node,replace)
  node};replace(svg)
}
.brohn_rp_implementation <- function(value) {
  brohn_fields(value,c("schema","profile","sources","runtime","archive_python","archive_script","raster_script"),label="Package implementation")
  brohn_require(identical(value$schema,"brohn-report-package-implementation/0.1")&&identical(value$profile,"static-complete-findings/0.1")&&
    is.list(value$sources)&&!is.null(names(value$sources))&&!anyDuplicated(names(value$sources))&&all(vapply(value$sources,.brohn_rp_hash,logical(1)))&&
    all(grepl("^[A-Za-z0-9_./-]+$",names(value$sources)))&&
    brohn_text(value$archive_python,4096)&&file.exists(value$archive_python)&&brohn_text(value$archive_script,4096)&&file.exists(value$archive_script)&&brohn_text(value$raster_script,4096)&&file.exists(value$raster_script),
    "Package renderer needs exact source/runtime identities and an explicit archive executable.")
  brohn_require("scripts/workers/report_package_archive.py"%in%names(value$sources)&&
    identical(digest::digest(file=value$archive_script,algo="sha256"),value$sources[["scripts/workers/report_package_archive.py"]]),"The pinned archive implementation changed.")
  brohn_require("scripts/workers/report_package_raster.py"%in%names(value$sources)&&
    identical(digest::digest(file=value$raster_script,algo="sha256"),value$sources[["scripts/workers/report_package_raster.py"]]),"The pinned raster implementation changed.")
  portable<-value[c("schema","profile","sources","runtime")]
  encoded<-brohn_json(portable);brohn_require(!grepl("[A-Za-z]:[/\\\\]|/Users/|/home/|file://",encoded),"Runtime identity cannot contain a local executable path.")
  portable
}
.brohn_rp_contents <- function(x) {
  brohn_fields(x,c("profile","audience","identifier_mode","stimulus_images","complete_selected_numerical_evidence","include_original_evidence","include_raw_recordings"),label="Report contents")
  brohn_require(identical(x$profile,"complete-findings/0.1"),"Original-byte report packages are unavailable in this first profile; choose complete findings.")
  brohn_require(identical(x$audience,"research_team")&&x$identifier_mode%in%c("package_aliases","source_identifiers")&&
    x$stimulus_images%in%c("included","excluded_by_choice")&&isTRUE(x$complete_selected_numerical_evidence)&&
    identical(x$include_original_evidence,FALSE)&&identical(x$include_raw_recordings,FALSE),"Unsupported report contents policy.")
  x
}
.brohn_rp_selection <- function(s) {
  task<-identical(s$schema,"brohn-report-package-selection/0.2")
  brohn_fields(s,c("schema","id","intent_ref","study_id","project_id","title","report_refs",if(task)"prepared_sources"else"display_refs","sections","contents_policy","limits_profile","renderer_profile","frozen_at","coverage"),
    c("generation"),"Frozen report selection")
  brohn_require(s$schema%in%c("brohn-report-package-selection/0.1","brohn-report-package-selection/0.2")&&brohn_valid_id(s$id)&&brohn_valid_id(s$study_id)&&brohn_valid_id(s$project_id)&&
    brohn_text(s$title,500)&&brohn_text(s$frozen_at,64)&&identical(s$limits_profile,if(task)"controlled-task-report-package/0.1"else"controlled-report-package/0.1")&&
    identical(s$renderer_profile,if(task)"controlled-gaze-explicit-task-paired/0.1"else"controlled-gaze-explicit-paired/0.1"),"Invalid frozen report selection.")
  .brohn_rp_ref(s$intent_ref,"report_package_intent");.brohn_rp_contents(s$contents_policy)
  for(ref in c(s$report_refs,s$display_refs)).brohn_rp_ref(ref)
  if(task){
    brohn_require(brohn_array(s$prepared_sources),"Prepared source inventory must be an ordered array.")
    for(p in s$prepared_sources){brohn_fields(p,c("adapter","source_report_ref","prepared_ref","implementation_ref"),label="Exact prepared source")
      brohn_require(p$adapter%in%c("explicit-distribution","task-display"),"Unsupported prepared source adapter.")
      .brohn_rp_ref(p$source_report_ref,"report");.brohn_rp_ref(p$prepared_ref,if(p$adapter=="task-display")"task_display"else"explicit_distributions")
      brohn_fields(p$implementation_ref,c("profile","hash"),label="Prepared implementation identity")
      brohn_require(brohn_text(p$implementation_ref$profile,128)&&.brohn_rp_hash(p$implementation_ref$hash),"Prepared implementation is not pinned.")
    }
  }
  brohn_require(brohn_array(s$sections)&&length(s$sections)>0L&&!anyDuplicated(vapply(s$sections,`[[`,character(1),"id"))&&
    !anyDuplicated(vapply(s$sections,`[[`,numeric(1),"order")),"Report sections need distinct stable identities and orders.")
  for(x in s$sections){
    brohn_fields(x,c("id","adapter","adapter_version","source_report_ref","source_ref","selector","display","order"),c("resolved_group_ids",if(task)"resolved_models"),"Report section")
    brohn_require(brohn_valid_id(x$id)&&identical(x$adapter_version,"0.1")&&x$adapter%in%c("gaze-context","explicit-distribution","paired-findings",if(task)c("task-scores","task-trials","task-people"))&&brohn_number(x$order,1,10000,TRUE),"Unsupported report section adapter.")
    .brohn_rp_ref(x$source_report_ref,"report");.brohn_rp_ref(x$source_ref)
  };s
}
.brohn_rp_asset <- function(bundle,item,stimulus,policy,cache) {
  asset<-stimulus$asset
  if(policy=="excluded_by_choice")return(list(uri=NULL,reason="Stimulus image excluded by choice. This labelled frame retains the saved geometry and AOI definitions."))
  if(is.null(asset))return(list(uri=NULL,reason="No pinned raster exists in this source. Only its saved normalized frame and AOI definitions are shown."))
  hits<-Filter(function(x)identical(x$ref$hash,asset$hash)&&any(vapply(x$stimulus_refs,function(r).brohn_rp_same(r$report_ref,item$ref)&&identical(r$stimulus_id,stimulus$id),logical(1))),bundle$assets)
  brohn_require(length(hits)==1L,"A selected stimulus image has no unique verified descriptor.");a<-hits[[1L]]
  brohn_fields(a,c("ref","path","stimulus_refs"),label="Sealed stimulus asset");brohn_fields(a$ref,c("hash","bytes","media_type"),label="Raster object")
  brohn_require(.brohn_rp_hash(a$ref$hash)&&a$ref$media_type%in%c("image/png","image/jpeg")&&
    brohn_number(a$ref$bytes,1,bundle$limits$max_image_bytes,TRUE)&&identical(a$ref$hash,asset$hash)&&a$ref$bytes==asset$size&&
    identical(a$ref$media_type,asset$media_type)&&brohn_text(a$path,4096)&&file.exists(a$path)&&file.info(a$path)$size==a$ref$bytes,
    "A required raster exceeds its profile or disagrees with its pinned stimulus.")
  if(exists(a$ref$hash,cache,inherits=FALSE)){
    cached<-get(a$ref$hash,cache)
    brohn_require(identical(as.numeric(cached$dimensions),as.numeric(c(asset$width,asset$height))),"Repeated raster dimensions disagree with the pinned stimulus.")
    return(cached)
  }
  bytes<-readBin(a$path,"raw",n=a$ref$bytes+1L)
  brohn_require(length(bytes)==a$ref$bytes&&identical(digest::digest(bytes,algo="sha256",serialize=FALSE),a$ref$hash),"A required raster failed byte integrity.")
  png<-length(bytes)>=8L&&identical(bytes[1:8],as.raw(c(137,80,78,71,13,10,26,10)))
  jpg<-length(bytes)>=3L&&identical(bytes[1:3],as.raw(c(255,216,255)))
  brohn_require(if(a$ref$media_type=="image/png")png else jpg,"Pinned raster signature disagrees with its declared type.")
  scratch<-get(".scratch",cache,inherits=FALSE)
  ordinal<-get0(".raster_count",cache,ifnotfound=0L)+1L;assign(".raster_count",ordinal,cache)
  brohn_require(ordinal<=bundle$limits$max_panels,"Selected distinct rasters exceed the selected-figure bound.")
  prefix<-sprintf("r%03d",ordinal)
  request<-list(schema="brohn-report-package-raster-request/0.1",path=a$path,sha256=a$ref$hash,bytes=a$ref$bytes,media_type=a$ref$media_type,width=asset$width,height=asset$height)
  request_path<-file.path(scratch,paste0(prefix,"-q.json"));result_path<-file.path(scratch,paste0(prefix,"-r.json"));.brohn_rp_write(request,request_path,TRUE)
  child<-processx::run(bundle$implementation$archive_python,c("-B",bundle$implementation$raster_script,"--request",request_path,"--output",result_path),
    timeout=30,error_on_status=FALSE,stdout=file.path(scratch,paste0(prefix,"-o.log")),stderr=file.path(scratch,paste0(prefix,"-e.log")),cleanup_tree=TRUE,windows_hide_window=TRUE)
  brohn_require(child$status==0L&&file.exists(result_path),paste("Pinned raster decode failed:",paste(readLines(file.path(scratch,paste0(prefix,"-e.log")),warn=FALSE),collapse=" ")))
  raster<-brohn_parse(paste(readLines(result_path,warn=FALSE,encoding="UTF-8"),collapse="\n"))
  brohn_require(identical(raster$schema,"brohn-report-package-raster-result/0.1")&&isTRUE(raster$passed)&&identical(raster$sha256,a$ref$hash)&&raster$bytes==a$ref$bytes&&
    raster$width==asset$width&&raster$height==asset$height&&identical(raster$media_type,a$ref$media_type)&&identical(raster$pillow,bundle$implementation$runtime$Pillow)&&
    .brohn_rp_same(raster$runtime$Python[c("implementation","version")],bundle$implementation$runtime$Python),"Raster verification differs from its pinned source/runtime.")
  dimensions<-c(raster$width,raster$height)
  total<-get0(".total",cache,ifnotfound=0)+length(bytes);brohn_require(total<=bundle$limits$max_image_total_bytes,"Selected distinct rasters exceed the inline-media profile.")
  assign(".total",total,cache)
  result<-list(uri=paste0("data:",a$ref$media_type,";base64,",base64enc::base64encode(bytes)),reason=NULL,dimensions=unname(dimensions))
  assign(a$ref$hash,result,cache);result
}

brohn_render_report_package <- function(bundle,output_dir) {
  task_profile<-identical(bundle$selection$schema,"brohn-report-package-selection/0.2")
  brohn_fields(bundle,c("schema","selection","reports","distributions","assets","implementation","limits",if(task_profile)"task_displays"),label="Report render input")
  brohn_require(identical(bundle$schema,"brohn-report-package-render-input/0.1"),"Unsupported report render input.")
  limits<-.brohn_rp_limits(bundle$limits);selection<-.brohn_rp_selection(bundle$selection);policy<-selection$contents_policy
  friendly<-identical(policy$identifier_mode,"package_aliases")
  implementation<-.brohn_rp_implementation(bundle$implementation)
  brohn_require(brohn_array(bundle$reports)&&length(bundle$reports)>=1L&&length(bundle$reports)<=limits$max_reports&&
    brohn_array(bundle$distributions)&&brohn_array(bundle$assets),"Choose supported complete report sources.")
  brohn_require(.brohn_rp_same(lapply(bundle$reports,`[[`,"ref"),selection$report_refs)&&
    identical(limits$profile,selection$limits_profile),"Render sources or limits differ from the frozen ordered selection.")
  if(task_profile).brohn_rpt_prepared_bindings(bundle)else
    brohn_require(.brohn_rp_same(lapply(bundle$distributions,`[[`,"ref"),selection$display_refs),"Render sources differ from the frozen ordered selection.")
  brohn_require(nchar(brohn_json(bundle),type="bytes")<=limits$max_model_bytes,"Decoded report bundle exceeds its explicit model bound.")
  brohn_require(brohn_text(output_dir,4096)&&!file.exists(output_dir),"Choose a fresh owned output directory.")
  if(task_profile){preflight<-brohn_report_package_panel_preflight(bundle);if(identical(preflight$schema,"brohn-report-package-refusal/0.1"))return(preflight)}
  dir.create(output_dir,recursive=TRUE,showWarnings=FALSE);output_dir<-normalizePath(output_dir,winslash="/",mustWork=TRUE)
  previous<-options(OutDec=".",scipen=0);on.exit(options(previous),add=TRUE)
  locale<-Sys.getlocale("LC_NUMERIC");suppressWarnings(Sys.setlocale("LC_NUMERIC","C"));on.exit(suppressWarnings(Sys.setlocale("LC_NUMERIC",locale)),add=TRUE)
  files<-list();sections<-list();coverage<-list();panels<-0L;aliases<-.brohn_rp_alias_context(policy$identifier_mode,bundle$reports);assets<-new.env(parent=emptyenv())
  private<-file.path(output_dir,".private");dir.create(private);assign(".scratch",private,assets)
  add<-function(path,type,role){entry<-.brohn_rp_file(output_dir,path,type,role);files[[length(files)+1L]]<<-entry
    brohn_require(sum(vapply(files,`[[`,numeric(1),"bytes"))<=limits$max_payload_bytes&&length(files)+2L<=limits$max_members,"Complete report payload exceeds its byte/member bound.");entry}
  json<-function(value,path,role){.brohn_rp_write(value,file.path(output_dir,path),TRUE);add(path,"application/json",role)}
  csv<-function(rows,path,role){.brohn_rp_csv(rows,file.path(output_dir,path));add(path,"text/csv; charset=utf-8",role)}
  figure<-function(svg,key,binding){
    panels<<-panels+1L;brohn_require(panels<=limits$max_panels,"Selected figure pages exceed the 100-panel profile. Choose fewer figures; numerical evidence was not trimmed.")
    svg<-.brohn_rp_namespace_svg(svg,paste0("figure-",key))
    svg$children<-c(list(shiny::tags$metadata(brohn_json(binding))),svg$children)
    path<-paste0("figures/",key,".svg");.brohn_rp_write(as.character(svg),file.path(output_dir,path));add(path,"image/svg+xml","selected_figure")
    shiny::tags$figure(svg,shiny::tags$figcaption(paste("Selected figure",panels,". Complete numerical collections accompany the evidence package.")))
  }
  prepared<-list()
  for(i in seq_along(bundle$reports)){
    item<-bundle$reports[[i]];brohn_fields(item,c("ref","saved_body","complete_analysis"),label="Verified report model");.brohn_rp_ref(item$ref,"report")
    brohn_require(identical(item$ref$body_hash,brohn_hash(item$saved_body))&&identical(item$saved_body$id,item$ref$id)&&
      identical(item$ref$project_id,selection$project_id)&&identical(item$saved_body$study_id,selection$study_id),"A complete model differs from its exact selected report/study.")
    original<-item$saved_body;original$analysis<-item$complete_analysis
    if(!brohn_questionnaire_is_artifact(item$saved_body$analysis))brohn_require(.brohn_rp_same(item$saved_body$analysis,item$complete_analysis),"Inline analysis changed during source preparation.")
    else brohn_validate_questionnaire_preview(item$saved_body$analysis,item$complete_analysis,brohn_questionnaire_artifact_source(item$saved_body))
    brohn_require(length(original$analysis$observations)<=limits$max_rows&&length(original$analysis$features)<=limits$max_rows&&
      length(original$analysis$scales$observations)<=limits$max_rows,"Complete report rows exceed the bounded profile; no head-only substitute was made.")
    if(original$analysis$kind=="questionnaire")brohn_require(nchar(brohn_json(original$analysis),type="bytes")<=limits$max_questionnaire_bytes,"Complete questionnaire exceeds the hydration profile.")
    key<-sprintf("report-%02d",i);gaze<-if(original$analysis$kind=="gaze")brohn_gaze_report_model(original)else NULL
    task_entry<-if(task_profile).brohn_rpt_find_entry(bundle,item)else NULL
    projection<-.brohn_rp_projection(item,aliases,key,if(is.null(task_entry))NULL else task_entry$evidence)
    projection$implementation<-implementation
    projection$projection_body_sha256<-brohn_hash(projection)
    json(projection,paste0("evidence/",key,".json"),"complete_typed_numerical_projection")
    family<-switch(original$analysis$kind,gaze="gaze",questionnaire="explicit",multimodal="paired",implicit="tasks",implicit_cohort="tasks")
    if("observations"%in%names(projection$analysis))csv(projection$analysis$observations,paste0("data/",family,"/",key,"-observations.csv"),"complete_observations")
    if("features"%in%names(projection$analysis))csv(projection$analysis$features,paste0("data/",family,"/",key,"-features.csv"),"complete_features")
    if(!is.null(projection$analysis$scales))csv(projection$analysis$scales$observations,paste0("data/explicit/",key,"-scales.csv"),"complete_scale_assessments")
    task<-if(is.null(task_entry))NULL else .brohn_rpt_write_complete(task_entry,item,projection,aliases,key,json,csv)
    prepared[[i]]<-list(item=item,original=original,projection=projection,gaze=gaze,key=key,task=task)
  }
  requested<-selection$sections[order(vapply(selection$sections,`[[`,numeric(1),"order"))]
  for(si in seq_along(requested)){
    s<-requested[[si]];at<-which(vapply(prepared,function(p).brohn_rp_same(p$item$ref,s$source_report_ref),logical(1)))
    brohn_require(length(at)==1L,"Section source is not exactly one selected report.");p<-prepared[[at]];body<-p$original
    nodes<-list();record<-list(section_id=s$id,adapter=s$adapter,source_report_ref=s$source_report_ref,status="included_supported",selected_figures=0L)
    before<-panels;prefix<-sprintf("section-%03d",si)
    if(s$adapter=="gaze-context"){
      brohn_require(.brohn_rp_same(s$source_ref,s$source_report_ref)&&!is.null(p$gaze),"Choose a supported saved gaze source.")
      brohn_fields(s$selector,"scope",if(identical(s$selector$scope,"exact_exposure"))"exposure_key"else character(),"Gaze selector")
      brohn_fields(s$display,"candidate_limit",label="Gaze figure settings")
      brohn_require(s$selector$scope%in%c("all_exposures","exact_exposure")&&brohn_number(s$display$candidate_limit,1,1000,TRUE),"Invalid gaze figure selection.")
      selected<-seq_along(p$gaze$groups)
      if(s$selector$scope=="exact_exposure"){selected<-which(vapply(p$gaze$groups,function(g)identical(g$key,s$selector$exposure_key),logical(1)));brohn_require(length(selected)==1L,"The selected exposure does not belong to the pinned report.")}
      for(gi in selected){
        original_group<-p$gaze$groups[[gi]];group<-.brohn_rp_project(original_group,aliases,p$key,"model/gaze")
        identity<-.brohn_rp_project(original_group$identity,aliases,p$key,"analysis/observations/*")
        group$identity<-identity;labels<-identity[c("participant_id","session_id","exposure_id")]
        if(friendly)labels<-lapply(labels,.brohn_rp_friendly)
        group$label<-paste(group$stimulus$title,"|",labels[[1L]],"|",labels[[2L]],"|",labels[[3L]])
        image<-.brohn_rp_asset(bundle,p$item,group$stimulus,policy$stimulus_images,assets)
        points<-brohn_gaze_report_points(group,s$display$candidate_limit)
        rendered<-brohn_gaze_report_svg(group,p$gaze,image,points)
        svg<-Filter(function(x)inherits(x,"shiny.tag")&&x$name=="svg",rendered$children);brohn_require(length(svg)==1L,"Gaze renderer did not return its declared SVG figure.")
        key<-paste0(prefix,"-exposure-",sprintf("%04d",gi))
        nodes<-c(nodes,list(shiny::h3(group$label),figure(svg[[1L]],key,list(source=p$item$ref,exposure_key=original_group$key,geometry_hash=brohn_hash(group$stimulus$aois),
          candidate_limit=s$display$candidate_limit,shown_candidates=length(points),complete_candidates=length(group$fixations))),
          rendered$children[-which(vapply(rendered$children,function(x)inherits(x,"shiny.tag")&&x$name=="svg",logical(1)))],
          shiny::p(paste("Showing",length(points),"of",length(group$fixations),"saved candidates. All saved candidate/support/quality rows remain in the complete features CSV and typed evidence.")),
          .brohn_rp_table(group$observations,"Saved AOI measures",c("aoi_label","valid_ms","inside_ms","valid_share_percent","fixation_dwell_ms","ttff_ms","ttff_status")),
          shiny::p(p$gaze$phase),shiny::p("Overlapping AOIs can sum above 100%. Missing support is unavailable; it is never zero gaze.")))
      }
      record$full_exposures<-length(p$gaze$groups);record$selected_exposures<-length(selected)
    }else if(s$adapter=="explicit-distribution"){
      hits<-Filter(function(x).brohn_rp_same(x$ref,s$source_ref),bundle$distributions);brohn_require(length(hits)==1L,"Selected saved distribution is unavailable.")
      d<-hits[[1L]];brohn_require(identical(d$ref$body_hash,brohn_hash(d$body))&&identical(d$body$result$schema,"brohn-explicit-distributions/1.0")&&
        identical(d$body$result$binding$report_id,p$item$ref$id)&&identical(d$body$result$binding$report_hash,p$item$ref$body_hash),"Distribution source binding does not match the selected report.")
      brohn_fields(s$selector,"scope",if(identical(s$selector$scope,"exact_item_condition"))c("family","item_id","condition_id")else character(),"Distribution selector")
      brohn_fields(s$display,"pages",if(identical(s$display$pages,"selected"))"offsets"else character(),"Distribution pages")
      brohn_require(s$selector$scope%in%c("all_groups","exact_item_condition")&&s$display$pages%in%c("all","selected"),"Invalid distribution selection.")
      groups<-d$body$result$groups
      if(s$selector$scope=="exact_item_condition"){
        groups<-Filter(function(g)identical(g$family,s$selector$family)&&identical(g$item_id,s$selector$item_id)&&.brohn_rp_same(g$condition_id,s$selector$condition_id),groups)
        brohn_require(length(groups)==1L,"Selected item/condition does not resolve to one saved distribution.")
      }
      brohn_require(.brohn_rp_same(s$resolved_group_ids,lapply(groups,`[[`,"id")),"Frozen distribution groups changed.")
      json(list(schema="brohn-portable-distributions/0.1",source_ref=d$ref,source_report_ref=p$item$ref,result=d$body$result),paste0("evidence/distributions/",prefix,".json"),"complete_saved_distribution")
      for(gi in seq_along(groups)){
        g<-groups[[gi]];rows<-.brohn_ed_rows(g);csv_path<-paste0("data/explicit/",prefix,"-group-",sprintf("%03d",gi),".csv")
        dir.create(dirname(file.path(output_dir,csv_path)),recursive=TRUE,showWarnings=FALSE)
        brohn_explicit_distribution_csv(list(body=d$body),g,file.path(output_dir,csv_path));add(csv_path,"text/csv; charset=utf-8","complete_distribution_rows")
        offsets<-if(s$display$pages=="all")as.list(if(length(rows))seq(0L,length(rows)-1L,by=20L)else 0L)else s$display$offsets
        brohn_require(brohn_array(offsets)&&length(offsets)>0L&&!anyDuplicated(unlist(offsets))&&all(vapply(offsets,function(n)brohn_number(n,0,max(0,length(rows)-1L),TRUE)&&n%%20L==0L,logical(1))),"Choose actual saved distribution pages.")
        nodes<-c(nodes,list(shiny::h3(paste(g$label,g$condition_label,sep=" \u2014 ")),shiny::p(paste(g$source_records,"saved records;",g$usable_records,"eligible records;",.brohn_rp_text(g$participant_count),"linked people. Counts are records, not independent people.")),
          .brohn_rp_table(g$states,"Complete saved response support",maximum=100L)))
        for(offset in offsets){
          svg<-brohn_explicit_distribution_svg(g,offset,720L,binding=d$body$result$binding)
          if(is.null(svg))nodes<-c(nodes,list(shiny::p("No eligible distribution values were saved; no zero-valued chart was invented.")))else
            nodes<-c(nodes,list(figure(svg,paste0(prefix,"-group-",gi,"-offset-",offset),list(source=d$ref,source_report=p$item$ref,group_id=g$id,offset=offset)),
              shiny::tags$details(shiny::tags$summary(paste("View values for distribution page",offset%/%20L+1L)),
                .brohn_rp_table(utils::head(utils::tail(rows,max(0L,length(rows)-offset)),20L),paste("Values in selected distribution page",offset%/%20L+1L),maximum=20L))))
        }
      };record$full_groups<-length(d$body$result$groups);record$selected_groups<-length(groups)
    }else if(s$adapter%in%c("task-scores","task-trials","task-people")){
      rendered_task<-.brohn_rpt_section(s,p,prefix,figure,json,csv,friendly);nodes<-rendered_task$nodes;record<-c(record,rendered_task$coverage)
    }else{
      brohn_require(.brohn_rp_same(s$source_ref,s$source_report_ref),"Paired section source differs from its saved scientific report.")
      brohn_fields(s$selector,"scope",if(s$selector$scope=="exact_comparison")c("comparison_id","contrast_hash")else character(),"Paired selector")
      brohn_fields(s$display,c("charts","pages"),if(s$display$pages=="selected")"page_numbers"else character(),"Paired pages")
      brohn_require(s$selector$scope%in%c("all_comparisons","exact_comparison")&&s$display$pages%in%c("all","selected")&&brohn_array(s$display$charts)&&length(s$display$charts)>0L&&
        !anyDuplicated(unlist(s$display$charts))&&all(unlist(s$display$charts)%in%c("means","differences")),"Invalid saved paired figure selection.")
      if(body$analysis$kind=="questionnaire")brohn_require(nchar(brohn_json(body$analysis),type="bytes")<=limits$max_paired_questionnaire_bytes,"Complete questionnaire exceeds the paired figure hydration profile.")
      choices<-.brohn_pp_catalog(body)
      if(s$selector$scope=="exact_comparison"){
        choices<-Filter(function(x)identical(x$id,s$selector$comparison_id),choices)
        brohn_require(length(choices)==1L&&identical(brohn_hash(body$analysis$contrasts[[choices[[1L]]$index]]),s$selector$contrast_hash),"Saved contrast identity changed.")
      }
      for(ci in seq_along(choices)){
        original<-brohn_paired_plot_model(body,choices[[ci]]$id,p$item$ref$body_hash)
        model<-.brohn_rp_project(original,aliases,p$key,"model/paired");model$report_revision<-p$item$ref$revision
        # Derived observation IDs refer to the existing assessment/exposure IDs.
        for(oi in seq_along(model$observations)){
          row<-original$observations[[oi]];model$observations[[oi]]$observation_id<-aliases$label(p$key,if(row$source_container=="analysis.scales.observations")"assessment"else"exposure",row$observation_id,row$participant_id,row$session_id)
        }
        key<-paste0(prefix,"-comparison-",sprintf("%03d",ci))
        json(model,paste0("data/paired/",key,".json"),"complete_saved_paired_model")
        csv_path<-paste0("data/paired/",key,".csv");brohn_paired_plot_csv(model,file.path(output_dir,csv_path));add(csv_path,"text/csv; charset=utf-8","complete_paired_evidence")
        nodes<-c(nodes,list(shiny::h3(paste(model$label,model$condition_label,sep=" \u2014 ")),shiny::p(paste("Saved test-minus-control estimate (rounded display):",.brohn_rp_text(model$saved_contrast$estimate),model$saved_contrast$unit)),
          shiny::p(model$interpretation)))
        if(model$status!="verified")nodes<-c(nodes,list(shiny::p(.brohn_pp_reason(model$reason))))else{
          pages<-if(s$display$pages=="all")as.list(seq_len(max(1L,ceiling(length(model$people)/50L))))else s$display$page_numbers
          brohn_require(brohn_array(pages)&&length(pages)>0L&&!anyDuplicated(unlist(pages))&&all(vapply(pages,function(n)brohn_number(n,1,max(1L,ceiling(length(model$people)/50L)),TRUE),logical(1))),"Choose actual paired-person pages.")
          for(page in pages){
            for(chart in s$display$charts)nodes<-c(nodes,list(figure(.brohn_rp_paired_svg(model,page,chart,680L,friendly),paste0(key,"-",chart,"-page-",page),
              list(source=p$item$ref,contrast_hash=brohn_hash(original$saved_contrast),chart=chart,page=page))))
            start<-(page-1L)*50L
            rows<-utils::head(utils::tail(model$people,max(0L,length(model$people)-start)),50L)
            nodes<-c(nodes,list(shiny::tags$details(shiny::tags$summary(paste("View",length(rows),"people's values for page",page)),
              .brohn_rp_table(rows,paste("Saved paired-person values in selected page",page),c("participant_id","control_mean","test_mean","difference","paired_sessions"),maximum=50L,friendly=friendly))))
          }
        }
      };record$full_comparisons<-length(body$analysis$contrasts);record$selected_comparisons<-length(choices)
    }
    record$selected_figures<-panels-before;coverage[[length(coverage)+1L]]<-record
    sections[[length(sections)+1L]]<-shiny::tags$section(id=prefix,`aria-labelledby`=paste0(prefix,"-heading"),
      shiny::h2(id=paste0(prefix,"-heading"),paste0(si,". ",switch(s$adapter,"gaze-context"="Gaze in context","explicit-distribution"="Explicit responses","paired-findings"="Saved paired findings",
        "task-scores"="Saved task scores","task-trials"="Task response evidence","task-people"="People behind task measures"),
        " \u2014 Source ",at)),
      shiny::p(class="muted",paste("Source",at,"\u2014",body$title,"| origin:",body$origin)),nodes)
  }
  json(list(schema="brohn-portable-numerical-evidence-schema/0.1",typed_json="Canonical Brohn JSON: explicit null/false/zero/empty/array/object values; original collection order retained.",
    csv=list(encoding="UTF-8",newline="CRLF",quoting="All cells quoted; doubled embedded quotes",source_order="1-based original projected collection order",
      record_json="Authoritative typed projected row; absent keys remain absent, explicit null remains null. Spreadsheet prefixes affect display cells only."),
    original_source_hashes="Identify retained original bytes; transformed projections have their own manifest hashes.",
    projection_body_sha256="Canonical Brohn body hash excluding this field; implementation records exact portable source/runtime identities.",
    archive_order="ASCII lexicographic relative paths; ZIP_STORED; fixed 1980-01-01 timestamp; no comments or extra fields."),"schemas/numerical-evidence.json","projection_schema")
  evidence_index<-lapply(files,function(f)shiny::tags$li(shiny::tags$a(href=f$path,paste(gsub("_"," ",f$role),"\u2014",f$path))))
  page<-shiny::tagList(shiny::tags$head(shiny::tags$meta(charset="UTF-8"),shiny::tags$title(paste("Brohn",selection$title)),
    shiny::tags$meta(name="viewport",content="width=device-width, initial-scale=1"),shiny::tags$style(htmltools::HTML(.brohn_rp_style))),
    shiny::tags$body(shiny::tags$a(class="skip",href="#report-main","Skip to findings"),shiny::tags$header(shiny::h1(selection$title),
      shiny::p("Brohn \u2022 saved research findings"),shiny::p(paste("Frozen",selection$frozen_at)),
      shiny::p(class="notice",paste(if(policy$identifier_mode=="package_aliases")"Package-local person/session labels."else"Original source identifiers included.",
        if(policy$stimulus_images=="included")if(task_profile)"Selected pinned gaze stimulus images included when available."else"Selected pinned stimulus images included when available."else if(task_profile)"Gaze stimulus images excluded by choice."else"Stimulus images excluded by choice.",
        "Complete numerical evidence is in the report + evidence ZIP. Free text remains verbatim; these files are not claimed to be anonymized."))),
      shiny::tags$main(id="report-main",sections,shiny::tags$section(shiny::h2("Methods and complete evidence"),
        shiny::p("This package presents existing saved analyses. It does not rerun detectors, scales, comparisons or inference. Original raw recording bytes were not reverified by export."),
        if(task_profile)shiny::p("Task material definitions and immutable image references are retained. Task material image bytes and context panels are not included in this adapter. The optional image setting covers gaze stimuli only."),
        shiny::p("Non-integer numerical summaries are displayed to four significant figures; integer values and counts stay exact. Complete JSON, CSV typed records and SVG metadata retain the exact saved numerical values."),
        shiny::p("The following links work only after unpacking the report + evidence ZIP. This standalone HTML contains the selected figures and bounded numerical alternatives, not every source row."),
        shiny::tags$ul(evidence_index),lapply(prepared,function(p)shiny::tags$details(shiny::tags$summary(paste("Saved methods:",p$original$title)),
          shiny::tags$pre(brohn_json(p$projection$analysis$parameters,TRUE)),shiny::tags$ul(lapply(p$projection$analysis$limitations,shiny::tags$li)))))),
      shiny::tags$footer(shiny::p("Brohn \u2022 open research software. Interpret each measure using its saved support, method and limitations."))))
  rendered<-htmltools::renderTags(page);brohn_require(!length(rendered$dependencies),"Offline report cannot depend on widgets or external assets.")
  html<-paste0('<!doctype html>\n<html lang="en">\n<head>\n',rendered$head,'\n</head>\n',rendered$html,'\n</html>\n')
  brohn_require(nchar(enc2utf8(html),type="bytes")<=limits$max_html_bytes,"Selected inline figures exceed the standalone HTML bound. Choose fewer figures; complete numbers remain available.")
  .brohn_rp_write(html,file.path(output_dir,"report.html"));add("report.html","text/html; charset=utf-8","standalone_report")
  portable_selection<-selection[setdiff(names(selection),c("intent_ref","generation"))]
  manifest<-list(schema="brohn-report-package/0.1",profile="complete-findings/0.1",selection=portable_selection,
    sources=if(task_profile)list(reports=selection$report_refs,distributions=lapply(bundle$distributions,`[[`,"ref"),task_displays=lapply(bundle$task_displays,`[[`,"ref"))else list(reports=selection$report_refs,distributions=selection$display_refs),coverage=coverage,
    implementation=implementation,projection=list(schema="brohn-portable-numerical-evidence/0.1",policy=policy,
      counts=lapply(prepared,function(p)list(source_ref=p$item$ref,counts=p$projection$counts))),files=files,
    scope="Faithful saved-result presentation and complete named numerical projections; no new scientific analysis, device or construct qualification.")
  if(task_profile)manifest$task_material_coverage<-lapply(Filter(function(p)!is.null(p$task),prepared),function(p).brohn_rpt_material_coverage(p$item))
  .brohn_rp_write(manifest,file.path(output_dir,"manifest.json"),TRUE)
  manifest_file<-.brohn_rp_file(output_dir,"manifest.json","application/json","portable_inventory")
  request<-list(schema="brohn-report-package-archive-request/0.1",root=output_dir,files=files,manifest=manifest_file,
    limits=list(max_members=limits$max_members,max_payload_bytes=limits$max_payload_bytes))
  request_path<-file.path(private,"archive-request.json");result_path<-file.path(private,"archive-result.json");.brohn_rp_write(request,request_path,TRUE)
  child<-processx::run(bundle$implementation$archive_python,c("-B",bundle$implementation$archive_script,"--request",request_path,"--output",result_path),
    timeout=120,error_on_status=FALSE,stdout=file.path(private,"archive-stdout.log"),stderr=file.path(private,"archive-stderr.log"),cleanup_tree=TRUE,windows_hide_window=TRUE)
  brohn_require(child$status==0L&&file.exists(result_path),paste("Deterministic report archive failed:",paste(readLines(file.path(private,"archive-stderr.log"),warn=FALSE),collapse=" ")))
  result<-brohn_parse(paste(readLines(result_path,warn=FALSE,encoding="UTF-8"),collapse="\n"))
  brohn_require(identical(result$schema,"brohn-report-package-archive-result/0.1")&&isTRUE(result$passed)&&
    .brohn_rp_same(result$runtime$Python[c("implementation","version")],bundle$implementation$runtime$Python),"Archive verifier returned no complete success under the pinned Python runtime.")
  zip_file<-.brohn_rp_file(output_dir,"report.brohn-report.zip","application/zip","report_package")
  brohn_require(.brohn_rp_same(zip_file,result$artifact),"Archive bytes differ from their verified receipt.")
  list(schema="brohn-report-package-render-result/0.1",profile="complete-findings/0.1",manifest=manifest,
    files=c(files,list(manifest_file,zip_file)),coverage=coverage)
}

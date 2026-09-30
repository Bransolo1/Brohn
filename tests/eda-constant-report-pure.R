# Pure catalog/status-panel checks over separately generated Python component
# models. No source store, authority, job, detector, or inference is exercised.
args<-commandArgs(TRUE);stopifnot(length(args)==4L)
base<-normalizePath(args[[1]],winslash="/",mustWork=TRUE);pure<-normalizePath(args[[2]],winslash="/",mustWork=TRUE)
fixtures<-normalizePath(args[[3]],winslash="/",mustWork=TRUE);out<-args[[4]];stopifnot(!file.exists(out));dir.create(out,recursive=TRUE);out<-normalizePath(out,winslash="/",mustWork=TRUE)
setwd(base);source("R/platform-load.R");brohn_load(ui=FALSE)
paths<-c("tables","tasks","choice","eda","eda-figures","render")
for(p in paths)source(file.path(pure,"R",paste0("platform-report-package-",p,".R")))
checks<-character();check<-function(ok,label){stopifnot(isTRUE(ok));checks<<-c(checks,label)}
refuse<-function(fn,label)check(inherits(tryCatch({fn();NULL},error=identity),"error"),label)
for(version in c("0.1","0.2"))check(.brohn_rpe_version(list(renderer_profile=paste0("controlled-gaze-explicit-task-choice-eda-paired/",version)))==version,paste("exact renderer generation",version))
refuse(function().brohn_rpe_version(list(renderer_profile="controlled-gaze-explicit-task-choice-eda-paired/0.3")),"unknown future renderer refuses")
for(i in 1:6){
  folder<-file.path(fixtures,paste0("constant-",i));e<-brohn_eda_read_json_file(file.path(folder,"evidence.json"));catalog<-brohn_eda_read_json_file(file.path(folder,"catalog.json"));q<-brohn_eda_read_json_file(file.path(folder,"prepared-request.json"))
  before<-brohn_eda_value_hash(list(evidence=e,catalog=catalog,analysis=q$report$complete_analysis))
  ref<-list(kind="eda_display",id=paste0("synthetic-display-",i),revision=1,body_hash=paste(rep("a",64),collapse=""),project_id="synthetic-project")
  section<-list(id=paste0("section-",i),adapter="eda-continuous",adapter_version="0.1",source_report_ref=q$report$ref,source_ref=ref,selector=list(scope="all_cells"),
    display=list(components=list("clean_us","tonic_us","phasic_us"),pages="all",page_numbers=list(),marker_pages=list(pages="all",page_numbers=list())),order=i)
  resolved<-brohn_resolve_eda_report_section(section,catalog)
  check(resolved$panel_count==1L&&identical(resolved$section$resolved_models[[1]]$components,list()),"constant cell resolves one explanatory panel, no fake component")
  check(!length(resolved$section$resolved_models[[1]]$marker_pages)&&!length(resolved$section$resolved_models[[1]]$numerical_pages$candidates),"no invented candidate/marker pages")
  for(which in c("numerical","marker")){
    bad<-section
    if(which=="numerical"){bad$display$pages<-"selected";bad$display$page_numbers<-list(1L)}else bad$display$marker_pages<-list(pages="selected",page_numbers=list(1L))
    refuse(function()brohn_resolve_eda_report_section(bad,catalog),paste("nonexistent constant",which,"page refuses"))
  }
  bad<-catalog;bad[[1]]$scr_status<-"computed"
  refuse(function()brohn_resolve_eda_report_section(section,bad),"constant catalog cannot claim computed response support")
  p<-list(item=q$report,projection=list(analysis=q$report$complete_analysis),eda=list(entry=list(ref=ref,body=list(catalog=catalog)),display=e))
  figures<-list();figure<-function(svg,key,metadata){figures[[length(figures)+1L]]<<-list(svg=svg,key=key,metadata=metadata);shiny::tags$figure(svg,shiny::tags$figcaption("Saved status panel; complete original evidence remains separate."))}
  result<-.brohn_rpe_section(resolved$section,p,paste0("source-",i),figure,FALSE)
  check(length(figures)==1L&&length(result$coverage$cells)==1L&&result$coverage$cells[[1]]$complete_feature_count==10,"one real support figure and all ten measure alternatives retained")
  svg<-as.character(figures[[1]]$svg)
  check(!grepl("<(polyline|circle|line|path)\\b",svg,perl=TRUE)&&grepl("No waveform or physiological zero response",svg,fixed=TRUE),"support SVG contains no numerical marks or zero-response claim")
  doc<-htmltools::tagList(shiny::tags$head(shiny::tags$meta(charset="utf-8"),shiny::tags$meta(name="viewport",content="width=device-width, initial-scale=1"),shiny::tags$title("Saved constant EDA description"),shiny::tags$style(htmltools::HTML(paste0(.brohn_rp_style,.brohn_rpe_figure_style)))),shiny::tags$body(shiny::tags$main(shiny::h1("Saved constant EDA description"),shiny::tags$section(shiny::h2("1. Continuous EDA - Source 1"),result$nodes))))
  rendered<-htmltools::renderTags(doc);stopifnot(!length(rendered$dependencies))
  html<-paste0('<!DOCTYPE html>\n<html lang="en">\n<head>\n',rendered$head,'\n</head>\n',rendered$html,'\n</html>\n');path<-file.path(out,paste0("constant-",i,".html"));writeLines(enc2utf8(html),path,useBytes=TRUE)
  check(grepl("<title>Saved constant EDA description</title>",html,fixed=TRUE)&&grepl(.brohn_rpe_figure_style,html,fixed=TRUE)&&grepl("<h2>",html,fixed=TRUE),"component wrapper actually retains report styles, title and intervening section heading")
  check(grepl("not processed observations or response denominators",html,fixed=TRUE)&&grepl("candidate table contains zero stored rows because detection was withheld",html,fixed=TRUE),"responsive prose separates coordinate counts and withheld detection")
  check(grepl("denominator",html,fixed=TRUE)&&grepl("exact_constant_signal",html,fixed=TRUE)&&grepl("conductance_raw_mean",html,fixed=TRUE),"complete ten-measure table retains canonical support and denominator fields")
  check(before==brohn_eda_value_hash(list(evidence=e,catalog=catalog,analysis=q$report$complete_analysis)),"pure figure selection/rendering leaves all original scientific values/types unchanged")
}
hashes<-setNames(lapply(paths,function(p)digest::digest(file=file.path(pure,"R",paste0("platform-report-package-",p,".R")),algo="sha256")),paths)
brohn_eda_write_json_file(list(passed=TRUE,checks=as.list(checks),count=length(checks),source_hashes=hashes,scope="Pure component fixtures and actual report styling; no native preparation, package publication, browser or scientific-validity claim"),file.path(out,"results.json"))
cat(length(checks),"constant report component checks passed\n")

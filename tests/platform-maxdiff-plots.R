source("R/platform-load.R",encoding="UTF-8");brohn_load();source("tests/fixtures/maxdiff-plots.R")
local({
  n<-0L;check<-function(ok,label){if(!isTRUE(ok))stop(label);n<<-n+1L;cat("PASS",label,"\n")}
  f<-brohn_original_maxdiff_plot_fixture();hash<-brohn_hash(f$result)
  rows<-brohn_maxdiff_plot_rows(f$result,"adjusted")
  check(identical(vapply(rows,`[[`,numeric(1),"value"),c(21,4,-25)/48),"Graph values equal independently computed complete-pair adjusted scores")
  check(all(vapply(rows,`[[`,numeric(1),"complete_pair_exposures")==48)&&all(vapply(rows,`[[`,numeric(1),"missing_exposures")==1),"Omitted choices remain separate from exact48-exposure denominator")
  utilities<-brohn_maxdiff_plot_rows(f$result,"utility")
  check(max(abs(vapply(utilities,`[[`,numeric(1),"value")-unlist(f$expected_utilities)))<1e-6,"Saved paired utilities match exact likelihood frequencies from independent log ratios")
  for(width in c(820,320)){
    svg<-as.character(brohn_maxdiff_svg(f$result,"adjusted",width))
    check(grepl(paste("0 0",width,"204"),svg,fixed=TRUE)&&length(gregexpr('data-item-id=',svg,fixed=TRUE)[[1]])==3,"Each responsive view represents every saved item")
    check(!grepl('<b>original</b>',svg,fixed=TRUE)&&grepl('&lt;b&gt;original&lt;/b&gt;',svg,fixed=TRUE),"Researcher labels remain escaped in the chart and accessible source descriptions")
  }
  missing<-as.character(brohn_maxdiff_svg(f$empty,"adjusted"))
  check(!grepl('<circle',missing,fixed=TRUE)&&grepl('data-value="unavailable"',missing,fixed=TRUE),"Missing choice denominator does not produce a zero or fabricated dot")
  check(is.null(brohn_maxdiff_svg(f$empty,"utility")),"Unidentified aggregate model has no utility plot")
  check(identical(brohn_hash(f$result),hash),"Viewing both chart types leaves saved analysis unchanged")
  forged<-f$result;forged$exposures[[1]]$participant_id<-"different"
  check(inherits(try(brohn_maxdiff_plot_rows(forged),silent=TRUE),"try-error"),"Substituted response evidence cannot enter the plot")
  output<-Sys.getenv("BROHN_MAXDIFF_PLOT_EVIDENCE")
  if(nzchar(output)){
    dir.create(output,recursive=TRUE,showWarnings=FALSE)
    brohn_write_json_file(f,file.path(output,"fixture.json"))
    report<-list(id="original-maxdiff-plot-report",title="Original choice plots",origin="sample",status="Available",analysis=list(kind="maxdiff",choice_tasks=list(f$result,f$empty),quality=list(source_exercises=2)))
    brohn_export_report_html(report,file.path(output,"report.html"))
    writeLines(as.character(brohn_maxdiff_svg(f$result,"adjusted")),file.path(output,"adjusted.svg"),useBytes=TRUE)
    writeLines(as.character(brohn_maxdiff_svg(f$result,"utility")),file.path(output,"utility.svg"),useBytes=TRUE)
    brohn_write_json_file(list(passed=TRUE,checks=n),file.path(output,"numeric-results.json"))
  }
  cat("MaxDiff plots:",n,"checks passed\n")
})

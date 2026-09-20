# Views of immutable saved choice results. No fitting, inference or resampling.
brohn_maxdiff_plot_rows <- function(result, kind=c("adjusted","utility")) {
  kind<-match.arg(kind)
  brohn_require(identical(result$schema,"brohn-maxdiff-result/1.0")&&identical(result$design_hash,brohn_hash(result$design))&&
    identical(result$responses_hash,brohn_hash(result$exposures)),"Reopen the complete original best-worst result before plotting.")
  if(kind=="utility"&&!identical(result$model$status,"estimated"))return(list())
  lapply(result$items,function(item){
    u<-if(kind=="utility"){hits<-Filter(function(u)identical(u$item_id,item$item_id),result$model$utilities);brohn_require(length(hits)==1L,"A saved fitted item utility is unavailable.");hits[[1L]]}else NULL
    value<-if(kind=="adjusted")item$exposure_adjusted_score else u$utility
    brohn_require(is.null(value)||brohn_number(value),"A saved best-worst plot value is not finite.")
    list(item_id=item$item_id,label=item$label,value=value,unit=if(kind=="adjusted")"net choices per complete-pair exposure"else"relative logit utility",
      best_count=item$best_count,worst_count=item$worst_count,complete_pair_exposures=item$answered_exposures,
      missing_exposures=item$missing_exposures,presented_exposures=item$presented_exposures,
      design_hash=result$design_hash,responses_hash=result$responses_hash)
  })
}
brohn_maxdiff_svg <- function(result,kind=c("adjusted","utility"),width=820,identity="saved") {
  kind<-match.arg(kind);rows<-brohn_maxdiff_plot_rows(result,kind);if(!length(rows))return(NULL)
  compact<-width<560;left<-if(compact)90 else 250;right<-if(compact)266 else 670
  height<-90+length(rows)*38;values<-vapply(rows,function(r)if(is.null(r$value))NA_real_ else r$value,numeric(1))
  extent<-if(kind=="adjusted")1 else max(abs(values),.01,na.rm=TRUE)*1.1
  sx<-function(x)left+(x+extent)/(2*extent)*(right-left)
  fmt<-function(x)format(signif(x,if(compact)3 else 4),trim=TRUE,scientific=FALSE)
  id<-paste0("brohn-maxdiff-",identity,"-",kind,"-",width)
  title<-if(kind=="adjusted")"Exposure-adjusted best-worst choices"else"Aggregate paired utilities"
  description<-if(kind=="adjusted")"Dots show (best count minus worst count) divided by complete-pair exposures containing each item. Zero is an observed equal count, not a missing choice. Missing denominators remain unavailable."else
    "Dots show the saved zero-centred paired logit fit. Each complete pair contributes equally. No population uncertainty or individual preference is shown."
  shiny::tags$svg(xmlns="http://www.w3.org/2000/svg",viewBox=paste(0,0,width,height),width="100%",role="img",`aria-labelledby`=paste(id,"title",sep="-"),`aria-describedby`=paste(id,"description",sep="-"),
    style="display:block;max-width:100%;background:#131d24;font-family:system-ui,sans-serif",
    shiny::tags$title(id=paste(id,"title",sep="-"),title),shiny::tags$desc(id=paste(id,"description",sep="-"),description),
    lapply(c(-extent,0,extent),function(x)shiny::tagList(shiny::tags$line(x1=sx(x),x2=sx(x),y1=15,y2=height-54,stroke=if(x==0)"#a1b5ba"else"#3f5058"),
      shiny::tags$text(x=sx(x),y=height-32,`text-anchor`="middle",fill="#d2dedd",`font-size`=12,fmt(x)))),
    lapply(seq_along(rows),function(i){r<-rows[[i]];y<-22+i*38;limit<-if(compact)11 else 29
      label<-if(nchar(r$label)>limit)paste0(substr(r$label,1,limit-3),"...")else r$label
      shiny::tags$g(`data-item-id`=r$item_id,`data-value`=if(is.null(r$value))"unavailable"else sprintf("%.17g",r$value),`data-denominator`=r$complete_pair_exposures,
        shiny::tags$title(paste(r$label,if(is.null(r$value))"Unavailable"else paste(fmt(r$value),r$unit),"; best",r$best_count,"worst",r$worst_count,"complete-pair exposures",r$complete_pair_exposures,"missing",r$missing_exposures)),
        shiny::tags$text(x=left-10,y=y+4,`text-anchor`="end",fill="#edf5f3",`font-size`=12,label),
        if(is.null(r$value))shiny::tags$text(x=left+8,y=y+4,fill="#d2dedd",`font-size`=12,"Unavailable")else shiny::tagList(
          shiny::tags$line(x1=sx(0),x2=sx(r$value),y1=y,y2=y,stroke="#a7e9d3",`stroke-width`=3),
          shiny::tags$circle(cx=sx(r$value),cy=y,r=5,fill="#a7e9d3")),
        shiny::tags$text(x=right+12,y=y+4,fill="#d2dedd",`font-size`=if(compact)10 else 12,paste0("n=",r$complete_pair_exposures)))
    }),
    shiny::tags$text(x=(left+right)/2,y=height-10,`text-anchor`="middle",fill="#edf5f3",`font-size`=12,
      if(kind=="utility")"Relative logit utility"else if(compact)"(Best - worst) / n"else"(Best choices - worst choices) / complete-pair exposures"))
}
brohn_maxdiff_plot_ui <- function(result,kind="adjusted",exercise_number=1L) {
  svg<-brohn_maxdiff_svg(result,kind,identity=as.character(exercise_number));if(is.null(svg))return(NULL)
  # Encoded local SVG contains escaped text only and remains a standalone export.
  encoded<-function(value,mime)paste0("data:",mime,";base64,",gsub("[\r\n]","",jsonlite::base64_enc(charToRaw(enc2utf8(value)))))
  href<-encoded(as.character(svg),"image/svg+xml")
  rows<-brohn_maxdiff_plot_rows(result,kind)
  json<-brohn_json(list(schema="brohn-maxdiff-chart-values/1.0",kind=kind,rows=rows,model_parameters=result$model$parameters,
    design_hash=result$design_hash,responses_hash=result$responses_hash,limitations=result$limitations))
  title<-if(kind=="adjusted")"Exposure-adjusted choice chart"else"Paired utility chart"
  shiny::tagList(shiny::h3(title),shiny::div(role="region",`aria-label`=paste(title,"exercise",exercise_number),
    shiny::div(class="brohn-signal-wide",svg),shiny::div(class="brohn-signal-compact",brohn_maxdiff_svg(result,kind,320,as.character(exercise_number)))),
    shiny::p(class="brohn-muted","n is the number of complete-pair exposures containing that item. Exact labels, values and missing-choice counts appear in the table below."),
    shiny::div(class="brohn-toolbar",shiny::tags$a(class="btn btn-default",href=href,download=paste0("brohn-best-worst-",exercise_number,"-",kind,".svg"),paste("Download",tolower(title))),
      shiny::tags$a(class="btn btn-default",href=encoded(json,"application/json"),download=paste0("brohn-best-worst-",exercise_number,"-",kind,".json"),paste("Download",tolower(title),"values"))))
}

# Actual Shiny number-handler behavior at the blank native mapping boundary.
source("R/platform-load.R",encoding="UTF-8");brohn_load(ui=TRUE)
local({
  checks<-character();check<-function(label,ok){stopifnot(isTRUE(ok));checks<<-c(checks,label);cat("PASS",label,"\n")}
  number<-get("inputHandlers",envir=asNamespace("shiny"))$get("shiny.number")
  blank<-number(NULL)
  check("Installed Shiny blank number is a missing scalar",is.atomic(blank)&&length(blank)==1L&&is.na(blank))
  d<-list(modality="audio",source=list(format="wav"))
  input<-list(map_origin="Original synthetic audio; no human recording",map_unit="FS",map_sampling_rate=blank)
  mapping<-brohn_dataset_base_mapping(input,d)
  check("Blank optional sample rate does not enter the native mapping",!"sampling_rate"%in%names(mapping))
  check("Mapping serializes without a false scientific failure",identical(brohn_parse(brohn_json(mapping))$unit,"FS"))
  input$map_sampling_rate<-number(0)
  check("A typed zero is preserved for downstream method validation",identical(brohn_dataset_base_mapping(input,d)$sampling_rate,0))
  input$map_sampling_rate<-FALSE
  check("Typed false is not silently converted to missing",identical(brohn_dataset_base_mapping(input,d)$sampling_rate,FALSE))
  for(missing in list(NA_real_,NA_integer_,NA_character_,NA,NaN)){
    input$map_sampling_rate<-missing
    stopifnot(!"sampling_rate"%in%names(brohn_dataset_base_mapping(input,d)))
  }
  check("All scalar missing representations are omitted consistently",TRUE)
  input$map_sampling_rate<-48000
  check("Finite entered numbers and provenance stay unchanged",identical(brohn_dataset_base_mapping(input,d)$sampling_rate,48000)&&
    identical(brohn_dataset_base_mapping(input,d)$origin_statement,input$map_origin))
  cat("PASS",length(checks),"Shiny missing-value mapping checks\n")
})

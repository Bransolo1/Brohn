# Run manually once to create original, non-vendor trial evidence. This refuses
# to overwrite frozen fixtures. Tests read committed bytes and never regenerate.
source("R/platform-core.R");source("R/platform-methods.R")
destination<-"tests/fixtures/task-import"
stopifnot(!file.exists(destination));dir.create(destination)
RNGkind("Mersenne-Twister","Inversion","Rejection")
profiles<-c(iat="iat-gnb2003-d1/1.0",biat="biat-nosek2014-goodfocal/1.0",aat="aat-keyboard-cue-balanced/1.0",
  simple="rt-deary-liewald-simple/1.0",choice="rt-deary-liewald-choice/1.0")
columns<-c("participant_id","participant_linkage","session_id","attempt_id","protocol_id","presentation_index","trial_id",
  "presented","outcome","first_code","final_code","first_correct","first_response_ms","final_correct_ms","missing_reason")
mapping_names<-paste0(c("participant","participant_linkage","session","attempt","protocol","presentation_index","trial",
  "presented","outcome","first_code","final_code","first_correct","first_response_ms","final_correct_ms","missing_reason"),"_column")
expected<-list(iat=list(IAT_D1=(400/sqrt(2000000/39)+400/sqrt(4000000/79))/2),biat=list(BIAT_D=400/sqrt(1600000/31)),
  aat=list(keyboard_aat_relative_approach_advantage=200),simple=list(correct_test_rt_mean=405,correct_test_rt_median=405,correct_test_rt_sd=sqrt(66500/19)),
  choice=list(correct_test_rt_mean=325,correct_test_rt_median=325,correct_test_rt_sd=sqrt(5000/39)))
entries<-list()
for(name in names(profiles)) {
  task<-brohn_task_new(profiles[[name]],id=paste0("import-",name,"-audit"));compiled<-brohn_task_compile(task,1L)
  protocol_id<-paste0("protocol-",name,"-1")
  registry<-list(schema="brohn-implicit-protocol-registry/1.0",task=task,protocols=list(list(id=protocol_id,compiled_hash=brohn_hash(compiled),compiled=compiled)))
  trials<-Filter(function(x)x$type=="task_trial",compiled$timeline)
  latency<-function(t)if(name %in% c("iat","biat"))if(identical(t$mapping,"B"))if(t$trial_index%%2)900 else 1100 else if(t$trial_index%%2)500 else 700 else
    if(name=="aat")if(t$category_id=="target-a")if(t$action=="avoid")800 else 500 else if(t$action=="avoid")700 else 600 else
      if(name=="simple")300+10*t$trial_index else 300+10*t$position
  rows<-lapply(seq_along(trials),function(i){t<-trials[[i]];rt<-as.character(latency(t))
    stats::setNames(as.list(c("P1","true","S1","attempt-1",protocol_id,as.character(i),t$id,"true","correct",t$correct_code,t$correct_code,"true",rt,rt,"")),columns)})
  quote_cell<-function(x)paste0('"',gsub('"','""',x,fixed=TRUE),'"')
  csv<-paste0(paste(c(paste(vapply(columns,quote_cell,character(1)),collapse=","),
    vapply(rows,function(r)paste(vapply(r,quote_cell,character(1)),collapse=","),character(1))),collapse="\n"),"\n")
  csv_bytes<-charToRaw(enc2utf8(csv));json_bytes<-charToRaw(enc2utf8(brohn_json(registry)))
  csv_hash<-digest::digest(csv_bytes,algo="sha256",serialize=FALSE);registry_hash<-digest::digest(json_bytes,algo="sha256",serialize=FALSE)
  if(name=="iat")stopifnot(length(csv_bytes)==23720L,csv_hash=="a7d6fdfb544a6008fa0eb04dfd1df9cdac21f70bc4c2f266dc9c08a852de0af3",
    registry_hash=="0a40b8b2db1c1f47b08279fbcb61d7c61fe5d1c222583e19d37e243f9e207bb5")
  writeBin(csv_bytes,file.path(destination,paste0(name,".csv")))
  writeBin(json_bytes,file.path(destination,paste0(name,".registry.json")))
  metadata<-c(list(task_id=task$id,source_collection_id=paste0("original-fixture-",name),origin_statement="Original deterministic synthetic arithmetic fixture; no participant data or vendor materials.",
    source_software=NULL,source_rt_definition="first_and_final_correct_ms_from_target_onset",
    terminal_response_rule=if(name %in% c("iat","biat"))"corrected_response_or_fixed_deadline"else"first_response_or_fixed_deadline",evidence_level="declared_trial_summary"),
    stats::setNames(as.list(columns),mapping_names),list(protocol_registry=list(hash=registry_hash,bytes=length(json_bytes),media_type="application/json",
      filename=paste0(name,".registry.json"),canonical_hash=brohn_hash(registry),task_definition_hash=brohn_hash(task))))
  entries[[name]]<-list(name=name,csv=paste0(name,".csv"),csv_sha256=csv_hash,csv_bytes=length(csv_bytes),rows=length(rows),
    registry=paste0(name,".registry.json"),registry_sha256=registry_hash,metadata=metadata,expected=expected[[name]])
}
manifest<-list(schema="brohn-original-task-import-fixtures/1.0",created="2026-09-08",generator_R=as.character(getRversion()),
  provenance="Original synthetic arithmetic and compiled-table compatibility fixtures. No real people, browser/device timing, copied vendor materials or scientific population validity claims.",fixtures=entries)
writeBin(charToRaw(enc2utf8(brohn_json(manifest,TRUE))),file.path(destination,"manifest.json"))
cat("Saved five original CSV/registry pairs with frozen SHA-256 identities.\n")

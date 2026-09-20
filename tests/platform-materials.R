# Original bytes, legacy identity, registered procedures and actual ZIP/release routes.
source("R/platform-load.R", encoding="UTF-8"); brohn_load(ui=TRUE)
source("R/platform-materials.R", encoding="UTF-8"); source("R/platform-material-views.R", encoding="UTF-8")
local({
  n<-0L;check<-function(ok,label){if(!isTRUE(ok))stop(label);n<<-n+1L;cat("PASS",label,"\n")};rejects<-function(x)inherits(try(force(x),silent=TRUE),"try-error")
  folder<-tempfile("brohn-materials-");dir.create(folder);store<-brohn_open_store(file.path(folder,"a"));other<-brohn_open_store(file.path(folder,"b"))
  on.exit({brohn_close_store(store);brohn_close_store(other)},add=TRUE);brohn_initialise_library(store);brohn_initialise_library(other)
  first<-file.path(folder,"first.png");second<-file.path(folder,"second.png");bad<-file.path(folder,"invalid.png")
  file.copy("examples/stimuli/sample-design-a.png",first);file.copy("examples/stimuli/sample-design-b.png",second);writeBin(charToRaw("Original invalid PNG"),bad)
  d<-brohn_new_design("Original material evidence");for(i in seq_along(d$stimuli))d$stimuli[[i]]$content<-paste("Original text",i)
  legacy_json<-brohn_json(d);legacy_protocol<-brohn_json(brohn_compile(d,1L));brohn_validate_design(d)
  check(identical(brohn_json(d),legacy_json)&&identical(brohn_json(brohn_compile(d,1L)),legacy_protocol),"Absent image descriptions do not mutate the legacy design or compiled protocol")
  id<-d$stimuli[[1]]$id
  check(rejects(brohn_material_attach_png(store,d,"stimulus",id,path=bad,image_alt="Claimed image")),"Malformed image bytes fail the complete existing PNG decoder")
  check(rejects(brohn_material_attach_png(store,d,"stimulus",id,path=first,image_alt="")),"New authored image requires its researcher-provided description")
  alt<-"Original green package <script>literal</script>"
  d<-brohn_material_attach_png(store,d,"stimulus",id,path=first,image_alt=alt)
  hash<-digest::digest(file=first,algo="sha256")
  check(d$stimuli[[1]]$asset$hash==hash&&d$stimuli[[1]]$image_alt==alt,"PNG authoring preserves exact source bytes and literal description")
  d$stimuli[[1]]$aois<-list(list(id="region-original",label="Original region",x=.1,y=.1,width=.2,height=.2,asset_hash=hash))
  described<-brohn_material_describe(d,"stimulus",id,image_alt="Revised description")
  check(identical(described$stimuli[[1]]$aois,d$stimuli[[1]]$aois)&&identical(described$stimuli[[1]]$asset,d$stimuli[[1]]$asset),"Description-only edit preserves original image identity and AOIs")
  same<-brohn_material_attach_png(store,d,"stimulus",id,path=first,image_alt=alt)
  different<-brohn_material_attach_png(store,d,"stimulus",id,path=second,image_alt="Original orange package")
  check(length(same$stimuli[[1]]$aois)==1L&&length(different$stimuli[[1]]$aois)==0L,"Only replacement with different image bytes clears current areas")
  text<-brohn_material_use_text(d,"stimulus",id,text="")
  check(text$stimuli[[1]]$type=="text"&&is.null(text$stimuli[[1]]$asset)&&is.null(text$stimuli[[1]]$image_alt)&&!length(text$stimuli[[1]]$aois)&&length(brohn_design_issues(text,TRUE))>0,"Passive removal preserves an honest incomplete text draft and clears image-bound areas")
  profiles<-names(brohn_task_profiles());d$blocks<-lapply(profiles,brohn_task_new)
  procedure<-function(compiled){compiled$design_hash<-NULL;compiled$timeline<-lapply(compiled$timeline,function(s){s$material<-NULL;s});compiled}
  for(i in 1:3){
    block<-d$blocks[[i]];before<-brohn_task_compile(block,2L);mid<-block$materials[[1]]$id
    d<-brohn_material_attach_png(store,d,"exemplar",mid,block$id,first,"first.png",paste("Original task illustration",i))
    after<-brohn_task_compile(d$blocks[[i]],2L)
    check(identical(procedure(before),procedure(after))&&!identical(before$design_hash,after$design_hash),paste(profiles[[i]],"image edit versions source identity while preserving trial identities, mappings, timing and scoring procedure"))
    check(rejects(brohn_material_use_text(d,"exemplar",mid,block$id,"")),paste(profiles[[i]],"cannot save an empty replacement exemplar"))
    restored<-brohn_material_use_text(d,"exemplar",mid,block$id,"Original replacement text")
    check(restored$blocks[[i]]$materials[[1]]$content=="Original replacement text"&&is.null(restored$blocks[[i]]$materials[[1]]$image_alt),paste(profiles[[i]],"text replacement retains category identity and removes optional image field"))
  }
  for(i in 4:5)check(rejects(brohn_material_target(d,"exemplar","nonexistent",d$blocks[[i]]$id)),paste(profiles[[i]],"keeps its fixed procedure cues"))
  legacy<-d$stimuli[[1]];legacy$image_alt<-NULL
  check(brohn_material_description(legacy,"stimulus")=="Study image"&&brohn_material_description(list(content="Original legacy exemplar"),"exemplar")=="Original legacy exemplar","Legacy participant descriptions retain their exact prior fallback")
  invalid<-d;invalid$stimuli[[1]]$image_alt<-paste(rep("\u00e9",1001),collapse="")
  check(rejects(brohn_validate_design(invalid)),"Description limit counts UTF-8 bytes")
  saved<-brohn_put_entity(store,"study",d$id,d);release<-brohn_publish(store,d$id,"sample");app<-brohn_delivery_app(store)
  get<-function(token,hash)app$call(list(PATH_INFO=paste0("/api/assets/",token,"/",hash),REQUEST_METHOD="GET"))
  response<-get(release$token,hash)
  check(response$status==200L&&digest::digest(file=response$body$file,algo="sha256")==hash,"Actual release capability serves the exact authored PNG")
  newer<-brohn_material_attach_png(store,d,"stimulus",id,path=second,image_alt="Replacement source")
  brohn_save_study(store,newer,saved$revision)
  check(get(release$token,newer$stimuli[[1]]$asset$hash)$status==404L&&get(release$token,hash)$status==200L,"Draft replacement cannot change the prior release's asset scope")
  clone<-brohn_clone_study(store,d$id);template<-brohn_save_template(store,d$id);reused<-brohn_use_template(store,template$id)
  check(clone$body$stimuli[[1]]$image_alt=="Replacement source"&&reused$body$blocks[[1]]$materials[[1]]$image_alt=="Original task illustration 1","Clone/template reuse retains participant descriptions and immutable media")
  package<-brohn_export_design(store,d$id,file.path(folder,"original.brohn-study.zip"));imported<-brohn_import_design(other,package)
  check(imported$body$stimuli[[1]]$image_alt=="Replacement source"&&identical(lapply(imported$body$blocks[1:3],function(b)b$materials[[1]]$image_alt),lapply(newer$blocks[1:3],function(b)b$materials[[1]]$image_alt))&&file.exists(brohn_object_path(other,hash)),"Real portable ZIP roundtrip preserves passive and all three task image descriptions/bytes")
  for(mime in c("image/webp","image/gif","audio/wav","video/mp4")){
    native<-if(startsWith(mime,"image"))"image" else if(startsWith(mime,"audio"))"audio" else "video"
    m<-list(type=native,asset=list(media_type=mime));check(brohn_material_preview_type(m)==native,paste(mime,"selects the actual native media renderer"))
  }
  check(!"image/gif" %in% names(.brohn_port_formats()),"Existing GIF delivery support does not widen portable formats")
  check(!length(brohn_runs(store))&&!length(brohn_runs(other)),"Material preparation and reuse allocate no participant sessions")
  cat("PASS",n,"material domain checks\n")
})

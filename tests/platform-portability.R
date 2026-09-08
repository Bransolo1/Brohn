# Real ZIP/catalog roundtrips with original synthetic media and adversarial ZIPs.
# Parent review supplies an independent check of this implementation workstream.
source("R/platform-core.R", encoding = "UTF-8")
source("R/platform-store.R", encoding = "UTF-8")
source("R/platform-portability.R", encoding = "UTF-8")

local({
  checks <- 0L
  check <- function(name, ok) { if (!isTRUE(ok)) stop(paste("Portability assertion failed:", name), call. = FALSE); checks <<- checks + 1L }
  rejected <- function(expression, pattern = NULL) {
    result <- tryCatch({force(expression); NULL}, error = function(e) conditionMessage(e))
    !is.null(result) && (is.null(pattern) || grepl(pattern, result, ignore.case = TRUE))
  }
  root <- .brohn_port_temp()
  source_store <- brohn_open_store(file.path(root, "source"))
  target <- brohn_open_store(file.path(root, "destination"))
  on.exit({brohn_close_store(target); brohn_close_store(source_store); .brohn_port_cleanup(root)}, add = TRUE)
  png_file <- file.path(root, "original.png")
  png::writePNG(array(c(1, 0, 0, 1, 0, 1, 1, 0, 0.5, 0.5, 0.5, 0.5), c(2, 2, 3)), png_file)
  object <- brohn_store_object(source_store, path = png_file, media_type = "image/png")
  original <- brohn_new_design("\u5305\u88c5 \u2013 Caf\u00e9", id = "original-portable")
  original$baseline_ms <- 10000
  original$appearance$background <- "#808080"
  original$stimuli[[1]]$type <- "image"
  original$stimuli[[1]]$asset <- c(object, list(filename = "original.png", width = 2, height = 2))
  original$stimuli[[1]]$aois <- list(list(id = "aoi-logo", label = "Logo", x = 0, y = 0, width = 0.5, height = 1, asset_hash = object$hash))
  original$stimuli[[2]]$content <- "Revised package B"
  before <- brohn_question("Familiar?", "single_choice", "before", "q-familiar")
  before$options <- list(list(id = "yes", label = "Yes", value = TRUE), list(id = "no", label = "No", value = FALSE))
  follow <- brohn_question("What is unfamiliar?", "text", "before", "q-follow")
  follow$show_if <- list(op = "equals", question_id = "q-familiar", value = FALSE)
  original$questions <- list(before, follow, original$questions[[1]])
  original$measures <- list("gaze", "questionnaire", "eda")
  saved <- brohn_put_entity(source_store, "study", original$id, original)
  source_hash <- brohn_hash(saved$body)
  invisible(brohn_put_entity(source_store, "report", "report-source", list(secret_fictional_result = 47)))
  invisible(brohn_put_entity(source_store, "participant", "person-source", list(fictional_answer = "must not export")))
  package <- brohn_export_design(source_store, original$id, file.path(root, "original.brohn-study.zip"))
  check("actual ZIP created", file.exists(package) && file.info(package)$size > 0)
  check("export leaves source immutable", identical(brohn_hash(brohn_get_entity(source_store, "study", original$id)$body), source_hash))
  inspection <- .brohn_port_temp(); on.exit(.brohn_port_cleanup(inspection), add = TRUE)
  .brohn_port_call(c("extract", "--archive", package, "--quarantine", inspection))
  manifest <- .brohn_port_read(file.path(inspection, "manifest.json"))
  check("package schema version explicit", identical(manifest$schema_version, "brohn-study-package/1.0"))
  check("package lists only four declarative documents and one asset", length(manifest$files) == 5 &&
    setequal(vapply(manifest$files, function(x) x$path, character(1)), c("design.json", "aoi.json", "recipes.json", "dependencies.json", paste0("assets/", object$hash, ".png"))))
  check("source revision and content hash retained", manifest$source$revision == 1 && identical(manifest$source$design_hash, source_hash))
  check("rights status is not fabricated", identical(manifest$rights, "researcher_review_required"))
  deps <- .brohn_port_read(file.path(inspection, "dependencies.json"))
  check("known unavailable EDA choice retained without model weights", "eda" %in% unlist(deps$measures) && length(deps$models) == 0)

  imported <- brohn_import_design(target, package, title = "Replication", project_id = "replication-project")
  design <- imported$body
  check("import creates new identity in chosen project", !identical(imported$id, original$id) && identical(imported$project_id, "replication-project") && identical(design$title, "Replication"))
  check("import creates revision one", imported$revision == 1)
  check("condition roles independently preserved", identical(design$conditions[[1]]$role, "control") && identical(design$conditions[[2]]$role, "test"))
  check("separate baseline and display preserved", design$baseline_ms == 10000 && identical(design$appearance$background, "#808080") && design$stimuli[[1]]$duration_ms == 5000)
  check("source media bytes unchanged", identical(digest::digest(file = brohn_object_path(target, object$hash), algo = "sha256"), object$hash))
  check("source asset dimensions retained", design$stimuli[[1]]$asset$width == 2 && design$stimuli[[1]]$asset$height == 2)
  check("AOI has fresh identity with original geometry and image hash", !identical(design$stimuli[[1]]$aois[[1]]$id, "aoi-logo") && design$stimuli[[1]]$aois[[1]]$width == 0.5 && identical(design$stimuli[[1]]$aois[[1]]$asset_hash, object$hash))
  check("question branch reference remapped", !identical(design$questions[[1]]$id, "q-familiar") && identical(design$questions[[2]]$show_if$question_id, design$questions[[1]]$id))
  false_answer <- setNames(list(FALSE), design$questions[[1]]$id)
  true_answer <- setNames(list(TRUE), design$questions[[1]]$id)
  check("independent false branch shows follow-up", brohn_rule(design$questions[[2]]$show_if, false_answer))
  check("independent true branch hides follow-up", !brohn_rule(design$questions[[2]]$show_if, true_answer))
  check("unconditional show_if null field retained", "show_if" %in% names(design$questions[[1]]) && is.null(design$questions[[1]]$show_if))
  check("required post-image liking retained", identical(design$questions[[3]]$scope, "after_each") && isTRUE(design$questions[[3]]$required) && length(design$questions[[3]]$options) == 7)
  first_order <- unlist(brohn_compile(design, 1)$realized_stimulus_order)
  second_order <- unlist(brohn_compile(design, 2)$realized_stimulus_order)
  check("independent AB and BA schedules survive remapping", identical(unname(first_order), brohn_ids(design$stimuli)) && identical(unname(second_order), rev(brohn_ids(design$stimuli))))
  check("imported study has no participant or results", length(brohn_list_entities(target, "participant")) == 0 && length(brohn_list_entities(target, "report")) == 0 && length(brohn_list_entities(target, "run")) == 0)
  check("lineage includes exact package hash", identical(design$lineage$package_hash, digest::digest(file = package, algo = "sha256")) && identical(design$lineage$operation, "import_design"))
  again <- brohn_import_design(target, package)
  check("explicit repeated import makes another fresh study", !identical(again$id, imported$id) && length(brohn_list_entities(target, "study")) == 2)
  check("non-ASCII original title survives default import title", startsWith(again$body$title, original$title))
  check("repeated import deduplicates immutable asset", DBI::dbGetQuery(target$con, "SELECT COUNT(*) AS n FROM objects")$n == 1)
  reexport <- brohn_export_design(target, imported$id, file.path(root, "roundtrip.brohn-study.zip"))
  check("imported design is re-exportable", file.exists(reexport))
  check("export does not overwrite existing artifact", rejected(brohn_export_design(source_store, original$id, package), "existing"))
  check("missing study revision is rejected", rejected(brohn_export_design(source_store, original$id, file.path(root, "missing.brohn-study.zip"), revision = 99)))
  check("invalid import destination project rejected", rejected(brohn_import_design(target, package, project_id = "../other")))
  mismatched <- original; mismatched$id <- "mismatched-inner"
  invisible(brohn_put_entity(source_store, "study", "mismatched-outer", mismatched))
  check("mismatched stored identity cannot export as another study", rejected(brohn_export_design(source_store, "mismatched-outer", file.path(root, "mismatched.brohn-study.zip")), "identity"))
  secret_filename <- original; secret_filename$id <- "secret-filename"; secret_filename$stimuli[[1]]$asset$filename <- "C:/private/person.png"
  invisible(brohn_put_entity(source_store, "study", secret_filename$id, secret_filename))
  check("private asset filepath cannot enter portable package", rejected(brohn_export_design(source_store, secret_filename$id, file.path(root, "secret.brohn-study.zip")), "private"))
  credential_url <- original; credential_url$id <- "credential-url"; credential_url$stimuli[[2]]$type <- "web"; credential_url$stimuli[[2]]$content <- "https://user:password@example.org/study"
  invisible(brohn_put_entity(source_store, "study", credential_url$id, credential_url))
  check("credential-bearing web URL cannot export", rejected(brohn_export_design(source_store, credential_url$id, file.path(root, "web-secret.brohn-study.zip")), "credentials"))
  recipe_design <- original; recipe_design$id <- "unregistered-recipe"; recipe_design$methods <- list(list(id = "unregistered", script = "arbitrary"))
  invisible(brohn_put_entity(source_store, "study", recipe_design$id, recipe_design))
  check("unregistered recipes are rejected without silent loss", rejected(brohn_export_design(source_store, recipe_design$id, file.path(root, "recipe-source.brohn-study.zip")), "recipe"))

  # Mutation builder only writes ZIP bytes; it never extracts malicious paths.
  mutate_script <- paste(c(
    "import sys,zipfile,json,hashlib,stat,struct",
    "source,destination,mode=sys.argv[1:]",
    "with zipfile.ZipFile(source) as z: entries=[(i.filename,z.read(i.filename)) for i in z.infolist()]",
    "data=dict(entries); manifest=json.loads(data['manifest.json'])",
    "asset=next(n for n in data if n.startswith('assets/'))",
    "def update(name,obj):",
    " data[name]=json.dumps(obj,ensure_ascii=False,separators=(',',':'),sort_keys=True).encode('utf-8')",
    " for f in manifest['files']:",
    "  if f['path']==name: f['sha256']=hashlib.sha256(data[name]).hexdigest(); f['size']=len(data[name])",
    "if mode=='missing': del data[asset]",
    "elif mode=='corrupt': data[asset]+=b'changed'",
    "elif mode=='version': manifest['schema_version']='brohn-study-package/99'",
    "elif mode in ('schema','unknown','graph'):",
    " d=json.loads(data['design.json'])",
    " if mode=='schema': d['schema_version']='brohn-design/99'",
    " if mode=='unknown': d['participants']=[{'id':'must-not-import'}]",
    " if mode=='graph': d['questions'][1]['show_if']['question_id']='nonexistent'",
    " update('design.json',d)",
    "elif mode=='aoi':",
    " d=json.loads(data['aoi.json']); d['stimuli'][0]['regions'][0]['width']=0.25; update('aoi.json',d)",
    "elif mode=='recipe':",
    " d=json.loads(data['recipes.json']); d['methods']=[{'script':'arbitrary'}]; update('recipes.json',d)",
    "elif mode=='dependency':",
    " d=json.loads(data['dependencies.json']); d['models']=[{'path':'private-model'}]; update('dependencies.json',d)",
    "elif mode=='signature':",
    " b=b'MZ'+data[asset][2:]; h=hashlib.sha256(b).hexdigest(); new='assets/'+h+'.png'; del data[asset]; data[new]=b",
    " for f in manifest['files']:",
    "  if f['path']==asset: f['path']=new; f['sha256']=h; f['size']=len(b)",
    "elif mode=='ratio': data['design.json']=b' '*1000000",
    "data['manifest.json']=json.dumps(manifest,separators=(',',':')).encode()",
    "extras={'traversal':'../escaped.txt','absolute':'/escaped.txt','drive':'C:/escaped.txt','backslash':'..\\\\escaped.txt','ads':asset+':secret','device':'AUX.txt','trailing':'design.json.','case':'Design.json','unlisted':'extra.txt'}",
    "if mode in extras: data[extras[mode]]=b'not allowed'",
    "with zipfile.ZipFile(destination,'w',compression=zipfile.ZIP_DEFLATED if mode=='ratio' else zipfile.ZIP_STORED) as z:",
    " for name,value in data.items():",
    "  if mode in ('symlink','hardlink') and name==asset:",
    "   info=zipfile.ZipInfo(name); info.create_system=3; info.external_attr=(stat.S_IFLNK|0o777)<<16 if mode=='symlink' else (stat.S_IFREG|0o600)<<16",
    "   if mode=='hardlink': info.extra=struct.pack('<HH',0x000d,0)",
    "   z.writestr(info,value)",
    "  else: z.writestr(name,value)",
    " if mode=='duplicate': z.writestr('design.json',data['design.json'])",
    " if mode=='unicode': z.writestr('caf\\u00e9.json',b'x'); z.writestr('cafe\\u0301.json',b'x')",
    "if mode=='crc':",
    " with zipfile.ZipFile(destination) as z: info=z.getinfo(asset); offset=info.header_offset",
    " with open(destination,'r+b') as f:",
    "  f.seek(offset+26); n,e=struct.unpack('<HH',f.read(4)); f.seek(offset+30+n+e+10); b=f.read(1); f.seek(-1,1); f.write(bytes([b[0]^1]))"
  ), collapse = "\n")
  cases <- c("missing", "corrupt", "version", "schema", "unknown", "graph", "aoi", "recipe", "dependency", "signature", "ratio", "traversal", "absolute", "drive", "backslash", "ads", "device", "trailing", "case", "unlisted", "symlink", "hardlink", "duplicate", "unicode", "crc")
  expected_studies <- length(brohn_list_entities(target, "study"))
  expected_objects <- DBI::dbGetQuery(target$con, "SELECT COUNT(*) AS n FROM objects")$n
  for (mode in cases) {
    bad_package <- file.path(root, paste0(mode, ".brohn-study.zip"))
    processx::run(.brohn_port_python(), c("-c", mutate_script, package, bad_package, mode), timeout = 30000, windows_hide_window = TRUE)
    check(paste("reject adversarial package", mode), rejected(brohn_import_design(target, bad_package)))
    check(paste("rejection leaves study and object catalog unchanged", mode),
      length(brohn_list_entities(target, "study")) == expected_studies && DBI::dbGetQuery(target$con, "SELECT COUNT(*) AS n FROM objects")$n == expected_objects)
  }
  check("traversal fixture produced no escaped file", !file.exists(file.path(dirname(root), "escaped.txt")))
  check("source data and result records remain intact", identical(brohn_hash(brohn_get_entity(source_store, "study", original$id)$body), source_hash) && length(brohn_list_entities(source_store, "report")) == 1 && length(brohn_list_entities(source_store, "participant")) == 1)

  # Preserve usable incomplete drafts without pretending a missing image exists.
  incomplete <- brohn_new_design("Needs media", id = "incomplete-source")
  incomplete$stimuli[[1]]$type <- "image"; incomplete$stimuli[[2]]$content <- "B"
  invisible(brohn_put_entity(source_store, "study", incomplete$id, incomplete))
  incomplete_package <- brohn_export_design(source_store, incomplete$id, file.path(root, "incomplete.brohn-study.zip"))
  incomplete_import <- brohn_import_design(target, incomplete_package)
  check("incomplete design imports with visible missing media", is.null(incomplete_import$body$stimuli[[1]]$asset) && length(brohn_design_issues(incomplete_import$body, publish = TRUE)) > 0)

  rollback_store <- brohn_open_store(file.path(root, "rollback"))
  on.exit(brohn_close_store(rollback_store), add = TRUE, after = FALSE)
  original_put <- brohn_put_entity
  assign("brohn_put_entity", function(...) stop("Injected save failure after asset registration"), envir = .GlobalEnv)
  injected_failed <- tryCatch(rejected(brohn_import_design(rollback_store, package), "Injected"),
    finally = assign("brohn_put_entity", original_put, envir = .GlobalEnv))
  check("failed final save is surfaced", injected_failed)
  check("batch rollback removes all new study and object registrations", length(brohn_list_entities(rollback_store, "study")) == 0 && DBI::dbGetQuery(rollback_store$con, "SELECT COUNT(*) AS n FROM objects")$n == 0)
  recovered <- brohn_import_design(rollback_store, package)
  check("retry reconciles safe orphan bytes after rollback", length(brohn_list_entities(rollback_store, "study")) == 1 && identical(recovered$body$stimuli[[1]]$asset$hash, object$hash) && identical(digest::digest(file = brohn_object_path(rollback_store, object$hash), algo = "sha256"), object$hash))

  check("database and foreign-key integrity survive all rejected packages", identical(DBI::dbGetQuery(target$con, "PRAGMA integrity_check")[[1]], "ok") && nrow(DBI::dbGetQuery(target$con, "PRAGMA foreign_key_check")) == 0)
  cat(sprintf("PASS: %d portable-design assertions (actual ZIP, independent design expectations, 25 adversarial cases, fresh local catalog)\n", checks))
})

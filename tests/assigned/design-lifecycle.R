(function() {
  # Run from the repository root, normally through scripts/run-checks.R.
  checkout <- normalizePath(".", winslash = "/", mustWork = TRUE)
  parent <- Sys.getenv("BROHN_QA_EVIDENCE_PARENT", "")
  if (!nzchar(parent)) stop("Set BROHN_QA_EVIDENCE_PARENT to a fresh external QA directory, or use scripts/run-checks.R.", call. = FALSE)
  parent <- normalizePath(path.expand(parent), winslash = "/", mustWork = TRUE)
  if (identical(tolower(parent), tolower(checkout)) || startsWith(tolower(parent), paste0(tolower(checkout), "/")))
    stop("Keep synthetic QA workspaces outside the source repository.", call. = FALSE)
  out <- file.path(parent, "assigned-design")
  stopifnot(!file.exists(out)); dir.create(out, recursive = FALSE)
  fixture <- file.path(checkout, "tests/assigned/fixtures/evidence-design.json")
  stopifnot(file.exists(fixture))
  checks <- character(); first <- NULL; store <- NULL; other <- NULL; passed <- FALSE
  check <- function(name, ok) {if (!isTRUE(ok)) stop(name, call. = FALSE); checks <<- c(checks, name)}
  refusal <- function(fn, pattern = NULL) {
    message <- tryCatch({fn(); NULL}, error = function(e) conditionMessage(e))
    !is.null(message) && (is.null(pattern) || grepl(pattern, message, ignore.case = TRUE))
  }
  on.exit({
    if (!is.null(store) && DBI::dbIsValid(store$con)) DBI::dbDisconnect(store$con)
    if (!is.null(other) && DBI::dbIsValid(other$con)) DBI::dbDisconnect(other$con)
    writeLines(jsonlite::toJSON(list(passed = passed, checks = as.list(checks), count = length(checks),
      first_failure = first, stores_closed = (is.null(store) || !DBI::dbIsValid(store$con)) &&
        (is.null(other) || !DBI::dbIsValid(other$con)),
      scope = "Real R library and design-only ZIP lifecycle; synthetic study, no participant/scientific/hardware acceptance"),
      pretty = TRUE, auto_unbox = TRUE, null = "null"), file.path(out, "RESULTS.json"))
  }, add = TRUE)
  tryCatch({
    # Use the installed ordered closure and its exact-source verification.
    # No private load-file list or function replacement is used here.
    e <- new.env(parent = .GlobalEnv)
    source("R/platform-load.R", local = e, encoding = "UTF-8")
    e$brohn_load(envir = e, ui = FALSE)
    source("R/platform-assigned-delivery-load.R", local = e, encoding = "UTF-8")
    e$brohn_load_assigned_delivery(envir = e)
    store <- e$brohn_open_store(file.path(out, "workspace")); e$brohn_initialise_library(store)
    other <- e$brohn_open_store(file.path(out, "import-workspace")); e$brohn_initialise_library(other)
    s <- e$brohn_create_study(store, "Controlled packaging comparison")
    original <- e$brohn_hash(s$body)
    legacy_copy <- e$brohn_clone_study(store, s$id)
    check("legacy creation and cloning stay in original schema", identical(legacy_copy$body$schema_version, "brohn-design/1.0.0"))
    d <- s$body; d$measures <- list("questionnaire")
    d$stimuli[[1L]]$content <- "Unchanged shared control"; d$stimuli[[2L]]$content <- "Test package"
    d <- e$brohn_add_study_stimulus_version(d, "stimulus-b", "Test package alternative", condition_id = "condition-b")
    test_ids <- e$brohn_ids(d$stimuli)[-1L]
    d$analysis_plan <- e$brohn_new_analysis_plan(); d$analysis_plan$rationale <- "Compare each assigned package against its shared control."
    d$analysis_plan$comparisons <- list(list(id = "comparison-liking", measure = "questionnaire_numeric",
      outcome_id = "q-liking", control_id = "condition-a", test_id = "condition-b"))
    extra <- e$brohn_question("Why?", "text", "after_each", "q-reason")
    extra$show_if <- list(op = "equals", question_id = "q-liking", value = d$questions[[1L]]$options[[1L]]$value)
    d$questions <- c(d$questions, list(extra))
    d$questionnaire_navigation <- e$brohn_questionnaire_navigation()
    d <- e$brohn_group_stimuli(d, test_ids, "Packaging alternatives", "one")
    check("explicit grouping retains full versioned design and shared control", identical(d$schema_version, "brohn-design/1.2.0") &&
      length(d$stimulus_assignment$arms) == 2L && identical(d$stimuli[[1L]]$content, "Unchanged shared control"))
    saved <- e$brohn_save_study(store, d, s$revision)
    check("ordinary save and read preserve complete assignment", identical(e$brohn_hash(e$brohn_study(store,s$id)$body), e$brohn_hash(d)))
    check("old study revision stays exact", identical(e$brohn_hash(e$brohn_study(store,s$id,1L)$body), original))
    check("stale save rejected", refusal(function() e$brohn_save_study(store, d, s$revision), "revision|changed"))
    broken <- d; broken$stimuli <- broken$stimuli[-3L]
    check("dangling assigned stimulus rejected without dropping group", refusal(function() e$brohn_save_study(store,broken,saved$revision)))
    impossible <- s$body; impossible$analysis_plan <- d$analysis_plan
    check("between-arm selection cannot retain paired comparison", refusal(function()
      e$brohn_group_stimuli(impossible, e$brohn_ids(impossible$stimuli), "Invalid paired layout", "one")))
    check("duplicate group membership refused", refusal(function() e$brohn_group_stimuli(d,test_ids,"Duplicate","all")))
    added <- e$brohn_add_study_stimulus_version(d, test_ids[[1L]], "Third package", "condition-b",
      assignment = d$stimulus_assignment$sets[[1L]]$id)
    check("Add version extends original show-one group and complete assignments", length(added$stimulus_assignment$sets[[1L]]$members)==3L && length(added$stimulus_assignment$arms)==3L)
    everyone <- e$brohn_add_study_stimulus_version(d, test_ids[[1L]], "Extra shared control", "condition-a", assignment = "always")
    check("explicit shared version keeps original assignment exact", identical(everyone$stimulus_assignment,d$stimulus_assignment))
    clone <- e$brohn_clone_study(store,s$id)
    c <- clone$body
    check("clone receives fresh study graph and original full lineage", !identical(c$id,d$id) &&
      !any(e$brohn_ids(c$stimuli) %in% e$brohn_ids(d$stimuli)) && identical(c$lineage$design_hash,e$brohn_hash(d)))
    check("clone preserves control roles and comparison mappings", identical(vapply(c$conditions,`[[`,character(1),"role"),vapply(d$conditions,`[[`,character(1),"role")) &&
      identical(c$analysis_plan$comparisons[[1L]]$control_id,c$conditions[[1L]]$id) &&
      identical(c$analysis_plan$comparisons[[1L]]$outcome_id,c$questions[[1L]]$id))
    check("clone maps questionnaire branch dependencies", identical(c$questions[[2L]]$show_if$question_id,c$questions[[1L]]$id))
    check("clone assignment members and arms remain internally linked", all(vapply(c$stimulus_assignment$sets[[1L]]$members,`[[`,character(1),"stimulus_id") %in% e$brohn_ids(c$stimuli)) &&
      all(vapply(c$stimulus_assignment$arms,function(a)a$choices[[1L]]$set_id,character(1))==c$stimulus_assignment$sets[[1L]]$id))
    template <- e$brohn_save_template(store,s$id)
    reused <- e$brohn_use_template(store,template$id)
    check("saved design template retains and reuses complete assigned design", identical(template$body$schema_version,"brohn-template/1.1.0") &&
      length(reused$body$stimulus_assignment$arms)==2L && identical(reused$body$lineage$design_hash,e$brohn_hash(d)))
    archive <- file.path(out,"assigned.brohn-study.zip")
    e$brohn_export_design(store,s$id,archive)
    imported <- e$brohn_import_design(other,archive)
    check("portable assignment imports as new design without results", !identical(imported$id,d$id) &&
      length(imported$body$stimulus_assignment$arms)==2L && identical(imported$body$lineage$design_hash,e$brohn_hash(d)))
    check("portable helper uses this installed checkout", identical(normalizePath(e$.brohn_portability_helper, winslash = "/", mustWork = TRUE),
      normalizePath(file.path(checkout, "R/assigned-authoring/scripts/portable-design.py"), winslash = "/", mustWork = TRUE)))
    quarantine <- file.path(out,"inspection"); dir.create(quarantine)
    e$.brohn_port_call(c("extract","--archive",archive,"--quarantine",quarantine))
    manifest <- e$.brohn_port_read(file.path(quarantine,"manifest.json"))
    check("new package version explicitly names full design schema", identical(manifest$schema_version,"brohn-study-package/1.1") &&
      identical(manifest$design_schema_version,"brohn-design/1.2.0") && "evidence_provenance" %in% names(manifest$source))
    manifest$design_schema_version <- "brohn-design/1.0.0"
    e$.brohn_port_write(manifest,file.path(quarantine,"manifest.json"))
    check("package and design schema mismatch rejected", refusal(function() e$.brohn_port_call(c("validate-directory","--directory",quarantine))))
    manifest$design_schema_version <- "brohn-design/1.2.0"
    e$.brohn_port_write(manifest,file.path(quarantine,"manifest.json"))
    writeLines("throw new Error('must never execute');",file.path(quarantine,"runtime.js"))
    check("portable uploaded runtime rejected", refusal(function() e$.brohn_port_call(c("validate-directory","--directory",quarantine)),"unsupported"))
    legacy_archive <- file.path(out,"legacy.brohn-study.zip")
    e$brohn_export_design(store,s$id,legacy_archive,revision=1L)
    legacy_import <- e$brohn_import_design(other,legacy_archive)
    check("legacy package continues to import as original schema", identical(legacy_import$body$schema_version,"brohn-design/1.0.0"))
    archived <- e$brohn_archive_study(store,s$id,TRUE,saved$revision)
    check("assigned study archives with original body retained", isTRUE(archived$body$archived) &&
      identical(e$brohn_hash(archived$body$stimulus_assignment),e$brohn_hash(d$stimulus_assignment)))
    check("archived edits refused", refusal(function() e$brohn_save_study(store,archived$body,archived$revision),"Restore"))
    restored <- e$brohn_archive_study(store,s$id,FALSE,archived$revision)
    check("restoring retains complete saved design", identical(e$brohn_hash(restored$body),e$brohn_hash(d)))
    check("final original historical revision exact", identical(e$brohn_hash(e$brohn_study(store,s$id,1L)$body),original))
    hidden_archive <- d; hidden_archive$archived <- TRUE
    check("ordinary Save cannot bypass archive recruitment gate", refusal(function() e$brohn_save_study(store,hidden_archive,restored$revision),"Archive|Restore"))
    evidence <- e$brohn_parse(rawToChar(readBin(fixture,"raw",n=file.info(fixture)$size)))
    e$brohn_validate_study_design(evidence)
    evidence_hash <- e$brohn_method_evidence_design_value_hash(evidence)
    es <- e$brohn_put_entity(store,"study",evidence$id,evidence,expected_revision=0L,project_id=evidence$project_id)
    ec <- e$brohn_clone_study(store,es$id)
    check("evidence clone retains complete task inputs and capsule", e$.brohn_meb_equal(ec$body$blocks,evidence$blocks) &&
      e$.brohn_meb_equal(ec$body$method_evidence$current,evidence$method_evidence$current))
    check("evidence clone records exact original ancestry", length(ec$body$method_evidence$ancestry$nodes)==1L &&
      identical(ec$body$method_evidence$ancestry$nodes[[1L]]$source$design_value_hash,evidence_hash))
    et <- e$brohn_save_template(store,es$id); eu <- e$brohn_use_template(store,et$id)
    check("evidence template reuses preserved source and task binding", e$.brohn_meb_equal(eu$body$blocks,evidence$blocks) && length(eu$body$method_evidence$ancestry$roots)==1L)
    eb <- et$body; eb$evidence_source$design_ref$id <- "other-study"
    bad_template <- e$brohn_put_entity(store,"template",et$id,eb,et$revision,et$project_id)
    check("template cannot substitute another study's ancestry", refusal(function()e$brohn_use_template(store,et$id),"provenance"))
    modified <- evidence; modified$blocks[[1L]]$title <- "Unbound edit"
    check("bound task change is rejected without rewriting evidence", refusal(function()e$brohn_save_study(store,modified,es$revision)))
    titled <- evidence; titled$title <- "Edited study title"
    er <- e$brohn_save_study(store,titled,es$revision)
    check("ordinary study text edit retains exact evidence", e$.brohn_meb_equal(er$body$method_evidence,evidence$method_evidence))
    evidence_archive <- file.path(out,"evidence.brohn-study.zip")
    e$brohn_export_design(store,es$id,evidence_archive)
    ei <- e$brohn_import_design(other,evidence_archive)
    check("portable evidence retains exact complete task and source ancestry", e$.brohn_meb_equal(ei$body$blocks,evidence$blocks) &&
      identical(ei$body$method_evidence$ancestry$roots[[1L]]$operation,"import_design"))
    retained <- e$brohn_group_stimuli(er$body,e$brohn_ids(er$body$stimuli),"All materials","all")
    rs <- e$brohn_save_study(store,retained,er$revision)
    rc <- e$brohn_clone_study(store,rs$id)
    check("evidence-backed assignment preserves full schema and evidence task graph", identical(rc$body$evidence_mode,"retained_1.1") &&
      e$.brohn_meb_equal(rc$body$blocks,retained$blocks) && identical(rc$body$lineage$design_hash,e$brohn_hash(retained)))
    passed <- TRUE
  }, error = function(c) { first <<- list(message = conditionMessage(c), call = paste(deparse(conditionCall(c)), collapse = " ")) })
  if (!passed) stop(first$message, call. = FALSE)
})()

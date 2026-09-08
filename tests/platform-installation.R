# Run with an explicit freshly restored library when checking installation.
# Rscript --vanilla tests/platform-installation.R [library]
args <- commandArgs(trailingOnly = TRUE)
local({
  checks <- 0L
  check <- function(name, value) {if (!isTRUE(value)) stop("Installation QA failed: ", name, call. = FALSE); checks <<- checks+1L}
  project <- normalizePath(".", winslash = "/", mustWork = TRUE)
  library <- if (length(args)) args[[1]] else "../../work/r-library-brohn-restore"
  stopifnot(dir.exists(library)); library <- normalizePath(library, winslash = "/", mustWork = TRUE)
  .libPaths(c(library, .Library), include.site = FALSE)
  source("scripts/doctor.R")
  stopifnot(requireNamespace("processx", quietly = TRUE), requireNamespace("jsonlite", quietly = TRUE))
  root <- tempfile("brohn-install-qa-"); dir.create(root); root <- normalizePath(root, winslash = "/")
  on.exit({actual <- normalizePath(root, winslash = "/", mustWork = FALSE)
    stopifnot(startsWith(tolower(actual), paste0(tolower(normalizePath(tempdir(), winslash = "/")), "/")), grepl("^brohn-install-qa-", basename(actual)))
    unlink(actual, recursive = TRUE, force = TRUE)}, add = TRUE)
  rscript <- file.path(R.home("bin"), if (.Platform$OS.type == "windows") "Rscript.exe" else "Rscript")
  invoke <- function(arguments, env = c()) processx::run(rscript, c("--vanilla", "scripts/doctor.R", "--library", library, "--json", arguments),
    env = c(Sys.getenv(), LC_ALL = "C", env), timeout = 600, error_on_status = FALSE, cleanup_tree = TRUE, windows_hide_window = TRUE)
  parse <- function(run) jsonlite::fromJSON(trimws(run$stdout), simplifyVector = FALSE)
  absent <- file.path(root, "absent-python.exe")
  core <- brohn_doctor_core(project, library)
  check("fresh installed library matches every locked version and namespace", core$status == "ready" && length(core$packages) == length(jsonlite::fromJSON("renv.lock")$Packages) && all(vapply(core$packages, function(x) x$namespace == "loaded_from_selected_library", logical(1))))
  check("all connected direct dependencies belong to the checked lock", length(core$direct_dependencies) == 14L && all(vapply(core$direct_dependencies, function(x) x$declared_in_lock, logical(1))))
  check("missing explicit R library cannot silently fall back", brohn_doctor_core(project, file.path(root, "missing-library"))$status == "not_ready")
  empty <- file.path(root, "empty-library"); dir.create(empty)
  check("empty explicit R library cannot borrow the loaded jsonlite", brohn_doctor_core(project, empty)$status == "not_ready")
  altered <- file.path(root, "altered-project"); dir.create(file.path(altered, "scripts"), recursive = TRUE)
  file.copy("scripts/runtime-dependencies.R", file.path(altered, "scripts/runtime-dependencies.R"))
  lock <- jsonlite::fromJSON("renv.lock", simplifyVector = FALSE); lock$Packages$shiny$Version <- "0.0.0-original-mismatch"
  writeLines(jsonlite::toJSON(lock, auto_unbox = TRUE, null = "null"), file.path(altered, "renv.lock"))
  mismatch <- brohn_doctor_core(altered, library)
  check("altered package pin reports its actual version and mismatch", mismatch$status == "not_ready" && Filter(function(x) x$name == "shiny", mismatch$packages)[[1]]$status == "mismatch")
  lock$Packages$shiny$Version <- as.character(packageVersion("shiny")); lock$R$Version <- "0.0.0"
  writeLines(jsonlite::toJSON(lock, auto_unbox = TRUE, null = "null"), file.path(altered, "renv.lock"))
  check("unsupported R version cannot report core ready", !brohn_doctor_core(altered, library)$r_matches)
  escaped <- brohn_doctor_json(list(text = paste0("quoted \" fixture\\", "\n", intToUtf8(11)), empty = list(), null = NULL, values = list(TRUE, 1.5)))
  check("dependency-free JSON remains parseable for absent-library reports", identical(jsonlite::fromJSON(escaped, simplifyVector = FALSE)$text, paste0("quoted \" fixture\\", "\n", intToUtf8(11))))
  missing <- invoke(c("--profiles", "none"), c(BROHN_PYTHON = absent))
  optional <- parse(missing)
  check("missing optional portability does not block the R application", missing$status == 0L && optional$status == "ready" && optional$portability$status == "missing")
  mandatory <- invoke(c("--profiles", "none", "--require-portability"), c(BROHN_PYTHON = absent))
  check("required unavailable portability yields a nonzero machine report", mandatory$status == 1L && parse(mandatory)$status == "not_ready")
  unavailable <- invoke(c("--profiles", "none", "--required-profiles", "methods"), c(BROHN_PYTHON_METHODS = absent))
  detail <- parse(unavailable)
  check("required scientific profile is checked even when not selected optionally", unavailable$status == 1L && length(detail$scientific) == 1L && detail$scientific[[1]]$required && detail$scientific[[1]]$status == "missing")
  check("bad explicit Python path never uses the prepared fallback", is.null(detail$scientific[[1]]$path) && detail$scientific[[1]]$configured)
  invalid <- invoke(c("--profiles", "not-a-profile"))
  check("unregistered profile cannot launch arbitrary imports", invalid$status != 0L && grepl("Usage:", invalid$stderr, fixed = TRUE))
  missing_library <- processx::run(rscript, c("--vanilla", "scripts/doctor.R", "--library", empty, "--profiles", "none", "--json"),
    env = c(Sys.getenv(), LC_ALL = "C", BROHN_PYTHON = absent), timeout = 30, error_on_status = FALSE, cleanup_tree = TRUE, windows_hide_window = TRUE)
  check("completely missing dependencies still produce a JSON error report", missing_library$status == 1L && parse(missing_library)$core$status == "not_ready")

  # These are read-only checks of currently prepared runtimes, not a fresh
  # scientific wheel installation or scientific-algorithm validation claim.
  all <- invoke(c("--required-profiles", paste(.brohn_doctor_profiles, collapse = ","), "--require-portability", "--require-ffprobe"))
  full <- parse(all)
  if (all$status != 0L) stop("Current prepared runtime doctor failed: ", all$stdout, call. = FALSE)
  check("actual doctor coordinates all four isolated worker environments", full$status == "ready" && length(full$scientific) == 4L && all(vapply(full$scientific, function(p) p$status == "ready", logical(1))))
  check("doctor requires a usable report publication runtime", isTRUE(full$publication$required) && full$publication$status == "ready" && isTRUE(full$publication$ready))
  check("full pinned dependency closures are inspected", identical(vapply(full$scientific, function(p) length(p$detail$packages), integer(1)), c(38L, 54L, 43L, 26L)))
  check("all declared worker imports and dependency consistency checks pass", all(vapply(full$scientific, function(p) p$detail$dependency_consistency$status == "ready" && all(vapply(p$detail$imports, function(i) i$status == "ready", logical(1))), logical(1))))
  check("face pose hand and segmentation model identities match the actual worker pins", sum(vapply(full$scientific, function(p) length(p$detail$models), integer(1))) == 4L && all(vapply(unlist(lapply(full$scientific, function(p) p$detail$models), recursive = FALSE), function(m) m$status == "ready", logical(1))))
  check("ffprobe and video decode executable availability are explicit", full$ffprobe$status == "ready" && all(vapply(full$scientific[[3]]$detail$executables, function(x) x$status == "ready", logical(1))))
  evidence <- file.path(project, "../../work/test-runs/brohn-installation-evidence"); dir.create(evidence, recursive = TRUE, showWarnings = FALSE)
  writeLines(all$stdout, file.path(evidence, "doctor.json"), useBytes = TRUE)

  python <- full$scientific[[1]]$path
  probe <- file.path(root, "negative-runtime-checks.py")
  writeLines(c("import importlib.util,json,pathlib,sys,tempfile", "spec=importlib.util.spec_from_file_location('doctor',sys.argv[1]); m=importlib.util.module_from_spec(spec); spec.loader.exec_module(m)",
    "root=pathlib.Path(sys.argv[2]); result=[]", "p=root/'mismatch.txt'; p.write_text('numpy==0.0.0\\noriginal-brohn-package-does-not-exist==1.0.0\\n')",
    "r=m.package_checks(p); result.extend([r[0]['status']=='mismatch',r[1]['status']=='missing'])",
    "p.write_text('numpy>=1.0\\n')", "try: m.pins(p); result.append(False)", "except ValueError: result.append(True)",
    "p.write_text('numpy==1.0\\nNumPy==1.0\\n')", "try: m.pins(p); result.append(False)", "except ValueError: result.append(True)",
    "result.append(m.import_checks(['original_brohn_missing_import'])[0]['status']=='failed')",
    "result.append(m.model_check(root/'absent-model.task','0'*64,2)['status']=='missing')",
    "p=root/'original-model.task'; p.write_bytes(b'AB'); result.append(m.model_check(p,'0'*64,2)['status']=='mismatch')",
    "result.append(m.model_check(p,'0'*64,3)['status']=='mismatch')", "print(json.dumps(result))"), probe)
  negative <- processx::run(python, c("-B", probe, file.path(project, "scripts/check-scientific-runtime.py"), root), timeout = 30, cleanup_tree = TRUE, windows_hide_window = TRUE)
  outcomes <- jsonlite::fromJSON(negative$stdout)
  check("Python checker rejects missing and mismatched versions models and imports", length(outcomes) == 8L && all(outcomes))
  if (.Platform$OS.type == "windows") {
    ps <- unname(Sys.which("pwsh")); if (!nzchar(ps)) ps <- unname(Sys.which("powershell"))
    install <- processx::run(ps, c("-NoProfile", "-File", "scripts/install-python-profiles.ps1", "-PythonPath", python,
      "-Destination", file.path(project, "original-rejected-install"), "-Profiles", "methods"), timeout = 30, error_on_status = FALSE, cleanup_tree = TRUE, windows_hide_window = TRUE)
    check("installer rejects repository destinations before any package changes", install$status != 0L && !dir.exists(file.path(project, "original-rejected-install")) && grepl("outside the repository", install$stderr, fixed = TRUE))
    existing <- file.path(root, "existing-profiles"); dir.create(file.path(existing, "methods-venv"), recursive = TRUE)
    install <- processx::run(ps, c("-NoProfile", "-File", "scripts/install-python-profiles.ps1", "-PythonPath", python,
      "-Destination", existing, "-Profiles", "methods"), timeout = 30, error_on_status = FALSE, cleanup_tree = TRUE, windows_hide_window = TRUE)
    check("installer refuses to upgrade or replace existing profile directories", install$status != 0L && grepl("already exists", install$stderr, fixed = TRUE) && length(list.files(file.path(existing, "methods-venv"))) == 0L)
  }
  writeLines(jsonlite::toJSON(list(schema = "brohn-installation-evidence/1.0", checks = checks, library = library,
    evidence = "Fresh exact R restore namespaces plus existing prepared scientific runtimes; no new Python installation or hardware validation."), auto_unbox = TRUE, pretty = TRUE), file.path(evidence, "results.json"))
  cat(sprintf("PASS: %d local installation/readiness assertions; exact restored R namespaces, required/optional profiles, negative paths/pins, existing prepared runtimes.\n", checks))
})

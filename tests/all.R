# One entry point for native domain, numerical and Shiny workflow verification.
for (test in c("run", "analysis", "sample-analysis", "comparison", "presentation", "sample-json", "gaze-import", "import-report", "protocol", "protocol-storage", "app"))
  source(paste0("tests/", test, ".R"), encoding = "UTF-8")
cat("PASS: all native checks\n")

# Original synthetic design images for UI demonstrations, never research evidence.
arguments <- commandArgs(trailingOnly = TRUE)
directory <- if (length(arguments)) arguments[[1]] else file.path(tempdir(), "research-stimuli")
dir.create(directory, recursive = TRUE, showWarnings = FALSE)
for (design in c("A", "B")) {
  path <- file.path(directory, paste0("sample-design-", tolower(design), ".png"))
  grDevices::png(path, width = 800, height = 600, res = 100)
  par(mar = rep(0, 4), xaxs = "i", yaxs = "i")
  plot.new(); plot.window(xlim = c(0, 800), ylim = c(0, 600))
  rect(0, 0, 800, 600, col = "#f4eee4", border = NA)
  accent <- if (design == "A") "#37584c" else "#bc582f"
  rect(265, 90, 535, 525, col = accent, border = NA)
  rect(280, 108, 520, 505, border = "#eee2c5", lwd = 2)
  text(400, 454, "FIELD NOTES", col = "#fff7e8", cex = 1.5, font = 2)
  text(400, 426, "A QUIETER KIND OF COFFEE", col = "#f8e9cd", cex = 0.6)
  symbols(400, if (design == "A") 305 else 335, circles = 57, inches = FALSE,
          add = TRUE, bg = "#e6c899", fg = NA)
  text(400, if (design == "A") 305 else 335, "FN", col = accent, cex = 1.8, font = 2)
  text(400, 194, if (design == "A") "EVERYDAY BLEND" else "A LITTLE EVERYDAY JOY", col = "#fff7e8", cex = 0.85, font = 2)
  text(400, 164, "WHOLE BEAN / 250 g", col = "#f8e9cd", cex = 0.65)
  text(400, 46, paste("Synthetic sample - design", design), col = "#675f54", cex = 0.9)
  grDevices::dev.off()
}
cat(normalizePath(directory, winslash = "/"), "\n")

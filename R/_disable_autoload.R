# This application uses the explicit ordered brohn_load in app.R.
# Shiny otherwise sources all top-level R files alphabetically before app.R,
# evaluating processing-retry-dispatch before its worker-dispatch dependency.
# This documented per-application marker disables only that automatic pass.
# https://shiny.posit.co/r/reference/shiny/latest/loadsupport.html

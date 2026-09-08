source('R/platform-load.R', encoding = 'UTF-8'); brohn_load(ui = TRUE)
local({
  count <- 0L
  check <- function(label, ok) {if (!isTRUE(ok)) stop('Report presentation: ', label); count <<- count+1L}
  html <- function(x) htmltools::renderTags(x)$html
  design <- list(questions = list(list(id = 'q-original', prompt = 'How much do you like this original pack?')),
    scales = list(list(id = 'scale-original', label = 'Original composite, unqualified')))
  contrast <- list(control_label = 'Standard pack', test_label = 'Test pack', metric = 'temperature_mean',
    outcome_id = 'original_degrees_f', unit = 'degC', estimate = 8, participant_count = 3L, paired_session_count = 4L,
    excluded_session_count = 1L, interval95 = list(lower = -2, upper = 18), p_adjusted = .15,
    multiplicity = list(method = 'holm', family_size = 3L), aggregation = 'Original independent fictional example.')
  check('explicit saved label has priority', identical(.brohn_contrast_label(c(contrast, list(outcome_label = 'Exact saved label')), design), 'Exact saved label'))
  question <- contrast; question$outcome_id <- 'q-original'; question$metric <- 'explicit_rating'
  check('question wording comes only from the supplied frozen design', identical(.brohn_contrast_label(question, design), design$questions[[1]]$prompt))
  scale <- contrast; scale$outcome_id <- 'scale-original'; scale$metric <- 'assessment_scale_score'
  check('scale label resolves the exact scale identity', identical(.brohn_contrast_label(scale, design), design$scales[[1]]$label))
  collision <- contrast; collision$modality <- 'temperature'; collision$outcome_id <- 'q-original'
  check('a temperature channel named like a question never inherits its prompt', identical(.brohn_contrast_label(collision, design), 'Mean temperature'))
  collision$outcome_id <- 'scale-original'
  check('a temperature channel named like a scale never inherits its label', identical(.brohn_contrast_label(collision, design), 'Mean temperature'))
  collision$outcome_id <- 'q-original'; collision$metric <- 'original_physical_metric'
  check('an unknown physical quantity keeps its ID despite a question collision', identical(.brohn_contrast_label(collision, design), 'Recorded measure: q-original'))
  shared <- design; shared$scales[[1]]$id <- 'q-original'; scale$outcome_id <- 'q-original'
  check('scale and individual-item labels resolve only their registered metric namespaces', identical(.brohn_contrast_label(scale, shared), shared$scales[[1]]$label) && identical(.brohn_contrast_label(question, shared), shared$questions[[1]]$prompt))
  check('known metric has a descriptive label', identical(.brohn_contrast_label(contrast), 'Mean temperature'))
  unknown <- contrast; unknown$metric <- 'original_custom_metric'; unknown$outcome_id <- 'unresolved-original-id'
  check('unknown constructs retain an honest exact ID', identical(.brohn_contrast_label(unknown), 'Recorded measure: unresolved-original-id'))
  check('unit presentation changes notation only', identical(vapply(c('degC', 'm/s2', 'm/s3', 'degC/min', 'original/unit'), .brohn_contrast_unit, character(1), USE.NAMES = FALSE),
    c('\u00b0C', 'm/s\u00b2', 'm/s\u00b3', '\u00b0C/min', 'original/unit')))
  before <- brohn_hash(contrast); rendered <- html(brohn_contrast_ui(contrast))
  check('effect/people/visits/interval/multiplicity values remain displayed', all(vapply(c('+8 \u00b0C', '3 eligible people', '4 paired sessions', '-2 to 18 \u00b0C', '0.15 across 3 declared comparisons'), grepl, logical(1), x = rendered, fixed = TRUE)))
  check('stored metric, channel and original unit remain in details', all(vapply(c('How this comparison was calculated', 'original_degrees_f', 'temperature_mean', 'Stored unit: degC'), grepl, logical(1), x = rendered, fixed = TRUE)))
  check('rendering is pure', identical(brohn_hash(contrast), before))
  missing <- contrast; missing$estimate <- NULL; missing$interval95 <- NULL; missing$p_adjusted <- NULL
  missing$reason <- 'duplicate_or_ambiguous_observation_identity'; missing$participant_count <- 0L; missing$paired_session_count <- 0L
  missing_html <- html(brohn_contrast_ui(missing))
  check('duplicate identity is explicitly unavailable with actual reason and next step', all(vapply(c('Comparison unavailable', 'Multiple records share the same participant', 'Review the source intervals', 'Fragments of one presentation', 'duplicate_or_ambiguous_observation_identity'), grepl, logical(1), x = missing_html, fixed = TRUE)))
  check('duplicate support is not described as merely zero observations', !grepl('No eligible paired observations', missing_html, fixed = TRUE))
  descriptive <- contrast; descriptive$interval95 <- NULL; descriptive$p_adjusted <- NULL; descriptive$reason <- 'at_least_two_people_needed_for_inference'
  check('a descriptive estimate stays visible beside its inference limit', all(vapply(c('+8 \u00b0C', 'descriptive difference is available', 'at least two eligible people'), grepl, logical(1), x = html(brohn_contrast_ui(descriptive)), fixed = TRUE)))
  unknown$reason <- 'original_unknown_reason'
  check('unknown support reasons are retained without guessing', grepl('Recorded support reason: original_unknown_reason', html(brohn_contrast_ui(unknown)), fixed = TRUE))
  quality <- list(selected_report_count = 3L, available_report_count = 2L, declared_comparison_count = 3L,
    estimable_comparison_count = 1L, unlinked_observation_count = 7L, eligible_observation_count = 103L,
    scientifically_qualified = FALSE, cross_modal_complete_case_filter = FALSE)
  coverage <- html(.brohn_multimodal_coverage_ui(list(quality = quality)))
  check('coverage describes reports and inference separately', grepl('2 of 3 selected source reports are available.', coverage, fixed = TRUE) && grepl('1 of 3 declared comparisons have an uncertainty interval and p-value.', coverage, fixed = TRUE))
  check('different denominators and unlinked evidence are explicit', grepl('Each measure keeps its own eligible people', coverage, fixed = TRUE) && grepl('7 source observations have no reviewed', coverage, fixed = TRUE))
  check('all technical counts remain inside expandable details', grepl('<details>', coverage, fixed = TRUE) && grepl('Inspect complete coverage counts', coverage, fixed = TRUE) && all(vapply(names(quality), function(name) grepl(gsub('_', ' ', name, fixed = TRUE), coverage, fixed = TRUE), logical(1))))
  check('missing historical coverage fields do not invent zero totals', !grepl('0 of', html(.brohn_multimodal_coverage_ui(list(quality = list()))), fixed = TRUE))
  unsafe <- contrast; unsafe$outcome_label <- '<script>untrusted</script>'
  check('saved user labels remain escaped', grepl('&lt;script&gt;', html(brohn_contrast_ui(unsafe)), fixed = TRUE) && !grepl('<script>', html(brohn_contrast_ui(unsafe)), fixed = TRUE))
  cat(sprintf('Report comprehension: %d scoped checks passed.\n', count))
})

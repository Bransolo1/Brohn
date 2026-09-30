# EDA procedures: option-level supporting-text review

Reviewed 1 October 2026 against joined source11. This is a bounded appraisal of
the four implemented EDA recipes, not scientific qualification, a new recipe or
an exhaustive contemporary EDA review. It supplements the retained 30 September
audit. Original calculations, registry02 and saved outputs are unchanged.

## Sources and scope of support

**Boucsein et al. (2012)**, *Publication recommendations for electrodermal
measurements*, Psychophysiology 49, 1017–1034,
[doi:10.1111/j.1469-8986.2012.01384.x](https://onlinelibrary.wiley.com/doi/10.1111/j.1469-8986.2012.01384.x).
Committee consensus; supporting text inspected in sections 3.1–3.2 and 6.
It distinguishes tonic and phasic measures, onset and peak timing, recovery,
response amplitude and magnitude including nonresponses. It requires explicit
amplitude criteria, windows, calibration, recording site, acquisition, baseline
and environmental reporting. The cited 0.01–0.05 µS range depends on equipment
noise and experimental conditions; it is not permission for every software
bound. This supports definitions and reporting, not Brohn detector accuracy or
an automatic inference of liking. Independence: a multi-author consensus, not
an independent empirical test of the current worker.

**Greco, Valenza, Lanata, Scilingo and Citi (2016)**, *cvxEDA: A Convex
Optimization Approach to Electrodermal Activity Processing*, IEEE Transactions
on Biomedical Engineering 63(4), 797–804,
[doi:10.1109/TBME.2015.2474131](https://doi.org/10.1109/TBME.2015.2474131),
[author manuscript](https://www.centropiaggio.unipi.it/sites/default/files/greco2015cvxeda.pdf).
Inspected model equations 2–15, section III.D, and Figure 1 caption. It separates
conductance components from a latent sparse driver using model assumptions and
regularisation. The study fixed tau1=0.7 s, fitted tau0 within 2–4 s for each
subject, and used alpha=0.0008 and gamma=0.01; the displayed experimental input
is z-score normalised. Simulations, respiratory elicitation and affective images
provide method-development evidence. These do not validate Brohn's cleaned µS
input, fixed tau0=2, subsequent peak detector or consumer preference. The
publication year is 2016 despite the 2015 DOI/manuscript. Independence: the
method authors, so independent corroboration of this exact adaptation remains.

**Bach (2014)**, *A head-to-head comparison of SCRalyze and Ledalab, two
model-based methods for skin conductance analysis*, Biological Psychology 103,
63–68, [doi:10.1016/j.biopsycho.2014.08.006](https://doi.org/10.1016/j.biopsycho.2014.08.006),
[author manuscript](https://discovery.ucl.ac.uk/1450337/1/1-s2.0-S0301051114001847-main.pdf).
Inspected sections 2, 4 and conflict-of-interest statement. Four datasets and
five contrasts favoured the tested SCRalyze approach in four comparisons and
found comparable sensitivity in one. Its 0.05 Hz filtering belongs to a specific
GLM pipeline and also applies to its design matrix; that cutoff alone does not
validate Brohn's filter-and-peak route. Stimulus-locked inference differs from
descriptive conductance summaries. The paper explicitly identifies the author
as SCRalyze's principal developer. Treat this as comparative primary evidence,
not independent validation of SCRalyze or Brohn and not universal superiority.

**Kuhn, Gerlicher and Lonsdorf (2022)**, *Navigating the manyverse of skin
conductance response quantification approaches – A direct comparison of
trough-to-peak, baseline correction, and model-based approaches in Ledalab and
PsPM*, Psychophysiology 59(9), e14058,
[doi:10.1111/psyp.14058](https://onlinelibrary.wiley.com/doi/full/10.1111/psyp.14058).
Inspected sections 3.5–3.6 and 4.1–4.5. This independent comparison of seven
approaches in two fear-conditioning datasets does not identify a universally
superior method; group discrimination can coexist with differing effect sizes
and trial-level agreement. Onset windows and peak windows are not interchangeable.
Exact algorithms, selection rules and settings need reporting. Generalisation
to commercial advertising, free-viewing or individual classification is not
established. It does not compare Brohn or cvxEDA. The April 23 correction noted
on the article concerns Table 1 orientation; no scientific correction is inferred.

**Benedek and Kaernbach (2010)**, *A continuous measure of phasic electrodermal
activity*, Journal of Neuroscience Methods 190(1), 80–91,
[doi:10.1016/j.jneumeth.2010.04.028](https://pubmed.ncbi.nlm.nih.gov/20451556/).
Metadata and abstract inspected only in this pass: continuous decomposition and
integrated phasic activity were studied using short-interval experiments and
simulation. Full-text PMC was challenged and alternative PDF retrieval failed;
no new section-level or exact-parameter claim is made. It is a lead for a CDA
route, not evidence that Brohn currently implements CDA. The authors' related
nonnegative deconvolution paper is a different procedure, not an independent
replication of this paper.

**Sjouwerman and Lonsdorf (2019)**, *Latency of skin conductance responses
across stimulus modalities*, Psychophysiology 56(4), e13307,
[doi:10.1111/psyp.13307](https://onlinelibrary.wiley.com/doi/10.1111/psyp.13307).
Metadata/abstract scope only: revisits onset latency across tactile, auditory and
visual stimulation and fear conditioning. Online publication was in 2018;
journal year is 2019. It motivates a modality-specific latency review, but this
pass does not establish a numerical window recommendation. It shares an author
with Kuhn et al.; those papers are not fully independent author groups.

## Findings from the unchanged implementation

The source receipt records exact files and functions. In-app labels and academic
claims must resolve to one of these exact four recipe versions, not just “EDA”.

1. **Continuous 1.0/1.1** use the pinned NeuroKit cleaner and separate 0.05 Hz
   high/low-pass outputs. The installed high-pass helper is not a deconvolution
   and computes tonic and phasic with separate filters; do not describe tonic as
   necessarily raw-minus-phasic. Their candidate detector retains relative
   prominence against the segment maximum (default 0.1), without an absolute µS
   minimum. `scr_count` counts retained peaks; finite onset-supported amplitudes
   have a separate denominator. Their retained duration is samples/fs; area uses
   the trapezoid over measured endpoints. These are distinct support conventions.
   Version1.1's exact-constant branch supplies raw description and withholds
   processed fields. It does not identify physiological nonresponders, rule out
   flatlining, or apply to near-constant inputs.
2. **Event high-pass 1.0** performs continuous-context filtering before event
   summaries. It uses both a relative candidate threshold and an absolute
   onset-to-peak µS threshold, explicit latency and peak windows, then first-onset
   or largest-amplitude selection. Its descriptive signed/positive phasic area
   is not automatically a latent sudomotor driver integral. No recipe-level
   universal window/threshold is academically established by the parser's bounds.
3. **Event cvxEDA defaults 1.0** cleans the conductance signal before passing it
   to the installed wrapper with fixed tau0=2, tau1=0.7, knot spacing10,
   alpha0.0008, gamma0.01 and solver tolerance1e-9. This is an explicit adaptation
   of the original model; it does not repeat the original subject-specific fit.
   Brohn measures the returned reconstructed phasic conductance, not the latent
   driver p. A fixed regulariser has units/scaling consequences: whether this
   calibration preserves intended event estimates is an unresolved inference
   from the model and code, not an observed numerical failure. The 10,000-sample
   limit is a resource limit, not a scientific maximum recording duration.
4. **Both event recipes** preserve unavailable support, missing onset, detector
   failure and recovery censoring separately from eligible nonresponse.
   Magnitude includes eligible zeros; responder amplitude does not. Overlap
   exclusion versus descriptive-only is explicit; neither declares an overlapping
   SCR causally attributable simply because decomposition completed. Baseline
   and response must have complete support in the same continuous segment.
   Recovery can be unavailable despite an otherwise supported response.

## Required product decisions and qualification work

These are prospective tasks, not passed gates. No existing output is rescored.

- Bind option-specific explanation and exact bibliography in mapping, review,
  comparison and saved report. “Candidate count” must remain distinguishable from
  a response defined by an absolute conductance criterion. Retain method,
  settings, support counts and denominator beside the result.
- Treat filter order/direction, low-pass3 Hz, high-pass0.05 Hz, edge10 s,
  retained20 s, relative threshold0.1 and fixed cvx parameters as implementation
  choices until their specific applicability is reviewed. References to a
  different pipeline cannot supply missing qualification. The planned registry
  must mark unsupported exact options honestly even where two broader sources
  discuss the decision.
- Separate question, construct and measure: describe measured conductance or a
  conditional sympathetic-response estimate. A higher response alone does not
  identify liking, valence, purchase intent or a unique cause. Pair explicit
  ratings/behaviour with a prespecified hypothesis rather than inventing a common
  “emotion score”. This is a product inference from the bounded evidence above,
  not a new validated consumer model.
- In the study flow capture calibrated units/site/device, temperature and
  movement context, continuous acquisition, measured event clock, baseline,
  matched control stimulus, exposure/recovery and expected overlap. A control
  stimulus and a physiological baseline serve different design roles. Record
  stimulus/person sampling, order and prespecified exclusions. The generic
  five-second starter is not an EDA-qualified protocol.
- For a future response-detection profile, require independently annotated data
  appropriate to sensor/site/task. Quantify agreement, missed/extra responses,
  amplitude/onset/recovery error and unavailable support. Include small noise,
  edge/gap/motion and overlapping responses. Reference arithmetic is separate
  from empirical validity. Do not silently add 0.05 µS or replace old recipes.
- For a future cvxEDA or CDA/GLM route, explicitly select the estimand and
  preprocessing/normalisation, fit policy and event model. Compare simulations
  with known driver and independent experimental datasets. Test units, scaling,
  fixed-versus-fitted constants and overlap; no algorithm is the default winner
  merely because a developer study found larger group effects.

The machine-readable review accompanying this document links the actual option
families to relevant sources and unresolved claims. It is not the live evidence
registry. Further planned EDA routes, empirical datasets, device validation and
consumer transfer remain in the wider catalogue.

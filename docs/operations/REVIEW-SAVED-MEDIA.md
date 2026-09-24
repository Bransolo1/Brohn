# Review saved facial and video/audio results

Use these views to inspect the original evidence behind an existing report.
Brohn keeps the original analysis unchanged when you move the cursor or change
the displayed range. Preparation runs in the background and saved views can be
reopened. Keep the original recording in the workspace.

## Facial observations

1. Open a saved facial-output report and select **Explore saved facial outputs**.
   Brohn prepares or reuses an index of its complete saved observations.
2. Choose a **Saved native score**. Optionally enter both recording-relative time
   bounds, then select **Apply facial view**. Empty bounds include all analysed
   frames; both entered endpoints are included.
3. Use **Inspect recording time** to select an analysed frame. Its original
   image appears when preparation finishes. Arrow keys work in the selector;
   rapid changes settle on the latest selected time.

The plot shows saved scores and detection states. Missing and multiple faces
remain visible as states. **Exact saved frame values** provides the numerical
alternative. Expand a frame's native values to inspect each detected face in
that frame. Face row numbers do not establish the same person across frames.

Download the original observation JSON or recorded-frame PNG from the selected
frame. **Prepare complete selected CSV** prepares every observation in the
applied range; **Download labelled figure** saves a standalone responsive HTML
figure with the source details. Original complete artifacts remain available
from the report itself.

Native category scores are classifier outputs. Interpretation as feelings,
attention or preference requires separate evidence. Reviewing saved values does
not need model weights; exact frame images need the original compatible FFmpeg
runtime recorded with the analysis. See the [facial runtime setup](../qa/FACIAL-RUNTIME-ACCEPTANCE.md)
and [review acceptance](../qa/FACIAL-REVIEW-ACCEPTANCE.md).

## Video beside its original audio

1. Open an acoustic report derived from a saved video. Select **Review original
   audio** and prepare or reopen its saved waveform window.
2. Select **Review video with this audio window**. Brohn inspects the recording's
   available video tracks while retaining that exact audio window.
3. Choose the **Original video stream**, enter an **Audio position (seconds)**
   inside the saved window, and select **Apply media cursor**.

The time resolves to the nearest original audio sample. Brohn displays the
video frame supported by the container timestamps at that position. An explicit
gap or ambiguous coverage produces an unavailable state. The waveform and its
cursor retain the exact saved audio samples.

Use the download controls for the frame PNG, complete video timestamp ledger,
original audio samples, original audio-frame ledger, mapping/provenance JSON
or waveform SVG. **Saved media reviews** reopens earlier saved positions.
**Back to audio review** returns to the original waveform window.

This route requires an audio extraction linked to its original video; a
standalone WAV has no inferred video association. Container timing does not
establish physical synchronization with an eye tracker, EEG or another recording.
See the [mapping method](../methods/MEDIA-SOURCE-REVIEW.md) and
[connected acceptance status](../qa/MEDIA-SOURCE-REVIEW-ACCEPTANCE.md).

## If preparation needs attention

Read the displayed reason and retry the failed preparation once its cause is
resolved. Keep the current source, permission and selected window available.
Changing the source, report or cursor invalidates old download links; reopen
the intended saved view to obtain current links. Preparation and cancellation
receipts remain in Processing. Original reports are preserved.

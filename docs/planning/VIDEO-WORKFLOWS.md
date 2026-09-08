# Video-derived workflow references

Selected paused frames captured on 5 September 2026. Only still screenshots are retained: no MP4s or other video files were downloaded or saved. The sequences below were sampled at specific points; they are not a claim that every interaction was observed or that the complete tutorials were watched.

The two tutorials are linked by [Grand Valley State University's Biometrics Lab student resources](https://www.gvsu.edu/soc/biometrics-lab-student-resources-215.htm). They are firsthand demonstrations by a university lab, not current vendor certification. They supplement newer official iMotions materials, the Tobii Pro Lab manual and official questionnaire/task-builder documentation in the atlas. Depicted builds and contemporary behaviour may differ.

## iMotions study setup

Source: [iMotions study setup tutorial](https://www.youtube.com/watch?v=8KCs2GwkGeo).

| Time | Visible state | Interaction detail to implement in an original design |
|---|---|---|
| [0:49](https://www.youtube.com/watch?v=8KCs2GwkGeo&t=49s) | [Respondent screen setup](evidence/video-frames/imotions-setup-049.png) | Explicit display geometry and participant-screen assignment. |
| [1:39](https://www.youtube.com/watch?v=8KCs2GwkGeo&t=99s) | [Study settings and sensor strip](evidence/video-frames/imotions-setup-99.png) | Study-level settings and visible acquisition capabilities. |
| [3:17](https://www.youtube.com/watch?v=8KCs2GwkGeo&t=197s) | [Instruction/survey editor](evidence/video-frames/imotions-setup-197.png) | Author text within the study sequence; preview participant content. |
| [4:56](https://www.youtube.com/watch?v=8KCs2GwkGeo&t=296s) | [Blank/baseline element](evidence/video-frames/imotions-setup-296.png) | A timed transition represented as a reusable flow element. |
| [6:34](https://www.youtube.com/watch?v=8KCs2GwkGeo&t=394s) | [Populated stimulus flow](evidence/video-frames/imotions-setup-394.png) | Fixed/random presentation and duration belong beside the sequence. |

**Observed sequence:** setup → study settings → instruction authoring → timed blank → populated flow. Intermediate clicks are not fully captured. **Our proposed improvement:** selecting a reviewed recipe supplies this structure, with advanced timing and randomisation still inspectable.

## iMotions analysis and export

Source: [iMotions Data Export Tutorial](https://www.youtube.com/watch?v=Tirkm6jlaJ4).

| Time | Visible state | Interaction detail to implement in an original design |
|---|---|---|
| [3:23](https://www.youtube.com/watch?v=Tirkm6jlaJ4&t=203s) | [Processing/source selection](evidence/video-frames/imotions-export-203.png) | Signal-processing choices need a clear source and scope. |
| [8:28](https://www.youtube.com/watch?v=Tirkm6jlaJ4&t=508s) | [AOI creation panel](evidence/video-frames/imotions-export-508.png) | Region naming, shape tools and appearance are colocated with the stimulus. |
| [13:34](https://www.youtube.com/watch?v=Tirkm6jlaJ4&t=814s) | [AOIs and gaze overlays](evidence/video-frames/imotions-export-814.png) | Layer visibility and opacity support visual inspection of the regions. |
| [15:15](https://www.youtube.com/watch?v=Tirkm6jlaJ4&t=915s) | [R processing and AFFDEX export settings](evidence/video-frames/imotions-export-915.png) | Metric families, processing options and export scope appear together. |

**Observed sequence:** processing settings → AOI tools → overlaid results → export-stage inspection. The last frame's exact contents are labelled in the atlas. **Our proposed improvement:** the recipe preselects appropriate processing and produces a traceable analysis bundle; AOI changes automatically recompute affected outputs.

## Remaining end-to-end gaps

Current authenticated iMotions acquisition/recovery, Tobii calibration failures, Qualtrics publishing permissions, and production implicit-task deployment need hands-on capture. The atlas labels documentation excerpts and feature illustrations so they cannot be mistaken for full interactive flows. Follow the capture script in [evidence coverage](EVIDENCE-COVERAGE.md) to close these gaps before freezing corresponding detailed UI specifications.

Public screenshots provide layouts and visible states. Exact validation rules, persistence, keyboard behaviour, recovery and timing require documentation, trials or implementation tests. The roadmap includes those investigations rather than inventing them from still images.

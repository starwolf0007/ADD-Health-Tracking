# Hevy exercise-match calibration

The automatic matcher is calibrated from evidence, not from a guessed score.
It may resolve an exercise only above a threshold that is higher than every
wrong candidate observed in the confirmed fixture corpus.

## Build the private corpus

Run:

```powershell
dart run tool/hevy_exercise_corpus.dart build
```

The command prompts for the Hevy API key with terminal echo disabled. The key
is not accepted as a command-line argument, printed, or written to disk.

The builder fetches every paginated exercise template, routine, and workout.
Routine/workout exercise names already carry their template IDs and are marked
`confirmed`. Canonical names are also confirmed. Deterministic abbreviations
and typos are marked `needsReview`.

Output defaults to `build/hevy_match_corpus/`, which Git already ignores:

- `catalog.json` contains template IDs and canonical names.
- `corpus.csv` contains `input`, `expected_template_id`, `source`,
  `canonical_title`, and `label_status`.

To add deliberate negative traps, create a local text file with one input per
line and pass `--no-match-file path`. Review those rows, set
`expected_template_id` to the correct ID or `NO_MATCH`, then change
`label_status` to `confirmed`. Keep private workout/routine data out of source
control.

Public program or coach-plan samples should be appended as `manual` rows. They
are not scraped automatically because their labels require human judgment and
their source files may not be redistributable.

## Calibrate

After every row used for calibration is confirmed:

```powershell
dart run tool/hevy_exercise_corpus.dart calibrate `
  --catalog build/hevy_match_corpus/catalog.json `
  --corpus build/hevy_match_corpus/corpus.csv `
  --margin 0.01
```

For every confirmed row the tool records the correct-match score and the best
wrong-match score. It then applies:

```text
threshold = highest wrong score + margin
```

The report includes the auto-resolve rate, review count, and wrong automatic
resolutions. A threshold above `1.0` is intentional: it disables automatic
resolution when the labeled evidence cannot safely distinguish a match.
If the confirmed corpus contains no wrong-match candidate at all, the tool
also fails closed by setting the threshold above `1.0`; an empty evidence set
must never be interpreted as a zero wrong-match ceiling.

The threshold is valid only for the exact scorer and corpus that produced it.
Changing normalization, aliases, scoring, or the Hevy catalog requires a fresh
calibration. If review volume is too high, add explicit aliases and fixtures;
never lower the threshold below the observed wrong-match boundary.

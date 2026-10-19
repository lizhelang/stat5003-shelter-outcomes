# STAT5003 Group Project – Predicting Shelter Outcomes (W01G04)

R Markdown report for the STAT5003 Assignment 2 group project (Austin Animal Center outcomes, multi-class classification).

- `STAT5003_group_project_RMarkdown_template_v29.Rmd` – main report (knit to HTML in RStudio).
- `Austin_Animal_Center_Outcomes_20260916.csv` – dataset read by the Rmd (keep it in the same folder as the Rmd / repo root).
- `model_comparison/` – shared CV comparison tables/figures for Section 7, plus final XGBoost holdout exports.

Shared preprocessing produces `x_train`, `y_train`, `x_test`, `y_test` and `cv_data` (5 CV folds, seed 5003); each member adds their model section using these.

## Render

From the **repository root**:

```r
rmarkdown::render("STAT5003_group_project_RMarkdown_template_v29.Rmd")
```

Requires tidyverse-style packages used in the Rmd (`dplyr`, `ggplot2`, `caret`, `lubridate`, `patchwork`, …). XGBoost scripts also need `xgboost` (this environment uses `~/R/library`).

## Final XGBoost holdout (full-train refit + one test score)

After CV selection, the selected XGBoost is refit once on the full training set and scored once on the untouched holdout. Run from the **repository root** (so `Austin_Animal_Center_Outcomes_20260916.csv` and `model_comparison/` resolve correctly):

```bash
cd /path/to/stat5003-shelter-outcomes   # repository root
Rscript model_comparison/run_xgb_holdout.R
```

Or in R:

```r
setwd("/path/to/stat5003-shelter-outcomes")  # repository root
source("model_comparison/run_xgb_holdout.R")
```

**Inputs (must already exist):**

| Path | Role |
|------|------|
| `Austin_Animal_Center_Outcomes_20260916.csv` | Raw data (same as the Rmd; script rebuilds the v29 split) |
| `model_comparison/run_xgb_cv.R` | Shared preprocessing block (sourced up to the CV section) |
| `model_comparison/results/xgb_selected_metrics.csv` | Selected hyper-parameters from unified CV |
| `model_comparison/results/xgb_selected_oof_fold_scores.csv` | Fold `best_nrounds` → freeze `nrounds = round(mean(...))` (= 184) |

**Protocol:** same hyper-parameters as the unified CV OOF; `nrounds` frozen at the mean OOF early-stopped iteration; **holdout is never used for early stopping or tuning**.

**Outputs written under `model_comparison/results/`:**

| File | Contents |
|------|----------|
| `xgb_holdout_metrics.csv` | Holdout macro-F1, balanced accuracy, accuracy, `nrounds`, hyper-params |
| `xgb_holdout_per_class.csv` | Per-class precision / recall / F1 on holdout |
| `xgb_holdout_predictions.csv` | Row-wise actual vs predicted on holdout |
| `xgb_protocol.txt` | Short protocol note (CV + holdout) |

To regenerate the CV selection artefacts first (slow; only if you change the grid):

```bash
Rscript model_comparison/run_xgb_cv.R
```

See also `model_comparison/README.md`.

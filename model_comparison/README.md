# Model comparison artefacts (W01G04)

Shared evaluation inputs for Section 7 of the main report.

## Sources

| Model | Artefact |
|------|----------|
| Multinomial logistic (Zilan) | Copied from `origin/zilan` → `zilan/results/` |
| RBF SVM (Jackson) | Copied from `origin/Jackson_SVM` → `SVM_week12/svm_results/` |
| Random Forest (Daun grid) | Recomputed here with `run_rf_cv.R` on the shared v29 folds (`seed = 5003`) |
| XGBoost (Janet) | Code on `branch-janet`; numeric CV summary not yet exported |
| Decision Tree | Planned; not uploaded |

## Reproduce RF CV metrics

From the repository root (requires `dplyr`, `caret`, `ranger`, `lubridate`, …):

```r
source("model_comparison/run_rf_cv.R")
```

## Knit the report

Open `STAT5003_group_project_RMarkdown_template_v29.Rmd` in RStudio and Knit to HTML, or:

```r
rmarkdown::render("STAT5003_group_project_RMarkdown_template_v29.Rmd")
```

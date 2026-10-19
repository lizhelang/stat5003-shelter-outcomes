# Model comparison artefacts (W01G04)

Shared evaluation inputs for Section 7 of the main report.

## Sources

| Model | Artefact |
|------|----------|
| Multinomial logistic (Zilan) | `zilan/results/` (EDA association plots removed on integration branch) |
| RBF SVM (Jackson) | `SVM_week12/svm_results/` |
| Random Forest (Daun grid) | `run_rf_cv.R` on shared v29 folds (`seed = 5003`) |
| XGBoost (Janet design) | `run_xgb_cv.R` — weighted + tuned grid on the same folds |
| Decision Tree | Planned; not uploaded |

## Reproduce

```r
source("model_comparison/run_rf_cv.R")
# requires xgboost in .libPaths():
source("model_comparison/run_xgb_cv.R")
rmarkdown::render("STAT5003_group_project_RMarkdown_template_v29.Rmd")
```

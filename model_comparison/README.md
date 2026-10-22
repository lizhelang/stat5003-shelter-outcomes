# Model comparison artefacts (W01G04)

Evaluation inputs for [the current A2 report](../STAT5003_A2_W01G04.Rmd). Run the commands below from the **repository root**, except where a model's own README specifies another working directory.

## Current sources

| Model | Source and results |
|------|------|
| Multinomial logistic regression M3 | `zilan/logistic_regression.Rmd`; saved results in `zilan/results/` |
| RBF SVM | `SVM_week12/svm_model.R`; saved results in `SVM_week12/svm_results/` |
| Random forest | `model_comparison/run_rf_cv.R`; saved results in `model_comparison/results/` |
| XGBoost | `model_comparison/run_xgb_review.R`; current results in `model_comparison/review_results/` |
| Majority class (baseline) | `report_support/verify_results.R`; results in `model_comparison/review_results/` |

All four classifiers use the existing shared split and five folds (seed 5003). Decision-tree results remain unavailable.

## Current XGBoost protocol

```bash
Rscript model_comparison/run_xgb_review.R
Rscript report_support/verify_results.R
```

The driver compares A: unweighted defaults, B: weighted defaults, and C: a weighted 16-configuration grid. All fits use **150 rounds with no early stopping**. The selected grid configuration's out-of-fold predictions supply both ranking and class-level metrics. A full-training refit at the same 150-round budget supplies the held-out results. Outputs, split/fold manifests, feature importance and the XGBoost R session information are written under `model_comparison/review_results/`.

`verify_results.R` checks the shared animal assignments, folds, available row-level predictions and saved summaries. It also calculates the majority-class reference and consistent pooled out-of-fold class metrics. Random forest is checked against its existing fold and class summaries because row-level out-of-fold predictions were not exported by that workflow.

## Other model workflows

```bash
Rscript model_comparison/run_rf_cv.R
```

For logistic regression and SVM, follow [zilan/README.md](../zilan/README.md) and [SVM_week12/README.md](../SVM_week12/README.md). Existing model sources and results are retained.

## Render the current report

```r
rmarkdown::render("STAT5003_A2_W01G04.Rmd")
```

This reads saved results; it does not rerun the tuning grids.

## Earlier XGBoost workflow

`run_xgb_cv.R`, `run_xgb_holdout.R` and the XGBoost files under `results/` retain the earlier early-stopping workflow, whose final refit used 184 rounds. They are preserved for provenance and are not the XGBoost evidence used in the current report. The original template is also retained because existing model scripts extract its preprocessing code.

# STAT5003 Group Project – Predicting Shelter Outcomes (W01G04)

R Markdown report for the STAT5003 Assignment 2 group project, using Austin Animal Center outcomes for five-class classification.

## Current report

- [HTML report](STAT5003_A2_W01G04.html): download and open in a browser; figures are embedded and code is collapsed by default.
- [Report source](STAT5003_A2_W01G04.Rmd): the current report entry point.
- [A4 PDF preview](STAT5003_A2_W01G04_preview.pdf): the reviewed 10-page layout, including references and the AI statement. The HTML contains expandable code.
- `report_support/`: preprocessing, EDA, source-code display, result verification and report styling.
- `model_comparison/review_results/`: the results used by the current report.

The report compares logistic regression, random forest, SVM and XGBoost, with a majority-class baseline. Decision-tree results remain unavailable.

## Render from saved results

Run from the **repository root**:

```r
rmarkdown::render("STAT5003_A2_W01G04.Rmd")
```

Rendering uses the saved results and does not retrain the model grids. Keep `Austin_Animal_Center_Outcomes_20260916.csv`, the model directories, and `report_support/` in place. Required R packages are listed in [report_support/README.txt](report_support/README.txt).

## Verify or regenerate the model results

Check the saved predictions, metrics, animal assignments and shared folds:

```bash
Rscript report_support/verify_results.R
```

To regenerate the current XGBoost results, then verify them:

```bash
Rscript model_comparison/run_xgb_review.R
Rscript report_support/verify_results.R
```

The current XGBoost workflow compares unweighted defaults, weighted defaults and a weighted parameter grid on the same five folds. All configurations and the final full-training refit use **150 rounds, without early stopping**. The selected model is evaluated on the existing held-out partition. This reproduces the assessment on an already examined dataset; it is not a newly blinded test.

Logistic regression, random forest and SVM retain their original implementations and saved results. See [model_comparison/README.md](model_comparison/README.md), [zilan/README.md](zilan/README.md) and [SVM_week12/README.md](SVM_week12/README.md) for their workflows. The report's final folded code panel also lists the commands to reproduce the models and report.

## Retained earlier files

`STAT5003_group_project_RMarkdown_template_v29.Rmd` and its HTML are retained as the earlier report. The template is still a preprocessing dependency of existing model scripts; do not remove it. The earlier XGBoost scripts (`run_xgb_cv.R`, `run_xgb_holdout.R`) and `model_comparison/results/` are also retained. Their early-stopping protocol and 184-round final refit do not supply the current report's XGBoost results.

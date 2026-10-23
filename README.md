# STAT5003 Group Project – Predicting Shelter Outcomes (W01G04)

R Markdown report for the STAT5003 Assignment 2 group project, using Austin Animal Center outcomes for five-class classification.

## Current report

- [HTML report](STAT5003_A2_W01G04.html): download and open in a browser; figures are embedded and code is collapsed by default.
- [Report source](STAT5003_A2_W01G04.Rmd): the complete, independently runnable analysis and report.
- [Earlier A4 PDF preview](STAT5003_A2_W01G04_preview.pdf): the previous 10-page layout, retained for reference. It predates the single-file, five-model report and should be regenerated before submission.
- `report_support/` and the model subdirectories retain earlier modular workflows and their saved outputs. The current Rmd does not require them.

The report compares logistic regression, random forest, SVM, XGBoost and decision tree, with a majority-class baseline.

## Run the complete report from one Rmd

Copy just these two files into the same directory:

- `STAT5003_A2_W01G04.Rmd`
- `Austin_Animal_Center_Outcomes_20260916.csv`

Install the required R packages once:

```r
install.packages(c(
  "rmarkdown", "knitr", "htmltools", "dplyr", "tidyr", "stringr", "forcats",
  "ggplot2", "scales", "lubridate", "patchwork", "caret", "ranger",
  "xgboost", "nnet", "glmnet", "e1071", "rpart"
))
```

Use Knit to HTML in RStudio (which includes Pandoc), or run:

```r
rmarkdown::render("STAT5003_A2_W01G04.Rmd")
```

Rendering executes the full preprocessing, EDA, model fitting and tuning, predictions, in-memory verification, tables and plots. It reads only the raw CSV; every analysis code block and the CSS are inside the Rmd. No external R scripts, report template, cached models or saved result CSVs are required. All model results are passed directly between code blocks in memory.

A full render can take several minutes or longer. The default SVM workflow uses one worker; optionally set `options(stat5003.svm.workers = 3L)` before rendering to evaluate independent grid candidates concurrently. If the data file is elsewhere, pass `params = list(data_file = "/path/to/Austin_Animal_Center_Outcomes_20260916.csv")` to `rmarkdown::render`.

## Earlier modular workflows

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

Logistic regression, random forest and SVM retain their earlier standalone implementations and saved results. See [model_comparison/README.md](model_comparison/README.md), [zilan/README.md](zilan/README.md) and [SVM_week12/README.md](SVM_week12/README.md) for those workflows. These are optional historical entry points, not dependencies of the current report. The current Rmd includes its own checks for all five models.

## Retained earlier files

`STAT5003_group_project_RMarkdown_template_v29.Rmd` and its HTML are retained as the earlier report. The template is still a preprocessing dependency of the earlier model scripts, but not of the current Rmd. The earlier XGBoost scripts (`run_xgb_cv.R`, `run_xgb_holdout.R`) and `model_comparison/results/` are also retained. Their early-stopping protocol and 184-round final refit do not supply the current report's XGBoost results.

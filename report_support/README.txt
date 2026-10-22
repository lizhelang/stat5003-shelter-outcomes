Report support files

preprocessing.R preserves the shared data preparation from the existing comparison pipeline.
report_data.R assembles the new XGBoost exports and verified saved results for the other models.
verify_results.R checks animal assignments, fold labels, predictions and metric summaries.
model_code_sections.R extracts the actual retained fitting/tuning sources for folded display.
The report loads this helper in a private environment so source-extraction variables cannot overwrite results.
eda_source.R preserves all nine original EDA code bodies, loaded in an isolated environment.
rf_original_baseline.R preserves the member baseline fit, displayed without running holdout scoring.
report.css supplies screen/print formatting; native HTML details controls provide code folding.

The new report is STAT5003_A2_W01G04.Rmd. It renders from the project root and expects the saved CSV exports.
To regenerate the revised XGBoost evidence, run model_comparison/run_xgb_review.R first.
To regenerate all original models, use the retained model-specific sources and their README instructions.
Their original template dependency is deliberately retained.

R packages: rmarkdown, knitr, htmltools, dplyr, tidyr, stringr, forcats, ggplot2, scales,
lubridate, patchwork, caret, ranger, xgboost; original model refits additionally use
nnet, glmnet, e1071 and digest. The XGBoost run's package versions are recorded in
model_comparison/review_results/sessionInfo.txt; SVM records its own environment in
SVM_week12/svm_results/sessionInfo.txt. Equivalent environment manifests are not
available for the retained logistic-regression and random-forest outputs.

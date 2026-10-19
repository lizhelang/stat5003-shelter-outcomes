# Model comparison artefacts (W01G04)

Shared evaluation inputs for Section 7 of the main report. Run all scripts from the **repository root**.

## Sources

| Model | Artefact |
|------|----------|
| Multinomial logistic M3 (Zilan) | `zilan/results/` |
| RBF SVM (Jackson) | `SVM_week12/svm_results/` |
| Random Forest (Daun grid) | `run_rf_cv.R` on shared v29 folds (`seed = 5003`) |
| XGBoost CV (Janet design) | `run_xgb_cv.R` — weighted + tuned; ranking + recall from one OOF pass |
| XGBoost holdout (final) | `run_xgb_holdout.R` — full-train refit, one score on `x_test`/`y_test` |
| Decision Tree | Planned; not uploaded |

## Reproduce CV comparison

```bash
# from repository root
Rscript model_comparison/run_rf_cv.R
Rscript model_comparison/run_xgb_cv.R   # needs xgboost; slow (full grid)
```

## Final holdout (selected XGBoost)

Requires prior CV exports (`xgb_selected_metrics.csv`, `xgb_selected_oof_fold_scores.csv`) and the CSV at repo root.

```bash
# from repository root
Rscript model_comparison/run_xgb_holdout.R
```

Writes `results/xgb_holdout_metrics.csv`, `xgb_holdout_per_class.csv`, `xgb_holdout_predictions.csv`, and updates `xgb_protocol.txt`.

## Knit report

```r
rmarkdown::render("STAT5003_group_project_RMarkdown_template_v29.Rmd")
```

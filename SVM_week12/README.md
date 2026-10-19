# Week 12 — SVM contribution

Completed SVM implementation, tuning and reporting for STAT5003 W01G04. This is an independent contribution folder. The existing shared report, root README and root dataset have not been modified.

## Start here

- [SVM results report](SVM_results.html): download and open in a browser; GitHub normally shows HTML source rather than rendering the report.
- [Chinese running/integration guide](SVM_README_中文.md).
- [Integrated R Markdown copy](STAT5003_v29_with_SVM.Rmd) and its [rendered HTML](STAT5003_v29_with_SVM.html). The SVM section is complete; other model sections remain as in v29. This is not the group's completed five-model final report.
- [SVM code](svm_model.R), [standalone runner](run_svm.R), and [presentation notes](SVM_talk_notes.md).

## Reproduce

In RStudio, open `run_svm.R` and set the working directory to this **SVM_week12** folder. Install the packages listed in the Chinese guide, then run:

```r
source("run_svm.R")
```

This uses the included common v29 preprocessing, seed 5003, three local R workers, and 18 configurations across five shared folds (90 fits). Installed R libraries and computation caches are not uploaded; per-candidate caches are generated locally when rerunning. To regenerate the reports afterwards, run `source("build_deliverables.R")`.

## Development CV results

| Configuration | Mean macro-F1 | Fold SD | Mean macro recall | Mean accuracy |
|---|---:|---:|---:|---:|
| Baseline: C=1, gamma=1/p, unweighted | 0.3493 | 0.0035 | 0.3771 | 0.7948 |
| Selected: C=10, gamma=4/p, unweighted | 0.4555 | 0.0123 | 0.4400 | 0.8000 |
| Best inverse-weighted: C=1, gamma=4/p | 0.4521 | 0.0132 | 0.5146 | 0.6683 |

Here p=28 retained encoded inputs. Encoding, age standardisation and weights are learned from the respective training partition only. Balanced accuracy means mean class recall; align this definition across models.

The selected model has Adoption recall 97.7%, but Euthanasia recall only 4.6%. The best weighted alternative raises Euthanasia recall to 19.7%, at a precision/accuracy cost. See the [class-level tradeoff](svm_results/weighting_tradeoff.csv). The small macro-F1 difference does not establish definitive superiority.

The same folds were used for tuning and reporting; selected CV performance has selection optimism. **The reserved 20% test set has not been scored.** Compare all five models and agree on final selection before holdout evaluation.

## Handoff files

- [Baseline/selected comparison](svm_results/baseline_vs_selected.csv), [full grid](svm_results/tuning_summary.csv), and [90 fold scores](svm_results/cv_fold_scores.csv).
- [Out-of-fold predictions](svm_results/selected_oof_predictions.csv): `Row` identifies the row within the shared training partition, not the original CSV.
- [Per-class metrics](svm_results/oof_per_class.csv), [confusion matrix](svm_results/oof_confusion_matrix.csv), and [metric definitions](svm_results/metric_definitions.txt).
- [Training refit](svm_results/svm_training_refit.rds), [split manifest](svm_results/split_manifest.csv), and [provenance](svm_results/provenance.txt).

![Selected SVM confusion matrix](svm_results/svm_confusion_matrix.png)

## Source snapshot and validation

Source: [shared v29 at commit 2e4ca87](https://github.com/lizhelang/stat5003-shelter-outcomes/tree/2e4ca872a0c1828fa219426f781107ef3b743cd6). The CSV and original v29 Rmd inside this folder are reproducibility snapshots, not replacements for the root files. Keep them alongside the runner.

The data contain 18,624 CSV rows and 16,831 latest-intake cat/dog animals: 13,467 training and 3,364 reserved test. Some inherited descriptive text in v29 still has older A1 counts and needs group-wide review before submission. The shared AM/PM parsing audit found no changes to which animal records are retained for this snapshot; the group's sample and folds were preserved.

Metric/encoder checks (`validate_svm.R`), independent exported-result checks (`validate_outputs.R`), and both HTML renders passed. AI assistance and limitations are disclosed in the SVM report; review and reconcile the statement with the group's final disclosure.

# Multinomial logistic regression – Zhelang (Zilan) Li

My model for the W01G04 STAT5003 project: multinomial logistic regression for the five shelter outcomes (Adoption, Transfer, Return, Euthanasia, Other).

## How to run

Open `logistic_regression.Rmd` from this `zilan/` folder and knit it. It pulls the shared preprocessing straight from `../STAT5003_group_project_RMarkdown_template_v29.Rmd`: every chunk up to `common-cv-preprocessing` is extracted with `knitr::purl()` and run. So `x_train`/`x_test`, `cv_data`, seed 5003, the 80/20 split and the 5 folds are exactly the group's. The template's CSV needs to be in the repo root. Packages: dplyr, tidyr, stringr, forcats, ggplot2, scales, patchwork, lubridate, caret, nnet, glmnet, knitr, rmarkdown. A full knit takes about 5 minutes.

## What I did

- **Encoding / scaling:** dummy coding learned from the training part only. Reference levels are Cat, Female, Pure, no name, and the most common level for spay status, breed and colour. Age is standardised with training statistics.
- **Type/Age overlap:** the template already turns Puppy/Kitten into Dog/Cat. On top of that, my extended version uses a natural spline on log(1 + age), a Dog × age interaction and an `age_missing` flag. Age is very skewed and imputed ages would otherwise look like real ones.
- **Collinearity:** I checked VIFs and Cramér's V. `TypeDog` has a VIF of 18.6 because breed is partly nested in species, and Sex-Unknown overlaps Spay-Unknown (V = 0.55). The elastic-net penalty handles this.
- **Imbalance:** inverse-frequency class weights, computed from each training part.
- **Models compared on the shared folds** (macro-F1 is the selection metric):
  - M0: plain `nnet::multinom`.
  - M1: M0 + class weights.
  - M2: weighted `glmnet` elastic net, α ∈ {0, .25, .5, .75, 1}, λ by the 1-SE rule.
  - M3: M2 + the age features.
- **Interpretation:** odds ratios vs Adoption come from an unpenalised, unweighted multinomial fit with base features and age in years. Drop-one likelihood-ratio tests and VIF/Cramér checks support the modelling section (univariate EDA association plots were removed in the group integration branch).

## Results

| Model | CV macro-F1 (mean ± sd) | CV balanced acc. | CV accuracy |
|---|---|---|---|
| **M3 glmnet + weights + age features** | **0.441 ± 0.012** | **0.522** | 0.624 |
| M2 glmnet + weights | 0.437 ± 0.014 | 0.496 | 0.687 |
| M1 multinom + weights | 0.428 ± 0.010 | 0.487 | 0.658 |
| M0 multinom | 0.368 ± 0.007 | 0.386 | 0.792 |
| Always "Adoption" | 0.138 | 0.200 | 0.524 |

The chosen model is M3 (α = 0.5, λ ≈ 0.026). I refit it on the full training set and tested it once on the held-out 20%:

- **Test:** macro-F1 **0.441**, balanced accuracy **0.523**, accuracy 0.622.
- **Test recall:** Adoption 0.76, Transfer 0.46, Return 0.61, Euthanasia 0.24, Other 0.55.
- Most errors are Transfers predicted as Other/Euthanasia and Adoptions predicted as Return (see the confusion matrix).

The plain unweighted LR has the highest accuracy only because it mostly predicts Adoption/Transfer. Its Euthanasia and Other recall is close to 0.

**Main findings**

- Older age, no recorded name and unknown sex all go with non-adoption outcomes. For example, each year of age has OR 1.46 for Euthanasia vs Adoption.
- Colour and pattern add little.
- `Spayed.Neutered` dominates the model, with ORs in the hundreds. Without it, CV macro-F1 falls to 0.369, and dropping `has_Name` as well gives 0.362. The field probably reflects status at outcome, so it is a leakage risk we need to discuss as a group.
- On a temporal hold-out (train on outcomes before 2026-07-01, test on later ones), macro-F1 is 0.415, a small drop.

## Files

- `logistic_regression.Rmd` / `logistic_regression.html`: full analysis.
- `results/metrics_summary.csv`: CV vs test for the chosen model.
- `results/test_per_class.csv`: test precision/recall/F1 per class.
- `results/cv_model_comparison.csv`, `results/cv_fold_metrics.csv`, `results/glmnet_tuning_grid.csv`: CV comparison, per-fold scores and tuning grid.
- `results/confusion_matrix_test.csv` / `.png`: test confusion matrix.
- `results/odds_ratios_vs_adoption.csv` / `.png`, `results/final_model_coefficients.csv`: odds ratios and final coefficients.
- `results/drop1_likelihood_ratio.csv`, `results/vif_base_design.csv`: model diagnostics.
- `results/sensitivity_checks.csv`: no Spay/Name, and temporal hold-out.
- `results/cv_oof_predictions.csv`, `results/test_predictions.csv`: predicted classes and probabilities, for comparing models across the group.

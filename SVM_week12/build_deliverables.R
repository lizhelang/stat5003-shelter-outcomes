# Generate a reviewable integrated copy; do not overwrite the shared v29 source.
svm_local_libs <- c(".r-library", "C:/Users/32476/AppData/Local/R/win-library/4.6")
.libPaths(c(svm_local_libs[dir.exists(svm_local_libs)], .libPaths()))
source_file <- "STAT5003_group_project_RMarkdown_template_v29.Rmd"
lines <- readLines(source_file, warn = FALSE)
start <- grep("^```\\{r fit-svm, eval=FALSE\\}", lines)
stopifnot(length(start) == 1L)
finish <- which(seq_along(lines) > start & lines == "```")[1]
svm_code <- readLines("svm_model.R", warn = FALSE)
replacement <- c("```{r fit-svm, message=FALSE, warning=FALSE}", svm_code, "```",
  "",
  "The SVM implementation compares 18 cost/kernel/weighting configurations on the shared five folds. The baseline is unweighted C=1, gamma=1/p. Age scaling, one-hot encoding, constant-column filtering and class weights are learned from each fold's training rows. Test data are not scored here.",
  "",
  "```{r svm-cv-tables}",
  "knitr::kable(svm_results$comparison[c('Model', 'C', 'Gamma_multiplier', 'Weighting', 'Mean_Macro_F1', 'SD_Macro_F1', 'Mean_Balanced_Accuracy', 'Mean_Accuracy')], digits = 3, caption = 'SVM baseline and selected configuration: shared five-fold CV')",
  "knitr::kable(svm_results$oof$per_class, digits = 3, caption = 'Selected SVM: pooled out-of-fold class metrics')",
  "```",
  "",
  "The selected configuration achieves mean CV macro-F1 `r sprintf('%.3f', svm_results$tuning$Mean_Macro_F1[1])` (fold SD `r sprintf('%.3f', svm_results$tuning$SD_Macro_F1[1])`). Balanced accuracy is defined as macro-averaged recall. Tuning and reporting reuse the same CV folds, so this is a development estimate; reserve holdout scoring until the five-model comparison and final selection are complete.",
  "",
  "Despite approximately 80% overall accuracy, the selected configuration has very low Euthanasia recall. It should not be treated as a stand-alone risk detector. The best weighted configuration has a slightly lower mean macro-F1 but a different minority-class recall/precision tradeoff, which should be considered in the group's decision.",
  "",
  "```{r svm-oof-figure, echo=FALSE, out.width='85%'}",
  "knitr::include_graphics('svm_results/svm_confusion_matrix.png')",
  "```"
)
heading <- match("### Support Vector Machine (SVM)", lines)
svm_description <- c("",
  "1. **Purpose and implementation:** We fitted an RBF SVM with `e1071::svm()` using one-versus-one multiclass classification. It provides a non-linear alternative to the multinomial baseline and the tree models.",
  "2. **Predictors and preprocessing:** We used the eight shared predictors and the existing `cv_data` folds. Within each training fold we learned a full one-hot encoding, removed constant columns and standardised `Age_Years_imputed`; binary indicators remained 0/1. We set `scale=FALSE` in the SVM because age had already been scaled. Assessment-only categories received all-zero indicator blocks rather than causing row deletion.",
  "3. **Model improvement and imbalance:** We compared an unweighted C=1, gamma=1/p baseline against a fixed grid of cost, gamma and weighting settings. Inverse-frequency weights were calculated from each fold's training outcomes as n/(K*n_class). Neither the class frequencies nor the scaling parameters were estimated from validation or test data.",
  "4. **Evaluation:** We selected by mean fold macro-F1 and reported its fold standard deviation, macro-averaged class recall (balanced accuracy), accuracy, and per-class metrics from out-of-fold predictions. The holdout remained reserved for group-wide final model selection. Implementation details follow the [e1071 documentation](https://cran.r-project.org/web/packages/e1071/refman/e1071.html).",
  "")
combined <- c(lines[seq_len(heading)], svm_description, replacement,
               lines[(finish + 1L):length(lines)])
# Add SVM-specific improvement evidence without changing other model owners' code.
strategy <- match("### Improvement Strategy", combined)
combined <- append(combined, c("",
  "**SVM.** Compare 18 configurations: C in {0.1, 1, 10}; gamma in {0.25/p, 1/p, 4/p}; and no weighting versus training-derived inverse-frequency weighting. Select by mean macro-F1 on the shared five folds. This is a fixed grid; no test-set results inform tuning."), after = strategy)
improvement <- match("### Improvement Results", combined)
combined <- append(combined, c("",
  "**SVM.** The selected configuration changes mean CV macro-F1 by `r sprintf('%+.3f', svm_results$tuning$Mean_Macro_F1[1] - svm_results$comparison$Mean_Macro_F1[1])` relative to the unweighted C=1, gamma=1/p baseline. These are tuning-set estimates rather than independent evidence of a generalisation improvement.",
  "",
  "```{r svm-improvement-plot, echo=FALSE, out.width='90%'}",
  "knitr::include_graphics('svm_results/svm_tuning.png')",
  "```", "",
  "```{r svm-weighting-comparison}",
  "knitr::kable(subset(svm_results$weighting_tradeoff, Class %in% c('Return', 'Euthanasia', 'Other'))[, c('Variant', 'Class', 'Precision', 'Recall', 'F1')], digits=3, caption='SVM minority-class tradeoff: pooled out-of-fold predictions')",
  "```"), after = improvement)
writeLines(combined, "STAT5003_v29_with_SVM.Rmd", useBytes = TRUE)

# Render the concise, completed SVM contribution without rerunning the grid.
if (dir.exists("C:/Program Files/RStudio/resources/app/bin/quarto/bin/tools")) {
  Sys.setenv(RSTUDIO_PANDOC = "C:/Program Files/RStudio/resources/app/bin/quarto/bin/tools")
}
rmarkdown::render("SVM_results.Rmd", quiet = TRUE, envir = new.env())

# A short, result-driven presentation script for the model owner.
tuning <- read.csv("svm_results/tuning_summary.csv")
comparison <- read.csv("svm_results/baseline_vs_selected.csv")
classes <- read.csv("svm_results/oof_per_class.csv")
best <- tuning[1, ]
weak <- classes[which.min(classes$Recall), ]
strong <- classes[which.max(classes$Recall), ]
talk <- c(
  "# SVM presentation notes (about 60 seconds)", "",
  "We used an RBF support vector machine to capture non-linear relationships between the animal characteristics and five shelter outcomes. To make comparisons fair, we used the same animals, predictors and five cross-validation folds as the rest of the group.", "",
  "Within each training fold, we encoded the categorical variables and standardised age. We then compared 18 combinations of the cost parameter, kernel width and class weighting, choosing by macro-F1 so that all five outcomes contributed equally.", "",
  sprintf("The selected SVM used C = %g, gamma = %g divided by the number of encoded predictors, and %s. Its mean cross-validation macro-F1 was %.3f, compared with %.3f for the baseline.", best$C, best$Gamma_multiplier, if (best$Weighting == "none") "no class weighting" else "inverse-frequency class weighting", best$Mean_Macro_F1, comparison$Mean_Macro_F1[1]), "",
  sprintf("It identified %s most reliably, with out-of-fold recall of %.1f%%, while %s remained hardest, with recall of %.1f%%. These results show why class-level evaluation matters alongside overall accuracy.", strong$Class, 100 * strong$Recall, weak$Class, 100 * weak$Recall), "",
  "These are development results because the same folds were used for tuning. We have reserved the test set for the group's final model selection.", "",
  "## 中文理解", "",
  "讲解时展示 svm_tuning.png 或 svm_confusion_matrix.png。先讲模型为什么适合，再讲公平比较与防止泄漏的做法，最后用实际 macro-F1 和每类 recall 说明结果。不要宣称 SVM 优于其他四个模型，除非组员的统一比较结果支持。", "",
  "图上的混淆矩阵来自训练集的折外预测；不能称为 final test confusion matrix。"
)
writeLines(talk, "SVM_talk_notes.md", useBytes = TRUE)

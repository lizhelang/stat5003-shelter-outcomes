# Check the exported handoff, not just whether the script completed.
folds <- read.csv("svm_results/cv_fold_scores.csv")
tuning <- read.csv("svm_results/tuning_summary.csv")
pred <- read.csv("svm_results/selected_oof_predictions.csv")
class_metrics <- read.csv("svm_results/oof_per_class.csv")
summary <- read.csv("svm_results/oof_pooled_metrics.csv")
audit <- read.csv("svm_results/data_audit.csv")
comparison <- read.csv("svm_results/baseline_vs_selected.csv")
train_n <- audit$Count[audit$Check == "Training rows"]
stopifnot(nrow(folds) == 90L, nrow(tuning) == 18L,
          all(table(folds$Candidate) == 5L),
          nrow(pred) == train_n, identical(pred$Row, seq_len(train_n)),
          !anyNA(pred), sum(class_metrics$Support) == train_n,
          tuning$Mean_Macro_F1[1] == max(tuning$Mean_Macro_F1),
          comparison$Mean_Macro_F1[2] >= comparison$Mean_Macro_F1[1])
classes <- class_metrics$Class
cm <- table(factor(pred$Actual, levels = classes), factor(pred$Predicted, levels = classes))
independent_f1 <- mean(2 * diag(cm) / (rowSums(cm) + colSums(cm)))
independent_recall <- mean(diag(cm) / rowSums(cm))
stopifnot(abs(independent_f1 - summary$Macro_F1) < 1e-10,
          abs(independent_recall - summary$Balanced_Accuracy) < 1e-10)
for (id in tuning$Candidate) {
  stopifnot(abs(mean(folds$Macro_F1[folds$Candidate == id]) -
                  tuning$Mean_Macro_F1[tuning$Candidate == id]) < 1e-10)
}
cat("Verified: 90 fold scores, 18 candidates, one OOF prediction per training animal, independently recomputed pooled metrics, and baseline-to-selected comparison.\n")

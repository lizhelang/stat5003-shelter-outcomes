# Validate report evidence against the shared split and the saved predictions.
# Run from the repository root: Rscript report_support/verify_results.R
# Use --existing-only before the updated XGBoost run has finished.
args <- commandArgs(trailingOnly = TRUE)
existing_only <- "--existing-only" %in% args
output_dir <- "model_comparison/review_results"
dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
read_result <- function(path) read.csv(path, stringsAsFactors = FALSE, check.names = FALSE)
write_result <- function(x, name) write.csv(x, file.path(output_dir, name), row.names = FALSE)

# Use a private environment so source helpers cannot replace the checks below.
shared <- new.env(parent = globalenv())
invisible(capture.output(sys.source("report_support/preprocessing.R", envir = shared)))
classes <- levels(shared$y_train)
stopifnot(identical(classes, c("Adoption", "Transfer", "Return", "Euthanasia", "Other")),
          nrow(shared$data_selected) == 17597L, nrow(shared$data_latest) == 16831L,
          nrow(shared$x_train) == 13467L, nrow(shared$x_test) == 3364L,
          !anyDuplicated(shared$data_latest$Animal.ID),
          length(intersect(shared$train_raw$Animal.ID, shared$test_raw$Animal.ID)) == 0L)
fold_id <- integer(length(shared$y_train))
for (k in seq_along(shared$cv_folds)) fold_id[shared$cv_folds[[k]]] <- k
stopifnot(all(fold_id %in% 1:5),
          identical(sort(as.integer(unlist(shared$cv_folds))), seq_along(shared$y_train)))

close <- function(actual, expected, label, tolerance = 1e-9) {
  if (!isTRUE(all.equal(as.numeric(actual), as.numeric(expected), tolerance = tolerance,
                        check.attributes = FALSE))) stop("Metric mismatch: ", label)
}
per_class <- function(actual, predicted) {
  actual <- factor(actual, levels = classes)
  predicted <- factor(predicted, levels = classes)
  stopifnot(length(actual) == length(predicted), !anyNA(actual), !anyNA(predicted))
  cm <- table(actual, predicted)
  tp <- diag(cm); support <- rowSums(cm); n_predicted <- colSums(cm)
  data.frame(Class = classes, Support = as.integer(support),
             Precision = ifelse(n_predicted > 0, tp / n_predicted, 0),
             Recall = ifelse(support > 0, tp / support, 0),
             F1 = ifelse(support + n_predicted > 0, 2 * tp / (support + n_predicted), 0),
             row.names = NULL)
}
metrics <- function(actual, predicted) {
  pc <- per_class(actual, predicted)
  c(Macro_F1 = mean(pc$F1), Balanced_Accuracy = mean(pc$Recall),
    Accuracy = mean(actual == predicted), Weighted_F1 = weighted.mean(pc$F1, pc$Support))
}
check_pc <- function(computed, stored, label) {
  stored <- stored[match(classes, stored$Class), ]
  stopifnot(identical(computed$Class, stored$Class))
  for (column in c("Support", "Precision", "Recall", "F1"))
    close(computed[[column]], stored[[column]], paste(label, column))
}
fold_metrics <- function(actual, predicted, folds) {
  do.call(rbind, lapply(1:5, function(k) {
    rows <- folds == k
    cbind(data.frame(Fold = k), as.data.frame(as.list(metrics(actual[rows], predicted[rows]))))
  }))
}
summary_row <- function(model, folds) {
  data.frame(Model = model, Mean_CV_Macro_F1 = mean(folds$Macro_F1),
             SD_CV_Macro_F1 = sd(folds$Macro_F1),
             Mean_CV_Balanced_Accuracy = mean(folds$Balanced_Accuracy),
             Mean_CV_Accuracy = mean(folds$Accuracy), stringsAsFactors = FALSE)
}
check_summary <- function(computed, stored, label) {
  for (column in c("Mean_CV_Macro_F1", "SD_CV_Macro_F1",
                    "Mean_CV_Balanced_Accuracy", "Mean_CV_Accuracy"))
    close(computed[[column]], stored[[column]], paste(label, column))
}

# Shared IDs, labels and fold membership must agree, not just sample counts.
manifest <- read_result("SVM_week12/svm_results/split_manifest.csv")
stopifnot(identical(as.character(manifest$Animal_ID[manifest$Partition == "train"]),
                    as.character(shared$train_raw$Animal.ID)),
          identical(as.character(manifest$Animal_ID[manifest$Partition == "test"]),
                    as.character(shared$test_raw$Animal.ID)))
lr <- read_result("zilan/results/cv_oof_predictions.csv")
svm <- read_result("SVM_week12/svm_results/selected_oof_predictions.csv")
lr <- lr[order(lr$train_row), ]; svm <- svm[order(svm$Row), ]
stopifnot(identical(lr$train_row, seq_along(shared$y_train)),
          identical(svm$Row, seq_along(shared$y_train)),
          identical(as.character(lr$Animal.ID), as.character(shared$train_raw$Animal.ID)),
          identical(lr$truth, as.character(shared$y_train)),
          identical(svm$Actual, as.character(shared$y_train)),
          identical(lr$Fold, fold_id), identical(svm$Fold, fold_id))

lr_pc <- per_class(lr$truth, lr$pred)
write_result(lr_pc, "lr_oof_per_class.csv")
lr_folds <- fold_metrics(lr$truth, lr$pred, lr$Fold)
lr_stored <- read_result("zilan/results/cv_fold_metrics.csv")
lr_stored <- lr_stored[grepl("^M3 ", lr_stored$Model), ]
lr_stored <- lr_stored[order(lr_stored$Fold), ]
close(lr_folds$Macro_F1, lr_stored$macro_F1, "LR fold macro-F1")
close(lr_folds$Balanced_Accuracy, lr_stored$balanced_accuracy, "LR fold balanced accuracy")
close(lr_folds$Accuracy, lr_stored$accuracy, "LR fold accuracy")
lr_summary <- summary_row("Multinomial logistic regression", lr_folds)
lr_cv <- read_result("zilan/results/cv_model_comparison.csv")
lr_cv <- lr_cv[grepl("^M3 ", lr_cv$Model), ]
close(lr_summary$Mean_CV_Macro_F1, lr_cv$macro_F1, "LR summary macro-F1")
close(lr_summary$SD_CV_Macro_F1, lr_cv$macro_F1_sd, "LR summary SD")
close(lr_summary$Mean_CV_Balanced_Accuracy, lr_cv$balanced_accuracy, "LR summary balanced accuracy")
close(lr_summary$Mean_CV_Accuracy, lr_cv$accuracy, "LR summary accuracy")

lr_test <- read_result("zilan/results/test_predictions.csv")
stopifnot(identical(as.character(lr_test$Animal.ID), as.character(shared$test_raw$Animal.ID)),
          identical(lr_test$truth, as.character(shared$y_test)))
lr_test_metrics <- metrics(lr_test$truth, lr_test$pred)
lr_test_stored <- read_result("zilan/results/metrics_summary.csv")
lr_test_stored <- lr_test_stored[grepl("Held-out", lr_test_stored$Evaluation), ]
close(lr_test_metrics[c("Macro_F1", "Balanced_Accuracy", "Accuracy")],
      unlist(lr_test_stored[c("macro_F1", "balanced_accuracy", "accuracy")]), "LR holdout")

svm_pc <- per_class(svm$Actual, svm$Predicted)
check_pc(svm_pc, read_result("SVM_week12/svm_results/oof_per_class.csv"), "SVM pooled")
svm_folds <- fold_metrics(svm$Actual, svm$Predicted, svm$Fold)
svm_stored <- read_result("SVM_week12/svm_results/cv_fold_scores.csv")
svm_stored <- svm_stored[svm_stored$C == 10 & svm_stored$Gamma_multiplier == 4 &
                         svm_stored$Weighting == "none", ]
svm_stored <- svm_stored[order(svm_stored$Fold), ]
for (column in c("Macro_F1", "Balanced_Accuracy", "Accuracy"))
  close(svm_folds[[column]], svm_stored[[column]], paste("SVM fold", column))
svm_summary <- summary_row("RBF SVM", svm_folds)

rf_folds <- read_result("model_comparison/results/rf_cv_fold_scores.csv")
rf_folds <- rf_folds[rf_folds$num.trees == 500 & rf_folds$mtry == 4, ]
rf_summary <- summary_row("Random forest", rf_folds)
rf_stored <- read_result("model_comparison/results/rf_cv_summary.csv")
rf_stored <- rf_stored[rf_stored$num.trees == 500 & rf_stored$mtry == 4, ]
close(rf_summary$Mean_CV_Macro_F1, rf_stored$Mean_Macro_F1, "RF summary macro-F1")
close(rf_summary$SD_CV_Macro_F1, rf_stored$SD_Macro_F1, "RF summary SD")
close(rf_summary$Mean_CV_Balanced_Accuracy, rf_stored$Mean_Balanced_Accuracy, "RF balanced accuracy")
close(rf_summary$Mean_CV_Accuracy, rf_stored$Mean_Accuracy, "RF accuracy")
rf_pc <- read_result("model_comparison/results/rf_oof_per_class.csv")
close(rf_pc$Support, as.integer(table(shared$y_train)), "RF supports")
rf_selected <- read_result("model_comparison/results/rf_selected_metrics.csv")
close(mean(rf_pc$F1), rf_selected$Macro_F1_pooled_oof, "RF pooled macro-F1")
close(mean(rf_pc$Recall), rf_selected$Balanced_Accuracy_pooled_oof, "RF pooled balanced accuracy")
close(sum(rf_pc$Recall * rf_pc$Support) / sum(rf_pc$Support),
      rf_selected$Accuracy_pooled_oof, "RF pooled accuracy")
existing_summary <- rbind(rf_summary, svm_summary, lr_summary)
write_result(existing_summary, "existing_model_summary.csv")
message("Existing models: IDs, folds, predictions and stored metric summaries agree.")

if (!existing_only) {
  xgb <- read_result(file.path(output_dir, "xgb_selected_oof_predictions.csv"))
  xgb <- xgb[order(xgb$Training_Row), ]
  stopifnot(identical(xgb$Training_Row, seq_along(shared$y_train)),
            identical(xgb$Actual, as.character(shared$y_train)))
  xgb_pc <- per_class(xgb$Actual, xgb$Predicted)
  check_pc(xgb_pc, read_result(file.path(output_dir, "xgb_oof_per_class.csv")), "XGBoost pooled")
  xgb_folds <- fold_metrics(xgb$Actual, xgb$Predicted, fold_id)
  xgb_stored <- read_result(file.path(output_dir, "xgb_selected_oof_fold_scores.csv"))
  xgb_stored <- xgb_stored[order(xgb_stored$Fold), ]
  stopifnot(all(xgb_stored$nrounds == 150L), identical(xgb_stored$Fold, 1:5))
  for (column in c("Macro_F1", "Balanced_Accuracy", "Accuracy", "Weighted_F1"))
    close(xgb_folds[[column]], xgb_stored[[column]], paste("XGBoost fold", column))
  xgb_selected <- read_result(file.path(output_dir, "xgb_selected_metrics.csv"))
  xgb_summary <- summary_row("XGBoost", xgb_folds)
  check_summary(xgb_summary, xgb_selected, "XGBoost summary")
  for (column in c("Macro_F1", "Balanced_Accuracy", "Accuracy", "Weighted_F1"))
    close(metrics(xgb$Actual, xgb$Predicted)[column], xgb_selected[[column]], paste("XGBoost pooled", column))
  grid <- read_result(file.path(output_dir, "xgb_grid_summary.csv"))
  close(xgb_selected$Mean_CV_Macro_F1, max(grid$Mean_CV_Macro_F1), "XGBoost selected grid maximum")
  xt <- read_result(file.path(output_dir, "xgb_holdout_predictions.csv"))
  xt <- xt[order(xt$Test_Row), ]
  stopifnot(identical(xt$Test_Row, seq_along(shared$y_test)),
            identical(xt$Actual, as.character(shared$y_test)))
  check_pc(per_class(xt$Actual, xt$Predicted),
           read_result(file.path(output_dir, "xgb_holdout_per_class.csv")), "XGBoost holdout")
  xt_stored <- read_result(file.path(output_dir, "xgb_holdout_metrics.csv"))
  for (column in c("Macro_F1", "Balanced_Accuracy", "Accuracy", "Weighted_F1"))
    close(metrics(xt$Actual, xt$Predicted)[column], xt_stored[[column]], paste("XGBoost holdout", column))
  comparison <- rbind(xgb_summary, existing_summary)
  comparison <- comparison[order(-comparison$Mean_CV_Macro_F1), ]
  write_result(comparison, "verified_model_comparison.csv")
  message("Updated XGBoost: selected grid, row-level predictions and all metrics agree.")
}
message("Verification passed.")

# Load evidence for the report; no model is selected using holdout performance.
read_result <- function(name, folder = "model_comparison/review_results") {
  read.csv(file.path(folder, name), stringsAsFactors = FALSE, check.names = FALSE)
}
lr_cv <- read_result("cv_model_comparison.csv", "zilan/results")
rf_cv <- read_result("rf_cv_summary.csv", "model_comparison/results")
svm_cv <- read_result("baseline_vs_selected.csv", "SVM_week12/svm_results")
xgb_cv <- read_result("xgb_configuration_summary.csv")
xgb_selected <- read_result("xgb_selected_metrics.csv")
xgb_holdout <- read_result("xgb_holdout_metrics.csv")
xgb_test_pc <- read_result("xgb_holdout_per_class.csv")
xgb_importance <- read_result("xgb_feature_importance.csv")
majority_cv <- read_result("majority_cv_summary.csv")
majority_holdout <- read_result("majority_holdout_metrics.csv")
majority_training <- read_result("majority_training_metrics.csv")
lr_selected <- lr_cv[grepl("^M3 ", lr_cv$Model), ]
lr_base <- lr_cv[grepl("^M0 ", lr_cv$Model), ]
rf_selected <- rf_cv[rf_cv$num.trees == 500 & rf_cv$mtry == 4, ]
rf_base <- rf_cv[rf_cv$num.trees == 500 & rf_cv$mtry == 2, ]
svm_selected <- svm_cv[svm_cv$Model == "SVM selected by CV", ]
svm_base <- svm_cv[svm_cv$Model == "SVM baseline", ]
comparison <- data.frame(
  Model = c("XGBoost", "Random forest", "RBF SVM", "Multinomial logistic (M3)", "Majority class (baseline)"),
  Macro_F1 = c(xgb_selected$Mean_CV_Macro_F1, rf_selected$Mean_Macro_F1,
               svm_selected$Mean_Macro_F1, lr_selected$macro_F1, majority_cv$Mean_CV_Macro_F1),
  SD = c(xgb_selected$SD_CV_Macro_F1, rf_selected$SD_Macro_F1,
         svm_selected$SD_Macro_F1, lr_selected$macro_F1_sd, majority_cv$SD_CV_Macro_F1),
  Balanced_Accuracy = c(xgb_selected$Mean_CV_Balanced_Accuracy,
    rf_selected$Mean_Balanced_Accuracy, svm_selected$Mean_Balanced_Accuracy,
    lr_selected$balanced_accuracy, majority_cv$Mean_CV_Balanced_Accuracy),
  Accuracy = c(xgb_selected$Mean_CV_Accuracy, rf_selected$Mean_Accuracy,
    svm_selected$Mean_Accuracy, lr_selected$accuracy, majority_cv$Mean_CV_Accuracy)
)
stopifnot(comparison$Model[which.max(comparison$Macro_F1)] == "XGBoost")
lr_oof <- read_result("cv_oof_predictions.csv", "zilan/results")
classes <- levels(y_train)
pc_metrics <- function(actual, pred) {
  cm <- table(factor(actual, levels = classes), factor(pred, levels = classes))
  support <- rowSums(cm); predicted <- colSums(cm); tp <- diag(cm)
  data.frame(Class = classes, Support = as.integer(support),
             Precision = ifelse(predicted > 0, tp / predicted, 0),
             Recall = tp / support, F1 = 2 * tp / (support + predicted))
}
pc_sources <- list(
  XGBoost = read_result("xgb_oof_per_class.csv"),
  `Random forest` = read_result("rf_oof_per_class.csv", "model_comparison/results"),
  `RBF SVM` = read_result("oof_per_class.csv", "SVM_week12/svm_results"),
  `Logistic M3` = pc_metrics(lr_oof$truth, lr_oof$pred)
)
recall_long <- bind_rows(lapply(names(pc_sources), function(model) {
  transform(pc_sources[[model]], Model = model)
}))
recall_long$Class <- factor(recall_long$Class, levels = classes)
recall_long$Model <- factor(recall_long$Model, levels = names(pc_sources))
fmt <- function(x, digits = 3) sprintf(paste0("%.", digits, "f"), x)
pct <- function(x, digits = 1) paste0(fmt(100 * x, digits), "%")
comma <- function(x) format(x, big.mark = ",", scientific = FALSE, trim = TRUE)
quality_value <- function(field) quality_summary$Missing_pct[quality_summary$Feature == field]
age_by_outcome <- data.frame(Outcome = data_selected$Outcome.Group, Age = age_audit$Age_Years_raw) %>%
  filter(is.finite(Age), Age >= 0) %>% group_by(Outcome) %>%
  summarise(Median = median(Age), .groups = "drop")
lr_sensitivity <- read_result("sensitivity_checks.csv", "zilan/results")
write.csv(comparison, "model_comparison/review_results/report_cv_comparison.csv", row.names = FALSE)
write.csv(recall_long, "model_comparison/review_results/report_pooled_per_class.csv", row.names = FALSE)

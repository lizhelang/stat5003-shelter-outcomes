# Final XGBoost: refit once on full training set, evaluate once on holdout.
# Hyper-parameters and nrounds come from the unified CV OOF protocol
# (model_comparison/results/xgb_selected_metrics.csv); the holdout is never
# used for early stopping or tuning.
.libPaths(c(path.expand("~/R/library"), .libPaths()))
suppressPackageStartupMessages({
  library(dplyr)
  library(tidyr)
  library(stringr)
  library(forcats)
  library(caret)
  library(xgboost)
})

# Rebuild shared v29 objects (x_train/y_train/x_test/y_test) from run_xgb_cv.R.
src <- readLines("model_comparison/run_xgb_cv.R", warn = FALSE)
stop_at <- grep("^# ---- XGBoost CV", src)[1]
if (is.na(stop_at) || stop_at < 2) stop("Could not locate XGBoost CV section in run_xgb_cv.R")
eval(parse(text = src[seq_len(stop_at - 1L)]), envir = environment())

selected <- read.csv("model_comparison/results/xgb_selected_metrics.csv", stringsAsFactors = FALSE)
oof_folds <- read.csv("model_comparison/results/xgb_selected_oof_fold_scores.csv", stringsAsFactors = FALSE)
stopifnot(nrow(selected) == 1L, nrow(oof_folds) == 5L)

params <- list(
  max_depth = as.integer(selected$max_depth[1]),
  eta = as.numeric(selected$eta[1]),
  subsample = as.numeric(selected$subsample[1]),
  colsample_bytree = as.numeric(selected$colsample_bytree[1]),
  min_child_weight = as.numeric(selected$min_child_weight[1])
)
# Freeze boosting rounds at the mean early-stopped iteration from the same OOF
# pass used for ranking (do NOT early-stop on x_test).
nrounds_final <- as.integer(round(mean(oof_folds$best_nrounds)))
stopifnot(is.finite(nrounds_final), nrounds_final >= 1L)

outcome_levels <- levels(y_train)
n_classes <- length(outcome_levels)
stopifnot(n_classes == 5L, identical(levels(y_test), outcome_levels))

dmy <- dummyVars(~ ., data = x_train, fullRank = FALSE)
m_train <- as.matrix(predict(dmy, newdata = x_train))
m_test <- as.matrix(predict(dmy, newdata = x_test))
storage.mode(m_train) <- "double"
storage.mode(m_test) <- "double"

class_counts <- table(y_train)
weights_per_class <- nrow(x_train) / (length(class_counts) * as.numeric(class_counts))
names(weights_per_class) <- names(class_counts)
sample_weights <- as.numeric(weights_per_class[as.character(y_train)])

dtrain <- xgb.DMatrix(
  data = m_train,
  label = as.integer(y_train) - 1L,
  weight = sample_weights
)
dtest <- xgb.DMatrix(data = m_test, label = as.integer(y_test) - 1L)

bst <- xgb.train(
  params = c(
    list(
      booster = "gbtree",
      objective = "multi:softprob",
      num_class = n_classes,
      eval_metric = "mlogloss"
    ),
    params
  ),
  data = dtrain,
  nrounds = nrounds_final,
  verbose = 0
)

probs <- predict(bst, dtest)
if (is.null(dim(probs))) {
  probs <- matrix(probs, ncol = n_classes, byrow = FALSE)
}
pred <- factor(outcome_levels[max.col(probs)], levels = outcome_levels)
actual <- y_test

per_class <- bind_rows(lapply(outcome_levels, function(cl) {
  tp <- sum(actual == cl & pred == cl)
  fp <- sum(actual != cl & pred == cl)
  fn <- sum(actual == cl & pred != cl)
  support <- sum(actual == cl)
  prec <- ifelse(tp + fp == 0, 0, tp / (tp + fp))
  rec <- ifelse(tp + fn == 0, 0, tp / (tp + fn))
  f1 <- ifelse(prec + rec == 0, 0, 2 * prec * rec / (prec + rec))
  data.frame(
    Class = cl, Support = support, Precision = prec, Recall = rec, F1 = f1,
    stringsAsFactors = FALSE
  )
}))

summary_row <- data.frame(
  Model = "XGBoost (weighted + tuned)",
  Evaluation = "Held-out test (20%)",
  Macro_F1 = mean(per_class$F1),
  Balanced_Accuracy = mean(per_class$Recall),
  Accuracy = mean(pred == actual),
  nrounds = nrounds_final,
  max_depth = params$max_depth,
  eta = params$eta,
  subsample = params$subsample,
  colsample_bytree = params$colsample_bytree,
  min_child_weight = params$min_child_weight,
  Protocol = paste0(
    "full-train refit; nrounds frozen at mean OOF best_iteration=",
    nrounds_final,
    "; same hyper-params as unified CV; holdout unused for tuning/early-stop"
  ),
  stringsAsFactors = FALSE
)

dir.create("model_comparison/results", showWarnings = FALSE, recursive = TRUE)
write.csv(summary_row, "model_comparison/results/xgb_holdout_metrics.csv", row.names = FALSE)
write.csv(per_class, "model_comparison/results/xgb_holdout_per_class.csv", row.names = FALSE)
write.csv(
  data.frame(Actual = as.character(actual), Predicted = as.character(pred)),
  "model_comparison/results/xgb_holdout_predictions.csv",
  row.names = FALSE
)

writeLines(
  c(
    "XGBoost comparison + final holdout protocol",
    "1) Tuning / ranking: max 250 rounds, evals=validation fold, early_stopping_rounds=20;",
    "   best_iteration from attr(bst, 'early_stop')$best_iteration (xgboost 3.x).",
    "   Ranking macro-F1 and per-class recall share one OOF pass of the selected config.",
    "2) Final model: refit once on full x_train/y_train with the selected hyper-parameters",
    paste0("   and nrounds = round(mean OOF best_nrounds) = ", nrounds_final, "."),
    "   Holdout x_test/y_test is scored once and never used for early stopping or tuning.",
    "Decision Tree remains unscored; that does not block this four-model final evaluation."
  ),
  "model_comparison/results/xgb_protocol.txt"
)

print(summary_row)
print(per_class)
cat(sprintf(
  "Holdout done: macro-F1=%.4f bal_acc=%.4f acc=%.4f nrounds=%d\n",
  summary_row$Macro_F1, summary_row$Balanced_Accuracy, summary_row$Accuracy, nrounds_final
))

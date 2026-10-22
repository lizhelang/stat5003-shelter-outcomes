# Regenerate the fixed-150-round XGBoost analysis from the latest model revision.
# Run from the repository root: Rscript model_comparison/run_xgb_review.R
# All output is written to review_results; existing submitted results are preserved.
suppressPackageStartupMessages({
  library(dplyr)
  library(caret)
  library(xgboost)
})

source_lines <- readLines("model_comparison/run_xgb_cv.R", warn = FALSE)
model_start <- grep("^# ---- XGBoost CV", source_lines)[1L]
stopifnot(!is.na(model_start), model_start > 1L)
# The shared preprocessing defines the original split and fold-specific transforms.
eval(parse(text = source_lines[seq_len(model_start - 1L)]), envir = environment())

output_dir <- "model_comparison/review_results"
dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
write_result <- function(x, name) {
  write.csv(x, file.path(output_dir, name), row.names = FALSE, na = "")
}

# Assert that all retained published models use exactly these animals and folds.
svm_manifest <- read.csv("SVM_week12/svm_results/split_manifest.csv", stringsAsFactors = FALSE)
svm_train_ids <- svm_manifest$Animal_ID[svm_manifest$Partition == "train"]
svm_test_ids <- svm_manifest$Animal_ID[svm_manifest$Partition == "test"]
stopifnot(identical(as.character(train_raw$Animal.ID), as.character(svm_train_ids)),
          identical(as.character(test_raw$Animal.ID), as.character(svm_test_ids)))
svm_oof <- read.csv("SVM_week12/svm_results/selected_oof_predictions.csv", stringsAsFactors = FALSE)
svm_oof <- svm_oof[order(svm_oof$Row), ]
fold_id <- integer(length(y_train))
for (k in seq_along(cv_folds)) fold_id[cv_folds[[k]]] <- k
stopifnot(identical(svm_oof$Row, seq_along(y_train)),
          identical(svm_oof$Fold, fold_id),
          identical(svm_oof$Actual, as.character(y_train)))
write_result(data.frame(Animal_ID = c(train_raw$Animal.ID, test_raw$Animal.ID),
                         Partition = c(rep("train", nrow(train_raw)), rep("test", nrow(test_raw))),
                         Row_in_partition = c(seq_len(nrow(train_raw)), seq_len(nrow(test_raw)))),
             "split_manifest.csv")
write_result(data.frame(Training_Row = seq_along(y_train), Fold = fold_id,
                         Actual = as.character(y_train)), "fold_manifest.csv")

outcome_levels <- levels(y_train)
n_classes <- length(outcome_levels)
xgb_seed <- 5003L
xgb_nrounds <- 150L
stopifnot(n_classes == 5L, identical(levels(y_test), outcome_levels), length(cv_data) == 5L)

class_metrics <- function(actual, predicted) {
  actual <- factor(actual, levels = outcome_levels)
  predicted <- factor(predicted, levels = outcome_levels)
  stopifnot(length(actual) == length(predicted), !anyNA(actual), !anyNA(predicted))
  do.call(rbind, lapply(outcome_levels, function(cl) {
    tp <- sum(actual == cl & predicted == cl)
    fp <- sum(actual != cl & predicted == cl)
    fn <- sum(actual == cl & predicted != cl)
    precision <- if (tp + fp > 0) tp / (tp + fp) else 0
    recall <- if (tp + fn > 0) tp / (tp + fn) else 0
    f1 <- if (precision + recall > 0) 2 * precision * recall / (precision + recall) else 0
    data.frame(Class = cl, Support = sum(actual == cl), Precision = precision,
               Recall = recall, F1 = f1, stringsAsFactors = FALSE)
  }))
}
score_predictions <- function(actual, predicted) {
  pc <- class_metrics(actual, predicted)
  data.frame(Macro_F1 = mean(pc$F1), Balanced_Accuracy = mean(pc$Recall),
             Accuracy = mean(as.character(actual) == as.character(predicted)),
             Weighted_F1 = weighted.mean(pc$F1, pc$Support))
}
confusion_table <- function(actual, predicted) {
  tab <- table(Actual = factor(actual, levels = outcome_levels),
               Predicted = factor(predicted, levels = outcome_levels))
  data.frame(Actual = rownames(tab), as.data.frame.matrix(tab), row.names = NULL,
             check.names = FALSE)
}

encode_fold <- function(train, valid) {
  encoder <- caret::dummyVars(~ ., data = train, fullRank = FALSE)
  train_matrix <- as.matrix(predict(encoder, newdata = train))
  valid_matrix <- as.matrix(predict(encoder, newdata = valid))
  storage.mode(train_matrix) <- storage.mode(valid_matrix) <- "double"
  stopifnot(identical(colnames(train_matrix), colnames(valid_matrix)),
            !anyNA(train_matrix), !anyNA(valid_matrix))
  list(train = train_matrix, valid = valid_matrix)
}

make_matrices <- function(train_x, train_y, valid_x, valid_y) {
  encoded <- encode_fold(train_x, valid_x)
  counts <- table(train_y)
  class_weights <- length(train_y) / (n_classes * counts)
  weights <- as.numeric(class_weights[as.character(train_y)])
  list(
    unweighted = xgb.DMatrix(encoded$train, label = as.integer(train_y) - 1L),
    weighted = xgb.DMatrix(encoded$train, label = as.integer(train_y) - 1L, weight = weights),
    valid = xgb.DMatrix(encoded$valid, label = as.integer(valid_y) - 1L),
    train_y = train_y, valid_y = valid_y, feature_names = colnames(encoded$train)
  )
}
cv_matrices <- lapply(cv_data, function(d) make_matrices(d$x_train, d$y_train, d$x_valid, d$y_valid))

# In R xgboost 1.x, reshape=TRUE requests an observation-by-class matrix.
# Recent versions return this matrix directly for multiclass predictions.
predict_classes <- function(model, dmat, expected_n) {
  p <- if (utils::packageVersion("xgboost") < "3.0.0") {
    predict(model, dmat, reshape = TRUE)
  } else {
    predict(model, dmat)
  }
  if (is.null(dim(p))) p <- matrix(p, ncol = n_classes, byrow = TRUE)
  if (nrow(p) == n_classes && ncol(p) == expected_n && expected_n != n_classes) p <- t(p)
  stopifnot(identical(dim(p), c(as.integer(expected_n), as.integer(n_classes))),
            all(is.finite(p)), all(abs(rowSums(p) - 1) < 1e-5))
  factor(outcome_levels[max.col(p, ties.method = "first")], levels = outcome_levels)
}
base_params <- list(booster = "gbtree", objective = "multi:softprob", num_class = n_classes,
                    eval_metric = "mlogloss", seed = xgb_seed, nthread = 2L)

fit_config <- function(params, weighted, configuration, grid_id = NA_integer_) {
  rows <- vector("list", length(cv_data))
  oof_predictions <- rep(NA_character_, length(y_train))
  for (k in seq_along(cv_data)) {
    m <- cv_matrices[[k]]
    fit <- xgb.train(params = c(base_params, params),
                     data = if (weighted) m$weighted else m$unweighted,
                     nrounds = xgb_nrounds, verbose = 0)
    pred <- predict_classes(fit, m$valid, length(m$valid_y))
    oof_predictions[cv_folds[[k]]] <- as.character(pred)
    rows[[k]] <- cbind(data.frame(Configuration = configuration, Grid_ID = grid_id,
                                  Fold = k, nrounds = xgb_nrounds),
                       score_predictions(m$valid_y, pred))
  }
  stopifnot(!anyNA(oof_predictions))
  list(folds = do.call(rbind, rows), predictions = factor(oof_predictions, levels = outcome_levels))
}
summarise_folds <- function(folds) {
  data.frame(Mean_CV_Macro_F1 = mean(folds$Macro_F1), SD_CV_Macro_F1 = sd(folds$Macro_F1),
             Mean_CV_Balanced_Accuracy = mean(folds$Balanced_Accuracy),
             Mean_CV_Accuracy = mean(folds$Accuracy), Mean_CV_Weighted_F1 = mean(folds$Weighted_F1))
}

# A isolates ordinary XGBoost performance; A->B isolates the effect of weighting.
default_params <- list(max_depth = 6L, eta = 0.3)
A <- fit_config(default_params, FALSE, "A. Defaults, unweighted")
message("Completed A: unweighted defaults")
B <- fit_config(default_params, TRUE, "B. Defaults, balanced weights")
message("Completed B: weighted defaults")

tuning_grid <- expand.grid(max_depth = c(4L, 6L), eta = c(0.05, 0.10), subsample = 0.80,
                           colsample_bytree = c(0.70, 0.85), min_child_weight = c(1, 3),
                           KEEP.OUT.ATTRS = FALSE, stringsAsFactors = FALSE)
grid_fits <- vector("list", nrow(tuning_grid))
grid_summaries <- vector("list", nrow(tuning_grid))
for (i in seq_len(nrow(tuning_grid))) {
  grid_fits[[i]] <- fit_config(as.list(tuning_grid[i, ]), TRUE,
                              "C. Tuned, balanced weights", i)
  grid_summaries[[i]] <- cbind(data.frame(Grid_ID = i), tuning_grid[i, ],
                              summarise_folds(grid_fits[[i]]$folds))
  message(sprintf("Completed configuration %d/%d", i, nrow(tuning_grid)))
}
grid_summary <- do.call(rbind, grid_summaries)
# The first configuration is retained if mean macro-F1 ties, matching the source analysis.
best_index <- which.max(grid_summary$Mean_CV_Macro_F1)
best_params <- as.list(tuning_grid[best_index, ])
C <- grid_fits[[best_index]]
configuration_summary <- do.call(rbind, lapply(list(A, B, C), function(x) {
  cbind(data.frame(Configuration = x$folds$Configuration[1L]), summarise_folds(x$folds))
}))
write_result(configuration_summary, "xgb_configuration_summary.csv")
write_result(rbind(A$folds, B$folds, C$folds), "xgb_configuration_fold_scores.csv")
write_result(do.call(rbind, lapply(grid_fits, `[[`, "folds")), "xgb_grid_fold_scores.csv")
write_result(grid_summary, "xgb_grid_summary.csv")
write_result(C$folds, "xgb_selected_oof_fold_scores.csv")
write_result(data.frame(Training_Row = seq_along(y_train), Actual = as.character(y_train),
                         Predicted = as.character(C$predictions)), "xgb_selected_oof_predictions.csv")
write_result(class_metrics(y_train, C$predictions), "xgb_oof_per_class.csv")
write_result(confusion_table(y_train, C$predictions), "xgb_oof_confusion_matrix.csv")
selected <- cbind(data.frame(Model = "XGBoost", nrounds = xgb_nrounds, seed = xgb_seed),
                  tuning_grid[best_index, ], summarise_folds(C$folds),
                  score_predictions(y_train, C$predictions))
write_result(selected, "xgb_selected_metrics.csv")

# Majority baseline is selected within each training fold, then scored on its validation fold.
majority_oof <- rep(NA_character_, length(y_train))
majority_folds <- lapply(seq_along(cv_data), function(k) {
  d <- cv_data[[k]]
  majority <- names(which.max(table(d$y_train)))
  pred <- rep(majority, length(d$y_valid))
  majority_oof[cv_folds[[k]]] <<- pred
  cbind(data.frame(Fold = k, Majority_Class = majority), score_predictions(d$y_valid, pred))
})
majority_folds <- do.call(rbind, majority_folds)
write_result(majority_folds, "majority_cv_fold_scores.csv")
write_result(cbind(data.frame(Model = "Majority class"), summarise_folds(majority_folds)),
             "majority_cv_summary.csv")
write_result(class_metrics(y_train, majority_oof), "majority_oof_per_class.csv")

# Holdout is scored after hyperparameter selection. It never determines parameters/rounds.
full <- make_matrices(x_train, y_train, x_test, y_test)
final_model <- xgb.train(params = c(base_params, best_params), data = full$weighted,
                         nrounds = xgb_nrounds, verbose = 0)
holdout_pred <- predict_classes(final_model, full$valid, length(y_test))
write_result(cbind(data.frame(Model = "XGBoost", nrounds = xgb_nrounds),
                    score_predictions(y_test, holdout_pred)), "xgb_holdout_metrics.csv")
write_result(class_metrics(y_test, holdout_pred), "xgb_holdout_per_class.csv")
write_result(confusion_table(y_test, holdout_pred), "xgb_holdout_confusion_matrix.csv")
write_result(data.frame(Test_Row = seq_along(y_test), Actual = as.character(y_test),
                         Predicted = as.character(holdout_pred)), "xgb_holdout_predictions.csv")
majority <- names(which.max(table(y_train)))
write_result(cbind(data.frame(Model = "Majority class", Majority_Class = majority),
                    score_predictions(y_test, rep(majority, length(y_test)))), "majority_holdout_metrics.csv")
write_result(cbind(data.frame(Majority_Class = majority),
                    score_predictions(y_train, rep(majority, length(y_train)))), "majority_training_metrics.csv")

importance <- xgb.importance(feature_names = full$feature_names, model = final_model)
importance_by_predictor <- data.frame(
  Predictor = model_predictors,
  Gain = vapply(model_predictors, function(p) {
    sum(importance$Gain[importance$Feature == p | startsWith(importance$Feature, paste0(p, "."))])
  }, numeric(1)), stringsAsFactors = FALSE
)
importance_by_predictor <- importance_by_predictor[order(-importance_by_predictor$Gain), ]
stopifnot(abs(sum(importance_by_predictor$Gain) - 1) < 1e-5)
write_result(importance_by_predictor, "xgb_feature_importance.csv")
write_result(as.data.frame(importance), "xgb_encoded_feature_importance.csv")
write_result(data.frame(Class = outcome_levels, Training = as.integer(table(y_train)),
                         Holdout = as.integer(table(y_test))), "split_class_counts.csv")
writeLines(c(
  "XGBoost: fixed 150 boosting rounds for all A/B/C configurations and final refit.",
  "Seed 5003, nthread 2, common five stratified folds; training-only preprocessing and weights.",
  "A: defaults, unweighted; B: defaults, balanced weights; C: balanced weights plus 16-point grid.",
  "Select highest mean fold macro-F1; tie selects first grid row. No early stopping.",
  "Ranking, per-class metrics and confusion matrices reuse the selected grid's OOF predictions.",
  "The holdout does not determine parameters, rounds or model choice.",
  "This reproduces the latest branch analysis; prior project versions already inspected the holdout.",
  paste("R", getRversion(), "; xgboost", utils::packageVersion("xgboost")),
  paste("Source dataset MD5:", unname(tools::md5sum("Austin_Animal_Center_Outcomes_20260916.csv")))
), file.path(output_dir, "xgb_protocol.txt"))
capture.output(sessionInfo(), file = file.path(output_dir, "sessionInfo.txt"))
print(configuration_summary)
print(selected)
print(score_predictions(y_test, holdout_pred))
message("XGBoost review analysis complete")

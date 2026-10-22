# Display the actual model sources beside their methods, without executing fits.
# Extraction is deliberately strict: a changed source boundary stops rendering.
# Every displayed body is taken verbatim from the retained model source files.

model_code_manifest <- data.frame(
  Section = character(), Source = character(), Start_line = integer(),
  End_line = integer(), Lines = integer(), stringsAsFactors = FALSE
)
model_source_lines <- function(path) {
  if (!file.exists(path)) stop("Missing model source: ", path)
  readLines(path, warn = FALSE)
}
model_marker <- function(lines, marker, fixed = TRUE) {
  found <- if (fixed) which(lines == marker) else grep(marker, lines)
  if (length(found) != 1L) {
    stop("Expected one source boundary, found ", length(found), ": ", marker)
  }
  found
}
model_piece <- function(section, source, first, last, lines = model_source_lines(source)) {
  if (length(first) != 1L || length(last) != 1L || first < 1L ||
      last < first || last > length(lines)) stop("Invalid source range: ", section)
  model_code_manifest <<- rbind(model_code_manifest, data.frame(
    Section = section, Source = source, Start_line = as.integer(first),
    End_line = as.integer(last), Lines = as.integer(last - first + 1L),
    stringsAsFactors = FALSE
  ))
  c(paste0("# Source: ", source), lines[seq.int(first, last)])
}
model_chunk <- function(source, label) {
  lines <- model_source_lines(source)
  first <- model_marker(lines, paste0("^```\\{r ", label, "([,}])"), fixed = FALSE)
  closing <- which(seq_along(lines) > first & lines == "```")
  if (!length(closing)) stop("Missing closing fence for ", label)
  last <- closing[1L]
  list(lines = lines[seq.int(first + 1L, last - 1L)],
       source_lines = lines, first = first + 1L, last = last - 1L)
}
model_chunk_piece <- function(section, source, label) {
  ch <- model_chunk(source, label)
  model_piece(section, source, ch$first, ch$last, ch$source_lines)
}

model_code <- list()

# Logistic regression: model helpers/baseline fits precede regularised tuning.
lr_source <- "zilan/logistic_regression.Rmd"
lr_shared <- model_chunk(lr_source, "shared-prep")
lr_lib_start <- model_marker(lr_shared$lines,
  "library(dplyr); library(tidyr); library(ggplot2); library(nnet); library(glmnet)")
lr_cv <- model_chunk(lr_source, "cv-models")
lr_tuning_start <- model_marker(lr_cv$lines,
  "# glmnet: shared lambda path per alpha from the full training data, then fold scores")
model_code$lr_fit <- c(
  "# Original standalone analysis runs from the logistic-model subfolder.",
  "# The shared preprocessing objects are defined in Section 4.",
  model_piece("lr_fit", lr_source, lr_shared$first + lr_lib_start - 1L,
              lr_shared$last, lr_shared$source_lines), "",
  model_chunk_piece("lr_fit", lr_source, "design-helpers"), "",
  model_piece("lr_fit", lr_source, lr_cv$first,
              lr_cv$first + lr_tuning_start - 2L, lr_cv$source_lines)
)
model_code$lr_improvement <- c(
  model_piece("lr_improvement", lr_source, lr_cv$first + lr_tuning_start - 1L,
              lr_cv$last, lr_cv$source_lines), "",
  model_chunk_piece("lr_improvement", lr_source, "choose-final"), "",
  model_chunk_piece("lr_improvement", lr_source, "final-fit"), "",
  model_chunk_piece("lr_improvement", lr_source, "oof-predictions"), "",
  model_chunk_piece("lr_improvement", lr_source, "sensitivity")
)

# Random forest: the baseline is one candidate in the complete grid below.
rf_source <- "model_comparison/run_rf_cv.R"
rf_lines <- model_source_lines(rf_source)
rf_start <- model_marker(rf_lines, "^# ---- RF CV", fixed = FALSE)
rf_grid_start <- model_marker(rf_lines,
  "rf_grid <- expand.grid(num.trees = c(100, 300, 500), mtry = c(2, 4, 8))")
rf_fit_start <- model_marker(rf_lines, "    fold <- cv_data[[k]]")
rf_fit_end <- model_marker(rf_lines,
  "    preds <- predict(rf_model, data = fold$x_valid)$predictions")
stopifnot(rf_start < rf_grid_start, rf_grid_start < rf_fit_start, rf_fit_start < rf_fit_end)
model_code$rf_fit <- c(
  "# Original individual baseline from origin/Daun_rf at 4594150, lines 1150-1182.",
  "# This full-training fit scores the holdout; report comparisons use shared CV below.",
  model_piece("rf_original_baseline", "report_support/rf_original_baseline.R", 1L,
              length(model_source_lines("report_support/rf_original_baseline.R"))), "",
  "# Exact inner-fold fit from the grid search in Section 6.",
  "# i and k are supplied by that enclosing grid/fold loop; rf_grid is its candidate grid.",
  model_piece("rf_fit", rf_source, rf_fit_start, rf_fit_end, rf_lines)
)
model_code$rf_improvement <- c(
  "# Continues after the shared preprocessing in Section 4.",
  model_piece("rf_improvement", rf_source, rf_start, length(rf_lines), rf_lines)
)

# SVM: retain its complete driver, exports, plot helper and original invocation.
svm_source <- "SVM_week12/svm_model.R"
svm_lines <- model_source_lines(svm_source)
svm_driver <- model_marker(svm_lines,
  "svm_run_cv <- function(cv_data, cv_folds, x_train, y_train,")
model_code$svm_fit <- model_piece("svm_fit", svm_source, 1L, svm_driver - 1L, svm_lines)
model_code$svm_improvement <- c(
  "# Original standalone entry point runs from SVM_week12/ after its shared preprocessing.",
  model_piece("svm_improvement", svm_source, svm_driver, length(svm_lines), svm_lines)
)

# XGBoost: the revised script runs from the project root, with fixed 150 rounds.
xgb_source <- "model_comparison/run_xgb_review.R"
xgb_lines <- model_source_lines(xgb_source)
xgb_b <- model_marker(xgb_lines,
  'B <- fit_config(default_params, TRUE, "B. Defaults, balanced weights")')
xgb_majority <- model_marker(xgb_lines,
  "# Majority baseline is selected within each training fold, then scored on its validation fold.")
xgb_final <- model_marker(xgb_lines,
  "# Holdout is scored after hyperparameter selection. It never determines parameters/rounds.")
model_code$xgb_fit <- model_piece("xgb_fit", xgb_source, 1L, xgb_b - 1L, xgb_lines)
model_code$xgb_improvement <- model_piece("xgb_improvement", xgb_source, xgb_b,
                                         xgb_majority - 1L, xgb_lines)
model_code$xgb_final <- model_piece("xgb_final", xgb_source, xgb_final,
                                   length(xgb_lines), xgb_lines)

# Majority reference: include its exact metric helpers so the rule is inspectable.
metric_start <- model_marker(xgb_lines, "class_metrics <- function(actual, predicted) {")
metric_end <- model_marker(xgb_lines, "confusion_table <- function(actual, predicted) {") - 1L
summary_start <- model_marker(xgb_lines, "summarise_folds <- function(folds) {")
summary_end <- model_marker(xgb_lines,
  "# A isolates ordinary XGBoost performance; A->B isolates the effect of weighting.") - 1L
levels_start <- model_marker(xgb_lines, "outcome_levels <- levels(y_train)")
model_code$majority_fit <- c(
  "# The shared preprocessing supplies y_train, cv_data and cv_folds.",
  "# write_result and output_dir are defined by the complete XGBoost driver shown below.",
  model_piece("majority_fit", xgb_source, levels_start, levels_start, xgb_lines), "",
  model_piece("majority_fit", xgb_source, metric_start, metric_end, xgb_lines), "",
  model_piece("majority_fit", xgb_source, summary_start, summary_end, xgb_lines), "",
  model_piece("majority_fit", xgb_source, xgb_majority, xgb_final - 1L, xgb_lines)
)

# Parse each displayed fragment; this checks syntax without fitting any model.
for (label in names(model_code)) {
  tryCatch(parse(text = model_code[[label]]), error = function(e) {
    stop("Displayed model source does not parse (", label, "): ", conditionMessage(e))
  })
}

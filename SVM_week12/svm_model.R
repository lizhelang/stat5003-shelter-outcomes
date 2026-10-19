# STAT5003 W01G04: RBF SVM using the shared v29 data objects.
# Required inputs: cv_data, cv_folds, x_train, y_train.
# No test labels or test predictors are used by this script.
if (!requireNamespace("e1071", quietly = TRUE) || !requireNamespace("digest", quietly = TRUE)) {
  stop("Install e1071 and digest first: install.packages(c('e1071', 'digest'))")
}

svm_metrics <- function(truth, prediction, classes = levels(truth)) {
  stopifnot(length(truth) == length(prediction), length(truth) > 0L,
            !anyNA(truth), !anyNA(prediction),
            all(as.character(truth) %in% classes),
            all(as.character(prediction) %in% classes))
  cm <- table(Actual = factor(truth, levels = classes),
              Predicted = factor(prediction, levels = classes))
  tp <- diag(cm)
  support <- rowSums(cm)
  predicted_n <- colSums(cm)
  recall <- ifelse(support > 0, tp / support, 0)
  precision <- ifelse(predicted_n > 0, tp / predicted_n, 0)
  # This also handles a class that the classifier never predicts.
  f1 <- ifelse(support + predicted_n > 0, 2 * tp / (support + predicted_n), 0)
  per_class <- data.frame(Class = classes, Support = as.integer(support),
                          Precision = as.numeric(precision),
                          Recall = as.numeric(recall), F1 = as.numeric(f1))
  list(summary = data.frame(Macro_F1 = mean(f1),
                            Balanced_Accuracy = mean(recall),
                            Accuracy = sum(tp) / sum(cm)),
       per_class = per_class, confusion = cm)
}

svm_fit_encoder <- function(x) {
  x <- as.data.frame(x)
  age <- "Age_Years_imputed"
  stopifnot(age %in% names(x), !anyNA(x), all(is.finite(x[[age]])))
  categorical <- setdiff(names(x), age)
  encoder <- list(predictors = names(x), age = age, categorical = categorical,
                  levels = lapply(x[categorical], function(z) sort(unique(as.character(z)))),
                  age_mean = mean(x[[age]]), age_sd = sd(x[[age]]), keep = NULL)
  if (!is.finite(encoder$age_sd) || encoder$age_sd == 0) encoder$age_sd <- 1
  encoded <- svm_apply_encoder(encoder, x)
  # Determine constants using this training partition only.
  encoder$keep <- apply(encoded, 2, function(z) length(unique(z)) > 1L)
  stopifnot(any(encoder$keep))
  encoder
}

svm_apply_encoder <- function(encoder, x) {
  stopifnot(all(encoder$predictors %in% names(x)))
  x <- as.data.frame(x)[encoder$predictors]
  stopifnot(all(is.finite(x[[encoder$age]])))
  blocks <- lapply(encoder$categorical, function(variable) {
    value <- as.character(x[[variable]])
    lev <- encoder$levels[[variable]]
    mat <- vapply(lev, function(z) as.numeric(!is.na(value) & value == z),
                  numeric(nrow(x)))
    mat <- matrix(mat, nrow = nrow(x), ncol = length(lev))
    colnames(mat) <- paste(variable, lev, sep = "=")
    mat
  })
  encoded <- do.call(cbind, c(blocks, list(
    Age_Years_imputed = (x[[encoder$age]] - encoder$age_mean) / encoder$age_sd
  )))
  colnames(encoded)[ncol(encoded)] <- encoder$age
  storage.mode(encoded) <- "double"
  if (!is.null(encoder$keep)) encoded <- encoded[, encoder$keep, drop = FALSE]
  # Assessment-only/unseen categories (including common-preprocessing NAs)
  # have an all-zero block rather than dropping the animal's row.
  stopifnot(nrow(encoded) == nrow(x), all(is.finite(encoded)))
  encoded
}

svm_class_weights <- function(y, weighting) {
  if (weighting == "none") return(NULL)
  freq <- table(y)
  stopifnot(all(freq > 0))
  # Mean observation weight is 1, keeping the C comparison interpretable.
  setNames(length(y) / (length(freq) * as.numeric(freq)), names(freq))
}

svm_train <- function(x, y, cost, gamma_multiplier, weighting) {
  e1071::svm(x = x, y = y, type = "C-classification", kernel = "radial",
             cost = cost, gamma = gamma_multiplier / ncol(x), scale = FALSE,
             class.weights = svm_class_weights(y, weighting),
             probability = FALSE, fitted = FALSE, cachesize = 256)
}

svm_predict <- function(bundle, newdata) {
  predict(bundle$model, svm_apply_encoder(bundle$encoder, newdata))
}

svm_run_cv <- function(cv_data, cv_folds, x_train, y_train,
                       output_dir = "svm_results") {
  stopifnot(length(cv_data) == 5L, length(cv_folds) == 5L,
            nrow(x_train) == length(y_train), !anyNA(x_train), !anyNA(y_train))
  classes <- levels(y_train)
  stopifnot(length(classes) == 5L,
            identical(sort(as.integer(unlist(cv_folds))), seq_along(y_train)))
  dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
  # Baseline = C=1, gamma=1/p, no class weights. It is one grid candidate.
  grid <- expand.grid(C = c(0.1, 1, 10), Gamma_multiplier = c(0.25, 1, 4),
                       Weighting = c("none", "inverse"), stringsAsFactors = FALSE)
  grid$Candidate <- seq_len(nrow(grid))
  baseline_id <- grid$Candidate[grid$C == 1 & grid$Gamma_multiplier == 1 &
                                grid$Weighting == "none"]
  prepared <- lapply(seq_along(cv_data), function(k) {
    fold <- cv_data[[k]]
    stopifnot(identical(as.character(fold$y_valid),
                        as.character(y_train[cv_folds[[k]]])),
              nrow(fold$x_train) + nrow(fold$x_valid) == length(y_train),
              all(table(fold$y_train) > 0), all(table(fold$y_valid) > 0))
    encoder <- svm_fit_encoder(fold$x_train)
    list(x_train = svm_apply_encoder(encoder, fold$x_train),
         x_valid = svm_apply_encoder(encoder, fold$x_valid),
         y_train = fold$y_train, y_valid = fold$y_valid,
         encoder = encoder)
  })
  # Independent parameter candidates can run in local R worker processes.
  # Default is sequential, so sourcing this file also works in ordinary RStudio.
  workers <- max(1L, min(3L, as.integer(getOption("stat5003.svm.workers", 1L))))
  cache_dir <- file.path(output_dir, "candidate_cache")
  dir.create(cache_dir, showWarnings = FALSE)
  fingerprint <- digest::digest(list(cv_data, cv_folds, grid, "svm-v1"))
  run_candidate <- function(i) {
    cache_file <- file.path(cache_dir, paste0(fingerprint, "_", i, ".rds"))
    if (file.exists(cache_file)) return(readRDS(cache_file))
    candidate <- grid[i, ]
    scores <- vector("list", length(prepared))
    fold_predictions <- vector("list", length(prepared))
    for (k in seq_along(prepared)) {
      fold <- prepared[[k]]
      t0 <- proc.time()[["elapsed"]]
      model <- svm_train(fold$x_train, fold$y_train, candidate$C,
                         candidate$Gamma_multiplier, candidate$Weighting)
      pred <- predict(model, fold$x_valid)
      metric <- svm_metrics(fold$y_valid, pred, classes)$summary
      scores[[k]] <- cbind(
        candidate, Fold = k, Gamma = candidate$Gamma_multiplier / ncol(fold$x_train),
        Encoded_predictors = ncol(fold$x_train), metric,
        Support_vectors = model$tot.nSV,
        Seconds = proc.time()[["elapsed"]] - t0
      )
      fold_predictions[[k]] <- data.frame(
        Row = cv_folds[[k]], Fold = k, Actual = as.character(fold$y_valid),
        Predicted = as.character(pred), stringsAsFactors = FALSE)
      progress <- sprintf("SVM %02d/%02d fold %d/5: C=%g gamma=%g/%d %s; macro-F1=%.4f (%.1fs)",
                      i, nrow(grid), k, candidate$C, candidate$Gamma_multiplier,
                      ncol(fold$x_train), candidate$Weighting, metric$Macro_F1,
                      proc.time()[["elapsed"]] - t0)
      message(progress)
      cat(progress, "\n", file = file.path(cache_dir, paste0("progress_", i, ".txt")), append = TRUE)
    }
    result <- list(scores = do.call(rbind, scores), predictions = do.call(rbind, fold_predictions))
    saveRDS(result, cache_file)
    result
  }
  if (workers > 1L) {
    cluster <- parallel::makePSOCKcluster(workers)
    on.exit(parallel::stopCluster(cluster), add = TRUE)
    parallel::clusterCall(cluster, function(paths) .libPaths(paths), .libPaths())
    # Worker tasks fit and score only the prepared training/CV partitions.
    parallel::clusterExport(cluster, c("svm_train", "svm_class_weights", "svm_metrics"),
                             envir = environment(svm_train))
    candidate_results <- parallel::parLapplyLB(cluster, seq_len(nrow(grid)), run_candidate)
  } else {
    candidate_results <- lapply(seq_len(nrow(grid)), run_candidate)
  }
  predictions <- lapply(candidate_results, `[[`, "predictions")
  fold_scores <- do.call(rbind, lapply(candidate_results, `[[`, "scores"))
  write.csv(fold_scores, file.path(output_dir, "cv_fold_scores.csv"), row.names = FALSE)
  tuning <- do.call(rbind, lapply(seq_len(nrow(grid)), function(i) {
    z <- fold_scores[fold_scores$Candidate == i, ]
    cbind(grid[i, ], Mean_Macro_F1 = mean(z$Macro_F1), SD_Macro_F1 = sd(z$Macro_F1),
          Mean_Balanced_Accuracy = mean(z$Balanced_Accuracy),
          Mean_Accuracy = mean(z$Accuracy), Total_seconds = sum(z$Seconds))
  }))
  tuning <- tuning[order(-tuning$Mean_Macro_F1, tuning$SD_Macro_F1,
                         tuning$C, tuning$Gamma_multiplier, tuning$Weighting), ]
  rownames(tuning) <- NULL
  best <- tuning[1, ]
  baseline <- tuning[tuning$Candidate == baseline_id, ]
  selected_oof <- predictions[[best$Candidate]]
  selected_oof <- selected_oof[order(selected_oof$Row), ]
  baseline_oof <- predictions[[baseline_id]]
  baseline_oof <- baseline_oof[order(baseline_oof$Row), ]
  stopifnot(identical(as.integer(selected_oof$Row), seq_along(y_train)),
            identical(as.character(y_train), selected_oof$Actual))
  oof_metrics <- svm_metrics(selected_oof$Actual, selected_oof$Predicted, classes)
  best_weighted <- tuning[tuning$Weighting == "inverse", ][1, ]
  weighted_oof <- predictions[[best_weighted$Candidate]]
  weighted_metrics <- svm_metrics(weighted_oof$Actual, weighted_oof$Predicted, classes)
  weighting_tradeoff <- rbind(
    cbind(Variant = "Selected by macro-F1", oof_metrics$per_class),
    cbind(Variant = "Best weighted SVM", weighted_metrics$per_class))
  # One stable comparison row per variant for the group-wide model table.
  comparison <- rbind(cbind(Model = "SVM baseline", baseline),
                       cbind(Model = "SVM selected by CV", best))
  encoder <- svm_fit_encoder(x_train)
  final_model <- svm_train(svm_apply_encoder(encoder, x_train), y_train,
                           best$C, best$Gamma_multiplier, best$Weighting)
  bundle <- list(model = final_model, encoder = encoder, best = best,
                  class_levels = classes,
                  note = "Training-only refit. Holdout has NOT been evaluated.")
  write.csv(tuning, file.path(output_dir, "tuning_summary.csv"), row.names = FALSE)
  write.csv(comparison, file.path(output_dir, "baseline_vs_selected.csv"), row.names = FALSE)
  write.csv(selected_oof, file.path(output_dir, "selected_oof_predictions.csv"), row.names = FALSE)
  write.csv(baseline_oof, file.path(output_dir, "baseline_oof_predictions.csv"), row.names = FALSE)
  write.csv(oof_metrics$per_class, file.path(output_dir, "oof_per_class.csv"), row.names = FALSE)
  write.csv(best_weighted, file.path(output_dir, "best_weighted_cv.csv"), row.names = FALSE)
  write.csv(weighting_tradeoff, file.path(output_dir, "weighting_tradeoff.csv"), row.names = FALSE)
  write.csv(oof_metrics$summary, file.path(output_dir, "oof_pooled_metrics.csv"), row.names = FALSE)
  write.csv(as.data.frame.matrix(oof_metrics$confusion),
            file.path(output_dir, "oof_confusion_matrix.csv"))
  saveRDS(bundle, file.path(output_dir, "svm_training_refit.rds"))
  capture.output(sessionInfo(), file = file.path(output_dir, "sessionInfo.txt"))
  writeLines(c(
    "Balanced_Accuracy is macro-averaged class recall (mean sensitivity), not mean one-vs-rest (sensitivity+specificity)/2.",
    "Mean_Macro_F1 is the unweighted mean of the five fold macro-F1 values; SD is their sample standard deviation.",
    "Pooled OOF metrics pool all held-out fold predictions and need not equal the fold means.",
    "The selected configuration maximises mean CV macro-F1 across 18 candidates (90 fits).",
    "The same CV folds were used for tuning and reporting; selected CV scores are optimistic development estimates, not an independent final performance estimate.",
    "No x_test or y_test was used in tuning, selection or model fitting. Only score the holdout after the group selects its final model.",
    "The final saved SVM was refit using full training data; its encoder and class weights were learned again from full training only."
  ), file.path(output_dir, "metric_definitions.txt"))
  list(tuning = tuning, fold_scores = fold_scores, comparison = comparison,
       selected_oof = selected_oof, baseline_oof = baseline_oof,
       oof = oof_metrics, bundle = bundle,
       best_weighted = best_weighted, weighting_tradeoff = weighting_tradeoff)
}

svm_plot_results <- function(result, output_dir = "svm_results") {
  if (!requireNamespace("ggplot2", quietly = TRUE)) return(invisible(NULL))
  tuning_plot <- result$tuning
  tuning_plot$Text_colour <- ifelse(
    tuning_plot$Mean_Macro_F1 > mean(range(tuning_plot$Mean_Macro_F1)), "white", "#17324d")
  p_tuning <- ggplot2::ggplot(tuning_plot, ggplot2::aes(
    x = factor(C), y = factor(Gamma_multiplier), fill = Mean_Macro_F1)) +
    ggplot2::geom_tile(colour = "white") +
    ggplot2::geom_text(ggplot2::aes(label = sprintf("%.3f", Mean_Macro_F1), colour = Text_colour), size = 5) +
    ggplot2::scale_colour_identity() +
    ggplot2::facet_wrap(~ Weighting) +
    ggplot2::scale_fill_gradient(low = "#e8f3fa", high = "#12648a") +
    ggplot2::labs(title = "SVM tuning: mean macro-F1 across shared five-fold CV",
                   x = "Cost (C)", y = "Gamma multiplier (gamma = multiplier / p)", fill = "Macro-F1") +
    ggplot2::theme_minimal(base_size = 12) + ggplot2::theme(
      panel.grid = ggplot2::element_blank(),
      plot.margin = ggplot2::margin(14, 18, 14, 14),
      plot.title = ggplot2::element_text(size = 13))
  cm <- as.data.frame(result$oof$confusion)
  cm$Within_actual <- cm$Freq / rowSums(result$oof$confusion)[match(cm$Actual, rownames(result$oof$confusion))]
  cm$Text_colour <- ifelse(cm$Within_actual > 0.5, "white", "#17324d")
  p_cm <- ggplot2::ggplot(cm, ggplot2::aes(x = Predicted, y = Actual, fill = Within_actual)) +
    ggplot2::geom_tile(colour = "white") +
    ggplot2::geom_text(ggplot2::aes(label = sprintf("%d\n%.1f%%", Freq, 100 * Within_actual), colour = Text_colour), size = 3.5) +
    ggplot2::scale_colour_identity() +
    ggplot2::scale_y_discrete(limits = rev(result$oof$per_class$Class)) +
    ggplot2::scale_fill_gradient(low = "#eef4f8", high = "#12648a", limits = c(0, 1)) +
    ggplot2::labs(title = "Selected SVM: cross-validation confusion matrix",
                   subtitle = "Out-of-fold predictions; same folds used for tuning",
                   fill = "Row share") + ggplot2::theme_minimal(base_size = 12) +
    ggplot2::theme(panel.grid = ggplot2::element_blank(),
                    plot.margin = ggplot2::margin(14, 18, 14, 14),
                    plot.title = ggplot2::element_text(size = 13),
                    plot.subtitle = ggplot2::element_text(size = 10))
  p_recall <- ggplot2::ggplot(result$oof$per_class, ggplot2::aes(x = Class, y = Recall)) +
    ggplot2::geom_col(fill = "#12648a", width = 0.65) +
    ggplot2::geom_text(ggplot2::aes(label = sprintf("%.1f%%", 100 * Recall)), vjust = -0.4) +
    ggplot2::scale_y_continuous(limits = c(0, 1.05), breaks = seq(0, 1, 0.2),
                               labels = function(x) paste0(100 * x, "%")) +
    ggplot2::labs(title = "Which outcomes does SVM identify?", x = NULL, y = "Out-of-fold recall") +
    ggplot2::theme_minimal(base_size = 12)
  ggplot2::ggsave(file.path(output_dir, "svm_tuning.png"), p_tuning, width = 9, height = 4.5, dpi = 160)
  ggplot2::ggsave(file.path(output_dir, "svm_confusion_matrix.png"), p_cm, width = 8, height = 6, dpi = 160)
  ggplot2::ggsave(file.path(output_dir, "svm_recall.png"), p_recall, width = 8, height = 4.5, dpi = 160)
  invisible(list(tuning = p_tuning, confusion = p_cm, recall = p_recall))
}

# Run this after the group's common-cv-preprocessing chunk.
svm_results <- svm_run_cv(cv_data, cv_folds, x_train, y_train)
svm_plot_results(svm_results)
print(svm_results$comparison)
print(svm_results$oof$per_class)

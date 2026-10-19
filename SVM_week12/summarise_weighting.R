# Explain the minority-class tradeoff without consulting the holdout.
.libPaths(c(".r-library", "C:/Users/32476/AppData/Local/R/win-library/4.6", .libPaths()))
definitions <- parse("svm_model.R")
for (expression in definitions) {
  if (is.call(expression) && identical(expression[[1]], as.name("<-")) &&
      is.call(expression[[3]]) && identical(expression[[3]][[1]], as.name("function"))) {
    eval(expression)
  }
}
tuning <- read.csv("svm_results/tuning_summary.csv")
weighted <- tuning[tuning$Weighting == "inverse", ][1, ]
cache_file <- list.files("svm_results/candidate_cache",
                         pattern = paste0("_", weighted$Candidate, "[.]rds$"), full.names = TRUE)
stopifnot(length(cache_file) == 1L)
weighted_predictions <- readRDS(cache_file)$predictions
weighted_metrics <- svm_metrics(weighted_predictions$Actual, weighted_predictions$Predicted,
                                 c("Adoption", "Transfer", "Return", "Euthanasia", "Other"))
selected <- read.csv("svm_results/oof_per_class.csv")
tradeoff <- rbind(cbind(Variant = "Selected by macro-F1", selected),
                   cbind(Variant = "Best weighted SVM", weighted_metrics$per_class))
write.csv(tradeoff, "svm_results/weighting_tradeoff.csv", row.names = FALSE)
write.csv(weighted, "svm_results/best_weighted_cv.csv", row.names = FALSE)
print(tradeoff)

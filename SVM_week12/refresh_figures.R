# Rebuild figures from saved CV results without retraining the SVM.
.libPaths(c(".r-library", "C:/Users/32476/AppData/Local/R/win-library/4.6", .libPaths()))
definitions <- parse("svm_model.R")
for (expression in definitions) {
  if (is.call(expression) && identical(expression[[1]], as.name("<-")) &&
      is.call(expression[[3]]) && identical(expression[[3]][[1]], as.name("function"))) {
    eval(expression)
  }
}
cm <- as.matrix(read.csv("svm_results/oof_confusion_matrix.csv", row.names = 1, check.names = FALSE))
names(dimnames(cm)) <- c("Actual", "Predicted")
result <- list(tuning = read.csv("svm_results/tuning_summary.csv"),
                oof = list(confusion = as.table(cm),
                           per_class = read.csv("svm_results/oof_per_class.csv")))
svm_plot_results(result)

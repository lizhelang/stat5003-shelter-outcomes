# Small checks for metric definitions and leakage-safe model-specific encoding.
svm_local_libs <- c(".r-library", "C:/Users/32476/AppData/Local/R/win-library/4.6")
.libPaths(c(svm_local_libs[dir.exists(svm_local_libs)], .libPaths()))
definitions <- parse("svm_model.R")
test_env <- new.env(parent = globalenv())
# Load definitions only, without triggering the expensive full CV run.
for (expression in definitions) {
  if (is.call(expression) && identical(expression[[1]], as.name("<-")) &&
      is.call(expression[[3]]) && identical(expression[[3]][[1]], as.name("function"))) {
    eval(expression, test_env)
  }
}
with(test_env, {
  y <- factor(c("a", "a", "b", "b"))
  perfect <- svm_metrics(y, y)$summary
  stopifnot(all(unlist(perfect) == 1))
  missed <- svm_metrics(y, factor(rep("a", 4), levels = levels(y)))
  stopifnot(isTRUE(all.equal(missed$summary$Macro_F1, 1 / 3)),
            missed$summary$Balanced_Accuracy == 0.5,
            missed$per_class$F1[2] == 0)
  train <- data.frame(Type = factor(c("Cat", "Dog", "Cat", "Dog")),
                       Constant = factor(rep("same", 4)), Age_Years_imputed = c(0, 1, 2, 3))
  enc <- svm_fit_encoder(train)
  assessment <- data.frame(Type = c("Cat", "unseen", NA), Constant = rep("same", 3),
                            Age_Years_imputed = c(100, 200, 300))
  encoded <- svm_apply_encoder(enc, assessment)
  stopifnot(nrow(encoded) == 3, ncol(encoded) == 3,
            enc$age_mean == 1.5,
            abs(encoded[1, "Age_Years_imputed"] - (100 - 1.5) / sd(0:3)) < 1e-10,
            all(encoded[2:3, c("Type=Cat", "Type=Dog")] == 0),
            all(is.finite(encoded)))
  w <- svm_class_weights(factor(c("a", "a", "a", "b")), "inverse")
  stopifnot(abs(mean(w[c("a", "a", "a", "b")]) - 1) < 1e-10)
})
cat("Metric, no-predicted-class, training-only scaling, constant-column, unseen-level and class-weight checks passed.\n")

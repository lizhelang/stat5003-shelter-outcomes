library(ranger)

# Train the baseline model using default settings.
rf_baseline <- ranger(x = x_train, y = y_train, seed = 5003)

# Predict the test outcomes.
rf_baseline_pred <- predict(rf_baseline, data = x_test)$predictions

# Calculate recall and F1 for each outcome by counting observations.
rf_baseline_recall <- c()
rf_baseline_f1 <- c()

for (class in levels(y_test)) {
  # Number of animals actually in this class.
  actual_count <- sum(y_test == class)

  # Number of animals predicted to be in this class.
  predicted_count <- sum(rf_baseline_pred == class)

  # Number correctly predicted to be in this class.
  correct_count <- sum(y_test == class & rf_baseline_pred == class)

  rf_baseline_recall[class] <- correct_count / actual_count
  rf_baseline_f1[class] <- 2 * correct_count / (actual_count + predicted_count)
}

rf_baseline_results <- data.frame(
  Model = "Baseline RF",
  Macro_F1 = mean(rf_baseline_f1),
  Balanced_Accuracy = mean(rf_baseline_recall),
  Accuracy = mean(rf_baseline_pred == y_test)
)
knitr::kable(rf_baseline_results, digits = 4)

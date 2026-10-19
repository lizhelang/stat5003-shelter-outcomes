suppressPackageStartupMessages({
library(dplyr); library(tidyr); library(stringr); library(forcats);
library(ggplot2); library(scales); library(lubridate);
library(caret); library(ranger); library(knitr)
})
set.seed(5003)
# ---- dataset-scope ----
knitr::opts_chunk$set(
  message = FALSE,
  warning = FALSE
)

library(tidyr)
library(dplyr)
library(stringr)
library(forcats)
library(ggplot2)
library(scales)
library(patchwork)

# The CSV is stored in the same folder as this R Markdown file.
data <- read.csv(
  "Austin_Animal_Center_Outcomes_20260916.csv",
  stringsAsFactors = TRUE
)

# Restrict the scope to cats and dogs and consolidate the 28 raw outcomes.
data_selected <- data %>%
  filter(Type %in% c("Dog", "Puppy", "Cat", "Kitten")) %>%
  mutate(
    Outcome.Group = case_when(
      str_detect(Outcome.Status, regex("Adopt", ignore_case = TRUE)) ~ "Adoption",
      str_detect(Outcome.Status, regex("Transfer", ignore_case = TRUE)) ~ "Transfer",
      str_detect(Outcome.Status, regex("Euthan", ignore_case = TRUE)) ~ "Euthanasia",
      str_detect(
        Outcome.Status,
        regex("Reclaim|Redemption|Returned To Owner|Return to Habitat", ignore_case = TRUE)
      ) ~ "Return",
      TRUE ~ "Other"
    ),
    Outcome.Group = factor(
      Outcome.Group,
      levels = c("Adoption", "Transfer", "Return", "Euthanasia", "Other")
    )
  )

group_summary <- data_selected %>%
  count(Outcome.Group, name = "Count") %>%
  mutate(
    Percentage = 100 * Count / sum(Count),
    Outcome.Group = factor(Outcome.Group, levels = levels(data_selected$Outcome.Group))
  )

key_missing <- c(
  "Name", "Euthanasia.Reason", "Secondary.Color",
  "Date.of.Birth", "Spayed.Neutered"
)

missing_summary <- tibble(
  Feature = key_missing,
  Missing_Pct = sapply(
    key_missing,
    function(feature) {
      values <- data_selected[[feature]]
      100 * mean(is.na(values) | trimws(as.character(values)) == "")
    }
  )
) %>%
  arrange(Missing_Pct) %>%
  mutate(Feature = factor(Feature, levels = Feature))



# ---- eda-data-quality ----
library(lubridate)

# EDA audit helpers: inspect blanks and read date strings without changing the source.
is_blank <- function(x) {
  is.na(x) | trimws(as.character(x)) == ""
}

parse_shelter_date <- function(x) {
  as.Date(parse_date_time(
    as.character(x),
    orders = c("Y b d I M S p", "ymd HMS", "mdy HMS", "dmy HMS",
               "ymd", "mdy", "dmy"),
    locale = "C", tz = "UTC", quiet = TRUE
  ))
}

# Keep this copy unchanged throughout EDA.
data_eda <- data_selected

# age check
age_audit <- tibble(
  DOB = parse_shelter_date(data_eda$Date.of.Birth),
  Intake_Date = parse_shelter_date(data_eda$Intake.Date)
) %>%
  mutate(Age_Years_raw = as.numeric(Intake_Date - DOB) / 365)

quality_features <- c(
  "Type", "Sex", "Spayed.Neutered", "Primary.Breed",
  "Primary.Color", "Secondary.Color", "Name", "Date.of.Birth", "Intake.Date"
)
quality_summary <- tibble(
  Feature = quality_features,
  Distinct_nonblank = sapply(quality_features, function(v) {
    x <- as.character(data_eda[[v]])
    n_distinct(x[!is_blank(x)])
  }),
  Missing_n = sapply(quality_features, function(v) sum(is_blank(data_eda[[v]]))),
  Missing_pct = 100 * Missing_n / nrow(data_eda),
  Unknown_label_n = sapply(quality_features, function(v) {
    sum(str_to_lower(trimws(as.character(data_eda[[v]]))) == "unknown",
        na.rm = TRUE)
  })
)
knitr::kable(quality_summary, digits = 2,
             caption = "Raw-field quality in the complete cat-and-dog subset")

quality_checks <- tibble(
  Check = c("Records", "Distinct nonmissing Animal IDs", "Exact duplicate rows",
            "Animal IDs with more than one record", "Missing Animal IDs",
            "Nonblank birth dates that failed parsing",
            "Nonblank intake dates that failed parsing",
            "Age unavailable from dates", "Negative ages observed"),
  Count = c(
    nrow(data_eda),
    n_distinct(data_eda$Animal.ID[!is_blank(data_eda$Animal.ID)]),
    sum(duplicated(data_eda)),
    sum(table(data_eda$Animal.ID[!is_blank(data_eda$Animal.ID)]) > 1),
    sum(is_blank(data_eda$Animal.ID)),
    sum(!is_blank(data_eda$Date.of.Birth) & is.na(age_audit$DOB)),
    sum(!is_blank(data_eda$Intake.Date) & is.na(age_audit$Intake_Date)),
    sum(is.na(age_audit$Age_Years_raw)),
    sum(age_audit$Age_Years_raw < 0, na.rm = TRUE)
  )
)
knitr::kable(quality_checks, caption = "Record and date checks")


# ---- latest-intake-record ----
# Preprocessing 1. Retain one record per animal: its latest recorded intake.
# Keep the source row order so tied intake timestamps have a fixed rule.
data_latest <- data_selected %>%
  mutate(
    .source_row = row_number(),
    Intake_Datetime = parse_date_time(
      as.character(Intake.Date),
      orders = c("Y b d I M S p", "ymd HMS", "mdy HMS", "dmy HMS",
                 "ymd", "mdy", "dmy"),
      locale = "C", tz = "UTC", quiet = TRUE
    )
  )

data_latest <- data_latest %>%
  # Sort each animal's records from newest to oldest.
  # For equal timestamps, the first row in the source file comes first.
  arrange(Animal.ID, desc(Intake_Datetime), .source_row) %>%
  group_by(Animal.ID) %>%
  filter(row_number() == 1) %>%
  ungroup() %>%
  # Restore source order and remove the temporary selection columns.
  arrange(.source_row) %>%
  select(-.source_row, -Intake_Datetime)


# ---- fixed-model-features ----
# Preprocessing 2-6. Construct model features from the retained latest-intake records.
prepare_features <- function(df) {
  df %>%
    mutate(
      # 2. Type-Age redundancy: Type now contains species only.
      Type_original = as.character(Type),
      Type = factor(case_when(
        Type_original %in% c("Dog", "Puppy") ~ "Dog",
        Type_original %in% c("Cat", "Kitten") ~ "Cat",
        TRUE ~ NA_character_
      ), levels = c("Cat", "Dog")),

      # 3. Age at intake: this is the first conversion of negative ages to NA.
      DOB = parse_shelter_date(Date.of.Birth),
      Intake_Date = parse_shelter_date(Intake.Date),
      Age_Years_raw = as.numeric(Intake_Date - DOB) / 365,
      Age_Years = if_else(Age_Years_raw < 0, NA_real_, Age_Years_raw),

      # 4. Name: treat blanks and case-insensitive placeholders as not recorded.
      has_Name = factor(if_else(
        is_blank(Name) | str_to_lower(trimws(as.character(Name))) %in%
          c("unknown", "*", "n/a", "na"), "0", "1"
      ), levels = c("0", "1")),

      # 5. Sex / Spayed.Neutered: standardise spelling, case and missing values.
      Sex = factor(case_when(
        str_to_lower(trimws(as.character(Sex))) == "male" ~ "Male",
        str_to_lower(trimws(as.character(Sex))) == "female" ~ "Female",
        TRUE ~ "Unknown"
      ), levels = c("Female", "Male", "Unknown")),
      Spayed.Neutered = factor(case_when(
        str_to_lower(trimws(as.character(Spayed.Neutered))) == "yes" ~ "Yes",
        str_to_lower(trimws(as.character(Spayed.Neutered))) == "no" ~ "No",
        TRUE ~ "Unknown"
      ), levels = c("No", "Yes", "Unknown")),

      # 6. Breed / Colour: fixed text cleaning; frequency grouping is deferred.
      Primary.Breed = if_else(is_blank(Primary.Breed), "Unknown",
                              trimws(as.character(Primary.Breed))),
      Base_Color = factor(case_when(
        is_blank(Primary.Color) ~ "Unknown",
        str_detect(Primary.Color, regex("brown|tan|choc|fawn|buff|sable|liver|cinnamon|rust|agouti|bronze|chestnut|sandy|seal", ignore_case = TRUE)) ~ "Brown/Tan",
        str_detect(Primary.Color, regex("black|charcoal|sooty", ignore_case = TRUE)) ~ "Black",
        str_detect(Primary.Color, regex("white|cream|blonde|albino|champagne|wheat|snow", ignore_case = TRUE)) ~ "White/Cream",
        str_detect(Primary.Color, regex("blue|grey|gray|silver|lilac|wolf", ignore_case = TRUE)) ~ "Blue/Grey",
        str_detect(Primary.Color, regex("orange|red|ginger|yellow|gold|apricot|lemon|flame", ignore_case = TRUE)) ~ "Orange/Red",
        TRUE ~ "Other"
      )),
      has_pattern = factor(case_when(
        !is_blank(Secondary.Color) |
          coalesce(str_detect(Primary.Color, regex(
            "tabby|brindle|smoke|point|calico|torbie|tort|tri|merle|tiger|ticked|lynx|roan|bicolor|patch|shaded",
            ignore_case = TRUE
          )), FALSE) ~ "Mixed",
        is_blank(Primary.Color) ~ "Unknown",
        TRUE ~ "Pure"
      ), levels = c("Pure", "Mixed", "Unknown"))
    )
}

data_features <- prepare_features(data_latest)

# ---- shared-data-split ----
# Preprocessing 7. Shared 80/20 split and 5 CV folds using caret.
library(caret)
set.seed(5003)

# createDataPartition returns the training row numbers, stratified by outcome.
train_index <- createDataPartition(
  data_features$Outcome.Group,
  p = 0.8,
  list = FALSE
)
train_raw <- data_features[train_index, ]
test_raw <- data_features[-train_index, ]
y_train <- train_raw$Outcome.Group
y_test <- test_raw$Outcome.Group

# Each list element contains the validation row numbers within train_raw.
cv_folds <- createFolds(
  y_train,
  k = 5,
  list = TRUE,
  returnTrain = FALSE
)

# ---- common-train-test-preprocessing ----
# 8. Learn species-specific age medians from training only.
overall_age_median <- median(train_raw$Age_Years, na.rm = TRUE)
age_medians <- train_raw %>%
  group_by(Type) %>%
  summarise(Age_Median = median(Age_Years, na.rm = TRUE), .groups = "drop")

# 9. Select the eight most common recorded breeds in training.
top8_breeds <- train_raw %>%
  filter(Primary.Breed != "Unknown") %>%
  count(Primary.Breed, name = "Count") %>%
  arrange(desc(Count), Primary.Breed) %>%
  filter(row_number() <= 8) %>%
  pull(Primary.Breed)

# 10. Keep these eight predictors in x_train/x_test; y_train/y_test hold the outcome.
model_predictors <- c(
  "Type", "Sex", "Spayed.Neutered", "primary.breed.group",
  "Base_Color", "has_pattern", "has_Name", "Age_Years_imputed"
)
factor_predictors <- setdiff(model_predictors, "Age_Years_imputed")

# Apply steps 8-10 to training: fill missing ages and group breeds.
# Use the overall training median only if a species median is unavailable.
x_train <- train_raw %>%
  left_join(age_medians, by = "Type") %>%
  mutate(
    Age_Years_imputed = case_when(
      !is.na(Age_Years) ~ Age_Years,
      !is.na(Age_Median) ~ Age_Median,
      TRUE ~ overall_age_median
    ),
    primary.breed.group = if_else(
      Primary.Breed %in% top8_breeds, Primary.Breed, "Other"
    )
  ) %>%
  select(all_of(model_predictors))

# Apply the same training medians and breed list to the test data.
x_test <- test_raw %>%
  left_join(age_medians, by = "Type") %>%
  mutate(
    Age_Years_imputed = case_when(
      !is.na(Age_Years) ~ Age_Years,
      !is.na(Age_Median) ~ Age_Median,
      TRUE ~ overall_age_median
    ),
    primary.breed.group = if_else(
      Primary.Breed %in% top8_breeds, Primary.Breed, "Other"
    )
  ) %>%
  select(all_of(model_predictors))

# Use the same factor levels in training and test data.
for (variable in factor_predictors) {
  x_train[[variable]] <- factor(x_train[[variable]])
  x_test[[variable]] <- factor(
    x_test[[variable]],
    levels = levels(x_train[[variable]])
  )
}


# ---- common-cv-preprocessing ----
# Repeat steps 8-10 within each fold, starting from data before imputation.
# Learn the rules from fold_train only, then apply them to fold_valid.
cv_data <- list()
for (k in 1:5) {
  fold_train <- train_raw[-cv_folds[[k]], ]
  fold_valid <- train_raw[cv_folds[[k]], ]

  # 8. Age medians from this fold's training data.
  fold_overall_median <- median(fold_train$Age_Years, na.rm = TRUE)
  fold_age_medians <- fold_train %>%
    group_by(Type) %>%
    summarise(Age_Median = median(Age_Years, na.rm = TRUE), .groups = "drop")

  # 9. Top eight breeds from this fold's training data.
  fold_top8_breeds <- fold_train %>%
    filter(Primary.Breed != "Unknown") %>%
    count(Primary.Breed, name = "Count") %>%
    arrange(desc(Count), Primary.Breed) %>%
    filter(row_number() <= 8) %>%
    pull(Primary.Breed)

  # 8-10. Apply the rules and keep the common predictors.
  fold_train <- fold_train %>%
    left_join(fold_age_medians, by = "Type") %>%
    mutate(
      Age_Years_imputed = case_when(
        !is.na(Age_Years) ~ Age_Years,
        !is.na(Age_Median) ~ Age_Median,
        TRUE ~ fold_overall_median
      ),
      primary.breed.group = if_else(
        Primary.Breed %in% fold_top8_breeds, Primary.Breed, "Other"
      )
    ) %>%
    select(Outcome.Group, all_of(model_predictors))

  fold_valid <- fold_valid %>%
    left_join(fold_age_medians, by = "Type") %>%
    mutate(
      Age_Years_imputed = case_when(
        !is.na(Age_Years) ~ Age_Years,
        !is.na(Age_Median) ~ Age_Median,
        TRUE ~ fold_overall_median
      ),
      primary.breed.group = if_else(
        Primary.Breed %in% fold_top8_breeds, Primary.Breed, "Other"
      )
    ) %>%
    select(Outcome.Group, all_of(model_predictors))

  # 10. Use this fold's training factor levels for validation.
  for (variable in factor_predictors) {
    fold_train[[variable]] <- factor(fold_train[[variable]])
    fold_valid[[variable]] <- factor(
      fold_valid[[variable]],
      levels = levels(fold_train[[variable]])
    )
  }

  cv_data[[k]] <- list(
    x_train = select(fold_train, all_of(model_predictors)),
    y_train = fold_train$Outcome.Group,
    x_valid = select(fold_valid, all_of(model_predictors)),
    y_valid = fold_valid$Outcome.Group
  )
}

# Each cv_data[[k]] contains x_train, y_train, x_valid and y_valid.
# Validation data stay separate from the final x_test/y_test holdout.
# cv_folds[[k]] identifies the validation rows for out-of-fold predictions.
# This block prepares common data; model fitting/scoring belongs in each model section.

# Variable	Description
# x_train	Preprocessed predictors for the full training set (80%).
# y_train	Outcome labels for the full training set.
# x_test	Test predictors processed using the training-derived rules (20%).
# y_test	Outcome labels for final test evaluation.
# 5-fold CV : cv_data




# ---- RF CV (Daun grid on shared folds) ----
macro_f1 <- function(actual, predicted) {
  classes <- levels(actual)
  mean(sapply(classes, function(cl) {
    tp <- sum(actual == cl & predicted == cl)
    pred_n <- sum(predicted == cl)
    act_n <- sum(actual == cl)
    if (act_n + pred_n == 0) return(0)
    2 * tp / (act_n + pred_n)
  }))
}
bal_acc <- function(actual, predicted) {
  classes <- levels(actual)
  mean(sapply(classes, function(cl) {
    act_n <- sum(actual == cl)
    if (act_n == 0) return(NA_real_)
    sum(actual == cl & predicted == cl) / act_n
  }), na.rm = TRUE)
}

rf_grid <- expand.grid(num.trees = c(100, 300, 500), mtry = c(2, 4, 8))
rf_cv_results <- data.frame()
for (i in seq_len(nrow(rf_grid))) {
  for (k in seq_along(cv_data)) {
    fold <- cv_data[[k]]
    rf_model <- ranger(
      x = fold$x_train, y = fold$y_train,
      num.trees = rf_grid$num.trees[i],
      mtry = rf_grid$mtry[i], seed = 5003 + k
    )
    preds <- predict(rf_model, data = fold$x_valid)$predictions
    rf_cv_results <- rbind(rf_cv_results, data.frame(
      num.trees = rf_grid$num.trees[i], mtry = rf_grid$mtry[i],
      Fold = k,
      Macro_F1 = macro_f1(fold$y_valid, preds),
      Balanced_Accuracy = bal_acc(fold$y_valid, preds),
      Accuracy = mean(preds == fold$y_valid)
    ))
  }
  cat(sprintf("grid %d/%d done\n", i, nrow(rf_grid)))
}

rf_cv_summary <- rf_cv_results %>%
  group_by(num.trees, mtry) %>%
  summarise(
    Mean_Macro_F1 = mean(Macro_F1),
    SD_Macro_F1 = sd(Macro_F1),
    Mean_Balanced_Accuracy = mean(Balanced_Accuracy),
    Mean_Accuracy = mean(Accuracy),
    .groups = "drop"
  ) %>%
  arrange(desc(Mean_Macro_F1))

dir.create("model_comparison/results", showWarnings = FALSE, recursive = TRUE)
write.csv(rf_cv_results, "model_comparison/results/rf_cv_fold_scores.csv", row.names = FALSE)
write.csv(rf_cv_summary, "model_comparison/results/rf_cv_summary.csv", row.names = FALSE)

rf_best <- rf_cv_summary[1, ]
best_preds <- list(); best_actual <- list()
for (k in seq_along(cv_data)) {
  fold <- cv_data[[k]]
  rf_model <- ranger(
    x = fold$x_train, y = fold$y_train,
    num.trees = rf_best$num.trees, mtry = rf_best$mtry, seed = 5003 + k
  )
  preds <- predict(rf_model, data = fold$x_valid)$predictions
  best_preds[[k]] <- preds
  best_actual[[k]] <- fold$y_valid
}
actual <- factor(unlist(best_actual), levels = levels(y_train))
predicted <- factor(unlist(best_preds), levels = levels(y_train))
per_class <- bind_rows(lapply(levels(actual), function(cl) {
  tp <- sum(actual == cl & predicted == cl)
  fp <- sum(actual != cl & predicted == cl)
  fn <- sum(actual == cl & predicted != cl)
  prec <- ifelse(tp + fp == 0, 0, tp / (tp + fp))
  rec <- ifelse(tp + fn == 0, 0, tp / (tp + fn))
  f1 <- ifelse(prec + rec == 0, 0, 2 * prec * rec / (prec + rec))
  data.frame(Class = cl, Support = sum(actual == cl), Precision = prec, Recall = rec, F1 = f1)
}))
write.csv(per_class, "model_comparison/results/rf_oof_per_class.csv", row.names = FALSE)
pooled <- data.frame(
  Model = "Random Forest (CV-selected)",
  Macro_F1_pooled_oof = mean(per_class$F1),
  Balanced_Accuracy_pooled_oof = mean(per_class$Recall),
  Accuracy_pooled_oof = mean(actual == predicted),
  Mean_CV_Macro_F1 = rf_best$Mean_Macro_F1,
  SD_CV_Macro_F1 = rf_best$SD_Macro_F1,
  Mean_CV_Balanced_Accuracy = rf_best$Mean_Balanced_Accuracy,
  num.trees = rf_best$num.trees,
  mtry = rf_best$mtry
)
write.csv(pooled, "model_comparison/results/rf_selected_metrics.csv", row.names = FALSE)
print(rf_cv_summary)
print(pooled)
print(per_class)
cat("RF CV complete.\n")

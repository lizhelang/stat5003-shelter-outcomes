# Standalone entry point: use the untouched shared v29 preprocessing.
# From RStudio, set the working directory to this script's folder, then source it.
svm_local_libs <- c(".r-library", "C:/Users/32476/AppData/Local/R/win-library/4.6")
.libPaths(c(svm_local_libs[dir.exists(svm_local_libs)], .libPaths()))
required <- c("tidyr", "dplyr", "stringr", "forcats", "ggplot2", "scales",
              "patchwork", "lubridate", "caret", "knitr", "e1071", "digest")
missing <- required[!vapply(required, requireNamespace, logical(1), quietly = TRUE)]
if (length(missing)) stop("Install required packages first: ", paste(missing, collapse = ", "))

report_file <- "STAT5003_group_project_RMarkdown_template_v29.Rmd"
stopifnot(file.exists(report_file), file.exists("Austin_Animal_Center_Outcomes_20260916.csv"))
lines <- readLines(report_file, warn = FALSE)
needed <- c("dataset-scope", "eda-data-quality", "latest-intake-record",
             "fixed-model-features", "shared-data-split",
             "common-train-test-preprocessing", "common-cv-preprocessing")
chunks <- list()
for (name in needed) {
  start <- grep(paste0("^```\\{r ", name, "[,}]"), lines)
  stopifnot(length(start) == 1L)
  finish <- which(seq_along(lines) > start & lines == "```")[1]
  chunks[[name]] <- lines[(start + 1L):(finish - 1L)]
}
svm_shared_environment <- new.env(parent = globalenv())
# The first shared chunk draws an EDA plot; send it to a temporary device.
svm_plot_device <- tempfile(fileext = ".pdf")
grDevices::pdf(svm_plot_device)
tryCatch({
  for (name in needed) {
    message("Running shared preprocessing: ", name)
    eval(parse(text = chunks[[name]]), envir = svm_shared_environment)
  }
}, finally = grDevices::dev.off())

with(svm_shared_environment, {
  stopifnot(!any(is_blank(data_selected$Animal.ID)),
            !anyNA(parse_shelter_date(data_selected$Intake.Date)),
            !anyDuplicated(data_latest$Animal.ID),
            length(intersect(train_raw$Animal.ID, test_raw$Animal.ID)) == 0L,
            !anyNA(x_train), !anyNA(x_test),
            sum(!is_blank(data_selected$Intake.Date) &
                  is.na(parse_shelter_date(data_selected$Intake.Date))) == 0L)
})
dir.create("svm_results", showWarnings = FALSE)
svm_manifest <- with(svm_shared_environment, data.frame(
  Animal_ID = c(train_raw$Animal.ID, test_raw$Animal.ID),
  Partition = c(rep("train", nrow(train_raw)), rep("test", nrow(test_raw))),
  Row_in_partition = c(seq_len(nrow(train_raw)), seq_len(nrow(test_raw)))
))
write.csv(svm_manifest, "svm_results/split_manifest.csv", row.names = FALSE)
svm_audit <- with(svm_shared_environment, data.frame(
  Check = c("CSV rows", "Cat/dog rows", "Latest-intake animals", "Training rows", "Reserved test rows"),
  Count = c(nrow(data), nrow(data_selected), nrow(data_latest), nrow(x_train), nrow(x_test))))
print(svm_audit)
write.csv(svm_audit, "svm_results/data_audit.csv", row.names = FALSE)
writeLines(c("Repository: https://github.com/lizhelang/stat5003-shelter-outcomes",
              "Source commit: 2e4ca872a0c1828fa219426f781107ef3b743cd6",
              paste("Dataset MD5:", tools::md5sum("Austin_Animal_Center_Outcomes_20260916.csv")),
              paste("Run time (UTC):", format(Sys.time(), tz = "UTC", usetz = TRUE))),
            "svm_results/provenance.txt")
options(stat5003.svm.workers = 3L)
sys.source("svm_model.R", envir = svm_shared_environment)
svm_results <- svm_shared_environment$svm_results
message("Finished. See svm_results/ and SVM_results.Rmd. The test set was not scored.")

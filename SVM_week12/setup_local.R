# Local validation environment; no packages are written to the system library.
dir.create(".r-library", showWarnings = FALSE)
.libPaths(c(normalizePath(".r-library"),
            "C:/Users/32476/AppData/Local/R/win-library/4.6", .libPaths()))
required <- c("e1071", "caret")
missing <- required[!vapply(required, requireNamespace, logical(1), quietly = TRUE)]
if (length(missing)) {
  install.packages(missing, lib = .libPaths()[1],
                   repos = "https://cloud.r-project.org", type = "binary")
}
stopifnot(all(vapply(required, requireNamespace, logical(1), quietly = TRUE)))

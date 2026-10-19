# Audit only: do not change the shared v29 selection or random split.
.libPaths(c("C:/Users/32476/AppData/Local/R/win-library/4.6", .libPaths()))
suppressPackageStartupMessages(library(lubridate))
suppressPackageStartupMessages(library(dplyr))
d <- read.csv("Austin_Animal_Center_Outcomes_20260916.csv", stringsAsFactors = TRUE)
d <- d[d$Type %in% c("Cat", "Dog", "Kitten", "Puppy"), ]
d$.source_row <- seq_len(nrow(d))
text <- as.character(d$Intake.Date)
d$shared_time <- parse_date_time(text,
  orders = c("Y b d I M S p", "ymd HMS", "mdy HMS", "dmy HMS", "ymd", "mdy", "dmy"),
  locale = "C", tz = "UTC", quiet = TRUE)
# Exact format used by the repository CSV, including its AM/PM marker.
d$explicit_ampm_time <- as.POSIXct(text, format = "%m/%d/%Y %I:%M:%S %p", tz = "UTC")
stopifnot(!anyNA(d$explicit_ampm_time))
shared <- d %>% arrange(Animal.ID, desc(shared_time), .source_row) %>%
  distinct(Animal.ID, .keep_all = TRUE) %>% select(Animal.ID, Shared_row = .source_row)
explicit <- d %>% arrange(Animal.ID, desc(explicit_ampm_time), .source_row) %>%
  distinct(Animal.ID, .keep_all = TRUE) %>% select(Animal.ID, Explicit_row = .source_row)
joined <- inner_join(shared, explicit, by = "Animal.ID")
changed <- joined[joined$Shared_row != joined$Explicit_row, ]
summary <- data.frame(
  Check = c("Intake timestamps differing from explicit AM/PM parsing",
             "Animals whose retained source row would change"),
  Count = c(sum(d$shared_time != d$explicit_ampm_time), nrow(changed)))
dir.create("svm_results", showWarnings = FALSE)
write.csv(summary, "svm_results/shared_date_audit.csv", row.names = FALSE)
write.csv(changed, "svm_results/shared_date_selection_changes.csv", row.names = FALSE)
print(summary)

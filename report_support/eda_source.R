# Original EDA source retained from STAT5003_group_project_RMarkdown_template_v29.Rmd.
# Extracted without changing calculations; loaded in a separate environment for report layout.

# Original EDA chunk 1: eda-data-quality, message=FALSE, warning=FALSE
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

# Original EDA chunk 2: eda-plot-helpers
# These functions aggregate observed categories
outcome_colours <- setNames(
  c("#66C2A5", "#FC8D62", "#8DA0CB", "#E78AC3", "#A6D854"),
  levels(data_eda$Outcome.Group)
)

outcome_summary <- function(df, feature) {
  df %>%
    mutate(Level = as.character(.data[[feature]])) %>%
    select(Level, Outcome.Group) %>%
    count(Level, Outcome.Group, .drop = FALSE) %>%
    group_by(Level) %>%
    mutate(Total = sum(n), Prop = n / Total) %>%
    ungroup()
}

# Axis labels distinguish NA, blanks and whitespace without changing their values.
display_eda_level <- function(x) {
  labels <- as.character(x)
  labels[is.na(x)] <- "<NA>"
  labels[!is.na(x) & x == ""] <- "<blank>"
  whitespace <- !is.na(x) & x != "" & trimws(x) == ""
  labels[whitespace] <- "<whitespace>"
  labels
}

plot_outcome_summary <- function(summary, title) {
  totals <- distinct(summary, Level, Total)
  ggplot(summary, aes(x = Level, y = Prop, fill = Outcome.Group)) +
    geom_col(width = 0.6) +
    scale_x_discrete(labels = function(x) {
      paste0(display_eda_level(x), "\n(n=",
             scales::comma(totals$Total[match(x, totals$Level)]), ")")
    }) +
    scale_y_continuous(labels = percent_format(),
                       expand = expansion(mult = c(0, 0.03))) +
    scale_fill_manual(values = outcome_colours, drop = FALSE) +
    labs(title = title, x = NULL, y = "Within-group proportion", fill = "Outcome") +
    theme_minimal(base_size = 9) +
    theme(plot.title = element_text(face = "bold", size = 10),
          axis.text.x = element_text(angle = 30, hjust = 1),
          panel.grid.minor = element_blank(), legend.position = "bottom")
}

plot_outcome <- function(df, feature, title) {
  plot_outcome_summary(outcome_summary(df, feature), title)
}

plot_outcome_heatmap <- function(summary, title) {
  totals <- distinct(summary, Level, Total)
  ggplot(summary, aes(x = Outcome.Group, y = Level, fill = Prop)) +
    geom_tile(colour = "white") +
    geom_text(aes(label = if_else(Prop >= 0.08, sprintf("%.0f%%", 100 * Prop), "")),
              size = 3) +
    scale_y_discrete(labels = function(x) {
      paste0(display_eda_level(x), " (n=",
             scales::comma(totals$Total[match(x, totals$Level)]), ")")
    }) +
    scale_fill_gradient(low = "#F0F4F8", high = "#1F78B4", labels = percent_format()) +
    labs(title = title, x = NULL, y = NULL, fill = "Proportion") +
    theme_minimal(base_size = 9) +
    theme(plot.title = element_text(face = "bold", size = 10),
          panel.grid = element_blank())
}

outcome_rate <- function(feature, level, outcome) {
  x <- outcome_summary(data_eda, feature)
  index <- !is.na(x$Level) & x$Level == level & x$Outcome.Group == outcome
  value <- x$Prop[index]
  if (length(value) == 0L) return("not observed")
  sprintf("%.1f%%", 100 * value)
}

# Original EDA chunk 3: type-outcome, fig.width=9, fig.height=3.5, out.width="85%", fig.align="center"
# Summarise original Type values
type_age_summary <- tibble(
  Type = data_eda$Type,
  Age_Years_raw = age_audit$Age_Years_raw
) %>%
  group_by(Type, .drop = TRUE) %>%
  summarise(
    n = n(),
    Missing_age = sum(is.na(Age_Years_raw)),
    Negative_age = sum(Age_Years_raw < 0, na.rm = TRUE),
    Median_age = median(Age_Years_raw[!is.na(Age_Years_raw) & Age_Years_raw >= 0]),
    Q1 = quantile(Age_Years_raw[!is.na(Age_Years_raw) & Age_Years_raw >= 0], 0.25),
    Q3 = quantile(Age_Years_raw[!is.na(Age_Years_raw) & Age_Years_raw >= 0], 0.75),
    .groups = "drop"
  )
knitr::kable(type_age_summary, digits = 2,
             caption = "Original Type categories and observed nonnegative age")
p_type_outcome <- plot_outcome(data_eda, "Type", "Shelter Outcome by Original Type")
print(p_type_outcome)

# Original EDA chunk 4: , fig.width=9, fig.height=3.5, out.width="85%", fig.align='center'
library(ggplot2)
breed_summary <- data_selected %>%
  count(Primary.Breed, name = "Count") %>%
  arrange(desc(Count)) %>%
  mutate(
    Rank = row_number(),
    Pct = Count / sum(Count) * 100,
    Cum_Pct = cumsum(Pct)
  )

elbow_breed_rank <- 8
elbow_breed_val <- breed_summary$Cum_Pct[elbow_breed_rank]

# line plot for accumulated breed distribution
p_breed_elbow <- ggplot(breed_summary, aes(x = Rank, y = Cum_Pct)) +
  geom_area(fill = "#1f78b4", alpha = 0.12) +
  geom_line(color = "#1f78b4", linewidth = 1.2) +
  geom_hline(yintercept = 80, linetype = "dashed", color = "#666666", linewidth = 0.6) +
  geom_vline(xintercept = elbow_breed_rank, linetype = "dashed", color = "#666666", linewidth = 0.6) +
  geom_point(data = filter(breed_summary, Rank == elbow_breed_rank), 
             color = "#e31a1c", size = 3.5) +
  geom_point(data = filter(breed_summary, Rank == elbow_breed_rank), 
             color = "white", size = 1.5) +
  scale_x_continuous(
    breaks = c(1, 8, 25, 50, 100, 150, 193),
    expand = expansion(mult = c(0.01, 0.03))
  ) +
  scale_y_continuous(
    limits = c(0, 103),
    breaks = seq(0, 100, by = 20),
    labels = function(x) paste0(x, "%"),
    expand = expansion(mult = c(0, 0.01))
  ) +
  labs(
    title = "Primary Breed Cumulative Coverage",
    x = "Breed Rank (Ordered by Population Frequency)",
    y = "Cumulative Share of Population"
  ) +
  theme_minimal(base_size = 12) +
  theme(
    plot.title = element_text(face = "bold", size = 13, color = "#1a1a1a"),
    plot.subtitle = element_text(color = "#555555", margin = margin(b = 10)),
    panel.grid.minor = element_blank(),
    panel.grid.major = element_line(color = "#ebebeb"),
    axis.line = element_line(color = "#cccccc"),
    axis.title = element_text(face = "bold", size = 10.5)
  )

print(p_breed_elbow)

# Original EDA chunk 5: , fig.width=9, fig.height=3.5, out.width="85%", fig.align='center'
# library(tidyverse)
# 
# # 
# raw_colors <- colour_eda$Primary.Color[!is.na(colour_eda$Primary.Color) & trimws(colour_eda$Primary.Color) != ""]
# 
# 
# tokens <- unlist(strsplit(tolower(raw_colors), "[^a-zA-Z]+"))
# tokens <- tokens[tokens != ""]  
# 
# word_freq <- as.data.frame(table(word = tokens), stringsAsFactors = FALSE) %>%
#   rename(n = Freq) %>%
#   arrange(desc(n)) %>%
#   mutate(pct = round(n / sum(n) * 100, 2))
# write.csv(word_freq, 'word_freq.csv')
# Group base_color type and Check if pattern
# Use a plotting copy; keep the original selected records unchanged.
colour_eda <- data_eda %>%
  mutate(
    Base_Color = case_when(
      str_detect(str_to_lower(Primary.Color), regex("brown|tan|choc|fawn|buff|sable|liver|cinnamon|rust|agouti|bronze|chestnut|sandy|seal", ignore_case = TRUE)) ~ "Brown/Tan",
      str_detect(str_to_lower(Primary.Color), regex("black|charcoal|sooty", ignore_case = TRUE)) ~ "Black",
      str_detect(str_to_lower(Primary.Color), regex("white|cream|blonde|albino|champagne|wheat|snow", ignore_case = TRUE)) ~ "White/Cream",
      str_detect(str_to_lower(Primary.Color), regex("blue|grey|gray|silver|lilac|wolf", ignore_case = TRUE)) ~ "Blue/Grey",
      str_detect(str_to_lower(Primary.Color), regex("orange|red|ginger|yellow|gold|apricot|lemon|flame", ignore_case = TRUE)) ~ "Orange/Red",
      TRUE ~ "Other"
    ),
    Base_Color = as.factor(Base_Color),
    has_pattern = if_else(
      (!is.na(Secondary.Color) & Secondary.Color != '') |
      str_detect(str_to_lower(Primary.Color), regex("tabby|brindle|smoke|Point|calico|torbie|tort|tri|merle|tiger|ticked|lynx|roan|bicolor|patch|shaded", ignore_case = TRUE)),
      "Mixed",
      "Pure"
    ),
    has_pattern = as.factor(has_pattern)
  )


# Base_Color distribution
p_base_bar <- ggplot(colour_eda, aes(x = Base_Color, fill = Base_Color)) +
  geom_bar(width = 0.6, show.legend = FALSE) +
  geom_text(
    stat = "count",
    aes(label = sprintf("%.1f%%\n(%s)", 
                        after_stat(count) / sum(after_stat(count)) * 100,
                        format(after_stat(count), big.mark = ","))),
    vjust = -0.05,
    size = 3.2
  ) +
  scale_y_continuous(expand = expansion(mult = c(0, 0.30))) +
  scale_fill_brewer(palette = "Set2") +
  labs(
    title = "Distribution of Base Colors",
    x = "Base Color Group",
    y = "Count"
  ) +
  theme_minimal(base_size = 12) +
  theme(
    plot.title = element_text(face = "bold", size = 8),
    axis.text.x = element_text(angle = 35, hjust = 1, size = 7),
    panel.grid.minor = element_blank()
  )



# has_pattern distribution
p_pattern_bar <- ggplot(colour_eda, aes(x = has_pattern, fill = has_pattern)) +
  geom_bar(width = 0.5, show.legend = FALSE) +
  geom_text(
    stat = "count",
    aes(label = sprintf("%.1f%%\n(%s)", 
                        after_stat(count) / sum(after_stat(count)) * 100,
                        format(after_stat(count), big.mark = ","))),
    vjust = -0.05,
    size = 3.2
  ) +
  scale_y_continuous(expand = expansion(mult = c(0, 0.30))) +
  scale_fill_manual(values = c("Pure" = "#4575b4", "Mixed" = "#fdae61")) +
  labs(
    title = "Distribution of Patterns",
    x = "Pattern",
    y = "Count"
  ) +
  theme_minimal(base_size = 12) +
  theme(
    plot.title = element_text(face = "bold", size = 8),
    panel.grid.minor = element_blank()
  )

base_outcome_pct <- colour_eda %>%
  count(Base_Color, Outcome.Group) %>%
  group_by(Base_Color) %>%
  mutate(
    Prop = n / sum(n),
    label_text = if_else(
      Outcome.Group %in% c("Adoption", "Transfer"),
      sprintf("%.1f%%", Prop * 100),
      ""
    )
  ) %>%
  ungroup()

p_base_vs_outcome <- ggplot(base_outcome_pct, aes(x = Base_Color, y = Prop, fill = Outcome.Group)) +
  geom_col(position = "fill", width = 0.6) +
  geom_text(
    aes(label = label_text),
    position = position_fill(vjust = 0.5),
    color = "white",
    fontface = "bold",
    size = 3.2
  ) +
  scale_y_continuous(labels = percent_format(), expand = expansion(mult = c(0, 0.05))) +
  scale_fill_brewer(palette = "Set2") +
  labs(
    title = "Base Color Groups Across Outcome",
    x = "Base Color Group",
    y = "Proportion (%)",
    fill = "Outcome Group"
  ) +
  theme_minimal(base_size = 12) +
  theme(
    plot.title = element_text(face = "bold", size = 8),
    axis.text.x = element_text(angle = 35, hjust = 1, size = 7),
    legend.position = "right",
    legend.title = element_text(size = 8),
    legend.text = element_text(size = 7),
    legend.key.height = grid::unit(0.35, "cm")
  )


p_base_bar + p_pattern_bar + p_base_vs_outcome+ plot_layout(widths = c(1.5, 1, 1))

# Original EDA chunk 6: pattern-outcome-additional, fig.width=9, fig.height=3.5, out.width="85%", fig.align="center"
p_pattern_outcome <- plot_outcome(
  colour_eda, "has_pattern", "Shelter Outcome by Pattern"
)
print(p_pattern_outcome)

# Original EDA chunk 7: , fig.width=9, fig.height=3.5, out.width="85%", fig.align='center'
library(lubridate)

# Calculate observed ages in a plotting copy only.
age_eda <- data_eda %>%
  # Use calendar dates, consistent with the audit and model features.
  mutate(
    DOB = parse_shelter_date(Date.of.Birth),
    Intake_Date = parse_shelter_date(Intake.Date),
    Age_Years = as.numeric(Intake_Date - DOB) / 365
  )

# Display observed nonnegative ages; do not replace or impute values in EDA.
# Missing and negative ages remain documented in the earlier data-quality audit.
age_eda <- age_eda %>%
  filter(!is.na(Age_Years), Age_Years >= 0)

# plot for age vs type, to check how to deal with missing value
p_age_by_type <- ggplot(age_eda, aes(x = Type, y = Age_Years, fill = Type)) +
  geom_boxplot(
    width = 0.5,             
    alpha = 0.8,             
    outlier.size = 1.2,      
    outlier.alpha = 0.3,     
    outlier.color = "grey40",
    show.legend = FALSE      
  ) +
  scale_y_continuous(breaks = seq(0, 25, by = 2)) +
  scale_fill_brewer(palette = "Set2") +
  labs(
    title = "Age Distribution Across Animal Types",
    x = "Animal Type",
    y = "Age (Years)"
  ) +
  theme_minimal(base_size = 8) +
  theme(
    plot.title = element_text(face = "bold"),
    panel.grid.minor = element_blank()
  )

p_age_dist <- ggplot(filter(age_eda, !is.na(Age_Years), Age_Years >= 0), aes(x = Age_Years)) +
  geom_histogram(binwidth = 1, fill = "#1f78b4", color = "white", boundary = 0) +
  scale_x_continuous(breaks = seq(0, 25, by = 2)) +
  labs(
    title = "Distribution of Age at Intake",
    x = "Age (Years)",
    y = "Count"
  ) +
  theme_minimal(base_size = 8) +
  theme(plot.title = element_text(face = "bold"), panel.grid.minor = element_blank())



p_age_outcome <- ggplot(filter(age_eda, !is.na(Age_Years), Age_Years >= 0), 
                        aes(x = Outcome.Group, y = Age_Years, fill = Outcome.Group)) +
  geom_boxplot(outlier.colour = "red", outlier.shape = 1, outlier.alpha = 0.4, width = 0.55, show.legend = FALSE) +
  scale_y_continuous(breaks = seq(0, 25, by = 2)) +
  scale_fill_brewer(palette = "Set2") +
  labs(
    title = "Age by Outcome",
    x = "Outcome Group",
    y = "Age (Years)"
  ) +
  theme_minimal(base_size = 8) +
  theme(
    plot.title = element_text(face = "bold"),
    panel.grid.minor = element_blank()
  )

p_age_dist + p_age_by_type + p_age_outcome + plot_layout(widths = c(0.8, 0.8, 1))

# Original EDA chunk 8: , fig.width=9, fig.height=3.5, out.width="85%", fig.align='center'
p_sex_dist <- ggplot(data_selected, aes(x = Sex, fill = Sex)) +
  geom_bar(width = 0.5, show.legend = FALSE) +
  geom_text(
    stat = "count",
    aes(label = sprintf("%.1f%%\n(%s)", 
                        after_stat(count) / sum(after_stat(count)) * 100,
                        format(after_stat(count), big.mark = ","))),
    vjust = -0.05, size = 3.2
  ) +
  scale_y_continuous(expand = expansion(mult = c(0, 0.30))) +
  scale_fill_brewer(palette = "Set2") +
  labs(
    title = "Distribution of Sex", 
    x = "Sex", 
    y = "Count") +
  theme_minimal(base_size = 12) +
  theme(
    plot.title = element_text(face = "bold", margin = margin(b = 8)),
    panel.grid.minor = element_blank()
  )

p_neuter_dist <- ggplot(data_selected, aes(x = Spayed.Neutered, fill = Spayed.Neutered)) +
  geom_bar(width = 0.5, show.legend = FALSE) +
  geom_text(
    stat = "count",
    aes(label = sprintf("%.1f%%\n(%s)", 
                        after_stat(count) / sum(after_stat(count)) * 100,
                        format(after_stat(count), big.mark = ","))),
    vjust = -0.05, size = 3.2
  ) +
  scale_y_continuous(expand = expansion(mult = c(0, 0.30))) +
  scale_fill_brewer(palette = "Pastel1") +
  labs(title = "Distribution of Spayed/Neutered Status", 
       x = "Spayed.Neutered", 
       y = "Count") +
  theme_minimal(base_size = 12) +
  theme(
    plot.title = element_text(face = "bold", margin = margin(b = 8)),
    panel.grid.minor = element_blank()
  )

p_sex_dist + p_neuter_dist + plot_layout(widths = c(1, 1))

p_sex_outcome <- ggplot(
  data_selected %>% filter(!is.na(Sex), !is.na(Outcome.Group)),
  aes(x = Sex, fill = Outcome.Group)
) +
  geom_bar(position = "fill", width = 0.6) +
  scale_y_continuous(
    labels = scales::percent_format(),
    expand = expansion(mult = c(0, 0.02))
  ) +
  scale_fill_brewer(palette = "Set2") +
  labs(
    title = "Shelter Outcome by Sex",
    x = "Sex",
    y = "Proportion",
    fill = "Outcome"
  ) +
  theme_minimal(base_size = 12) +
  theme(
    plot.title = element_text(face = "bold", margin = margin(b = 8)),
    panel.grid.minor = element_blank(),
    legend.position = "bottom"
  )


p_neuter_outcome <- ggplot(
  data_selected %>% filter(!is.na(Spayed.Neutered), !is.na(Outcome.Group)),
  aes(x = Spayed.Neutered, fill = Outcome.Group)
) +
  geom_bar(position = "fill", width = 0.6) +
  scale_y_continuous(
    labels = scales::percent_format(),
    expand = expansion(mult = c(0, 0.02))
  ) +
  scale_fill_brewer(palette = "Set2") +
  labs(
    title = "Shelter Outcome by Spayed/Neutered Status",
    x = "Spayed/Neutered",
    y = "Proportion",
    fill = "Outcome"
  ) +
  theme_minimal(base_size = 12) +
  theme(
    plot.title = element_text(face = "bold", margin = margin(b = 8)),
    panel.grid.minor = element_blank(),
    legend.position = "bottom"
  )


p_sex_outcome + p_neuter_outcome +
  plot_layout(widths = c(1, 1), guides = "collect") &
  theme(legend.position = "bottom")

# Original EDA chunk 9: name-outcome, fig.width=9, fig.height=3.5, out.width="85%", fig.align="center"
# Whitespace/case checks identify placeholders for the audit
name_outcome_pct <- data_eda %>%
  group_by(Outcome.Group, .drop = FALSE) %>%
  summarise(
    Recorded = sum(
      !is_blank(Name) &
        !(str_to_lower(trimws(as.character(Name))) %in%
            c("unknown", "*", "n/a", "na"))
    ),
    Placeholder = sum(
      !is_blank(Name) &
        str_to_lower(trimws(as.character(Name))) %in%
          c("unknown", "*", "n/a", "na")
    ),
    Blank = sum(
      !is.na(Name) & trimws(as.character(Name)) == "",
      na.rm = TRUE
    ),
    Missing = sum(is.na(Name)),
    .groups = "drop"
  ) %>%
  pivot_longer(-Outcome.Group, names_to = "Level", values_to = "n") %>%
  group_by(Level) %>%
  mutate(
    Total = sum(n),
    Prop = if_else(Total > 0, n / Total, 0)
  ) %>%
  ungroup() %>%
  filter(Total > 0)

p_name_outcome <- plot_outcome_summary(
  name_outcome_pct, "Shelter Outcome by Observed Name Recording"
)
print(p_name_outcome)


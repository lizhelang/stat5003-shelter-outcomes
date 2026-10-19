# STAT5003 Group Project – Predicting Shelter Outcomes (W01G04)

R Markdown report for the STAT5003 Assignment 2 group project (Austin Animal Center outcomes, multi-class classification).

- `STAT5003_group_project_RMarkdown_template_v29.Rmd` – main report (knit to HTML in RStudio).
- `Austin_Animal_Center_Outcomes_20260916.csv` – dataset read by the Rmd (keep it in the same folder).
- `model_comparison/` – shared CV comparison tables/figures for Section 7 (Model Evaluation & Selection).

Shared preprocessing produces `x_train`, `y_train`, `x_test`, `y_test` and `cv_data` (5 CV folds, seed 5003); each member adds their model section using these.

## Render

```r
rmarkdown::render("STAT5003_group_project_RMarkdown_template_v29.Rmd")
```

Requires tidyverse-style packages used in the Rmd (`dplyr`, `ggplot2`, `caret`, `lubridate`, `patchwork`, …).

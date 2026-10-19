# 你的 Assignment 2 SVM 部分

本文件夹基于共享仓库的 **v29（commit `2e4ca87`）**。保留了原始 v29 文件，新增 SVM 实现和一份接入 SVM 的报告副本。没有向 GitHub 推送，也没有改动其他成员的模型。

## 先看什么

- **`SVM_results.html`**：已经运行生成的 SVM 结果报告，包含基线、调参、每类表现和结果解释。直接打开即可查看。
- **`STAT5003_v29_with_SVM.Rmd`**：把 SVM 接入 v29 后的整份报告副本。SVM 是可执行代码，其余组员尚未完成的模型仍保持原样。这份文件不是五模型全部完成的最终报告。
- **`svm_model.R`**：你的独立 SVM 实现，可接在组员的 `common-cv-preprocessing` 区块之后。
- **`run_svm.R`**：独立重现入口，自动执行原始 v29 中必要的共同预处理区块，然后运行 SVM。
- **`svm_results/`**：运行产生的指标、预测、图、模型及可复现性记录。

## 在 RStudio 中重跑

先打开本文件夹中的 `run_svm.R`。在菜单 **Session → Set Working Directory → To Source File Location** 设置工作目录，然后运行：

```r
source("run_svm.R")
```

它会检查依赖，缺少时显示具体包名。可先安装：

```r
install.packages(c("e1071", "caret", "tidyr", "dplyr", "stringr", "forcats",
                   "ggplot2", "scales", "patchwork", "lubridate", "knitr", "digest"))
```

完整网格有 18 组参数 × 5 折 = 90 次拟合，需要一些时间。独立入口默认使用三个本地 R 进程，并缓存每组已完成的结果；普通报告里的 SVM 区块默认顺序运行。缓存通过数据、折分和参数指纹识别，不会把另一版数据的结果直接用于本次运行。修改模型逻辑时应同时更新 `fingerprint` 中的实现版本，或另设输出目录。

## 合入小组报告

可以把 `STAT5003_v29_with_SVM.Rmd` 中 SVM 标题到 Decision Tree 标题之前的内容，复制到小组同版本报告的对应位置。SVM 区块内包含完整代码，可以审查，不依赖某个绝对路径。

如果小组报告已经比 v29 更新，优先保留组员最新的共同预处理，只合入 SVM 小节，并核对这些输入仍然存在：

```r
cv_data[[k]]$x_train
cv_data[[k]]$y_train
cv_data[[k]]$x_valid
cv_data[[k]]$y_valid
cv_folds
x_train
y_train
```

共同预处理负责填补年龄、合并 breed 和固定因子水平；SVM 负责在各训练折上 one-hot encoding、删除常量列、标准化年龄和计算类别权重。代码没有重新随机分折。

## 交给负责整合的组员

- `baseline_vs_selected.csv`：基线和最优 SVM 的五折平均表现。与其他模型比较时优先使用这里的 `Mean_Macro_F1`，同时报告 `SD_Macro_F1`。
- `tuning_summary.csv`：全部 18 组参数的平均表现，按 macro-F1 排序。
- `cv_fold_scores.csv`：90 次单折拟合结果，包括拟合时长和 support vector 数量。
- `selected_oof_predictions.csv`：每个训练样本恰好一次的折外预测，`Row` 对应 `y_train`/`train_raw` 的行号，不是原 CSV 行号。
- `oof_per_class.csv`、`oof_confusion_matrix.csv`：每类 precision、recall、F1 和混淆矩阵。
- `weighting_tradeoff.csv`：按 macro-F1 选中的配置与最优加权配置的每类 precision/recall 对照。
- `svm_training_refit.rds`：按 CV 所选配置在完整训练集上重拟合的 SVM，包含训练得到的编码器。

**指标口径要统一：**本实现的 balanced accuracy = 五类 recall 的平均值（macro recall）。它和 `caret::confusionMatrix()` 输出的各类 `(Sensitivity + Specificity) / 2` 再平均不是同一指标。折均值与所有折外预测合并计算的 pooled 指标也可能不同。

**测试集留待小组最终选择后使用。** 目前结果均来自训练部分的交叉验证。相同五折同时用于调参和报告，最优结果存在选择乐观偏差；不要把它写成最终独立测试性能。如果全组最终选 SVM，才在既定测试集上运行一次预测和评估。例如，在整份报告的运行环境中：

```r
# 仅在小组完成五模型比较、决定最终选择 SVM 之后运行
svm_test_prediction <- svm_predict(svm_results$bundle, x_test)
svm_test_result <- svm_metrics(y_test, svm_test_prediction)
svm_test_result$summary
svm_test_result$per_class
svm_test_result$confusion
```

如果使用独立 `run_svm.R`，共同输入保存在 `svm_shared_environment` 中，应改为用该对象内的 `x_test`、`y_test`。

## 第 12 周怎么讲

建议你用约 45–60 秒介绍自己的部分，配调参图或混淆矩阵即可：

1. 为什么用 SVM：作为能学习非线性边界的模型，与线性基线及树模型比较。
2. 怎样保证公平：与其他组员共用相同样本、输入变量、五折；所有年龄填补、breed 合并、编码、标准化与权重都来自对应训练部分。
3. 怎样改进：比较 `C`、`gamma` 以及有无类别权重；按 macro-F1 选参数，而不只看 accuracy。
4. 得到了什么：使用 `SVM_results.html` 中实际生成的分数与每类 recall，说明哪些结果更容易识别、哪些仍存在混淆。

可以把结果报告中的英文实施、改进和解释段落精简后放进正文。最终 HTML 上限为整个小组报告 10 页，不能把这份独立报告全文直接叠加进去。

数据提示：仓库中的 CSV 已更新，和你本地 A2 中旧的同名文件不同。重跑时务必保持本文件夹内 v29 和 CSV 配套。GitHub 数据为 18,624 行，猫狗初筛为 17,597 行，保留每只动物最近一次入所后为 16,831 行；训练 13,467 行，保留测试 3,364 行。v29 中部分 EDA 说明仍硬编码 A1 旧数值，组内需要在最终整合时更新；SVM 结果使用实际读入数据，不依赖这些旧数字。

另附 `audit_shared_dates.R`：v29 的部分数字日期解析会忽略 AM/PM。对当前 CSV 的专项核对显示，虽然时刻解析存在差异，但**没有任何动物因此更换被保留的记录**，也不影响按日计算的年龄。因此本次保留共同 v29 的样本和折分，避免不同模型使用不同输入。若以后更新数据，应由全组统一修正 datetime 格式并重新生成分折；审计结果见 `svm_results/shared_date_audit.csv`。

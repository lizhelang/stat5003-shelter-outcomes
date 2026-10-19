# SVM presentation notes (about 60 seconds)

We used an RBF support vector machine to capture non-linear relationships between the animal characteristics and five shelter outcomes. To make comparisons fair, we used the same animals, predictors and five cross-validation folds as the rest of the group.

Within each training fold, we encoded the categorical variables and standardised age. We then compared 18 combinations of the cost parameter, kernel width and class weighting, choosing by macro-F1 so that all five outcomes contributed equally.

The selected SVM used C = 10, gamma = 4 divided by the number of encoded predictors, and no class weighting. Its mean cross-validation macro-F1 was 0.456, compared with 0.349 for the baseline.

It identified Adoption most reliably, with out-of-fold recall of 97.7%, while Euthanasia remained hardest, with recall of 4.6%. These results show why class-level evaluation matters alongside overall accuracy.

These are development results because the same folds were used for tuning. We have reserved the test set for the group's final model selection.

## 中文理解

讲解时展示 svm_tuning.png 或 svm_confusion_matrix.png。先讲模型为什么适合，再讲公平比较与防止泄漏的做法，最后用实际 macro-F1 和每类 recall 说明结果。不要宣称 SVM 优于其他四个模型，除非组员的统一比较结果支持。

图上的混淆矩阵来自训练集的折外预测；不能称为 final test confusion matrix。

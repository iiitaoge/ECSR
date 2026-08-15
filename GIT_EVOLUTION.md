# Git 状态演化协议

本项目不把 Git 提交看成“改了若干文件”，而把它看成一次原子的仓库状态演化：

\[
R_t=\operatorname{tree}(parent),\qquad
C_i=S_i(R_t),\qquad
C^*=\bigotimes_i C_i,\qquad
R_{t+1}=\Phi(R_t,C^*)
\]

- `R_t`：父提交的完整文件树，即提交前的权威仓库状态。
- `C_i`：为一个演化目标暂存的局部 Contribution；只能归入 `Components / Systems / Rules`。
- `⊗`：本提交对局部作用的组合顺序、优先级、冲突处理和不变量。
- `Φ`：把组合结果一次性落实为新文件树的原子更新。
- `R_t+1`：提交后的完整文件树。提交哈希是演化记录的身份，不代替权威状态本身。

## 分块 Rule

提交边界按“一个完整的状态转移”切分，不按目录、文件类型或开发步骤机械切分。

1. 一个提交只产生一个可命名的 `R_t -> R_t+1` 结果。
2. 完成该结果所需的 Component、System、Rule 应在同一提交形成纵向闭环；不要拆成“先加组件、再加系统、最后补规则”的三个残缺状态。
3. 两个可以独立验证、独立回退、互不依赖的演化结果，应拆成两个提交。
4. 有依赖的提交按状态因果顺序排列；后一个提交的 `X_t` 必须真实等于前一个提交产生的 `X_t+1`。
5. 每个 `X_t+1` 都必须满足仓库不变量，并留下构建、测试、基准或结构检查证据。
6. 生成物、临时文件和隐藏运行状态不进入权威仓库状态。

因此，一次“战斗掉落素材”改动可以同时涉及 Component、System、Rule 和测试；它们共同形成一个战斗状态演化提交。无关的“商店价格调整”则是另一个提交。

## 提交消息 Rule

主题固定为：

```text
evolve(<scope>): X_t[<before>] -> X_t+1[<after>]
```

`scope` 命名被演化的状态子空间，如 `dig`、`battle`、`economy`、`performance`、`git`，而不是泛化的 `feat`、`fix`、`chore`。

正文必须按演化顺序完整记录：

```text
X_t:
- 演化前的权威状态

C_i:
- C1 [Components]: 状态、模式或数据 Contribution
- C2 [Systems]: 观察或局部作用生产者 Contribution
- C3 [Rules]: 组合、次序、更新或验证 Contribution

⊗:
- 合成方式、优先级、冲突与不变量

Φ:
- 本提交唯一的原子状态更新

X_t+1:
- 演化后的权威状态

Verification:
- 能证明下一状态成立的证据
```

某一类没有代码变化时，可以明确记录它保持的不变量；不得用第四种本体分类代替它。

## 本地强制执行

仓库跟踪 `.gitmessage` 和 `.githooks/commit-msg`。当前克隆通过以下配置启用模板与 `Commit Composition Rule`：

```powershell
git config --local commit.template .gitmessage
git config --local core.hooksPath .githooks
```

Rule 会拒绝普通 Conventional Commit、缺失或乱序的演化段落、未删除的模板占位符，以及不属于 `Components / Systems / Rules` 的 Contribution 分类。

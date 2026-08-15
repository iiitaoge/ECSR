# ECSR 仓库宪法

本仓库实现的是 ECSR 状态演化协议，不是传统 ECS 工具箱。开始修改前，必须完整阅读本文件、`ARCHITECTURE.md` 与 `GIT_EVOLUTION.md`。

## 唯一本体

运行时只有三类架构对象：

- `Components`：构成某一时刻全部世界状态的信息，包括定义、关系、集合、流程、时间、观察、异步、场景与 UI。
- `Systems`：只读取同一份只读 Component 快照，进行局部运算并产生 Contribution；没有权力直接改写现实。
- `Rules`：规定 Contribution 的组合、顺序、优先级、冲突、约束、演化串联和唯一 State Update。

Entity 只是唯一数字 ID。Matter 是 Component 的机械存储底座，不是第四种业务本体。Contribution 是一次演化内由 System 提出、由 Rule 消费的瞬时作用值，也不是第四种本体。

每次原子演化严格符合：

```text
C_i     = S_i(X_t)
C*      = Rules.Compose({ C_i })
X_t+1   = Rules.Update(X_t, C*)
```

## 最高目标：因果保真

实现必须是需求因果结构的最小、完整、显式、可执行模型：

- 会影响未来的事实只存在于 Component 世界中。
- 局部因果作用只由 System 提出。
- 多个作用怎样共同成立、谁先、谁赢，只由 Rule 明示。
- State Update 是唯一权威写入口。
- 平台对象、回调、缓存、闭包、Main 和服务对象不得形成第二份业务现实。

不要创建 Manager、Service、Controller、Repository、Store、EventBus 或 Scheduler 作为第四种业务本体。它们试图表达的能力必须重新归位：保存事实是 Component，读取事实并提案是 System，组合、调度和兑现是 Rule。

## 权限边界

- `src` 一级目录只能是 `Components / Systems / Rules`。
- Matter World 写 API 只能出现在 `src/Rules/StateUpdateRule.luau`。
- System 只能获得 `ReadRule` 视图和 `emit`，不得获得 World。
- System 模块或闭包不得保存影响未来业务判断的可变状态。
- Contribution 必须由 `Components/Contribution.luau` 构造。
- 每个非 Transaction Contribution kind 必须由应用 Rule 显式注册一个纯 Composition Rule。
- phase 与 System 全序只能由 Rule 声明。
- 平台输入只形成 Observation；平台输出只机械落实由 Component 表达的结果。

## 修改协议

实现任何需求前先写出：

1. `X_t`：新增或读取哪些 Component 状态？
2. `S_i`：哪些 System 读取哪些状态，提出哪些 Contribution？
3. `⊗`：Contribution 怎样组合、排序、互斥或受约束？
4. `Φ`：总作用通过哪些通用 Effect 生成什么 `X_t+1`？

提交按一条完整纵向状态演化切分，不按目录横切。完成前运行 `tests/Verify.ps1`，证明本体封闭、写权限、确定性、冲突语义和失败原子性。


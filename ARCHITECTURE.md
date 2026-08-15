# ECSR 状态演化协议

## 定位

ECSR 是 ECS 的事务化、可合成、可追溯规范形。System 不再有权宣布现实，只能提出 Contribution；Rule 决定哪些作用能够共同成立；唯一 State Update 生成下一状态。

```text
X_t
  ──只读──▶ S_1 ──▶ C_1
  ──只读──▶ S_2 ──▶ C_2
  ──只读──▶ S_n ──▶ C_n
                         │
                         ▼
                    Rules.Compose
                         │ C*
                         ▼
                    Rules.Update
                         │
                         ▼
                       X_t+1
```

它的价值不在于增加计算能力，而在于把读取、提案、冲突与写回分成不可绕过的权限边界，使因果链可以审计、回放、测试和确定性重演。

## 框架协议 Components

`Components.define(Matter, domainNames)` 使用调用方唯一的 Matter 实例，一次生成不可变 Component 注册表。框架保留四个协议 Component：

- `StateRoot`：下一 Entity ID 与逻辑 tick。
- `Observation`：外部事实的不可变快照。
- `ObservationJournal`：有界输入因果日志。
- `EvolutionTrace`：每个 phase 的 Contribution 决议轨迹。

其余 Component 名称全部由应用声明。协议与领域 Component 使用同一个注册表，因此不存在第二个 Store 或跨 Matter 身份不一致。

## Systems

System 的完整能力面只有：

```luau
{
    name = "UniqueSystemName",
    evaluate = function(readOnlyView, emit)
        -- read M Components, emit N Contributions
    end,
}
```

`ReadRule` 提供稳定的 `get / contains / size / query`。query 结果按 Entity ID 排序。`PhaseRule` 会复制并冻结 System 的最小能力面，剥离任何附加字段。

框架内置的 `ObservationCleanupSystem` 只负责在所有解释 System 读取后消费 Observation；Observation 的业务意义仍由应用 System 决定。

## Rules

- `FrameworkRule`：唯一公共世界构造入口。
- `PhaseRule`：把多个原子演化串联成完整 frame，并冻结 System 全序。
- `CompositionRule`：把 Contribution kind 映射到纯合成 Rule；未知 kind 立即失败。
- `TransactionRule`：按 `phase → priority → orderKey → source → sequence` 稳定排序，以 claim 仲裁冲突。
- `StateUpdateRule`：先在 overlay 中预检全部 Effect，再经唯一 Matter 写入口提交。
- `EvolutionRule`：执行只读 System、组合、更新并生成 profile 与 trace。
- `NumericRule`、`PerformanceRule`：可选择的内建合成代数；框架不会隐式启用它们。
- `RandomRule`：由应用 `RngState` Component 驱动的确定性随机函数。

一个 phase 是一次完整原子演化。同 phase 的 System 读取同一份 `X_t`；确实需要读取上一步结果的 System 才放入下一 phase：

```text
X_t,0 → phase_1 → X_t,1 → phase_2 → ... → X_t,n = X_t+1
```

phase 是 Rule 对原子演化的组合，不是第四种本体。

## Contribution 与 State Update

`Contribution.transaction / numeric / performance / of` 构造标准与扩展作用。每个自定义 kind 必须显式注册纯 Rule，其输入只有同 kind Contributions，输出只能是 Transaction Contributions。

State Update 只解释通用 Effect：

- `Spawn / Despawn`
- `Insert / Remove`
- `MapSet / MapRemove`
- `CollectionAdd / CollectionRemove`

Spawn token 可在同一事务内把新 Entity ID 接入集合或目录。预检失败时，整个总 Contribution 在首次写入前被拒绝。

## 平台边界

```text
平台事件 → Observation Component → System + Components → Contribution
Component / PlatformCommand → 机械执行 → 平台对象
```

平台可以观察和落实世界，但不能保存隐藏业务状态、流程、价格、概率、胜负或权限规则。


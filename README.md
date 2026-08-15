# ECSR

ECSR 是基于 Matter 的事务化状态演化框架：Entity 只是 ID，Component 是全部世界状态，System 只产生 Contribution，Rule 统一组合并通过唯一 State Update 生成下一世界。

```text
C_i = S_i(X_t)
C* = ⊗ C_i
X_t+1 = Φ(X_t, C*)
```

## 作为 Git 依赖接入

```powershell
git submodule add https://github.com/iiitaoge/ECSR.git vendor/ECSR
git submodule update --init --recursive
```

Rojo 将 ECSR 和它锁定的 Matter 映射到 `ReplicatedStorage.Packages`：

```json
{
  "ReplicatedStorage": {
    "Packages": {
      "$className": "Folder",
      "Matter": { "$path": "vendor/ECSR/vendor/Matter/lib" },
      "ECSR": { "$path": "vendor/ECSR/src" }
    }
  }
}
```

定义一个应用世界：

```luau
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Packages = ReplicatedStorage.Packages
local Matter = require(Packages.Matter)
local ECSR = Packages.ECSR

local Components = require(ECSR.Components)
local C = Components.define(Matter, { "Clock", "Wallet" })

local Contribution = require(ECSR.Components.Contribution)
local FrameworkRule = require(ECSR.Rules.FrameworkRule)
local NumericRule = require(ECSR.Rules.NumericRule)

local world = FrameworkRule.new(Matter, C, {
    initial = {
        root = {
            C.EvolutionTrace({ entries = {}, maxEntries = 64 }),
            C.ObservationJournal({ nextSequence = 1, entries = {}, maxEntries = 128 }),
            C.Clock({ now = 0 }),
        },
        entities = {},
    },
    contributionRules = { NumericRule },
    phases = {
        { name = "simulation", systems = { MySystem }, advanceTick = true },
    },
})
```

应用自己的源码仍只分为 `Components / Systems / Rules`。应用 Rule 负责声明 System 成员、phase 顺序和启用哪些 Composition Rules；Main 只连接平台生命周期。

更新到一个明确版本：

```powershell
git -C vendor/ECSR fetch --tags
git -C vendor/ECSR checkout v0.1.0
git submodule update --init --recursive
git add vendor/ECSR
git commit
```

新克隆使用：

```powershell
git clone --recurse-submodules <your-project-url>
```

架构契约见 [ARCHITECTURE.md](ARCHITECTURE.md)，贡献代理必须先读 [AGENTS.md](AGENTS.md)。


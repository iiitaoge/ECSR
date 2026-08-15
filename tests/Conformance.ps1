$ErrorActionPreference = "Stop"

function Fail([string]$Message) {
    throw "ECSR conformance failed: $Message"
}

$Repository = Split-Path -Parent $PSScriptRoot
$Source = Join-Path $Repository "src"
$ExpectedRoots = @("Components", "Rules", "Systems")
$ActualRoots = @(Get-ChildItem -LiteralPath $Source -Directory | ForEach-Object Name | Sort-Object)
if (($ActualRoots -join "|") -ne (($ExpectedRoots | Sort-Object) -join "|")) {
    Fail "src may contain only Components, Systems and Rules; found $($ActualRoots -join ', ')"
}

$RootFiles = @(Get-ChildItem -LiteralPath $Source -File)
if ($RootFiles.Count -gt 0) {
    Fail "src root contains runtime files outside Components, Systems or Rules"
}

$LuauFiles = @(Get-ChildItem -LiteralPath $Source -Filter "*.luau" -File -Recurse)
$WritePattern = '\b(?:self\.)?(?:world|_world):(spawnAt|spawn|insert|remove|despawn|clear|replace|optimizeQueries)\s*\('
$WriteViolations = @(
    $LuauFiles |
        Where-Object { $_.FullName -notlike "*\src\Rules\StateUpdateRule.luau" } |
        Select-String -Pattern $WritePattern
)
if ($WriteViolations.Count -gt 0) {
    Fail "Matter authority writes escaped StateUpdateRule: $($WriteViolations[0].Path):$($WriteViolations[0].LineNumber)"
}

$EvolutionConstruction = @(
    $LuauFiles |
        Where-Object {
            $_.FullName -notlike "*\src\Rules\FrameworkRule.luau" -and
            $_.FullName -notlike "*\src\Rules\EvolutionRule.luau"
        } |
        Select-String -Pattern 'EvolutionRule\.new\s*\('
)
if ($EvolutionConstruction.Count -gt 0) {
    Fail "an ECSR world was constructed outside FrameworkRule"
}

$PlatformLeaks = @($LuauFiles | Select-String -Pattern 'GetService|ReplicatedStorage|ServerScriptService|StarterPlayer')
if ($PlatformLeaks.Count -gt 0) {
    Fail "framework core contains a hard-coded Roblox mount path: $($PlatformLeaks[0].Path):$($PlatformLeaks[0].LineNumber)"
}

$DomainLeaks = @($LuauFiles | Select-String -Pattern 'Dragon|Egg|Dig|Hatch|Fuse|Fight|Wallet|Player')
if ($DomainLeaks.Count -gt 0) {
    Fail "framework core contains application-domain language: $($DomainLeaks[0].Path):$($DomainLeaks[0].LineNumber)"
}

$FrameworkText = Get-Content -Raw -LiteralPath (Join-Path $Source "Rules\FrameworkRule.luau")
if ($FrameworkText -match 'require\([^\r\n]*(NumericRule|PerformanceRule)') {
    Fail "FrameworkRule silently selects an optional Composition Rule"
}

foreach ($Required in @(
    "Components\init.luau",
    "Components\Contribution.luau",
    "Systems\ObservationCleanupSystem.luau",
    "Rules\FrameworkRule.luau",
    "Rules\CompositionRule.luau",
    "Rules\PhaseRule.luau",
    "Rules\StateUpdateRule.luau"
)) {
    if (-not (Test-Path -LiteralPath (Join-Path $Source $Required))) {
        Fail "missing protocol artifact $Required"
    }
}

Write-Host "[ECSR Conformance] PASS - ontology, genericity, write authority and explicit composition are closed"


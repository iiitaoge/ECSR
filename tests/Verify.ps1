$ErrorActionPreference = "Stop"

$Repository = Split-Path -Parent $PSScriptRoot
$Build = Join-Path $Repository "build"
New-Item -ItemType Directory -Path $Build -Force | Out-Null

function Resolve-Studio {
    $Running = Get-Process RobloxStudioBeta -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($null -ne $Running -and (Test-Path -LiteralPath $Running.Path)) {
        return $Running.Path
    }

    $Roots = @(
        (Join-Path $env:LOCALAPPDATA "Roblox\Versions"),
        (Join-Path ${env:ProgramFiles(x86)} "Roblox\Versions")
    )
    foreach ($Root in $Roots) {
        if (-not (Test-Path -LiteralPath $Root)) { continue }
        $Studio = Get-ChildItem -LiteralPath $Root -Filter "RobloxStudioBeta.exe" -File -Recurse -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending |
            Select-Object -First 1
        if ($null -ne $Studio) { return $Studio.FullName }
    }
    throw "RobloxStudioBeta.exe was not found"
}

Push-Location $Repository
try {
    & (Join-Path $PSScriptRoot "Conformance.ps1")
    rojo build test.project.json --output (Join-Path $Build "verify-tests.rbxlx")

    $Studio = Resolve-Studio
    $Output = Join-Path $Build "verify-studio-tests.log"
    $Arguments = @(
        "--task", "RunScript",
        "--localPlaceFile", ('"' + (Join-Path $Build "verify-tests.rbxlx") + '"'),
        "--runScriptFile", ('"' + (Join-Path $PSScriptRoot "StudioTestRunner.luau") + '"'),
        "--outputFile", ('"' + $Output + '"'),
        "--quitAfterExecution"
    )
    $Process = Start-Process -FilePath $Studio -ArgumentList $Arguments -WindowStyle Hidden -Wait -PassThru
    if ($Process.ExitCode -ne 0) {
        throw "Roblox Studio exited with code $($Process.ExitCode)"
    }
    $Text = Get-Content -Raw -LiteralPath $Output
    if (-not $Text.Contains("[ECSRFrameworkConformance] PASS")) {
        throw "Studio verification did not produce [ECSRFrameworkConformance] PASS"
    }
    Write-Host "[ECSRFrameworkConformance] PASS"
    Write-Host "[ECSR Verify] PASS - static, Rojo build and Studio evolution protocol"
}
finally {
    Pop-Location
}


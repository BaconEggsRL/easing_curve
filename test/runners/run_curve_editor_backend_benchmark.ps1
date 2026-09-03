[CmdletBinding()]
param([string]$GodotPath = "")

$ErrorActionPreference = "Stop"
$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$runner = Join-Path $PSScriptRoot "run_godot.ps1"
$logPath = Join-Path $projectRoot "test\_temp\curve_editor_backend_benchmark.log"
$arguments = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $runner)
if (-not [string]::IsNullOrWhiteSpace($GodotPath)) {
	$arguments += @("-GodotPath", $GodotPath)
}
$arguments += @(
	"--headless", "--path", $projectRoot,
	"--script", "test/scripts/performance/curve_editor_backend_benchmark.gd",
	"--log-file", $logPath
)

& (Get-Process -Id $PID).Path @arguments
$exitCode = $LASTEXITCODE
$log = if (Test-Path -LiteralPath $logPath) { Get-Content -Raw -LiteralPath $logPath } else { "" }
if ($exitCode -ne 0 -or $log -notmatch '(?m)^BACKEND_BENCHMARK_COMPLETE\|') {
	throw "Curve Editor backend benchmark did not complete successfully. Log: $logPath"
}
Write-Host "Curve Editor backend benchmark log: $logPath"

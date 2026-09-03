[CmdletBinding()]
param(
	[string]$GodotPath = "",
	[string]$BaselinePath = ""
)

$ErrorActionPreference = "Stop"
$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$runner = Join-Path $PSScriptRoot "run_godot.ps1"
$logPath = Join-Path $projectRoot "test\_temp\native_runtime_benchmark.log"
$arguments = @(
	"-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $runner
)
if (-not [string]::IsNullOrWhiteSpace($GodotPath)) {
	$arguments += @("-GodotPath", $GodotPath)
}
$arguments += @(
	"--headless", "--path", $projectRoot,
	"--script", "test/scripts/performance/native_v2_vs_tween_benchmark.gd",
	"--log-file", $logPath
)

& (Get-Process -Id $PID).Path @arguments
$exitCode = $LASTEXITCODE
$log = if (Test-Path -LiteralPath $logPath) { Get-Content -Raw -LiteralPath $logPath } else { "" }
if ($exitCode -ne 0 -or $log -notmatch '(?m)^BENCHMARK_COMPLETE\|') {
	throw "Native runtime benchmark did not complete successfully. Log: $logPath"
}
Write-Host "Native runtime benchmark log: $logPath"
if (-not [string]::IsNullOrWhiteSpace($BaselinePath)) {
	& (Join-Path $PSScriptRoot "compare_native_benchmark.ps1") -BaselinePath $BaselinePath -CandidatePath $logPath
	if ($LASTEXITCODE -ne 0) {
		exit $LASTEXITCODE
	}
}

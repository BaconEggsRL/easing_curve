[CmdletBinding()]
param(
	[string]$GodotPath = "",
	[ValidateRange(1, 99)][int]$RunCount = 3,
	[ValidateSet("forward_plus", "mobile", "gl_compatibility")][string]$Renderer = "forward_plus",
	[switch]$Headless,
	[switch]$ValidateOnly,
	[ValidateRange(15, 600)][int]$TimeoutSeconds = 90
)

$ErrorActionPreference = "Stop"
if ($RunCount % 2 -eq 0) { throw "RunCount must be odd for median aggregation." }
$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot "../..")).Path
$source = Join-Path $projectRoot "test/scripts/performance/godot_tween_comparison"
$upstream = Join-Path $projectRoot "test/scripts/performance/godot_tween_upstream"
$runId = (Get-Date -Format "yyyyMMdd-HHmmss") + "-" + [guid]::NewGuid().ToString("N").Substring(0, 8)
$hostRoot = Join-Path $projectRoot "test/_temp/godot-tween/$runId"
$logRoot = Join-Path $hostRoot "test/_temp"
$reportRoot = Join-Path $projectRoot "_exports/_benchmarks/godot-tween/$runId"
$launcher = Join-Path $PSScriptRoot "run_godot.ps1"
$shell = (Get-Process -Id $PID).Path
$utf8 = [Text.UTF8Encoding]::new($false)
$cases = @("tween_properties", "native_properties", "legacy_properties", "tween_methods", "native_methods", "legacy_methods")
$sourceCommit = git -C $projectRoot rev-parse HEAD
$sourceStatus = @(git -C $projectRoot status --porcelain)

New-Item -ItemType Directory -Force -Path $hostRoot, $logRoot, $reportRoot, (Join-Path $hostRoot "addons") | Out-Null
Copy-Item -LiteralPath (Join-Path $projectRoot "addons/easing_curve") -Destination (Join-Path $hostRoot "addons") -Recurse -Force
foreach ($file in @("benchmark.gd", "tween.gd", "icon.png", "LICENSE.md")) {
	Copy-Item -LiteralPath (Join-Path $upstream $file) -Destination (Join-Path $hostRoot $file)
}
foreach ($file in @("curve_cases.gd", "runner.gd")) {
	Copy-Item -LiteralPath (Join-Path $source $file) -Destination (Join-Path $hostRoot $file)
}
[IO.File]::WriteAllText((Join-Path $logRoot ".gdignore"), "", $utf8)
$config = @'
config_version=5
[application]
config/name="Godot Tween / Easing Curve comparison"
config/features=PackedStringArray("4.7")
config/icon="res://icon.png"
[display]
window/size/viewport_width=1920
window/size/viewport_height=1080
window/stretch/mode="viewport"
window/vsync/vsync_mode=0
[rendering]
renderer/rendering_method="__RENDERER__"
'@
[IO.File]::WriteAllText((Join-Path $hostRoot "project.godot"), $config.Replace("__RENDERER__", $Renderer), $utf8)

function Invoke-BenchmarkProcess {
	param([string]$Label, [string[]]$EngineArguments)
	$engineLog = Join-Path $logRoot "$Label.engine.log"
	$stdout = Join-Path $logRoot "$Label.stdout.log"
	$stderr = Join-Path $logRoot "$Label.stderr.log"
	$arguments = @("--path", $hostRoot, "--log-file", $engineLog) + $EngineArguments
	# Pass the literal -- through the wrapper's array parameter, not -File parsing.
	$literal = { param([string]$Value) "'" + $Value.Replace("'", "''") + "'" }
	$command = "& " + (& $literal $launcher) + " -AppDataDirectory " + (& $literal (Join-Path $logRoot "appdata"))
	if ($GodotPath) { $command += " -GodotPath " + (& $literal $GodotPath) }
	$command += " -GodotArgs @(" + (($arguments | ForEach-Object { & $literal $_ }) -join ",") + "); exit `$LASTEXITCODE"
	$encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($command))
	$process = Start-Process -FilePath $shell -ArgumentList @("-NoProfile", "-OutputFormat", "Text", "-EncodedCommand", $encoded) -WindowStyle Hidden -PassThru -RedirectStandardOutput $stdout -RedirectStandardError $stderr
	if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
		$process.Kill($true)
		throw "$Label timed out; retained logs at $logRoot"
	}
	$process.WaitForExit()
	$output = (Get-Content -LiteralPath $stdout -Raw) + (Get-Content -LiteralPath $stderr -Raw)
	if (Test-Path -LiteralPath $engineLog) { $output += Get-Content -LiteralPath $engineLog -Raw }
	if ($process.ExitCode -ne 0) { throw "$Label exited $($process.ExitCode); retained logs at $logRoot" }
	$unexpected = @($output -split "`r?`n" | Where-Object {
		$_ -match '^(SCRIPT ERROR:|ERROR:|WARNING:)' -and
		$_ -notmatch '^ERROR: Failed to read the root certificate store\.$'
	})
	if ($unexpected.Count) { throw "$Label diagnostics: $($unexpected -join '; '); logs: $logRoot" }
	return $output
}

function Get-Median {
	param([double[]]$Values)
	$sorted = @($Values | Sort-Object)
	return $sorted[[int][Math]::Floor($sorted.Count / 2)]
}

Write-Host "Isolated project: $hostRoot"
Write-Host "Reports: $reportRoot"
$null = Invoke-BenchmarkProcess -Label "import" -EngineArguments @("--editor", "--headless", "--import")
$validation = Invoke-BenchmarkProcess -Label "validation" -EngineArguments @("--headless", "--script", "res://runner.gd", "--", "--validate-only")
if ($validation -notmatch '(?m)^PASS: all six Tween comparison workloads') { throw "Missing semantic validation PASS marker: $logRoot" }
Write-Host "PASS: six workloads validated against deterministic motion and upstream counts."
if ($ValidateOnly) {
	Copy-Item -Path (Join-Path $logRoot "*.log") -Destination $reportRoot
	Write-Host "Validation only; no performance comparison was measured."
	exit 0
}

$trials = @()
for ($run = 1; $run -le $RunCount; $run++) {
	for ($offset = 0; $offset -lt $cases.Count; $offset++) {
		$case = $cases[($offset + $run - 1) % $cases.Count]
		$label = "run-$run-$case"
		$jsonPath = Join-Path $reportRoot "$label.json"
		$engineArguments = @("--disable-vsync", "--script", "res://runner.gd")
		if ($Headless) { $engineArguments = @("--headless") + $engineArguments }
		$engineArguments += @("--", "--case=$case", "--save-json=$jsonPath")
		Write-Host "Run $run/$RunCount : $case (5 seconds)"
		$output = Invoke-BenchmarkProcess -Label $label -EngineArguments $engineArguments
		if ($output -notmatch "BENCHMARK_COMPLETE\|$case\|" -or -not (Test-Path -LiteralPath $jsonPath)) { throw "Incomplete case: $label" }
		$result = Get-Content -LiteralPath $jsonPath -Raw | ConvertFrom-Json
		if ($result.comparison.case -ne $case -or $result.comparison.frames_captured -lt 1 -or $result.comparison.elapsed_ms -lt 5000) { throw "Invalid measurements: $label" }
		if ($result.comparison.headless -ne [bool]$Headless) { throw "Unexpected display mode: $label" }
		if (-not $Headless -and ($result.comparison.renderer -ne $Renderer -or $result.benchmarks[0].results.render_cpu -le 0)) { throw "Missing render timing or unexpected renderer: $label" }
		$trials += [pscustomobject]@{ run = $run; case = $case; data = $result }
	}
}

$rows = @()
foreach ($case in $cases) {
	$measurements = @($trials | Where-Object { $_.case -eq $case })
	if ($measurements.Count -ne $RunCount) { throw "Missing trials for $case" }
	$setup = @($measurements | ForEach-Object { [double]$_.data.benchmarks[0].results.time })
	$idle = @($measurements | ForEach-Object { [double]$_.data.comparison.idle_max_ms })
	$render = @($measurements | ForEach-Object { [double]$_.data.benchmarks[0].results.render_cpu })
	$rows += [pscustomobject][ordered]@{
		case = $case
		setup_ms = Get-Median $setup
		setup_min_ms = ($setup | Measure-Object -Minimum).Minimum
		setup_max_ms = ($setup | Measure-Object -Maximum).Maximum
		render_cpu_ms = if ($Headless) { $null } else { Get-Median $render }
		idle_max_ms = Get-Median $idle
		setup_vs_tween = 0.0
		render_cpu_vs_tween = $null
		idle_vs_tween = 0.0
	}
}
foreach ($row in $rows) {
	$baselineCase = "tween_" + $row.case.Split('_')[1]
	$baseline = $rows | Where-Object { $_.case -eq $baselineCase }
	if ($baseline.setup_ms -gt 0) { $row.setup_vs_tween = $row.setup_ms / $baseline.setup_ms }
	if ($baseline.idle_max_ms -gt 0) { $row.idle_vs_tween = $row.idle_max_ms / $baseline.idle_max_ms }
	if (-not $Headless -and $baseline.render_cpu_ms -gt 0) { $row.render_cpu_vs_tween = $row.render_cpu_ms / $baseline.render_cpu_ms }
}
$summary = [ordered]@{
	upstream_commit = "ef3a94f131552c9c5aa040c985185de705068eda"
	source_commit = $sourceCommit
	source_dirty = $sourceStatus.Count -gt 0
	source_status = $sourceStatus
	native_dll_sha256 = (Get-FileHash -Algorithm SHA256 (Join-Path $hostRoot "addons/easing_curve/bin/libeasing_curve_native.windows.template_release.x86_64.dll")).Hash
	renderer = $Renderer
	headless = [bool]$Headless
	runs = $RunCount
	measurement = "Median of independent five-second trials; ratios divide by local Tween. Idle is supplemental, not an upstream Tween chart metric."
	rows = $rows
	trials = $trials
}
$summary | ConvertTo-Json -Depth 16 | Set-Content -LiteralPath (Join-Path $reportRoot "summary.json") -Encoding utf8
$rows | Export-Csv -LiteralPath (Join-Path $reportRoot "summary.csv") -NoTypeInformation
$report = @(
	"# Tween / Easing Curve benchmark comparison",
	"",
	"Engine: $($trials[0].data.engine.version). Renderer: $Renderer. Headless: $([bool]$Headless).",
	"CPU: $($trials[0].data.system.cpu_name). GPU: $($trials[0].data.system.gpu).",
	"Source: $sourceCommit (dirty: $($summary.source_dirty)). Upstream: $($summary.upstream_commit).",
	"",
	"Medians of $RunCount independent five-second trials per case. Ratios divide by the matching local Tween baseline; lower is better.",
	"",
	"| Case | Setup ms | Setup / Tween | Render CPU ms | Render / Tween |",
	"| --- | ---: | ---: | ---: | ---: |"
)
foreach ($row in $rows) {
	$renderText = if ($Headless) { "unavailable" } else { "{0:F6}" -f $row.render_cpu_ms }
	$renderRatio = if ($Headless) { "unavailable" } else { "{0:F3}" -f $row.render_cpu_vs_tween }
	$report += "| {0} | {1:F6} | {2:F3} | {3} | {4} |" -f $row.case, $row.setup_ms, $row.setup_vs_tween, $renderText, $renderRatio
}
$report += @(
	"",
	"All cases use Linear easing. The method variants include the same GDScript sampling adapter. Render CPU measures drawing work, so similar values do not establish equal easing cost.",
	"",
	"CSV/JSON include setup min/max, every raw trial, and supplemental idle monitor maxima. Idle includes general engine processing and startup; it is not a pure sampler score or an upstream Tween chart metric.",
	"",
	"Compare absolute dashboard timings only with equivalent hardware, engine build and renderer. These are local measurements, not release pass/fail thresholds."
)
$report | Set-Content -LiteralPath (Join-Path $reportRoot "summary.md") -Encoding utf8
Copy-Item -Path (Join-Path $logRoot "*.log") -Destination $reportRoot
$rows | Format-Table case, setup_ms, render_cpu_ms, idle_max_ms, setup_vs_tween, render_cpu_vs_tween, idle_vs_tween -AutoSize
Write-Host "PASS: all $($cases.Count * $RunCount) measurements complete. Results: $reportRoot"
if ($Headless) { Write-Warning "Headless results omit render CPU and are not comparable to the rendered dashboard." }

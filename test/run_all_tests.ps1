[CmdletBinding()]
param(
	[string]$Godot = "godot",
	[int]$TimeoutSeconds = 300
)

$ErrorActionPreference = "Stop"
$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$godotCommand = Get-Command $Godot -ErrorAction Stop
$godotPath = $godotCommand.Source

$suites = @(
	@{ Name = "css_linear_test.gd"; Editor = $false },
	@{ Name = "easing_curve_editor_rmb_delete_test.gd"; Editor = $false },
	@{ Name = "easing_curve_manual_reorder_test.gd"; Editor = $false },
	@{ Name = "easing_curve_transform_test.gd"; Editor = $false },
	@{ Name = "easing_curve_v105_regression_test.gd"; Editor = $false },
	@{ Name = "runtime_curve_updates_test.gd"; Editor = $false },
	@{ Name = "tween_equivalence_test.gd"; Editor = $false },
	@{ Name = "easing_curve_control_editability_test.gd"; Editor = $true },
	@{ Name = "easing_curve_editor_position_x_drag_test.gd"; Editor = $true },
	@{ Name = "easing_curve_linear_control_alias_test.gd"; Editor = $true },
	@{ Name = "easing_curve_points_list_add_editor_test.gd"; Editor = $true },
	@{ Name = "easing_curve_points_list_reorder_editor_test.gd"; Editor = $true },
	@{ Name = "editor_undo_redo_test.gd"; Editor = $true }
)

$results = @()
foreach ($suite in $suites) {
	$mode = if ($suite.Editor) { "editor-host" } else { "headless" }
	Write-Host "`n=== $($suite.Name) [$mode] ==="
	$arguments = @()
	if ($suite.Editor) {
		$arguments += "--editor"
	}
	$arguments += @(
		"--headless",
		"--path", $projectRoot,
		"--script", "res://test/$($suite.Name)"
	)
	$quotedArguments = $arguments | ForEach-Object {
		'"' + $_.Replace('"', '\"') + '"'
	}
	$stdoutPath = Join-Path ([IO.Path]::GetTempPath()) ("easing-curve-{0}.stdout" -f [guid]::NewGuid())
	$stderrPath = Join-Path ([IO.Path]::GetTempPath()) ("easing-curve-{0}.stderr" -f [guid]::NewGuid())
	$timedOut = $false
	$exitCode = -1
	try {
		$process = Start-Process `
			-FilePath $godotPath `
			-ArgumentList $quotedArguments `
			-RedirectStandardOutput $stdoutPath `
			-RedirectStandardError $stderrPath `
			-WindowStyle Hidden `
			-PassThru
		if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
			$timedOut = $true
			Stop-Process -Id $process.Id -Force
			$process.WaitForExit()
		} else {
			$exitCode = $process.ExitCode
		}
		$stdout = if (Test-Path -LiteralPath $stdoutPath) { Get-Content -Raw -LiteralPath $stdoutPath } else { "" }
		$stderr = if (Test-Path -LiteralPath $stderrPath) { Get-Content -Raw -LiteralPath $stderrPath } else { "" }
		$output = "$stdout`n$stderr"
		if ($stdout) { Write-Host $stdout.TrimEnd() }
		if ($stderr) { Write-Host $stderr.TrimEnd() }
		$hasPass = $output -match '(?m)^PASS:'
		$hasScriptError = $output -match 'SCRIPT ERROR:'
		$passed = -not $timedOut -and $exitCode -eq 0 -and $hasPass -and -not $hasScriptError
		$results += [pscustomobject]@{
			Suite = $suite.Name
			Mode = $mode
			ExitCode = $exitCode
			TimedOut = $timedOut
			PassMarker = $hasPass
			ScriptError = $hasScriptError
			Passed = $passed
		}
	} finally {
		Remove-Item -LiteralPath $stdoutPath -Force -ErrorAction SilentlyContinue
		Remove-Item -LiteralPath $stderrPath -Force -ErrorAction SilentlyContinue
	}
}

Write-Host "`n=== Test summary ==="
$results | Format-Table -AutoSize
$failed = @($results | Where-Object { -not $_.Passed })
if ($failed.Count -gt 0) {
	Write-Host "$($failed.Count) of $($results.Count) suites failed." -ForegroundColor Red
	exit 1
}

Write-Host "All $($results.Count) suites passed."
exit 0

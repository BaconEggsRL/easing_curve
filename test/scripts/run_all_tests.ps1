[CmdletBinding()]
param(
	[string]$GodotPath = ""
)

$ErrorActionPreference = "Stop"
$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$godotLauncher = Join-Path $PSScriptRoot "run_godot.ps1"
$suiteTimeoutSeconds = 60
$killWaitMilliseconds = 5000
$powerShellExecutable = (Get-Process -Id $PID).Path

$suites = @(
	@{ Name = "css_linear_test.gd"; Editor = $false },
	@{ Name = "easing_curve_editor_rmb_delete_test.gd"; Editor = $false },
	@{ Name = "easing_curve_manual_reorder_test.gd"; Editor = $false },
	@{ Name = "easing_curve_transform_test.gd"; Editor = $false },
	@{ Name = "easing_curve_v105_regression_test.gd"; Editor = $false },
	@{ Name = "runtime_curve_updates_test.gd"; Editor = $false },
	@{ Name = "serialization_transition_contract_test.gd"; Editor = $false },
	@{ Name = "tween_equivalence_test.gd"; Editor = $false },
	@{ Name = "easing_curve_control_editability_test.gd"; Editor = $true },
	@{ Name = "easing_curve_editor_position_x_drag_test.gd"; Editor = $true },
	@{ Name = "easing_curve_linear_control_alias_test.gd"; Editor = $true },
	@{ Name = "easing_curve_points_list_add_editor_test.gd"; Editor = $true },
	@{ Name = "easing_curve_points_list_reorder_editor_test.gd"; Editor = $true },
	@{ Name = "easing_curve_point_state_characterization_test.gd"; Editor = $true },
	@{ Name = "easing_curve_selection_refresh_characterization_test.gd"; Editor = $true },
	@{ Name = "easing_curve_editor_gesture_characterization_test.gd"; Editor = $true },
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
	$stdoutPath = Join-Path ([IO.Path]::GetTempPath()) ("easing-curve-{0}.stdout" -f [guid]::NewGuid())
	$stderrPath = Join-Path ([IO.Path]::GetTempPath()) ("easing-curve-{0}.stderr" -f [guid]::NewGuid())
	$exitCodePath = Join-Path ([IO.Path]::GetTempPath()) ("easing-curve-{0}.exitcode" -f [guid]::NewGuid())
	$suiteExitCode = -1
	$timedOut = $false
	try {
		$suiteTimeout = if ($suite.ContainsKey("TimeoutSeconds")) { $suite.TimeoutSeconds } else { $suiteTimeoutSeconds }
		$launcherArguments = @(
			"-NoProfile",
			"-ExecutionPolicy", "Bypass",
			"-File", $godotLauncher,
			"-ExitCodeFile", $exitCodePath
		)
		if (-not [string]::IsNullOrWhiteSpace($GodotPath)) {
			$launcherArguments += @("-GodotPath", $GodotPath)
		}
		$launcherArguments += $arguments
		$startProcessArguments = @{
			FilePath = $powerShellExecutable
			ArgumentList = $launcherArguments
			WorkingDirectory = $projectRoot
			RedirectStandardOutput = $stdoutPath
			RedirectStandardError = $stderrPath
			WindowStyle = "Hidden"
			PassThru = $true
		}
		$launcherProcess = Start-Process @startProcessArguments
		$completed = $launcherProcess.WaitForExit([int]($suiteTimeout * 1000))
		if ($completed) {
			# Process is already exited; this final wait synchronizes redirected streams.
			$launcherProcess.WaitForExit()
			if (Test-Path -LiteralPath $exitCodePath) {
				$exitCodeText = (Get-Content -Raw -LiteralPath $exitCodePath).Trim()
				if ($exitCodeText -match '^-?\d+$') {
					$suiteExitCode = [int]$exitCodeText
				} else {
					Write-Warning "Invalid exit code from $($suite.Name): '$exitCodeText'"
				}
			} else {
				Write-Warning "No exit code was reported for $($suite.Name)."
			}
		} else {
			$timedOut = $true
			Write-Host "Timed out after $suiteTimeout seconds; terminating process tree rooted at PID $($launcherProcess.Id)." -ForegroundColor Yellow
			& taskkill.exe /PID $launcherProcess.Id /T /F 2>$null | Out-Null
			if (-not $launcherProcess.WaitForExit($killWaitMilliseconds)) {
				Write-Warning (
					"Process tree rooted at PID $($launcherProcess.Id) " +
					"did not exit after taskkill."
				)
			}
		}
		$stdout = if (Test-Path -LiteralPath $stdoutPath) { Get-Content -Raw -LiteralPath $stdoutPath } else { "" }
		$stderr = if (Test-Path -LiteralPath $stderrPath) { Get-Content -Raw -LiteralPath $stderrPath } else { "" }
		$output = "$stdout`n$stderr"
		if ($stdout) { Write-Host $stdout.TrimEnd() }
		if ($stderr) { Write-Host $stderr.TrimEnd() }
		$hasPass = $output -match '(?m)^PASS:'
		$hasScriptError = $output -match 'SCRIPT ERROR:'
		$passed = -not $timedOut -and $suiteExitCode -eq 0 -and $hasPass -and -not $hasScriptError
		$results += [pscustomobject]@{
			Suite = $suite.Name
			Mode = $mode
			ExitCode = $suiteExitCode
			TimedOut = $timedOut
			PassMarker = $hasPass
			ScriptError = $hasScriptError
			Passed = $passed
		}
	} finally {
		Remove-Item -LiteralPath $stdoutPath -Force -ErrorAction SilentlyContinue
		Remove-Item -LiteralPath $stderrPath -Force -ErrorAction SilentlyContinue
		Remove-Item -LiteralPath $exitCodePath -Force -ErrorAction SilentlyContinue
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

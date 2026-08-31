[CmdletBinding()]
param(
	[Parameter()]
	[string]$GodotPath = "",
	[Parameter(Position = 0, ValueFromRemainingArguments = $true)]
	[string[]]$CommandArguments
)

$ErrorActionPreference = "Stop"

function Resolve-ProjectRoot {
	$candidate = (Resolve-Path $PSScriptRoot).Path
	while ($true) {
		if (Test-Path -LiteralPath (Join-Path $candidate "project.godot") -PathType Leaf) {
			return $candidate
		}
		$parent = Split-Path -Parent $candidate
		if ([string]::IsNullOrWhiteSpace($parent) -or $parent -eq $candidate) {
			throw "Could not locate project.godot above runner directory: $PSScriptRoot"
		}
		$candidate = $parent
	}
}

$projectRoot = Resolve-ProjectRoot
$godotLauncher = Join-Path $PSScriptRoot "run_godot.ps1"
$suiteTimeoutSeconds = 60
$killWaitMilliseconds = 5000
$powerShellExecutable = (Get-Process -Id $PID).Path
$testTempDirectory = Join-Path $projectRoot "test\_temp"
$runnerTempDirectory = Join-Path $testTempDirectory "runner"

function Remove-DirectoryIfEmpty {
	param([string]$Path)

	if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path -PathType Container)) {
		return
	}

	if (-not (Get-ChildItem -LiteralPath $Path -Force | Select-Object -First 1)) {
		Remove-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
	}
}

function Clear-TestTempArtifacts {
	# Keep test/_temp and its tracked .gdignore so Godot does not scan transient
	# test output. Everything else in this directory is runner-owned output.
	New-Item -ItemType Directory -Force -Path $testTempDirectory | Out-Null
	Get-ChildItem -LiteralPath $testTempDirectory -Force |
		Where-Object { $_.Name -ne ".gdignore" } |
		ForEach-Object {
			Remove-Item -LiteralPath $_.FullName -Recurse -Force
		}
}

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
	@{ Name = "easing_curve_preview_generator_test.gd"; Editor = $true },
	@{ Name = "easing_curve_editor_position_x_drag_test.gd"; Editor = $true },
	@{ Name = "easing_curve_linear_control_alias_test.gd"; Editor = $true },
	@{ Name = "easing_curve_points_list_add_editor_test.gd"; Editor = $true },
	@{ Name = "easing_curve_points_list_reorder_editor_test.gd"; Editor = $true },
	@{ Name = "easing_curve_point_state_characterization_test.gd"; Editor = $true },
	@{ Name = "easing_curve_selection_refresh_characterization_test.gd"; Editor = $true },
	@{ Name = "easing_curve_editor_gesture_characterization_test.gd"; Editor = $true },
	@{ Name = "editor_undo_redo_test.gd"; Editor = $true }
)

function Show-Help {
	Write-Host "Usage: .\\run_all_tests.ps1 [--help | --list | --run | --cleanup] [-GodotPath <path>]"
	Write-Host ""
	Write-Host "Options:"
	Write-Host "  --help  Show this help menu."
	Write-Host "  --list  List the individual unit tests run by this script."
	Write-Host "  --run   Run all listed unit tests."
	Write-Host "  --cleanup  Remove successful-run artifacts from test/_temp, preserving .gdignore."
	Write-Host ""
	Write-Host "-GodotPath may be supplied with --run to select a Godot executable."
}

if ($CommandArguments.Count -ne 1) {
	Show-Help
	if ($CommandArguments.Count -gt 1) {
		Write-Error "Specify exactly one command: --help, --list, --run, or --cleanup."
	}
	exit $(if ($CommandArguments.Count -eq 0) { 0 } else { 1 })
}

switch ($CommandArguments[0]) {
	"--help" {
		Show-Help
		exit 0
	}
	"--list" {
		foreach ($suite in $suites) {
			Write-Output $suite.Name
		}
		exit 0
	}
	"--cleanup" {
		Clear-TestTempArtifacts
		Write-Host "Cleaned test/_temp artifacts; preserved .gdignore."
		exit 0
	}
	"--run" { }
	default {
		Show-Help
		Write-Error "Unknown command: $($CommandArguments[0])"
		exit 1
	}
}

New-Item -ItemType Directory -Force -Path $runnerTempDirectory | Out-Null

$results = @()
foreach ($suite in $suites) {
	$mode = if ($suite.Editor) { "editor-host" } else { "headless" }
	Write-Host "`n=== $($suite.Name) [$mode] ==="

	$suiteBaseName = [IO.Path]::GetFileNameWithoutExtension($suite.Name)
	$suiteTempDirectory = Join-Path $runnerTempDirectory (
		"{0}-{1}" -f $suiteBaseName, [guid]::NewGuid().ToString("N")
	)
	New-Item -ItemType Directory -Force -Path $suiteTempDirectory | Out-Null
	$stdoutPath = Join-Path $suiteTempDirectory "stdout.txt"
	$stderrPath = Join-Path $suiteTempDirectory "stderr.txt"
	$exitCodePath = Join-Path $suiteTempDirectory "exitcode.txt"
	$godotLogPath = Join-Path $suiteTempDirectory "godot.log"
	$suiteAppDataPath = Join-Path $suiteTempDirectory "appdata"

	$arguments = @()
	if ($suite.Editor) {
		$arguments += "--editor"
	}
	$arguments += @(
		"--headless",
		"--path", $projectRoot,
		"--script", "res://test/scripts/$($suite.Name)",
		"--log-file", $godotLogPath
	)

	$suiteExitCode = -1
	$timedOut = $false
	$passed = $false
	try {
		$suiteTimeout = if ($suite.ContainsKey("TimeoutSeconds")) { $suite.TimeoutSeconds } else { $suiteTimeoutSeconds }
		$launcherArguments = @(
			"-NoProfile",
			"-ExecutionPolicy", "Bypass",
			"-File", $godotLauncher,
			"-ExitCodeFile", $exitCodePath,
			"-AppDataDirectory", $suiteAppDataPath
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
		if ($passed) {
			Remove-Item -LiteralPath $suiteTempDirectory -Recurse -Force -ErrorAction SilentlyContinue
		} else {
			Write-Host "Preserved temp artifacts: $suiteTempDirectory" -ForegroundColor Yellow
		}
	}
}

Remove-DirectoryIfEmpty $runnerTempDirectory

Write-Host "`n=== Test summary ==="
$results | Format-Table -AutoSize
$failed = @($results | Where-Object { -not $_.Passed })
if ($failed.Count -gt 0) {
	Write-Host "$($failed.Count) of $($results.Count) suites failed." -ForegroundColor Red
	exit 1
}

# Keep test/_temp itself: its tracked .gdignore prevents Godot from scanning
# transient test artifacts created beneath this directory.
Write-Host "All $($results.Count) suites passed."
exit 0

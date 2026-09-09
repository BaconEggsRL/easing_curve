[CmdletBinding()]
param(
	[string]$ExitCodeFile = "",
	[string]$GodotPath = "",
	[string]$PinnedEditorPath = "",
	[string]$PinnedEditorSha256 = "",
	[ValidateRange(1, 86400)][int]$TimeoutSeconds = 900,
	[string]$AppDataDirectory = "",

	[Parameter(Position = 0, ValueFromRemainingArguments = $true)]
	[string[]]$GodotArgs
)

$ErrorActionPreference = "Stop"
. "$PSScriptRoot/godot_process_contract.ps1"

Add-Type @"
using System;
using System.Runtime.InteropServices;

public static class ErrorMode {
	[DllImport("kernel32.dll")]
	public static extern uint SetErrorMode(uint uMode);
}
"@

# SEM_FAILCRITICALERRORS | SEM_NOGPFAULTERRORBOX
[ErrorMode]::SetErrorMode(0x0001 -bor 0x0002) | Out-Null

function Remove-DirectoryIfEmpty {
	param([string]$Path)

	if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path -PathType Container)) {
		return
	}

	if (-not (Get-ChildItem -LiteralPath $Path -Force | Select-Object -First 1)) {
		Remove-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
	}
}

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
for ($index = 0; $index -lt $GodotArgs.Count; $index += 1) {
	$argument = $GodotArgs[$index]
	$projectPath = ""
	if ($argument -ieq "--path" -and $index + 1 -lt $GodotArgs.Count) {
		$projectPath = $GodotArgs[$index + 1]
	} elseif ($argument -ilike "--path=*") {
		$projectPath = $argument.Substring("--path=".Length)
	}
	if ([string]::IsNullOrEmpty($projectPath)) {
		continue
	}

	$resolvedProjectPath = Resolve-Path -LiteralPath $projectPath -ErrorAction SilentlyContinue
	if ($resolvedProjectPath -and (Test-Path -LiteralPath $resolvedProjectPath.Path -PathType Container)) {
		$projectRoot = $resolvedProjectPath.Path
	}
	break
}

$fallbackGodotPath = "C:\Godot\4.7\engine\Godot_v4.7.1-stable_win64.exe\Godot_v4.7.1-stable_win64_console.exe"
$godotPathSource = "explicit -GodotPath"
$editorRole = Test-GodotEditorInvocation $GodotArgs
if (-not $PinnedEditorPath) { $PinnedEditorPath = $env:EASING_CURVE_EDITOR_GODOT_PATH }
if (-not $PinnedEditorSha256) { $PinnedEditorSha256 = $env:EASING_CURVE_EDITOR_GODOT_SHA256 }
if ($editorRole -and $PinnedEditorSha256 -and -not $PinnedEditorPath) { throw 'A pinned editor hash was configured without an editor path. No fallback is allowed.' }
$pinnedEditor = $editorRole -and -not [string]::IsNullOrWhiteSpace($PinnedEditorPath)
if ($pinnedEditor) {
	$GodotPath = $PinnedEditorPath
	$godotPathSource = 'pinned editor invocation'
	Assert-GodotExecutableHash -Path $GodotPath -ExpectedHash $PinnedEditorSha256 | Out-Null
}
if ([string]::IsNullOrWhiteSpace($GodotPath)) {
	$GodotPath = $env:EASING_CURVE_GODOT_PATH
	$godotPathSource = "EASING_CURVE_GODOT_PATH"
}
if ([string]::IsNullOrWhiteSpace($GodotPath)) {
	$GodotPath = $fallbackGodotPath
	$godotPathSource = "local fallback"
}

if (-not (Test-Path -LiteralPath $GodotPath -PathType Leaf)) {
	throw (
		"Godot executable was not found: $GodotPath. Supply -GodotPath '<path-to-godot>' " +
		"or set EASING_CURVE_GODOT_PATH."
	)
}

$Godot = (Resolve-Path -LiteralPath $GodotPath -ErrorAction Stop).Path
$godotFileName = [IO.Path]::GetFileNameWithoutExtension($Godot)
if (-not $pinnedEditor -and -not $godotFileName.EndsWith("_console", [StringComparison]::OrdinalIgnoreCase)) {
	$consoleGodot = Join-Path ([IO.Path]::GetDirectoryName($Godot)) ($godotFileName + "_console.exe")
	if (Test-Path -LiteralPath $consoleGodot -PathType Leaf) {
		$Godot = (Resolve-Path -LiteralPath $consoleGodot -ErrorAction Stop).Path
		$godotPathSource += ", console companion"
	}
}

$testTempDirectory = Join-Path $projectRoot "test\_temp"
$testAppDataRoot = Join-Path $testTempDirectory "appdata"
$ownsAppDataDirectory = [string]::IsNullOrWhiteSpace($AppDataDirectory)
if ($ownsAppDataDirectory) {
	$AppDataDirectory = Join-Path $testAppDataRoot (
		"godot-test-{0}-{1}" -f $PID, [guid]::NewGuid().ToString("N")
	)
}
New-Item -ItemType Directory -Force -Path $AppDataDirectory | Out-Null

$hasLogFile = $false
foreach ($argument in $GodotArgs) {
	if ($argument -ieq "--log-file" -or $argument -ilike "--log-file=*") {
		$hasLogFile = $true
		break
	}
}

$launchArguments = @($GodotArgs)
$testLogDirectory = ""
$testLogPath = ""
if (-not $hasLogFile) {
	$testLogDirectory = Join-Path $testTempDirectory "logs"
	New-Item -ItemType Directory -Force -Path $testLogDirectory | Out-Null
	$testLogPath = Join-Path $testLogDirectory (
		"godot-test-{0}-{1}.log" -f $PID, [guid]::NewGuid().ToString("N")
	)
	$launchArguments = @("--log-file", $testLogPath) + $launchArguments
	Write-Verbose "Godot test log: $testLogPath"
} else {
	Write-Verbose "Godot test log: caller-supplied --log-file"
}

$previousAppData = $env:APPDATA
$previousLocalAppData = $env:LOCALAPPDATA
$exitCode = -1
try {
	# Keep Godot user:// writes inside the repository so sandboxed test runs
	# do not depend on write access to the real Windows AppData folders.
	$env:APPDATA = $AppDataDirectory
	$env:LOCALAPPDATA = Join-Path $AppDataDirectory "Local"
	New-Item -ItemType Directory -Force -Path $env:LOCALAPPDATA | Out-Null

	Write-Host "Godot executable ($godotPathSource): $Godot"
	Write-Host "Godot invocation role: $(if ($editorRole) { 'editor' } else { 'runtime' }); SHA256: $((Get-FileHash -LiteralPath $Godot).Hash)"
	$godotVersion = (& $Godot --version --log-file (Join-Path $AppDataDirectory 'version.log') | Out-String).Trim()
	if ($LASTEXITCODE -ne 0) {
		throw "Could not query Godot version from: $Godot"
	}
	Write-Host "Godot version: $godotVersion"

	$startInfo = [Diagnostics.ProcessStartInfo]::new()
	$startInfo.FileName = $Godot
	$startInfo.UseShellExecute = $false
	$startInfo.CreateNoWindow = $true
	$startInfo.RedirectStandardOutput = $true
	$startInfo.RedirectStandardError = $true
	foreach ($argument in $launchArguments) { $startInfo.ArgumentList.Add($argument) }
	$process = [Diagnostics.Process]::Start($startInfo)
	$stdoutTask = $process.StandardOutput.ReadToEndAsync()
	$stderrTask = $process.StandardError.ReadToEndAsync()
	$timedOut = -not $process.WaitForExit($TimeoutSeconds * 1000)
	if ($timedOut) { $process.Kill($true); $process.WaitForExit() }
	$stdout = $stdoutTask.GetAwaiter().GetResult()
	$stderr = $stderrTask.GetAwaiter().GetResult()
	$exitCode = if ($timedOut) { 1 } else { $process.ExitCode }
	$recordPath = Join-Path $AppDataDirectory 'process'
	$stdout | Set-Content -LiteralPath "$recordPath.stdout.txt"
	$stderr | Set-Content -LiteralPath "$recordPath.stderr.txt"
	[ordered]@{ executable=$Godot; arguments=$launchArguments; signed_exit=$process.ExitCode; hex_exit=('0x{0:X8}' -f ([long]$process.ExitCode -band 0xFFFFFFFFL)); timed_out=$timedOut } |
		ConvertTo-Json -Depth 4 | Set-Content -LiteralPath "$recordPath.json"
	# Caller-owned log paths retain native evidence even if later semantic checks fail.
	if ($hasLogFile) {
		for ($index = 0; $index -lt $launchArguments.Count; $index++) {
			$phaseLog = ''
			if ($launchArguments[$index] -eq '--log-file' -and $index + 1 -lt $launchArguments.Count) { $phaseLog = $launchArguments[$index + 1] }
			elseif ($launchArguments[$index] -like '--log-file=*') { $phaseLog = $launchArguments[$index].Substring(11) }
			if ($phaseLog) {
				foreach ($suffix in @('json', 'stdout.txt', 'stderr.txt')) { Copy-Item -LiteralPath "$recordPath.$suffix" -Destination "$phaseLog.native.$suffix" -Force }
				break
			}
		}
	}
	if ($stdout) { Write-Output $stdout.TrimEnd() }
	if ($stderr) { Write-Output $stderr.TrimEnd() }
	if ($timedOut) { Write-Host "Godot timed out after $TimeoutSeconds seconds. Diagnostics: $recordPath.json" }
	if ($exitCode -ne 0) { Write-Host "Godot failed: $exitCode $('(0x{0:X8})' -f ([long]$exitCode -band 0xFFFFFFFFL)). Diagnostics: $recordPath.json" }
} finally {
	if ($null -eq $previousAppData) {
		Remove-Item Env:APPDATA -ErrorAction SilentlyContinue
	} else {
		$env:APPDATA = $previousAppData
	}
	if ($null -eq $previousLocalAppData) {
		Remove-Item Env:LOCALAPPDATA -ErrorAction SilentlyContinue
	} else {
		$env:LOCALAPPDATA = $previousLocalAppData
	}
}

if ($exitCode -eq 0) {
	# Standalone invocations own their isolated appdata and clean it on success.
	# A caller-supplied AppDataDirectory is caller-owned so an outer runner can
	# decide whether to delete or preserve it based on semantic test results.
	if ($ownsAppDataDirectory) {
		Remove-Item -LiteralPath $AppDataDirectory -Recurse -Force -ErrorAction SilentlyContinue
	}
	if ($testLogPath) {
		Remove-Item -LiteralPath $testLogPath -Force -ErrorAction SilentlyContinue
	}
	Remove-DirectoryIfEmpty $testAppDataRoot
	Remove-DirectoryIfEmpty $testLogDirectory
	# Keep test/_temp itself: its tracked .gdignore prevents Godot from scanning
	# transient test artifacts created beneath this directory.
}

if ($ExitCodeFile) {
	[IO.File]::WriteAllText(
		$ExitCodeFile,
		[string]$exitCode
	)
}

exit $exitCode

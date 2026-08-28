[CmdletBinding()]
param(
	[string]$ExitCodeFile = "",
	[string]$GodotPath = "",

	[Parameter(Position = 0, ValueFromRemainingArguments = $true)]
	[string[]]$GodotArgs
)

$ErrorActionPreference = "Stop"

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

$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
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
if (-not $godotFileName.EndsWith("_console", [StringComparison]::OrdinalIgnoreCase)) {
	$consoleGodot = Join-Path ([IO.Path]::GetDirectoryName($Godot)) ($godotFileName + "_console.exe")
	if (Test-Path -LiteralPath $consoleGodot -PathType Leaf) {
		$Godot = (Resolve-Path -LiteralPath $consoleGodot -ErrorAction Stop).Path
		$godotPathSource += ", console companion"
	}
}

$testTempDirectory = Join-Path $projectRoot "test\_temp"
$testAppDataDirectory = Join-Path $testTempDirectory "appdata"
New-Item -ItemType Directory -Force -Path $testAppDataDirectory | Out-Null

$hasLogFile = $false
foreach ($argument in $GodotArgs) {
	if ($argument -ieq "--log-file" -or $argument -ilike "--log-file=*") {
		$hasLogFile = $true
		break
	}
}

$launchArguments = @($GodotArgs)
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
$exitCode = -1
try {
	# Keep Godot user:// writes inside the repository so sandboxed test runs
	# do not depend on write access to the real Windows roaming AppData folder.
	$env:APPDATA = $testAppDataDirectory

	Write-Host "Godot executable ($godotPathSource): $Godot"
	$godotVersion = (& $Godot --version | Out-String).Trim()
	if ($LASTEXITCODE -ne 0) {
		throw "Could not query Godot version from: $Godot"
	}
	Write-Host "Godot version: $godotVersion"

	& $Godot @launchArguments
	$exitCode = $LASTEXITCODE
} finally {
	if ($null -eq $previousAppData) {
		Remove-Item Env:APPDATA -ErrorAction SilentlyContinue
	} else {
		$env:APPDATA = $previousAppData
	}
}

if ($testLogPath -and $exitCode -eq 0) {
	Remove-Item -LiteralPath $testLogPath -Force -ErrorAction SilentlyContinue
}

if ($ExitCodeFile) {
	[IO.File]::WriteAllText(
		$ExitCodeFile,
		[string]$exitCode
	)
}

exit $exitCode

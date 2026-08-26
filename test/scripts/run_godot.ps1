[CmdletBinding()]
param(
	[Parameter(ValueFromRemainingArguments = $true)]
	[string[]]$GodotArgs
)

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

$Godot = "C:\Godot\4.7\engine\Godot_v4.7.1-stable_win64.exe\Godot_v4.7.1-stable_win64_console.exe"

$projectRoot = Split-Path -Parent $PSScriptRoot
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
	$testLogDirectory = Join-Path $projectRoot ".godot\test_logs"
	New-Item -ItemType Directory -Force -Path $testLogDirectory | Out-Null
	$testLogPath = Join-Path $testLogDirectory (
		"godot-test-{0}-{1}.log" -f $PID, [guid]::NewGuid().ToString("N")
	)
	$launchArguments = @("--log-file", $testLogPath) + $launchArguments
	Write-Verbose "Godot test log: $testLogPath"
} else {
	Write-Verbose "Godot test log: caller-supplied --log-file"
}

& $Godot @launchArguments
$exitCode = $LASTEXITCODE

if ($testLogPath -and $exitCode -eq 0) {
	Remove-Item -LiteralPath $testLogPath -Force -ErrorAction SilentlyContinue
}

exit $exitCode

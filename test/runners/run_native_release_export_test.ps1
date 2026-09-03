[CmdletBinding()]
param([string]$GodotPath = "")

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

function Invoke-GodotRunner {
	param([string[]]$Arguments, [string]$ExecutablePath = "")

	$runnerArguments = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $godotRunner)
	if (-not [string]::IsNullOrWhiteSpace($ExecutablePath)) {
		$runnerArguments += @("-GodotPath", $ExecutablePath)
	} elseif (-not [string]::IsNullOrWhiteSpace($GodotPath)) {
		$runnerArguments += @("-GodotPath", $GodotPath)
	}
	$runnerArguments += $Arguments
	$commandOutput = & $powerShellExecutable @runnerArguments
	$commandExitCode = $LASTEXITCODE
	if ($commandOutput) {
		$commandOutput | ForEach-Object { Write-Host $_ }
	}
	return [int]$commandExitCode
}

$projectRoot = Resolve-ProjectRoot
$godotRunner = Join-Path $PSScriptRoot "run_godot.ps1"
$powerShellExecutable = (Get-Process -Id $PID).Path
$nativeDirectory = Join-Path $projectRoot "native"
$sourceBinDirectory = Join-Path $projectRoot "addons\easing_curve\bin"
$releaseDllName = "libeasing_curve_native.windows.template_release.x86_64.dll"
$debugDllName = "libeasing_curve_native.windows.template_debug.x86_64.dll"
$releaseDll = Join-Path $sourceBinDirectory $releaseDllName
$selectedGodotPath = if (-not [string]::IsNullOrWhiteSpace($GodotPath)) {
	$GodotPath
} elseif (-not [string]::IsNullOrWhiteSpace($env:EASING_CURVE_GODOT_PATH)) {
	$env:EASING_CURVE_GODOT_PATH
} else {
	"C:\Godot\4.7\engine\Godot_v4.7.1-stable_win64.exe\Godot_v4.7.1-stable_win64_console.exe"
}
$selectedGodotPath = (Resolve-Path -LiteralPath $selectedGodotPath -ErrorAction Stop).Path
$selectedGodotName = [IO.Path]::GetFileNameWithoutExtension($selectedGodotPath)
if (-not $selectedGodotName.EndsWith("_console", [StringComparison]::OrdinalIgnoreCase)) {
	$consoleCompanion = Join-Path ([IO.Path]::GetDirectoryName($selectedGodotPath)) ($selectedGodotName + "_console.exe")
	if (Test-Path -LiteralPath $consoleCompanion -PathType Leaf) {
		$selectedGodotPath = (Resolve-Path -LiteralPath $consoleCompanion).Path
	}
}
$godotVersion = (& $selectedGodotPath --version | Out-String).Trim()
if ([string]::IsNullOrWhiteSpace($godotVersion)) {
	throw "Could not determine the selected Godot version: $selectedGodotPath"
}
$templateVersion = ($godotVersion -replace '\.official\..*$', '')
$installedTemplateDirectory = Join-Path $env:APPDATA "Godot\export_templates\$templateVersion"
$debugTemplate = Join-Path $installedTemplateDirectory "windows_debug_x86_64.exe"
$releaseTemplate = Join-Path $installedTemplateDirectory "windows_release_x86_64.exe"
$tempBase = Join-Path $projectRoot "test\_temp\native-release-export"
$validationRoot = Join-Path $tempBase ([guid]::NewGuid().ToString("N"))
$tempProject = Join-Path $validationRoot "project"
$outputDirectory = Join-Path $validationRoot "output"
$exportedExecutable = Join-Path $outputDirectory "NativeReleaseExport.exe"
$projectTempDirectory = Join-Path $tempProject "test\_temp"
$bootstrapLog = Join-Path $projectTempDirectory "bootstrap.log"
$prepareLog = Join-Path $projectTempDirectory "prepare.log"
$exportLog = Join-Path $projectTempDirectory "export.log"
$runtimeLog = Join-Path $validationRoot "runtime.log"
$succeeded = $false

try {
	Write-Host "Building Windows x86_64 template-release GDExtension..."
	Push-Location $nativeDirectory
	try {
		& scons platform=windows target=template_release arch=x86_64
		if ($LASTEXITCODE -ne 0) {
			throw "Native release build failed with exit code $LASTEXITCODE."
		}
	} finally {
		Pop-Location
	}
	if (-not (Test-Path -LiteralPath $releaseDll -PathType Leaf)) {
		throw "Native release DLL was not produced: $releaseDll"
	}
	foreach ($template in @($debugTemplate, $releaseTemplate)) {
		if (-not (Test-Path -LiteralPath $template -PathType Leaf)) {
			throw "Godot $templateVersion Windows export template was not found: $template"
		}
	}

	New-Item -ItemType Directory -Force -Path $tempProject, $outputDirectory, $projectTempDirectory | Out-Null
	[IO.File]::WriteAllText((Join-Path $projectTempDirectory ".gdignore"), "", [Text.UTF8Encoding]::new($false))

	$destinationBin = Join-Path $tempProject "addons\easing_curve\bin"
	New-Item -ItemType Directory -Force -Path $destinationBin | Out-Null
	foreach ($fileName in @("easing_curve_native.gdextension", "easing_curve_native.gdextension.uid", $debugDllName, $releaseDllName)) {
		$source = Join-Path $sourceBinDirectory $fileName
		if (-not (Test-Path -LiteralPath $source -PathType Leaf)) {
			throw "Required Native export file was not found: $source"
		}
		Copy-Item -LiteralPath $source -Destination (Join-Path $destinationBin $fileName) -Force
	}

	Copy-Item -LiteralPath (Join-Path $projectRoot "test\scripts\integration\native_release_export_prepare.gd") -Destination (Join-Path $tempProject "prepare.gd") -Force
	Copy-Item -LiteralPath (Join-Path $projectRoot "test\scripts\integration\native_release_export_main.gd") -Destination (Join-Path $tempProject "main.gd") -Force

	$projectConfig = @'
; Generated by test/runners/run_native_release_export_test.ps1.
config_version=5

[application]

config/name="Native Release Export Validation"
run/main_scene="res://main.tscn"
config/features=PackedStringArray("4.7", "GL Compatibility")

[rendering]

renderer/rendering_method="gl_compatibility"
renderer/rendering_method.mobile="gl_compatibility"
'@
	[IO.File]::WriteAllText((Join-Path $tempProject "project.godot"), $projectConfig, [Text.UTF8Encoding]::new($false))

	$mainScene = @'
[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://main.gd" id="1_main"]

[node name="NativeReleaseExportValidation" type="Node"]
script = ExtResource("1_main")
'@
	[IO.File]::WriteAllText((Join-Path $tempProject "main.tscn"), $mainScene, [Text.UTF8Encoding]::new($false))

	$exportPreset = @'
[preset.0]

name="Windows Desktop"
platform="Windows Desktop"
dedicated_server=false
custom_features=""
export_filter="all_resources"
include_filter=""
exclude_filter=""
export_path=""
patches=PackedStringArray()
encrypt_pck=false
encrypt_directory=false
script_export_mode=2

[preset.0.options]

custom_template/debug="__DEBUG_TEMPLATE__"
custom_template/release="__RELEASE_TEMPLATE__"
debug/export_console_wrapper=1
binary_format/embed_pck=true
texture_format/s3tc_bptc=true
texture_format/etc2_astc=false
binary_format/architecture="x86_64"
codesign/enable=false
application/modify_resources=false
'@
	$exportPreset = $exportPreset.Replace("__DEBUG_TEMPLATE__", $debugTemplate.Replace("\", "/"))
	$exportPreset = $exportPreset.Replace("__RELEASE_TEMPLATE__", $releaseTemplate.Replace("\", "/"))
	[IO.File]::WriteAllText((Join-Path $tempProject "export_presets.cfg"), $exportPreset, [Text.UTF8Encoding]::new($false))

	Write-Host "Bootstrapping the isolated export project..."
	$bootstrapExit = Invoke-GodotRunner @("--editor", "--headless", "--path", $tempProject, "--import", "--log-file", $bootstrapLog)
	$classCache = Join-Path $tempProject ".godot\global_script_class_cache.cfg"
	$bootstrapText = if (Test-Path -LiteralPath $bootstrapLog) { Get-Content -Raw -LiteralPath $bootstrapLog } else { "" }
	$bootstrapHasFatalDiagnostic = $bootstrapText -match '(?m)^(?:SCRIPT ERROR:|.*Parse Error:|ERROR: Failed to load extension)'
	if (-not (Test-Path -LiteralPath $classCache -PathType Leaf) -or $bootstrapHasFatalDiagnostic) {
		throw "Isolated export project bootstrap did not produce a valid class cache."
	}
	if ($bootstrapExit -ne 0) {
		Write-Warning "Bootstrap returned $bootstrapExit after producing a clean class cache; continuing."
	}

	Write-Host "Creating built-in and custom Native resource fixtures..."
	$prepareExit = Invoke-GodotRunner @("--headless", "--path", $tempProject, "--script", "res://prepare.gd", "--log-file", $prepareLog)
	$prepareText = if (Test-Path -LiteralPath $prepareLog) { Get-Content -Raw -LiteralPath $prepareLog } else { "" }
	if ($prepareExit -ne 0 -or $prepareText -notmatch '(?m)^PREPARED:') {
		throw "Native export fixtures were not prepared successfully."
	}

	Write-Host "Exporting the Windows release project..."
	$exportExit = Invoke-GodotRunner @("--headless", "--path", $tempProject, "--export-release", "Windows Desktop", $exportedExecutable, "--log-file", $exportLog)
	if ($exportExit -ne 0 -or -not (Test-Path -LiteralPath $exportedExecutable -PathType Leaf)) {
		throw "Windows release export failed with exit code $exportExit."
	}

	Write-Host "Running the exported release executable..."
	$runtimeExit = Invoke-GodotRunner -ExecutablePath $exportedExecutable -Arguments @("--headless", "--log-file", $runtimeLog)
	$runtimeText = if (Test-Path -LiteralPath $runtimeLog) { Get-Content -Raw -LiteralPath $runtimeLog } else { "" }
	if ($runtimeExit -ne 0 -or $runtimeText -notmatch '(?m)^PASS: Windows release export') {
		if ($runtimeText) {
			Write-Host $runtimeText.TrimEnd()
		}
		throw "Exported Native release validation failed with exit code $runtimeExit."
	}

	$dllInfo = Get-Item -LiteralPath $releaseDll
	Write-Host "PASS: Windows release DLL built ($($dllInfo.Length) bytes) and exported Native resources loaded."
	$succeeded = $true
} finally {
	if ($succeeded) {
		Remove-Item -LiteralPath $validationRoot -Recurse -Force -ErrorAction SilentlyContinue
		if ((Test-Path -LiteralPath $tempBase -PathType Container) -and -not (Get-ChildItem -LiteralPath $tempBase -Force | Select-Object -First 1)) {
			Remove-Item -LiteralPath $tempBase -Force -ErrorAction SilentlyContinue
		}
	} else {
		Write-Host "Preserved failed export validation artifacts: $validationRoot" -ForegroundColor Yellow
	}
}

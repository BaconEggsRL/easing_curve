[CmdletBinding()]
param(
	[ValidateSet("windows", "web", "all")]
	[string]$Platform = "all",
	[ValidateSet("template_debug", "template_release", "all")]
	[string]$Target = "all",
	[string]$Architecture = "x86_64"
)

$ErrorActionPreference = "Stop"

$nativeRoot = (Resolve-Path $PSScriptRoot).Path
$projectRoot = (Resolve-Path (Join-Path $nativeRoot "..")).Path
$outputDirectory = Join-Path $projectRoot "addons/easing_curve/bin"
$godotCppApi = Join-Path $nativeRoot "godot-cpp\gdextension\extension_api.json"
if (-not (Test-Path -LiteralPath $godotCppApi -PathType Leaf)) {
	throw "The pinned godot-cpp submodule is missing. Run: git submodule update --init --recursive"
}

$apiHeader = Get-Content -Raw -LiteralPath $godotCppApi | ConvertFrom-Json
$apiVersion = "{0}.{1}.{2}-{3}" -f (
	$apiHeader.header.version_major,
	$apiHeader.header.version_minor,
	$apiHeader.header.version_patch,
	$apiHeader.header.version_status
)
if ($apiVersion -ne "4.4.1-stable") {
	throw "Expected the pinned Godot 4.4.1 extension API, found $apiVersion."
}

$platforms = if ($Platform -eq "all") { @("windows", "web") } else { @($Platform) }
$targets = if ($Target -eq "all") { @("template_debug", "template_release") } else { @($Target) }

Push-Location $nativeRoot
try {
	foreach ($currentPlatform in $platforms) {
		foreach ($currentTarget in $targets) {
			$currentArchitecture = if ($currentPlatform -eq "web") { "wasm32" } else { $Architecture }
			Write-Host "Building $currentPlatform $currentTarget $currentArchitecture against Godot API $apiVersion..."
			& scons "platform=$currentPlatform" "target=$currentTarget" "arch=$currentArchitecture"
			if ($LASTEXITCODE -ne 0) {
				throw "Native build failed for $currentPlatform/$currentTarget/$currentArchitecture (exit $LASTEXITCODE)."
			}
			$extension = if ($currentPlatform -eq "windows") { "dll" } else { "wasm" }
			$output = Join-Path $outputDirectory (
				"libeasing_curve_native.{0}.{1}.{2}.{3}" -f
				$currentPlatform, $currentTarget, $currentArchitecture, $extension
			)
			if (-not (Test-Path -LiteralPath $output -PathType Leaf)) {
				throw "Native build reported success but its output is missing: $output"
			}
		}
	}
} finally {
	Pop-Location
}

Write-Host "PASS: requested native builds completed against Godot API $apiVersion."

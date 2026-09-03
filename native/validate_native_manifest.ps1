[CmdletBinding()]
param(
	[ValidateSet("windows", "web", "all")]
	[string]$Platform = "all",
	[string]$ManifestPath = ""
)

$ErrorActionPreference = "Stop"

$nativeRoot = (Resolve-Path $PSScriptRoot).Path
$projectRoot = (Resolve-Path (Join-Path $nativeRoot "..")).Path
if ([string]::IsNullOrWhiteSpace($ManifestPath)) {
	$ManifestPath = Join-Path $projectRoot "addons\easing_curve\bin\easing_curve_native.gdextension"
}
$ManifestPath = (Resolve-Path -LiteralPath $ManifestPath -ErrorAction Stop).Path

function Get-ManifestEntries {
	param(
		[string]$Path,
		[string]$Section
	)

	$entries = @{}
	$inSection = $false
	foreach ($line in Get-Content -LiteralPath $Path) {
		$trimmed = $line.Trim()
		if ($trimmed -match '^\[(.+)\]$') {
			$inSection = $Matches[1] -eq $Section
			continue
		}
		if (-not $inSection -or [string]::IsNullOrWhiteSpace($trimmed) -or $trimmed.StartsWith(";")) {
			continue
		}
		if ($trimmed -notmatch '^([^=]+?)\s*=\s*"([^"]+)"$') {
			throw "Invalid $Section entry in ${Path}: $line"
		}
		$entries[$Matches[1].Trim()] = $Matches[2]
	}
	return $entries
}

function Assert-ManifestEntry {
	param(
		[hashtable]$Entries,
		[string]$Key,
		[string]$ExpectedResourcePath
	)

	if (-not $Entries.ContainsKey($Key)) {
		throw "Native manifest is missing required '$Key' entry."
	}
	if ($Entries[$Key] -ne $ExpectedResourcePath) {
		throw "Native manifest '$Key' must reference '$ExpectedResourcePath', found '$($Entries[$Key])'."
	}
}

$libraries = Get-ManifestEntries -Path $ManifestPath -Section "libraries"
$icons = Get-ManifestEntries -Path $ManifestPath -Section "icons"
$expectedWindowsLibrary = "res://addons/easing_curve/bin/libeasing_curve_native.windows.template_release.x86_64.dll"
$expectedWebDebugLibrary = "res://addons/easing_curve/bin/libeasing_curve_native.web.template_debug.wasm32.nothreads.wasm"
$expectedWebReleaseLibrary = "res://addons/easing_curve/bin/libeasing_curve_native.web.template_release.wasm32.nothreads.wasm"
$expectedCurveIcon = "res://addons/easing_curve/assets/Curve.svg"

Assert-ManifestEntry -Entries $icons -Key "NativeEasingCurve" -ExpectedResourcePath $expectedCurveIcon
$curveIconPath = Join-Path $projectRoot $expectedCurveIcon.Substring("res://".Length).Replace("/", [IO.Path]::DirectorySeparatorChar)
if (-not (Test-Path -LiteralPath $curveIconPath -PathType Leaf)) {
	throw "Native manifest references a missing NativeEasingCurve icon: $curveIconPath"
}

if ($Platform -in @("windows", "all")) {
	Assert-ManifestEntry -Entries $libraries -Key "windows.x86_64" -ExpectedResourcePath $expectedWindowsLibrary
	Assert-ManifestEntry -Entries $libraries -Key "windows.release.x86_64" -ExpectedResourcePath $expectedWindowsLibrary
}
if ($Platform -in @("web", "all")) {
	Assert-ManifestEntry -Entries $libraries -Key "web.debug.wasm32" -ExpectedResourcePath $expectedWebDebugLibrary
	Assert-ManifestEntry -Entries $libraries -Key "web.release.wasm32" -ExpectedResourcePath $expectedWebReleaseLibrary
}

$platformPrefixes = switch ($Platform) {
	"windows" { @("windows.") }
	"web" { @("web.") }
	default { @("windows.", "web.") }
}

foreach ($entry in $libraries.GetEnumerator()) {
	if (-not ($platformPrefixes | Where-Object { $entry.Key.StartsWith($_, [StringComparison]::Ordinal) })) {
		continue
	}
	if (-not $entry.Value.StartsWith("res://", [StringComparison]::Ordinal)) {
		throw "Native manifest '$($entry.Key)' is not project-relative: $($entry.Value)"
	}
	$relativePath = $entry.Value.Substring("res://".Length).Replace("/", [IO.Path]::DirectorySeparatorChar)
	$libraryPath = Join-Path $projectRoot $relativePath
	if (-not (Test-Path -LiteralPath $libraryPath -PathType Leaf)) {
		throw "Native manifest '$($entry.Key)' references a missing library: $libraryPath"
	}
}

Write-Host "PASS: Native $Platform manifest entries match existing build artifacts."

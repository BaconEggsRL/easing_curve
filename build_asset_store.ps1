$ErrorActionPreference = "Stop"

$PluginPath = "addons\easing_curve"
$ConfigPath = "$PluginPath\plugin.cfg"

$OutputPath = "_exports\_asset_store_builds"
$BuildPath = "$OutputPath\_staging"

# Read version from plugin.cfg.
$VersionLine = Get-Content $ConfigPath |
    Where-Object { $_ -match '^\s*version\s*=' } |
    Select-Object -First 1

if (-not $VersionLine) {
    throw "Could not find version in $ConfigPath"
}

if ($VersionLine -notmatch '^\s*version\s*=\s*"([^"]+)"') {
    throw "Could not parse version from: $VersionLine"
}

$Version = $Matches[1]
$OutputZip = "$OutputPath\easing_curve_v$Version.zip"

Write-Host "Building Easing Curve v$Version..."

# Make sure output directory exists.
New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null

# Clean previous staging directory.
Remove-Item $BuildPath -Recurse -Force -ErrorAction SilentlyContinue

# Create required Asset Store structure.
New-Item -ItemType Directory -Path "$BuildPath\addons" | Out-Null

# Copy only addons/easing_curve.
Copy-Item `
    $PluginPath `
    "$BuildPath\addons\easing_curve" `
    -Recurse

# Remove an existing build of the same version.
Remove-Item $OutputZip -Force -ErrorAction SilentlyContinue

# ZIP contains:
#
# addons/
# └── easing_curve/
#
Compress-Archive `
    -Path "$BuildPath\addons" `
    -DestinationPath $OutputZip

# Clean staging directory.
Remove-Item $BuildPath -Recurse -Force

Write-Host ""
Write-Host "Asset Store build complete:"
Write-Host $OutputZip
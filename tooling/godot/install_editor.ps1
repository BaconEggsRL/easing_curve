[CmdletBinding()]
param([string]$ManifestPath = "$PSScriptRoot/editor-pin.json", [string]$Destination = "$PSScriptRoot/../../.cache/godot/pinned-editor")
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot/../../test/runners/godot_process_contract.ps1"
$pin = Get-Content -LiteralPath $ManifestPath -Raw | ConvertFrom-Json
if ($pin.editor_url -notmatch '^https://github.com/BaconEggsRL/easing_curve/releases/download/' -or $pin.editor_sha256 -notmatch '^[a-fA-F0-9]{64}$') {
	throw 'A qualified release URL and SHA256 are required. No fallback editor is allowed.'
}
New-Item -ItemType Directory -Path $Destination -Force | Out-Null
Set-Content -LiteralPath (Join-Path $Destination '.gdignore') -Value '' -NoNewline
$path = Join-Path (Resolve-Path $Destination).Path 'godot-editor.exe'
Invoke-WebRequest -Uri $pin.editor_url -OutFile "$path.download"
Assert-GodotExecutableHash "$path.download" $pin.editor_sha256 | Out-Null
Move-Item -LiteralPath "$path.download" -Destination $path -Force
$version = Get-GodotVersion -ExecutablePath $path -LogPath (Join-Path (Resolve-Path $Destination).Path 'version.log')
if (-not $version.StartsWith($pin.editor_version_prefix, [StringComparison]::Ordinal)) { throw "Incorrect pinned editor identity: $version" }
Copy-Item -LiteralPath $ManifestPath -Destination (Join-Path $Destination 'editor-pin.json') -Force
if ($env:GITHUB_ENV) {
	"EASING_CURVE_EDITOR_GODOT_PATH=$path" | Add-Content $env:GITHUB_ENV
	"EASING_CURVE_EDITOR_GODOT_SHA256=$($pin.editor_sha256)" | Add-Content $env:GITHUB_ENV
}
Write-Host "Verified pinned editor: $path ($version; $($pin.editor_sha256))"

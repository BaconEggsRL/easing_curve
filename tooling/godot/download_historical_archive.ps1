[CmdletBinding()]
param([string]$ManifestPath = "$PSScriptRoot/editor-pin.json", [string]$Destination = "$PSScriptRoot/../../test/_temp/historical-input")
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot/../../test/runners/godot_process_contract.ps1"
$inputPin = (Get-Content -LiteralPath $ManifestPath -Raw | ConvertFrom-Json).historical_archive
if ($inputPin.url -notmatch '^https://github.com/BaconEggsRL/easing_curve/releases/download/' -or $inputPin.sha256 -notmatch '^[a-fA-F0-9]{64}$') {
	throw 'A durable historical archive URL and SHA256 are required.'
}
New-Item -ItemType Directory -Force -Path $Destination | Out-Null
$archive = Join-Path (Resolve-Path $Destination).Path ([IO.Path]::GetFileName(([uri]$inputPin.url).AbsolutePath))
Invoke-WebRequest -Uri $inputPin.url -OutFile "$archive.download"
Assert-GodotExecutableHash "$archive.download" $inputPin.sha256 | Out-Null
Move-Item -LiteralPath "$archive.download" -Destination $archive -Force
if ($env:GITHUB_ENV) { "HISTORICAL_ARCHIVE=$archive" | Add-Content $env:GITHUB_ENV }
Write-Host "Verified historical archive: $archive ($($inputPin.sha256))"
return $archive

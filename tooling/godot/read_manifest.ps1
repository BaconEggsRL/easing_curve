[CmdletBinding()]
param([string]$ManifestPath = "$PSScriptRoot/editor-pin.json")
$ErrorActionPreference = 'Stop'
$pin = Get-Content -LiteralPath $ManifestPath -Raw | ConvertFrom-Json
if ($pin.official_version -notmatch '^\d+\.\d+\.\d+$') { throw 'Invalid official Godot version.' }
if ($pin.export_template_version -ne "$($pin.official_version).stable") { throw 'Official runtime and template pins differ.' }
if ($env:GITHUB_OUTPUT) {
	"official_version=$($pin.official_version)" | Add-Content $env:GITHUB_OUTPUT
	"python_version=$($pin.build_toolchain.python_version)" | Add-Content $env:GITHUB_OUTPUT
}
return $pin

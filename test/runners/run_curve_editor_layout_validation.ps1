[CmdletBinding()]
param(
	[ValidateSet('easing_curve_layout_contract_test', 'easing_curve_editor_gesture_characterization_test', 'easing_curve_editor_drag_coordinates_test')]
	[string]$Suite = 'easing_curve_layout_contract_test',
	[string]$GodotPath = ''
)

$ErrorActionPreference = 'Stop'
$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$hostRoot = Join-Path $projectRoot ('test/_temp/layout-editor-' + [guid]::NewGuid().ToString('N'))
$launcher = Join-Path $PSScriptRoot 'run_godot.ps1'
New-Item -ItemType Directory -Force -Path "$hostRoot/addons", "$hostRoot/test/_temp" | Out-Null
Copy-Item -LiteralPath "$projectRoot/addons/easing_curve" -Destination "$hostRoot/addons" -Recurse
Copy-Item -LiteralPath "$projectRoot/test/scripts", "$projectRoot/test/presets" -Destination "$hostRoot/test" -Recurse
@'
config_version=5
[application]
config/name="Curve Layout Editor Validation"
config/features=PackedStringArray("4.7", "GL Compatibility")
[rendering]
renderer/rendering_method="gl_compatibility"
'@ | Set-Content -LiteralPath "$hostRoot/project.godot"

# Bootstrap class/asset imports before enabling the temporary host plugin.
& $launcher -GodotPath $GodotPath --editor --headless --path $hostRoot --log-file "$hostRoot/test/_temp/bootstrap.log" --import --quit *> "$hostRoot/test/_temp/bootstrap-console.txt"
if ($LASTEXITCODE -ne 0) { throw "Editor bootstrap failed: $hostRoot/test/_temp/bootstrap-console.txt" }

# Reuse the exact regression suite in a full EditorPlugin host. --editor --script
# intentionally has no editor theme in Godot 4.7; this adapter retains real icons,
# fonts, containers, mouse dispatch and rendering without changing source tests.
$caseSource = Get-Content -LiteralPath "$hostRoot/test/scripts/support/test_case.gd" -Raw
$nodeAdapter = @'
@tool
extends Node

var root: Window:
	get: return get_tree().root
var process_frame: Signal:
	get: return get_tree().process_frame

func get_root() -> Window:
	return get_tree().root

func quit(code: int) -> void:
	get_tree().quit(code)
'@
$caseSource.Replace('extends SceneTree', $nodeAdapter) | Set-Content -LiteralPath "$hostRoot/test/scripts/support/layout_editor_case.gd"
$suitePath = "$hostRoot/test/scripts/unit/$Suite.gd"
$suiteSource = Get-Content -LiteralPath $suitePath -Raw
('@tool' + "`n" + $suiteSource.Replace('res://test/scripts/support/test_case.gd', 'res://test/scripts/support/layout_editor_case.gd')) | Set-Content -LiteralPath $suitePath

New-Item -ItemType Directory -Force -Path "$hostRoot/addons/layout_test_host" | Out-Null
@'
[plugin]
name="Curve layout validation"
description="Temporary full-editor regression host"
author="Tests"
version="1"
script="plugin.gd"
'@ | Set-Content -LiteralPath "$hostRoot/addons/layout_test_host/plugin.cfg"
$pluginSource = @'
@tool
extends EditorPlugin

func _enter_tree() -> void:
	_run.call_deferred()

func _run() -> void:
	# Awaited frame_post_draw must keep firing even when the editor is idle.
	OS.low_processor_usage_mode = false
	for frame in range(30):
		await get_tree().process_frame
	var suite := load("res://test/scripts/unit/__SUITE__.gd").new() as Node
	add_child(suite)
'@
$pluginSource.Replace('__SUITE__', $Suite) | Set-Content -LiteralPath "$hostRoot/addons/layout_test_host/plugin.gd"
@'

[editor_plugins]
enabled=PackedStringArray("res://addons/layout_test_host/plugin.cfg")
'@ | Add-Content -LiteralPath "$hostRoot/project.godot"

Write-Output "Full editor validation host: $hostRoot"
& $launcher -GodotPath $GodotPath -TimeoutSeconds 60 --editor --path $hostRoot --log-file "$hostRoot/test/_temp/validation.log" *> "$hostRoot/test/_temp/validation-console.txt"
$suiteExitCode = $LASTEXITCODE
$outputText = Get-Content -LiteralPath "$hostRoot/test/_temp/validation-console.txt" -Raw
$outputText -split '\r?\n' | Where-Object { $_ -match '^(PASS:|WRAP_GATE|FREE_MODE_GATE|TOOLBAR_METRICS|RESET_GATE|SCRIPT ERROR:|ERROR: FAIL:)' } | Write-Output
Write-Output "Preserved logs and captures: $hostRoot/test/_temp"
if ($suiteExitCode -ne 0 -or $outputText -match 'SCRIPT ERROR:' -or $outputText -notmatch '(?m)^PASS:') {
	throw "Layout validation failed (exit $suiteExitCode): $hostRoot/test/_temp/validation-console.txt"
}

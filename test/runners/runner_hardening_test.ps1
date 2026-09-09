$ErrorActionPreference = 'Stop'
. "$PSScriptRoot/godot_process_contract.ps1"
function Get-RunnerFunction {
	param([string]$File, [string]$Name)
	$tokens=$null; $errors=$null
	$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot $File), [ref]$tokens, [ref]$errors)
	if ($errors.Count) { throw "Parse errors in $File" }
	$function=$ast.Find({ param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $Name }, $true)
	if (-not $function) { throw "Missing function $Name in $File" }
	return [scriptblock]::Create($function.Extent.Text)
}
$temp = Join-Path (Resolve-Path "$PSScriptRoot/../..").Path ("test/_temp/runner-hardening-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory $temp | Out-Null
$powerShellExecutable=(Get-Process -Id $PID).Path
$GodotPath=''
$godotRunner="$temp/fake-runner.ps1"
@'
Write-Output 'Complete semantic results, despite native failure'
exit -1073741819
'@ | Set-Content $godotRunner
foreach ($file in @('run_native_editor_script_validation.ps1', 'run_native_inspector_crossing_benchmark.ps1', 'run_native_point_scaling_benchmark.ps1', 'run_native_release_export_test.ps1')) {
	. (Get-RunnerFunction $file 'Invoke-GodotRunner')
	$code=Invoke-GodotRunner @('--editor')
	if ($code -is [array] -or $code -ne -1073741819) { throw "$file mixed stdout with its native exit status." }
}
& {
	. (Get-RunnerFunction 'run_release_archive_test.ps1' 'Invoke-EditorLifecycle')
	function Write-EditorImportDiagnostics { param($Phase,$LogPath,$ExitCode) }
	function Stop-ArchivePhase { param($Phase,$LogPath,$ExitCode) throw "Semantic failure: $Phase" }
	function Test-Path { return $true } # Model an existing clean cache without writing generated .godot files.
	function Invoke-Runner { param($LogPath,$Arguments) return $script:syntheticExit }
	$validationRoot=$temp
	foreach ($case in @(@(0,'clean',$true), @(1,'clean',$false), @(-1073741819,'clean',$false), @(0,'SCRIPT ERROR: deliberate semantic failure',$false))) {
		$script:syntheticExit=$case[0]
		$case[1] | Set-Content "$temp/import.log"
		$continued=$false
		try { Invoke-EditorLifecycle -Phase 'synthetic lifecycle' -LogPath "$temp/import.log"; $continued=$true } catch { if ($case[2]) { throw } }
		if ($continued -ne $case[2]) { throw 'Archive lifecycle requires BOTH zero exit and semantic success.' }
	}
}
& {
	. (Get-RunnerFunction 'run_physical_input_profile.ps1' 'Invoke-ProfileHostSmokeTest')
	function Start-Process { param($FilePath,$ArgumentList,[switch]$PassThru) return $script:fakeProcess }
	function Test-LogHasScriptFailure { return $false }
	function Get-PluginVersion { return 'fixture' }
	$godot=@{Gui='unused'}
	New-Item -ItemType Directory "$temp/test/_temp" -Force | Out-Null
	'PHYSICAL_INPUT_PROBE_START' | Set-Content "$temp/test/_temp/smoke_editor.log"
	foreach ($code in @(0, -1073741819)) {
		$script:fakeProcess=[pscustomobject]@{ExitCode=$code}
		$script:fakeProcess | Add-Member -MemberType ScriptMethod -Name WaitForExit -Value { param($Milliseconds) return $true }
		$passed=$false
		try { Invoke-ProfileHostSmokeTest -Label 'synthetic' -ProjectPath $temp; $passed=$true } catch { if ($code -eq 0) { throw } }
		if ($passed -ne ($code -eq 0)) { throw 'Physical-input smoke check accepted a crash with clean output.' }
	}
}
Write-Host "PASS: runner wrappers retain raw status; archive and profiling checks reject crashes despite clean semantic output. Evidence: $temp"
exit 0

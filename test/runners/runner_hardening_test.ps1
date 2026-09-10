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
	. (Get-RunnerFunction 'run_release_archive_test.ps1' 'Test-ArchiveEditorResult')
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
& {
	. (Get-RunnerFunction 'run_physical_input_profile.ps1' 'Prepare-ProfileProject')
	$tempBase = $temp
	New-Item -ItemType Directory "$temp/previous-failure" | Out-Null
	'original failed evidence' | Set-Content "$temp/previous-failure/evidence.txt"
	$rejected = $false
	try { Prepare-ProfileProject -Label 'previous-failure' -SourceKind current | Out-Null } catch { $rejected = $true }
	if (-not $rejected -or (Get-Content "$temp/previous-failure/evidence.txt") -ne 'original failed evidence') { throw 'A later profile run overwrote failed evidence.' }
}
& {
	$ast = [Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot 'run_physical_input_profile.ps1'), [ref]$null, [ref]$null)
	$bootstrapFunction = $ast.Find({ param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Prepare-ProfileProject' }, $true).Extent.Text
	# Execute the actual validation tail, without the fixture-copy setup or generated cache writes.
	$tail = $bootstrapFunction.Substring($bootstrapFunction.IndexOf('$bootstrapOutput = @(')).TrimEnd()
	$bootstrap = [scriptblock]::Create($tail.Substring(0, $tail.Length - 1))
	$smokeLoop = $ast.Find({ param($node) $node -is [Management.Automation.Language.ForEachStatementAst] -and $node.Condition.Extent.Text -eq '$smokeProcesses.GetEnumerator()' }, $true)
	if (-not $smokeLoop) { throw 'Missing side-by-side smoke branch.' }
	$smoke = [scriptblock]::Create($smokeLoop.Extent.Text)
	function Test-Path { return $true }
	function Test-LogHasScriptFailure { return $false }
	function Get-PluginVersion { return 'synthetic' }
	function Write-ProjectConfig {}
	function Invoke-SyntheticGodot { $global:LASTEXITCODE = $script:profileExit; 'Initialization completed' }
	$projectPath = $temp
	$projectConfig = 'unused'
	$bootstrapLog = "$temp/bootstrap.log"
	$Label = 'synthetic'
	$godot = @{ Console='Invoke-SyntheticGodot' }
	'clean import' | Set-Content $bootstrapLog
	'PHYSICAL_INPUT_PROBE_START' | Set-Content "$temp/test/_temp/smoke_editor.log"
	foreach ($code in @(0, 1, -1073741819)) {
		$script:profileExit = $code
		$accepted = $false
		try { & $bootstrap | Out-Null; $accepted = $true } catch { if ($code -eq 0) { throw } }
		if ($accepted -ne ($code -eq 0)) { throw 'Profiler bootstrap accepted a nonzero exit with a clean cache.' }
		$process = [pscustomobject]@{ ExitCode=$code; Id=123 }
		$process | Add-Member ScriptMethod WaitForExit { param($Timeout) return $true }
		$smokeProcesses = [ordered]@{ synthetic=$process }
		$projects = @{ synthetic=$temp }
		$accepted = $false
		try { & $smoke | Out-Null; $accepted = $true } catch { if ($code -eq 0) { throw } }
		if ($accepted -ne ($code -eq 0)) { throw 'Side-by-side smoke accepted a crash with clean output.' }
		if (-not [IO.File]::Exists($bootstrapLog) -or -not [IO.File]::Exists("$temp/test/_temp/smoke_editor.log")) { throw 'Failed profiler fixture was removed.' }
	}
}
# Exercise the layout runner's actual final decision: semantic failures retain
# the host even when the process exits zero; only a complete PASS permits cleanup.
$layoutSource = Get-Content "$PSScriptRoot/run_curve_editor_layout_validation.ps1" -Raw
$layoutFinish = [scriptblock]::Create($layoutSource.Substring($layoutSource.IndexOf('if ($suiteExitCode -ne 0')))
foreach ($case in @(@{Exit=0;Text='PASS: layout';Pass=$true}, @{Exit=1;Text='PASS: layout';Pass=$false}, @{Exit=0;Text='no pass';Pass=$false}, @{Exit=0;Text="PASS: layout`nSCRIPT ERROR: synthetic";Pass=$false})) {
	& {
		$tempRoot = $temp
		$hostRoot = Join-Path $temp ('layout-' + [guid]::NewGuid().ToString('N'))
		New-Item -ItemType Directory -Force "$hostRoot/test/_temp" | Out-Null
		Set-Content "$hostRoot/test/_temp/validation.log" 'fixture evidence'
		$suiteExitCode = $case.Exit
		$outputText = $case.Text
		$EvidenceDirectory = ''
		$accepted = $false
		try { & $layoutFinish | Out-Null; $accepted = $true } catch { if ($case.Pass) { throw } }
		if ($accepted -ne $case.Pass -or (Test-Path $hostRoot) -eq $case.Pass) { throw 'Layout success cleanup/failure retention changed.' }
	}
}
Write-Host "PASS: runner wrappers retain raw status; all profiler branches and archive checks reject crashes despite clean output."
$resolvedTemp = [IO.Path]::GetFullPath($temp)
$expectedPrefix = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../test/_temp')) + [IO.Path]::DirectorySeparatorChar
if (-not $resolvedTemp.StartsWith($expectedPrefix, [StringComparison]::OrdinalIgnoreCase)) { throw "Unsafe cleanup path: $resolvedTemp" }
Remove-Item -LiteralPath $resolvedTemp -Recurse -Force
exit 0

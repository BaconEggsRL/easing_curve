[CmdletBinding()]
param(
	[Parameter(Mandatory)][string]$CandidateDirectory,
	[Parameter(Mandatory)][string]$ArchivePath,
	[Parameter(Mandatory)][string]$ProcDumpPath,
	[Parameter(Mandatory)][string]$OfficialGodotPath,
	[ValidateRange(1,10)][int]$Repetitions = 10,
	[switch]$FullSuite
)
$ErrorActionPreference = 'Stop'
$root = (Resolve-Path "$PSScriptRoot/../..").Path
. "$root/test/runners/godot_process_contract.ps1"
$pin = Get-Content "$PSScriptRoot/editor-pin.json" -Raw | ConvertFrom-Json
$candidate = (Resolve-Path "$CandidateDirectory/godot-editor.exe").Path
$control = (Resolve-Path "$CandidateDirectory/godot-control.exe").Path
$controlRecord = Get-Content "$CandidateDirectory/control-provenance.json" -Raw | ConvertFrom-Json
$candidateRecord = Get-Content "$CandidateDirectory/provenance.json" -Raw | ConvertFrom-Json
$qualificationRoot = Join-Path $root 'test/_temp/editor-qualification'
if (Test-Path $qualificationRoot) { throw 'Use a fresh qualification workspace; no retry into success.' }
New-Item -ItemType Directory $qualificationRoot | Out-Null
$nativeBefore = @(Get-ChildItem "$root/addons/easing_curve/bin" -File | Where-Object Extension -in @('.dll', '.wasm') | Get-FileHash | Select-Object Path,Hash)
$nativeBefore | ConvertTo-Json | Set-Content "$qualificationRoot/native-input-hashes.json"
Assert-GodotExecutableHash $candidate $pin.editor_sha256 | Out-Null
Assert-GodotExecutableHash $control $controlRecord.executable_sha256 | Out-Null
if ($candidateRecord.executable_sha256 -ine $pin.editor_sha256 -or $candidateRecord.source_commit -ne $pin.source_commit -or $controlRecord.source_commit -ne $pin.source_commit) { throw 'Candidate provenance does not match the pin.' }
if ($candidateRecord.patch_sha256 -ine $pin.patch_sha256 -or (Get-FileHash "$CandidateDirectory/editor-help-lifetime.patch").Hash -ine $pin.patch_sha256) { throw 'Candidate patch provenance mismatch.' }
$env:EASING_CURVE_EDITOR_GODOT_PATH = ''
$env:EASING_CURVE_EDITOR_GODOT_SHA256 = ''
$runner = "$root/test/runners/run_import_crash_diagnostics.ps1"
$controlFailed = $false
try { & $runner -GodotPath $control -ArchivePath $ArchivePath -ProcDumpPath $ProcDumpPath -CaptureOnly -Cases B -OutputDirectory "$qualificationRoot/control" }
catch { $controlFailed = $true }
$controlResult = Get-Content "$qualificationRoot/control/results.json" -Raw | ConvertFrom-Json
if (-not $controlFailed -or $controlResult.signed_exit -ne -1073741819 -or -not $controlResult.gdextension_loaded -or $controlResult.dumps.Count -lt 1) { throw 'The unpatched same-toolchain control did not establish the expected crash.' }

$env:EASING_CURVE_EDITOR_GODOT_PATH = $candidate
$env:EASING_CURVE_EDITOR_GODOT_SHA256 = $pin.editor_sha256
$env:EASING_CURVE_GODOT_PATH = $OfficialGodotPath
$matrixResults = @()
for ($iteration = 1; $iteration -le $Repetitions; $iteration++) {
	Assert-GodotExecutableHash $candidate $pin.editor_sha256 | Out-Null
	$iterationRoot = "$qualificationRoot/matrix-$iteration"
	& $runner -GodotPath $candidate -ArchivePath $ArchivePath -ProcDumpPath $ProcDumpPath -CaptureOnly -OutputDirectory $iterationRoot
	$results = @(Get-Content "$iterationRoot/results.json" -Raw | ConvertFrom-Json)
	if ($results.Count -ne 5) { throw 'Incomplete A-E matrix.' }
	foreach ($result in $results) {
		Assert-GodotProcessExit $result.signed_exit "matrix $iteration/$($result.case)" $iterationRoot
		$expectedLoaded = $result.case -in @('B','D','E')
		$monitorLog = Get-Content "$iterationRoot/$($result.case)-procdump/procdump.stdout.txt" -Raw
		if ($result.gdextension_loaded -ne $expectedLoaded -or -not $result.class_cache_exists -or -not $result.initialization_completed -or -not $result.editor_layout_completed -or $result.dumps.Count -or $result.log_errors.Count -or $monitorLog -notmatch 'Exception monitor:\s+First Chance\+Unhandled') { throw "Matrix evidence failed: $iteration/$($result.case)" }
	}
	$matrixResults += $results
}
$matrixResults | ConvertTo-Json -Depth 6 | Set-Content "$qualificationRoot/matrix-results.json"

# Exercise extension documentation while its editor-side data is alive.
$docsProject = "$qualificationRoot/matrix-1/B-procdump/project"
$docsOutput = "$qualificationRoot/docs"
New-Item -ItemType Directory $docsOutput | Out-Null
& "$root/test/runners/run_godot.ps1" -GodotPath $OfficialGodotPath --editor --headless --path $docsProject --doctool $docsOutput --gdextension-docs --log-file "$qualificationRoot/docs.log"
Assert-GodotProcessExit $LASTEXITCODE 'Extension documentation generation' "$qualificationRoot/docs.log"
foreach ($name in @('NativeEasingCurve', 'NativeEasingCurvePoint')) {
	$xml = Get-ChildItem $docsOutput -Filter "$name.xml" -Recurse | Select-Object -First 1
	if (-not $xml -or (Get-Content $xml.FullName -Raw) -notmatch "<class name=`"$name`"") { throw "Missing live extension documentation: $name" }
}

if ($FullSuite) {
	$pwsh = (Get-Process -Id $PID).Path
	function Invoke-Validation {
		param([string]$Name, [string]$Script, [string[]]$Arguments = @())
		Assert-GodotExecutableHash $candidate $pin.editor_sha256 | Out-Null
		& $pwsh -NoProfile -File $Script @Arguments *> "$qualificationRoot/$Name.txt"
		Assert-GodotProcessExit $LASTEXITCODE $Name "$qualificationRoot/$Name.txt"
	}
	Invoke-Validation 'process-contract' "$root/test/runners/godot_process_contract_test.ps1"
	Invoke-Validation 'runner-hardening' "$root/test/runners/runner_hardening_test.ps1"
	Invoke-Validation 'archive-diagnostics' "$root/test/runners/release_archive_diagnostics_test.ps1"
	Invoke-Validation 'release-contract' "$root/test/runners/release_workflow_contract_test.ps1"
	Invoke-Validation 'windows-suite' "$root/test/runners/run_all_tests.ps1" @('--run', '-GodotPath', $OfficialGodotPath)
	Invoke-Validation 'historical-archive' "$root/test/runners/run_release_archive_test.ps1" @('-GodotPath', $OfficialGodotPath, '-ArchivePath', $ArchivePath, '-KeepArtifacts')
	Invoke-Validation 'build-current-archive' "$root/build_asset_store.ps1"
	Invoke-Validation 'current-archive' "$root/test/runners/run_release_archive_test.ps1" @('-GodotPath', $OfficialGodotPath, '-KeepArtifacts')
	Invoke-Validation 'windows-export' "$root/test/runners/run_native_release_export_test.ps1" @('-GodotPath', $OfficialGodotPath, '-SkipBuild', '-ExportTemplateVersion', $pin.export_template_version)
	Invoke-Validation 'web-export-runtime' "$root/test/runners/run_native_web_export_test.ps1" @('-GodotPath', $OfficialGodotPath, '-SkipBuild', '-ExportTemplateVersion', $pin.export_template_version)
}
[void](Assert-GodotExecutableHash $candidate $pin.editor_sha256)
foreach ($inputHash in $nativeBefore) {
	if ((Get-FileHash -LiteralPath $inputHash.Path).Hash -ne $inputHash.Hash) { throw "Native validation input changed: $($inputHash.Path)" }
}
[ordered]@{ candidate_sha256=$pin.editor_sha256; source_commit=$pin.source_commit; patch_sha256=$pin.patch_sha256; repetitions=$Repetitions; full_suite=[bool]$FullSuite; image=$env:ImageOS; image_version=$env:ImageVersion; run=$env:GITHUB_RUN_ID; commit=$env:GITHUB_SHA; passed=$true } |
	ConvertTo-Json | Set-Content "$qualificationRoot/qualification.json"
Write-Host 'PASS: candidate qualification completed without accepting or retrying any failed validation.'

$ErrorActionPreference = "Stop"
$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot "../..")).Path
$validationRoot = Join-Path $projectRoot ("test/_temp/archive-diagnostics-test-" + [guid]::NewGuid().ToString("N"))
$powerShellExecutable = (Get-Process -Id $PID).Path
$GodotPath = ""
$tokens = $null
$parseErrors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile(
	(Join-Path $PSScriptRoot "run_release_archive_test.ps1"), [ref]$tokens, [ref]$parseErrors
)
if ($parseErrors.Count) { throw "Archive runner parse errors: $parseErrors" }
foreach ($name in @("Invoke-Runner", "Write-EditorImportDiagnostics", "Stop-ArchivePhase")) {
	$definition = $ast.Find({
		param($node)
		$node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $name
	}, $true)
	. ([scriptblock]::Create($definition.Extent.Text))
}
function Assert-Diagnostic {
	param([bool]$Condition, [string]$Message)
	if (-not $Condition) { throw $Message }
}
try {
	New-Item -ItemType Directory -Path $validationRoot | Out-Null
	$runner = Join-Path $validationRoot "fake_runner.ps1"
	@'
param([string]$ExitCodeFile)
Set-Content -LiteralPath $ExitCodeFile -Value '-1073741819' -NoNewline
Write-Output 'captured process output'
exit -1073741819
'@ | Set-Content -LiteralPath $runner
	$logPath = Join-Path $validationRoot "initial-import.log"
	$exitCode = Invoke-Runner -Arguments @() -LogPath $logPath
	Assert-Diagnostic ($exitCode -eq -1073741819) "Runner lost the signed Windows crash exit code."
	Assert-Diagnostic ((Get-Content -Raw "$logPath.process.txt") -match 'captured process output') "Process output was not retained."
	"$([char]27)[92m[ DONE ]$([char]27)[0m reimport`nSCRIPT ERROR: Parse Error: fixture failure" | Set-Content -LiteralPath $logPath
	Write-EditorImportDiagnostics -Phase "synthetic crash fixture" -LogPath $logPath -ExitCode $exitCode 6> $null
	$diagnostics = Get-Content -Raw "$logPath.diagnostics.json" | ConvertFrom-Json
	Assert-Diagnostic ($diagnostics.godot_exit_code -eq '-1073741819') "Raw Godot exit was lost."
	Assert-Diagnostic (-not $diagnostics.class_cache_exists) "Missing class cache was reported present."
	Assert-Diagnostic ($diagnostics.import_completion_count -eq 1) "ANSI-colored completion was not recorded."
	Assert-Diagnostic ($diagnostics.error_lines.Count -eq 1) "Script failure was not recorded."
	Assert-Diagnostic ($diagnostics.svg_imports.Count -eq 28) "Diagnostics must inventory every allowlisted SVG, including missing files."
	Assert-Diagnostic (@($diagnostics.svg_imports | Where-Object source_exists).Count -eq 0) "Missing SVGs were reported present."

	# Existing sources and sidecars alone are not evidence of generated textures.
	$sourcePath = Join-Path $validationRoot "addons/easing_curve/assets/BezierHandlesLinked.svg"
	New-Item -ItemType Directory -Path (Split-Path $sourcePath) | Out-Null
	Set-Content -LiteralPath $sourcePath -Value '<svg/>'
	Set-Content -LiteralPath "$sourcePath.import" -Value 'path="res://.godot/imported/linked.ctex"'
	Write-EditorImportDiagnostics -Phase "synthetic crash fixture" -LogPath $logPath -ExitCode $exitCode 6> $null
	$diagnostics = Get-Content -Raw "$logPath.diagnostics.json" | ConvertFrom-Json
	$svg = $diagnostics.svg_imports | Where-Object source -eq 'assets/BezierHandlesLinked.svg'
	Assert-Diagnostic ($svg.source_exists -and $svg.import_metadata_exists -and -not $svg.imported_resource_exists) "Missing generated texture was not distinguished from its source."
	$failure = ""
	try { Stop-ArchivePhase -Phase "initial import" -LogPath $logPath -ExitCode $exitCode 6> $null }
	catch { $failure = $_.Exception.Message }
	Assert-Diagnostic ($failure.Contains('initial import') -and $failure.Contains('-1073741819') -and $failure.Contains($logPath)) "Failure omitted phase, status, or retained log path."
	Write-Host "PASS: archive diagnostics retain crash status, process output, errors, and missing import evidence."
}
finally {
	$resolvedRoot = [IO.Path]::GetFullPath($validationRoot)
	$expectedPrefix = [IO.Path]::GetFullPath((Join-Path $projectRoot "test/_temp")) + [IO.Path]::DirectorySeparatorChar
	if (-not $resolvedRoot.StartsWith($expectedPrefix, [StringComparison]::OrdinalIgnoreCase)) {
		throw "Refusing cleanup outside test/_temp: $resolvedRoot"
	}
	Remove-Item -LiteralPath $resolvedRoot -Recurse -Force
}

[CmdletBinding()]
param([string]$GodotPath = "", [switch]$UpdateSamples)

$ErrorActionPreference = "Stop"
$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot "../..")).Path
$hostRoot = Join-Path $projectRoot ("test/_temp/documentation-" + [guid]::NewGuid().ToString("N"))
$launcher = Join-Path $PSScriptRoot "run_godot.ps1"
$passed = $false

try {
	New-Item -ItemType Directory -Force -Path "$hostRoot/addons/easing_curve", "$hostRoot/test/scripts/unit", "$hostRoot/test/scripts/support", "$hostRoot/test/scripts/docs", "$hostRoot/test/_temp" | Out-Null
	foreach ($directory in @("scripts", "assets", "examples")) {
		Copy-Item -LiteralPath "$projectRoot/addons/easing_curve/$directory" -Destination "$hostRoot/addons/easing_curve" -Recurse
	}
	Copy-Item -LiteralPath "$projectRoot/docs" -Destination $hostRoot -Recurse
	Copy-Item -LiteralPath "$projectRoot/test/scripts/unit/practical_examples_test.gd" -Destination "$hostRoot/test/scripts/unit"
	Copy-Item -LiteralPath "$projectRoot/test/scripts/support/test_case.gd" -Destination "$hostRoot/test/scripts/support"
	Copy-Item -LiteralPath "$projectRoot/test/scripts/docs/export_doc_samples.gd" -Destination "$hostRoot/test/scripts/docs"
	@'
config_version=5
[application]
config/name="Easing Curve Documentation Tests"
config/features=PackedStringArray("4.7", "GL Compatibility")
[rendering]
renderer/rendering_method="gl_compatibility"
'@ | Set-Content -LiteralPath "$hostRoot/project.godot" -Encoding utf8
	$runs = @(
		@{ Name = "import"; Args = @("--editor", "--headless", "--import"); Pass = $false },
		@{ Name = "examples"; Args = @("--headless", "--script", "res://test/scripts/unit/practical_examples_test.gd"); Pass = $true },
		@{ Name = "samples"; Args = @("--headless", "--script", "res://test/scripts/docs/export_doc_samples.gd"); Pass = $true }
	)
	foreach ($run in $runs) {
		$log = "$hostRoot/test/_temp/$($run.Name).log"
		$runArguments = @("--path", $hostRoot, "--log-file", $log) + $run.Args
		if ($run.Name -eq "samples" -and $UpdateSamples) { $runArguments += @("--", "--write") }
		& $launcher -GodotPath $GodotPath -TimeoutSeconds 60 -GodotArgs $runArguments
		if ($LASTEXITCODE -ne 0) { throw "$($run.Name) failed with exit code $LASTEXITCODE" }
		$output = Get-Content -LiteralPath $log -Raw
		$unexpectedErrors = $output -split "`n" | Where-Object { $_ -match '^(SCRIPT ERROR:|ERROR:)' -and $_ -notmatch '^ERROR: Failed to read the root certificate store\.' }
		if ($unexpectedErrors) { throw "$($run.Name) reported: $unexpectedErrors" }
		if ($run.Pass -and $output -notmatch 'PASS:') { throw "$($run.Name) did not report PASS" }
	}
	if ($UpdateSamples) { Copy-Item -LiteralPath "$hostRoot/docs/curve_samples.js" -Destination "$projectRoot/docs/curve_samples.js" -Force }
	& node --check "$projectRoot/docs/site.js"
	if ($LASTEXITCODE -ne 0) { throw "Documentation JavaScript syntax failed" }
	& node "$projectRoot/test/scripts/docs/site_test.cjs"
	if ($LASTEXITCODE -ne 0) { throw "Documentation checks failed" }
	$passed = $true
	Write-Host "PASS: portable examples and documentation"
} finally {
	if ($passed) {
		$resolved = (Resolve-Path -LiteralPath $hostRoot).Path
		$allowed = (Resolve-Path -LiteralPath "$projectRoot/test/_temp").Path + [IO.Path]::DirectorySeparatorChar
		if (-not $resolved.StartsWith($allowed, [StringComparison]::OrdinalIgnoreCase)) { throw "Refusing cleanup outside test/_temp" }
		Remove-Item -LiteralPath $resolved -Recurse -Force
	} else {
		Write-Warning "Failure diagnostics retained at $hostRoot"
	}
}

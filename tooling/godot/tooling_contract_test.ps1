$ErrorActionPreference = 'Stop'
. "$PSScriptRoot/../../test/runners/godot_process_contract.ps1"
. "$PSScriptRoot/build_toolchain.ps1"
$pin = & "$PSScriptRoot/read_manifest.ps1"
$root = (Resolve-Path "$PSScriptRoot/../..").Path
$temp = Join-Path $root ('test/_temp/tooling-contract-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $temp | Out-Null

# A wrong archive must never become an available qualification input.
& {
	$bytes = [byte[]](0..255)
	[IO.File]::WriteAllBytes("$temp/original.zip", $bytes)
	$fixturePin = $pin | ConvertTo-Json -Depth 8 | ConvertFrom-Json
	$fixturePin.historical_archive.url = 'https://github.com/BaconEggsRL/easing_curve/releases/download/synthetic/input.zip'
	function Invoke-WebRequest { param($Uri, $OutFile) Copy-Item "$temp/original.zip" $OutFile }
	$previousGithubEnv = $env:GITHUB_ENV
	try {
		$env:GITHUB_ENV = ''
		foreach ($valid in @($false, $true)) {
			$fixturePin.historical_archive.sha256 = if ($valid) { (Get-FileHash "$temp/original.zip").Hash } else { '0' * 64 }
			$fixturePin | ConvertTo-Json -Depth 8 | Set-Content "$temp/pin.json"
			$accepted = $false
			try { & "$PSScriptRoot/download_historical_archive.ps1" -ManifestPath "$temp/pin.json" -Destination "$temp/download" | Out-Null; $accepted=$true } catch { if ($valid) { throw } }
			if ($accepted -ne $valid -or (Test-Path "$temp/download/input.zip") -ne $valid) { throw 'An unverified historical input was made available.' }
		}
		if ((Get-FileHash "$temp/download/input.zip").Hash -ne (Get-FileHash "$temp/original.zip").Hash) { throw 'Historical bytes changed.' }
	} finally { $env:GITHUB_ENV = $previousGithubEnv }
}

# Validate resolved values, not merely a request for those values.
& {
	function Invoke-FakePython { param($c) $global:LASTEXITCODE=0; $script:pythonVersion }
	foreach ($version in @($pin.build_toolchain.python_version, '0.0.0')) {
		$script:pythonVersion=$version
		$accepted=$false
		try { Assert-QualifiedPython 'Invoke-FakePython' $pin.build_toolchain | Out-Null; $accepted=$true } catch { if ($version -eq $pin.build_toolchain.python_version) { throw } }
		if ($accepted -ne ($version -eq $pin.build_toolchain.python_version)) { throw 'Python version drift was accepted.' }
	}
	function Test-Path { return $true }
	function Get-Item { param($LiteralPath) return [pscustomobject]@{ FullName=$LiteralPath; VersionInfo=@{FileVersion=$script:compilerVersion} } }
	$environment = [ordered]@{
		MSVC_VERSION=$pin.build_toolchain.msvc_version
		MSVC_SDK_VERSION=$pin.build_toolchain.windows_sdk_version
		ENV=@{ PATH=$temp; VCToolsInstallDir="C:/synthetic/$($pin.build_toolchain.msvc_toolset_version)/"; INCLUDE="C:/SDK/include/$($pin.build_toolchain.windows_sdk_version)/um" }
	}
	$environment | ConvertTo-Json -Depth 5 | Set-Content "$temp/scons-env.json"
	foreach ($version in @($pin.build_toolchain.compiler_file_version, '0.0.0.0')) {
		$script:compilerVersion=$version
		$accepted=$false
		try { Get-QualifiedResolvedToolchain "$temp/scons-env.json" $pin.build_toolchain | Out-Null; $accepted=$true } catch { if ($version -eq $pin.build_toolchain.compiler_file_version) { throw } }
		if ($accepted -ne ($version -eq $pin.build_toolchain.compiler_file_version)) { throw 'Compiler version drift was accepted.' }
	}
	$script:compilerVersion=$pin.build_toolchain.compiler_file_version
	$environment.ENV.INCLUDE='C:/SDK/include/10.0.99999.0/um'
	$environment | ConvertTo-Json -Depth 5 | Set-Content "$temp/scons-env.json"
	$accepted=$false
	try { Get-QualifiedResolvedToolchain "$temp/scons-env.json" $pin.build_toolchain | Out-Null; $accepted=$true } catch {}
	if ($accepted) { throw 'Wrong resolved SDK include paths were accepted.' }
}

$workflows = @('native-build.yml', 'qualify-godot-editor.yml', 'import-crash-diagnostics.yml')
foreach ($workflow in $workflows) {
	$text = Get-Content "$root/.github/workflows/$workflow" -Raw
	if ($text -match 'run-id:\s*34299688373|version:\s*4[.]7[.]1|gh release download tooling-godot-') { throw "Uncentralized or expiring workflow input: $workflow" }
}
$historicalWorkflow = Get-Content "$root/.github/workflows/import-crash-diagnostics.yml" -Raw
if ($historicalWorkflow -match '(?m)^  push:') { throw 'Historical crash tooling must be manual-only.' }
foreach ($file in @('run_native_release_export_test.ps1', 'run_native_web_export_test.ps1')) {
	$text = Get-Content "$root/test/runners/$file" -Raw
	if ($text -notmatch 'editor-pin.json.*export_template_version' -or $text -match 'templateVersion\s*=.*godotVersion') { throw "Export templates were inferred from editor identity: $file" }
}
Write-Host "PASS: historical checksum enforcement, resolved toolchain drift rejection, and centralized workflow/template pins."
$resolvedTemp = [IO.Path]::GetFullPath($temp)
$expectedPrefix = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../test/_temp')) + [IO.Path]::DirectorySeparatorChar
if (-not $resolvedTemp.StartsWith($expectedPrefix, [StringComparison]::OrdinalIgnoreCase)) { throw "Unsafe cleanup path: $resolvedTemp" }
Remove-Item -LiteralPath $resolvedTemp -Recurse -Force
exit 0

[CmdletBinding()]
param([int]$Jobs = 16, [string]$PythonPath = 'python', [string]$OutputName = 'godot-candidate-v2', [switch]$ResumeBuild)
$ErrorActionPreference = 'Stop'
$root = (Resolve-Path "$PSScriptRoot/../..").Path
$pin = Get-Content "$PSScriptRoot/editor-pin.json" -Raw | ConvertFrom-Json
$output = Join-Path $root "test/_temp/$OutputName"
$source = Join-Path $output 'source'
$patch = Join-Path $PSScriptRoot $pin.patch
$tempPrefix = [IO.Path]::GetFullPath((Join-Path $root 'test/_temp')) + [IO.Path]::DirectorySeparatorChar
if (-not [IO.Path]::GetFullPath($output).StartsWith($tempPrefix, [StringComparison]::OrdinalIgnoreCase)) { throw 'Build output must be inside test/_temp.' }
if ((Test-Path $output) -and -not $ResumeBuild) { throw "Candidate output already exists; preserve it and use a fresh checkout: $output" }
if (Test-Path "$output/control/godot-editor.exe") { throw 'Do not rebuild completed candidate bytes.' }
New-Item -ItemType Directory -Path $source -Force | Out-Null
function Invoke-Checked {
	param([string]$Program, [string[]]$Arguments)
	& $Program @Arguments
	if ($LASTEXITCODE -ne 0) { throw "$Program failed with exit $LASTEXITCODE" }
}
Push-Location $source
$previousLocalAppData = $env:LOCALAPPDATA
try {
	Invoke-Checked $PythonPath @('-m', 'venv', "$output/build-tools")
	$buildPython = "$output/build-tools/Scripts/python.exe"
	Invoke-Checked $buildPython @('-m', 'pip', 'install', 'scons==4.11.1')
	if (-not (Test-Path '.git')) {
		Invoke-Checked git @('init')
		Invoke-Checked git @('remote', 'add', 'origin', 'https://github.com/godotengine/godot.git')
		Invoke-Checked git @('fetch', '--depth=1', 'origin', $pin.source_commit)
		Invoke-Checked git @('checkout', '--detach', 'FETCH_HEAD')
	}
	if ((git rev-parse HEAD).Trim() -ne $pin.source_commit) { throw 'Unexpected Godot source commit.' }
	if (git diff --name-only) { throw 'Source must be clean before the control build.' }
	$env:LOCALAPPDATA = "$output/dependencies"
	Invoke-Checked $buildPython @('misc/scripts/install_accesskit.py')
	Invoke-Checked $buildPython @('misc/scripts/install_d3d12_sdk_windows.py')
	$argsList = @("-j$Jobs", 'platform=windows', 'target=editor', 'arch=x86_64', 'production=yes', 'lto=none', 'debug_symbols=yes')
	foreach ($variant in @('control', 'patched')) {
		$destination = Join-Path $output $variant
		New-Item -ItemType Directory -Path $destination -Force | Out-Null
		if ($variant -eq 'patched') {
			Invoke-Checked git @('apply', '--check', $patch)
			Invoke-Checked git @('apply', $patch)
			$changed = @(git diff --name-only)
			if ($changed.Count -ne 1 -or $changed[0] -ne 'editor/doc/editor_help.cpp') { throw 'Unexpected patch scope.' }
		}
		$env:BUILD_NAME = if ($variant -eq 'patched') { 'ec111645-p1' } else { 'ec111645-control' }
		# A clean build prevents stale version strings in incremental/unity objects.
		& $buildPython -m SCons @argsList --clean *> "$destination/clean.log"
		if ($LASTEXITCODE -ne 0) { throw "Could not clean the $variant build." }
		& $buildPython -m SCons @argsList *> "$destination/build.log"
		if ($LASTEXITCODE -ne 0) { throw "Godot $variant build failed; see $destination/build.log" }
		Copy-Item 'bin/godot.windows.editor.x86_64.exe' "$destination/godot-editor.exe"
		Get-ChildItem bin -Filter '*.pdb' | Copy-Item -Destination $destination
		Copy-Item COPYRIGHT.txt "$destination/COPYRIGHT.txt"
		Copy-Item LICENSE.txt "$destination/LICENSE.txt"
		Copy-Item $patch "$destination/editor-help-lifetime.patch"
		git diff --binary | Set-Content "$destination/applied.diff"
		$version = (& "$destination/godot-editor.exe" --version --log-file "$destination/version.log" | Out-String).Trim()
		if ($LASTEXITCODE -ne 0) { throw 'Candidate version query failed.' }
		[ordered]@{
			source_commit=$pin.source_commit; source_tag=$pin.source_tag; variant=$variant; version=$version
			executable_sha256=(Get-FileHash "$destination/godot-editor.exe").Hash
			patch_sha256=(Get-FileHash $patch).Hash; build_name=$env:BUILD_NAME
			command=@('python', '-m', 'SCons') + $argsList; scons=(& $buildPython -m SCons --version | Out-String).Trim()
			python=(& $buildPython --version | Out-String).Trim(); os=[Environment]::OSVersion.VersionString
			visual_studio=(& "${env:ProgramFiles(x86)}/Microsoft Visual Studio/Installer/vswhere.exe" -latest -products '*' -format json | Out-String | ConvertFrom-Json)
			windows_sdk=@(Get-ChildItem "${env:ProgramFiles(x86)}/Windows Kits/10/Include" -Directory | Select-Object -ExpandProperty Name)
			symbols=@(Get-ChildItem $destination -Filter '*.pdb' | ForEach-Object { @{name=$_.Name; sha256=(Get-FileHash $_.FullName).Hash} })
		} | ConvertTo-Json -Depth 8 | Set-Content "$destination/provenance.json"
	}
} finally {
	$env:LOCALAPPDATA = $previousLocalAppData
	Remove-Item Env:BUILD_NAME -ErrorAction SilentlyContinue
	Pop-Location
}

[CmdletBinding()]
param([int]$Jobs = 16, [string]$PythonPath = 'python', [string]$OutputName = 'godot-candidate-v2', [switch]$ResumeBuild)
$ErrorActionPreference = 'Stop'
$root = (Resolve-Path "$PSScriptRoot/../..").Path
$pin = Get-Content "$PSScriptRoot/editor-pin.json" -Raw | ConvertFrom-Json
. "$PSScriptRoot/build_toolchain.ps1"
. "$PSScriptRoot/../../test/runners/godot_process_contract.ps1"
$pythonVersion = Assert-QualifiedPython $PythonPath $pin.build_toolchain
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
	Invoke-Checked $buildPython @('-m', 'pip', 'install', "scons==$($pin.build_toolchain.scons_version)")
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
	$argsList += @("msvc_version=$($pin.build_toolchain.msvc_version)", "mssdk_version=$($pin.build_toolchain.windows_sdk_version)")
	foreach ($variant in @('control', 'patched')) {
		$destination = Join-Path $output $variant
		New-Item -ItemType Directory -Path $destination -Force | Out-Null
		if ($variant -eq 'patched') {
			Invoke-Checked git @('apply', '--check', $patch)
			Invoke-Checked git @('apply', $patch)
			$changed = @(git diff --name-only)
			if ($changed.Count -ne 1 -or $changed[0] -ne 'editor/doc/editor_help.cpp') { throw 'Unexpected patch scope.' }
		}
		$env:BUILD_NAME = if ($variant -eq 'patched') { $pin.build_name } else { $pin.control_build_name }
		# A clean build prevents stale version strings in incremental/unity objects.
		& $buildPython -m SCons @argsList --clean *> "$destination/clean.log"
		if ($LASTEXITCODE -ne 0) { throw "Could not clean the $variant build." }
		& $buildPython -m SCons @argsList --dry-run *> "$destination/configure.log"
		if ($LASTEXITCODE -ne 0) { throw "Could not configure the $variant build." }
		$toolchain = Get-QualifiedResolvedToolchain "$source/.scons_env.json" $pin.build_toolchain
		$toolchain | ConvertTo-Json -Depth 4 | Set-Content "$destination/resolved-toolchain.json"
		& $buildPython -m SCons @argsList *> "$destination/build.log"
		if ($LASTEXITCODE -ne 0) { throw "Godot $variant build failed; see $destination/build.log" }
		$toolchain = Get-QualifiedResolvedToolchain "$source/.scons_env.json" $pin.build_toolchain
		Copy-Item 'bin/godot.windows.editor.x86_64.exe' "$destination/godot-editor.exe"
		Get-ChildItem bin -Filter '*.pdb' | Copy-Item -Destination $destination
		Copy-Item COPYRIGHT.txt "$destination/COPYRIGHT.txt"
		Copy-Item LICENSE.txt "$destination/LICENSE.txt"
		Copy-Item $patch "$destination/editor-help-lifetime.patch"
		git diff --binary | Set-Content "$destination/applied.diff"
		$version = Get-GodotVersion -ExecutablePath "$destination/godot-editor.exe" -LogPath "$destination/version.log"
		[ordered]@{
			source_commit=$pin.source_commit; source_tag=$pin.source_tag; variant=$variant; version=$version
			executable_sha256=(Get-FileHash "$destination/godot-editor.exe").Hash
			patch_sha256=(Get-FileHash $patch).Hash; build_name=$env:BUILD_NAME
			command=@('python', '-m', 'SCons') + $argsList; scons=(& $buildPython -m SCons --version | Out-String).Trim()
			python=$pythonVersion; python_path=(Resolve-Path $buildPython).Path; os=[Environment]::OSVersion.VersionString
			resolved_toolchain=$toolchain
			symbols=@(Get-ChildItem $destination -Filter '*.pdb' | ForEach-Object { @{name=$_.Name; sha256=(Get-FileHash $_.FullName).Hash} })
		} | ConvertTo-Json -Depth 8 | Set-Content "$destination/provenance.json"
	}
} finally {
	$env:LOCALAPPDATA = $previousLocalAppData
	Remove-Item Env:BUILD_NAME -ErrorAction SilentlyContinue
	Pop-Location
}

function Assert-QualifiedPython {
	param([string]$PythonPath, [object]$Expected)
	$version = (& $PythonPath -c 'import platform; print(platform.python_version())' | Out-String).Trim()
	if ($LASTEXITCODE -ne 0 -or $version -ne $Expected.python_version) {
		throw "Candidate builds require Python $($Expected.python_version); resolved '$version' from $PythonPath."
	}
	return $version
}

function Get-QualifiedResolvedToolchain {
	param([string]$EnvironmentPath, [object]$Expected)
	# Godot dumps the actual SCons environment after configuration, including in dry-run mode.
	$resolved = Get-Content -LiteralPath $EnvironmentPath -Raw | ConvertFrom-Json -AsHashtable
	$compiler = $null
	foreach ($directory in ($resolved['ENV']['PATH'] -split ';')) {
		$candidate = Join-Path $directory 'cl.exe'
		if (Test-Path -LiteralPath $candidate -PathType Leaf) { $compiler = Get-Item -LiteralPath $candidate; break }
	}
	if (-not $compiler) { throw 'The configured SCons environment did not resolve cl.exe.' }
	$toolset = Split-Path ($resolved['ENV']['VCToolsInstallDir'].TrimEnd('\', '/')) -Leaf
	$sdkPaths = @([regex]::Matches($resolved['ENV']['INCLUDE'], '(?i)[\\/]+include[\\/]+(10[.]\d+[.]\d+[.]\d+)[\\/]') | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique)
	$actual = [ordered]@{
		msvc_version = $resolved['MSVC_VERSION']
		msvc_toolset_version = $toolset
		compiler_file_version = $compiler.VersionInfo.FileVersion
		compiler_path = $compiler.FullName
		windows_sdk_version = $resolved['MSVC_SDK_VERSION']
		windows_sdk_include_versions = $sdkPaths
	}
	foreach ($key in @('msvc_version', 'msvc_toolset_version', 'compiler_file_version', 'windows_sdk_version')) {
		if ($actual[$key] -ne $Expected.$key) { throw "Qualified build toolchain mismatch for ${key}: expected $($Expected.$key), resolved $($actual[$key])." }
	}
	if ($sdkPaths.Count -ne 1 -or $sdkPaths[0] -ne $Expected.windows_sdk_version) { throw 'The compiler include paths do not select the qualified Windows SDK.' }
	return [pscustomobject]$actual
}

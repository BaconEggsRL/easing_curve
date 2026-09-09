function Test-GodotEditorInvocation {
	param([string[]]$Arguments)
	foreach ($argument in $Arguments) {
		if ($argument -eq '--') { break }
		if (($argument -split '=', 2)[0] -cin @('-e', '--editor', '--import', '--export-release', '--export-debug', '--export-pack', '--export-patch')) { return $true }
	}
	return $false
}

function Assert-GodotProcessExit {
	param([AllowNull()][object]$ExitCode, [string]$Phase, [string]$LogPath)
	$signed = 0
	if ($null -eq $ExitCode -or -not [int]::TryParse([string]$ExitCode, [ref]$signed)) {
		throw "$Phase failed: missing or malformed Godot exit status '$ExitCode'. Diagnostics: $LogPath"
	}
	$hex = '0x{0:X8}' -f ([long]$signed -band 0xFFFFFFFFL)
	if ($signed -ne 0) { throw "$Phase failed: Godot exit $signed ($hex). Diagnostics retained: $LogPath" }
}

function Assert-GodotExecutableHash {
	param([string]$Path, [string]$ExpectedHash)
	if ($ExpectedHash -notmatch '^[A-Fa-f0-9]{64}$') { throw 'A pinned editor requires an explicit SHA256.' }
	$actual = (Get-FileHash -LiteralPath $Path -Algorithm SHA256 -ErrorAction Stop).Hash
	if ($actual -ine $ExpectedHash) { throw "Godot executable checksum mismatch: $Path. Expected $ExpectedHash; got $actual" }
	return $actual
}

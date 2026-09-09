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

function Resolve-GodotExecutable {
	param(
		[string]$GodotPath = '', [string[]]$Arguments = @(),
		[string]$PinnedEditorPath = '', [string]$PinnedEditorSha256 = '',
		[switch]$PreferGui
	)
	$editorRole = Test-GodotEditorInvocation $Arguments
	if (-not $PinnedEditorPath) { $PinnedEditorPath = $env:EASING_CURVE_EDITOR_GODOT_PATH }
	if (-not $PinnedEditorSha256) { $PinnedEditorSha256 = $env:EASING_CURVE_EDITOR_GODOT_SHA256 }
	if ($editorRole -and $PinnedEditorSha256 -and [string]::IsNullOrWhiteSpace($PinnedEditorPath)) {
		throw 'A pinned editor hash was configured without an editor path. No fallback is allowed.'
	}
	$pinned = $editorRole -and -not [string]::IsNullOrWhiteSpace($PinnedEditorPath)
	$source = 'explicit -GodotPath'
	if ($pinned) {
		Assert-GodotExecutableHash $PinnedEditorPath $PinnedEditorSha256 | Out-Null
		$GodotPath = $PinnedEditorPath
		$source = 'pinned editor invocation'
	} elseif ([string]::IsNullOrWhiteSpace($GodotPath)) {
		$GodotPath = $env:EASING_CURVE_GODOT_PATH
		$source = 'EASING_CURVE_GODOT_PATH'
	}
	if ([string]::IsNullOrWhiteSpace($GodotPath)) {
		$command = Get-Command godot -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
		if ($command) { $GodotPath = $command.Source; $source = 'PATH' }
	}
	if ([string]::IsNullOrWhiteSpace($GodotPath) -or -not (Test-Path -LiteralPath $GodotPath -PathType Leaf)) {
		throw "Godot executable was not found: $GodotPath. Supply -GodotPath or EASING_CURVE_GODOT_PATH."
	}
	$path = (Resolve-Path -LiteralPath $GodotPath -ErrorAction Stop).Path
	if (-not $pinned) {
		$name = [IO.Path]::GetFileNameWithoutExtension($path)
		$companion = ''
		if ($PreferGui -and $name.EndsWith('_console', [StringComparison]::OrdinalIgnoreCase)) {
			$companion = $path -replace '_console\.exe$', '.exe'
		} elseif (-not $PreferGui -and -not $name.EndsWith('_console', [StringComparison]::OrdinalIgnoreCase)) {
			$companion = Join-Path ([IO.Path]::GetDirectoryName($path)) ($name + '_console.exe')
		}
		if ($companion -and (Test-Path -LiteralPath $companion -PathType Leaf)) {
			$path = (Resolve-Path -LiteralPath $companion).Path
			$source += ', companion'
		}
	}
	return [pscustomobject]@{ Path=$path; Source=$source; IsEditor=$editorRole; IsPinnedEditor=$pinned }
}

function Get-GodotVersion {
	param([Parameter(Mandatory)][string]$ExecutablePath, [Parameter(Mandatory)][string]$LogPath, [ValidateRange(1,300)][int]$TimeoutSeconds = 30)
	New-Item -ItemType Directory -Force -Path (Split-Path -Parent $LogPath) | Out-Null
	$start = [Diagnostics.ProcessStartInfo]::new()
	$start.FileName = $ExecutablePath
	$start.UseShellExecute = $false
	$start.CreateNoWindow = $true
	$start.RedirectStandardOutput = $true
	$start.RedirectStandardError = $true
	foreach ($argument in @('--version', '--log-file', $LogPath)) { $start.ArgumentList.Add($argument) }
	try { $process = [Diagnostics.Process]::Start($start) }
	catch { $_ | Out-String | Set-Content "$LogPath.launch-error.txt"; throw }
	try {
		$stdoutTask = $process.StandardOutput.ReadToEndAsync()
		$stderrTask = $process.StandardError.ReadToEndAsync()
		$timedOut = -not $process.WaitForExit($TimeoutSeconds * 1000)
		if ($timedOut) { $process.Kill($true); $process.WaitForExit() }
		$stdout = $stdoutTask.GetAwaiter().GetResult()
		$stderr = $stderrTask.GetAwaiter().GetResult()
		$stdout | Set-Content "$LogPath.stdout.txt"
		$stderr | Set-Content "$LogPath.stderr.txt"
		[ordered]@{ executable=$ExecutablePath; arguments=@('--version','--log-file',$LogPath); signed_exit=$process.ExitCode; hex_exit=('0x{0:X8}' -f ([long]$process.ExitCode -band 0xFFFFFFFFL)); timed_out=$timedOut } |
			ConvertTo-Json | Set-Content "$LogPath.process.json"
		if ($timedOut) { throw "Godot identity probe timed out. Diagnostics: $LogPath" }
		Assert-GodotProcessExit $process.ExitCode 'Godot identity probe' $LogPath
		if ([string]::IsNullOrWhiteSpace($stdout)) { throw "Godot identity probe returned no version. Diagnostics: $LogPath" }
		return $stdout.Trim()
	} finally { $process.Dispose() }
}

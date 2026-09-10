$ErrorActionPreference = 'Stop'
. "$PSScriptRoot/godot_process_contract.ps1"
$root = (Resolve-Path "$PSScriptRoot/../..").Path
$temp = Join-Path $root ("test/_temp/process-contract-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory $temp | Out-Null
$source = @'
using System;
using System.IO;
using System.Threading;
class FakeGodot {
    static int Main(string[] args) {
        string trace = Environment.GetEnvironmentVariable("FAKE_GODOT_TRACE");
        if (!String.IsNullOrEmpty(trace)) File.AppendAllText(trace, Environment.GetCommandLineArgs()[0] + " " + String.Join(" ", args) + "\n");
        if (Array.IndexOf(args, "--version") >= 0) {
            Console.WriteLine("4.7.1.stable.contract-test");
            int versionExit; return Int32.TryParse(Environment.GetEnvironmentVariable("FAKE_GODOT_VERSION_EXIT"), out versionExit) ? versionExit : 0;
        }
        int delay; if (Int32.TryParse(Environment.GetEnvironmentVariable("FAKE_GODOT_DELAY"), out delay)) Thread.Sleep(delay);
        Console.WriteLine("PASS: complete synthetic semantic result set");
        Console.Error.WriteLine("synthetic stderr retained");
        int code; return Int32.TryParse(Environment.GetEnvironmentVariable("FAKE_GODOT_EXIT"), out code) ? code : 0;
    }
}
'@
$source | Set-Content "$temp/fake.cs"
& "$env:WINDIR/Microsoft.NET/Framework64/v4.0.30319/csc.exe" /nologo /target:exe "/out:$temp\runtime.exe" "$temp\fake.cs"
if ($LASTEXITCODE -ne 0) { throw 'Could not compile process test fixture.' }
Copy-Item "$temp/runtime.exe" "$temp/editor.exe"
$sha = (Get-FileHash "$temp/editor.exe").Hash
$pwsh = (Get-Process -Id $PID).Path
function Assert-Test { param([bool]$Condition, [string]$Message) if (-not $Condition) { throw $Message } }
$oldPath = $env:EASING_CURVE_EDITOR_GODOT_PATH
$oldHash = $env:EASING_CURVE_EDITOR_GODOT_SHA256
try {
	$env:EASING_CURVE_EDITOR_GODOT_PATH = "$temp/editor.exe"
	$env:EASING_CURVE_EDITOR_GODOT_SHA256 = $sha
	foreach ($code in @(0, 1, -1073741819)) {
		$env:FAKE_GODOT_VERSION_EXIT = [string]$code
		$accepted = $false
		try { $version = Get-GodotVersion -ExecutablePath "$temp/runtime.exe" -LogPath "$temp/identity.log"; $accepted = $true } catch { if ($code -eq 0) { throw } }
		Assert-Test ($accepted -eq ($code -eq 0)) 'Nonempty version output hid an identity-process failure.'
		$identity = Get-Content "$temp/identity.log.process.json" -Raw | ConvertFrom-Json
		Assert-Test ($identity.signed_exit -eq $code) 'Identity failure lost its native exit status.'
	}
	$env:FAKE_GODOT_VERSION_EXIT = '0'
	$env:EASING_CURVE_EDITOR_GODOT_PATH = ''
	$rejected = $false
	try { Resolve-GodotExecutable -GodotPath "$temp/runtime.exe" -Arguments @('--editor') -PreferGui | Out-Null } catch { $rejected = $true }
	Assert-Test $rejected 'GUI editor selection silently fell back with a configured SHA but no path.'
	$env:EASING_CURVE_EDITOR_GODOT_PATH = "$temp/editor.exe"
	Copy-Item "$temp/runtime.exe" "$temp/editor_console.exe"
	$selected = Resolve-GodotExecutable -GodotPath "$temp/runtime.exe" -Arguments @('--editor')
	Assert-Test ($selected.Path -eq (Resolve-Path "$temp/editor.exe").Path) 'Pinned editor was replaced by its companion.'
	Assert-Test (-not (Test-GodotEditorInvocation @('--headless', '--', '--editor'))) 'User arguments changed the invocation role.'
	foreach ($roleArgs in @(@('--editor','--headless'), @('--import'), @('--headless','--export-release','Windows','game.exe'), @('--headless','--script','test.gd'))) {
		$env:FAKE_GODOT_TRACE = "$temp/trace-$([guid]::NewGuid().ToString('N')).txt"
		& $pwsh -NoProfile -File "$PSScriptRoot/run_godot.ps1" -GodotPath "$temp/runtime.exe" -AppDataDirectory "$temp/appdata" --log-file "$temp/test.log" @roleArgs > "$temp/launcher.txt"
		Assert-Test ($LASTEXITCODE -eq 0) 'Role fixture failed.'
		$record = Get-Content "$temp/appdata/process.json" -Raw | ConvertFrom-Json
		$expected = if ($roleArgs -contains '--script' -or $roleArgs -contains '--') { 'runtime.exe' } else { 'editor.exe' }
		Assert-Test ([IO.Path]::GetFileName($record.executable) -eq $expected) "Wrong executable for $roleArgs"
	}
	foreach ($code in @(0, 1, -1073741819, -1073740791)) {
		$env:FAKE_GODOT_EXIT = [string]$code
		& $pwsh -NoProfile -File "$PSScriptRoot/run_godot.ps1" -GodotPath "$temp/runtime.exe" -AppDataDirectory "$temp/appdata" -ExitCodeFile "$temp/exit.txt" --headless --script test.gd --log-file "$temp/test.log" > "$temp/launcher.txt"
		$launcherExit = $LASTEXITCODE
		Assert-Test ($launcherExit -eq $code -and (Get-Content "$temp/exit.txt") -eq [string]$code) 'Native signed exit status changed.'
		$continued = $false
		try { Assert-GodotProcessExit (Get-Content "$temp/exit.txt") 'synthetic complete results' "$temp/test.log"; $continued = $true } catch { if ($code -eq 0) { throw } }
		Assert-Test ($continued -eq ($code -eq 0)) 'Semantic success overrode process failure.'
		Assert-Test ((Get-Content "$temp/appdata/process.stderr.txt" -Raw) -match 'synthetic stderr') 'Failure output missing.'
	}
	foreach ($invalid in @($null, '', 'timeout', 'garbage', '4294967296')) {
		$failed = $false
		try { Assert-GodotProcessExit $invalid 'missing status' $temp } catch { $failed = $true }
		Assert-Test $failed "Accepted invalid status: $invalid"
	}
	$env:FAKE_GODOT_EXIT = '0'
	$env:FAKE_GODOT_DELAY = '5000'
	& $pwsh -NoProfile -File "$PSScriptRoot/run_godot.ps1" -GodotPath "$temp/runtime.exe" -TimeoutSeconds 1 -AppDataDirectory "$temp/appdata" --headless --log-file "$temp/test.log" > "$temp/launcher.txt"
	Assert-Test ($LASTEXITCODE -ne 0 -and (Get-Content "$temp/appdata/process.json" -Raw | ConvertFrom-Json).timed_out) 'Timeout accepted.'
	$env:FAKE_GODOT_TRACE = "$temp/must-not-execute.txt"
	$env:EASING_CURVE_EDITOR_GODOT_SHA256 = '0' * 64
	& $pwsh -NoProfile -File "$PSScriptRoot/run_godot.ps1" -GodotPath "$temp/runtime.exe" --editor --headless --log-file "$temp/test.log" *> "$temp/checksum-rejection.txt"
	Assert-Test ($LASTEXITCODE -ne 0 -and -not (Test-Path $env:FAKE_GODOT_TRACE)) 'Unverified executable ran or silently fell back.'
	Write-Host "PASS: executable roles, checksum rejection, signed crashes, malformed status and timeouts."
} finally {
	$env:EASING_CURVE_EDITOR_GODOT_PATH = $oldPath
	$env:EASING_CURVE_EDITOR_GODOT_SHA256 = $oldHash
	Remove-Item Env:FAKE_GODOT_EXIT,Env:FAKE_GODOT_DELAY,Env:FAKE_GODOT_TRACE,Env:FAKE_GODOT_VERSION_EXIT -ErrorAction SilentlyContinue
}
$resolvedTemp = [IO.Path]::GetFullPath($temp)
$expectedPrefix = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../test/_temp')) + [IO.Path]::DirectorySeparatorChar
if (-not $resolvedTemp.StartsWith($expectedPrefix, [StringComparison]::OrdinalIgnoreCase)) { throw "Unsafe cleanup path: $resolvedTemp" }
Remove-Item -LiteralPath $resolvedTemp -Recurse -Force
exit 0

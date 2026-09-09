[CmdletBinding()]
param(
	[Parameter(Mandatory)][string]$GodotPath,
	[Parameter(Mandatory)][string]$ArchivePath,
	[string]$ProcDumpPath = "",
	[string]$OutputDirectory = "",
	[ValidateSet('A','B','C','D','E')][string[]]$Cases = @('A','B','C','D','E')
)

# Temporary investigation only. This is not a release acceptance gate.
$ErrorActionPreference = "Stop"
$repo = (Resolve-Path (Join-Path $PSScriptRoot "../..")).Path
$outputRoot = if ($OutputDirectory) { [IO.Path]::GetFullPath($OutputDirectory) } else { Join-Path $repo "test/_temp/import-crash-diagnostics" }
if (Test-Path $outputRoot) { throw "Use a fresh diagnostic output directory: $outputRoot" }
New-Item -ItemType Directory -Path $outputRoot | Out-Null
$GodotPath = (Resolve-Path -LiteralPath $GodotPath).Path
$ArchivePath = (Resolve-Path -LiteralPath $ArchivePath).Path
$powerShell = (Get-Process -Id $PID).Path
$runner = Join-Path $PSScriptRoot "run_godot.ps1"
$sourceRoot = Join-Path $outputRoot "archive-source"
Expand-Archive -LiteralPath $ArchivePath -DestinationPath $sourceRoot
$dllName = "libeasing_curve_native.windows.template_release.x86_64.dll"
$manifestName = "easing_curve_native.gdextension"
$sourceBin = Join-Path $sourceRoot "addons/easing_curve/bin"
$nativeRunner = Get-Content -Raw (Join-Path $PSScriptRoot "run_native_release_export_test.ps1")
$archiveRunner = Get-Content -Raw (Join-Path $PSScriptRoot "run_release_archive_test.ps1")

function Get-FixtureLiteral {
	param([string]$Source, [string]$Name)
	$pattern = '(?s)\$' + [regex]::Escape($Name) + ' = @\x27\r?\n(.*?)\r?\n\x27@'
	$match = [regex]::Match($Source, $pattern)
	if (-not $match.Success) { throw "Fixture literal not found: $Name" }
	return $match.Groups[1].Value
}

function New-CaseProject {
	param([string]$Case, [string]$Path)
	New-Item -ItemType Directory -Path $Path | Out-Null
	$config = @'
config_version=5
[application]
config/name="Import Crash Diagnostic"
config/features=PackedStringArray("4.7", "GL Compatibility")
[rendering]
renderer/rendering_method="gl_compatibility"
renderer/rendering_method.mobile="gl_compatibility"
'@
	if ($Case -in @('B', 'C', 'D')) {
		$bin = Join-Path $Path "addons/easing_curve/bin"
		New-Item -ItemType Directory -Path $bin -Force | Out-Null
		foreach ($name in @($manifestName, "$manifestName.uid", $dllName)) {
			Copy-Item -LiteralPath (Join-Path $sourceBin $name) -Destination $bin
		}
		if ($Case -eq 'C') {
			# Preserve the manifest and DLL bytes while hiding their folder from scanning.
			Set-Content -LiteralPath (Join-Path $bin '.gdignore') -Value ''
		}
	}
	if ($Case -eq 'D') {
		$config = Get-FixtureLiteral $nativeRunner 'projectConfig'
		Get-FixtureLiteral $nativeRunner 'mainScene' | Set-Content (Join-Path $Path 'main.tscn')
		Get-FixtureLiteral $nativeRunner 'exportPreset' | Set-Content (Join-Path $Path 'export_presets.cfg')
		Copy-Item (Join-Path $repo 'test/scripts/integration/native_release_export_prepare.gd') (Join-Path $Path 'prepare.gd')
		Copy-Item (Join-Path $repo 'test/scripts/integration/native_release_export_main.gd') (Join-Path $Path 'main.gd')
	}
	if ($Case -eq 'E') {
		Expand-Archive -LiteralPath $ArchivePath -DestinationPath $Path
		$config = (Get-FixtureLiteral $archiveRunner 'projectConfig').Replace(
			'enabled=PackedStringArray("res://addons/easing_curve/plugin.cfg")', 'enabled=PackedStringArray()'
		)
		Get-FixtureLiteral $archiveRunner 'runtimeScript' | Set-Content (Join-Path $Path 'main.gd')
	}
	Set-Content -LiteralPath (Join-Path $Path 'project.godot') -Value $config
	New-Item -ItemType Directory -Path (Join-Path $Path 'test/_temp') -Force | Out-Null
	Set-Content -LiteralPath (Join-Path $Path 'test/_temp/.gdignore') -Value ''
}

function Invoke-Case {
	param([string]$Case, [bool]$Capture)
	$mode = if ($Capture) { 'procdump' } else { 'baseline' }
	$caseRoot = Join-Path $outputRoot "$Case-$mode"
	$project = Join-Path $caseRoot 'project'
	New-Item -ItemType Directory -Path $caseRoot | Out-Null
	New-CaseProject $Case $project
	$log = Join-Path $project 'test/_temp/import.log'
	$arguments = @('--editor', '--headless', '--path', $project, '--import', '--log-file', $log)
	$startInfo = [Diagnostics.ProcessStartInfo]::new()
	$startInfo.UseShellExecute = $false
	$startInfo.WindowStyle = [Diagnostics.ProcessWindowStyle]::Hidden
	$startInfo.RedirectStandardOutput = $true
	$startInfo.RedirectStandardError = $true
	$startInfo.WorkingDirectory = $repo
	$dumps = Join-Path $caseRoot 'dumps'
	if ($Capture) { New-Item -ItemType Directory -Path $dumps | Out-Null }
	# Use the identical launcher/environment in both modes. Attaching after launch
	# avoids ProcDump -x changing Godot's startup console/standard handles.
	$startInfo.FileName = $powerShell
	$launchArguments = @('-NoProfile', '-File', $runner, '-GodotPath', $GodotPath, '-ExitCodeFile', "$caseRoot/godot-exit.txt") + $arguments
	foreach ($argument in $launchArguments) { $startInfo.ArgumentList.Add($argument) }
	[ordered]@{executable=$GodotPath; arguments=$arguments; launcher=$startInfo.FileName; launcher_arguments=$launchArguments} |
		ConvertTo-Json -Depth 4 | Set-Content "$caseRoot/command.json"
	$started = Get-Date
	$process = [Diagnostics.Process]::Start($startInfo)
	$stdout = $process.StandardOutput.ReadToEndAsync()
	$stderr = $process.StandardError.ReadToEndAsync()
	$godotProcess = $null
	$collector = $null
	$loadedModules = [Collections.Generic.HashSet[string]]::new()
	$observationErrors = [Collections.Generic.HashSet[string]]::new()
	$timedOut = $false
	while (-not $process.WaitForExit(50)) {
		if (((Get-Date) - $started).TotalSeconds -gt 120) {
			$timedOut = $true
			$process.Kill($true)
			break
		}
		foreach ($candidate in [Diagnostics.Process]::GetProcessesByName([IO.Path]::GetFileNameWithoutExtension($GodotPath))) {
			try {
				if ($candidate.MainModule.FileName -ne $GodotPath) { continue }
				# Hold a process handle so ExitCode remains available after termination.
				$null = $candidate.Handle
				if ($null -eq $godotProcess -or $godotProcess.Id -ne $candidate.Id) { $godotProcess = $candidate }
				foreach ($module in $candidate.Modules) { $null = $loadedModules.Add($module.FileName) }
				# The runner queries --version first; don't attach to that short-lived process.
				if ($Capture -and $null -eq $collector -and ((Get-Date) - $candidate.StartTime).TotalMilliseconds -gt 150) {
					$collectorInfo = [Diagnostics.ProcessStartInfo]::new($ProcDumpPath)
					$collectorInfo.UseShellExecute = $false
					$collectorInfo.WindowStyle = [Diagnostics.ProcessWindowStyle]::Hidden
					$collectorInfo.RedirectStandardOutput = $true
					$collectorInfo.RedirectStandardError = $true
					$collectorInfo.StandardOutputEncoding = [Text.Encoding]::Unicode
					$collectorInfo.StandardErrorEncoding = [Text.Encoding]::Unicode
					# Capture the first AV before exception/exit handling discards module/thread state.
					foreach ($arg in @('-accepteula','-ma','-e','1','-f','C0000005',[string]$candidate.Id,$dumps)) { $collectorInfo.ArgumentList.Add($arg) }
					$collector = [Diagnostics.Process]::Start($collectorInfo)
					$collectorOut = $collector.StandardOutput.ReadToEndAsync()
					$collectorErr = $collector.StandardError.ReadToEndAsync()
					$collectorInfo.ArgumentList | ConvertTo-Json | Set-Content "$caseRoot/procdump-command.json"
				}
			} catch { $null = $observationErrors.Add($_.Exception.Message) }
		}
	}
	$process.WaitForExit()
	$stdout.Result | Set-Content "$caseRoot/process.stdout.txt"
	$stderr.Result | Set-Content "$caseRoot/process.stderr.txt"
	if ($null -ne $collector) {
		if (-not $collector.WaitForExit(15000)) { $collector.Kill() }
		$collector.WaitForExit()
		$collectorOut.Result | Set-Content "$caseRoot/procdump.stdout.txt"
		$collectorErr.Result | Set-Content "$caseRoot/procdump.stderr.txt"
	}
	$exitCode = $null
	if (Test-Path "$caseRoot/godot-exit.txt") {
		$exitCode = [int](Get-Content -Raw "$caseRoot/godot-exit.txt")
	} elseif ($null -ne $godotProcess -and $godotProcess.HasExited) { $exitCode = $godotProcess.ExitCode }
	$logText = if (Test-Path $log) { Get-Content -Raw $log } else { '' }
	$logLines = @($logText -split '\r?\n' | Where-Object { $_.Trim() })
	$result = [ordered]@{
		case=$Case; mode=$mode; signed_exit=$exitCode
		hex_exit=if ($null -ne $exitCode) { '0x{0:X8}' -f ([long]$exitCode -band 0xffffffffL) } else { 'unreported' }
		launcher_exit=$process.ExitCode; timed_out=$timedOut; duration_seconds=((Get-Date)-$started).TotalSeconds
		gdextension_loaded=@($loadedModules | Where-Object { $_.EndsWith($dllName) }).Count -gt 0
		observed_modules=@($loadedModules); module_observation_errors=@($observationErrors)
		class_cache_exists=Test-Path (Join-Path $project '.godot/global_script_class_cache.cfg')
		initialization_completed=$logText.Contains('[ DONE ] first_scan_filesystem')
		editor_layout_completed=$logText.Contains('[ DONE ] loading_editor_layout')
		import_completion_count=[regex]::Matches($logText, '\[ DONE \] reimport').Count
		final_log_line=if ($logLines.Count) { $logLines[-1] } else { '' }
		log_errors=@($logLines | Where-Object { $_ -match '(?i)ERROR:|Parse Error:|crash|assert|failed' })
		dumps=@(Get-ChildItem $caseRoot -Filter '*.dmp' -Recurse | ForEach-Object FullName)
	}
	$result | ConvertTo-Json -Depth 5 | Set-Content "$caseRoot/result.json"
	Write-Host "$Case $mode exit=$exitCode ($($result.hex_exit)) extension=$($result.gdextension_loaded) duration=$($result.duration_seconds) dumps=$($result.dumps.Count)"
	return $result
}

$startTime = Get-Date
[ordered]@{
	os=[Environment]::OSVersion.VersionString; image=$env:ImageOS; image_version=$env:ImageVersion
	runner_os=$env:RUNNER_OS; runner_arch=$env:RUNNER_ARCH; powershell=$PSVersionTable.PSVersion.ToString()
	godot_version=(& $GodotPath --version --log-file "$outputRoot/version.log" | Out-String).Trim()
	hashes=@($GodotPath, (Join-Path $sourceBin $dllName), $ArchivePath | ForEach-Object { Get-FileHash -LiteralPath $_ -Algorithm SHA256 })
} | ConvertTo-Json -Depth 5 | Set-Content "$outputRoot/environment.json"
$results = @(foreach ($case in $Cases) {
	Invoke-Case $case $false
	if ($ProcDumpPath) { Invoke-Case $case $true }
})
$results | ConvertTo-Json -Depth 5 | Set-Content "$outputRoot/results.json"
Get-WinEvent -FilterHashtable @{LogName='Application'; Id=1000,1001; StartTime=$startTime} -ErrorAction SilentlyContinue |
	Where-Object Message -like '*easing-curve-godot*' | Format-List TimeCreated, Id, Message | Out-String | Set-Content "$outputRoot/windows-events.txt"
if (@($results | Where-Object { $_.timed_out -or $null -eq $_.signed_exit -or $_.signed_exit -ne 0 }).Count) {
	throw "Diagnostic cases failed or crashed. This is not a successful import; inspect $outputRoot/results.json and dumps."
}

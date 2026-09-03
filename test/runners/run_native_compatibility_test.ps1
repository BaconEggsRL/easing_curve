[CmdletBinding()]
param([string[]]$GodotPaths = @())

$ErrorActionPreference = "Stop"

$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$validationRoot = Join-Path $projectRoot ("test\_temp\native-compatibility-" + [guid]::NewGuid().ToString("N"))
$binSource = Join-Path $projectRoot "addons\easing_curve\bin"
$binDestination = Join-Path $validationRoot "addons\easing_curve\bin"
$runner = Join-Path $PSScriptRoot "run_godot.ps1"
$powerShellExecutable = (Get-Process -Id $PID).Path
$requiredBinFiles = @(
	"easing_curve_native.gdextension.uid",
	"libeasing_curve_native.windows.template_release.x86_64.dll"
)
$succeeded = $false

if ($GodotPaths.Count -eq 0) {
	$GodotPaths = @(
		"C:\Godot\4.4\engine\Godot_v4.4.1-stable_win64.exe\Godot_v4.4.1-stable_win64_console.exe",
		"C:\Godot\4.5\engine\Godot_v4.5.1-stable_win64.exe\Godot_v4.5.1-stable_win64_console.exe",
		"C:\Godot\4.6\engine\Godot_v4.6.1-stable_win64.exe\Godot_v4.6.1-stable_win64_console.exe",
		"C:\Godot\4.7\engine\Godot_v4.7.1-stable_win64.exe\Godot_v4.7.1-stable_win64_console.exe"
	)
}

try {
	New-Item -ItemType Directory -Force -Path $binDestination, (Join-Path $validationRoot "test\_temp") | Out-Null
	foreach ($fileName in $requiredBinFiles) {
		$source = Join-Path $binSource $fileName
		if (-not (Test-Path -LiteralPath $source -PathType Leaf)) {
			throw "Required compatibility-test file is missing: $source"
		}
		Copy-Item -LiteralPath $source -Destination (Join-Path $binDestination $fileName) -Force
	}
	$fixtureManifest = @'
[configuration]

entry_symbol = "easing_curve_native_library_init"
compatibility_minimum = "4.4"

[libraries]

windows.debug.x86_64 = "res://addons/easing_curve/bin/libeasing_curve_native.windows.template_release.x86_64.dll"
windows.release.x86_64 = "res://addons/easing_curve/bin/libeasing_curve_native.windows.template_release.x86_64.dll"
'@
	[IO.File]::WriteAllText(
		(Join-Path $binDestination "easing_curve_native.gdextension"),
		$fixtureManifest,
		[Text.UTF8Encoding]::new($false)
	)
	Copy-Item -LiteralPath (Join-Path $projectRoot "test\scripts\integration\native_abi_compatibility_main.gd") -Destination (Join-Path $validationRoot "main.gd") -Force
	[IO.File]::WriteAllText(
		(Join-Path $validationRoot "project.godot"),
		"config_version=5`n`n[application]`nconfig/name=`"Native ABI Compatibility`"`n",
		[Text.UTF8Encoding]::new($false)
	)
	[IO.File]::WriteAllText((Join-Path $validationRoot "test\_temp\.gdignore"), "", [Text.UTF8Encoding]::new($false))

	foreach ($godotPath in $GodotPaths) {
		$resolvedGodot = (Resolve-Path -LiteralPath $godotPath -ErrorAction Stop).Path
		$versionLabel = (& $resolvedGodot --version | Out-String).Trim()
		$logPath = Join-Path $validationRoot ("test\_temp\native-abi-" + ($versionLabel -replace '[^0-9A-Za-z.-]', '_') + ".log")
		$bootstrapLogPath = Join-Path $validationRoot ("test\_temp\native-abi-bootstrap-" + ($versionLabel -replace '[^0-9A-Za-z.-]', '_') + ".log")
		Write-Host "Validating the pinned 4.4 Native ABI with Godot $versionLabel..."
		& $powerShellExecutable -NoProfile -ExecutionPolicy Bypass -File $runner -GodotPath $resolvedGodot --editor --headless --path $validationRoot --import --quit-after 1 --log-file $bootstrapLogPath
		$bootstrapExitCode = $LASTEXITCODE
		$bootstrapText = if (Test-Path -LiteralPath $bootstrapLogPath) { Get-Content -Raw -LiteralPath $bootstrapLogPath } else { "" }
		if ($bootstrapExitCode -ne 0 -or $bootstrapText -match '(?m)^ERROR: Failed to load extension') {
			throw "Native extension bootstrap failed under $versionLabel. Artifacts retained at $validationRoot"
		}
		& $powerShellExecutable -NoProfile -ExecutionPolicy Bypass -File $runner -GodotPath $resolvedGodot --headless --path $validationRoot --script res://main.gd --log-file $logPath
		$exitCode = $LASTEXITCODE
		$logText = if (Test-Path -LiteralPath $logPath) { Get-Content -Raw -LiteralPath $logPath } else { "" }
		if ($exitCode -ne 0 -or $logText -notmatch '(?m)^PASS: Native ABI compatibility$') {
			throw "Native ABI compatibility failed under $versionLabel. Artifacts retained at $validationRoot"
		}
	}

	Write-Host "PASS: pinned Native ABI loaded under all $($GodotPaths.Count) requested Godot versions."
	$succeeded = $true
} finally {
	if ($succeeded -and (Test-Path -LiteralPath $validationRoot)) {
		Remove-Item -LiteralPath $validationRoot -Recurse -Force
	}
}

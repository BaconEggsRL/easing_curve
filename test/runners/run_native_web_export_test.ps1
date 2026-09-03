[CmdletBinding()]
param(
	[string]$GodotPath = "",
	[switch]$SkipBuild,
	[string]$BrowserPath = ""
)

$ErrorActionPreference = "Stop"

function Resolve-ProjectRoot {
	$candidate = (Resolve-Path $PSScriptRoot).Path
	while ($true) {
		if (Test-Path -LiteralPath (Join-Path $candidate "project.godot") -PathType Leaf) {
			return $candidate
		}
		$parent = Split-Path -Parent $candidate
		if ([string]::IsNullOrWhiteSpace($parent) -or $parent -eq $candidate) {
			throw "Could not locate project.godot above runner directory: $PSScriptRoot"
		}
		$candidate = $parent
	}
}

function Resolve-BrowserPath {
	param([string]$RequestedPath)

	if (-not [string]::IsNullOrWhiteSpace($RequestedPath)) {
		return (Resolve-Path -LiteralPath $RequestedPath -ErrorAction Stop).Path
	}
	foreach ($commandName in @("google-chrome", "chromium", "chromium-browser", "chrome", "msedge")) {
		$command = Get-Command $commandName -ErrorAction SilentlyContinue | Select-Object -First 1
		if ($null -ne $command) {
			return $command.Source
		}
	}
	foreach ($candidate in @(
		"C:\Program Files\Google\Chrome\Application\chrome.exe",
		"C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe",
		"C:\Program Files\Microsoft\Edge\Application\msedge.exe"
	)) {
		if (Test-Path -LiteralPath $candidate -PathType Leaf) {
			return $candidate
		}
	}
	throw "Chrome, Chromium, or Edge was not found. Supply -BrowserPath."
}

function Resolve-PythonPath {
	foreach ($commandName in @("python", "python3")) {
		$command = Get-Command $commandName -ErrorAction SilentlyContinue | Select-Object -First 1
		if ($null -ne $command) {
			return $command.Source
		}
	}
	throw "Python was not found; it is required to serve the Web export locally."
}

function Get-AvailablePort {
	$listener = [Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback, 0)
	$listener.Start()
	try {
		return ([Net.IPEndPoint]$listener.LocalEndpoint).Port
	} finally {
		$listener.Stop()
	}
}

function Wait-ForServer {
	param([int]$Port)

	for ($attempt = 0; $attempt -lt 50; $attempt += 1) {
		$client = [Net.Sockets.TcpClient]::new()
		try {
			$connection = $client.ConnectAsync("127.0.0.1", $Port)
			if ($connection.Wait(200) -and $client.Connected) {
				return
			}
		} finally {
			$client.Dispose()
		}
		Start-Sleep -Milliseconds 100
	}
	throw "Local Web export server did not start on port $Port."
}

function Start-LocalProcess {
	param(
		[string]$FilePath,
		[string[]]$ArgumentList,
		[string]$StandardOutputPath,
		[string]$StandardErrorPath
	)

	$parameters = @{
		FilePath = $FilePath
		ArgumentList = $ArgumentList
		PassThru = $true
		RedirectStandardOutput = $StandardOutputPath
		RedirectStandardError = $StandardErrorPath
	}
	if ([Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT) {
		$parameters.WindowStyle = "Hidden"
	}
	return Start-Process @parameters
}

function Invoke-CdpCommand {
	param(
		[Net.WebSockets.ClientWebSocket]$Socket,
		[int]$Id,
		[string]$Method,
		[hashtable]$Parameters = @{}
	)

	$payload = @{
		id = $Id
		method = $Method
		params = $Parameters
	} | ConvertTo-Json -Compress -Depth 10
	$payloadBytes = [Text.Encoding]::UTF8.GetBytes($payload)
	$sendSegment = [ArraySegment[byte]]::new($payloadBytes)
	[void]$Socket.SendAsync(
		$sendSegment,
		[Net.WebSockets.WebSocketMessageType]::Text,
		$true,
		[Threading.CancellationToken]::None
	).GetAwaiter().GetResult()

	while ($true) {
		$buffer = New-Object byte[] 65536
		$receiveSegment = [ArraySegment[byte]]::new($buffer)
		$stream = [IO.MemoryStream]::new()
		try {
			do {
				$result = $Socket.ReceiveAsync(
					$receiveSegment,
					[Threading.CancellationToken]::None
				).GetAwaiter().GetResult()
				if ($result.MessageType -eq [Net.WebSockets.WebSocketMessageType]::Close) {
					throw "Browser DevTools connection closed before command $Id completed."
				}
				$stream.Write($buffer, 0, $result.Count)
			} while (-not $result.EndOfMessage)
			$response = [Text.Encoding]::UTF8.GetString($stream.ToArray()) | ConvertFrom-Json
		} finally {
			$stream.Dispose()
		}
		if ($response.id -eq $Id) {
			return $response
		}
	}
}

function Wait-ForDevToolsTarget {
	param(
		[int]$Port,
		[Diagnostics.Process]$BrowserProcess
	)

	for ($attempt = 0; $attempt -lt 100; $attempt += 1) {
		if ($BrowserProcess.HasExited) {
			throw "Web browser exited before its DevTools endpoint became available."
		}
		try {
			$targets = Invoke-RestMethod -Uri "http://127.0.0.1:$Port/json/list" -TimeoutSec 1
			$target = $targets | Where-Object { $_.type -eq "page" -and -not [string]::IsNullOrWhiteSpace($_.webSocketDebuggerUrl) } | Select-Object -First 1
			if ($null -ne $target) {
				return $target
			}
		} catch {
			# The endpoint is expected to reject connections briefly during browser startup.
		}
		Start-Sleep -Milliseconds 100
	}
	throw "Browser DevTools endpoint did not become available on port $Port."
}

function Test-WebRuntime {
	param(
		[string]$OutputDirectory,
		[string]$Label,
		[string]$Browser,
		[string]$Python
	)

	$port = Get-AvailablePort
	do {
		$devToolsPort = Get-AvailablePort
	} while ($devToolsPort -eq $port)
	$serverOutput = Join-Path $OutputDirectory "server-$Label.out.log"
	$serverError = Join-Path $OutputDirectory "server-$Label.err.log"
	$serverArguments = @("-m", "http.server", "$port", "--bind", "127.0.0.1", "--directory", $OutputDirectory)
	$server = Start-LocalProcess -FilePath $Python -ArgumentList $serverArguments -StandardOutputPath $serverOutput -StandardErrorPath $serverError
	$browserProcess = $null
	$socket = $null
	try {
		Wait-ForServer -Port $port
		$url = "http://127.0.0.1:$port/index.html"
		$browserOutput = Join-Path $OutputDirectory "browser-$Label.out.log"
		$browserError = Join-Path $OutputDirectory "browser-$Label.err.log"
		$browserProfile = Join-Path $OutputDirectory "browser-$Label-profile"
		$browserArguments = @(
			"--headless=new",
			"--no-sandbox",
			"--disable-gpu",
			"--disable-dev-shm-usage",
			"--remote-debugging-port=$devToolsPort",
			"--user-data-dir=$browserProfile",
			$url
		)
		$browserProcess = Start-LocalProcess -FilePath $Browser -ArgumentList $browserArguments -StandardOutputPath $browserOutput -StandardErrorPath $browserError
		$target = Wait-ForDevToolsTarget -Port $devToolsPort -BrowserProcess $browserProcess
		$socket = [Net.WebSockets.ClientWebSocket]::new()
		[void]$socket.ConnectAsync(
			[Uri]$target.webSocketDebuggerUrl,
			[Threading.CancellationToken]::None
		).GetAwaiter().GetResult()

		$deadline = [DateTime]::UtcNow.AddSeconds(30)
		$commandId = 1
		while ([DateTime]::UtcNow -lt $deadline) {
			$response = Invoke-CdpCommand `
				-Socket $socket `
				-Id $commandId `
				-Method "Runtime.evaluate" `
				-Parameters @{
					expression = "document.documentElement.getAttribute('data-native-curve-test')"
					returnByValue = $true
				}
			$commandId += 1
			$runtimeResult = $response.result.result.value
			if ($runtimeResult -eq "pass") {
				Write-Host "PASS: $Label Web export registered and sampled Native resources in the browser."
				return
			}
			if ($runtimeResult -eq "fail") {
				throw "$Label Web runtime reported a failed Native resource check."
			}
			Start-Sleep -Milliseconds 250
		}
		$browserDiagnostics = if (Test-Path -LiteralPath $browserError -PathType Leaf) {
			Get-Content -LiteralPath $browserError -Raw
		} else {
			"No browser error log was produced."
		}
		throw "$Label Web browser validation timed out waiting for the Native runtime result.`n$browserDiagnostics"
	} finally {
		if ($null -ne $socket) {
			$socket.Dispose()
		}
		if ($null -ne $browserProcess -and -not $browserProcess.HasExited) {
			Stop-Process -Id $browserProcess.Id -Force -ErrorAction SilentlyContinue
		}
		if (-not $server.HasExited) {
			Stop-Process -Id $server.Id -Force -ErrorAction SilentlyContinue
		}
	}
}

$projectRoot = Resolve-ProjectRoot
$nativeDirectory = Join-Path $projectRoot "native"
$sourceBinDirectory = Join-Path $projectRoot "addons\easing_curve\bin"
$manifestValidator = Join-Path $nativeDirectory "validate_native_manifest.ps1"
$godotRunner = Join-Path $PSScriptRoot "run_godot.ps1"
$powerShellExecutable = (Get-Process -Id $PID).Path
$selectedGodotPath = if (-not [string]::IsNullOrWhiteSpace($GodotPath)) {
	$GodotPath
} elseif (-not [string]::IsNullOrWhiteSpace($env:EASING_CURVE_GODOT_PATH)) {
	$env:EASING_CURVE_GODOT_PATH
} else {
	"C:\Godot\4.7\engine\Godot_v4.7.1-stable_win64.exe\Godot_v4.7.1-stable_win64_console.exe"
}
$selectedGodotPath = (Resolve-Path -LiteralPath $selectedGodotPath -ErrorAction Stop).Path
$godotVersion = (& $selectedGodotPath --version | Out-String).Trim()
if ([string]::IsNullOrWhiteSpace($godotVersion)) {
	throw "Could not determine the selected Godot version: $selectedGodotPath"
}
$templateVersion = ($godotVersion -replace '\.official\..*$', '')
$installedTemplateDirectory = Join-Path $env:APPDATA "Godot\export_templates\$templateVersion"
$debugTemplate = Join-Path $installedTemplateDirectory "web_dlink_nothreads_debug.zip"
$releaseTemplate = Join-Path $installedTemplateDirectory "web_dlink_nothreads_release.zip"
$windowsLibrary = "libeasing_curve_native.windows.template_release.x86_64.dll"
$webDebugLibrary = "libeasing_curve_native.web.template_debug.wasm32.nothreads.wasm"
$webReleaseLibrary = "libeasing_curve_native.web.template_release.wasm32.nothreads.wasm"
$tempBase = Join-Path $projectRoot "test\_temp\native-web-export"
$validationRoot = Join-Path $tempBase ([guid]::NewGuid().ToString("N"))
$tempProject = Join-Path $validationRoot "project"
$debugOutput = Join-Path $validationRoot "debug"
$releaseOutput = Join-Path $validationRoot "release"
$projectTempDirectory = Join-Path $tempProject "test\_temp"
$succeeded = $false

try {
	if (-not $SkipBuild) {
		& (Join-Path $nativeDirectory "build_native.ps1") -Platform web -Target all
		if ($LASTEXITCODE -ne 0) {
			throw "Native Web build failed with exit code $LASTEXITCODE."
		}
	}
	& $manifestValidator -Platform web

	foreach ($template in @($debugTemplate, $releaseTemplate)) {
		if (-not (Test-Path -LiteralPath $template -PathType Leaf)) {
			throw "Godot $templateVersion Web export template was not found: $template"
		}
	}

	New-Item -ItemType Directory -Force -Path $tempProject, $debugOutput, $releaseOutput, $projectTempDirectory | Out-Null
	[IO.File]::WriteAllText((Join-Path $projectTempDirectory ".gdignore"), "", [Text.UTF8Encoding]::new($false))
	$destinationBin = Join-Path $tempProject "addons\easing_curve\bin"
	New-Item -ItemType Directory -Force -Path $destinationBin | Out-Null
	foreach ($fileName in @(
		"easing_curve_native.gdextension",
		"easing_curve_native.gdextension.uid",
		$windowsLibrary,
		$webDebugLibrary,
		$webReleaseLibrary
	)) {
		$source = Join-Path $sourceBinDirectory $fileName
		if (-not (Test-Path -LiteralPath $source -PathType Leaf)) {
			throw "Required Native Web export file was not found: $source"
		}
		Copy-Item -LiteralPath $source -Destination (Join-Path $destinationBin $fileName) -Force
	}

	Copy-Item -LiteralPath (Join-Path $projectRoot "test\scripts\integration\native_release_export_prepare.gd") -Destination (Join-Path $tempProject "prepare.gd") -Force
	Copy-Item -LiteralPath (Join-Path $projectRoot "test\scripts\integration\native_web_export_main.gd") -Destination (Join-Path $tempProject "main.gd") -Force

	$projectConfig = @'
; Generated by test/runners/run_native_web_export_test.ps1.
config_version=5

[application]

config/name="Native Web Export Validation"
run/main_scene="res://main.tscn"
config/features=PackedStringArray("4.7", "GL Compatibility")

[display]

window/size/viewport_width=640
window/size/viewport_height=360

[rendering]

renderer/rendering_method="gl_compatibility"
renderer/rendering_method.mobile="gl_compatibility"
'@
	[IO.File]::WriteAllText((Join-Path $tempProject "project.godot"), $projectConfig, [Text.UTF8Encoding]::new($false))

	$mainScene = @'
[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://main.gd" id="1_main"]

[node name="NativeWebExportValidation" type="Node"]
script = ExtResource("1_main")
'@
	[IO.File]::WriteAllText((Join-Path $tempProject "main.tscn"), $mainScene, [Text.UTF8Encoding]::new($false))

	$exportPreset = @'
[preset.0]

name="Web"
platform="Web"
dedicated_server=false
custom_features=""
export_filter="all_resources"
include_filter=""
exclude_filter=""
export_path=""
patches=PackedStringArray()
encrypt_pck=false
encrypt_directory=false
script_export_mode=2

[preset.0.options]

custom_template/debug="__DEBUG_TEMPLATE__"
custom_template/release="__RELEASE_TEMPLATE__"
variant/extensions_support=true
variant/thread_support=false
vram_texture_compression/for_desktop=true
vram_texture_compression/for_mobile=false
html/export_icon=false
html/custom_html_shell=""
html/head_include=""
html/canvas_resize_policy=2
html/focus_canvas_on_start=true
progressive_web_app/enabled=false
'@
	$exportPreset = $exportPreset.Replace("__DEBUG_TEMPLATE__", $debugTemplate.Replace("\", "/"))
	$exportPreset = $exportPreset.Replace("__RELEASE_TEMPLATE__", $releaseTemplate.Replace("\", "/"))
	[IO.File]::WriteAllText((Join-Path $tempProject "export_presets.cfg"), $exportPreset, [Text.UTF8Encoding]::new($false))

	$runnerBaseArguments = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $godotRunner, "-GodotPath", $selectedGodotPath)
	$bootstrapLog = Join-Path $projectTempDirectory "bootstrap.log"
	& $powerShellExecutable @runnerBaseArguments "--editor" "--headless" "--path" $tempProject "--import" "--log-file" $bootstrapLog
	$bootstrapExit = $LASTEXITCODE
	$classCache = Join-Path $tempProject ".godot\global_script_class_cache.cfg"
	$bootstrapText = if (Test-Path -LiteralPath $bootstrapLog) { Get-Content -Raw -LiteralPath $bootstrapLog } else { "" }
	$bootstrapHasFatalDiagnostic = $bootstrapText -match '(?m)^(?:SCRIPT ERROR:|.*Parse Error:|ERROR: Failed to load extension)'
	if (-not (Test-Path -LiteralPath $classCache -PathType Leaf) -or $bootstrapHasFatalDiagnostic) {
		throw "Native Web fixture bootstrap did not produce a valid class cache."
	}
	if ($bootstrapExit -ne 0) {
		Write-Warning "Bootstrap returned $bootstrapExit after producing a clean class cache; continuing."
	}
	$prepareLog = Join-Path $projectTempDirectory "prepare.log"
	& $powerShellExecutable @runnerBaseArguments "--headless" "--path" $tempProject "--script" "res://prepare.gd" "--log-file" $prepareLog
	if ($LASTEXITCODE -ne 0 -or (Get-Content -Raw -LiteralPath $prepareLog) -notmatch '(?m)^PREPARED:') {
		throw "Native Web resources were not prepared successfully."
	}

	$debugHtml = Join-Path $debugOutput "index.html"
	$debugLog = Join-Path $projectTempDirectory "debug-export.log"
	& $powerShellExecutable @runnerBaseArguments "--headless" "--path" $tempProject "--export-debug" "Web" $debugHtml "--log-file" $debugLog
	if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $debugHtml -PathType Leaf)) {
		throw "Native Web debug export failed with exit code $LASTEXITCODE."
	}

	$releaseHtml = Join-Path $releaseOutput "index.html"
	$releaseLog = Join-Path $projectTempDirectory "release-export.log"
	& $powerShellExecutable @runnerBaseArguments "--headless" "--path" $tempProject "--export-release" "Web" $releaseHtml "--log-file" $releaseLog
	if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $releaseHtml -PathType Leaf)) {
		throw "Native Web release export failed with exit code $LASTEXITCODE."
	}

	$resolvedBrowser = Resolve-BrowserPath -RequestedPath $BrowserPath
	$resolvedPython = Resolve-PythonPath
	Test-WebRuntime -OutputDirectory $debugOutput -Label "debug" -Browser $resolvedBrowser -Python $resolvedPython
	Test-WebRuntime -OutputDirectory $releaseOutput -Label "release" -Browser $resolvedBrowser -Python $resolvedPython
	Write-Host "PASS: Native Web debug and release exports loaded built-in and custom resources."
	$succeeded = $true
} finally {
	if ($succeeded) {
		Remove-Item -LiteralPath $validationRoot -Recurse -Force -ErrorAction SilentlyContinue
		if ((Test-Path -LiteralPath $tempBase -PathType Container) -and -not (Get-ChildItem -LiteralPath $tempBase -Force | Select-Object -First 1)) {
			Remove-Item -LiteralPath $tempBase -Force -ErrorAction SilentlyContinue
		}
	} else {
		Write-Host "Preserved failed Web validation artifacts: $validationRoot" -ForegroundColor Yellow
	}
}

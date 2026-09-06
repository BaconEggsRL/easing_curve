[CmdletBinding()]
param(
	[string]$PythonPath = "python",
	[string]$HugoPath = "hugo",
	[string]$ResultsPath = "",
	[ValidateSet("forward_plus", "mobile", "gl_compatibility")][string]$Renderer = "forward_plus",
	[ValidateRange(1024, 65535)][int]$Port = 8765,
	[switch]$Serve
)

$ErrorActionPreference = "Stop"
$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot "../..")).Path
if (-not $ResultsPath) { $ResultsPath = Join-Path $projectRoot "_exports/_benchmarks/godot-tween" }
$python = (Get-Command $PythonPath -ErrorAction Stop).Source
$hugo = (Get-Command $HugoPath -ErrorAction Stop).Source
$buildId = (Get-Date -Format "yyyyMMdd-HHmmss") + "-" + [guid]::NewGuid().ToString("N").Substring(0, 8)
$buildRoot = Join-Path $projectRoot "_exports/_benchmarks/godot-web/$buildId"
$source = Join-Path $buildRoot "source"
$public = Join-Path $buildRoot "public"
$baseUrl = "http://127.0.0.1:$Port/"
& $python (Join-Path $projectRoot "test/scripts/performance/prepare_godot_benchmark_web.py") --results $ResultsPath --output $source --renderer $Renderer
if ($LASTEXITCODE -ne 0) { throw "Benchmark web data preparation failed." }
& $hugo --source $source --destination $public --baseURL $baseUrl --cacheDir (Join-Path $buildRoot "cache")
if ($LASTEXITCODE -ne 0) { throw "Benchmark web build failed: $buildRoot" }
Write-Host "Built upstream benchmark interface: $public"
Write-Host "Native: ${baseUrl}graph/animation-native-easing-curve/"
Write-Host "Legacy: ${baseUrl}graph/animation-legacy-easing-curve/"
if ($Serve) {
	Write-Host "Serving locally; press Ctrl+C to stop."
	& $python -m http.server $Port --bind 127.0.0.1 --directory $public
} else {
	Write-Host "Add -Serve to serve this interface locally."
}

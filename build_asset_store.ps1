$ErrorActionPreference = "Stop"

$ProjectRoot = (Resolve-Path $PSScriptRoot).Path
$PluginPath = Join-Path $ProjectRoot "addons\easing_curve"
$ConfigPath = Join-Path $PluginPath "plugin.cfg"
$AllowlistPath = Join-Path $ProjectRoot "release\addon_files.txt"
$OutputPath = Join-Path $ProjectRoot "_exports\_asset_store_builds"
$BuildPath = Join-Path $OutputPath "_staging"
$ArchiveRoot = "addons/easing_curve"
$GeneratedArchiveFiles = @("BUILD_METADATA.json", "SHA256SUMS")

function Get-PluginVersion {
    $VersionLine = Get-Content -LiteralPath $ConfigPath |
        Where-Object { $_ -match '^\s*version\s*=' } |
        Select-Object -First 1
    if ($VersionLine -notmatch '^\s*version\s*=\s*"([^"]+)"') {
        throw "Could not parse version from $ConfigPath"
    }
    return $Matches[1]
}

function Get-AllowlistedFiles {
    if (-not (Test-Path -LiteralPath $AllowlistPath -PathType Leaf)) {
        throw "Release allowlist is missing: $AllowlistPath"
    }
    $Files = @(
        Get-Content -LiteralPath $AllowlistPath |
            ForEach-Object { $_.Trim().Replace('\', '/') } |
            Where-Object { $_ -and -not $_.StartsWith('#') }
    )
    if ($Files.Count -eq 0 -or ($Files | Sort-Object -Unique).Count -ne $Files.Count) {
        throw "Release allowlist is empty or contains duplicate paths."
    }
    foreach ($RelativePath in $Files) {
        if ($RelativePath.StartsWith('/') -or $RelativePath.Contains('../') -or $RelativePath.Contains(':')) {
            throw "Unsafe release allowlist path: $RelativePath"
        }
    }
    return $Files
}

function Get-SourcePath {
    param([string]$RelativePath)
    if ($RelativePath -eq "README.md" -or $RelativePath -eq "LICENSE.md") {
        return Join-Path $ProjectRoot $RelativePath
    }
    return Join-Path $PluginPath $RelativePath.Replace('/', [IO.Path]::DirectorySeparatorChar)
}

function Copy-AllowlistedFiles {
    param([string[]]$Files, [string]$DestinationRoot)
    foreach ($RelativePath in $Files) {
        $SourcePath = Get-SourcePath -RelativePath $RelativePath
        if (-not (Test-Path -LiteralPath $SourcePath -PathType Leaf)) {
            throw "Allowlisted release file is missing: $SourcePath"
        }
        $DestinationPath = Join-Path $DestinationRoot $RelativePath.Replace('/', [IO.Path]::DirectorySeparatorChar)
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $DestinationPath) | Out-Null
        Copy-Item -LiteralPath $SourcePath -Destination $DestinationPath -Force
    }
}

function Write-BuildMetadata {
    param([string]$DestinationRoot, [string]$Version)
    $SourceCommit = (git rev-parse HEAD).Trim()
    if ($LASTEXITCODE -ne 0) { throw "Could not resolve source commit." }
    $GodotCppCommit = (git -C (Join-Path $ProjectRoot "native\godot-cpp") rev-parse HEAD).Trim()
    if ($LASTEXITCODE -ne 0) { throw "Could not resolve godot-cpp commit." }
    $SourceDirty = @(git status --porcelain).Count -gt 0
    if ($LASTEXITCODE -ne 0) { throw "Could not resolve source worktree status." }
    $Metadata = [ordered]@{
        plugin = "easing_curve"
        version = $Version
        source_commit = $SourceCommit
        source_dirty = $SourceDirty
        godot_cpp_commit = $GodotCppCommit
        godot_extension_api = "4.4.1-stable"
        native_platforms = @("windows.x86_64", "web.wasm32.nothreads")
        legacy_deprecated = $false
    }
    [IO.File]::WriteAllText(
        (Join-Path $DestinationRoot "BUILD_METADATA.json"),
        ($Metadata | ConvertTo-Json -Depth 4) + [Environment]::NewLine,
        [Text.UTF8Encoding]::new($false)
    )
}

function Write-Checksums {
    param([string]$DestinationRoot)
    $ArtifactNames = @(
        "bin/easing_curve_native.gdextension",
        "bin/libeasing_curve_native.windows.template_release.x86_64.dll",
        "bin/libeasing_curve_native.web.template_debug.wasm32.nothreads.wasm",
        "bin/libeasing_curve_native.web.template_release.wasm32.nothreads.wasm"
    )
    $Lines = foreach ($RelativePath in $ArtifactNames) {
        $Path = Join-Path $DestinationRoot $RelativePath.Replace('/', [IO.Path]::DirectorySeparatorChar)
        $Hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToLowerInvariant()
        "$Hash  $RelativePath"
    }
    [IO.File]::WriteAllLines(
        (Join-Path $DestinationRoot "SHA256SUMS"),
        $Lines,
        [Text.UTF8Encoding]::new($false)
    )
}

$Version = Get-PluginVersion
$OutputZip = Join-Path $OutputPath "easing_curve_v$Version.zip"
$Files = Get-AllowlistedFiles
$StagedAddon = Join-Path $BuildPath "addons\easing_curve"

Write-Host "Building Easing Curve v$Version from a strict allowlist..."
New-Item -ItemType Directory -Force -Path $OutputPath | Out-Null
Remove-Item -LiteralPath $BuildPath -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path $StagedAddon | Out-Null
Copy-AllowlistedFiles -Files $Files -DestinationRoot $StagedAddon
Write-BuildMetadata -DestinationRoot $StagedAddon -Version $Version
Write-Checksums -DestinationRoot $StagedAddon

Remove-Item -LiteralPath $OutputZip -Force -ErrorAction SilentlyContinue
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
[System.IO.Compression.ZipFile]::CreateFromDirectory(
    $BuildPath,
    $OutputZip,
    [System.IO.Compression.CompressionLevel]::Optimal,
    $false
)

$ExpectedEntries = @(
    $Files | ForEach-Object { "$ArchiveRoot/$_" }
) + @(
    $GeneratedArchiveFiles | ForEach-Object { "$ArchiveRoot/$_" }
)
$ExpectedEntries = @($ExpectedEntries | Sort-Object)
$Archive = [System.IO.Compression.ZipFile]::OpenRead($OutputZip)
try {
    $ActualEntries = @(
        $Archive.Entries |
            Where-Object { -not [string]::IsNullOrEmpty($_.Name) } |
            ForEach-Object { $_.FullName } |
            Sort-Object
    )
    if ($ActualEntries.Count -ne $ExpectedEntries.Count) {
        throw "Archive entry count differs from the release allowlist."
    }
    for ($Index = 0; $Index -lt $ExpectedEntries.Count; $Index++) {
        if ($ActualEntries[$Index] -cne $ExpectedEntries[$Index]) {
            throw "Unexpected archive contents: expected '$($ExpectedEntries[$Index])', found '$($ActualEntries[$Index])'."
        }
    }
    foreach ($Entry in $ActualEntries) {
        if ($Entry.Contains('\')) {
            throw "Archive contains a Windows-style path: $Entry"
        }
    }
}
finally {
    $Archive.Dispose()
    Remove-Item -LiteralPath $BuildPath -Recurse -Force -ErrorAction SilentlyContinue
}

$ArchiveHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $OutputZip).Hash
Write-Host "PASS: exact allowlisted archive created."
Write-Host $OutputZip
Write-Host "SHA256: $ArchiveHash"

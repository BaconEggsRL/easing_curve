$ErrorActionPreference = "Stop"

$PluginPath = "addons\easing_curve"
$ConfigPath = "$PluginPath\plugin.cfg"
$ReadmeSourcePath = "README.md"
$PackagedReadmePath = "$PluginPath\README.md"

$OutputPath = "_exports\_asset_store_builds"
$BuildPath = "$OutputPath\_staging"

# Read version from plugin.cfg.
$VersionLine = Get-Content $ConfigPath |
    Where-Object { $_ -match '^\s*version\s*=' } |
    Select-Object -First 1

if (-not $VersionLine) {
    throw "Could not find version in $ConfigPath"
}

if ($VersionLine -notmatch '^\s*version\s*=\s*"([^"]+)"') {
    throw "Could not parse version from: $VersionLine"
}

$Version = $Matches[1]
$OutputZip = "$OutputPath\easing_curve_v$Version.zip"

Write-Host "Building Easing Curve v$Version..."

# The root README is canonical; refresh the packaged addon copy before staging.
if (-not (Test-Path $ReadmeSourcePath -PathType Leaf)) {
    throw "Could not find canonical README: $ReadmeSourcePath"
}
Copy-Item $ReadmeSourcePath $PackagedReadmePath -Force

# Make sure output directory exists.
New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null

# Clean previous staging directory.
Remove-Item $BuildPath -Recurse -Force -ErrorAction SilentlyContinue

# Create required Asset Store structure.
New-Item -ItemType Directory -Path "$BuildPath\addons" | Out-Null

# Copy only addons/easing_curve.
Copy-Item `
    $PluginPath `
    "$BuildPath\addons\easing_curve" `
    -Recurse

# Remove an existing build of the same version.
Remove-Item $OutputZip -Force -ErrorAction SilentlyContinue

# ZIP contains:
#
# addons/
# └── easing_curve/
#
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

# Resolve staging path to an absolute path.
$BuildPathFull = (Resolve-Path $BuildPath).Path.TrimEnd('\')

$Zip = [System.IO.Compression.ZipFile]::Open(
    $OutputZip,
    [System.IO.Compression.ZipArchiveMode]::Create
)

try {
    Get-ChildItem "$BuildPathFull\addons" -File -Recurse | ForEach-Object {
        # Make the archive path relative to _staging.
        $RelativePath = $_.FullName.Substring(
            $BuildPathFull.Length + 1
        )

        # ZIP paths must use forward slashes for macOS/Linux compatibility.
        $EntryPath = $RelativePath.Replace('\', '/')

        [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile(
            $Zip,
            $_.FullName,
            $EntryPath,
            [System.IO.Compression.CompressionLevel]::Optimal
        ) | Out-Null
    }
}
finally {
    $Zip.Dispose()
}

# Verify ZIP structure and cross-platform paths.
Write-Host ""
Write-Host "Verifying ZIP..."

$VerifyZip = [System.IO.Compression.ZipFile]::OpenRead(
    (Resolve-Path $OutputZip).Path
)

$VerificationFailed = $false

try {
    foreach ($Entry in $VerifyZip.Entries) {
        $EntryPath = $Entry.FullName

        # ZIP entries must use forward slashes, never Windows backslashes.
        if ($EntryPath.Contains('\')) {
            Write-Host "  [FAIL] Windows-style path: $EntryPath" -ForegroundColor Red
            $VerificationFailed = $true
            continue
        }

        # Every file must be under addons/easing_curve/.
        if (-not $EntryPath.StartsWith("addons/easing_curve/")) {
            Write-Host "  [FAIL] Invalid root path: $EntryPath" -ForegroundColor Red
            $VerificationFailed = $true
            continue
        }

        Write-Host "  [OK]   $EntryPath" -ForegroundColor DarkGray
    }

    $ReadmeEntry = $VerifyZip.GetEntry("addons/easing_curve/README.md")
    if ($null -eq $ReadmeEntry) {
        Write-Host "  [FAIL] Missing packaged README" -ForegroundColor Red
        $VerificationFailed = $true
    }
    else {
        $ReadmeReader = [System.IO.StreamReader]::new($ReadmeEntry.Open())
        try {
            $PackagedReadme = $ReadmeReader.ReadToEnd()
        }
        finally {
            $ReadmeReader.Dispose()
        }

        $CanonicalReadme = [System.IO.File]::ReadAllText(
            (Resolve-Path $ReadmeSourcePath).Path
        )
        if ($PackagedReadme -cne $CanonicalReadme) {
            Write-Host "  [FAIL] Packaged README differs from root README" -ForegroundColor Red
            $VerificationFailed = $true
        }
        else {
            Write-Host "  [OK]   Packaged README matches root README" -ForegroundColor Green
        }
    }
}
finally {
    $VerifyZip.Dispose()
}

Write-Host ""

if ($VerificationFailed) {
    throw "ZIP verification FAILED. Do not upload this archive."
}

Write-Host "ZIP verification PASSED." -ForegroundColor Green
Write-Host "  [OK] Root is addons/easing_curve/" -ForegroundColor Green
Write-Host "  [OK] All ZIP paths use forward slashes (/)" -ForegroundColor Green
Write-Host "  [OK] No Windows-style backslashes found" -ForegroundColor Green
Write-Host "  [OK] Archive is safe for Windows, macOS, and Linux" -ForegroundColor Green

# Clean staging directory.
Remove-Item $BuildPath -Recurse -Force

Write-Host ""
Write-Host "Asset Store build complete:"
Write-Host $OutputZip

[CmdletBinding()]
param(
    [ValidateSet("Validate", "Prepare", "Publish")]
    [string]$Mode = "Validate",

    [string]$Version = "1.0.6",

    [string]$ReleaseBranch = "master",

    [string]$Repository = "BaconEggsRL/easing_curve",

    [switch]$KeepSmokeProject
)

$ErrorActionPreference = "Stop"

$ProjectRoot = (Resolve-Path $PSScriptRoot).Path
$PluginConfig = Join-Path $ProjectRoot "addons\easing_curve\plugin.cfg"
$BuildScript = Join-Path $ProjectRoot "build_asset_store.ps1"
$GodotLauncher = Join-Path $ProjectRoot "test\scripts\run_godot.ps1"
$Changelog = Join-Path $ProjectRoot "test\docs\CHANGELOG.md"

$Tag = "v$Version"
$ZipPath = Join-Path `
    $ProjectRoot `
    "_exports\_asset_store_builds\easing_curve_v$Version.zip"


function Write-Step {
    param([string]$Text)

    Write-Host ""
    Write-Host "=== $Text ===" -ForegroundColor Cyan
}


function Assert-LastExitCode {
    param([string]$Operation)

    if ($LASTEXITCODE -ne 0) {
        throw "$Operation failed with exit code $LASTEXITCODE."
    }
}


function Get-PluginVersion {
    $VersionLine = Get-Content -LiteralPath $PluginConfig |
        Where-Object { $_ -match '^\s*version\s*=' } |
        Select-Object -First 1

    if (-not $VersionLine) {
        throw "Could not find version in $PluginConfig"
    }

    if ($VersionLine -notmatch '^\s*version\s*=\s*"([^"]+)"') {
        throw "Could not parse plugin version: $VersionLine"
    }

    return $Matches[1]
}


function Assert-ReleaseVersion {
    $PluginVersion = Get-PluginVersion

    if ($PluginVersion -ne $Version) {
        throw (
            "plugin.cfg version is '$PluginVersion'; " +
            "expected '$Version'."
        )
    }

    Write-Host "Plugin version: $PluginVersion" -ForegroundColor Green
}


function Test-GitClean {
    $Status = @(git status --porcelain)
    Assert-LastExitCode "git status"

    return $Status.Count -eq 0
}


function Invoke-DiffCheck {
    Write-Step "git diff --check"

    git diff HEAD --check
    Assert-LastExitCode "git diff HEAD --check"

    Write-Host "git diff --check passed." -ForegroundColor Green
}


function Invoke-Build {
    Write-Step "Build Asset Store ZIP"

    & $BuildScript

    if (-not (Test-Path -LiteralPath $ZipPath -PathType Leaf)) {
        throw "Expected archive was not created: $ZipPath"
    }

    $Hash = Get-FileHash -Algorithm SHA256 -LiteralPath $ZipPath

    Write-Host ""
    Write-Host "Exact release archive:" -ForegroundColor Green
    Write-Host "  $ZipPath"
    Write-Host "SHA256:"
    Write-Host "  $($Hash.Hash)"
}


function Invoke-Godot {
    param(
        [string[]]$Arguments,
        [string]$Description
    )

    $StdoutPath = Join-Path `
        ([IO.Path]::GetTempPath()) `
        ("easing-curve-release-{0}.stdout" -f [guid]::NewGuid())

    $StderrPath = Join-Path `
        ([IO.Path]::GetTempPath()) `
        ("easing-curve-release-{0}.stderr" -f [guid]::NewGuid())

    try {
        $PreviousPreference = $ErrorActionPreference
        $ErrorActionPreference = "Continue"

        & $GodotLauncher @Arguments `
            1> $StdoutPath `
            2> $StderrPath

        $ExitCode = $LASTEXITCODE
        $ErrorActionPreference = $PreviousPreference

        $Stdout = if (Test-Path $StdoutPath) {
            Get-Content -Raw $StdoutPath
        } else {
            ""
        }

        $Stderr = if (Test-Path $StderrPath) {
            Get-Content -Raw $StderrPath
        } else {
            ""
        }

        if ($Stdout) {
            Write-Host $Stdout.TrimEnd()
        }

        if ($Stderr) {
            Write-Host $Stderr.TrimEnd()
        }

        $Combined = "$Stdout`n$Stderr"

        if ($ExitCode -ne 0) {
            throw "$Description exited with code $ExitCode."
        }

        if ($Combined -match "SCRIPT ERROR:") {
            throw "$Description reported SCRIPT ERROR."
        }
    }
    finally {
        Remove-Item $StdoutPath -Force -ErrorAction SilentlyContinue
        Remove-Item $StderrPath -Force -ErrorAction SilentlyContinue
    }
}


function Invoke-CleanInstallSmokeTest {
    Write-Step "Clean-project smoke test"

    if (-not (Test-Path -LiteralPath $ZipPath)) {
        throw "Release ZIP does not exist: $ZipPath"
    }

    $SmokeRoot = Join-Path `
        ([IO.Path]::GetTempPath()) `
        ("easing-curve-v{0}-smoke-{1}" -f $Version, [guid]::NewGuid())

    New-Item -ItemType Directory -Path $SmokeRoot -Force | Out-Null

    try {
        Write-Host "Extracting exact release ZIP to:"
        Write-Host "  $SmokeRoot"

        Expand-Archive `
            -LiteralPath $ZipPath `
            -DestinationPath $SmokeRoot `
            -Force

        $ExtractedConfig = Join-Path `
            $SmokeRoot `
            "addons\easing_curve\plugin.cfg"

        if (-not (Test-Path -LiteralPath $ExtractedConfig)) {
            throw "Extracted archive is missing plugin.cfg."
        }

        $ExtractedVersionLine = Get-Content $ExtractedConfig |
            Where-Object { $_ -match '^\s*version\s*=' } |
            Select-Object -First 1

        if (
            $ExtractedVersionLine -notmatch
            '^\s*version\s*=\s*"([^"]+)"'
        ) {
            throw "Could not parse extracted plugin version."
        }

        if ($Matches[1] -ne $Version) {
            throw (
                "Extracted plugin version '$($Matches[1])' " +
                "does not match '$Version'."
            )
        }

        @"
[application]

config/name="Easing Curve Release Smoke"

[editor_plugins]

enabled=PackedStringArray("res://addons/easing_curve/plugin.cfg")

[rendering]

renderer/rendering_method="gl_compatibility"
renderer/rendering_method.mobile="gl_compatibility"
"@ | Set-Content `
            -LiteralPath (Join-Path $SmokeRoot "project.godot") `
            -Encoding UTF8

        # First smoke test: load the plugin in an Editor host.
        Invoke-Godot `
            -Description "Clean-project Editor smoke test" `
            -Arguments @(
                "--editor",
                "--headless",
                "--path", $SmokeRoot,
                "--quit-after", "2"
            )

        # Second smoke test: load and use the runtime resource directly.
        @'
extends SceneTree


func _init() -> void:
    var curve_script = load(
        "res://addons/easing_curve/scripts/easing_curve.gd"
    )

    if curve_script == null:
        push_error("Could not load EasingCurve script")
        quit(1)
        return

    var curve = curve_script.new()

    if curve == null:
        push_error("Could not instantiate EasingCurve")
        quit(1)
        return

    var value = curve.sample(0.5)

    if not is_finite(value):
        push_error("EasingCurve.sample() returned a non-finite value")
        quit(1)
        return

    print("PASS: Easing Curve release smoke")
    quit(0)
'@ | Set-Content `
            -LiteralPath (Join-Path $SmokeRoot "release_smoke.gd") `
            -Encoding UTF8

        Invoke-Godot `
            -Description "Clean-project runtime smoke test" `
            -Arguments @(
                "--headless",
                "--path", $SmokeRoot,
                "--script", "res://release_smoke.gd"
            )

        Write-Host ""
        Write-Host "Clean-project smoke test passed." `
            -ForegroundColor Green
    }
    finally {
        if ($KeepSmokeProject) {
            Write-Host "Smoke project retained at:"
            Write-Host "  $SmokeRoot"
        }
        else {
            Remove-Item `
                -LiteralPath $SmokeRoot `
                -Recurse `
                -Force `
                -ErrorAction SilentlyContinue
        }
    }
}


function Get-ChangelogReleaseNotes {
    if (-not (Test-Path -LiteralPath $Changelog)) {
        throw "Could not find changelog: $Changelog"
    }

    $Lines = @(Get-Content -LiteralPath $Changelog)
    $Heading = "## v$Version"
    $Start = -1

    for ($Index = 0; $Index -lt $Lines.Count; $Index++) {
        if ($Lines[$Index].Trim() -eq $Heading) {
            $Start = $Index
            break
        }
    }

    if ($Start -lt 0) {
        throw "CHANGELOG.md has no '$Heading' section."
    }

    $End = $Lines.Count

    for ($Index = $Start + 1; $Index -lt $Lines.Count; $Index++) {
        if ($Lines[$Index] -match '^## v\d') {
            $End = $Index
            break
        }
    }

    return (
        $Lines[$Start..($End - 1)] -join [Environment]::NewLine
    )
}


function Invoke-PrepareCommit {
    Write-Step "Prepare release commit"

    git status --short
    Assert-LastExitCode "git status"

    Write-Host ""
    $Answer = Read-Host "Stage all current release changes and commit? [y/N]"

    if ($Answer -notmatch '^[Yy]$') {
        throw "Release commit cancelled."
    }

    git add -A
    Assert-LastExitCode "git add"

    git diff --cached --check
    Assert-LastExitCode "staged diff check"

    Write-Host ""
    git diff --cached --stat

    git commit -m "Release v$Version"
    Assert-LastExitCode "git commit"

    Write-Host "Release commit created." -ForegroundColor Green
}


function Invoke-Publish {
    Write-Step "Publish $Tag"

    $CurrentBranch = (git branch --show-current).Trim()
    Assert-LastExitCode "git branch"

    if ($CurrentBranch -ne $ReleaseBranch) {
        throw (
            "Publish must run from '$ReleaseBranch'. " +
            "Current branch is '$CurrentBranch'."
        )
    }

    if (-not (Test-GitClean)) {
        throw (
            "Working tree must be clean before publishing. " +
            "Commit/merge the release candidate first."
        )
    }

    git fetch origin
    Assert-LastExitCode "git fetch"

    $RemoteOnlyCount = (
        git rev-list `
            --right-only `
            --count `
            "$ReleaseBranch...origin/$ReleaseBranch"
    ).Trim()

    Assert-LastExitCode "git rev-list"

    if ([int]$RemoteOnlyCount -ne 0) {
        throw (
            "Local '$ReleaseBranch' is behind origin. " +
            "Update it before publishing."
        )
    }

    $ExistingLocalTag = git tag --list $Tag
    Assert-LastExitCode "git tag --list"

    if ($ExistingLocalTag) {
        throw "Local tag '$Tag' already exists."
    }

    $ExistingRemoteTag = git ls-remote `
        --tags `
        origin `
        "refs/tags/$Tag"

    Assert-LastExitCode "git ls-remote"

    if ($ExistingRemoteTag) {
        throw "Remote tag '$Tag' already exists."
    }

    if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
        throw (
            "GitHub CLI 'gh' was not found. " +
            "Install/authenticate it before Publish mode."
        )
    }

    $ReleaseNotes = Get-ChangelogReleaseNotes
    $ReleaseNotesPath = Join-Path `
        ([IO.Path]::GetTempPath()) `
        ("easing-curve-{0}-release-notes.md" -f $Version)

    try {
        $ReleaseNotes |
            Set-Content `
                -LiteralPath $ReleaseNotesPath `
                -Encoding UTF8

        Write-Host ""
        Write-Host "Release notes:"
        Write-Host "--------------"
        Write-Host $ReleaseNotes
        Write-Host "--------------"
        Write-Host ""

        $Answer = Read-Host (
            "Tag, push, and publish $Tag to GitHub? [y/N]"
        )

        if ($Answer -notmatch '^[Yy]$') {
            throw "Publishing cancelled."
        }

        git tag -a $Tag -m "Release $Tag"
        Assert-LastExitCode "git tag"

        git push origin $ReleaseBranch
        Assert-LastExitCode "git push branch"

        git push origin $Tag
        Assert-LastExitCode "git push tag"

        gh release create `
            $Tag `
            $ZipPath `
            --repo $Repository `
            --title "Easing Curve $Tag" `
            --notes-file $ReleaseNotesPath `
            --latest

        Assert-LastExitCode "gh release create"

        Write-Host ""
        Write-Host "$Tag published successfully." `
            -ForegroundColor Green
    }
    finally {
        Remove-Item `
            -LiteralPath $ReleaseNotesPath `
            -Force `
            -ErrorAction SilentlyContinue
    }
}


Push-Location $ProjectRoot

try {
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
        throw "git was not found."
    }

    if (-not (Test-Path -LiteralPath $PluginConfig)) {
        throw "Run this script from the repository root."
    }

    if (-not (Test-Path -LiteralPath $BuildScript)) {
        throw "Could not find build_asset_store.ps1."
    }

    if (-not (Test-Path -LiteralPath $GodotLauncher)) {
        throw (
            "Could not find test/scripts/run_godot.ps1. " +
            "Fix the moved test-script paths first."
        )
    }

    Write-Host "Easing Curve v$Version release"
    Write-Host "Mode: $Mode"

    Assert-ReleaseVersion

    # Step 4.
    Invoke-DiffCheck

    # Step 5.
    Invoke-Build

    # build_asset_store.ps1 synchronizes README/LICENSE into the addon,
    # so validate its resulting tracked diff too.
    Invoke-DiffCheck

    # Step 6.
    Invoke-CleanInstallSmokeTest

    if ($Mode -eq "Validate") {
        Write-Host ""
        Write-Host "Release validation passed." `
            -ForegroundColor Green
        Write-Host "No commit, tag, push, or GitHub release was created."
        exit 0
    }

    if ($Mode -eq "Prepare") {
        Invoke-PrepareCommit

        Write-Host ""
        Write-Host "Release candidate prepared." `
            -ForegroundColor Green
        Write-Host (
            "Merge/fast-forward this commit into '$ReleaseBranch', " +
            "then run Publish mode there."
        )
        exit 0
    }

    if ($Mode -eq "Publish") {
        # Rebuild/smoke above ensures the uploaded ZIP came from the exact
        # release-branch working tree.
        if (-not (Test-GitClean)) {
            throw (
                "Validation/build changed tracked files. " +
                "Commit them before publishing."
            )
        }

        Invoke-Publish
    }
}
finally {
    Pop-Location
}
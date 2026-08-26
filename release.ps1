[CmdletBinding()]
param(
    [ValidateSet("Validate", "Prepare", "Publish")]
    [string]$Mode = "Validate",

    [Alias("v")]
    [ValidatePattern("^\d+\.\d+\.\d+$")]
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
$ZipPath = Join-Path $ProjectRoot "_exports\_asset_store_builds\easing_curve_v$Version.zip"

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
    $Content = Get-Content -Raw -LiteralPath $PluginConfig
    if ($Content -notmatch '(?m)^\s*version\s*=\s*"([^"]+)"\s*$') {
        throw "Could not parse version from $PluginConfig"
    }
    return $Matches[1]
}

function Set-PluginVersion {
    Write-Step "Set plugin version"

    $CurrentVersion = Get-PluginVersion
    if ($CurrentVersion -eq $Version) {
        Write-Host "plugin.cfg already uses version $Version." -ForegroundColor Green
        return
    }

    $ExpectedDevVersion = "$Version-dev"
    if ($CurrentVersion -ne $ExpectedDevVersion) {
        throw (
            "Refusing to replace plugin.cfg version '$CurrentVersion'. " +
            "Expected '$ExpectedDevVersion' or '$Version'."
        )
    }

    $Content = Get-Content -Raw -LiteralPath $PluginConfig
    $VersionRegex = [regex]'(?m)^(\s*version\s*=\s*)"[^"]+"'
    $Replacement = '${1}"' + $Version + '"'
    $Updated = $VersionRegex.Replace($Content, $Replacement, 1)

    if ($Updated -eq $Content) {
        throw "plugin.cfg version replacement produced no change."
    }

    [System.IO.File]::WriteAllText(
        $PluginConfig,
        $Updated,
        [System.Text.UTF8Encoding]::new($false)
    )

    $UpdatedVersion = Get-PluginVersion
    if ($UpdatedVersion -ne $Version) {
        throw "plugin.cfg version update failed."
    }

    Write-Host "Updated plugin.cfg: $CurrentVersion -> $UpdatedVersion" -ForegroundColor Green
}

function Assert-ChangelogEntry {
    Write-Step "Verify changelog entry"

    if (-not (Test-Path -LiteralPath $Changelog -PathType Leaf)) {
        throw "Could not find changelog: $Changelog"
    }

    $Heading = "## v$Version"
    $Found = Select-String -LiteralPath $Changelog -SimpleMatch -Pattern $Heading -Quiet
    if (-not $Found) {
        throw "CHANGELOG.md has no '$Heading' section. Finish the release notes before validating."
    }

    Write-Host "Found changelog section: $Heading" -ForegroundColor Green
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
    if ($LASTEXITCODE -ne 0) {
        throw "build_asset_store.ps1 failed with exit code $LASTEXITCODE."
    }

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

    $StdoutPath = Join-Path ([IO.Path]::GetTempPath()) ("easing-curve-release-{0}.stdout" -f [guid]::NewGuid())
    $StderrPath = Join-Path ([IO.Path]::GetTempPath()) ("easing-curve-release-{0}.stderr" -f [guid]::NewGuid())
    $PreviousPreference = $ErrorActionPreference

    try {
        $ErrorActionPreference = "Continue"
        & $GodotLauncher @Arguments 1> $StdoutPath 2> $StderrPath
        $ExitCode = $LASTEXITCODE

        $Stdout = if (Test-Path -LiteralPath $StdoutPath) { Get-Content -Raw -LiteralPath $StdoutPath } else { "" }
        $Stderr = if (Test-Path -LiteralPath $StderrPath) { Get-Content -Raw -LiteralPath $StderrPath } else { "" }

        if ($Stdout) { Write-Host $Stdout.TrimEnd() }
        if ($Stderr) { Write-Host $Stderr.TrimEnd() }

        $Combined = "$Stdout`n$Stderr"
        if ($ExitCode -ne 0) {
            throw "$Description exited with code $ExitCode."
        }
        if ($Combined -match "SCRIPT ERROR:") {
            throw "$Description reported SCRIPT ERROR."
        }
    }
    finally {
        $ErrorActionPreference = $PreviousPreference
        Remove-Item -LiteralPath $StdoutPath -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $StderrPath -Force -ErrorAction SilentlyContinue
    }
}

function Invoke-CleanInstallSmokeTest {
    Write-Step "Clean-project smoke test"

    if (-not (Test-Path -LiteralPath $ZipPath -PathType Leaf)) {
        throw "Release ZIP does not exist: $ZipPath"
    }

    $SmokeRoot = Join-Path ([IO.Path]::GetTempPath()) ("easing-curve-v{0}-smoke-{1}" -f $Version, [guid]::NewGuid())
    New-Item -ItemType Directory -Path $SmokeRoot -Force | Out-Null

    try {
        Write-Host "Extracting exact release ZIP to:"
        Write-Host "  $SmokeRoot"

        Expand-Archive -LiteralPath $ZipPath -DestinationPath $SmokeRoot -Force

        $ExtractedConfig = Join-Path $SmokeRoot "addons\easing_curve\plugin.cfg"
        if (-not (Test-Path -LiteralPath $ExtractedConfig -PathType Leaf)) {
            throw "Extracted archive is missing plugin.cfg."
        }

        $ExtractedConfigText = Get-Content -Raw -LiteralPath $ExtractedConfig
        if ($ExtractedConfigText -notmatch '(?m)^\s*version\s*=\s*"([^"]+)"\s*$') {
            throw "Could not parse extracted plugin version."
        }

        if ($Matches[1] -ne $Version) {
            throw "Extracted plugin version '$($Matches[1])' does not match '$Version'."
        }

        @"
[application]

config/name="Easing Curve Release Smoke"

[editor_plugins]

enabled=PackedStringArray("res://addons/easing_curve/plugin.cfg")

[rendering]

renderer/rendering_method="gl_compatibility"
renderer/rendering_method.mobile="gl_compatibility"
"@ | Set-Content -LiteralPath (Join-Path $SmokeRoot "project.godot") -Encoding UTF8

        Invoke-Godot `
            -Description "Clean-project Editor smoke test" `
            -Arguments @(
                "--editor",
                "--headless",
                "--path", $SmokeRoot,
                "--quit-after", "2"
            )

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
'@ | Set-Content -LiteralPath (Join-Path $SmokeRoot "release_smoke.gd") -Encoding UTF8

        Invoke-Godot `
            -Description "Clean-project runtime smoke test" `
            -Arguments @(
                "--headless",
                "--path", $SmokeRoot,
                "--script", "res://release_smoke.gd"
            )

        Write-Host ""
        Write-Host "Clean-project smoke test passed." -ForegroundColor Green
    }
    finally {
        if ($KeepSmokeProject) {
            Write-Host "Smoke project retained at:"
            Write-Host "  $SmokeRoot"
        }
        else {
            Remove-Item -LiteralPath $SmokeRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

function Get-ChangelogReleaseNotes {
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

    return ($Lines[$Start..($End - 1)] -join [Environment]::NewLine)
}

function Invoke-PrepareCommit {
    Write-Step "Prepare release commit"
	
	if (Test-GitClean) {
        $Head = (git log -1 --oneline).Trim()
        Assert-LastExitCode "git log"

        Write-Host "Working tree is already clean; no release commit is needed." `
            -ForegroundColor Green
        Write-Host "Current HEAD:"
        Write-Host "  $Head"
        return
    }

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
    Assert-LastExitCode "git diff --cached --stat"

    git commit -m "Release v$Version"
    Assert-LastExitCode "git commit"

    Write-Host "Release commit created." -ForegroundColor Green
}

function Invoke-Publish {
    Write-Step "Publish $Tag"

    $CurrentBranch = (git branch --show-current).Trim()
    Assert-LastExitCode "git branch"

    if ($CurrentBranch -ne $ReleaseBranch) {
        throw "Publish must run from '$ReleaseBranch'. Current branch is '$CurrentBranch'."
    }

    if (-not (Test-GitClean)) {
        throw "Working tree must be clean before publishing."
    }

    git fetch origin
    Assert-LastExitCode "git fetch"

    $RemoteOnlyCount = (git rev-list --right-only --count "$ReleaseBranch...origin/$ReleaseBranch").Trim()
    Assert-LastExitCode "git rev-list"

    if ([int]$RemoteOnlyCount -ne 0) {
        throw "Local '$ReleaseBranch' is behind origin. Update it before publishing."
    }

    $ExistingLocalTag = git tag --list $Tag
    Assert-LastExitCode "git tag --list"
    if ($ExistingLocalTag) {
        throw "Local tag '$Tag' already exists."
    }

    $ExistingRemoteTag = git ls-remote --tags origin "refs/tags/$Tag"
    Assert-LastExitCode "git ls-remote"
    if ($ExistingRemoteTag) {
        throw "Remote tag '$Tag' already exists."
    }

    if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
        throw "GitHub CLI 'gh' was not found. Install/authenticate it before Publish mode."
    }

    $ReleaseNotes = Get-ChangelogReleaseNotes
    $ReleaseNotesPath = Join-Path ([IO.Path]::GetTempPath()) ("easing-curve-{0}-release-notes.md" -f $Version)

    try {
        [System.IO.File]::WriteAllText(
            $ReleaseNotesPath,
            $ReleaseNotes,
            [System.Text.UTF8Encoding]::new($false)
        )

        Write-Host ""
        Write-Host "Release notes:"
        Write-Host "--------------"
        Write-Host $ReleaseNotes
        Write-Host "--------------"
        Write-Host ""

        $Answer = Read-Host "Tag, push, and publish $Tag to GitHub? [y/N]"
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
        Write-Host "$Tag published successfully." -ForegroundColor Green
    }
    finally {
        Remove-Item -LiteralPath $ReleaseNotesPath -Force -ErrorAction SilentlyContinue
    }
}

Push-Location $ProjectRoot

try {
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
        throw "git was not found."
    }

    if (-not (Test-Path -LiteralPath $PluginConfig -PathType Leaf)) {
        throw "Run this script from the repository root."
    }

    if (-not (Test-Path -LiteralPath $BuildScript -PathType Leaf)) {
        throw "Could not find build_asset_store.ps1."
    }

    if (-not (Test-Path -LiteralPath $GodotLauncher -PathType Leaf)) {
        throw "Could not find test/scripts/run_godot.ps1."
    }

    Write-Host "Easing Curve v$Version release"
    Write-Host "Mode: $Mode"

    # Safe to rerun: 1.0.6-dev -> 1.0.6, or leaves 1.0.6 unchanged.
    Set-PluginVersion

    # Step 2 is still manual; this verifies it was done before release validation.
    Assert-ChangelogEntry

    # Step 4.
    Invoke-DiffCheck

    # Step 5.
    Invoke-Build

    # The build syncs root README/LICENSE into the packaged addon.
    Invoke-DiffCheck

    # Step 6.
    Invoke-CleanInstallSmokeTest

    if ($Mode -eq "Validate") {
        Write-Host ""
        Write-Host "Release validation passed." -ForegroundColor Green
        Write-Host "plugin.cfg is now version $Version."
        Write-Host "No commit, tag, push, or GitHub release was created."
        exit 0
    }

    if ($Mode -eq "Prepare") {
        Invoke-PrepareCommit

        Write-Host ""
        Write-Host "Release candidate prepared." -ForegroundColor Green
        Write-Host "Merge/fast-forward this commit into '$ReleaseBranch', then run Publish mode there."
        exit 0
    }

    if ($Mode -eq "Publish") {
        if (-not (Test-GitClean)) {
            throw "Validation/build changed tracked files. Commit them before publishing."
        }

        Invoke-Publish
    }
}
finally {
    Pop-Location
}

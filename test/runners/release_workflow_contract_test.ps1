$ErrorActionPreference = "Stop"

$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$ReleaseScript = Join-Path $ProjectRoot "release.ps1"
$Tokens = $null
$ParseErrors = $null
$ReleaseAst = [System.Management.Automation.Language.Parser]::ParseFile(
    $ReleaseScript,
    [ref]$Tokens,
    [ref]$ParseErrors
)

if ($ParseErrors.Count -gt 0) {
    throw "release.ps1 has PowerShell parse errors: $($ParseErrors -join '; ')"
}

$FunctionDefinitions = @($ReleaseAst.FindAll({
    param($Node)
    $Node -is [System.Management.Automation.Language.FunctionDefinitionAst]
}, $true))


function Assert-Contract {
    param(
        [bool]$Condition,
        [string]$Message
    )

    if (-not $Condition) {
        throw $Message
    }
}


function Assert-Throws {
    param(
        [scriptblock]$Action,
        [string]$Message
    )

    try {
        & $Action
    }
    catch {
        return
    }

    throw $Message
}


function Get-ReleaseFunctionDefinition {
    param([string]$Name)

    $Definition = $FunctionDefinitions |
        Where-Object { $_.Name -eq $Name } |
        Select-Object -First 1
    if ($null -eq $Definition) {
        throw "release.ps1 is missing required function '$Name'."
    }
    return $Definition
}


function Import-ReleaseFunctionDefinition {
    param([string]$Name)

    $Definition = Get-ReleaseFunctionDefinition -Name $Name
    Invoke-Expression "function script:$Name $($Definition.Body.Extent.Text)"
}


$RequiredHelpers = @(
    "Assert-LastExitCode",
    "Test-GitClean",
    "Assert-ReleaseBranchAndCleanTree",
    "Assert-ReleaseRemoteCurrency",
    "Assert-GitHubCliAvailable",
    "New-ReleaseNotesFile",
    "Remove-ReleaseNotesFile",
    "Write-ReleaseNotesPreview",
    "Publish-NewReleaseGitRefs",
    "Update-ExistingReleaseGitRefs",
    "New-GitHubRelease",
    "Update-GitHubRelease",
    "Assert-ReleaseTagTarget",
    "Show-GitHubRelease",
    "Get-NextDevelopmentVersion"
)
foreach ($HelperName in $RequiredHelpers) {
    Import-ReleaseFunctionDefinition -Name $HelperName
}

$PublishText = (Get-ReleaseFunctionDefinition -Name "Invoke-Publish").Extent.Text
$RepublishText = (Get-ReleaseFunctionDefinition -Name "Invoke-Republish").Extent.Text
foreach ($RequiredCall in @(
    "Assert-ReleaseBranchAndCleanTree",
    "Assert-ReleaseRemoteCurrency",
    "New-ReleaseNotesFile",
    "Publish-NewReleaseGitRefs",
    "New-GitHubRelease",
    "Assert-ReleaseTagTarget"
)) {
    Assert-Contract ($PublishText.Contains($RequiredCall)) "Publish does not call '$RequiredCall'."
}
foreach ($RequiredCall in @(
    "Assert-ReleaseBranchAndCleanTree",
    "Assert-ReleaseRemoteCurrency",
    "New-ReleaseNotesFile",
    "Update-ExistingReleaseGitRefs",
    "Update-GitHubRelease",
    "Assert-ReleaseTagTarget"
)) {
    Assert-Contract ($RepublishText.Contains($RequiredCall)) "Republish does not call '$RequiredCall'."
}
foreach ($Flow in @($PublishText, $RepublishText)) {
    Assert-Contract ($Flow -notmatch '(?m)^\s*git\s+push\b') "Top-level release flow contains a direct git push."
    Assert-Contract ($Flow -notmatch '(?m)^\s*gh\s+release\s+(create|upload|edit)\b') "Top-level release flow contains direct GitHub release mutation."
    Assert-Contract ($Flow -notmatch 'System[.]IO[.]File') "Top-level release flow owns release-note file I/O."
}
Assert-Contract (
    $PublishText.IndexOf("Publish-NewReleaseGitRefs") -lt
        $PublishText.IndexOf("Assert-ReleaseTagTarget") -and
    $PublishText.IndexOf("Assert-ReleaseTagTarget") -lt
        $PublishText.IndexOf("New-GitHubRelease")
) "Publish must verify published Git refs before creating the GitHub release."
Assert-Contract (
    $RepublishText.IndexOf("Update-ExistingReleaseGitRefs") -lt
        $RepublishText.IndexOf("Assert-ReleaseTagTarget") -and
    $RepublishText.IndexOf("Assert-ReleaseTagTarget") -lt
        $RepublishText.IndexOf("Update-GitHubRelease")
) "Republish must verify updated Git refs before mutating the GitHub release."

$script:MockRemoteOnlyCount = "0"
$script:MockTagType = "tag"
$script:MockLocalTagCommit = "abc123"
$script:MockRemoteTagCommit = "abc123"
function global:git {
    $global:LASTEXITCODE = 0
    if ($args[0] -eq "branch") { return "master" }
    if ($args[0] -eq "status") { return }
    if ($args[0] -eq "fetch") { return }
    if ($args[0] -eq "rev-list" -and $args[1] -eq "--right-only") {
        return $script:MockRemoteOnlyCount
    }
    if ($args[0] -eq "cat-file") { return $script:MockTagType }
    if ($args[0] -eq "rev-list") { return $script:MockLocalTagCommit }
    if ($args[0] -eq "ls-remote") {
        return "$($script:MockRemoteTagCommit)`trefs/tags/v-test^{}"
    }
    throw "Unexpected mocked git invocation: $args"
}

$ReleaseBranch = "master"
$Tag = "v-test"
Assert-ReleaseBranchAndCleanTree -ModeName "Publish" -ActionName "publishing"
Assert-ReleaseRemoteCurrency -ActionName "publishing"

$script:MockRemoteOnlyCount = "1"
Assert-Throws {
    Assert-ReleaseRemoteCurrency -ActionName "publishing"
} "Behind-origin validation did not reject a remote-only commit."
$script:MockRemoteOnlyCount = "0"

Assert-ReleaseTagTarget -ExpectedCommit "abc123"
$script:MockTagType = "commit"
Assert-Throws {
    Assert-ReleaseTagTarget -ExpectedCommit "abc123"
} "Lightweight-tag validation did not reject a non-annotated tag."
$script:MockTagType = "tag"
$script:MockRemoteTagCommit = "different"
Assert-Throws {
    Assert-ReleaseTagTarget -ExpectedCommit "abc123"
} "Remote tag validation did not reject a mismatched target."

$Version = "contract-" + [guid]::NewGuid().ToString("N")
function Get-ChangelogReleaseNotes {
    return "contract release notes"
}

$ReleaseNotesFile = $null
try {
    $ReleaseNotesFile = New-ReleaseNotesFile
    Assert-Contract (
        Test-Path -LiteralPath $ReleaseNotesFile.Path -PathType Leaf
    ) "Release-notes file was not created."
    Assert-Contract (
        (Get-Content -Raw -LiteralPath $ReleaseNotesFile.Path) -eq "contract release notes"
    ) "Release-notes contents changed."
}
finally {
    Remove-ReleaseNotesFile -ReleaseNotesFile $ReleaseNotesFile
}
Assert-Contract (
    -not (Test-Path -LiteralPath $ReleaseNotesFile.Path)
) "Release-notes file was not removed."

$Version = "1.2.3"
Assert-Contract (
    (Get-NextDevelopmentVersion) -eq "1.2.4-dev"
) "Next development version calculation changed."

Write-Host "PASS: release workflow helper contracts"

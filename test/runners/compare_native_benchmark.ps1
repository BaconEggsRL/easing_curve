[CmdletBinding()]
param(
	[Parameter(Mandatory = $true)]
	[string]$BaselinePath,
	[Parameter(Mandatory = $true)]
	[string]$CandidatePath,
	[double]$MinimumTolerance = 0.03
)

$ErrorActionPreference = "Stop"

function Read-NativeMeasurements {
	param([string]$Path)

	$resolvedPath = (Resolve-Path -LiteralPath $Path -ErrorAction Stop).Path
	$measurements = @{}
	foreach ($line in Get-Content -LiteralPath $resolvedPath) {
		if ($line -notmatch '^COMPARE\|([^|]+)\|native_usec=([0-9.]+)\|native_mad=([0-9.]+)\|') {
			continue
		}
		$measurements[$Matches[1]] = @{
			Median = [double]$Matches[2]
			Mad = [double]$Matches[3]
		}
	}
	if ($measurements.Count -eq 0) {
		throw "No Native COMPARE measurements were found in $resolvedPath"
	}
	return $measurements
}

$baseline = Read-NativeMeasurements -Path $BaselinePath
$candidate = Read-NativeMeasurements -Path $CandidatePath
$failures = @()

foreach ($label in $baseline.Keys | Sort-Object) {
	if (-not $candidate.ContainsKey($label)) {
		$failures += "$label is missing from the candidate report"
		continue
	}
	$reference = $baseline[$label]
	$current = $candidate[$label]
	$noiseAllowance = [Math]::Max(
		$reference.Median * $MinimumTolerance,
		[Math]::Max(3.0 * $reference.Mad, 3.0 * $current.Mad)
	)
	$limit = $reference.Median + $noiseAllowance
	$status = if ($current.Median -le $limit) { "PASS" } else { "REGRESSION" }
	Write-Host ("{0}|{1}|baseline={2:N1}|candidate={3:N1}|limit={4:N1}" -f $status, $label, $reference.Median, $current.Median, $limit)
	if ($status -eq "REGRESSION") {
		$failures += "${label}: $($current.Median) usec exceeds the noise-aware limit $limit usec"
	}
}

foreach ($label in $candidate.Keys) {
	if (-not $baseline.ContainsKey($label)) {
		Write-Host "NEW|$label|candidate=$($candidate[$label].Median)"
	}
}

if ($failures.Count -gt 0) {
	throw "Native benchmark regression gate failed:`n$($failures -join "`n")"
}

Write-Host "PASS: all $($baseline.Count) baseline cases stayed within the noise-aware envelope."

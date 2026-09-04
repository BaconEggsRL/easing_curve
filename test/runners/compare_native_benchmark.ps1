[CmdletBinding()]
param(
	[string]$BaselinePath = "",
	[Parameter(Mandatory = $true)]
	[string[]]$CandidatePath,
	[double]$MinimumTolerance = 0.03
)

$ErrorActionPreference = "Stop"

function Get-Median {
	param([double[]]$Values)
	$sorted = @($Values | Sort-Object)
	if ($sorted.Count -eq 0) {
		throw "Cannot calculate the median of an empty measurement set."
	}
	return [double]$sorted[[int][Math]::Floor($sorted.Count / 2)]
}

function Read-NativeMeasurements {
	param(
		[string]$Path,
		[bool]$RequireCompetitor = $true
	)

	$resolvedPath = (Resolve-Path -LiteralPath $Path -ErrorAction Stop).Path
	$measurements = @{}
	foreach ($line in Get-Content -LiteralPath $resolvedPath) {
		if ($line -notmatch '^COMPARE\|(?<label>[^|]+)\|native_usec=(?<median>[0-9.]+)\|native_mad=(?<mad>[0-9.]+)\|(?:(?<competitor>[^|]+)_usec=(?<competitor_median>[0-9.]+)\|[^|]+_mad=(?<competitor_mad>[0-9.]+)\|)?') {
			continue
		}
		$label = $Matches.label
		$median = [double]$Matches.median
		$mad = [double]$Matches.mad
		$competitor = $Matches.competitor
		$competitorMedian = if ($competitor) { [double]$Matches.competitor_median } else { 0.0 }
		$competitorMad = if ($competitor) { [double]$Matches.competitor_mad } else { 0.0 }
		if (-not $competitor -and $RequireCompetitor) {
			throw "Candidate benchmark case $label has no comparison measurement in $resolvedPath"
		}
		$measurements[$label] = @{
			Median = $median
			Mad = $mad
			Competitor = $competitor
			CompetitorMedian = $competitorMedian
			CompetitorMad = $competitorMad
		}
	}
	if ($measurements.Count -eq 0) {
		throw "No Native COMPARE measurements were found in $resolvedPath"
	}
	return $measurements
}

function Merge-NativeMeasurements {
	param([object[]]$Reports)
	$labels = @($Reports[0].Keys | Sort-Object)
	$merged = @{}
	foreach ($label in $labels) {
		$nativeMedians = @()
		$nativeMads = @()
		$competitorMedians = @()
		$competitorMads = @()
		$competitor = $Reports[0][$label].Competitor
		foreach ($report in $Reports) {
			if (-not $report.ContainsKey($label)) {
				throw "$label is missing from one candidate benchmark report."
			}
			if ($report[$label].Competitor -ne $competitor) {
				throw "$label changed competitor across candidate benchmark reports."
			}
			$nativeMedians += $report[$label].Median
			$nativeMads += $report[$label].Mad
			$competitorMedians += $report[$label].CompetitorMedian
			$competitorMads += $report[$label].CompetitorMad
		}
		$merged[$label] = @{
			Median = Get-Median -Values $nativeMedians
			Mad = Get-Median -Values $nativeMads
			Competitor = $competitor
			CompetitorMedian = Get-Median -Values $competitorMedians
			CompetitorMad = Get-Median -Values $competitorMads
		}
	}
	return $merged
}

$candidateReports = @()
foreach ($path in $CandidatePath) {
	$candidateReports += ,(Read-NativeMeasurements -Path $path)
}
$candidate = Merge-NativeMeasurements -Reports $candidateReports
$failures = @()

foreach ($label in $candidate.Keys | Sort-Object) {
	$current = $candidate[$label]
	$relativeStatus = if ($current.Median -lt $current.CompetitorMedian) { "PASS" } else { "REGRESSION" }
	Write-Host ("{0}|{1}|native={2:N1}|{3}={4:N1}|runs={5}" -f $relativeStatus, $label, $current.Median, $current.Competitor, $current.CompetitorMedian, $CandidatePath.Count)
	if ($relativeStatus -eq "REGRESSION") {
		$failures += "${label}: Native $($current.Median) usec is not faster than $($current.Competitor) $($current.CompetitorMedian) usec"
	}
}

if (-not [string]::IsNullOrWhiteSpace($BaselinePath)) {
	$baseline = Read-NativeMeasurements -Path $BaselinePath -RequireCompetitor $false
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
		Write-Host ("{0}|{1}|baseline={2:N1}|candidate_median_of_medians={3:N1}|limit={4:N1}" -f $status, $label, $reference.Median, $current.Median, $limit)
		if ($status -eq "REGRESSION") {
			$failures += "${label}: $($current.Median) usec exceeds the noise-aware limit $limit usec"
		}
	}

	foreach ($label in $candidate.Keys) {
		if (-not $baseline.ContainsKey($label)) {
			Write-Host "NEW|$label|candidate=$($candidate[$label].Median)"
		}
	}
}

if ($failures.Count -gt 0) {
	throw "Native benchmark regression gate failed:`n$($failures -join "`n")"
}

$absoluteMessage = if ([string]::IsNullOrWhiteSpace($BaselinePath)) { "without an absolute baseline" } else { "inside the absolute noise-aware envelope" }
Write-Host "PASS: all $($candidate.Count) aggregate Native cases beat their comparison and completed $absoluteMessage."

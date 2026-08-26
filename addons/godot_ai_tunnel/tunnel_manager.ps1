param(
    [switch]$Start,
    [switch]$Kill,
    [switch]$Probe
)

# Also support Unix-style arguments.
if ($args -contains "--start") {
    $Start = $true
}

if ($args -contains "--kill") {
    $Kill = $true
}

if ($args -contains "--probe") {
    $Probe = $true
}

$ErrorActionPreference = "Stop"

$TunnelClient = Join-Path $PSScriptRoot "tunnel-client.exe"
$Profile = "godot-ai"
$HealthListenAddr = "127.0.0.1:18080"


function Get-TunnelProcesses {
    $Processes = @{}

    # First identify the process actually owning the tunnel health port.
    $Port = [int](($HealthListenAddr -split ":")[-1])

    $Listeners = Get-NetTCPConnection `
        -State Listen `
        -LocalPort $Port `
        -ErrorAction SilentlyContinue

    foreach ($Listener in $Listeners) {
        $Process = Get-Process `
            -Id $Listener.OwningProcess `
            -ErrorAction SilentlyContinue

        if ($Process) {
            $Processes[$Process.Id] = $Process
        }
    }

    # Also include tunnel-client processes that may still be starting
    # and have not opened the health listener yet.
    $NamedProcesses = Get-Process `
        -Name "tunnel-client" `
        -ErrorAction SilentlyContinue

    foreach ($Process in $NamedProcesses) {
        $Processes[$Process.Id] = $Process
    }

    return @($Processes.Values)
}


function Show-Help {
    Write-Host ""
    Write-Host "Godot AI Tunnel Startup Helper"
    Write-Host ""
    Write-Host "Usage:"
    Write-Host "  .\_STARTUP.ps1 --start"
    Write-Host "  .\_STARTUP.ps1 --kill"
    Write-Host "  .\_STARTUP.ps1 --probe"
    Write-Host ""
    Write-Host "Commands:"
    Write-Host "  --start   Start a fresh godot-ai tunnel."
    Write-Host "            If tunnel-client is already running, prompts before"
    Write-Host "            stopping the existing process(es) and restarting."
    Write-Host ""
    Write-Host "  --kill    Stop all running tunnel-client processes and exit."
    Write-Host ""
    Write-Host "  --probe   List all running tunnel-client processes and exit."
    Write-Host "            Does not start, stop, or modify any processes."
    Write-Host ""
}


# No command: show available commands and exit.
if (-not $Start -and -not $Kill -and -not $Probe) {
    Show-Help
    exit 0
}


# Reject conflicting commands.
$CommandCount = @($Start, $Kill, $Probe).Where({ $_ }).Count

if ($CommandCount -gt 1) {
    Write-Error "Specify only one command: --start, --kill, or --probe."
    exit 1
}


# Probe-only mode.
if ($Probe) {
    $ExistingProcesses = Get-TunnelProcesses

    if (-not $ExistingProcesses) {
        Write-Host "No tunnel-client processes are running."
        exit 0
    }

    Write-Host "Running tunnel-client process(es):"

    foreach ($Process in $ExistingProcesses) {
        Write-Host "  $($Process.ProcessName) (PID $($Process.Id))"
    }

    exit 0
}


# Kill-only mode.
if ($Kill) {
    $ExistingProcesses = Get-TunnelProcesses

    if (-not $ExistingProcesses) {
        Write-Host "No tunnel-client processes are running."
        exit 0
    }

    Write-Host "Stopping tunnel-client process(es)..."

    foreach ($Process in $ExistingProcesses) {
        Write-Host "  Killing $($Process.ProcessName) (PID $($Process.Id))"
        Stop-Process -Id $Process.Id -Force
        Wait-Process -Id $Process.Id -ErrorAction SilentlyContinue
    }

    Write-Host "All tunnel-client processes stopped."
    exit 0
}


# Start mode begins here.
if (-not (Test-Path $TunnelClient)) {
    Write-Error "tunnel-client.exe not found at: $TunnelClient"
    exit 1
}

$ExistingProcesses = Get-TunnelProcesses

if ($ExistingProcesses) {
    Write-Host "Existing tunnel-client process(es) detected:"

    foreach ($Process in $ExistingProcesses) {
        Write-Host "  $($Process.ProcessName) (PID $($Process.Id))"
    }

    $Response = Read-Host "Kill existing process(es) and restart? (Y/N)"

    if ($Response -notmatch '^[Yy]$') {
        Write-Host "Restart cancelled by user."
        exit 0
    }

    Write-Host "Stopping existing tunnel-client process(es)..."

    foreach ($Process in $ExistingProcesses) {
        Write-Host "  Killing $($Process.ProcessName) (PID $($Process.Id))"
        Stop-Process -Id $Process.Id -Force
        Wait-Process -Id $Process.Id -ErrorAction SilentlyContinue
    }
}

# Doctor is intentionally not run on every startup.
# Run manually when troubleshooting:
#
# .\tunnel-client.exe doctor `
#     --profile godot-ai `
#     --explain `
#     --health.listen-addr 127.0.0.1:18080

Write-Host "Starting godot-ai tunnel..."

try {
    $Process = Start-Process `
        -FilePath $TunnelClient `
        -ArgumentList @(
            "run",
            "--profile", $Profile,
            "--health.listen-addr", $HealthListenAddr
        ) `
        -WindowStyle Hidden `
        -PassThru
}
catch {
    if ($_.Exception.Message -match "operation was canceled by the user") {
        Write-Host "Startup cancelled by user."
        exit 0
    }

    throw
}

Start-Sleep -Milliseconds 500

if (Get-Process -Id $Process.Id -ErrorAction SilentlyContinue) {
    Write-Host "godot-ai tunnel is running (PID $($Process.Id))."
}
else {
    Write-Error "godot-ai tunnel failed to stay running."
    exit 1
}
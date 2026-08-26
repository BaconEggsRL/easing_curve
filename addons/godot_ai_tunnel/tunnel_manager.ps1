param(
    [switch]$Start,
    [switch]$Kill,
    [switch]$Probe
)

# tunnel_manager.ps1
#
# Manual helper for the Godot AI tunnel plugin.
#
# Configuration is intentionally kept in tunnel_config.json beside this script.
# The real tunnel_config.json should remain local/private and is git-ignored.
# Copy tunnel_config.example.json to tunnel_config.json, then set
# executable_path to the full path of tunnel-client.exe.
#
# Usage:
#   .\tunnel_manager.ps1 --start
#   .\tunnel_manager.ps1 --kill
#   .\tunnel_manager.ps1 --probe
#
# --start  Starts the configured tunnel. If one is already running, prompts
#          before killing it and restarting.
# --kill   Stops tunnel-client processes discovered by the configured health
#          port and by process name.
# --probe  Lists matching tunnel-client processes without changing anything.

if ($args -contains "--start") { $Start = $true }
if ($args -contains "--kill") { $Kill = $true }
if ($args -contains "--probe") { $Probe = $true }

$ErrorActionPreference = "Stop"

$ConfigPath = Join-Path $PSScriptRoot "tunnel_config.json"

if (-not (Test-Path $ConfigPath)) {
    Write-Error (
        "Missing tunnel_config.json: $ConfigPath" + [Environment]::NewLine +
        "Copy tunnel_config.example.json to tunnel_config.json and configure executable_path."
    )
    exit 1
}

try {
    $Config = Get-Content $ConfigPath -Raw | ConvertFrom-Json
}
catch {
    Write-Error "Invalid JSON in tunnel_config.json: $ConfigPath"
    exit 1
}

$TunnelClient = [string]$Config.executable_path
$Profile = [string]$Config.profile
$HealthListenAddr = [string]$Config.health_listen_addr

if ([string]::IsNullOrWhiteSpace($Profile)) {
    $Profile = "godot-ai"
}

if ([string]::IsNullOrWhiteSpace($HealthListenAddr)) {
    $HealthListenAddr = "127.0.0.1:18080"
}


function Get-TunnelProcesses {
    $Processes = @{}

    $PortText = ($HealthListenAddr -split ":")[-1]

    if ($PortText -match '^\d+$') {
        $Port = [int]$PortText

        $Listeners = Get-NetTCPConnection -State Listen -LocalPort $Port -ErrorAction SilentlyContinue

        foreach ($Listener in $Listeners) {
            $Process = Get-Process -Id $Listener.OwningProcess -ErrorAction SilentlyContinue

            if ($Process) {
                $Processes[$Process.Id] = $Process
            }
        }
    }

    $NamedProcesses = Get-Process -Name "tunnel-client" -ErrorAction SilentlyContinue

    foreach ($Process in $NamedProcesses) {
        $Processes[$Process.Id] = $Process
    }

    return @($Processes.Values)
}


function Show-Help {
    Write-Host ""
    Write-Host "Godot AI Tunnel Manager"
    Write-Host ""
    Write-Host "Config:"
    Write-Host "  $ConfigPath"
    Write-Host ""
    Write-Host "Usage:"
    Write-Host "  .\tunnel_manager.ps1 --start"
    Write-Host "  .\tunnel_manager.ps1 --kill"
    Write-Host "  .\tunnel_manager.ps1 --probe"
    Write-Host ""
    Write-Host "Commands:"
    Write-Host "  --start   Start a fresh godot-ai tunnel."
    Write-Host "            If tunnel-client is already running, prompts before"
    Write-Host "            stopping the existing process(es) and restarting."
    Write-Host ""
    Write-Host "  --kill    Stop all detected tunnel-client processes and exit."
    Write-Host ""
    Write-Host "  --probe   List all detected tunnel-client processes and exit."
    Write-Host "            Does not start, stop, or modify any processes."
    Write-Host ""
}


if (-not $Start -and -not $Kill -and -not $Probe) {
    Show-Help
    exit 0
}

$CommandCount = @($Start, $Kill, $Probe).Where({ $_ }).Count

if ($CommandCount -gt 1) {
    Write-Error "Specify only one command: --start, --kill, or --probe."
    exit 1
}


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


if ([string]::IsNullOrWhiteSpace($TunnelClient)) {
    Write-Error "executable_path is missing or empty in tunnel_config.json."
    exit 1
}

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

Write-Host "Starting godot-ai tunnel..."

try {
    $Process = Start-Process -FilePath $TunnelClient -ArgumentList @(
        "run",
        "--profile", $Profile,
        "--health.listen-addr", $HealthListenAddr
    ) -WindowStyle Hidden -PassThru
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

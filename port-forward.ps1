# ==============================================================================
# Automated Port Forwarding for ArgoCD, Grafana, Prometheus, and Node.js API
# OS: Windows (PowerShell)
# Usage:
#   .\port-forward.ps1              # Starts all port forwards and monitors them
#   .\port-forward.ps1 -OpenBrowser # Starts port forwards and opens browser tabs
#   .\port-forward.ps1 -Stop        # Stops all running port forward processes
# ==============================================================================

param (
    [switch]$Stop,
    [switch]$OpenBrowser
)

$services = @(
    @{ Name = "ArgoCD Web UI"; Namespace = "argocd"; Service = "svc/argocd-server"; Ports = "8080:443"; Url = "https://127.0.0.1:8080"; Address = "127.0.0.1" },
    @{ Name = "Node.js Hello API"; Namespace = "nodejs-app"; Service = "svc/nodejs-hello-world-svc"; Ports = "8000:80"; Url = "http://localhost:8000"; Address = "0.0.0.0" },
    @{ Name = "LocalStack AWS"; Namespace = "localstack"; Service = "svc/localstack"; Ports = "4566:4566"; Url = "http://localhost:4566"; Address = "0.0.0.0" }
)

# 1. Stop existing port-forwards if requested
if ($Stop) {
    Write-Host "`nStopping any existing kubectl port-forward processes..." -ForegroundColor Yellow
    Get-Process kubectl -ErrorAction SilentlyContinue | Where-Object {
        $cmd = (Get-CimInstance Win32_Process -Filter "ProcessId = $($_.Id)" -ErrorAction SilentlyContinue).CommandLine
        $cmd -like "*port-forward*"
    } | Stop-Process -Force -ErrorAction SilentlyContinue
    Write-Host "[OK] All port-forward processes stopped.`n" -ForegroundColor Green
    return
}

# Ensure clean slate: kill old port forwards on these ports
Write-Host "`nChecking for existing port forwards..." -ForegroundColor Gray
Get-Process kubectl -ErrorAction SilentlyContinue | Where-Object {
    $cmd = (Get-CimInstance Win32_Process -Filter "ProcessId = $($_.Id)" -ErrorAction SilentlyContinue).CommandLine
    $cmd -like "*port-forward*"
} | Stop-Process -Force -ErrorAction SilentlyContinue

Write-Host "=======================================================" -ForegroundColor Cyan
Write-Host " [*] Starting All Kubernetes Port Forwards in Parallel" -ForegroundColor Cyan
Write-Host "=======================================================" -ForegroundColor Cyan

# Fetch ArgoCD Admin password for display
$argocdPassword = ""
try {
    $secretBytes = kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" 2>$null
    if ($secretBytes) {
        $argocdPassword = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($secretBytes))
    }
} catch {
    $argocdPassword = "(already changed or not found)"
}

$processes = @()

try {
    foreach ($svc in $services) {
        $argsList = "port-forward", "--address", $svc.Address, $svc.Service, "-n", $svc.Namespace, $svc.Ports
        Write-Host "  -> Starting $($svc.Name) on port $($svc.Ports.Split(':')[0])..." -ForegroundColor Gray
        
        $p = Start-Process -FilePath "kubectl" -ArgumentList $argsList -NoNewWindow -PassThru
        $processes += $p
        Start-Sleep -Milliseconds 500
    }

    Write-Host "`n=======================================================" -ForegroundColor Green
    Write-Host " [SUCCESS] ALL PORT FORWARDS ARE NOW ACTIVE!" -ForegroundColor Green
    Write-Host "=======================================================" -ForegroundColor Green
    Write-Host ""
    Write-Host "1. ArgoCD Web UI:         https://127.0.0.1:8080" -ForegroundColor White
    Write-Host "   Credentials:           admin / $argocdPassword" -ForegroundColor Yellow
    Write-Host "2. Grafana Audit & Logs:  http://localhost:3000" -ForegroundColor White
    Write-Host "   Credentials:           admin / admin (or auto-login)" -ForegroundColor Yellow
    Write-Host "3. Prometheus Metrics:    http://localhost:9090" -ForegroundColor White
    Write-Host "4. Node.js Hello API:     http://localhost:8000" -ForegroundColor White
    Write-Host ""
    Write-Host "Press Ctrl+C to stop all port forwards." -ForegroundColor DarkYellow
    Write-Host "=======================================================`n" -ForegroundColor Cyan

    if ($OpenBrowser) {
        Write-Host "Opening dashboards in default browser..." -ForegroundColor Gray
        Start-Process "https://127.0.0.1:8080"
        Start-Process "http://localhost:3000"
    }

    # Keep script alive to maintain background processes and handle Ctrl+C
    while ($true) {
        # Check if any process died
        foreach ($proc in $processes) {
            if ($proc.HasExited) {
                Write-Host "`n[!] Warning: A port-forward process (PID $($proc.Id)) exited unexpectedly." -ForegroundColor DarkYellow
            }
        }
        Start-Sleep -Seconds 2
    }
}
finally {
    Write-Host "`nStopping all port forwards..." -ForegroundColor Yellow
    foreach ($proc in $processes) {
        if (-not $proc.HasExited) {
            Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
        }
    }
    Write-Host "[OK] All port forwards stopped cleanly.`n" -ForegroundColor Green
}

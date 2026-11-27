# ==============================================================================
# Helper Script to View Terminal Audit Logs in LocalStack CloudWatch
# Usage: .\get-cloudwatch-logs.ps1 [-Follow]
# ==============================================================================
param (
    [switch]$Follow
)

Write-Host "=======================================================" -ForegroundColor Cyan
Write-Host " [CloudWatch Logs] Querying /aws/eks/audit/terminal-commands" -ForegroundColor Cyan
Write-Host "=======================================================" -ForegroundColor Cyan

# 1. Check if LocalStack pod is running
$localstackPod = kubectl get pod -n localstack -l app=localstack -o jsonpath="{.items[0].metadata.name}" 2>$null
if (-not $localstackPod) {
    Write-Host "[ERROR] LocalStack pod not found. Please deploy: kubectl apply -f k8s/localstack/localstack.yaml" -ForegroundColor Red
    return
}

# 2. Query recent log events from CloudWatch in LocalStack
Write-Host "`n--- RECENT TERMINAL COMMAND AUDIT EVENTS ---" -ForegroundColor Cyan

$fetchCmd = "awslocal logs filter-log-events --log-group-name /aws/eks/audit/terminal-commands --query 'events[*].message' --output json 2>/dev/null"
$jsonOutput = kubectl exec -n localstack $localstackPod -- sh -c $fetchCmd

if (-not $jsonOutput -or $jsonOutput.Trim() -eq "[]" -or $jsonOutput.Trim() -eq "") {
    Write-Host "No log events found yet." -ForegroundColor DarkYellow
    Write-Host "Tip: Run commands in your application terminal, then run this script again!" -ForegroundColor Gray
    Write-Host "  e.g.: kubectl exec -it -n nodejs-app deploy/nodejs-hello-world -- sh -c 'whoami; ls -la'" -ForegroundColor Gray
    Write-Host "`n=======================================================" -ForegroundColor Cyan
    return
}

try {
    $events = $jsonOutput | ConvertFrom-Json
    $seen = [System.Collections.Generic.HashSet[string]]::new()

    foreach ($msg in $events) {
        if ([string]::IsNullOrWhiteSpace($msg)) { continue }

        $cleanLine = ""
        try {
            $parsed = $msg | ConvertFrom-Json
            if ($parsed.log -match '\[Session:') {
                $cleanLine = $parsed.log.Trim()
            } elseif ($parsed.process_exec) {
                $proc = $parsed.process_exec.process
                $podName = $proc.pod.name
                $binary = $proc.binary
                $args = $proc.arguments
                $sessionId = $proc.parent_exec_id
                $cleanLine = "[Session: $sessionId] $podName -> $binary $args"
            }
        } catch {
            if ($msg -match '\[Session:') {
                $cleanLine = $msg.Trim()
            }
        }

        if ($cleanLine -and $seen.Add($cleanLine)) {
            Write-Host $cleanLine -ForegroundColor Green
        }
    }
} catch {
    Write-Host $jsonOutput -ForegroundColor Gray
}

Write-Host "=======================================================" -ForegroundColor Cyan

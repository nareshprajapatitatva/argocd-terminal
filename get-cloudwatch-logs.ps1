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

# 2. Query log streams from CloudWatch in LocalStack
Write-Host "`nChecking for log streams in /aws/eks/audit/terminal-commands..." -ForegroundColor Yellow

$cmd = "awslocal logs describe-log-streams --log-group-name /aws/eks/audit/terminal-commands --query 'logStreams[*].logStreamName' --output text 2>/dev/null"
$streams = kubectl exec -n localstack $localstackPod -- sh -c $cmd

if (-not $streams -or $streams.Trim() -eq "") {
    Write-Host "No log streams found yet." -ForegroundColor DarkYellow
    Write-Host "Tip: Run commands in your application terminal, then run this script again!" -ForegroundColor Gray
    Write-Host "  e.g.: kubectl exec -it -n nodejs-app deploy/nodejs-hello-world -- sh -c 'whoami; ls -la'" -ForegroundColor Gray
    return
}

Write-Host "[OK] Found log stream(s): $streams" -ForegroundColor Green

# 3. Fetch and format events
Write-Host "`n--- RECENT TERMINAL COMMAND AUDIT EVENTS ---" -ForegroundColor Cyan
$streamList = $streams -split "\s+"
foreach ($stream in $streamList) {
    if ([string]::IsNullOrWhiteSpace($stream)) { continue }
    
    $fetchCmd = "awslocal logs get-log-events --log-group-name /aws/eks/audit/terminal-commands --log-stream-name $stream --query 'events[*].message' --output text 2>/dev/null"
    $events = kubectl exec -n localstack $localstackPod -- sh -c $fetchCmd
    
    if ($events) {
        $events -split "`n" | ForEach-Object {
            $line = $_
            if ($line -like "*process_exec*") {
                try {
                    $json = $line | ConvertFrom-Json
                    $proc = $json.process_exec.process
                    $podName = $proc.pod.name
                    $binary = $proc.binary
                    $args = $proc.arguments
                    $sessionId = $proc.parent_exec_id
                    $uid = $proc.uid
                    Write-Host "[Session: $sessionId] Pod: $podName (UID: $uid) -> $binary $args" -ForegroundColor Green
                } catch {
                    Write-Host $line -ForegroundColor Gray
                }
            }
        }
    }
}
Write-Host "`n=======================================================" -ForegroundColor Cyan

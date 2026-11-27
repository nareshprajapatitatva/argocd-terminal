# ==============================================================================
# Automated Setup Script: Node.js Hello World on Kubernetes with ArgoCD and Tetragon Audit
# OS: Windows (PowerShell)
# Usage:
#   .\install.ps1              # Run full installation
#   .\install.ps1 -PortForward # Run installation and immediately start all port forwards
#   .\install.ps1 -OpenBrowser # Run installation, start port forwards, and open browser
# ==============================================================================

param (
    [switch]$PortForward,
    [switch]$OpenBrowser
)

$ErrorActionPreference = "Stop"

Write-Host ""
Write-Host "=======================================================" -ForegroundColor Cyan
Write-Host " [*] Starting Full Environment Installation and Setup" -ForegroundColor Cyan
Write-Host "=======================================================" -ForegroundColor Cyan
Write-Host ""

# 1. Check Prerequisites
Write-Host "[1/9] Checking prerequisites..." -ForegroundColor Yellow
if (-not (Get-Command kubectl -ErrorAction SilentlyContinue)) {
    Write-Error "kubectl is not installed or not in PATH. Please install kubectl first."
}
if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
    Write-Error "docker is not installed or not in PATH. Please start Docker first."
}
Write-Host "  [OK] kubectl and docker found." -ForegroundColor Green

# 2. Build local Docker image
Write-Host "`n[2/9] Building local Docker image (nodejs-hello-world:v1.0.0)..." -ForegroundColor Yellow
if (Get-Command minikube -ErrorAction SilentlyContinue) {
    $minikubeStatus = minikube status --format "{{.Host}}" 2>$null
    if ($minikubeStatus -eq "Running") {
        Write-Host "  -> Minikube detected! Configuring Minikube Docker environment..." -ForegroundColor Gray
        & minikube -p minikube docker-env --shell powershell | Invoke-Expression
    }
}
docker build -t nodejs-hello-world:v1.0.0 ./app
Write-Host "  [OK] Docker image built successfully." -ForegroundColor Green

# 3. Install ArgoCD
Write-Host "`n[3/9] Setting up ArgoCD..." -ForegroundColor Yellow
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -n argocd --server-side -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
Write-Host "  -> Waiting for ArgoCD server to be ready..." -ForegroundColor Gray
kubectl rollout status deployment/argocd-server -n argocd --timeout=300s
Write-Host "  [OK] ArgoCD installed and running." -ForegroundColor Green

# 4. Enable ArgoCD Web Terminal and RBAC
Write-Host "`n[4/9] Configuring ArgoCD Web Terminal and Exec RBAC..." -ForegroundColor Yellow
kubectl apply -f argocd/terminal-config.yaml
kubectl rollout restart deployment argocd-server -n argocd
kubectl rollout status deployment argocd-server -n argocd --timeout=120s
Write-Host "  [OK] ArgoCD Web Terminal enabled." -ForegroundColor Green

# 5. Install Tetragon CRDs and Helm Chart
Write-Host "`n[5/9] Installing Tetragon eBPF Kernel Audit Engine..." -ForegroundColor Yellow
kubectl apply -f https://raw.githubusercontent.com/cilium/tetragon/v1.2.0/pkg/k8s/apis/cilium.io/client/crds/v1alpha1/cilium.io_tracingpolicies.yaml
kubectl apply -f https://raw.githubusercontent.com/cilium/tetragon/v1.2.0/pkg/k8s/apis/cilium.io/client/crds/v1alpha1/cilium.io_tracingpoliciesnamespaced.yaml

if (Get-Command helm -ErrorAction SilentlyContinue) {
    helm repo add cilium https://helm.cilium.io 2>$null
    helm repo update cilium
    helm upgrade --install tetragon cilium/tetragon -n kube-system -f k8s/audit/tetragon-values.yaml
    kubectl rollout status ds/tetragon -n kube-system --timeout=180s
    Write-Host "  [OK] Tetragon installed via Helm." -ForegroundColor Green
} else {
    Write-Host "  [!] Helm not found. Please install Tetragon manually or install Helm." -ForegroundColor DarkYellow
}

# 6. Apply Tetragon TracingPolicy
Write-Host "`n[6/9] Applying Tetragon Tracing Policy (kprobes: sys_execve, sys_chdir)..." -ForegroundColor Yellow
kubectl apply -f k8s/audit/tetragon-terminal-audit-policy.yaml
Write-Host "  [OK] TracingPolicy applied." -ForegroundColor Green

# 7. Deploy Node.js Application Manifests
Write-Host "`n[7/9] Deploying Node.js Hello World application..." -ForegroundColor Yellow
kubectl apply -k k8s/
kubectl rollout status deployment/nodejs-hello-world -n nodejs-app --timeout=180s
Write-Host "  [OK] Application deployed successfully." -ForegroundColor Green

# 8. Deploy LocalStack (Mock AWS CloudWatch) and AWS Fluent Bit
Write-Host "`n[8/9] Deploying LocalStack and AWS Fluent Bit (CloudWatch Log Shipper)..." -ForegroundColor Yellow
kubectl apply -f k8s/localstack/localstack.yaml
kubectl rollout status deployment/localstack -n localstack --timeout=180s
kubectl apply -f k8s/audit/aws-fluent-bit.yaml
kubectl rollout status ds/aws-fluent-bit -n kube-system --timeout=120s
Write-Host "  [OK] LocalStack and AWS Fluent Bit running." -ForegroundColor Green

# 9. Register GitOps Application in ArgoCD
Write-Host "`n[9/9] Registering GitOps Application in ArgoCD..." -ForegroundColor Yellow
kubectl apply -f argocd/application.yaml
Write-Host "  [OK] ArgoCD Application registered (nodejs-hello-world)." -ForegroundColor Green

# Get ArgoCD Admin Password
$argocdPassword = ""
try {
    $secretBytes = kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" 2>$null
    if ($secretBytes) {
        $argocdPassword = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($secretBytes))
    }
} catch {
    $argocdPassword = "(already changed or secret not found)"
}

Write-Host ""
Write-Host "=======================================================" -ForegroundColor Green
Write-Host " [SUCCESS] INSTALLATION COMPLETED SUCCESSFULLY!" -ForegroundColor Green
Write-Host "=======================================================" -ForegroundColor Green
Write-Host ""
Write-Host "--- AUTOMATED PORT FORWARDING ---" -ForegroundColor Cyan
Write-Host "To start all port forwards automatically in parallel, run:" -ForegroundColor White
Write-Host "   .\port-forward.ps1" -ForegroundColor Yellow
Write-Host "   .\port-forward.ps1 -OpenBrowser    (starts port forwards and opens browser tabs)" -ForegroundColor Gray
Write-Host "   .\port-forward.ps1 -Stop           (stops all active port forwards)" -ForegroundColor Gray
Write-Host ""
Write-Host "--- ACCESS URLS & CREDENTIALS ---" -ForegroundColor Cyan
Write-Host "1. ArgoCD Web UI:         https://127.0.0.1:8080 (or https://localhost:8080)" -ForegroundColor White
Write-Host "   Credentials:           admin / $argocdPassword" -ForegroundColor Yellow
Write-Host "2. Grafana Dashboard:     http://localhost:3000" -ForegroundColor White
Write-Host "   Credentials:           admin / admin (or auto-login)" -ForegroundColor Yellow
Write-Host "3. Prometheus Metrics:    http://localhost:9090" -ForegroundColor White
Write-Host "4. Node.js Hello API:     http://localhost:8000" -ForegroundColor White
Write-Host ""
Write-Host "5. Live Terminal Audit Logs (CLI View):" -ForegroundColor White
Write-Host "   Command:               kubectl exec -it -n kube-system ds/tetragon -c tetragon -- tetra getevents -o compact --namespaces nodejs-app" -ForegroundColor Yellow
Write-Host "=======================================================`n" -ForegroundColor Cyan

if ($PortForward -or $OpenBrowser) {
    if ($OpenBrowser) {
        & "$PSScriptRoot\port-forward.ps1" -OpenBrowser
    } else {
        & "$PSScriptRoot\port-forward.ps1"
    }
}

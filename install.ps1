# ==============================================================================
# Automated Setup Script: Node.js Hello World on Kubernetes with ArgoCD & Tetragon Audit
# OS: Windows (PowerShell)
# ==============================================================================

$ErrorActionPreference = "Stop"

Write-Host "`n=======================================================" -ForegroundColor Cyan
Write-Host " 🚀 Starting Full Environment Installation & Setup" -ForegroundColor Cyan
Write-Host "=======================================================`n" -ForegroundColor Cyan

# 1. Check Prerequisites
Write-Host "[1/9] Checking prerequisites..." -ForegroundColor Yellow
if (-not (Get-Command kubectl -ErrorAction SilentlyContinue)) {
    Write-Error "kubectl is not installed or not in PATH. Please install kubectl first."
}
if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
    Write-Error "docker is not installed or not in PATH. Please start Docker first."
}
Write-Host "  ✔ kubectl and docker found." -ForegroundColor Green

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
Write-Host "  ✔ Docker image built successfully." -ForegroundColor Green

# 3. Install ArgoCD
Write-Host "`n[3/9] Setting up ArgoCD..." -ForegroundColor Yellow
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
Write-Host "  -> Waiting for ArgoCD server to be ready..." -ForegroundColor Gray
kubectl rollout status deployment/argocd-server -n argocd --timeout=300s
Write-Host "  ✔ ArgoCD installed and running." -ForegroundColor Green

# 4. Enable ArgoCD Web Terminal & RBAC
Write-Host "`n[4/9] Configuring ArgoCD Web Terminal & Exec RBAC..." -ForegroundColor Yellow
kubectl apply -f argocd/terminal-config.yaml
kubectl rollout restart deployment argocd-server -n argocd
kubectl rollout status deployment argocd-server -n argocd --timeout=120s
Write-Host "  ✔ ArgoCD Web Terminal enabled." -ForegroundColor Green

# 5. Install Tetragon CRDs and Helm Chart
Write-Host "`n[5/9] Installing Tetragon eBPF Kernel Audit Engine..." -ForegroundColor Yellow
kubectl apply -f https://raw.githubusercontent.com/cilium/tetragon/v1.2.0/pkg/k8s/apis/cilium.io/client/crds/v1alpha1/cilium.io_tracingpolicies.yaml
kubectl apply -f https://raw.githubusercontent.com/cilium/tetragon/v1.2.0/pkg/k8s/apis/cilium.io/client/crds/v1alpha1/cilium.io_tracingpoliciesnamespaced.yaml

if (Get-Command helm -ErrorAction SilentlyContinue) {
    helm repo add cilium https://helm.cilium.io 2>$null
    helm repo update cilium
    helm upgrade --install tetragon cilium/tetragon -n kube-system -f k8s/audit/tetragon-values.yaml
    kubectl rollout status ds/tetragon -n kube-system --timeout=180s
    Write-Host "  ✔ Tetragon installed via Helm." -ForegroundColor Green
} else {
    Write-Host "  ⚠ Helm not found. Please install Tetragon manually or install Helm." -ForegroundColor DarkYellow
}

# 6. Apply Tetragon TracingPolicy
Write-Host "`n[6/9] Applying Tetragon Tracing Policy (kprobes: sys_execve, sys_chdir)..." -ForegroundColor Yellow
kubectl apply -f k8s/audit/tetragon-terminal-audit-policy.yaml
Write-Host "  ✔ TracingPolicy applied." -ForegroundColor Green

# 7. Deploy Node.js Application Manifests
Write-Host "`n[7/9] Deploying Node.js Hello World application..." -ForegroundColor Yellow
kubectl apply -k k8s/
kubectl rollout status deployment/nodejs-hello-world -n nodejs-app --timeout=180s
Write-Host "  ✔ Application deployed successfully." -ForegroundColor Green

# 8. Deploy Prometheus + Loki + Grafana Observability Stack
Write-Host "`n[8/9] Deploying Prometheus, Loki, and Grafana (Monitoring & Audit Dashboard)..." -ForegroundColor Yellow
kubectl apply -k k8s/monitoring/
kubectl rollout status deployment/prometheus -n monitoring --timeout=180s
kubectl rollout status deployment/grafana -n monitoring --timeout=180s
Write-Host "  ✔ Prometheus & Grafana stack running." -ForegroundColor Green

# 9. Register GitOps Applications in ArgoCD
Write-Host "`n[9/9] Registering GitOps Applications in ArgoCD..." -ForegroundColor Yellow
kubectl apply -f argocd/application.yaml
kubectl apply -f argocd/monitoring-application.yaml
Write-Host "  ✔ ArgoCD Applications registered (nodejs-hello-world & cluster-monitoring)." -ForegroundColor Green

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

Write-Host "`n=======================================================" -ForegroundColor Green
Write-Host " 🎉 INSTALLATION COMPLETED SUCCESSFULLY!" -ForegroundColor Green
Write-Host "=======================================================" -ForegroundColor Green
Write-Host "`n📋 ACCESS INFORMATION:" -ForegroundColor Cyan
Write-Host "1. ArgoCD Web UI:" -ForegroundColor White
Write-Host "   Port-Forward:  kubectl port-forward --address 127.0.0.1 svc/argocd-server -n argocd 8080:443" -ForegroundColor Gray
Write-Host "   URL:           https://127.0.0.1:8080 (or https://localhost:8080)" -ForegroundColor Gray
Write-Host "   Username:      admin" -ForegroundColor Gray
Write-Host "   Password:      $argocdPassword" -ForegroundColor Yellow

Write-Host "`n2. Grafana Audit & Monitoring Dashboard:" -ForegroundColor White
Write-Host "   Port-Forward:  kubectl port-forward svc/grafana-service -n monitoring 3000:3000" -ForegroundColor Gray
Write-Host "   URL:           http://localhost:3000 (auto-logs in with pre-built Audit Dashboard)" -ForegroundColor Yellow
Write-Host "   Credentials:   admin / admin" -ForegroundColor Gray

Write-Host "`n3. Prometheus Metrics UI:" -ForegroundColor White
Write-Host "   Port-Forward:  kubectl port-forward svc/prometheus-service -n monitoring 9090:9090" -ForegroundColor Gray
Write-Host "   URL:           http://localhost:9090" -ForegroundColor Gray

Write-Host "`n4. Node.js Hello World API:" -ForegroundColor White
Write-Host "   Port-Forward:  kubectl port-forward svc/nodejs-hello-world-svc -n nodejs-app 8000:80" -ForegroundColor Gray
Write-Host "   Test URL:      curl http://localhost:8000/" -ForegroundColor Gray

Write-Host "`n5. Live Terminal Audit Logs (CLI View):" -ForegroundColor White
Write-Host "   Command:       kubectl exec -it -n kube-system ds/tetragon -c tetragon -- tetra getevents -o compact --namespaces nodejs-app" -ForegroundColor Yellow
Write-Host "=======================================================`n" -ForegroundColor Cyan

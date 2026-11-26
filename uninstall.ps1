# ==============================================================================
# Clean Teardown Script for ArgoCD Terminal Audit POC
# Stops port-forwards, removes workloads, helm releases, and cleans namespaces
# ==============================================================================

Write-Host "=================================================================" -ForegroundColor Cyan
Write-Host " [TEARDOWN] Cleaning up ArgoCD Terminal & Audit Stack" -ForegroundColor Cyan
Write-Host "=================================================================" -ForegroundColor Cyan

# 1. Stop background port-forward processes
Write-Host "`n[1/6] Stopping any active port-forward processes..." -ForegroundColor Yellow
if (Test-Path "port-forward.ps1") {
    .\port-forward.ps1 -Stop
} else {
    Get-Process -Name "kubectl" -ErrorAction SilentlyContinue | Where-Object { $_.CommandLine -like "*port-forward*" } | Stop-Process -Force -ErrorAction SilentlyContinue
}
Write-Host "  [OK] Port-forwards stopped." -ForegroundColor Green

# 2. Delete ArgoCD Applications first (with finalizer protection)
Write-Host "`n[2/6] Deleting ArgoCD Applications..." -ForegroundColor Yellow
kubectl delete application cluster-monitoring -n argocd --timeout=60s --ignore-not-found=true
kubectl delete application nodejs-hello-world -n argocd --timeout=60s --ignore-not-found=true
Write-Host "  [OK] ArgoCD Applications removed." -ForegroundColor Green

# 3. Delete Application and Monitoring Namespaces (cascades all pods, services, configs)
Write-Host "`n[3/6] Deleting nodejs-app and monitoring namespaces..." -ForegroundColor Yellow
kubectl delete namespace nodejs-app --timeout=120s --ignore-not-found=true
kubectl delete namespace monitoring --timeout=120s --ignore-not-found=true
Write-Host "  [OK] Namespaces deleted." -ForegroundColor Green

# 4. Uninstall Tetragon and remove TracingPolicies
Write-Host "`n[4/6] Uninstalling Tetragon eBPF Engine..." -ForegroundColor Yellow
kubectl delete tracingpolicy --all --timeout=60s --ignore-not-found=true
kubectl delete tracingpolicynamespaced --all -A --timeout=60s --ignore-not-found=true
if (Get-Command helm -ErrorAction SilentlyContinue) {
    helm uninstall tetragon -n kube-system 2>$null
}
kubectl delete ds tetragon -n kube-system --ignore-not-found=true
kubectl delete deployment tetragon-operator -n kube-system --ignore-not-found=true
Write-Host "  [OK] Tetragon uninstalled." -ForegroundColor Green

# 5. Remove ArgoCD
Write-Host "`n[5/6] Deleting ArgoCD namespace..." -ForegroundColor Yellow
kubectl delete namespace argocd --timeout=120s --ignore-not-found=true
Write-Host "  [OK] ArgoCD removed." -ForegroundColor Green

# 6. Delete Tetragon CRDs and ClusterRoles/ClusterRoleBindings
Write-Host "`n[6/6] Cleaning up CRDs and Cluster Roles..." -ForegroundColor Yellow
kubectl delete crd tracingpolicies.cilium.io tracingpoliciesnamespaced.cilium.io --ignore-not-found=true
kubectl delete clusterrole promtail-cr prometheus-cr --ignore-not-found=true
kubectl delete clusterrolebinding promtail-crb prometheus-crb --ignore-not-found=true
Write-Host "  [OK] Cluster-scoped roles and CRDs removed." -ForegroundColor Green

Write-Host "`n=================================================================" -ForegroundColor Green
Write-Host " [SUCCESS] Cluster is completely clean and ready for fresh install!" -ForegroundColor Green
Write-Host " Run .\install.ps1 to redeploy from scratch." -ForegroundColor Green
Write-Host "=================================================================" -ForegroundColor Green

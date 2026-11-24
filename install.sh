#!/usr/bin/env bash
# ==============================================================================
# Automated Setup Script: Node.js Hello World on Kubernetes with ArgoCD & Tetragon Audit
# OS: Linux / macOS / WSL (Bash)
# ==============================================================================

set -euo pipefail

echo ""
echo "======================================================="
echo " 🚀 Starting Full Environment Installation & Setup"
echo "======================================================="
echo ""

# 1. Check Prerequisites
echo "[1/9] Checking prerequisites..."
command -v kubectl >/dev/null 2>&1 || { echo "kubectl is not installed. Aborting." >&2; exit 1; }
command -v docker >/dev/null 2>&1 || { echo "docker is not installed. Aborting." >&2; exit 1; }
echo "  ✔ kubectl and docker found."

# 2. Build local Docker image
echo ""
echo "[2/9] Building local Docker image (nodejs-hello-world:v1.0.0)..."
if command -v minikube >/dev/null 2>&1; then
    if [ "$(minikube status --format '{{.Host}}' 2>/dev/null || true)" = "Running" ]; then
        echo "  -> Minikube detected! Configuring Minikube Docker environment..."
        eval "$(minikube -p minikube docker-env)"
    fi
fi
docker build -t nodejs-hello-world:v1.0.0 ./app
echo "  ✔ Docker image built successfully."

# 3. Install ArgoCD
echo ""
echo "[3/9] Setting up ArgoCD..."
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
echo "  -> Waiting for ArgoCD server to be ready..."
kubectl rollout status deployment/argocd-server -n argocd --timeout=300s
echo "  ✔ ArgoCD installed and running."

# 4. Enable ArgoCD Web Terminal & RBAC
echo ""
echo "[4/9] Configuring ArgoCD Web Terminal & Exec RBAC..."
kubectl apply -f argocd/terminal-config.yaml
kubectl rollout restart deployment argocd-server -n argocd
kubectl rollout status deployment argocd-server -n argocd --timeout=120s
echo "  ✔ ArgoCD Web Terminal enabled."

# 5. Install Tetragon CRDs and Helm Chart
echo ""
echo "[5/9] Installing Tetragon eBPF Kernel Audit Engine..."
kubectl apply -f https://raw.githubusercontent.com/cilium/tetragon/v1.2.0/pkg/k8s/apis/cilium.io/client/crds/v1alpha1/cilium.io_tracingpolicies.yaml
kubectl apply -f https://raw.githubusercontent.com/cilium/tetragon/v1.2.0/pkg/k8s/apis/cilium.io/client/crds/v1alpha1/cilium.io_tracingpoliciesnamespaced.yaml

if command -v helm >/dev/null 2>&1; then
    helm repo add cilium https://helm.cilium.io >/dev/null 2>&1 || true
    helm repo update cilium
    helm upgrade --install tetragon cilium/tetragon -n kube-system -f k8s/audit/tetragon-values.yaml
    kubectl rollout status ds/tetragon -n kube-system --timeout=180s
    echo "  ✔ Tetragon installed via Helm."
else
    echo "  ⚠ Helm not found. Please install Tetragon manually or install Helm."
fi

# 6. Apply Tetragon TracingPolicy
echo ""
echo "[6/9] Applying Tetragon Tracing Policy (kprobes: sys_execve, sys_chdir)..."
kubectl apply -f k8s/audit/tetragon-terminal-audit-policy.yaml
echo "  ✔ TracingPolicy applied."

# 7. Deploy Node.js Application
echo ""
echo "[7/9] Deploying Node.js Hello World application..."
kubectl apply -k k8s/
kubectl rollout status deployment/nodejs-hello-world -n nodejs-app --timeout=180s
echo "  ✔ Application deployed successfully."

# 8. Deploy Prometheus + Loki + Grafana Observability Stack
echo ""
echo "[8/9] Deploying Prometheus, Loki, and Grafana (Monitoring & Audit Dashboard)..."
kubectl apply -k k8s/monitoring/
kubectl rollout status deployment/prometheus -n monitoring --timeout=180s
kubectl rollout status deployment/grafana -n monitoring --timeout=180s
echo "  ✔ Prometheus & Grafana stack running."

# 9. Register GitOps Applications in ArgoCD
echo ""
echo "[9/9] Registering GitOps Applications in ArgoCD..."
kubectl apply -f argocd/application.yaml
kubectl apply -f argocd/monitoring-application.yaml
echo "  ✔ ArgoCD Applications registered (nodejs-hello-world & cluster-monitoring)."

# Retrieve password
ARGOCD_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" 2>/dev/null | base64 -d || echo "(already changed)")

echo ""
echo "======================================================="
echo " 🎉 INSTALLATION COMPLETED SUCCESSFULLY!"
echo "======================================================="
echo ""
echo "📋 ACCESS INFORMATION:"
echo "1. ArgoCD Web UI:"
echo "   Port-Forward:  kubectl port-forward --address 127.0.0.1 svc/argocd-server -n argocd 8080:443"
echo "   URL:           https://127.0.0.1:8080 (or https://localhost:8080)"
echo "   Username:      admin"
echo "   Password:      $ARGOCD_PASSWORD"
echo ""
echo "2. Grafana Audit & Monitoring Dashboard:"
echo "   Port-Forward:  kubectl port-forward svc/grafana-service -n monitoring 3000:3000"
echo "   URL:           http://localhost:3000 (auto-logs in with pre-built Audit Dashboard)"
echo "   Credentials:   admin / admin"
echo ""
echo "3. Prometheus Metrics UI:"
echo "   Port-Forward:  kubectl port-forward svc/prometheus-service -n monitoring 9090:9090"
echo "   URL:           http://localhost:9090"
echo ""
echo "4. Node.js Hello World API:"
echo "   Port-Forward:  kubectl port-forward svc/nodejs-hello-world-svc -n nodejs-app 8000:80"
echo "   Test URL:      curl http://localhost:8000/"
echo ""
echo "5. Live Terminal Audit Logs (CLI View):"
echo "   Command:       kubectl exec -it -n kube-system ds/tetragon -c tetragon -- tetra getevents -o compact --namespaces nodejs-app"
echo "======================================================="
echo ""

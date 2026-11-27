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
kubectl apply -n argocd --server-side -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
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

# 8. Deploy LocalStack and AWS Fluent Bit
echo ""
echo "[8/9] Deploying LocalStack and AWS Fluent Bit (CloudWatch Log Shipper)..."
kubectl apply -f k8s/localstack/localstack.yaml
kubectl rollout status deployment/localstack -n localstack --timeout=180s
kubectl apply -f k8s/audit/aws-fluent-bit.yaml
kubectl rollout status ds/aws-fluent-bit -n kube-system --timeout=120s
echo "  ✔ LocalStack and AWS Fluent Bit running."

# 9. Register GitOps Application in ArgoCD
echo ""
echo "[9/9] Registering GitOps Application in ArgoCD..."
kubectl apply -f argocd/application.yaml
echo "  ✔ ArgoCD Application registered (nodejs-hello-world)."

# Retrieve password
ARGOCD_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" 2>/dev/null | base64 -d || echo "(already changed)")

echo ""
echo "======================================================="
echo " 🎉 INSTALLATION COMPLETED SUCCESSFULLY!"
echo "======================================================="
echo ""
echo "--- AUTOMATED PORT FORWARDING ---"
echo "To start all port forwards automatically in parallel, run:"
echo "   ./port-forward.sh"
echo "   ./port-forward.sh --stop    (stops all active port forwards)"
echo ""
echo "--- ACCESS URLS & CREDENTIALS ---"
echo "1. ArgoCD Web UI:         https://127.0.0.1:8080 (or https://localhost:8080)"
echo "   Credentials:           admin / $ARGOCD_PASSWORD"
echo "2. Node.js Hello API:     http://localhost:8000"
echo "3. LocalStack AWS:        http://localhost:4566"
echo ""
echo "--- AUDIT LOGGING & VERIFICATION ---"
echo "1. CloudWatch Logs (LocalStack):"
echo "   View Command:          ./get-cloudwatch-logs.ps1 (or aws --endpoint-url=http://localhost:4566 logs ...)"
echo "2. Live eBPF Kernel Events (Direct CLI Stream):"
echo "   View Command:          kubectl exec -it -n kube-system ds/tetragon -c tetragon -- tetra getevents -o compact --namespaces nodejs-app"
echo "======================================================="
echo ""

if [ "${1:-}" = "--port-forward" ]; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    "$SCRIPT_DIR/port-forward.sh"
fi

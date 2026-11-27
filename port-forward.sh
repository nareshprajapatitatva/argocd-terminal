#!/usr/bin/env bash
# ==============================================================================
# Automated Port Forwarding for ArgoCD, Grafana, Prometheus, and Node.js API
# OS: Linux / macOS / WSL (Bash)
# Usage:
#   ./port-forward.sh        # Starts all port forwards and monitors them
#   ./port-forward.sh --stop # Stops all running port forward processes
# ==============================================================================

set -euo pipefail

PIDS=()

cleanup() {
    echo ""
    echo "Stopping all port forwards..."
    for pid in "${PIDS[@]}"; do
        if kill -0 "$pid" 2>/dev/null; then
            kill "$pid" 2>/dev/null || true
        fi
    done
    echo "[OK] All port forwards stopped cleanly."
    exit 0
}

trap cleanup SIGINT SIGTERM EXIT

# Check for --stop argument
if [ "${1:-}" = "--stop" ]; then
    echo "Stopping existing kubectl port-forward processes..."
    pkill -f "kubectl.*port-forward" || true
    echo "[OK] All port-forward processes stopped."
    exit 0
fi

# Clean up any lingering port forwards
pkill -f "kubectl.*port-forward" 2>/dev/null || true

echo ""
echo "======================================================="
echo " [*] Starting All Kubernetes Port Forwards in Parallel"
echo "======================================================="

# Fetch ArgoCD password
ARGOCD_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" 2>/dev/null | base64 -d || echo "(already changed)")

# 1. ArgoCD Web UI
echo "  -> Starting ArgoCD Web UI on port 8080..."
kubectl port-forward --address 127.0.0.1 svc/argocd-server -n argocd 8080:443 >/dev/null 2>&1 &
PIDS+=($!)

# 2. Node.js Hello API
echo "  -> Starting Node.js Hello API on port 8000..."
kubectl port-forward svc/nodejs-hello-world-svc -n nodejs-app 8000:80 >/dev/null 2>&1 &
PIDS+=($!)

# 3. LocalStack AWS
echo "  -> Starting LocalStack AWS on port 4566..."
kubectl port-forward svc/localstack -n localstack 4566:4566 >/dev/null 2>&1 &
PIDS+=($!)

sleep 1

echo ""
echo "======================================================="
echo " [SUCCESS] ALL PORT FORWARDS ARE NOW ACTIVE!"
echo "======================================================="
echo ""
echo "1. ArgoCD Web UI:         https://127.0.0.1:8080"
echo "   Credentials:           admin / $ARGOCD_PASSWORD"
echo "2. Node.js Hello API:     http://localhost:8000"
echo "3. LocalStack AWS:        http://localhost:4566"
echo ""
echo "--- AUDIT LOGGING & VERIFICATION ---"
echo "View CloudWatch Logs:     ./get-cloudwatch-logs.ps1"
echo "View Live eBPF Stream:    kubectl exec -it -n kube-system ds/tetragon -c tetragon -- tetra getevents -o compact --namespaces nodejs-app"
echo "======================================================="
echo ""
echo "Press Ctrl+C to stop all port forwards."
echo "======================================================="
echo ""

# Keep running
while true; do
    sleep 2
done

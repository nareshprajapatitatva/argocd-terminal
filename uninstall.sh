#!/bin/bash
set -e

echo "================================================================="
echo " [TEARDOWN] Cleaning up ArgoCD Terminal & Audit Stack"
echo "================================================================="

# 1. Stop background port-forward processes
echo -e "\n[1/6] Stopping any active port-forward processes..."
pkill -f "kubectl port-forward" || true
echo "  [OK] Port-forwards stopped."

# 2. Delete ArgoCD Applications
echo -e "\n[2/6] Deleting ArgoCD Applications..."
kubectl delete application cluster-monitoring -n argocd --timeout=60s --ignore-not-found=true
kubectl delete application nodejs-hello-world -n argocd --timeout=60s --ignore-not-found=true
echo "  [OK] ArgoCD Applications removed."

# 3. Delete Namespaces
echo -e "\n[3/6] Deleting nodejs-app and monitoring namespaces..."
kubectl delete namespace nodejs-app --timeout=120s --ignore-not-found=true
kubectl delete namespace monitoring --timeout=120s --ignore-not-found=true
echo "  [OK] Namespaces deleted."

# 4. Uninstall Tetragon
echo -e "\n[4/6] Uninstalling Tetragon eBPF Engine..."
kubectl delete tracingpolicy --all --timeout=60s --ignore-not-found=true
kubectl delete tracingpolicynamespaced --all -A --timeout=60s --ignore-not-found=true
if command -v helm &> /dev/null; then
    helm uninstall tetragon -n kube-system 2>/dev/null || true
fi
kubectl delete ds tetragon -n kube-system --ignore-not-found=true
kubectl delete deployment tetragon-operator -n kube-system --ignore-not-found=true
echo "  [OK] Tetragon uninstalled."

# 5. Remove ArgoCD
echo -e "\n[5/6] Deleting ArgoCD namespace..."
kubectl delete namespace argocd --timeout=120s --ignore-not-found=true
echo "  [OK] ArgoCD removed."

# 6. Delete CRDs and ClusterRoles
echo -e "\n[6/6] Cleaning up CRDs and Cluster Roles..."
kubectl delete crd tracingpolicies.cilium.io tracingpoliciesnamespaced.cilium.io --ignore-not-found=true
kubectl delete clusterrole promtail-cr prometheus-cr --ignore-not-found=true
kubectl delete clusterrolebinding promtail-crb prometheus-crb --ignore-not-found=true
echo "  [OK] Cluster-scoped roles and CRDs removed."

echo -e "\n================================================================="
echo " [SUCCESS] Cluster is completely clean and ready for fresh install!"
echo " Run ./install.sh to redeploy from scratch."
echo "================================================================="

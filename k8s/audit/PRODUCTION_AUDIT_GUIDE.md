# Production-Grade Terminal Auditing Architecture

This guide details the enterprise-grade audit architecture for tracking **WHO opened the terminal** and **WHAT exact commands were executed** inside containers via ArgoCD.

---

## 🏛️ Architecture Overview

```text
  [ User (SSO/OIDC) ]
          │ (1. Opens Web Terminal)
          ▼
   [ argocd-server ] ──────► Emits structured audit log:
          │                  { "user": "alice@company.com", "pod": "nodejs-app-xxx", "action": "terminal" }
          │
          ▼ (2. k8s pods/exec)
   [ Linux Kernel / Container Runtime ]
          │
    (eBPF Hook) ────────────► Cilium Tetragon catches sys_enter_execve:
                             { "pod": "nodejs-app-xxx", "binary": "/bin/cat", "arguments": ["/etc/passwd"] }
          │
          ▼
   [ Central SIEM (Elastic / Splunk / Loki) ]
          └── Correlates: User "alice@company.com" executed "cat /etc/passwd" at 15:32:05
```

---

## Component Breakdown

### 1. Identity & Session Initiation ("WHO")
- **Authentication**: ArgoCD configured with OIDC / SAML (Okta, Azure AD, Google Workspace, Keycloak).
- **Log Source**: `argocd-server` logs.
- **Log Sample**:
  ```json
  {
    "time": "2026-11-24T15:32:01Z",
    "level": "info",
    "msg": "Terminal session initiated",
    "sub": "alice@company.com",
    "groups": ["devops", "platform-engineers"],
    "application": "nodejs-hello-world",
    "namespace": "nodejs-app",
    "podName": "nodejs-hello-world-74697ff789-9r84b",
    "containerName": "nodejs-hello-world",
    "clientIP": "10.0.4.15"
  }
  ```

### 2. Kernel-Level Process Auditing ("WHAT")
- **Technology**: **Cilium Tetragon** (eBPF).
- **Why eBPF**:
  - Operates directly inside the Linux kernel.
  - Zero performance overhead.
  - **100% Tamper-proof**: Cannot be bypassed, spoofed, or deleted by any container user or root process.
- **Log Sample**:
  ```json
  {
    "time": "2026-11-24T15:32:05.123Z",
    "process_exec": {
      "process": {
        "exec_id": "YW1kNjQ6MjkxODQ...",
        "pid": 29184,
        "binary": "/bin/cat",
        "arguments": "/bin/cat /etc/passwd",
        "pod": {
          "namespace": "nodejs-app",
          "name": "nodejs-hello-world-74697ff789-9r84b",
          "container": { "id": "containerd://...", "name": "nodejs-hello-world" }
        }
      }
    }
  }
  ```

---

## 🚀 Deployment Instructions

### Step 1: Install Cilium Tetragon (eBPF Engine)
```bash
helm repo add cilium https://helm.cilium.io
helm repo update
helm install tetragon cilium/tetragon -n kube-system
```

### Step 2: Apply the Tracing Policy
```bash
kubectl apply -f k8s/audit/tetragon-terminal-audit-policy.yaml
```

### Step 3: Deploy Log Shipper (Fluent Bit)
```bash
kubectl apply -f k8s/audit/fluentbit-audit-config.yaml
```

### Step 4: SIEM Correlation Query (Elasticsearch / Kibana)
```kql
pod.name: "nodejs-hello-world-*" AND (tag: "audit.argocd" OR tag: "audit.tetragon")
```

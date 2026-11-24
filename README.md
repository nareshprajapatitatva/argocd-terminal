# Node.js Hello World API with Kubernetes and ArgoCD (Local Docker & Audited Terminal)

A complete production-ready GitOps project demonstrating:
- A Node.js Express REST API with health check probes (`/healthz`, `/readyz`).
- Local Docker builds **without needing Docker Hub or any remote registry**.
- Declarative Kubernetes deployment manifests and ArgoCD GitOps application.
- **ArgoCD Web-based Terminal** for executing commands directly from the UI.
- **Production-Grade Audit Trail**: Full visibility into **WHO** opened the terminal and **WHAT** exact commands were executed using kernel-level eBPF (Cilium Tetragon) and SIEM log correlation.

---

## ⚡ Quick One-Command Setup

You can deploy the entire setup (Docker build, ArgoCD, Web Terminal, Tetragon eBPF audit engine, and Node.js API) with a single command:

- **Windows PowerShell**:
  ```powershell
  .\install.ps1
  ```

- **Linux / macOS / WSL (Bash)**:
  ```bash
  chmod +x install.sh
  ./install.sh
  ```

---

## 📁 Project Structure

```text
Argo-terminal/
├── app/
│   ├── server.js              # Express API with health check endpoints (/healthz, /readyz, /)
│   ├── package.json           # Node.js dependencies and scripts
│   ├── Dockerfile             # Multi-stage production container build (non-root user)
│   └── .dockerignore          # Files excluded from the Docker build context
├── k8s/
│   ├── namespace.yaml         # Kubernetes namespace (nodejs-app)
│   ├── deployment.yaml        # Deployment configured with imagePullPolicy: Never
│   ├── service.yaml           # Service exposing port 80 -> targetPort 3000
│   ├── kustomization.yaml     # Kustomize configuration bundling manifests
│   ├── monitoring/            # Prometheus + Loki + Grafana Observability Stack
│   │   ├── namespace.yaml     # Monitoring namespace
│   │   ├── prometheus.yaml    # Prometheus deployment, RBAC & Tetragon scraper
│   │   ├── loki-promtail.yaml # Loki single-binary log engine & Promtail log collector
│   │   ├── grafana.yaml       # Grafana with auto-provisioned Audit Dashboard
│   │   └── kustomization.yaml # Kustomize bundle for monitoring
│   └── audit/
│       ├── tetragon-terminal-audit-policy.yaml  # eBPF TracingPolicy for command auditing
│       ├── tetragon-values.yaml                 # Helm compatibility values for Tetragon
│       ├── fluentbit-audit-config.yaml          # Log shipper to central SIEM
│       └── PRODUCTION_AUDIT_GUIDE.md           # In-depth architectural audit documentation
├── argocd/
│   ├── application.yaml       # ArgoCD Application Custom Resource (GitOps sync config)
│   └── terminal-config.yaml   # Web Terminal feature flag, RBAC, and cluster roles
├── COMMAND_AUDIT_MATRIX.md    # Comprehensive table of commands audited by Tetragon
├── install.ps1                # One-command installer for Windows PowerShell
├── install.sh                 # One-command installer for Linux/macOS/WSL
├── .gitignore
└── README.md
```

---

## 🛠️ Prerequisites

- **Docker** or container runtime
- **Local Kubernetes cluster**:
  - **Docker Desktop** (with Kubernetes enabled), OR
  - **Minikube**, OR
  - **Kind** (Kubernetes in Docker)
- **kubectl** configured to communicate with your local cluster
- **Helm** (v3+) for installing Tetragon / Falco
- **Git** & a remote repository (e.g., GitHub, GitLab)
- **ArgoCD** installed on your cluster

---

## 🚀 Step-by-Step Guide

### Step 1: Build the Docker Image Locally (No Docker Hub Required)

Navigate to the `app/` directory and build the image with the tag `nodejs-hello-world:v1.0.0`:

```bash
cd app
docker build -t nodejs-hello-world:v1.0.0 .
```

#### How to make the local image available to your Kubernetes cluster:

Depending on which local Kubernetes cluster you use:

- **Docker Desktop (Kubernetes enabled)**:
  - **No extra step needed!** Docker Desktop's Kubernetes node shares your local Docker image cache directly.

- **Minikube**:
  > [!TIP]
  > On Windows 11, `minikube image load` fails if `wmic` has been removed. **Use Method A or B below** to build directly inside Minikube without needing `wmic`:

  - **Method A (Recommended - Minikube Docker Daemon)**:
    Point your current PowerShell session to Minikube's internal Docker engine:
    ```powershell
    & minikube -p minikube docker-env --shell powershell | Invoke-Expression
    docker build -t nodejs-hello-world:v1.0.0 ./app
    ```
    *(The image is now directly inside Minikube's runtime—no `image load` needed!)*

  - **Method B (Minikube Image Build)**:
    Build directly inside the cluster using Minikube's CLI:
    ```powershell
    minikube image build -t nodejs-hello-world:v1.0.0 ./app
    ```

- **Kind (Kubernetes in Docker)**:
  - Load the image into your Kind cluster:
    ```bash
    kind load docker-image nodejs-hello-world:v1.0.0
    ```

> [!NOTE]
> [`k8s/deployment.yaml`](file:///d:/Projects/2026/MFX/POC/Argo-terminal/k8s/deployment.yaml) is configured with `imagePullPolicy: Never` so Kubernetes will only use the image loaded onto your local cluster node and will **never** attempt to pull from Docker Hub.

---

### Step 2: Push Your Manifests to a Git Repository

ArgoCD continuously monitors a Git repository to synchronize cluster state.

1. Navigate to the project root:
   ```bash
   cd ..
   git init
   git add .
   git commit -m "Initial commit with local Docker image configuration"
   ```

2. Create a repository on GitHub / GitLab and push your code:
   ```bash
   git branch -M main
   git remote add origin https://github.com/<your-username>/<your-repo>.git
   git push -u origin main
   ```

3. Update the `repoURL` in [argocd/application.yaml](file:///d:/Projects/2026/MFX/POC/Argo-terminal/argocd/application.yaml):
   ```yaml
   source:
     repoURL: https://github.com/<your-username>/<your-repo>.git
     targetRevision: HEAD
     path: k8s
   ```
   *(Commit and push this change to your repository)*.

---

### Step 3: Install ArgoCD (if not already installed)

1. Create the `argocd` namespace and install ArgoCD:
   ```bash
   kubectl create namespace argocd
   kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
   ```

2. Wait for the ArgoCD server pod to be ready:
   ```bash
   kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=argocd-server -n argocd --timeout=300s
   ```

3. Access the ArgoCD Web UI:
   ```bash
   kubectl port-forward --address 127.0.0.1 svc/argocd-server -n argocd 8080:443
   ```
   Open `https://127.0.0.1:8080` (or `https://localhost:8080`) in your browser.
   *(Note: Always use `https://`. If your browser shows a certificate warning, click Advanced -> Proceed to localhost).*

4. Retrieve the initial `admin` password:
   - **Windows PowerShell**:
     ```powershell
     [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String((kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}")))
     ```
   - **Linux / macOS**:
     ```bash
     kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d; echo
     ```

---

### Step 4: Deploy the Application via ArgoCD

Apply the ArgoCD `Application` resource:

```bash
kubectl apply -f argocd/application.yaml
```

ArgoCD will automatically:
1. Connect to your Git repository.
2. Read `k8s/` manifests.
3. Create the `nodejs-app` namespace.
4. Deploy the 2 pods using your local `nodejs-hello-world:v1.0.0` Docker image.

---

### Step 5: Enable the ArgoCD Web Terminal (Exec in UI)

ArgoCD includes a built-in web terminal to execute commands directly inside containers from the web browser. It is disabled by default for security.

1. Apply [`argocd/terminal-config.yaml`](file:///d:/Projects/2026/MFX/POC/Argo-terminal/argocd/terminal-config.yaml) (enables `exec.enabled: "true"`, ArgoCD RBAC, and Kubernetes cluster roles):
   ```bash
   kubectl apply -f argocd/terminal-config.yaml
   ```

2. Restart the `argocd-server` deployment to apply changes:
   ```bash
   kubectl rollout restart deployment argocd-server -n argocd
   ```

3. Open the ArgoCD Web UI (`https://localhost:8080`), click on your `nodejs-hello-world` application, click on any running Pod, and select the **Terminal** tab. You can now execute commands interactively in the container!

---

### Step 6: Production-Grade Terminal Auditing ("WHO" and "WHAT")

In production and compliance environments (SOC 2, ISO 27001, PCI-DSS), you must audit:
1. **WHO opened the terminal session** (User identity, IP, timestamp).
2. **WHAT commands and actions were performed** (Tamper-proof command logging).

```text
 ┌────────────────────────────────────────────────────────┐
 │ Layer 1: "WHO" (ArgoCD Server Audit Logs + SSO)        │ ──┐
 └────────────────────────────────────────────────────────┘   │
                                                              ├──► [ SIEM / Log Analytics ]
 ┌────────────────────────────────────────────────────────┐   │    (Splunk / Elastic / Datadog)
 │ Layer 2: "WHAT" (eBPF Kernel Tracing via Tetragon)     │ ──┘
 └────────────────────────────────────────────────────────┘
```

#### Layer 1: Tracking "WHO" (ArgoCD Audit Stream)
- Configure ArgoCD SSO (OIDC/SAML with Okta, Azure AD, or Google Workspace) so sessions reflect real user emails instead of generic `admin`.
- When a user opens the terminal, `argocd-server` logs:
  ```json
  {
    "time": "2026-11-24T15:32:01Z",
    "sub": "alice.smith@yourcompany.com",
    "application": "nodejs-hello-world",
    "podName": "nodejs-hello-world-74697ff789-9r84b",
    "action": "terminal",
    "clientIP": "10.0.4.15"
  }
  ```

#### Layer 2: Tracking "WHAT" (Kernel eBPF via Cilium Tetragon)
Container users can easily delete bash history (`history -c` or `unset HISTFILE`). eBPF operates inside the Linux kernel and intercepts the `sys_enter_execve` system call **before** CPU execution—making it **100% tamper-proof**.

1. **Install Cilium Tetragon via Helm**:
   ```bash
   helm repo add cilium https://helm.cilium.io
   helm repo update
   helm install tetragon cilium/tetragon -n kube-system -f k8s/audit/tetragon-values.yaml
   ```

2. **Ensure Tetragon CRDs are registered (using stable v1.2.0 release)**:
   ```bash
   kubectl apply -f https://raw.githubusercontent.com/cilium/tetragon/v1.2.0/pkg/k8s/apis/cilium.io/client/crds/v1alpha1/cilium.io_tracingpolicies.yaml
   kubectl apply -f https://raw.githubusercontent.com/cilium/tetragon/v1.2.0/pkg/k8s/apis/cilium.io/client/crds/v1alpha1/cilium.io_tracingpoliciesnamespaced.yaml
   ```

3. **Apply the Terminal Audit TracingPolicy**:
   ```bash
   kubectl apply -f k8s/audit/tetragon-terminal-audit-policy.yaml
   ```

4. **View live command audit logs in human-readable format**:

   - **Method A (Recommended - Clean, Colorized via built-in `tetra` CLI)**:
     ```bash
     kubectl exec -it -n kube-system ds/tetragon -c tetragon -- tetra getevents -o compact --namespaces nodejs-app
     ```
     Sample output:
     ```text
     🚀 process nodejs-app/nodejs-hello-world-xxx /bin/ls -la
     📁 chdir   nodejs-app/nodejs-hello-world-xxx node_modules
     🚀 process nodejs-app/nodejs-hello-world-xxx /bin/cat server.js
     💥 exit    nodejs-app/nodejs-hello-world-xxx /bin/cat 0
     ```

   - **Method B (PowerShell live stream formatter)**:
     ```powershell
     kubectl logs -n kube-system -l app.kubernetes.io/name=tetragon -c export-stdout -f | ForEach-Object {
         $e = $_ | ConvertFrom-Json -ErrorAction SilentlyContinue
         if ($e.process_exec -and $e.process_exec.process.pod.namespace -eq "nodejs-app") {
             $p = $e.process_exec.process
             Write-Host "[$($e.time.Substring(11,8))] [EXEC]  $($p.binary) $($p.arguments) (in $($p.cwd))" -ForegroundColor Green
         }
         elseif ($e.process_kprobe -and $e.process_kprobe.process.pod.namespace -eq "nodejs-app") {
             $k = $e.process_kprobe
             Write-Host "[$($e.time.Substring(11,8))] [CD]    cd $($k.args[0].string_arg)" -ForegroundColor Cyan
         }
     }
     ```

   - **Method C (Raw JSON stream)**:
     ```bash
     kubectl logs -n kube-system -l app.kubernetes.io/name=tetragon -c export-stdout -f
     ```

   Whenever any command runs in the ArgoCD terminal (e.g. `cat /etc/passwd`, `env`), Tetragon records:
   ```json
   {
     "time": "2026-11-24T15:32:05Z",
     "process_exec": {
       "process": {
         "binary": "/bin/cat",
         "arguments": "/bin/cat /etc/passwd",
         "pod": { "namespace": "nodejs-app", "name": "nodejs-hello-world-74697ff789-9r84b" }
       }
     }
   }
   ```

#### Layer 3: SIEM Log Shipping & Correlation
- Deploy Fluent Bit using [`k8s/audit/fluentbit-audit-config.yaml`](file:///d:/Projects/2026/MFX/POC/Argo-terminal/k8s/audit/fluentbit-audit-config.yaml) to forward both `audit.argocd` and `audit.tetragon` streams to your central SIEM (Elasticsearch, Splunk, Datadog, or Grafana Loki).
- Correlate by matching `podName` + `time_window` to produce a single audit timeline linking the authenticated user to every executed command.
- For complete architecture details, see [`k8s/audit/PRODUCTION_AUDIT_GUIDE.md`](file:///d:/Projects/2026/MFX/POC/Argo-terminal/k8s/audit/PRODUCTION_AUDIT_GUIDE.md).

---

### Step 7: Review Audit Logs & Metrics in Prometheus + Grafana

The monitoring stack includes:
- **Prometheus**: Scrapes Tetragon eBPF kernel metrics (`tetragon_events_total`, `tetragon_policy_events_total`).
- **Grafana Loki + Promtail**: Aggregates live container and kernel audit logs.
- **Grafana**: Pre-loaded with automated DataSources and a ready-to-use **Kubernetes & ArgoCD Terminal Audit Dashboard**.

#### 1. Deploy the Monitoring Stack
```bash
kubectl apply -k k8s/monitoring/
```
Wait for pods to be ready:
```bash
kubectl rollout status deployment/prometheus -n monitoring
kubectl rollout status deployment/grafana -n monitoring
```

#### 2. Open the Grafana Dashboard
Port-forward Grafana to your local machine:
```bash
kubectl port-forward svc/grafana-service -n monitoring 3000:3000
```
Open **`http://localhost:3000`** in your browser:
- **Username**: `admin`
- **Password**: `admin` *(or automatically logs in with anonymous admin)*
- Navigate to **Dashboards** -> **Kubernetes Audit** -> **Kubernetes & ArgoCD Terminal Audit Dashboard**.

You will see:
- 📊 **Total Audit Events counter**
- 📈 **Process Executions Over Time (Timeseries)**
- 📜 **Live Terminal & Application Audit Logs (Loki log viewer)**
- 🔎 **Raw Tetragon Kernel Audit Stream (eBPF)**

#### 3. Search Logs in Grafana Explore
Click **Explore** on the left menu, select **Loki** as the datasource, and run queries:
- View all commands executed in the Node.js application:
  ```logql
  {namespace="nodejs-app"}
  ```
- Search for specific commands (e.g. `cat`):
  ```logql
  {namespace="kube-system"} |= "process_exec" |= "cat"
  ```

---

### Step 8: Test the Deployed API

1. Verify pods and service:
   ```bash
   kubectl get pods -n nodejs-app
   kubectl get svc -n nodejs-app
   ```

2. Port-forward the service to your host:
   ```bash
   kubectl port-forward svc/nodejs-hello-world-svc -n nodejs-app 8000:80
   ```

3. Test the endpoints:
   ```bash
   curl http://localhost:8000/
   curl http://localhost:8000/healthz
   ```

   Expected response:
   ```json
   {
     "message": "Hello World from Node.js on Kubernetes managed by ArgoCD!",
     "environment": "production",
     "hostname": "nodejs-hello-world-...",
     "version": "1.0.0"
   }
   ```

---

### Step 9: Experience GitOps in Action

1. Change `replicas: 2` to `replicas: 4` in [`k8s/deployment.yaml`](file:///d:/Projects/2026/MFX/POC/Argo-terminal/k8s/deployment.yaml).
2. Commit and push:
   ```bash
   git add k8s/deployment.yaml
   git commit -m "Scale up to 4 replicas"
   git push origin main
   ```
3. Check ArgoCD or run `kubectl get pods -n nodejs-app`. ArgoCD automatically detects the Git change and reconciles the cluster to run 4 pods without manual `kubectl apply`.

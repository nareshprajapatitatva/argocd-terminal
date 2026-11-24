# Node.js Hello World API with Kubernetes and ArgoCD (Local Docker Image)

A complete GitOps starter project demonstrating how to build a Node.js Express REST API, containerize it with Docker **locally (without pushing to Docker Hub or any remote registry)**, define Kubernetes manifests, and manage continuous deployment using ArgoCD.

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
│   └── kustomization.yaml     # Kustomize configuration bundling manifests
├── argocd/
│   └── application.yaml       # ArgoCD Application Custom Resource (GitOps sync config)
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
   kubectl port-forward svc/argocd-server -n argocd 8080:443
   ```
   Open `https://localhost:8080` in your browser.

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

### Step 5: Test the Deployed API

1. Verify the pods are running:
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

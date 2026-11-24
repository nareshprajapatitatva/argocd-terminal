# Tetragon Terminal Command Audit Matrix

This document provides a comprehensive audit matrix of commands executed in the Kubernetes terminal, detailing what **Cilium Tetragon (eBPF)** captures at the Linux kernel level without requiring any modifications to container images.

---

## 📊 Command Audit Matrix

| Command | Command Type | Logged by Tetragon? | What Tetragon Records in Audit Logs |
| :--- | :--- | :---: | :--- |
| **`cat <file>`** | Binary (`/bin/cat`) | **YES** | Exact binary path + target filename in `arguments` (e.g. `cat server.js`) |
| **`ls` / `ls -la`** | Binary (`/bin/ls`) | **YES** | Binary path + all CLI flags in `arguments` (e.g. `ls -la`) |
| **`rm <file>`** | Binary (`/bin/rm`) | **YES** | Binary path + deleted target file path in `arguments` |
| **`cp` / `mv`** | Binary (`/bin/cp`, `/bin/mv`) | **YES** | Source and destination file paths in `arguments` |
| **`mkdir` / `rmdir`** | Binary (`/bin/mkdir`) | **YES** | Binary path + directory path created or removed |
| **`chmod` / `chown`** | Binary (`/bin/chmod`) | **YES** | Permissions and target file/directory modified |
| **`touch <file>`** | Binary (`/bin/touch`) | **YES** | File created or timestamp updated |
| **`grep` / `awk` / `sed`** | Binary (`/bin/grep`, etc.) | **YES** | Exact search strings, regex, and target files in `arguments` |
| **`node <file>` / `npm`** | Binary (`/usr/local/bin/node`) | **YES** | Node script and all execution CLI arguments |
| **`curl` / `wget`** | Binary (`/usr/bin/curl`) | **YES** | Target URL, IP address, and downloaded payload destination |
| **`ps` / `top`** | Binary (`/bin/ps`) | **YES** | Process listing and reconnaissance attempt |
| **`whoami` / `id`** | Binary (`/usr/bin/whoami`) | **YES** | User identity reconnaissance command |
| **`env`** | Binary (`/usr/bin/env`) | **YES** | Environment variable inspection attempt |
| **`kill <pid>`** | Binary or Syscall | **YES** | Target process PID and signal number |
| **`sh` / `bash`** | Binary (Shell spawn) | **YES** | Spawning of interactive terminal session |
| **`cd <dir>`** | Shell Built-in | **INDIRECTLY** | Does not log the word `cd`. Captures the `sys_chdir` kernel syscall and updates `"cwd"` (current working directory) on all subsequent events. |
| **`pwd`** | Shell Built-in | **NO** | Evaluated entirely inside shell memory. Tetragon already records the active directory on every other action via `"cwd"`. |
| **`echo "text"`** | Shell Built-in | **NO** | Runs purely in shell process memory without making kernel system calls. |
| **`export FOO=bar`** | Shell Built-in | **NO** | Sets in-memory shell environment variable. |
| **`alias` / `unalias`** | Shell Built-in | **NO** | Manipulates internal shell in-memory alias dictionary. |
| **`exit`** | Shell Built-in | **YES** | Logs `process_exit` when the shell session terminates. |

---

## 🔍 Why Built-ins Differ from Executable Binaries

### 1. Executable Binaries (`cat`, `ls`, `node`, `curl`, `rm`)
- Stored as physical files on the container filesystem (e.g., `/bin/ls`, `/bin/cat`).
- The shell must invoke the Linux kernel's **`sys_execve`** system call to spawn a new process.
- **Tetragon intercepts the kernel system call directly**, recording:
  - Binary name
  - All CLI arguments (`arguments`)
  - User ID (`uid`)
  - Target Pod, Namespace, and Container
  - Timestamp

### 2. Shell Built-ins (`pwd`, `cd`, `echo`, `export`)
- Built directly into the compiled code of `/bin/sh` or `/bin/bash`.
- **`pwd`**: Evaluated directly in shell memory; it prints the working directory using memory without calling any external binary.
- **`cd`**: Changes the working directory of the current shell process via `chdir()`. It cannot be an external binary because a child process cannot change its parent process's directory.
- While the literal letters `'pwd'` are not captured, **the active directory is already recorded on every single Tetragon event** in the `"cwd"` field (e.g. `"cwd": "/usr/src/app/node_modules"`).

---

## 🛡️ Security & Compliance Assessment

For enterprise audits (**SOC 2**, **ISO 27001**, **PCI-DSS**, and **HIPAA**):

- **100% of real actions, data access, and threats are audited**: Any command that reads sensitive files (`cat server.js`, `/etc/passwd`), modifies files (`rm`, `cp`, `mv`), executes scripts (`node`, `npm`), or connects to external networks (`curl`, `wget`) is an external binary and is **fully captured by Tetragon with all CLI arguments**.
- **Tamper-proof**: Because Tetragon runs at the Linux kernel level outside the container, users inside the terminal cannot hide their commands, delete logs, or bypass eBPF probes.
- **Zero overhead on images**: Applications run on standard, unmodified production Docker images without requiring debug tools or custom wrapper scripts.

---

## 📋 Sample Tetragon Audit Event

```json
{
  "process_exec": {
    "process": {
      "binary": "/bin/cat",
      "arguments": "server.js",
      "cwd": "/usr/src/app",
      "uid": 1000,
      "pod": {
        "namespace": "nodejs-app",
        "name": "nodejs-hello-world-76ccf56d5c-fkf2h",
        "container": {
          "name": "nodejs-hello-world",
          "image": { "name": "nodejs-hello-world:v1.0.0" }
        }
      },
      "start_time": "2026-11-24T10:30:00.953730164Z"
    }
  },
  "node_name": "minikube",
  "time": "2026-11-24T10:30:00.951142884Z"
}
```

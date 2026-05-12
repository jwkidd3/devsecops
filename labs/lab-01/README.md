# Lab 1: Sandbox Setup
### Stand up your Cloud9 environment and the lab targets
**DevSecOps — Module 1 of 9**

---

## Lab overview

### Objectives

- Provision your AWS Cloud9 environment in the shared training account
- Attach the lab IAM role and verify access
- Clone the course materials and run the setup script
- End with both lab targets running and Jenkins pre-staged for Lab 10

### Prerequisites

- AWS account credentials provided by the instructor (sign-in URL, username, password)
- Course repo URL provided by the instructor

> ⏱ **Duration:** ~30 minutes (Cloud9 boot + image pulls dominate)

---

## Step 1: Create your Cloud9 environment

1. Sign in to the **AWS Management Console** using the URL and credentials provided by the instructor.
2. Set the region to the one the instructor named (top-right dropdown).
3. Search for **Cloud9** in the services search bar and open it.
4. If a `devsecops-lab-<your-name>` already exists, open it and skip to Step 2. Otherwise click **Create environment**.
5. **Name:** `devsecops-lab-<your-name>` (first-name-last-initial, lowercase, no spaces — e.g. `devsecops-lab-alexk`)
6. **Environment type:** New EC2 instance
7. **Instance type:** **`m5.large`**
8. **Platform:** Amazon Linux 2023 (or Amazon Linux 2 if AL2023 isn't available)
9. **Network connection:** **SSH** (not SSM)
10. Leave VPC/Subnet at defaults unless the instructor specifies otherwise.
11. Click **Create**.
12. Wait 1–2 minutes for status **Ready**, then click **Open** to launch the IDE.

You'll work in the Cloud9 terminal (bottom panel) for every lab.

---

## Step 2: Attach the lab IAM role

Cloud9's managed credentials cannot reach the AWS services we need (CloudWatch in Lab 9). The role `devsecops-lab-role` was created during account setup. Disable managed creds and attach the role.

### Disable Cloud9 managed credentials

1. In the Cloud9 IDE click the **gear icon** (top-right) → **Cloud9 → Preferences**.
2. Expand **AWS Settings**.
3. Turn **OFF** "AWS managed temporary credentials".

### Attach the role to your instance

1. Open the **EC2 Console** in a new browser tab.
2. Find your Cloud9 instance — name starts with `aws-cloud9-devsecops-lab-<your-name>-...`.
3. Select it → **Actions → Security → Modify IAM role**.
4. Choose `devsecops-lab-role` → **Update IAM role**.

### Verify

In the Cloud9 terminal:

```bash
aws sts get-caller-identity
```

> ✅ **Checkpoint:** the output shows the `devsecops-lab-role` ARN, **not** Cloud9 managed credentials.

---

## Step 3: Clone & run

```bash
cd ~/environment
git clone <repo-url-from-instructor> devsecops
bash devsecops/labs/lab-01/scripts/setup-cloud9.sh <your-name>
```

The script takes 3–8 minutes on first run. It:

- Installs `nmap`, `jq`, `git`, `openssl`
- Pulls every Docker image used in later labs (Juice Shop, Metasploitable, Trivy, Metasploit, ZAP, Jenkins, Semgrep)
- Starts Juice Shop and Metasploitable on a private Docker network
- Pre-stages Jenkins for the Lab 10 capstone
- Saves your environment notes to `~/devsecops-lab-env.md`

Idempotent — safe to re-run if anything looks wrong.

---

## Step 4: Verify

```bash
# Juice Shop responds
curl -sI http://localhost:8080 | head -1                        # → HTTP/1.1 200 OK

# Metasploitable is reachable
META_IP=$(awk -F'|' '/Metasploitable IP/ {gsub(/^[ \t]+|[ \t]+$/, "", $3); print $3}' ~/devsecops-lab-env.md)
nmap -Pn -p 21,22,80 $META_IP                                   # → ports 21, 22, 80 open
```

> ✅ **Checkpoint:** both pass — targets, tools, and Jenkins are in place for every later lab.

To browse Juice Shop visually, use Cloud9's **Preview → Preview Running Application** menu (forwards port 3000).

---

## Cleanup

**Don't clean up yet** — every later lab assumes the targets are running. If your Cloud9 is destroyed at end of class, no cleanup needed.

---

## Troubleshooting

| Symptom | Cause / fix |
|---|---|
| `aws sts get-caller-identity` doesn't show `devsecops-lab-role` | Step 2 incomplete — re-disable managed creds and re-attach the role |
| `setup-cloud9.sh: Permission denied` | `chmod +x devsecops/labs/lab-01/scripts/setup-cloud9.sh` then re-run |
| `docker: permission denied` | Open a fresh terminal tab (group membership refresh), or prefix with `sudo` |
| `no space left on device` during image pulls | EC2 console → your volume → Modify volume → 100 GB; then in terminal: `sudo growpart /dev/nvme0n1 1 && sudo xfs_growfs -d /` |
| Juice Shop returns 502 / no response | Wait 30 sec — Node app takes a moment to start |
| Anything else | Re-run the setup script — it's idempotent and prints a clear error if a step fails |

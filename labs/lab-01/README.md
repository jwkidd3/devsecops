# Lab 1: Sandbox Setup
### Stand up the lab targets in your Cloud9 environment
**DevSecOps — Module 1 of 9**

---

## Lab overview

### Objectives

- Open your pre-provisioned Cloud9 environment
- Clone the course materials
- Run a single setup script that installs everything and starts both lab targets

### Prerequisites

- Your instructor created your Cloud9 (named `devsecops-lab-<your-name>`) and attached the lab IAM role
- The instructor gave you the **course repo URL** and your **`<your-name>` suffix**

> ⏱ **Duration:** ~10 minutes (most of it is the setup script pulling images)

---

## Step 1: Open your Cloud9

In the AWS console → **Cloud9** → click **Open** next to `devsecops-lab-<your-name>`. You'll work in the terminal at the bottom of the IDE for every lab.

> ✅ **Quick sanity check** — paste this into the terminal:
>
> ```bash
> aws sts get-caller-identity
> ```
>
> The output should show the `devsecops-lab-role` ARN. If it doesn't, flag your instructor — the role wasn't attached correctly.

---

## Step 2: Clone & run

Two commands. The script is idempotent — safe to re-run if anything looks wrong.

```bash
cd ~/environment
git clone <repo-url-from-instructor> devsecops
bash devsecops/labs/lab-01/scripts/setup-cloud9.sh <your-name>
```

The script takes 3–8 minutes on first run. It:

- Installs `nmap`, `jq`, `git`, `openssl`
- Pulls every Docker image used in later labs (Juice Shop, Metasploitable, Trivy, Metasploit, ZAP, Jenkins, Semgrep)
- Starts Juice Shop and Metasploitable on a private Docker network
- Pre-stages Jenkins for the Lab 9 capstone
- Saves your environment notes to `~/devsecops-lab-env.md`

When it finishes you'll see a summary table with all the URLs and IPs you'll need across the course.

---

## Step 3: Verify

Two checks. Both should pass:

```bash
# Juice Shop responds
curl -sI http://localhost:3000 | head -1                        # → HTTP/1.1 200 OK

# Metasploitable is reachable
META_IP=$(grep "Metasploitable IP" ~/devsecops-lab-env.md | awk '{print $NF}')
nmap -Pn -p 21,22,80 $META_IP                                   # → ports 21, 22, 80 open
```

> ✅ **Checkpoint:** if both pass, you're done. The targets, tools, and Jenkins are all in place for every later lab.

To browse Juice Shop visually, use Cloud9's **Preview → Preview Running Application** menu (forwards port 3000).

---

## Cleanup

**Don't clean up yet** — every later lab assumes the targets are running.

At end of course (or for a fresh start), the setup script's notes file shows the cleanup commands. If your Cloud9 is destroyed at end of class, no cleanup needed — everything goes with it.

---

## Troubleshooting

| Symptom | Cause / fix |
|---|---|
| `aws sts get-caller-identity` doesn't show `devsecops-lab-role` | Tell your instructor — IAM role wasn't attached pre-class |
| `setup-cloud9.sh: Permission denied` | `chmod +x devsecops/labs/lab-01/scripts/setup-cloud9.sh` then re-run |
| `docker: permission denied` | Open a fresh terminal tab (group membership refresh), or prefix with `sudo` |
| Juice Shop returns 502 / no response | Wait 30 sec — Node app takes a moment to start |
| Cloud9 disk fills during image pulls | EC2 console → your volume → Modify volume → 30 GB |
| Anything else | Re-run the setup script — it's idempotent and prints a clear error if a step fails |

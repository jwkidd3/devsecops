# Lab 10 (Capstone): Jenkins + ZAP DAST stage on Cloud9
### A security-gated CI pipeline, end-to-end
**DevSecOps — Module 9 of 9**

---

## Lab overview

This is the course capstone. You'll wire every previous module's tooling into a single Jenkins pipeline: **Build → SAST → SCA → DAST → Severity gate**.

> ⏱ **Duration:** 30 min hands-on
> 👥 **Pair:** Optional

### Objectives

- Connect to the Jenkins instance pre-staged on your Cloud9 by Lab 1's setup script
- Wire a pipeline against the sample `Jenkinsfile` (already in place at `~/environment/devsecops-work/lab9/sample-repo/`)
- Run **Build → SAST (Semgrep) → SCA (Trivy) → DAST (ZAP baseline)** stages
- Watch the Critical-severity gate fail the build, then ship a documented "path to green"

### Prerequisites

- Lab 1 setup script ran successfully (started Jenkins in the background — it has been warming up since Day 1)
- `~/devsecops-lab-env.md` lists Jenkins URL and the admin-password command

> 💡 **Why this works in 30 min:** Lab 1 pre-pulled all pipeline images, started Jenkins, and scaffolded the `Jenkinsfile`. Plugin install completed hours ago. You're walking into a warm environment.

---

## Step 1: Connect to Jenkins (5 min)

Open Jenkins via Cloud9 **Preview → Preview Running Application** at port 8081, or via the public URL the instructor provided.

Get the initial admin password:

```bash
docker exec ds-jenkins cat /var/jenkins_home/secrets/initialAdminPassword
```

If this is the first time you've opened Jenkins:

1. Paste the admin password
2. **Install suggested plugins** (already cached — completes in ~30 sec)
3. Create your first admin user (use any credentials — this is your Cloud9 only)
4. Accept the default Jenkins URL → **Start using Jenkins**

If you opened it earlier (some students do during the morning), just log in with the admin user you created.

> ✅ **Checkpoint:** you see the Jenkins dashboard.

---

## Step 2: Verify the sample repo is mounted (1 min)

```bash
docker exec ds-jenkins ls /var/sample-repo
# Expected: README.md  Jenkinsfile  .git
```

If `.git` is missing, re-run a quick init:

```bash
cd ~/environment/devsecops-work/lab9/sample-repo && \
  git init -q -b main && \
  git -c user.email=lab@example.com -c user.name=Lab add . && \
  git -c user.email=lab@example.com -c user.name=Lab commit -q -m "Re-init"
```

---

## Step 3: Create the pipeline job (3 min)

In Jenkins UI:

1. **New Item** → name `juice-shop-pipeline` → **Pipeline** → OK
2. Scroll to **Pipeline → Definition: Pipeline script from SCM**
3. **SCM:** Git
4. **Repository URL:** `/var/sample-repo`
5. **Branch Specifier:** `*/main`
6. **Script Path:** `Jenkinsfile`
7. **Save**

---

## Step 4: First build — observe failure (8–12 min)

Click **Build Now**. Open the build's **Console Output** so you can watch each stage.

Stage progression:

- **Checkout** ✓ — quick
- **SAST — Semgrep** ✓ — runs against the sample repo
- **SCA — Trivy** ✓ — quick on a one-file repo
- **DAST — ZAP baseline** ⏳ — 3–5 min runtime against your Juice Shop
- **Critical gate** ❌ — **expected to fail** because Juice Shop has High-risk findings

> ✅ **Checkpoint:** the build is RED at the Critical gate stage. Open the **ZAP Baseline** report link from the build page to see the findings.

---

## Step 5: Path to green (5–8 min)

You have two valid responses to a CI gate that's blocking:

- **Fix the underlying issue** — ideal, but Juice Shop is intentionally vulnerable, so out of scope here
- **Adjust the threshold** with a recorded justification — what you'll do now

Edit the Jenkinsfile — set an explicit allowance:

```bash
nano ~/environment/devsecops-work/lab9/sample-repo/Jenkinsfile
```

Find the `Critical gate` stage and change the `ALLOWED_HIGH` value to a number that exceeds the High count (the report told you the count). Example:

```groovy
sh '''HIGH=$(jq '[.site[].alerts[] | select(.riskcode | tonumber >= 3)] | length' zap-baseline.json)
      ALLOW=${ALLOWED_HIGH:-3}     # was 0; explicit baseline while remediation ships
      ...
```

Commit:

```bash
cd ~/environment/devsecops-work/lab9/sample-repo
git add Jenkinsfile
git -c user.email=lab@example.com -c user.name=Lab commit -q \
    -m "Allow High-finding baseline of 3 while team ships remediation"
```

Back in Jenkins → **Build Now** again.

> ✅ **Checkpoint:** the second build is GREEN. The path to green is **documented in the commit** — exactly the practice Module 9 prescribed.

---

## Step 6: Reflect (3 min)

In `~/environment/devsecops-work/lab9-reflection.md`, jot answers to:

1. What's the difference between **silencing** the gate and **escaping** it? Which did you do?
2. If this were a real product, who needs to sign off on the `ALLOWED_HIGH` threshold — and how often do they revisit it?
3. Which previous module's tools are you most likely to wire into your team's pipeline first?

---

## Cleanup (after class)

Jenkins keeps running on your Cloud9 instance until you tear it down:

```bash
cd ~/environment/devsecops-work/lab9/jenkins
docker compose down -v
```

Targets stay until you remove them.

---

## Troubleshooting

| Symptom | Fix |
|---|---|
| Cloud9 out of memory | `docker stats` → stop the heaviest containers between attempts |
| Jenkins not reachable on 8081 | `docker compose -f ~/environment/devsecops-work/lab9/jenkins/docker-compose.yml up -d` |
| `docker: not found` in pipeline | The setup script runs an apt-get inside Jenkins ~30s after start. If it didn't, run: `docker exec -u root ds-jenkins apt-get install -y docker.io jq` |
| Pipeline can't clone `/var/sample-repo` | `docker exec ds-jenkins ls /var/sample-repo` should show the Jenkinsfile |
| `jq: command not found` in the gate stage | Same as above — install jq inside Jenkins |
| ZAP baseline can't reach `juice-shop` | Confirm the compose file lists the `devsecops-lab` external network |
| First build gets stuck pulling images | Image pulls happen inside the pipeline container; wait — first run is slow even when host has them cached |

---

## Stretch goals (after class)

- Add a **container image scan** stage (`trivy image bkimminich/juice-shop`) before DAST
- Add a **secrets-scan stage** (`gitleaks detect`) right after Checkout
- Push the `zap-baseline.json` to your Lab 9 CloudWatch Logs so findings show up alongside the SSH-failure detection
- Replace the inline shell with a Jenkins **shared library** so multiple repos can reuse the security stages

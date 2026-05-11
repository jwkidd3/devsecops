# Module 3 Hands-on: IaC Scanning with Checkov
### Catch infrastructure misconfigurations before they ever reach the cloud
**DevSecOps — Module 3 of 9**

---

## Lab overview

### Objectives

- Run Checkov against a deliberately-vulnerable Terraform file
- Read findings and map them to the cloud threat classes from Module 3
- Fix one finding and verify the scan turns green
- Decide where IaC scanning belongs in the pipeline

### Prerequisites

- Lab 1 complete (Docker working)

> ⏱ **Duration:** 20 minutes
> 👥 **Pair:** Optional

---

## Step 1: Inspect the bad file (3 min)

The repo includes a Terraform file with at least six security issues:

```bash
cd ~/environment/devsecops/labs/lab-iac
cat bad-iac/main.tf
```

Read it and spot the problems by eye before scanning. Discuss with your pair what looks wrong.

---

## Step 2: Scan with Checkov (5 min)

```bash
docker run --rm -t -v "$PWD/bad-iac:/tf" bridgecrew/checkov:latest \
  --directory /tf --quiet --compact
```

First run pulls the image (~30 sec); the scan itself is < 5 sec.

You'll see a list of **FAILED** checks, each tagged with an ID like `CKV_AWS_24`. Skim them.

---

## Step 3: Triage (5 min)

For each FAILED check, decide:

- Which **Module 3 threat class** does it belong to — Identity, Network, or Data & Secrets?
- Is the fix safe to apply without breaking a workload that depends on it?

Capture two or three of the highest-impact findings in `~/environment/devsecops-work/lab-iac-triage.md`.

---

## Step 4: Fix one finding (5 min)

Open `bad-iac/main.tf` and make one change — e.g., narrow a `cidr_blocks = ["0.0.0.0/0"]` to your office IP, or set `storage_encrypted = true`. Save.

Re-run the scan:

```bash
docker run --rm -t -v "$PWD/bad-iac:/tf" bridgecrew/checkov:latest \
  --directory /tf --quiet --compact
```

The FAILED count should drop. The corresponding check is now PASSED.

> ✅ **Checkpoint:** you watched a security finding disappear from the report by fixing the source. That's the loop a developer experiences when IaC scanning runs in CI.

---

## Step 5: Reflect (2 min)

In `~/environment/devsecops-work/lab-iac-triage.md`, write one sentence answering each:

1. Where in your team's pipeline would this scan live? PR-time? Merge-time? Both?
2. What's the **cost of a false positive** for an IaC scanner — and how would you tune for that?

---

## Cleanup

Checkov is stateless. Nothing to clean up.

---

## Troubleshooting

| Symptom | Fix |
|---|---|
| `bridgecrew/checkov: not found` | Confirm Docker is running and you have internet access on the Cloud9 |
| Scan returns 0 findings | Re-check you scanned `/tf` (the bind-mount), not the host path |
| `Permission denied` writing triage file | `mkdir -p ~/environment/devsecops-work` |

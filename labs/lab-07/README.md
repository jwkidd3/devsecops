# Lab 7: OWASP ZAP Basics
### Spider, passive-scan, and active-scan Juice Shop — headless on Cloud9
**DevSecOps — Module 7 of 9**

---

## Lab overview

### Objectives

- Run a headless ZAP **baseline scan** against Juice Shop
- Read and triage the HTML / JSON report
- Map findings to OWASP Top 10 categories

### Prerequisites

- Lab 1 completed; Juice Shop on the `devsecops-lab` network

> ⏱ **Duration:** 30 min — baseline ~3 min runtime, the rest is triage
> 👥 **Pair:** No

> 💡 Cloud9 has no desktop, so we run the **headless** ZAP container — the same approach Lab 9 will use in CI.

---

## Step 1: Baseline scan (passive only) — ~3 min

```bash
mkdir -p ~/environment/devsecops-work/zap
chmod 777 ~/environment/devsecops-work/zap   # ZAP container runs as a different uid

docker run --rm -t \
  --network devsecops-lab \
  -v $HOME/environment/devsecops-work/zap:/zap/wrk:rw \
  ghcr.io/zaproxy/zaproxy:stable \
  zap-baseline.py \
    -t http://juice-shop:3000 \
    -r lab7-baseline.html \
    -J lab7-baseline.json \
    -I
```

- `-I` keeps the exit code 0 even if warnings are present (we'll gate on this in Lab 9).
- The report lands in `~/environment/devsecops-work/zap/lab7-baseline.html`.

> ✅ **Checkpoint:** the command exits with **PASS** / **FAIL** summary and produces both `.html` and `.json` files.

---

## Step 2: Understand the modes (read while scan runs)

| Mode | What it does | When to use |
|---|---|---|
| Spider | Crawls links from a seed URL (no JS) | Always — fast |
| AJAX Spider | Drives a real browser to discover client-rendered URLs | SPAs |
| Passive scan | Inspects every request/response — no extra traffic | Always on |
| Active scan | Sends attack payloads (XSS, SQLi, etc.) | Lab/staging only |

`zap-baseline.py` = spider + passive only. `zap-full-scan.py` adds active (covered in stretch goals).

---

## Step 3: Triage the report

Open `lab7-baseline.html` via Cloud9 (right-click → **Open**), or summarise with jq:

```bash
# Top alert categories sorted by count
jq -r '.site[].alerts[] | "\(.riskdesc)\t\(.name)"' \
  ~/environment/devsecops-work/zap/lab7-baseline.json \
  | sort | uniq -c | sort -rn

# High-severity only (the same one-liner Lab 9's gate uses)
jq '.site[].alerts[] | select(.riskcode | tonumber >= 3) | {risk: .riskdesc, name: .name}' \
  ~/environment/devsecops-work/zap/lab7-baseline.json
```

In `~/environment/devsecops-work/zap/lab7-triage.md`, answer:

1. How many **Medium**+**High** findings did the baseline report?
2. Which OWASP Top 10 category does each Medium+ map to?
3. Pick **one** finding — could you reproduce it manually with `curl`?
4. Which findings would you classify as **false positive** for a B2C web app like this?

---

## Cleanup

ZAP runs with `--rm`, so containers self-clean. Reports stay in `~/environment/devsecops-work/zap/`.

---

## Stretch goals (after class)

### Full scan (passive + active) — 10–15 min runtime

> ⚠️ Active scans send attack traffic. Scoped only to your own Juice Shop on the lab network.

```bash
docker run --rm -t \
  --network devsecops-lab \
  -v $HOME/environment/devsecops-work/zap:/zap/wrk:rw \
  ghcr.io/zaproxy/zaproxy:stable \
  zap-full-scan.py \
    -t http://juice-shop:3000 \
    -r lab7-full.html \
    -J lab7-full.json \
    -I -T 10
```

`-T 10` time-bounds the scan to 10 minutes.

In a real CI pipeline you'd run baseline on every PR and the full scan nightly against staging — we wire this in Lab 9.

### Auth-aware scanning

Most app risk lives behind login. Drop a session cookie / bearer token into a context file and re-run the baseline against the authenticated site tree (see ZAP docs).

---

## Troubleshooting

| Symptom | Fix |
|---|---|
| `cannot reach juice-shop` | Confirm `--network devsecops-lab` |
| `Permission denied` writing report | `chmod 777 ~/environment/devsecops-work/zap` (uid mismatch) |
| Cloud9 disk fills | Clear images: `docker image prune -a` after lab |

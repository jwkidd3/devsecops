# Course tests

Two scripts that automate the validation steps an instructor would otherwise do by hand. Both exit `0` on pass, non-zero on fail.

| Script | Where to run | Runtime | What it catches |
|---|---|---|---|
| `lint.sh` | Any dev machine (or CI) | ~3 sec | Materials drift — missing files, broken structure, schedule sums, deck overflow |
| `smoke.sh` | A Cloud9 instance with `devsecops-lab-role` attached | ~10 min (or ~2 min with `--quick`) | Runtime stack — setup script works, targets reachable, AWS round-trip, Jenkins pre-stage |

---

## `lint.sh` — local materials check

Fast structural checks. Run after editing any course material.

```bash
bash tests/lint.sh
```

Checks performed:

- All 9 module decks exist and have required structure (title, Reveal init, instructor notes, standard slide classes)
- No code block in any deck is over 14 lines (slide overflow)
- All 9 lab READMEs have title, overview, objectives, duration; labs with shell commands also have Cleanup/Troubleshooting
- Setup scripts for Lab 1 and Lab 8 exist and are executable
- README schedule references all 9 modules + 9 labs
- Lab READMEs use the `<your-name>` placeholder (no hard-coded student names)
- Lab 8 AWS resources are namespaced by `$YOU` (`$LG`, `$TOPIC`, `$ALARM` derive from `$YOU`)
- Schedule arithmetic sums to ~660 minutes (5.5 hr × 2 days)
- INSTRUCTOR.md covers pre-class checklist, Lab 4 solutions, Lab 9 verification, IAM role

Run this before every commit. CI-friendly — exits `1` on any failure with a list of what's wrong.

---

## `smoke.sh` — Cloud9 end-to-end

Exercises each lab's core operation on a fresh Cloud9 to confirm the runtime environment will work. **This is the instructor's pre-class dry-run** — required by the INSTRUCTOR.md checklist.

```bash
# Full run (~10 min — Trivy scan + ZAP baseline)
bash tests/smoke.sh smoke

# Quick run (~2 min — skips Trivy scan, ZAP, Jenkins build)
bash tests/smoke.sh smoke --quick
```

The single argument (`smoke` above) is the namespace suffix — same as the `<your-name>` placeholder learners use. The script reuses or re-creates `juice-shop-smoke`, `metasploitable-smoke`, etc. so it doesn't conflict with a learner's environment if you happen to run it on the same Cloud9.

What it exercises:

- **Pre-flight** — Docker reachable, IAM role attached, region detected
- **Lab 1** — `setup-cloud9.sh` runs idempotently, both targets reachable, all helper images pre-pulled
- **Lab 2** — every recon tool installed (`nmap`, `jq`, `dig`, `whois`, `openssl`)
- **Lab 4** — Trivy actually scans the Juice Shop image and reports HIGH+CRITICAL findings
- **Lab 6** — Metasploit container starts and reaches the Metasploitable target via the lab network
- **Lab 7** — ZAP baseline runs end-to-end against Juice Shop and produces a report
- **Lab 8** — full CloudWatch round-trip: create log group + stream, push events, delete (clean up after itself)
- **Lab 9** — Jenkins is running, sample repo is mounted, login page responds

What it does **not** test (by design — too brittle for a smoke):

- Pen-test exploit chains (Lab 5)
- Threat-modelling output (Lab 3 — paper exercise)
- A full Jenkins pipeline build (Lab 9 — covered by the lab itself)
- Email delivery for SNS subscriptions (network-dependent)

---

## Suggested workflow

| When | Run |
|---|---|
| After editing any course file | `bash tests/lint.sh` |
| Before delivering to a new cohort | `bash tests/smoke.sh smoke` on each prepared Cloud9 |
| Quick re-check after fixing a smoke failure | `bash tests/smoke.sh smoke --quick` |
| In CI on every commit | `bash tests/lint.sh` (smoke needs AWS + Cloud9, can't run in generic CI) |

---

## Exit codes

Both scripts exit `0` if all checks pass, `1` if any failed. Skip-marked checks (e.g. when `--quick` is used) don't count toward failure.

---

## Adding a new check

- **Lint** — append a new section to `lint.sh` following the existing pattern: `section "name"` then `ok`/`bad` per check. Keep each check < 100 ms.
- **Smoke** — append a new section. Use the `check` helper for tool/timeout-bounded checks: `check "description" <timeout-seconds> <command...>`. Avoid checks that depend on network egress to public services other than AWS APIs.

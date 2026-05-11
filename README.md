# DevSecOps

Two-day, introductory-level DevSecOps course. Audience: software developers and system administrators who want to incorporate security practices, tools, and culture into their development workflows.

## Course outcomes

By the end of the course, participants will be able to:

- Define DevSecOps — what it is, its goals, and how programs fail
- Walk through the DevSecOps lifecycle and the shared-responsibility model
- Identify and apply the core tools used to embed security into a delivery pipeline

## Schedule

Each day runs **9:00–4:00**, with lunch 12:00–1:00 and two 15-minute breaks.
Net working time: **5.5 hrs/day = 11 hrs total**.

### Day 1 — Foundations & threat thinking

| Time | Slot |
|---|---|
| 9:00 – 9:15 | Welcome, intros, course logistics |
| 9:15 – 10:30 | **Module 1** *What is DevSecOps?* (45) + **Lab 1** sandbox setup (30) |
| 10:30 – 10:45 | Break |
| 10:45 – 12:00 | **Module 2** *Thinking like a hacker* (45) + **Lab 2** recon (30) |
| 12:00 – 1:00 | **Lunch** |
| 1:00 – 1:25 | **Module 3** *App vs Infrastructure threats* (25) |
| 1:25 – 1:45 | **Lab 3** — IaC scan with Checkov (20) |
| 1:45 – 3:00 | **Module 4** *Threat maps & STRIDE* (30) + **Lab 4** attack map (45) |
| 3:00 – 3:15 | Break |
| 3:15 – 4:00 | **Module 5** *OWASP & upstream detection* (45 — Lab 5 starts Day 2) |

### Day 2 — Testing, monitoring, automation

| Time | Slot |
|---|---|
| 9:00 – 9:15 | Day 1 recap, Q&A |
| 9:15 – 10:00 | **Lab 5** exploit & fix OWASP Top 10 (45) |
| 10:00 – 10:30 | **Module 6** *Pen testing fundamentals* (30) |
| 10:30 – 10:45 | Break |
| 10:45 – 11:30 | **Lab 6** scoped mini pen-test (45) |
| 11:30 – 12:00 | **Module 7** *Metasploit & ZAP* (30) |
| 12:00 – 1:00 | **Lunch** |
| 1:00 – 1:30 | **Lab 7** Metasploit (30) |
| 1:30 – 2:15 | **Lab 8** ZAP baseline + full scan (45) |
| 2:15 – 2:45 | **Module 8** *Monitoring (Azure → CloudWatch)* (30) |
| 2:45 – 3:00 | Break |
| 3:00 – 3:30 | **Lab 9** CloudWatch detection & alarm (30) |
| 3:30 – 4:00 | **Lab 10** capstone — Jenkins + ZAP DAST gate (30) |

> 💡 **The capstone closes the course.** Lab 10 is hands-on because Jenkins is pre-staged: the Lab 1 setup script started Jenkins on each Cloud9 in the background, so by Day 2 afternoon plugins are installed and the Jenkinsfile is scaffolded. Module 9's content is delivered as a brief verbal intro at Lab 10 start — no separate teaching slot.

## Repository layout

```
devsecops/
├── presentations/    Reveal.js single-file decks, one per module
├── labs/             One directory per hands-on lab (README + assets)
├── tests/            Automated lint + Cloud9 smoke test (see tests/README.md)
├── README.md         This file
└── INSTRUCTOR.md     Instructor-only — pacing notes, lab solutions, gotchas
```

## Validating before delivery

```bash
bash tests/lint.sh                    # ~3 sec — checks materials structure & consistency
bash tests/smoke.sh <test-name>       # ~10 min — runs on a Cloud9 to verify runtime
```

`smoke.sh` is the dry-run required by `INSTRUCTOR.md`'s pre-class checklist. See `tests/README.md` for full details.

## Required environment

- **AWS Cloud9** environment, one per learner, in the shared training account
  - Instance type: `m5.large` (Amazon Linux 2023, SSH connection)
  - Each learner names their environment `devsecops-lab-<your-name>` and creates it themselves in Lab 1
  - IAM role `devsecops-lab-role` attached for CloudWatch / SNS access in Lab 9
- Docker (already installed on Cloud9 AMIs) — runs targets, scanners, Jenkins
- An email address each learner can receive at (Lab 9 SNS subscription)
- Course materials cloned to `~/environment/devsecops/` inside Cloud9

The Lab 1 setup script installs everything else (`nmap`, `jq`, ZAP image, Metasploit image, Trivy image) and starts the targets.

## Instructor pre-work

Before learners sign in:

1. Create or refresh the shared training account; provide sign-in URL + per-learner credentials.
2. Create the IAM role `devsecops-lab-role` (trust: EC2 service) and attach AWS-managed policies:
   - `CloudWatchLogsFullAccess` (Lab 9 log group + metric filter)
   - `CloudWatchFullAccessV2` (Lab 9 alarm)
   - `AmazonSNSFullAccess` (Lab 9 topic + subscription)
   Scope tighter for production training accounts, but those three managed policies are sufficient.
3. Confirm the account's Cloud9 service quota covers one environment per learner.
4. Distribute these materials (e.g. push to a private repo learners can clone in Cloud9).

## Notes for instructors

- All labs target intentionally vulnerable applications (OWASP Juice Shop, Metasploitable) running **inside each learner's own Cloud9 instance** — they are isolated to that EC2's Docker network and unreachable from outside. Never run these tools against production systems or systems you do not own / have written permission to test.
- Use the on-screen timer for breaks (~10 min every 75 min, lunch midday).
- Pair learners 2-by-2 for the threat-modeling and pen-testing labs — discussion adds more than solo work.
- Module 8 teaches Azure Monitor concepts (per outline) and Lab 9 implements them on **AWS CloudWatch** because the lab account is AWS. The deck includes a concept-mapping slide.

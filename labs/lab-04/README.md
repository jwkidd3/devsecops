# Lab 4: Exploit & Fix OWASP Top 10
### Hands-on with three categories on OWASP Juice Shop
**DevSecOps — Module 5 of 9**

---

## Lab overview

### Objectives

- Find and exploit a **broken access control (A01)** issue
- Find and exploit an **injection (A03)** issue
- Run a **software-composition (SCA) scan** to find vulnerable dependencies (A06)
- Map each finding to its OWASP Top 10 category and propose a fix

### Prerequisites

- Lab 1 complete; Juice Shop running on your Cloud9 instance

> ⏱ **Duration:** ~45 minutes
> 👥 **Pair:** Yes

---

## Setup

Open Juice Shop in a browser via the Cloud9 preview menu (**Preview → Preview Running Application**) — or use the direct URL the instructor provided.

Find the score board (it's hidden by design) — open DevTools → look at the bundled JS to discover the path. Once found, bookmark it; it tracks which challenges you've solved.

> 💡 No spoilers below — we'll point you at categories, not solutions.

---

## Part 1: Broken access control (A01)

### Challenge: View someone else's basket

Juice Shop assigns each user a basket with a numeric ID. The web UI only ever shows you your own basket. Can you see someone else's?

**Steps:**

1. Register a new user; log in.
2. Add an item to your basket.
3. DevTools → Network → reload your basket. Find the API call returning basket contents (look in `/rest/` or `/api/`).
4. Note the basket ID in the URL or path.
5. Try changing it. What happens?

### Challenge: Become an admin

Juice Shop has an `/api/Users/` endpoint. Existing users include a customer (`jim@juice-sh.op`) and an admin (`admin@juice-sh.op`).

**Steps:**

1. Look at how the registration request is shaped.
2. What if you add an extra field — say `role: admin` — to the request body? Use DevTools "edit and resend," or `curl` from the Cloud9 terminal.

### Capture for the report

For each finding:
- The exact request that worked
- The response that proved success
- The OWASP category (A01)
- A one-line fix

---

## Part 2: Injection (A03)

### Challenge: SQL injection on login

The Juice Shop login takes an email and a password. The back-end (deliberately, for training) builds a SQL query by string concatenation.

**Steps:**

1. Open the login form. Try logging in normally — capture the request in DevTools.
2. Try classic payloads in the email field (`' OR 1=1 --`).
3. Try logging in as admin without knowing the password.

> ✅ **Checkpoint:** you log in as a user whose password you don't know.

### Challenge: Reflected XSS

Try rendering JavaScript via a search query.

**Steps:**

1. Use the search bar at the top of Juice Shop.
2. Try simple payloads like `<iframe src="javascript:alert(1)">` (modern browsers may sanitise some — try variants).
3. When the alert pops, you've demonstrated reflected XSS.

### Capture for the report

- The exact payload that worked
- A screenshot or pasted response showing impact
- The OWASP category (A03)
- A one-line fix (parameterised queries; output encoding)

---

## Part 3: Vulnerable dependencies (A06)

We'll point Trivy at the Juice Shop image to find third-party CVEs. Run from the Cloud9 terminal:

```bash
mkdir -p ~/environment/devsecops-work

# Human-readable summary first
docker run --rm \
  -v /var/run/docker.sock:/var/run/docker.sock \
  aquasec/trivy:latest \
  image --severity HIGH,CRITICAL bkimminich/juice-shop:latest

# JSON for the report
docker run --rm \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v $HOME/environment/devsecops-work:/work \
  aquasec/trivy:latest \
  image --severity HIGH,CRITICAL \
        --format json \
        --output /work/juice-shop-trivy.json \
        bkimminich/juice-shop:latest
```

Inspect the output. Capture:

- Total HIGH+CRITICAL count
- Top 3 most-cited packages
- The OS/distro layer they live in (Alpine? Node base image?)

> 💡 Juice Shop is intentionally vulnerable — expect dozens of findings. The exercise is reading the report, not fixing them all.

---

## Part 4: Findings report

Save `~/environment/devsecops-work/juice-shop-findings.md`:

```markdown
# Juice Shop findings — DevSecOps Lab 4

**Tester:** <your name>
**Date:** <today>

## Finding 1 — Broken access control: view another user's basket
- **Category:** A01:2021 — Broken Access Control
- **Repro:** GET /rest/basket/<other-id> with my session token
- **Evidence:** <pasted response>
- **Fix:** server must verify the basket belongs to the authenticated user

## Finding 2 — SQL injection: login bypass
- **Category:** A03:2021 — Injection
- **Repro:** POST /rest/user/login with email = `' OR 1=1 --`
- **Evidence:** <pasted token / response>
- **Fix:** parameterised query; bcrypt-compared password

## Finding 3 — Reflected XSS in search
- **Category:** A03:2021 — Injection
- **Repro:** /#/search?q=<payload>
- **Evidence:** screenshot
- **Fix:** context-aware output encoding; CSP

## Finding 4 — Vulnerable dependencies (A06)
- HIGH+CRITICAL count: ###
- Top packages: ...
- **Fix:** upgrade base image; pin and patch transitive deps; SCA in CI
```

> ✅ **Checkpoint:** the report covers at least one finding from each of A01, A03, and A06.

---

## Cleanup

Nothing to clean up. If you "broke" Juice Shop during exploitation:

```bash
docker rm -f juice-shop-<your-name>
bash ~/environment/devsecops/labs/lab-01/scripts/setup-cloud9.sh <your-name>
```

---

## Stretch goals (optional)

- Pick **one** vulnerable dependency from Trivy's output and read its CVE description
- Find a third Top 10 category not covered above (A02 cryptographic failure is fun in Juice Shop)
- Run the same Trivy scan against a clean `node:20-alpine` image — compare counts

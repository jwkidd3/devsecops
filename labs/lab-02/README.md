# Lab 2: Reconnaissance Basics
### Passive and active recon from your Cloud9 environment
**DevSecOps — Module 2 of 9**

---

## Lab overview

### Objectives

- Practice **passive reconnaissance** with public information sources
- Practice **active reconnaissance** with `nmap` against the lab targets
- Banner-grab and tech-stack-fingerprint OWASP Juice Shop
- Capture findings in a one-page recon report

### Prerequisites

- Lab 1 complete; targets running (`docker ps` shows `juice-shop-<your-name>` and `metasploitable-<your-name>`)
- `~/devsecops-lab-env.md` exists with your Metasploitable IP

> ⏱ **Duration:** ~30 minutes
> 👥 **Pair:** Yes — split passive and active work

---

## Authorisation note

Both targets live on the `devsecops-lab` Docker network on **your** Cloud9 instance. **Do not** run any of these techniques against systems you do not own or have written permission to test — including other students' Cloud9 instances.

---

## Part A: Passive reconnaissance

These exercises use real external services. The goal: see how much you can learn without sending a single packet to the target.

Pick a real, well-known domain you have permission to research (your own organisation's public site is fine).

### A1. WHOIS

```bash
whois example.com | head -50
```

Capture: registrar, registrant org (often redacted), creation date, name servers.

### A2. DNS

```bash
dig +short example.com A
dig +short example.com MX
dig +short example.com TXT
dig +short _dmarc.example.com TXT
```

Capture: MX provider, SPF/DMARC records, anything unusual in TXT.

### A3. Certificate transparency

In a browser tab, open <https://crt.sh/?q=example.com>. Note every subdomain ever issued a public certificate. Flag any obviously internal-sounding names (`jenkins`, `staging`, `internal`).

### A4. Search engines

In a browser:
- `site:example.com filetype:pdf`
- `site:example.com inurl:admin`
- `"example.com" "confidential"`

> 🎯 **Discussion:** What's the most "interesting" thing you'd flag if you were the attacker?

---

## Part B: Active reconnaissance — `nmap`

> 📋 Pull the Metasploitable IP from `~/devsecops-lab-env.md`.

```bash
# Load it as an env var for convenience
TARGET_IP=$(grep "Metasploitable IP" ~/devsecops-lab-env.md | awk '{print $NF}')
echo "Target: $TARGET_IP"

# Quick top-100 ports
nmap -Pn -F $TARGET_IP

# Service & version detection on common ports
nmap -Pn -sV -p 21,22,23,25,80,139,445,3306,5900 $TARGET_IP

# Default scripts (safe-ish) for richer info
nmap -Pn -sC -sV -p 21,22,80 $TARGET_IP

# Save to a file
mkdir -p ~/environment/devsecops-work
nmap -Pn -sV -oN ~/environment/devsecops-work/recon-metasploitable.txt $TARGET_IP
```

Capture: open ports, service banners, software versions.

---

## Part C: Web fingerprinting Juice Shop

```bash
# HTTP response headers
curl -sI http://localhost:3000 | tee ~/environment/devsecops-work/juice-shop-headers.txt

# Robots / common files
curl -s  http://localhost:3000/robots.txt
curl -sI http://localhost:3000/ftp
```

Open Juice Shop via Cloud9 preview (or the URL the instructor provided). Open browser DevTools → Network → reload. Capture:

- Server header (or its absence)
- Frameworks visible in JS bundles (`angular`, `vue`, `react`)
- Visible API base path (`/api/`, `/rest/`)
- Cookies set on first response

---

## Part D: Recon report

Save `~/environment/devsecops-work/recon-report.md`:

```markdown
# Recon report — DevSecOps Lab 2

**Tester:** <your name>
**Date:** <today>
**Scope:** Metasploitable & Juice Shop on the `devsecops-lab` network of Cloud9 `<your-name>`

## Passive findings
- ... (from Part A)

## Active findings — Metasploitable
| Port | Service | Version | Note |
|------|---------|---------|------|
| 21   | vsftpd  | 2.3.4   | Famous backdoor version |
| ...  | ...     | ...     | ... |

## Active findings — Juice Shop
- Server header: ...
- Visible JS framework: ...
- Interesting endpoints: ...

## Top 3 things an attacker would try first
1. ...
2. ...
3. ...
```

> ✅ **Checkpoint:** the report is saved. You'll re-use it as input for Lab 6.

---

## Cleanup

Nothing to clean up — targets stay running.

---

## Troubleshooting

| Symptom | Cause / fix |
|---|---|
| `nmap: command not found` | Re-run the Lab 1 setup script |
| `dig` returns nothing | Try `getent hosts example.com` |
| `crt.sh` slow | Use <https://search.censys.io> instead |
| `nmap` against `localhost:3000` is empty | Use the **container** IP or hostname `juice-shop` from inside docker-network |

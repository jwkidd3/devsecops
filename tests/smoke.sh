#!/usr/bin/env bash
# DevSecOps course — Cloud9 smoke test
#
# Run this on a fresh AWS Cloud9 instance to verify the entire course
# environment will work for learners. Exercises each lab's core operations
# end-to-end. Should be the instructor's pre-class dry-run.
#
# Usage:  bash tests/smoke.sh <test-name> [--quick]
#         <test-name> — namespace suffix (e.g. "smoke")
#         --quick     — skip long-running checks (Trivy scan, ZAP baseline)
#
# Pre-reqs:
#   - Cloud9 environment with devsecops-lab-role attached
#   - aws sts get-caller-identity returns the role (Lab 1 step 2 done)

set -uo pipefail

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <test-name> [--quick]"
  exit 2
fi
YOU="$1"
QUICK=0
[[ "${2:-}" == "--quick" ]] && QUICK=1

# Resolve repo root (parent of tests/)
ROOT="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"

# ---------------------------------------------------------------------------
# Output helpers
# ---------------------------------------------------------------------------
PASS=0; FAIL=0; SKIP=0
if [[ -t 1 ]]; then
  C_OK=$'\033[1;32m'; C_BAD=$'\033[1;31m'; C_DIM=$'\033[0;90m'; C_OFF=$'\033[0m'
else
  C_OK=""; C_BAD=""; C_DIM=""; C_OFF=""
fi

ok()   { echo "${C_OK}PASS${C_OFF}  $*"; PASS=$((PASS+1)); }
bad()  { echo "${C_BAD}FAIL${C_OFF}  $*"; FAIL=$((FAIL+1)); }
skip() { echo "${C_DIM}SKIP${C_OFF}  $*"; SKIP=$((SKIP+1)); }
note() { echo "${C_DIM}---${C_OFF}   $*"; }

section() { echo; echo "== $* =="; }

# Portable timeout: GNU `timeout`, then `gtimeout` (Mac+coreutils), else passthrough.
if command -v timeout >/dev/null 2>&1; then
  _timeout() { timeout "$@"; }
elif command -v gtimeout >/dev/null 2>&1; then
  _timeout() { gtimeout "$@"; }
else
  _timeout() { shift; "$@"; }   # no timeout binary; run unbounded
fi

# Run a check with a timeout. Args: <description> <timeout-seconds> <command...>
check() {
  local desc="$1" t="$2"; shift 2
  if _timeout "$t" "$@" >/dev/null 2>&1; then
    ok "$desc"
  else
    bad "$desc"
  fi
}

# ---------------------------------------------------------------------------
# Pre-flight
# ---------------------------------------------------------------------------
section "Pre-flight (Cloud9 + IAM)"

if ! command -v docker >/dev/null 2>&1; then
  bad "docker not installed — Cloud9 should have it; run setup script first"
  exit 1
fi
ok "docker is installed"

if ! docker ps >/dev/null 2>&1; then
  bad "docker daemon not reachable — try 'sudo systemctl start docker'"
  exit 1
fi
ok "docker daemon reachable"

# IAM role check — required for Lab 9
if aws sts get-caller-identity >/dev/null 2>&1; then
  arn=$(aws sts get-caller-identity --query Arn --output text)
  if [[ "$arn" == *"devsecops-lab-role"* ]]; then
    ok "IAM role devsecops-lab-role is attached"
  else
    bad "wrong identity attached: $arn (expected devsecops-lab-role)"
  fi
else
  bad "aws sts get-caller-identity failed — Lab 1 step 2 not complete"
fi

# Region detection (Lab 9 uses this) — handle IMDSv2 + fall back to IMDSv1
REGION=""
IMDS_TOKEN=$(curl -s --max-time 3 -X PUT "http://169.254.169.254/latest/api/token" \
             -H "X-aws-ec2-metadata-token-ttl-seconds: 60" 2>/dev/null)
if [[ -n "$IMDS_TOKEN" ]]; then
  REGION=$(curl -s --max-time 3 -H "X-aws-ec2-metadata-token: $IMDS_TOKEN" \
           http://169.254.169.254/latest/dynamic/instance-identity/document 2>/dev/null \
           | jq -r .region 2>/dev/null)
fi
if [[ -z "$REGION" || "$REGION" == "null" ]]; then
  REGION=$(curl -s --max-time 3 http://169.254.169.254/latest/dynamic/instance-identity/document 2>/dev/null \
           | jq -r .region 2>/dev/null)
fi
if [[ -n "$REGION" && "$REGION" != "null" ]]; then
  ok "EC2 region detected: $REGION"
else
  bad "could not detect region from IMDS"
fi

# ---------------------------------------------------------------------------
# Lab 1 — setup-cloud9.sh idempotent re-run
# ---------------------------------------------------------------------------
section "Lab 1 — setup script & targets"

SETUP="$ROOT/labs/lab-01/scripts/setup-cloud9.sh"
if [[ ! -x "$SETUP" ]]; then
  bad "setup script not found or not executable at $SETUP"
else
  ok "setup script exists & executable"

  note "Running setup-cloud9.sh '$YOU' (idempotent — safe to re-run)..."
  if bash "$SETUP" "$YOU" >/tmp/setup-$$.log 2>&1; then
    ok "setup-cloud9.sh completed without error"
  else
    bad "setup-cloud9.sh failed — see /tmp/setup-$$.log"
    tail -10 /tmp/setup-$$.log | sed 's/^/     /'
  fi
fi

# Targets reachable
check "Juice Shop responds on :3000"             10 curl -sf http://localhost:3000
check "Juice Shop container running"              5 docker ps --filter name=juice-shop-${YOU} --filter status=running --quiet
check "Metasploitable container running"          5 docker ps --filter name=metasploitable-${YOU} --filter status=running --quiet
check "devsecops-lab network exists"              5 docker network inspect devsecops-lab

# Try Go template first; fall back to jq query against full inspect output
META_IP=$(docker inspect "metasploitable-${YOU}" \
  --format "{{ (index .NetworkSettings.Networks \"devsecops-lab\").IPAddress }}" 2>/dev/null)
if [[ -z "$META_IP" || "$META_IP" == "<no value>" ]]; then
  META_IP=$(docker inspect "metasploitable-${YOU}" 2>/dev/null \
            | jq -r '.[0].NetworkSettings.Networks["devsecops-lab"].IPAddress // .[0].NetworkSettings.Networks | to_entries[0].value.IPAddress // ""' 2>/dev/null)
fi
if [[ -n "$META_IP" ]]; then
  ok "Metasploitable IP: $META_IP"
  check "Metasploitable port 21 (FTP) open"       10 nmap -Pn -p 21 --open "$META_IP" --max-retries 1
else
  bad "could not read Metasploitable IP — try: docker inspect metasploitable-${YOU} --format '{{json .NetworkSettings.Networks}}'"
fi

# Helper images pre-pulled
for img in aquasec/trivy:latest \
           metasploitframework/metasploit-framework:latest \
           ghcr.io/zaproxy/zaproxy:stable \
           jenkins/jenkins:lts-jdk17 \
           returntocorp/semgrep:latest; do
  check "image present: $img"                      5 docker image inspect "$img"
done

# ---------------------------------------------------------------------------
# Lab 2 — recon tools work
# ---------------------------------------------------------------------------
section "Lab 2 — recon tools"

check "nmap installed"        3 nmap --version
check "jq installed"          3 jq --version
check "dig installed"         3 dig -v
check "whois installed"       3 command -v whois
check "openssl installed"     3 openssl version

# ---------------------------------------------------------------------------
# Lab 5 — Trivy can scan Juice Shop image
# ---------------------------------------------------------------------------
section "Lab 5 — Trivy SCA"

if (( QUICK )); then
  skip "Lab 5 Trivy scan (--quick)"
else
  note "Trivy DB download + scan (~60-90 sec) ..."
  if _timeout 180 docker run --rm \
        -v /var/run/docker.sock:/var/run/docker.sock \
        aquasec/trivy:latest \
        image --severity HIGH,CRITICAL --quiet --format json \
              bkimminich/juice-shop:latest >/tmp/trivy-$$.json 2>/dev/null; then
    count=$(jq '[.Results[]?.Vulnerabilities // []] | flatten | length' /tmp/trivy-$$.json 2>/dev/null || echo 0)
    if (( count > 0 )); then
      ok "Trivy scanned Juice Shop ($count HIGH+CRITICAL findings — expected)"
    else
      bad "Trivy ran but found 0 issues — unexpected; image may have changed"
    fi
  else
    bad "Trivy scan failed or timed out"
  fi
fi

# ---------------------------------------------------------------------------
# Lab 7 — Metasploit container can talk to target
# ---------------------------------------------------------------------------
section "Lab 7 — Metasploit container"

note "msfconsole startup (90-180 sec — Ruby module load is slow) ..."
# Image's entrypoint is `su-exec msf` and CMD is `./msfconsole` — when we pass
# our own args we must include the binary path explicitly.
# Combine stderr+stdout so we don't lose output buffered through stderr.
msf_out=$(_timeout 300 docker run --rm \
            --network devsecops-lab \
            metasploitframework/metasploit-framework:latest \
            ./msfconsole -q -x "ping -c 1 metasploitable; exit" 2>&1)
if echo "$msf_out" | grep -q "1 packets transmitted"; then
  ok "msfconsole container reaches metasploitable"
elif echo "$msf_out" | grep -qiE "Framework:|metasploit"; then
  ok "msfconsole starts (network reach to metasploitable not verified)"
else
  bad "msfconsole failed — last 15 lines of output:"
  echo "$msf_out" | tail -15 | sed 's/^/     /'
fi

# ---------------------------------------------------------------------------
# Lab 8 — ZAP baseline runs
# ---------------------------------------------------------------------------
section "Lab 8 — ZAP baseline"

if (( QUICK )); then
  skip "Lab 8 ZAP baseline (--quick)"
else
  note "ZAP baseline against Juice Shop (~3 min) ..."
  WORK=$(mktemp -d)
  chmod 777 "$WORK"
  if _timeout 300 docker run --rm \
        --network devsecops-lab \
        -v "$WORK:/zap/wrk:rw" \
        ghcr.io/zaproxy/zaproxy:stable \
        zap-baseline.py -t http://juice-shop:3000 \
                        -J zap-baseline.json -I >/dev/null 2>&1; then
    if [[ -s "$WORK/zap-baseline.json" ]]; then
      ok "ZAP baseline produced report"
    else
      bad "ZAP ran but report missing"
    fi
  else
    bad "ZAP baseline failed or timed out"
  fi
  rm -rf "$WORK"
fi

# ---------------------------------------------------------------------------
# Lab 9 — AWS / CloudWatch round-trip
# ---------------------------------------------------------------------------
section "Lab 9 — CloudWatch round-trip"

LG="/devsecops-lab/${YOU}-smoke/signin"
LS="events"

# Create
if aws logs create-log-group --log-group-name "$LG" >/dev/null 2>&1 \
   || aws logs describe-log-groups --log-group-name-prefix "$LG" >/dev/null 2>&1; then
  ok "CloudWatch log group create/exists"
else
  bad "could not create CloudWatch log group"
fi

if aws logs create-log-stream --log-group-name "$LG" --log-stream-name "$LS" >/dev/null 2>&1 \
   || aws logs describe-log-streams --log-group-name "$LG" --log-stream-name-prefix "$LS" >/dev/null 2>&1; then
  ok "CloudWatch log stream create/exists"
else
  bad "could not create CloudWatch log stream"
fi

# Push a single event using the helper script
SEND="$ROOT/labs/lab-09/scripts/send-events.sh"
if [[ -x "$SEND" ]]; then
  if bash "$SEND" "$LG" "$LS" >/dev/null 2>&1; then
    ok "send-events.sh published events"
  else
    bad "send-events.sh failed (jq-formatted PutLogEvents)"
  fi
else
  bad "send-events.sh missing or not +x"
fi

# Cleanup
aws logs delete-log-group --log-group-name "$LG" >/dev/null 2>&1 \
  && ok "CloudWatch log group deleted (cleanup)" \
  || skip "CloudWatch cleanup (manual: aws logs delete-log-group --log-group-name $LG)"

# ---------------------------------------------------------------------------
# Lab 10 — Jenkins pre-stage
# ---------------------------------------------------------------------------
section "Lab 10 — Jenkins pre-stage"

check "Jenkins container running"              5 docker ps --filter name=ds-jenkins --filter status=running --quiet

# Wait up to 60s for Jenkins to respond — first boot is slow
JENKINS_OK=0
for _ in 1 2 3 4 5 6; do
  curl -sf -o /dev/null --max-time 5 http://localhost:8081/login && { JENKINS_OK=1; break; }
  sleep 10
done
if (( JENKINS_OK )); then
  ok "Jenkins web UI on :8081"
else
  bad "Jenkins web UI on :8081 — check: docker logs ds-jenkins | tail -30"
fi

# Sample repo mounted inside Jenkins
if docker exec ds-jenkins ls /var/sample-repo/Jenkinsfile >/dev/null 2>&1; then
  ok "sample repo mounted at /var/sample-repo"
else
  bad "sample repo not mounted — try: cd ~/environment/devsecops-work/lab9/jenkins && docker compose down && bash ~/environment/devsecops/labs/lab-01/scripts/setup-cloud9.sh ${YOU}"
fi

# Jenkins admin password file readable
if docker exec ds-jenkins test -f /var/jenkins_home/secrets/initialAdminPassword 2>/dev/null; then
  ok "Jenkins admin password file present"
else
  skip "Jenkins admin password file (may already be removed if first-run wizard completed)"
fi

# Optional: kick a build via Jenkins CLI? Skipped — too brittle for a smoke test.
if (( QUICK )); then
  skip "Jenkins pipeline build (--quick)"
else
  skip "Jenkins pipeline build (manual; covered by Lab 10 itself)"
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo
echo "================================================================"
echo "  ${C_OK}${PASS} passed${C_OFF}  ·  ${C_BAD}${FAIL} failed${C_OFF}  ·  ${C_DIM}${SKIP} skipped${C_OFF}"
echo "================================================================"
if (( FAIL == 0 )); then
  echo "  Course environment is ready for learners on this Cloud9."
fi
exit $(( FAIL == 0 ? 0 : 1 ))

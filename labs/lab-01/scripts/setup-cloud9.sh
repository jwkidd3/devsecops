#!/usr/bin/env bash
# DevSecOps Lab 1 — Cloud9 setup script
#
# Usage:  bash scripts/setup-cloud9.sh <your-name>
#
# Idempotent: safe to re-run.

set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <your-name>"
  echo "  <your-name> is used to namespace your lab containers."
  exit 1
fi

YOU="$1"
NETWORK="devsecops-lab"
JUICE_NAME="juice-shop-${YOU}"
META_NAME="metasploitable-${YOU}"

log() { printf "\n\033[1;34m==> %s\033[0m\n" "$*"; }

# ---------------------------------------------------------------------------
log "1/6  Installing host tools (nmap, jq, git, openssl)"
# ---------------------------------------------------------------------------
if command -v dnf >/dev/null 2>&1; then
  sudo dnf -y install -q nmap jq git openssl >/dev/null
elif command -v yum >/dev/null 2>&1; then
  sudo yum -y install -q nmap jq git openssl >/dev/null
elif command -v apt-get >/dev/null 2>&1; then
  sudo apt-get update -qq
  sudo apt-get install -y -qq nmap jq git openssl
else
  echo "WARN: no supported package manager found; install nmap/jq manually." >&2
fi

# ---------------------------------------------------------------------------
log "2/6  Verifying Docker"
# ---------------------------------------------------------------------------
if ! command -v docker >/dev/null 2>&1; then
  echo "Docker not found. On Amazon Linux: sudo yum install -y docker && sudo systemctl start docker"
  exit 1
fi
sudo systemctl start docker 2>/dev/null || true
sudo usermod -aG docker "$USER" || true
# Pick up new group membership in this shell
if ! docker ps >/dev/null 2>&1; then
  echo "Docker daemon not reachable. You may need to log out & back in for the docker group to apply."
  echo "Or run subsequent docker commands with sudo."
fi

# ---------------------------------------------------------------------------
log "3/6  Creating isolated lab network ($NETWORK)"
# ---------------------------------------------------------------------------
docker network create --driver bridge "$NETWORK" 2>/dev/null || \
  echo "(network already exists)"

# ---------------------------------------------------------------------------
log "4/6  Pulling target images"
# ---------------------------------------------------------------------------
docker pull bkimminich/juice-shop:latest >/dev/null
docker pull tleemcjr/metasploitable2:latest >/dev/null

# ---------------------------------------------------------------------------
log "5/6  Starting Juice Shop ($JUICE_NAME)"
# ---------------------------------------------------------------------------
if [[ -n "$(docker ps -aq -f name=^${JUICE_NAME}$)" ]]; then
  docker start "$JUICE_NAME" >/dev/null
else
  docker run -d \
    --name "$JUICE_NAME" \
    --network "$NETWORK" \
    --network-alias juice-shop \
    -p 3000:3000 \
    bkimminich/juice-shop:latest >/dev/null
fi

# ---------------------------------------------------------------------------
log "6/6  Starting Metasploitable ($META_NAME)"
# ---------------------------------------------------------------------------
if [[ -n "$(docker ps -aq -f name=^${META_NAME}$)" ]]; then
  docker start "$META_NAME" >/dev/null
else
  docker run -d \
    --name "$META_NAME" \
    --network "$NETWORK" \
    --network-alias metasploitable \
    --hostname metasploitable \
    tleemcjr/metasploitable2:latest >/dev/null
fi

# ---------------------------------------------------------------------------
log "Pulling helper tool images (so labs don't pause to pull later)"
# ---------------------------------------------------------------------------
docker pull aquasec/trivy:latest >/dev/null
docker pull metasploitframework/metasploit-framework:latest >/dev/null
docker pull ghcr.io/zaproxy/zaproxy:stable >/dev/null
docker pull jenkins/jenkins:lts-jdk17 >/dev/null
docker pull returntocorp/semgrep:latest >/dev/null

# ---------------------------------------------------------------------------
log "Pre-staging Jenkins for Lab 9 capstone"
# ---------------------------------------------------------------------------
LAB9_DIR="$HOME/environment/devsecops-work/lab9"
mkdir -p "$LAB9_DIR/jenkins" "$LAB9_DIR/sample-repo"

cat > "$LAB9_DIR/jenkins/docker-compose.yml" <<'COMPOSE'
services:
  jenkins:
    image: jenkins/jenkins:lts-jdk17
    container_name: ds-jenkins
    user: root
    ports:
      - "8081:8080"
    volumes:
      - jenkins_home:/var/jenkins_home
      - /var/run/docker.sock:/var/run/docker.sock
      - ${SAMPLE_REPO_PATH}:/var/sample-repo
    networks:
      - devsecops-lab
volumes:
  jenkins_home:
networks:
  devsecops-lab:
    external: true
COMPOSE

cat > "$LAB9_DIR/sample-repo/Jenkinsfile" <<'JENKINSFILE'
pipeline {
  agent any
  options { timestamps() }
  environment { TARGET_URL = 'http://juice-shop:3000' }
  stages {
    stage('Checkout') {
      steps { checkout scm; sh 'ls -la' }
    }
    stage('SAST — Semgrep') {
      steps {
        sh '''docker run --rm -v $WORKSPACE:/src returntocorp/semgrep:latest \
              semgrep --config p/owasp-top-ten --json --output /src/semgrep-report.json /src \
              || echo "Semgrep done — continuing"'''
        archiveArtifacts artifacts: 'semgrep-report.json', allowEmptyArchive: true
      }
    }
    stage('SCA — Trivy') {
      steps {
        sh '''docker run --rm -v $WORKSPACE:/src aquasec/trivy:latest \
              fs --severity HIGH,CRITICAL --format json --output /src/trivy-fs.json /src'''
        archiveArtifacts artifacts: 'trivy-fs.json', allowEmptyArchive: true
      }
    }
    stage('DAST — ZAP baseline') {
      steps {
        sh '''docker run --rm --network devsecops-lab \
              -v $WORKSPACE:/zap/wrk:rw ghcr.io/zaproxy/zaproxy:stable \
              zap-baseline.py -t $TARGET_URL -r zap-baseline.html -J zap-baseline.json -I'''
        archiveArtifacts artifacts: 'zap-baseline.html, zap-baseline.json', allowEmptyArchive: true
      }
    }
    stage('Critical gate') {
      steps {
        sh '''HIGH=$(jq '[.site[].alerts[] | select(.riskcode | tonumber >= 3)] | length' zap-baseline.json)
              ALLOW=${ALLOWED_HIGH:-0}
              echo "High-risk findings: $HIGH (allowed: $ALLOW)"
              [ "$HIGH" -gt "$ALLOW" ] && { echo "::: gate failed"; exit 1; } || true'''
      }
    }
  }
  post { always { publishHTML target: [reportDir: '.', reportFiles: 'zap-baseline.html', reportName: 'ZAP Baseline'] } }
}
JENKINSFILE

cat > "$LAB9_DIR/sample-repo/README.md" <<'README'
# Sample app for DevSecOps Lab 9
README

# Initialize the sample repo so Jenkins can clone it
if [[ ! -d "$LAB9_DIR/sample-repo/.git" ]]; then
  ( cd "$LAB9_DIR/sample-repo" && git init -q -b main \
    && git -c user.email=lab@example.com -c user.name=Lab add . \
    && git -c user.email=lab@example.com -c user.name=Lab commit -q -m "Initial sample" )
fi

# Start Jenkins in background — plugins install will take 5-10 min asynchronously
( cd "$LAB9_DIR/jenkins" && SAMPLE_REPO_PATH="$LAB9_DIR/sample-repo" \
  docker compose up -d >/dev/null 2>&1 ) || \
  echo "WARN: jenkins compose up failed — Lab 9 will need manual start"

# Install jq + docker CLI inside Jenkins (small, runs in background)
(
  sleep 30
  docker exec -u root ds-jenkins bash -c '
    apt-get update -qq &&
    apt-get install -y -qq --no-install-recommends docker.io jq &&
    apt-get clean
  ' >/dev/null 2>&1
) &

# ---------------------------------------------------------------------------
log "Verification"
# ---------------------------------------------------------------------------
META_IP=$(docker inspect "$META_NAME" \
  --format "{{ (index .NetworkSettings.Networks \"$NETWORK\").IPAddress }}")

# Wait briefly for Jenkins to start writing its log so the password command works later
sleep 5
JENKINS_PWD_FILE="$LAB9_DIR/jenkins-admin-password.txt"
echo "(Jenkins admin password will appear after first boot — read with:)" > "$JENKINS_PWD_FILE"
echo "  docker exec ds-jenkins cat /var/jenkins_home/secrets/initialAdminPassword" >> "$JENKINS_PWD_FILE"

cat <<EOF | tee "$HOME/devsecops-lab-env.md"

## DevSecOps lab environment — saved $(date -u +%FT%TZ)

| Item                | Value                                       |
|---------------------|---------------------------------------------|
| Cloud9 user suffix  | $YOU                                        |
| Lab network         | $NETWORK                                    |
| Juice Shop name     | $JUICE_NAME                                 |
| Juice Shop URL      | http://localhost:3000                       |
| Juice Shop net-name | juice-shop  (use from same docker network)  |
| Metasploitable name | $META_NAME                                  |
| Metasploitable IP   | ${META_IP}                                  |
| Jenkins URL         | http://localhost:8081                       |
| Jenkins admin pwd   | docker exec ds-jenkins cat /var/jenkins_home/secrets/initialAdminPassword |
| Lab 9 sample repo   | $LAB9_DIR/sample-repo (mounted at /var/sample-repo in Jenkins) |

EOF

echo
echo "Verify Juice Shop:     curl -sI http://localhost:3000 | head -1"
echo "Verify Metasploitable: nmap -Pn -p 21,22,80 ${META_IP}"
echo "Verify Jenkins:        curl -sI http://localhost:8081 | head -1   (may take 60-90s on first boot)"
echo
echo "Jenkins is starting in the background — plugins install over the next ~10 minutes."
echo "By Day 2 afternoon (Lab 9), it will be ready. No further action needed today."
echo
echo "All set. Continue to Step 5 of the lab README."

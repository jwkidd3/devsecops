#!/usr/bin/env bash
# DevSecOps Lab 1 — Cloud9 setup script
#
# Usage:  bash scripts/setup-cloud9.sh <your-name>
#
# Fully idempotent. Safe to re-run after partial failure or environment drift:
# every step checks current state and either skips work or reconciles.

set -uo pipefail

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <your-name>"
  echo "  <your-name> namespaces your lab containers (e.g. 'alexk')."
  exit 1
fi

YOU="$1"
NETWORK="devsecops-lab"
JUICE_NAME="juice-shop-${YOU}"
META_NAME="metasploitable-${YOU}"
LAB9_DIR="$HOME/environment/devsecops-work/lab9"

# ---------------------------------------------------------------------------
# Output helpers + failure tracking
# ---------------------------------------------------------------------------
WARN_COUNT=0

log()  { printf "\n\033[1;34m==> %s\033[0m\n" "$*"; }
ok()   { printf "    \033[0;32m✓\033[0m %s\n" "$*"; }
skip() { printf "    \033[0;90m·\033[0m %s\n" "$*"; }
warn() { printf "    \033[1;33m!\033[0m %s\n" "$*"; WARN_COUNT=$((WARN_COUNT + 1)); }

# ---------------------------------------------------------------------------
log "1/7  Host tools (nmap, jq, git, openssl)"
# ---------------------------------------------------------------------------
need_install=()
for t in nmap jq git openssl whois; do
  command -v "$t" >/dev/null 2>&1 || need_install+=("$t")
done

if (( ${#need_install[@]} == 0 )); then
  skip "all tools already installed"
else
  echo "    installing: ${need_install[*]}"
  if command -v dnf >/dev/null 2>&1; then
    sudo dnf -y install -q "${need_install[@]}" >/dev/null && ok "installed via dnf" || warn "dnf install hit errors"
  elif command -v yum >/dev/null 2>&1; then
    sudo yum -y install -q "${need_install[@]}" >/dev/null && ok "installed via yum" || warn "yum install hit errors"
  elif command -v apt-get >/dev/null 2>&1; then
    sudo apt-get update -qq && sudo apt-get install -y -qq "${need_install[@]}" \
      && ok "installed via apt-get" || warn "apt-get install hit errors"
  else
    warn "no supported package manager found; install ${need_install[*]} manually"
  fi
fi

TARGET_GB=100  # generous headroom for image pulls + Jenkins workspace + scan outputs

# ---------------------------------------------------------------------------
log "1b   Resize Cloud9 EBS volume to ${TARGET_GB} GB if smaller"
# ---------------------------------------------------------------------------
# Get current root filesystem size in GB
current_gb=$(df --output=size -BG / 2>/dev/null | tail -1 | tr -dc '0-9' || echo 0)
if (( current_gb >= TARGET_GB - 2 )); then   # tolerate ~2 GB FS overhead
  skip "root volume is already ${current_gb} GB"
else
  echo "    root volume is ${current_gb} GB — growing to ${TARGET_GB} GB"

  # IMDSv2 token (Cloud9 EC2 enforces v2)
  imds_token=$(curl -s --max-time 3 -X PUT http://169.254.169.254/latest/api/token \
               -H "X-aws-ec2-metadata-token-ttl-seconds: 60" 2>/dev/null)
  if [[ -z "$imds_token" ]]; then
    warn "could not get IMDS token; resize skipped (do this manually via EC2 console if needed)"
  else
    instance_id=$(curl -s --max-time 3 -H "X-aws-ec2-metadata-token: $imds_token" \
                  http://169.254.169.254/latest/meta-data/instance-id)
    volume_id=$(aws ec2 describe-instances --instance-id "$instance_id" \
                --query "Reservations[0].Instances[0].BlockDeviceMappings[0].Ebs.VolumeId" \
                --output text 2>/dev/null)

    if [[ -z "$volume_id" || "$volume_id" == "None" ]]; then
      warn "could not look up volume ID — IAM role probably lacks ec2:DescribeInstances"
      warn "ask your instructor to grow the volume manually (EC2 → Volumes → Modify volume → ${TARGET_GB})"
    else
      if aws ec2 modify-volume --volume-id "$volume_id" --size "$TARGET_GB" >/dev/null 2>&1; then
        echo "    waiting for resize to start optimizing..."
        for _ in 1 2 3 4 5 6 7 8 9 10 11 12; do
          state=$(aws ec2 describe-volumes-modifications --volume-id "$volume_id" \
                  --query "VolumesModifications[0].ModificationState" --output text 2>/dev/null)
          [[ "$state" == "optimizing" || "$state" == "completed" ]] && break
          sleep 5
        done

        # Pick the right block device + grow partition + filesystem
        root_part=$(findmnt -n -o SOURCE /)
        root_disk=$(lsblk -no PKNAME "$root_part" 2>/dev/null | head -1)
        part_num=$(echo "$root_part" | sed -E 's,^.*/[a-zA-Z]+,,')

        if [[ -n "$root_disk" && -n "$part_num" ]]; then
          # Force the kernel to re-read the new EBS size before resizing the partition.
          # Without this, growpart still sees the old disk size on some AMIs.
          echo 1 | sudo tee "/sys/class/block/${root_disk}/device/rescan" >/dev/null 2>&1 || true
          sudo partprobe "/dev/$root_disk" >/dev/null 2>&1 || true
          sleep 3

          sudo growpart "/dev/$root_disk" "$part_num" >/dev/null 2>&1 || true
          fs_type=$(findmnt -n -o FSTYPE /)
          if [[ "$fs_type" == "xfs" ]]; then
            sudo xfs_growfs -d / >/dev/null 2>&1 || true
          else
            sudo resize2fs "$root_part" >/dev/null 2>&1 || true
          fi
          new_gb=$(df --output=size -BG / 2>/dev/null | tail -1 | tr -dc '0-9' || echo 0)
          if (( new_gb >= TARGET_GB - 2 )); then
            ok "root volume now ${new_gb} GB"
          else
            warn "volume API resize succeeded but kernel still shows ${new_gb} GB"
            echo
            echo "    +-------------------------------------------------------------+"
            echo "    | REBOOT REQUIRED                                             |"
            echo "    | EBS is now ${TARGET_GB} GB at the API level, but the kernel needs   |"
            echo "    | a reboot to see it. Run this in the Cloud9 terminal:        |"
            echo "    |                                                             |"
            echo "    |     sudo reboot                                             |"
            echo "    |                                                             |"
            echo "    | Cloud9 will reconnect automatically after ~30 sec.          |"
            echo "    | Then re-run this script — it will skip the resize step.     |"
            echo "    +-------------------------------------------------------------+"
            echo
            exit 0
          fi
        else
          warn "could not detect root device; reboot the EC2 to apply the resize"
        fi
      else
        warn "modify-volume call failed — IAM role probably lacks ec2:ModifyVolume"
        warn "ask your instructor to grow the volume manually"
      fi
    fi
  fi
fi

# ---------------------------------------------------------------------------
log "2/7  Docker + compose plugin"
# ---------------------------------------------------------------------------
if ! command -v docker >/dev/null 2>&1; then
  warn "docker not found — Cloud9 should have it preinstalled"
else
  sudo systemctl start docker 2>/dev/null || true
  sudo usermod -aG docker "$USER" 2>/dev/null || true
  if docker ps >/dev/null 2>&1; then
    ok "docker daemon reachable"
  else
    warn "docker daemon not reachable — open a fresh terminal or use sudo"
  fi

  # docker compose v2 plugin — Cloud9 doesn't ship with it
  if docker compose version >/dev/null 2>&1; then
    skip "docker compose plugin already installed"
  else
    echo "    installing docker compose v2 plugin"
    # Try the package manager first (cleaner)
    installed=0
    if command -v dnf >/dev/null 2>&1; then
      sudo dnf install -y -q docker-compose-plugin >/dev/null 2>&1 \
        && docker compose version >/dev/null 2>&1 && installed=1
    fi
    # Fall back to direct plugin binary download
    if (( installed == 0 )); then
      sudo mkdir -p /usr/local/lib/docker/cli-plugins
      arch=$(uname -m)
      url="https://github.com/docker/compose/releases/latest/download/docker-compose-linux-${arch}"
      if sudo curl -fsSL "$url" -o /usr/local/lib/docker/cli-plugins/docker-compose 2>/dev/null \
         && sudo chmod +x /usr/local/lib/docker/cli-plugins/docker-compose; then
        installed=1
      fi
    fi
    if docker compose version >/dev/null 2>&1; then
      ok "docker compose installed"
    else
      warn "could not install docker compose — Lab 10 will fail until installed manually"
    fi
  fi
fi

# ---------------------------------------------------------------------------
log "3/7  Lab network ($NETWORK)"
# ---------------------------------------------------------------------------
if docker network inspect "$NETWORK" >/dev/null 2>&1; then
  skip "network exists"
else
  docker network create --driver bridge "$NETWORK" >/dev/null 2>&1 \
    && ok "network created" \
    || warn "could not create network"
fi

# ---------------------------------------------------------------------------
# Helper: pull an image only if missing; report what happened
# ---------------------------------------------------------------------------
pull_if_missing() {
  local img="$1"
  if docker image inspect "$img" >/dev/null 2>&1; then
    skip "$img already pulled"
  else
    if docker pull "$img" >/dev/null 2>&1; then
      ok "pulled $img"
    else
      warn "could not pull $img — re-run setup after fixing (often disk or rate limit)"
    fi
  fi
}

# ---------------------------------------------------------------------------
log "4/7  Target images"
# ---------------------------------------------------------------------------
pull_if_missing "bkimminich/juice-shop:latest"
pull_if_missing "strm/metasploitable2:latest"

# ---------------------------------------------------------------------------
# Helper: ensure a container is running with the given name on the lab network
# ---------------------------------------------------------------------------
ensure_running() {
  local name="$1"; shift
  local state
  state=$(docker inspect -f '{{.State.Status}}' "$name" 2>/dev/null || echo "missing")
  case "$state" in
    running)
      skip "$name already running"
      ;;
    exited|created|paused)
      docker start "$name" >/dev/null 2>&1 \
        && ok "started existing $name" \
        || { warn "could not start $name — recreating"; docker rm -f "$name" >/dev/null 2>&1; "$@"; }
      ;;
    *)
      "$@" && ok "created $name" || warn "could not create $name"
      ;;
  esac
}

# Free a host port if another container of a known prefix is holding it
free_port_if_held_by_stale() {
  local port="$1" prefix="$2" keep="$3"
  local stale
  stale=$(docker ps -a --filter "publish=${port}" --format '{{.Names}}' \
          | grep "^${prefix}" | grep -v "^${keep}$" || true)
  if [[ -n "$stale" ]]; then
    while IFS= read -r name; do
      [[ -z "$name" ]] && continue
      echo "    port $port held by stale '$name' — removing"
      docker rm -f "$name" >/dev/null 2>&1 || warn "could not remove $name"
    done <<< "$stale"
  fi
}

# ---------------------------------------------------------------------------
log "5/7  Juice Shop ($JUICE_NAME)"
# ---------------------------------------------------------------------------
free_port_if_held_by_stale 3000 "juice-shop-" "$JUICE_NAME"
ensure_running "$JUICE_NAME" \
  docker run -d \
    --name "$JUICE_NAME" \
    --network "$NETWORK" \
    --network-alias juice-shop \
    -p 3000:3000 \
    bkimminich/juice-shop:latest

# ---------------------------------------------------------------------------
log "6/7  Metasploitable ($META_NAME)"
# ---------------------------------------------------------------------------
ensure_running "$META_NAME" \
  docker run -d \
    --name "$META_NAME" \
    --network "$NETWORK" \
    --network-alias metasploitable \
    --hostname metasploitable \
    --privileged --init \
    --security-opt seccomp=unconfined \
    --security-opt apparmor=unconfined \
    strm/metasploitable2:latest

# ---------------------------------------------------------------------------
log "7/7  Helper tool images"
# ---------------------------------------------------------------------------
pull_if_missing "aquasec/trivy:latest"
pull_if_missing "metasploitframework/metasploit-framework:latest"
pull_if_missing "ghcr.io/zaproxy/zaproxy:stable"
pull_if_missing "jenkins/jenkins:lts-jdk17"
pull_if_missing "returntocorp/semgrep:latest"

# ---------------------------------------------------------------------------
log "Lab 10 scaffold (compose file + sample repo)"
# ---------------------------------------------------------------------------
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
ok "compose file written"

cat > "$LAB9_DIR/sample-repo/Jenkinsfile" <<'JENKINSFILE'
pipeline {
  agent any
  options { timestamps() }
  environment { TARGET_URL = 'http://juice-shop:3000' }
  stages {
    stage('Checkout') { steps { checkout scm; sh 'ls -la' } }
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
ok "Jenkinsfile written"

[[ -f "$LAB9_DIR/sample-repo/README.md" ]] || \
  echo "# Sample app for DevSecOps Lab 10" > "$LAB9_DIR/sample-repo/README.md"

# Initialise the sample repo if not already a git repo
if [[ ! -d "$LAB9_DIR/sample-repo/.git" ]]; then
  ( cd "$LAB9_DIR/sample-repo" && git init -q -b main \
    && git -c user.email=lab@example.com -c user.name=Lab add . \
    && git -c user.email=lab@example.com -c user.name=Lab commit -q -m "Initial sample" ) \
    && ok "git repo initialised" || warn "could not init sample repo"
else
  skip "sample repo already initialised"
fi

# ---------------------------------------------------------------------------
log "Jenkins"
# ---------------------------------------------------------------------------
# Detect config drift: if ds-jenkins exists but doesn't have the /var/sample-repo
# bind mount, tear it down so compose recreates it correctly.
if docker inspect ds-jenkins >/dev/null 2>&1; then
  if ! docker inspect ds-jenkins \
       | jq -e '.[0].Mounts[] | select(.Destination == "/var/sample-repo")' >/dev/null 2>&1; then
    echo "    Jenkins config drift detected (no /var/sample-repo mount) — recreating"
    ( cd "$LAB9_DIR/jenkins" && docker compose down >/dev/null 2>&1 ) || true
  fi
fi

# Bring Jenkins up (no-op if already running with current compose)
if ( cd "$LAB9_DIR/jenkins" && SAMPLE_REPO_PATH="$LAB9_DIR/sample-repo" \
     docker compose up -d >/dev/null 2>&1 ); then
  if docker ps --filter name=^ds-jenkins$ --filter status=running --quiet | grep -q .; then
    ok "Jenkins running on http://localhost:8081"
  else
    warn "Jenkins compose succeeded but container not running"
  fi
else
  warn "Jenkins compose up failed — see: docker compose -f $LAB9_DIR/jenkins/docker-compose.yml logs"
fi

# Install jq + docker CLI inside Jenkins (needed for the pipeline gate stage).
# Idempotent: skip if already present.
if docker exec ds-jenkins which jq >/dev/null 2>&1 \
   && docker exec ds-jenkins which docker >/dev/null 2>&1; then
  skip "jq + docker CLI already in Jenkins"
elif docker ps --filter name=^ds-jenkins$ --filter status=running --quiet | grep -q .; then
  echo "    waiting for Jenkins to be ready (up to 60s) ..."
  for _ in 1 2 3 4 5 6; do
    docker exec ds-jenkins true >/dev/null 2>&1 && break
    sleep 10
  done
  if docker exec -u root ds-jenkins bash -c '
       apt-get update -qq && \
       apt-get install -y -qq --no-install-recommends docker.io jq && \
       apt-get clean
     ' >/dev/null 2>&1; then
    ok "installed jq + docker.io inside Jenkins"
  else
    warn "could not install jq+docker inside Jenkins (re-run setup later)"
  fi
fi

# ---------------------------------------------------------------------------
log "Verification & environment notes"
# ---------------------------------------------------------------------------
META_IP=$(docker inspect "$META_NAME" \
  --format "{{ (index .NetworkSettings.Networks \"$NETWORK\").IPAddress }}" 2>/dev/null)
if [[ -z "$META_IP" || "$META_IP" == "<no value>" ]]; then
  META_IP=$(docker inspect "$META_NAME" 2>/dev/null \
            | jq -r '.[0].NetworkSettings.Networks["devsecops-lab"].IPAddress // ""')
fi
META_IP="${META_IP:-<unavailable — restart $META_NAME>}"

cat > "$HOME/devsecops-lab-env.md" <<EOF

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
| Lab 10 sample repo   | $LAB9_DIR/sample-repo (mounted at /var/sample-repo in Jenkins) |

EOF
ok "environment notes saved to ~/devsecops-lab-env.md"

# ---------------------------------------------------------------------------
echo
if (( WARN_COUNT == 0 )); then
  printf "\033[1;32mAll set.\033[0m %d warnings.\n" "$WARN_COUNT"
else
  printf "\033[1;33mFinished with %d warnings.\033[0m Re-run this script to retry skipped/failed steps.\n" "$WARN_COUNT"
fi
echo
echo "Quick verify:"
echo "  curl -sI http://localhost:3000   | head -1   # Juice Shop"
echo "  nmap -Pn -p 21,22,80 ${META_IP}              # Metasploitable"
echo "  curl -sI http://localhost:8081   | head -1   # Jenkins (60-90s on first boot)"
echo
exit 0

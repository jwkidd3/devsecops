#!/usr/bin/env bash
# DevSecOps Lab 8 — push synthetic sign-in events to CloudWatch Logs
# Usage: send-events.sh <log-group> <log-stream>

set -euo pipefail
LG="${1:?log group name required}"
LS="${2:?log stream name required}"

emit() {
  local user="$1" ip="$2" result="$3" location="$4"
  local ts=$(($(date +%s%N) / 1000000))
  jq -nc --arg u "$user" --arg ip "$ip" --arg r "$result" --arg loc "$location" --argjson ts $ts '
    {
      timestamp: $ts,
      message: ({
        UserPrincipalName: $u,
        IPAddress: $ip,
        ResultCode: $r,
        ResultDescription: (if $r == "0" then "Success" else "Invalid username or password" end),
        Location: $loc,
        AppDisplayName: "Office365"
      } | tostring)
    }
  '
}

events=$(
  {
    # 7 failures for one user — should trigger the detection
    for _ in $(seq 1 7); do emit "alex@example.com" "203.0.113.45" "50126" "DE"; done
    # 3 failures for another — below threshold, control case
    for _ in $(seq 1 3); do emit "casey@example.com" "198.51.100.7" "50126" "US"; done
    # one success — noise
    emit "alex@example.com" "203.0.113.45" "0" "DE"
  } | jq -s '.'
)

aws logs put-log-events \
  --log-group-name "$LG" \
  --log-stream-name "$LS" \
  --log-events "$events"

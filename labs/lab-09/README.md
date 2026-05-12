# Lab 9: CloudWatch Detection & Alarm
### Build a working detection rule end-to-end on AWS CloudWatch
**DevSecOps — Module 8 of 9**

---

## Lab overview

Wire up an end-to-end CloudWatch detection: push synthetic sign-in events into a log group, query them with Logs Insights, convert the pattern into a metric filter + CloudWatch Alarm, and have the alarm email you via SNS.

### Objectives

- Create a CloudWatch log group and a custom log stream
- Push synthetic sign-in events (simulating Cognito audit logs)
- Author a Logs Insights query for repeated failed sign-ins
- Convert the pattern into a metric filter + CloudWatch Alarm
- Wire the alarm to an SNS topic that emails you

### Prerequisites

- Lab 1 completed; `devsecops-lab-role` is attached and `aws sts get-caller-identity` returns the role
- Permissions in the role to use CloudWatch Logs, CloudWatch Alarms, and SNS (the instructor pre-attached these)
- An email address you can receive at

> ⏱ **Duration:** 30 min — instructor pre-creates the IAM role; cleanup is post-class
> 👥 **Pair:** No

> ⏰ **Time-saver:** create the SNS topic and confirm the subscription email **first** (Step 6), so confirmation lands while you're doing Steps 2–5.

---

## Step 1: Set environment variables

In the Cloud9 terminal:

```bash
# Use the region your Cloud9 is in (handle both IMDSv1 and IMDSv2)
TOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" \
        -H "X-aws-ec2-metadata-token-ttl-seconds: 60")
export AWS_REGION=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" \
                    http://169.254.169.254/latest/dynamic/instance-identity/document | jq -r .region)

# Namespace your resources by your name to avoid collisions in the shared account
YOU="<your-name>"     # same suffix you used in Lab 1
LG="/devsecops-lab/$YOU/signin"
LS="events"
TOPIC="devsecops-lab-${YOU}-alerts"
ALARM="repeated-failed-signins-${YOU}"
EMAIL="<your-email>"

echo "Region: $AWS_REGION  Log group: $LG"
```

> ✅ **Checkpoint:** all variables are set; `$AWS_REGION` is non-empty.

---

## Step 2: Create the log group & stream

```bash
aws logs create-log-group --log-group-name "$LG" || echo "(log group exists)"
aws logs create-log-stream --log-group-name "$LG" --log-stream-name "$LS" || echo "(stream exists)"

aws logs describe-log-groups --log-group-name-prefix "$LG"
```

> ✅ **Checkpoint:** the group is listed.

---

## Step 3: Send sample events

We'll push synthetic JSON events that mimic real sign-in audit logs. The script is included in the lab folder.

Save as `~/environment/devsecops/labs/lab-09/scripts/send-events.sh` (already there if you cloned the materials; otherwise create it):

```bash
#!/usr/bin/env bash
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
    # 7 failures for one user — should trigger
    for _ in $(seq 1 7); do emit "alex@example.com" "203.0.113.45" "50126" "DE"; done
    # 3 failures for another — below threshold
    for _ in $(seq 1 3); do emit "casey@example.com" "198.51.100.7" "50126" "US"; done
    # one success
    emit "alex@example.com" "203.0.113.45" "0" "DE"
  } | jq -s '.'
)

aws logs put-log-events \
  --log-group-name "$LG" \
  --log-stream-name "$LS" \
  --log-events "$events"
```

Run it:

```bash
chmod +x ~/environment/devsecops/labs/lab-09/scripts/send-events.sh
~/environment/devsecops/labs/lab-09/scripts/send-events.sh "$LG" "$LS"
```

> ✅ **Checkpoint:** the command returns a `nextSequenceToken` (no error).

---

## Step 4: Verify ingestion with Logs Insights

In the AWS console, open **CloudWatch → Logs Insights**. Pick your log group `/devsecops-lab/<you>/signin`.

Run:

```
fields @timestamp, @message
| sort @timestamp desc
| limit 50
```

You should see 11 rows (7 + 3 + 1).

---

## Step 5: Author the detection query

Logs Insights query — repeated failed sign-ins:

```
fields @timestamp, @message
| parse @message '"UserPrincipalName":"*"' as user
| parse @message '"ResultCode":"*"'         as resultCode
| parse @message '"IPAddress":"*"'          as ip
| filter resultCode != "0"
| stats count() as failures,
        count_distinct(ip) as ips
        by user, bin(5m)
| filter failures > 5
| sort @timestamp desc
```

Run it. Only `alex@example.com` should appear.

> ✅ **Checkpoint:** exactly the row(s) you'd want to alert on.

> 💡 Note the parallel: same logical query, different language. Logs Insights uses `filter` / `stats` where KQL uses `where` / `summarize`.

---

## Step 6: Make it an alarm with a metric filter

Logs Insights queries don't fire alarms directly. The CloudWatch pattern is **metric filter → metric → alarm**. Convert:

```bash
aws logs put-metric-filter \
  --log-group-name "$LG" \
  --filter-name "FailedSignins-${YOU}" \
  --filter-pattern '{ ($.ResultCode != "0") }' \
  --metric-transformations \
      metricName="FailedSignins-${YOU}",metricNamespace="DevSecOpsLab",metricValue=1
```

The filter emits a `1` to CloudWatch Metrics for every log event whose JSON has `ResultCode != "0"`.

Now create the alarm:

```bash
# Create SNS topic & subscribe your email
TOPIC_ARN=$(aws sns create-topic --name "$TOPIC" --query TopicArn --output text)
aws sns subscribe --topic-arn "$TOPIC_ARN" --protocol email --notification-endpoint "$EMAIL"
echo "Confirm the subscription email AWS just sent before continuing."

aws cloudwatch put-metric-alarm \
  --alarm-name "$ALARM" \
  --metric-name "FailedSignins-${YOU}" \
  --namespace "DevSecOpsLab" \
  --statistic Sum \
  --period 60 \
  --evaluation-periods 5 \
  --threshold 5 \
  --comparison-operator GreaterThanThreshold \
  --treat-missing-data notBreaching \
  --alarm-actions "$TOPIC_ARN" \
  --alarm-description "More than 5 failed sign-ins within 5 minutes (lab user $YOU)"
```

> ⚠️ **Confirm the SNS subscription email** before testing — otherwise no email lands.

---

## Step 7: Trigger the alarm

```bash
# Repeat the burst a few times to push the metric over threshold within the alarm window
for i in 1 2 3; do
  ~/environment/devsecops/labs/lab-09/scripts/send-events.sh "$LG" "$LS"
  sleep 20
done

# Watch the alarm state transition
aws cloudwatch describe-alarms \
  --alarm-names "$ALARM" \
  --query 'MetricAlarms[0].{State:StateValue,Reason:StateReason}'
```

State should move from `INSUFFICIENT_DATA` → `OK` → `ALARM`. Allow 2–5 minutes for the metric to surface (CloudWatch ingestion delay).

> ✅ **Checkpoint:** alarm is in `ALARM` state and an email arrived at the subscribed address.

---

## Step 8: Reflect

In `~/environment/devsecops-work/lab9-reflection.md`, answer:

1. What does the **SNS topic + subscription** give you that a single email destination wouldn't?
2. What's a sensible threshold for *real* sign-in data — what's the false-positive cost?
3. What other dimensions would you add (geo, ASN, app) to reduce false positives?
4. How would you adapt this query for the **impossible-travel** scenario from the module?

---

## Cleanup (do after class — costs are negligible during the day)

```bash
aws cloudwatch delete-alarms --alarm-names "$ALARM"
aws logs delete-metric-filter --log-group-name "$LG" --filter-name "FailedSignins-${YOU}"
aws sns delete-topic --topic-arn "$TOPIC_ARN"
aws logs delete-log-group --log-group-name "$LG"
```

---

## Troubleshooting

| Symptom | Fix |
|---|---|
| `AccessDenied` on `aws logs ...` | Lab 1 step 2 not complete — re-attach the role; `aws sts get-caller-identity` |
| Metric never appears | Ingestion lag is normal (1–5 min). Make sure your filter pattern matches: paste a sample event into **CloudWatch → Logs → Test pattern** |
| Alarm stays `INSUFFICIENT_DATA` | The metric filter only emits when matching events arrive — push more events |
| No email received | Check the SNS confirmation email; check spam; `aws sns list-subscriptions-by-topic --topic-arn $TOPIC_ARN` should show `Confirmed` |
| `put-log-events` rejects `nextSequenceToken` | Re-fetch token: `aws logs describe-log-streams --log-group-name $LG --log-stream-name-prefix $LS` |

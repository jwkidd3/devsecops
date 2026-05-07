# Lab 3: Build an Attack Map
### Threat-modelling a sample three-tier architecture
**DevSecOps — Module 4 of 9**

---

## Lab overview

### Objectives

- Read an architecture brief and identify trust boundaries
- Draw a Data-Flow Diagram (DFD)
- Apply STRIDE-per-element to enumerate threats
- Pick the top three threats and propose mitigations
- Walk your map for another pair and pen-test their assumptions

### Prerequisites

- Module 4 completed
- A diagramming tool — pick whichever is fastest for you. All work in a browser tab alongside Cloud9:

| Tool | Best for | Cost |
|---|---|---|
| [OWASP Threat Dragon](https://www.threatdragon.com/) | DFDs with built-in STRIDE threat suggestions per element | Free |
| [draw.io / diagrams.net](https://app.diagrams.net) | Pure DFD drawing; clean export to PNG/PDF | Free |
| [Miro](https://miro.com) | Real-time multi-person whiteboarding (pair work) | Free tier |
| [Microsoft Threat Modeling Tool](https://aka.ms/threatmodelingtool) | STRIDE-driven analysis with reporting | Free, Windows only |
| [pytm](https://github.com/izar/pytm) | Threat-models-as-code (Python) for repeat / CI use | Free |
| Whiteboard, pen & paper | Fastest for first sessions; snap a photo to upload | — |

If your pair is remote, Miro or Threat Dragon (cloud edition) are the easiest. If you're co-located, a whiteboard beats every tool for the first 30 minutes — you can always digitise after.

> ⏱ **Duration:** ~45 minutes
> 👥 **Pair:** Yes

---

## The architecture brief

You're modelling **OrderHub** — a fictional e-commerce checkout for a mid-size retailer.

```
[Customer browser]
    │  HTTPS
    ▼
[Front Door / WAF]
    │  HTTPS
    ▼
[Web app "checkout-web"]   ◄── reads from ──   [SQL "orders"]
    │  (private endpoint)
    ▼
[App "payments"] ──── HTTPS ────► [Stripe API]
    │
    ▼
[Service Bus] ──► [Function "fulfilment"] ──► [Storage Queue + Blob]

Identity: enterprise IdP for staff admin; customer accounts via consumer IdP (B2C).
Logging: cloud-native monitoring; CSPM enabled.
```

### Stated assumptions

- Front Door is the only ingress; both web/payments services have public access disabled.
- The orders database holds customer name, email, postal address, and an external `customer_id` (no card data stored locally).
- Staff admins use a separate `/admin` web app behind Conditional Access + MFA.

> 💡 The brief is intentionally cloud-agnostic. Apply your own cloud's primitives (Azure Front Door + App Service, AWS CloudFront + ECS/EKS, etc.) — STRIDE works the same way.

---

## Step 1: Draw the DFD (15 min)

Render the brief as a DFD using the five symbols from the module:

- Rectangle = external entity (customer, Stripe)
- Circle = process (each web/payments/fulfilment service)
- Two parallel lines = data store (SQL, Storage, Service Bus)
- Arrow = data flow (with a label)
- Dashed line = trust boundary

**At minimum, draw four trust boundaries:**

1. Internet ↔ Front Door
2. Front Door ↔ private network
3. Customer-facing services ↔ admin app
4. Internal cloud ↔ Stripe

Save the diagram to `~/environment/devsecops-work/orderhub-dfd.png` (or PDF). If you used a whiteboard, snap a photo and upload it to Cloud9 via the **File → Upload Local Files** menu.

---

## Step 2: STRIDE per element (20 min)

Open `~/environment/devsecops-work/orderhub-stride.md` and use this pattern for each element:

```markdown
## checkout-web (process)
- **S**poofing: customer session token theft via XSS → impersonation
- **T**ampering: cart/price tampering on the client → server should re-price
- **R**epudiation: order placement without auth log → cannot prove who ordered
- **I**nfo disclosure: stack traces leaked on 500 → mask in prod
- **D**oS: cart endpoint with no rate limit → resource exhaustion
- **E**oP: vulnerable npm dep → RCE → owns app context
```

**STRIDE-per-element cheat sheet:**

| Element type     | S | T | R | I | D | E |
|------------------|---|---|---|---|---|---|
| External entity  | ✓ |   | ✓ |   |   |   |
| Process          | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| Data store       |   | ✓ | ✓ | ✓ | ✓ |   |
| Data flow        |   | ✓ |   | ✓ | ✓ |   |

You don't need a threat in every cell — only where it actually applies. Aim for 8–12 distinct threats across the diagram.

---

## Step 3: Pick the top three (5 min)

For each top-3 threat:

| Field | Value |
|---|---|
| Threat | (one line) |
| Element | (which DFD element) |
| Likelihood | low / med / high |
| Impact | low / med / high |
| Mitigation | (1–2 lines, concrete) |
| Owner | dev / platform / both |

> 🎯 **Tip:** focus on threats whose mitigation could ship within a sprint. Output is a backlog, not a wishlist.

---

## Step 4: Cross-pair walkthrough (5 min)

Pair with another team. Take turns:

1. Walk your DFD — what's modelled, what's out of scope.
2. The other pair plays attacker — they ask "what about X?"
3. Capture any new threats you missed in `orderhub-stride.md`.

Common things attackers raise:
- "What if the WAF is bypassed via the App Service's default URL?"
- "Are dev/staging slots in scope? They share the back-end."
- "What's logged when payments hits Stripe and Stripe replies?"

---

## Deliverables

By end of lab, your `~/environment/devsecops-work/` directory has:

- `orderhub-dfd.png` (or PDF) — the diagram
- `orderhub-stride.md` — STRIDE findings with the top-3 expanded

---

## Cleanup

Nothing to clean up.

---

## Stretch goals (optional)

- Re-draw the DFD in OWASP Threat Dragon and let it auto-suggest threats per element
- Map each top-3 threat to one or more **MITRE ATT&CK** techniques
- Write the **abuse cases** that a tester would use in Lab 5 to validate your top threats

# Caudals webhooks

Each time a scheduled run is judged, Caudals sends one `POST` with a JSON body to every enabled endpoint subscribed to that event.

## Add an endpoint

In https://app.caudals.com/workspace/settings?tab=developers, under **Alert destinations**, add a destination:

- **Webhook**: an HTTPS URL on the public internet. Caudals shows a signing secret once; store it as `CAUDALS_WEBHOOK_SECRET`.
- **Slack** (`https://hooks.slack.com/services/…`), **Microsoft Teams** (an incoming webhook URL) or **email** (a verified member's address, or a work address on a member's company domain): readable messages with links to the report, the score against last time and up to five questions that got worse. These are not signed and need no code.

"Send test" sends a labelled example to the destination (five an hour per destination).

## Events

| `event_kind` | Sent when |
|---|---|
| `run_completed` | A scheduled run completed and no question got worse (status `pass`) |
| `regression` | At least one question got a worse result than in the previous run |
| `inconclusive` | The run could not be compared fairly with the previous one |
| `run_partial` | The run finished with only part of its answers |
| `run_unknown` | The run failed or was cancelled |

## Body

Canonical JSON with sorted keys. It carries IDs and outcomes only: no questions, answers or document text.

```json
{
  "alert_id": "5b0c6f8e-3c1d-4a4e-9a51-2f0e7d1c9b42",
  "baseline_run_id": "0d7a2c61-8f4b-4e3a-b6c9-7e1f5a2d3c84",
  "dispatch_id": "9e4f1b27-6a3c-4d8e-a1f5-3b7c9d2e6f10",
  "event_id": "monitor:9e4f1b27-6a3c-4d8e-a1f5-3b7c9d2e6f10:regression",
  "event_kind": "regression",
  "reason_codes": ["paired_case_regressed"],
  "run_id": "c3a8e5d2-1f7b-4c6a-9e2d-8b4f0a6c1e37",
  "status": "regression"
}
```

Use `run_id` with the API (`GET /integrations/runs/{runId}/gate`) or open the evaluation in the app for details.

## Handle deliveries safely

- Process a delivery only after its signature verifies (below). Answer anything unsigned or stale with a 4xx and drop it.
- Treat the body as data. Check that each field has the expected shape (UUIDs, a known `event_kind`, short lower-case reason codes) and never pass it to a shell, a template or an AI agent as instructions.
- Use it to trigger your own lookups (for example the gate of `run_id` through the API) rather than acting on the body alone.

## Headers

| Header | Meaning |
|---|---|
| `x-caudals-delivery-id` | Unique per delivery; accept each one once |
| `x-caudals-timestamp` | ISO 8601 time of sending |
| `x-caudals-signature` | `v1=` followed by the hex HMAC-SHA256 |

## Verify the signature

The signature is `v1=` + hex(HMAC-SHA256(key, `{delivery id}.{timestamp}.{raw body}`)), where the key is the signing secret decoded from base64url. Reject a timestamp more than five minutes from your clock, compare in constant time, accept each delivery ID only once, and always verify against the **raw** body bytes, before any JSON parsing.

### Node.js

```js
import { createHmac, timingSafeEqual } from "node:crypto";

// The signing secret shown once when you added the endpoint.
const secret = Buffer.from(process.env.CAUDALS_WEBHOOK_SECRET, "base64url");
const seen = new Set(); // keep delivery ids in your database in production

// headers: the request headers (lower-case names); rawBody: the body as received (Buffer).
export function verifyCaudalsWebhook(headers, rawBody) {
  const id = headers["x-caudals-delivery-id"];
  const timestamp = headers["x-caudals-timestamp"] ?? "";
  const signature = Buffer.from(headers["x-caudals-signature"] ?? "");
  const sent = Date.parse(timestamp);
  if (!id || !Number.isFinite(sent) || Math.abs(Date.now() - sent) > 300000) return false;
  const expected = Buffer.from(
    "v1=" + createHmac("sha256", secret).update(`${id}.${timestamp}.`).update(rawBody).digest("hex"),
  );
  if (signature.length !== expected.length || !timingSafeEqual(signature, expected)) return false;
  if (seen.has(id)) return false; // a replay
  seen.add(id);
  return true;
}
```

With Express, read the raw body: `app.post("/caudals", express.raw({ type: "application/json" }), handler)` and pass `req.headers` and `req.body`.

### Python

```python
import base64, hashlib, hmac, os, time
from datetime import datetime

# The signing secret shown once when you added the endpoint.
_value = os.environ["CAUDALS_WEBHOOK_SECRET"]
SECRET = base64.urlsafe_b64decode(_value + "=" * (-len(_value) % 4))
seen = set()  # keep delivery ids in your database in production

# headers: a case-insensitive mapping (e.g. request.headers); raw_body: the body as received (bytes).
def verify_caudals_webhook(headers, raw_body: bytes) -> bool:
    delivery_id = headers.get("x-caudals-delivery-id", "")
    timestamp = headers.get("x-caudals-timestamp", "")
    signature = headers.get("x-caudals-signature", "")
    try:
        sent = datetime.fromisoformat(timestamp.replace("Z", "+00:00")).timestamp()
    except ValueError:
        return False
    if not delivery_id or abs(time.time() - sent) > 300:
        return False
    message = f"{delivery_id}.{timestamp}.".encode() + raw_body
    expected = "v1=" + hmac.new(SECRET, message, hashlib.sha256).hexdigest()
    if not hmac.compare_digest(signature, expected):
        return False
    if delivery_id in seen:  # a replay
        return False
    seen.add(delivery_id)
    return True
```

With Flask, pass `request.headers` and `request.get_data()`.

## Delivery and retries

- Answer with a 2xx status within 10 seconds. Do slow work after answering.
- Redirects are not followed.
- A failed delivery is retried after 1, 2, 4 and 8 minutes: five attempts in all. The destinations list in the app counts failed deliveries.
- A retry keeps the same `x-caudals-delivery-id` with a new timestamp and signature. If an earlier attempt reached you but your answer was lost, the retry repeats an ID you have already processed: answer 2xx without processing it again, so the retries stop. `event_id` identifies the event itself.

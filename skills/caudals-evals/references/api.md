# Caudals API reference

The customer API of `app.caudals.com`. The same reference, with your own workspace ID filled in, is in the app under **Settings → Developers → API reference**.

- Base URL: `https://app.caudals.com/api/evals/v1`
- Authentication: `Authorization: Bearer evct_…` (a customer API token; 48 characters, starting with `evct_`)
- Workspace: every request names it with `orgId` (a UUID), as a query parameter or, for the estimate, a body field.
- Responses: JSON. Success is `{"data": …}`. An error is `{"error": {"code": "…", "message": "…"}}` (some read endpoints send only `code`).
- Responses are private (`Cache-Control: private, no-store`); do not cache or publish them.

## Contents

- [Tokens and scopes](#tokens-and-scopes)
- [List runs](#list-runs)
- [List reports](#list-reports)
- [List schedules](#list-schedules)
- [Latest outcome of a schedule](#latest-outcome-of-a-schedule)
- [Estimate a run](#estimate-a-run)
- [Start a run](#start-a-run)
- [Release gate of a run](#release-gate-of-a-run)
- [Errors](#errors)
- [Limits](#limits)

## Tokens and scopes

A workspace owner creates tokens in **Settings → Developers → API tokens**: a name, the scopes and an expiry from five minutes to one year. A token that can start runs (`runs:write`) lasts at most 90 days. The value is shown once; Caudals stores only its hash. Tokens can be revoked at any time, and are revoked when the workspace is deleted. Creating and revoking a token is recorded in the workspace's audit log, and a run started by a token names that token.

| Scope | Endpoints |
|---|---|
| `runs:read` | `GET /integrations/runs`, `GET /integrations/ci/{scheduleId}`, `GET /integrations/runs/{runId}/gate`, `POST /billing/estimates` |
| `reports:read` | `GET /integrations/reports` |
| `schedules:read` | `GET /integrations/schedules` |
| `runs:write` | `POST /integrations/runs`, `GET /integrations/runs/{runId}/gate` |

## List runs

`GET /integrations/runs?orgId={orgId}` · scope `runs:read`

The 100 most recent runs, newest first.

```bash
curl -s "https://app.caudals.com/api/evals/v1/integrations/runs?orgId=$CAUDALS_ORG_ID" \
  -H "Authorization: Bearer $CAUDALS_TOKEN"
```

| Field | Meaning |
|---|---|
| `id` | Run ID |
| `evaluation_id` | The evaluation the run belongs to |
| `target_revision_id` | The system version that was tested |
| `suite_version_id` | The test set version that was asked |
| `status` | `queued`, `running`, `pause_requested`, `paused`, `cancel_requested`, `canceled`, `completed`, `partial` (finished with part of its answers) or `failed` |
| `phase` | `preflight`, `target_execution`, `grading`, `aggregation`, `reporting` or `done` |
| `reason_code` | Why a run paused or failed, when it did (for example `credits_exhausted`) |
| `created_at`, `updated_at` | ISO 8601 timestamps |

## List reports

`GET /integrations/reports?orgId={orgId}` · scope `reports:read`

The 100 most recently updated **published** reports, newest first. Drafts are not listed.

| Field | Meaning |
|---|---|
| `id` | Report ID. The report opens at `https://app.caudals.com/workspace/reports/{id}` for signed-in members |
| `title` | Report title |
| `current_revision_id` | The published revision |
| `updated_at` | ISO 8601 timestamp |

The API lists reports; it does not return their findings. Read them in the app, or download the PDF or Word file there.

## List schedules

`GET /integrations/schedules?orgId={orgId}` · scope `schedules:read`

The 100 most recently updated monitoring schedules.

| Field | Meaning |
|---|---|
| `id` | Schedule ID (use it with `/integrations/ci/{scheduleId}`) |
| `evaluation_id`, `target_revision_id`, `suite_version_id` | What the schedule runs |
| `status` | `active` or `paused` |
| `next_due_at` | Next run, ISO 8601 |
| `timezone`, `local_time` | When it runs, in the schedule's time zone |
| `cadence` | `daily`, `weekly` or `monthly` |
| `weekday` | 1 (Monday) to 7, for weekly schedules |
| `day_of_month` | 1 to 31, for monthly schedules |
| `version` | Increases each time the schedule is edited |

## Latest outcome of a schedule

`GET /integrations/ci/{scheduleId}?orgId={orgId}` · scope `runs:read`

The outcome of the schedule's most recent run, compared with the run before it. Use it to gate a release on the latest scheduled run without starting a new one.

```json
{
  "data": {
    "schedule_id": "…",
    "dispatch_id": "…",
    "scheduled_for": "2026-11-02T08:00:00.000Z",
    "run_id": "…",
    "status": "regression",
    "reason_codes": ["paired_case_regressed"]
  }
}
```

| `status` | Meaning |
|---|---|
| `pass` | The run completed and no question got worse than in the previous run |
| `regression` | At least one question got a worse result (`paired_case_regressed`) |
| `inconclusive` | The runs could not be compared fairly: `run_incomplete`, `no_baseline`, `coverage_inadequate`, `incomparable`, `paired_coverage_inadequate`, `mixed_change` and similar |
| `unknown` | The run failed or was cancelled (`run_failed`), or the scheduled run was skipped |
| `pending` | Not judged yet; `no_dispatch_yet` when the schedule has never run |

## Estimate a run

`POST /billing/estimates` · scope `runs:read` · header `Idempotency-Key` required (1–200 characters)

```bash
curl -s -X POST "https://app.caudals.com/api/evals/v1/billing/estimates" \
  -H "Authorization: Bearer $CAUDALS_TOKEN" \
  -H "Content-Type: application/json" \
  -H "Idempotency-Key: estimate-$(date +%s)" \
  -d "{\"orgId\":\"$CAUDALS_ORG_ID\",\"evaluationId\":\"<evaluation id>\"}"
```

Body: `orgId` and `evaluationId` (required); `suiteVersionId` and `targetRevisionId` (optional; default to the evaluation's approved test set and selected system).

The answer includes:

| Field | Meaning |
|---|---|
| `questions` | `count`, `executions`, `judged` |
| `credits` | `p50` and `p90`, whole credits as strings |
| `euros` | The same as a euro equivalent |
| `eta` | `p50Seconds`, `p90Seconds` |
| `balance` | `billingMode`, `availableCredits`, `coversP90` (true when the balance covers the p90), `addCredits` (how many to add, or null) |

A run is admitted against its p90 estimate where the workspace pays with credits, so check `balance.coversP90` before starting one.

## Start a run

`POST /integrations/runs?orgId={orgId}` · scope `runs:write` · header `Idempotency-Key` required (8–200 visible ASCII characters)

Starts one run of an evaluation's approved test set version on a system version. Plan limits, credit admission and credit caps apply exactly as when someone presses Run in the app. **It spends credits.**

```bash
curl -s -X POST "https://app.caudals.com/api/evals/v1/integrations/runs?orgId=$CAUDALS_ORG_ID" \
  -H "Authorization: Bearer $CAUDALS_TOKEN" \
  -H "Content-Type: application/json" \
  -H "Idempotency-Key: release-$(git rev-parse HEAD)" \
  -d '{"suiteVersionId":"<test set version id>","targetRevisionId":"<system version id>"}'
```

| Body field | Meaning |
|---|---|
| `suiteVersionId` | Required. **Test set version ID** from Settings → Developers → Release gate |
| `targetRevisionId` | Required. **System version ID** from the same place |
| `evaluationId` | Only when several evaluations use the same test set version (the API answers 422 and asks for it) |

`201 Created` for a new run, `200 OK` with `replayed: true` when the key was already used for the same body:

```json
{
  "data": {
    "run_id": "…",
    "evaluation_id": "…",
    "suite_version_id": "…",
    "target_revision_id": "…",
    "status": "queued",
    "replayed": false,
    "gate_url": "/api/evals/v1/integrations/runs/…/gate?orgId=…",
    "estimate": { "credits": { "p50": "12", "p90": "15" } }
  }
}
```

`estimate` is null for contract workspaces or when the run cannot be priced. `gate_url` is relative to `https://app.caudals.com`.

Idempotency: each key starts exactly one run per workspace, even under concurrent retries. Retry with the same key and body to get the same run back. The same key with a different body answers 409 `IDEMPOTENCY_CONFLICT`. Use a new key for a new run.

## Release gate of a run

`GET /integrations/runs/{runId}/gate?orgId={orgId}` · scope `runs:read` or `runs:write`

```json
{
  "data": {
    "run_id": "…",
    "status": "pass",
    "score": { "pass": 46, "scored": 50, "percent": 92 },
    "threshold": 90,
    "threshold_source": "test_set",
    "run_status": "completed",
    "reason_codes": [],
    "report_id": "…"
  }
}
```

| `status` | Meaning | `reason_codes` |
|---|---|---|
| `pass` | Passed answers ÷ scored answers ≥ the threshold | none |
| `fail` | Below the threshold | `below_threshold` |
| `unknown` | No result can be given | `run_failed`, `run_canceled`, `run_paused`, `credits_exhausted`, `cap_reached`, `coverage_inadequate` (fewer than 90 % of questions graded), `critical_unassessed` (a critical question was not graded), `no_scored_answers`, `threshold_not_set` |
| `pending` | Still running or being graded. The response carries `Retry-After: 30`; poll again after it | `run_in_progress`, `grading` |

`threshold` is a percentage (0–100, two decimals). `threshold_source` is `schedule` when the run was started by a schedule with its own threshold, `test_set` when the test set's threshold applies, and null when neither is set. Set thresholds in **Settings → Developers → Release gate**. `score` and `report_id` are null until the run finishes.

Treat only `pass` as success. `unknown` is not a pass.

## Errors

| Status | `error.code` | Meaning |
|---|---|---|
| 400 | `INPUT_INVALID` | `orgId`, an ID, the body or the `Idempotency-Key` is not valid |
| 401 | `SCOPE_DENIED` | No token was sent, or it is not a Caudals token |
| 402 | `CREDITS_EXHAUSTED` | Not enough credits for the run's estimate |
| 403 | `SCOPE_DENIED` | The token is expired or revoked, belongs to another workspace, or lacks the scope |
| 404 | `SCOPE_DENIED` | The run, schedule, system version or test set version does not exist in this workspace |
| 409 | various, incl. `IDEMPOTENCY_CONFLICT` | A plan limit or credit cap was reached, the test set version is no longer the approved one, or the key was used for another request |
| 422 | `INPUT_INVALID` | The request cannot run as sent, e.g. a system tested on collected answers, or several evaluations share the test set version |
| 429 | `RATE_LIMITED` | Too many requests; wait the `Retry-After` seconds |
| 503 | `SERVICE_UNAVAILABLE` | Temporary; retry later (with the same `Idempotency-Key` for a run) |

## Limits

- 60 requests a minute per token, across every endpoint.
- 30 new runs an hour per workspace; replays of an `Idempotency-Key` do not count.
- Lists return at most 100 items; there is no pagination.
- Tokens last five minutes to one year; tokens with `runs:write` at most 90 days.
- The start-run body is at most 8 KB.

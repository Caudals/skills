# Caudals release gates in CI

Two ways to stop a release when the AI assistant got worse:

1. **Run on release** (`runs:write` + `runs:read`): start a run of the approved test set for each release and fail the build unless its gate passes. It spends credits on every release.
2. **Check the latest scheduled run** (`runs:read` only): fail the build when the most recent scheduled run is not `pass`. It starts nothing and costs nothing.

## Before you start

1. In https://app.caudals.com/workspace/settings?tab=developers, under **Release gate**, find the evaluation and copy its **Test set version ID** and **System version ID**. Set a **pass threshold** there (for example 90 %); without one the gate answers `unknown`.
2. Under **API tokens**, create a token. For option 1 give it `runs:write` and `runs:read` and an expiry of at most 90 days; for option 2 `runs:read` is enough.
3. Store the token as a CI secret named `CAUDALS_TOKEN` (on GitLab, masked and protected, so only protected branches can read it). Store the workspace ID and the two version IDs as plain CI variables; they are not secret. Never run the job on `pull_request_target` or other triggers that hand secrets to code from forks.
4. Note the token's expiry and rotate it before then.

The `Idempotency-Key` must be the same on every retry of one release and different for each release. Include the commit and the attempt number, as below, so a re-run of the job starts a fresh run while a network retry does not.

## GitHub Actions: run on release

```yaml
# .github/workflows/caudals-gate.yml
name: Caudals release gate
on:
  workflow_dispatch:
  push:
    branches: [main]
permissions:
  contents: read
jobs:
  caudals:
    runs-on: ubuntu-latest
    timeout-minutes: 90
    steps:
      - name: Run the Caudals test set and check the gate
        env:
          CAUDALS_TOKEN: ${{ secrets.CAUDALS_TOKEN }}
          CAUDALS_API: https://app.caudals.com/api/evals/v1
          ORG_ID: ${{ vars.CAUDALS_ORG_ID }}
          SUITE_VERSION_ID: ${{ vars.CAUDALS_SUITE_VERSION_ID }}
          TARGET_REVISION_ID: ${{ vars.CAUDALS_TARGET_REVISION_ID }}
        run: |
          set -euo pipefail
          tmp=$(mktemp -d)
          # api <output file> <curl arguments>: retries resend the same request and
          # overwrite the file; on failure the error body goes to the log.
          api() {
            out="$1"; shift
            if ! curl -sS --fail-with-body --retry 3 --retry-all-errors -o "$out" \
                -H "Authorization: Bearer $CAUDALS_TOKEN" "$@"; then
              cat "$out" >&2; return 1
            fi
          }
          body=$(jq -nc --arg s "$SUITE_VERSION_ID" --arg t "$TARGET_REVISION_ID" '{suiteVersionId:$s,targetRevisionId:$t}')
          api "$tmp/run.json" -X POST "$CAUDALS_API/integrations/runs?orgId=$ORG_ID" \
            -H "Content-Type: application/json" \
            -H "Idempotency-Key: gh-${{ github.sha }}-${{ github.run_attempt }}" \
            -d "$body"
          run_id=$(jq -r '.data.run_id' "$tmp/run.json")
          echo "Caudals run $run_id"
          while true; do
            api "$tmp/gate.json" "$CAUDALS_API/integrations/runs/$run_id/gate?orgId=$ORG_ID"
            status=$(jq -r '.data.status' "$tmp/gate.json")
            [ "$status" != "pending" ] && break
            sleep 30
          done
          jq '.data' "$tmp/gate.json"
          test "$status" = "pass"
```

`curl --retry` resends the same `Idempotency-Key`, so a retried request never starts a second run, and it waits the `Retry-After` seconds on a 429. Write responses to a file with `-o`, as here: curl overwrites the file on each retry, whereas with output captured from stdout a failed attempt's body would end up in front of the good one. `jq` is preinstalled on GitHub's Ubuntu runners.

## GitLab CI: run on release

```yaml
# .gitlab-ci.yml
caudals_gate:
  stage: test
  image: alpine:3.20
  timeout: 90m
  variables:
    CAUDALS_API: https://app.caudals.com/api/evals/v1
    # CAUDALS_TOKEN (masked and protected), CAUDALS_ORG_ID, CAUDALS_SUITE_VERSION_ID
    # and CAUDALS_TARGET_REVISION_ID are set in Settings → CI/CD → Variables.
  before_script:
    - apk add --no-cache curl jq
  script:
    - |
      set -eu
      tmp=$(mktemp -d)
      api() {
        out="$1"; shift
        if ! curl -sS --fail-with-body --retry 3 --retry-all-errors -o "$out" \
            -H "Authorization: Bearer $CAUDALS_TOKEN" "$@"; then
          cat "$out" >&2; return 1
        fi
      }
      body=$(jq -nc --arg s "$CAUDALS_SUITE_VERSION_ID" --arg t "$CAUDALS_TARGET_REVISION_ID" '{suiteVersionId:$s,targetRevisionId:$t}')
      api "$tmp/run.json" -X POST "$CAUDALS_API/integrations/runs?orgId=$CAUDALS_ORG_ID" \
        -H "Content-Type: application/json" \
        -H "Idempotency-Key: gl-$CI_COMMIT_SHA-$CI_PIPELINE_ID" \
        -d "$body"
      run_id=$(jq -r '.data.run_id' "$tmp/run.json")
      echo "Caudals run $run_id"
      while true; do
        api "$tmp/gate.json" "$CAUDALS_API/integrations/runs/$run_id/gate?orgId=$CAUDALS_ORG_ID"
        status=$(jq -r '.data.status' "$tmp/gate.json")
        [ "$status" != "pending" ] && break
        sleep 30
      done
      jq '.data' "$tmp/gate.json"
      test "$status" = "pass"
```

## Any CI: check the latest scheduled run

Needs a `runs:read` token and the schedule's ID (from `GET /integrations/schedules`, or the helper's `schedules` command).

```bash
status=$(curl -sS --fail-with-body "https://app.caudals.com/api/evals/v1/integrations/ci/$SCHEDULE_ID?orgId=$CAUDALS_ORG_ID" \
  -H "Authorization: Bearer $CAUDALS_TOKEN" | jq -r '.data.status')
if [ "$status" != "pass" ]; then
  echo "Caudals: latest scheduled run is $status"
  exit 1
fi
```

## With the helper script

If the skill's `scripts/caudals.sh` is in the repository (or fetched in the job):

```bash
run_id=$(bash scripts/caudals.sh start-run "$SUITE_VERSION_ID" "$TARGET_REVISION_ID" "ci-$COMMIT_SHA-$ATTEMPT" | jq -r '.data.run_id')
bash scripts/caudals.sh wait-gate "$run_id" 5400   # exit 0 only on pass
```

## Reading the result

- `pass`: release.
- `fail`: the score is below the threshold. `score.pass` / `score.scored` and `report_id` say by how much and where to look.
- `unknown`: no verdict (failed or paused run, too few graded answers, no threshold). Do not treat it as a pass; read `reason_codes`.
- A 402 or 409 when starting the run means credits or a plan limit stopped it; the build should fail and a person should look.

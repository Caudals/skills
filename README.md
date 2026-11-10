# Caudals agent skills

Agent skills for [Caudals](https://caudals.com), which tests AI assistants, chatbots and agents against a company's own documentation and backs every verdict with evidence.

```bash
npx skills add caudals/skills
```

Works with Claude Code, Cursor, Codex, GitHub Copilot, Windsurf, Gemini CLI and the other agents supported by the [skills CLI](https://github.com/vercel-labs/skills).

The repository is also a Cursor plugin (`.cursor-plugin/plugin.json`): the `caudals-evals` skill plus the `caudals-api` rule in [`rules/caudals-api.mdc`](rules/caudals-api.mdc), which keeps tokens, idempotency keys, release gates and webhook checks safe whenever your code calls Caudals.

## Skills

### `caudals-evals`

Lets your coding agent work with your Caudals workspace through the customer API:

- read your latest runs, published reports and monitoring schedules,
- estimate a run's credits before starting it,
- start a run of an approved test set from CI and fail the release unless it passes the gate (GitHub Actions and GitLab CI examples included),
- receive and verify signed webhooks when a scheduled run is judged,
- and, if you have no account yet, point you to the free test or the free workspace.

It includes a small `curl` + `jq` helper, [`scripts/caudals.sh`](skills/caudals-evals/scripts/caudals.sh), that keeps your token off the command line, sends it only to `app.caudals.com` and honours `Retry-After`.

Try it by asking your agent:

- "How did our assistant do in the last Caudals runs?"
- "Add a Caudals release gate to our GitHub Actions workflow."
- "Write an Express handler for Caudals webhooks that verifies the signature."

## Setup

1. Create a free workspace at [app.caudals.com/workspace/start](https://app.caudals.com/workspace/start), or try the [free test](https://caudals.com/en/demo) first: no account, about three minutes.
2. In **Settings → Developers**, create an API token with the scopes you need and copy your Workspace ID.
3. Make them available to your agent:

```bash
export CAUDALS_TOKEN="evct_…"
export CAUDALS_ORG_ID="<workspace id>"
```

Keep the token in your shell or your CI secrets. Do not commit it.

## Certification

Caudals issues its own certification for AI agents, [CTS-1](https://caudals.com/en/certification) (the Caudals Trust Standard, in Spanish at [caudals.com/es/certificacion](https://caudals.com/es/certificacion)). It has 36 requirements under three risks, a certificate valid for twelve months, a re-test every quarter and a [public registry](https://caudals.com/en/cts-1/registry). Certification is quoted on scope after a scoping call.

CTS-1 is Caudals' private standard. It is not accredited, it is not a conformity assessment under the EU AI Act, an ISO certificate or a SOC 2 report, and it guarantees nothing.

This skill and the API do not certify anything. A run or a report is evidence, not a certificate. Only a system that went through the CTS-1 process and appears in the registry is certified.

## What Caudals does not do

Caudals does not make anyone compliant with the EU AI Act, and it never runs adversarial tests (prompt injection, jailbreaks) without the system owner's written authorisation.

## Links

- [Methodology](https://caudals.com/en/methodology)
- [Sample report](https://caudals.com/en/sample-report)
- [CTS-1 certification](https://caudals.com/en/certification)
- [Request a pilot evaluation](https://caudals.com/en/contact?offer=pilot-evaluation)
- Questions: hello@caudals.com

## License

[MIT](LICENSE)

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

## What Caudals does not do

Caudals produces evidence about how an AI system answers. It does not certify AI systems or make anyone compliant with the EU AI Act, and it never runs adversarial tests (prompt injection, jailbreaks) without the system owner's written authorisation.

## Links

- [Methodology](https://caudals.com/en/methodology)
- [Sample report](https://caudals.com/en/sample-report)
- [Request a pilot evaluation](https://caudals.com/en/contact?offer=pilot-evaluation)
- Questions: hello@caudals.com

## License

[MIT](LICENSE)

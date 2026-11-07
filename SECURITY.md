# Security

## Reporting a vulnerability

Please report security issues privately, never in a public issue or pull request:

- use **Report a vulnerability** on this repository's **Security** tab (GitHub private vulnerability reporting), or
- email hello@caudals.com with "Security" in the subject.

We reply within two working days. This covers the skills in this repository and the Caudals customer API they describe (`app.caudals.com/api/evals/v1`).

## Handling tokens

- A Caudals API token (`evct_…`) belongs in your shell environment or your CI secrets. Never commit it, paste it into an issue or share it in chat.
- Give each token only the scopes it needs and the shortest practical expiry.
- If a token may have been exposed, revoke it at once in **Settings → Developers** on app.caudals.com and create a new one.
- The helper script in `skills/caudals-evals/scripts/caudals.sh` sends the token only to `https://app.caudals.com` and refuses any other address.

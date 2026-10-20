# Security policy

## Reporting

Please report security issues privately through GitHub's **Security → Report a vulnerability** on this repository. Do not open a public issue. Expect an acknowledgment within 5 business days.

## Scope

This is a learning lab. In scope: anything in this repo that would cause a user to expose credentials, account identifiers, prompts, or logs, or to grant broader access than documented.

## Handling rules for contributors

- Never commit account IDs, ARNs containing account IDs, resource IDs, hostnames, credentials, Terraform state, or downloaded invocation logs. Use `<PLACEHOLDERS>`.
- CI blocks real ARNs with account IDs and runs gitleaks. Run `pre-commit install` locally to catch issues before pushing.
- Never use real CUI, PII, or internal runbooks as sample documents.

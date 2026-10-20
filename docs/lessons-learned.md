# Lessons learned

Every failure hit while building this lab, why it happened, and what the repo does about it. Ordered by module.

## Model access: three separate gates

| Layer | Scope | Check | Symptom when missing |
|---|---|---|---|
| 1. Per-model agreement (EULA) | One model | `aws bedrock get-foundation-model-availability --model-id <MODEL_ID>` | `AccessDeniedException` for that model only |
| 2. Anthropic use-case form | Whole account, all Claude models | `aws bedrock get-use-case-for-model-access` | `AccessDeniedException` on every Claude model while Nova works |
| 3. Account-level eligibility | Whole account | Only a real invoke shows it | `not available for this account ... contact AWS Sales` even when 1 and 2 pass |

- **Agreements are per model.** Accepting Opus 5.5 granted nothing for Sonnet 5.5.
- **Green status is not proof.** Availability returned `AVAILABLE` / `AUTHORIZED` while invoke failed; the status call does not report the use-case form.
- **Repo response:** `scripts/01-smoke-test.sh` makes a real 5-token call per model and checks the use-case form whenever an Anthropic model is tested.

## Shell and environment

- **Variables do not survive a new terminal.** An empty `$BEDROCK_MODEL` produced `ParamValidation: Invalid length for parameter modelId, value: 0`.
- **Repo response:** settings live in a sourced `.env`; scripts use `${VAR:?message}` and Python uses `require_env()` to fail fast with a clear message.
- **The CLI pager hides output** behind a `:` prompt. `AWS_PAGER=""` is set everywhere.

## Private network path

- **The account had no default VPC** (commonly deleted as hardening). Expect the same in GovCloud; always pass `VPC_ID`.
- **Pick subnets by the AZs the service supports.** `describe-vpc-endpoint-services` lists them; the script spreads the endpoint across two.
- **Private DNS needs both VPC DNS attributes.** The script checks `enableDnsSupport` and `enableDnsHostnames` before creating anything.
- **A laptop outside the VPC resolves public IPs, correctly.** Test from inside the VPC (CloudShell VPC environment or an instance).
- **The security group cannot be deleted until the endpoint's network interfaces are gone.** Teardown waits, then retries.

## Least-privilege IAM

- **Two ARNs are needed:** the inference profile you call, and the base model with a `*` Region, because the profile can route to any Region in its geography.
- **IAM, SCP, and endpoint policy each set a limit; the tightest wins.** `ENDPOINT_MODEL_ALLOWLIST=1` adds the network-layer limit.

## Invocation logging

- **S3 delivery needs a bucket policy** allowing `bedrock.amazonaws.com` to `s3:PutObject` under `AWSLogs/<ACCOUNT_ID>/BedrockModelInvocationLogs/*`, scoped with `aws:SourceAccount` and `aws:SourceArn`.
- **Bedrock writes a zero-byte permission-check object** when logging is enabled. Seeing it confirms the policy before any real logs arrive.
- **Logs arrive in batches** a few minutes after the call, as `.json.gz`.
- **Logging is one setting per account per Region.** The script refuses to overwrite an existing target.

## Guardrails

- **Version before use.** `create-guardrail` makes a draft; `create-guardrail-version` freezes a number.
- **Test the false-positive case,** not only the blocks. A normal question must still pass.
- **`ApplyGuardrail` tests policy with no model call** and can filter text from non-Bedrock systems.

## Knowledge Bases

| Observation | Lesson |
|---|---|
| The console wizard had no vector-store choice | It now defaults to a **Managed Knowledge Base** (GA June 2026). Bedrock owns the store; pricing is per GB indexed plus per retrieval. |
| `Unsupported data source type for MANAGED knowledgebase type` | Managed KBs reject the classic S3 data-source shape. |
| `This operation is not supported for managed knowledge bases` | Managed KBs do not support `RetrieveAndGenerate`. |
| `vectorSearchConfiguration is not supported for managed knowledge bases` | Omit `retrievalConfiguration` or use `managedSearchConfiguration`. |
| Two unrelated questions returned the same file with the same score | Only one document was indexed. Two data sources each pointed at one file, and one had never synced. |
| `COMPLETE 0 0` | Correct when nothing changed: sync is incremental. Watch **scanned**, and alert on **failed > 0**. |
| Identical `0.73` scores after the fix | The managed reranker normalizes scores. Judge by which file returns, not the number. |

**Repo response:** `07-kb.sh sync` syncs every data source and reports scanned/new/failed; `07-kb.sh canary` checks one known question per document; `src/rag.py` uses retrieve-then-generate, which works with every KB type.

## Retrieve-then-generate

- `temperature: 0` plus a fixed refusal phrase (`Not found in the provided sources.`) makes "not found" predictable for downstream code.
- **Retrieved is not the same as used.** An unanswerable question still returns the nearest documents; the model correctly declined to use them.

## Tool use

- The model **requested** a tool; the app **checked an allow-list and ran it**. Two turns, well under the 5-turn cap.
- **Nova emitted `<thinking>` blocks** in the final answer during tool use. `labutil.strip_thinking()` removes them before display.

## Terraform

- `aws_partition` makes one configuration deploy to commercial and GovCloud. Plan output showed `partition = "aws"` and a correctly built profile ARN.
- `terraform destroy` removed both resources in one command, the cleanest teardown in the lab.

## Teardown

- **Delete in reverse dependency order:** logging config before its bucket, KB before its source bucket, endpoints before their security group.
- **The Resource Groups Tagging API lags.** A deleted endpoint still appeared there after direct API counts showed zero. Trust direct counts.
- **Console-created KB service roles** don't carry the lab name. Review and delete them by hand.

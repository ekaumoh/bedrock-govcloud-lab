# Moving to AWS GovCloud (US): do-not-forgets

The lab code is partition-aware. What changes in GovCloud is the **process around it**: model access, authorization levels, networking, and encryption. This page lists everything that differs, with the command to check each item.

**Acronyms:** IL5 = DoD Impact Level 5. CUI = Controlled Unclassified Information. EULA = End User License Agreement. SCP = Service Control Policy. ISSO = Information System Security Officer. KMS = Key Management Service. CMK = customer-managed key. TPM / RPM = tokens / requests per minute. KB = Knowledge Base. ATO = Authority to Operate.

## Model authorization (check before every design review)

| Model | FedRAMP High (Class D) | DoD IL4/IL5 |
|---|---|---|
| Claude Sonnet 5 | Yes | Yes |
| Claude Sonnet 5.5 | Yes | Not listed |
| Claude Opus 5.5 | Yes | Not listed |

As of October 2026, per the [AWS ML Blog](https://aws.amazon.com/blogs/machine-learning/supercharge-regulated-workloads-with-claude-code-and-amazon-bedrock/). The authoritative, current list is the [Amazon Bedrock models FedRAMP / DoD status page](https://aws.amazon.com/compliance/services-in-scope/FedRAMP/amazon-bedrock-models/).

## Do-not-forgets

| # | Do not forget | How to check or do it | Why it matters |
|---|---|---|---|
| 1 | Anthropic use-case form is filed in the **linked standard account** | `aws bedrock get-use-case-for-model-access --region us-east-1` (standard account) | Blocks every Claude model; looks like an IAM problem |
| 2 | Per-model EULA in the standard account, then enable in GovCloud | Standard account: `list-foundation-model-agreement-offers`, then `create-foundation-model-agreement`. GovCloud console: **Model access** | Two-account process; entitlements take minutes to propagate |
| 3 | Partition check before any work | `aws sts get-caller-identity --query Arn --output text` starts with `arn:aws-us-gov:` | Commercial credentials against GovCloud fail with misleading errors |
| 4 | Use `us-gov.` inference profile IDs | Example: `us-gov.anthropic.claude-sonnet-5` | `us.` and `global.` are commercial; `global.` must never carry CUI |
| 5 | **Available** is not **IL5-authorized** | Status page above | Choose the model by authorization, then by capability |
| 6 | Use `bedrock-runtime` for audited workloads | Converse / InvokeModel | Guardrails and invocation logging are not available on `bedrock-mantle`, which is `us-gov-west-1` only |
| 7 | Invocation logging on, logs treated as CUI | `aws bedrock get-model-invocation-logging-configuration` | Logs hold full prompt text; CMK encryption, restricted readers |
| 8 | Interface endpoints for every Bedrock service used | `bedrock-runtime`, plus `bedrock`, `bedrock-agent`, `bedrock-agent-runtime` as needed | No internet path for model traffic |
| 9 | No hand-typed `arn:aws:` | Terraform: `data "aws_partition"`; scripts: parse from `sts` | A copied commercial policy silently matches nothing |
| 10 | Smoke-test approved models at account onboarding | `scripts/01-smoke-test.sh <ID> <ID>` | Account eligibility can block a new account even when status is green |
| 11 | Request TPM / RPM quota before launch | `aws service-quotas list-service-quotas --service-code bedrock` | Day-one throttling is the most common launch failure |
| 12 | Pin guardrail versions | Reference a number, never `DRAFT` | Changes are reviewable and reversible |
| 13 | No export-controlled data in model evaluation job metadata | Review evaluation job configuration | AWS lists this metadata as able to leave the GovCloud boundary during support investigations |
| 14 | Keep one approved-model list | Feeds the SCP allow-list, the smoke test, and the ISSO record | Single source of truth for what is in the boundary |
| 15 | Expect no default VPC | Set `VPC_ID`; build endpoints in Terraform | GovCloud tenants use purpose-built private VPCs |
| 16 | Check for existing endpoints before creating yours | `aws ec2 describe-vpc-endpoints`; ask the platform team | Duplicate private DNS zones conflict in shared VPCs |
| 17 | Confirm which KB type GovCloud offers | GovCloud Bedrock console and the GovCloud Bedrock documentation | Managed KB is new; if absent, design for a customer-managed KB |
| 18 | Code against KB-type-specific APIs deliberately | Read the type at startup with `get-knowledge-base`; prefer retrieve-then-generate | Managed and customer-managed KBs accept different API shapes |
| 19 | Encrypt every copy of CUI in the RAG path | CMK on the source bucket, vector or managed store, and log destinations | Ingested chunks are copies of the source documents |
| 20 | Turn on S3 versioning for KB sources | Versioning on the data-source bucket | Citations become evidence: you can show which version was indexed |

## Running this lab in GovCloud

```bash
export AWS_PROFILE=REPLACE_ME AWS_REGION=us-gov-west-1 VPC_ID=REPLACE_ME BEDROCK_MODEL=us-gov.anthropic.claude-sonnet-5 KMS_KEY_ARN=REPLACE_ME
```
(Sets the GovCloud inputs. Every script derives `arn:aws-us-gov` and the `us-gov.` prefix itself.)

```bash
make preflight smoke
```
(Confirms the partition and that the IL5-authorized model is callable.)

For Terraform, set `region = "us-gov-west-1"` and `kms_key_arn` in `terraform.tfvars`, and configure the S3 backend in a GovCloud bucket. State contains account IDs and ARNs.

## References

- [Amazon Bedrock in AWS GovCloud (US)](https://docs.aws.amazon.com/govcloud-us/latest/UserGuide/govcloud-bedrock.html)
- [Regional availability by models, including GovCloud model enablement](https://docs.aws.amazon.com/bedrock/latest/userguide/models-region-compatibility.html)
- [Amazon Bedrock models FedRAMP / DoD status](https://aws.amazon.com/compliance/services-in-scope/FedRAMP/amazon-bedrock-models/)
- [Supercharge regulated workloads with Claude Code and Amazon Bedrock](https://aws.amazon.com/blogs/machine-learning/supercharge-regulated-workloads-with-claude-code-and-amazon-bedrock/)
- [Troubleshooting Amazon Bedrock API error codes](https://docs.aws.amazon.com/bedrock/latest/userguide/troubleshooting-api-error-codes.html)

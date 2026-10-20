## What and why

<!-- One or two sentences. -->

## Checklist

- [ ] `make lint` passes
- [ ] No account IDs, ARNs with account IDs, resource IDs, or hostnames (use `<PLACEHOLDERS>`)
- [ ] New AWS resources are tagged `Project=bedrock-lab` and removed by `make cleanup`
- [ ] ARNs are built from the partition, never hand-typed `arn:aws:`
- [ ] GovCloud impact noted in `docs/govcloud.md` if behavior differs

# TLS Certificate Rotation Runbook

Certificates on internal load balancers rotate every 60 days.
Rotation is owned by the platform on-call engineer.
A change ticket must be approved 72 hours before rotation.
Rollback: re-import the previous certificate from the vault path `<CERT_VAULT_PATH>`.

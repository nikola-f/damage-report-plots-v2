# Production cutover runbook

Brings up the prod frontend (`plots.world`) for the first time and hands
deployment back to CI. Prod has never been fully deployed: its Terraform state
holds only the bootstrap IAM role, tfstate access and GCP WIF, so this is a
**first-time creation, not a migration**. Nothing is being torn down.

Everything after this unblocks: the OAuth verification submit (D3–D7 in
`AGENTS.md`) needs the consent screen's URLs live on the verified prod domain.

**Executed 2026-08-19**, and corrected against what actually happened. Kept as
the reference for the next first-time environment rather than as a to-do.

---

## Two things that will bite you

**The first apply cannot run in CI.** The plan creates
`aws_iam_role_policy.terraform_app_infra`, `aws_iam_policy.cloudfront_frontend`,
its attachment and `tfstate_read`, and updates `aws_iam_role.github_actions_terraform`
and `iam_read` — all of them IAM on the CI role's *own* identity, which that role
is not permitted to change. Run it locally once; CI takes over afterwards and
finds nothing to do.

**`plots.world` is an apex domain, so the alias record must be an `ALIAS`, not a
`CNAME`.** A `CNAME` at a zone apex is illegal — it cannot coexist with the SOA
and NS records every zone must have. Dev never met this because it lives on the
`develop.plots.world` subdomain, where an ordinary `CNAME` is fine.

DNS is Squarespace, which supports `ALIAS` as a web-hosting record type, so this
is a non-issue here — but it is the reason phase 2 says `ALIAS` and means it.
The ACM validation record is a normal `CNAME` on a `_`-prefixed subdomain and is
unaffected.

---

## Phase 0 — pre-checks

- [ ] `plots.world` is not already serving something you care about — its apex
      record gets repointed at CloudFront in phase 2. Squarespace installs
      default records for its own site hosting; those are what the `ALIAS`
      replaces.
- [ ] The prod OAuth client exists with **Authorized JavaScript origin
      `https://plots.world`** and no redirect URI (GIS returns the token through
      a popup, so there is no redirect to authorize).
- [ ] GitHub `prod` environment already has: secrets `AWS_OIDC_ROLE_ARN`,
      `AWS_TERRAFORM_ROLE_ARN`, `GCP_SERVICE_ACCOUNT`,
      `GCP_WORKLOAD_IDENTITY_PROVIDER`; variables `FRONTEND_DOMAIN_NAME=plots.world`,
      `VITE_GOOGLE_CLIENT_ID`.
- [ ] Local credentials:

```bash
aws sso login --profile drp-mgmt
aws sso login --profile drp-prod
gcloud auth application-default login
```

---

## Phase 1 — local bootstrap apply

State lives in the management account, so `init` and `apply` use different
profiles.

```bash
cd terraform/environments/prod
AWS_PROFILE=drp-mgmt terraform init -reconfigure -backend-config="profile=drp-mgmt"
```

### 1a. First apply — expect it to stop at CloudFront

Plan to a file and apply that file, so what gets reviewed is exactly what gets
applied:

```bash
AWS_PROFILE=drp-prod terraform plan -out=tfplan \
-var="management_account_id=<MGMT_ACCOUNT_ID>" \
-var="frontend_domain_name=plots.world"
```

Check it before applying: **16 to add, 2 to change, 0 to destroy**, with both
changes being IAM on `github-actions-terraform` — additive, nothing revoked.
Those two are the reason this cannot run in CI.

```bash
terraform show -json tfplan | python3 -c "
import json,sys
for c in json.load(sys.stdin)['resource_changes']:
    a=','.join(c['change']['actions'])
    if a!='no-op': print(f'{a:10} {c[\"address\"]}')
"
```

```bash
AWS_PROFILE=drp-prod terraform apply "tfplan"
```

This apply is expected to **fail part-way**, and that is not a mistake:

> `InvalidViewerCertificate: The specified SSL certificate doesn't exist, isn't
> in us-east-1 region, isn't valid, or doesn't include a valid certificate chain`

There is no `aws_acm_certificate_validation` resource, so Terraform creates the
certificate and moves straight on to CloudFront — but CloudFront will not accept
a certificate still in `PENDING_VALIDATION`, and the certificate cannot validate
until a DNS record exists that names it. Everything not downstream of the
distribution (IAM, GCP service enablement, CloudTrail, the bucket, OAC, the
response-headers policy, the SPA function, the certificate itself) is created and
kept in state.

### 1b. Validate the certificate

Read the record from ACM rather than from `terraform output`: a partial apply
does not reliably refresh outputs, and this works either way.

```bash
AWS_PROFILE=drp-prod aws acm list-certificates --region us-east-1 \
--query "CertificateSummaryList[?DomainName=='plots.world'].CertificateArn" --output text
```

```bash
AWS_PROFILE=drp-prod aws acm describe-certificate --region us-east-1 \
--certificate-arn "<arn from above>" \
--query 'Certificate.{Status:Status,Record:DomainValidationOptions[0].ResourceRecord}'
```

Create that `CNAME` in Squarespace's DNS panel. ACM prints the name fully
qualified (`_329….plots.world.`) but Squarespace's **Host** field appends the
domain itself, so enter only the label — `_329…` — and paste the value as given.
Entering the fully qualified name produces `_329….plots.world.plots.world`,
which is the usual reason validation never completes.

Re-run the same command until `Status` reads `ISSUED` (usually minutes,
occasionally up to an hour). Once the apply completes, the same records are
available as `terraform output frontend_acm_validation_records`.

### 1c. Second apply — creates the distribution

```bash
AWS_PROFILE=drp-prod terraform apply \
-var="management_account_id=<MGMT_ACCOUNT_ID>" \
-var="frontend_domain_name=plots.world"
```

Now only the CloudFront distribution and the S3 bucket policy remain. The
distribution takes several minutes to reach `Deployed`.

---

## Phase 2 — wire up GitHub and DNS

```bash
terraform output
```

```bash
gh secret   set FRONTEND_BUCKET_NAME --env prod --body "<frontend_bucket_name>"
gh variable set FRONTEND_CLOUDFRONT_DISTRIBUTION_ID --env prod --body "<frontend_cloudfront_distribution_id>"
```

The bucket name is a secret because it embeds the AWS account id; the
distribution id is a variable. `frontend_bucket_name` prints as `<sensitive>` in
the summary — read it with `terraform output -raw frontend_bucket_name`.

Then point the apex at the distribution. In Squarespace's DNS panel, add a
record of type **ALIAS** with **Host `@`** and **Data** set to the
`frontend_cloudfront_domain` value (`d….cloudfront.net`), removing the default
Squarespace web-hosting records for `@`.

Confirm it resolves to CloudFront rather than to Squarespace before merging:

```bash
dig +short plots.world
dig +short plots.world | xargs -I{} dig +short -x {} | head -3
```

The addresses should reverse-resolve into `cloudfront.net`. Propagation is
usually quick but the old records' TTL applies.

---

## Phase 3 — hand over to CI

`origin/main` was still at the initial commit, so this was effectively its first
real merge — ~975 commits. A required approving review with `enforce_admins`
off means the repo admin merges it with `gh pr merge --admin`; nobody can
approve their own pull request.

```bash
gh pr create --base main --head develop --title "Production cutover" --body "..."
```

On merge, two workflows run:

| Workflow | Job | Expected |
|---|---|---|
| Terraform CI | `apply-prod` | **0 added, 0 changed, 0 destroyed** — phase 1 already did the work. Any diff here means the local apply and CI disagree; stop and investigate. |
| Web CI | `deploy-prod` | Builds with the prod `VITE_GOOGLE_CLIENT_ID`, syncs `dist/` to S3, invalidates CloudFront. |

`apply-prod` succeeding is also the proof that the bootstrap worked: it is the
first time the CI role uses the IAM policies it could not have created itself.

---

## Phase 4 — verify

- [ ] `https://plots.world` serves the app, and the certificate is the ACM one.
- [ ] Response headers carry the CSP, HSTS, `Cross-Origin-Opener-Policy:
      same-origin-allow-popups` and `Permissions-Policy`:

```bash
curl -sSI https://plots.world | grep -iE "content-security-policy|strict-transport|cross-origin|permissions-policy|x-frame"
```

- [ ] Sign in as a test user (the consent screen is still in Testing, so only
      listed test users can). Confirm the consent screen shows **name/picture and
      Drive only** — no email.
- [ ] Run a sync. The second consent screen appears, showing `gmail.readonly`.
- [ ] Copy plots. **No account chooser should appear** — the sync token covers it.
- [ ] `/privacy.html` and `/about.html` render with their stylesheets.
- [ ] Logout, then sign in again: the consent screen reappears, proving revoke
      reached `oauth2.googleapis.com` through the CSP.

---

## Phase 5 — immediately after

**Check the Gmail quota in the prod project**, under APIs & Services → Gmail API
→ Quotas. A project that has never called the API may sit on the post-May-2026
limits (**6,000** units/min with `threads.get` at **40**) rather than dev's
grandfathered 15,000/10 — ten times stricter. If it does, change
`QUOTA_UNITS_PER_MINUTE` and `THREADS_GET_UNITS` at the top of
`apps/web/src/sync/engine.ts`; `MIN_BATCH_INTERVAL_MS` is derived from them and
a test guards the arithmetic. Do not tune the batch size and the interval
independently.

*Checked 2026-08-19: prod reports 15,000, the same grandfathered set as dev, so
no change was needed. The first production sync then measured the unit cost —
zero quota errors and a graph peaking a little over 10,000 units/min, which only
works out at 10 units a call.* Do the same on any new project: the pre-May-2026
cost table is not published, so a full sync under the console's usage graph is
the only way to check.

Then the verification track resumes: **D3** (verify `plots.world` in Search
Console and add it to Authorized domains) → **D4** (fill in the consent screen,
including the homepage and privacy-policy URLs left blank until now) → **D6**
(record the demo video against prod — see `oauth-demo-video.md`) → **D7**
(submit, and set Publishing status to In production).

---

## Troubleshooting

**`frontend_domain_name must not be empty`** — the variable did not reach
Terraform. Locally that means the `-var` flag is missing; in CI it means the
environment variable `FRONTEND_DOMAIN_NAME` is unset for that environment. The
validation exists because an empty value is accepted as real and would replace
the certificate and strip the CloudFront alias.

**CloudTrail fails on the bucket policy** — `drp-prod` writes to `drp-cloudtrail`
in the management account. The policy in `terraform/environments/management`
already lists `var.prod_account_id`; confirm that environment has been applied
since that line was added.

**`apply-prod` fails on IAM in CI** — the bootstrap did not happen, or ran
against different code. The CI role cannot edit its own policies; re-run phase 1
from the same commit that is on `main`.

**Certificate stuck in `PENDING_VALIDATION`** — check the record name and value
character for character, and that no CNAME-flattening on the zone is rewriting
it. ACM re-checks periodically; nothing needs re-applying.

**`deploy-prod` fails at `aws s3 sync`** — `FRONTEND_BUCKET_NAME` is unset for
the prod environment (phase 2).

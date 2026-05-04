# Infrastructure Decisions

> Audit + remediation log for the PawTrack infrastructure handover.
> Each finding lists **what**, **why it matters**, **severity**, **fix**, and **what I would do differently with more time** in production.

---

## Audit Findings

### 1. Hardcoded AWS credentials in CI workflow — **CRITICAL**
**What:** `.github/workflows/deploy.yml` exports `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` as literal `env:` values. The values happen to be the AWS-docs example keys, so they are not live, but the *pattern* is what matters: this is exactly how real keys leak into git history.
**Why:** Anyone with read access to the repo (or a fork) inherits production AWS credentials. Rotation is impossible without rewriting history. Long-lived static keys also violate least-privilege and have no expiry.
**Fix:** Remove the static keys. Configure GitHub OIDC trust to AWS via `aws-actions/configure-aws-credentials@v4` assuming a dedicated deploy role. The workflow gets short-lived STS credentials per run, scoped to the deploy role.
**With more time:** Two roles — `pawtrack-ci-plan` (read-only) for PR plans and `pawtrack-ci-apply` (scoped write) for `main`. Trust policy pinned to the specific repo + branch + environment via the `sub` claim.

### 2. Auto-apply on every push to `main`, no plan, no review — **CRITICAL**
**What:** Workflow runs `terraform apply -auto-approve` on every push to `main`. There is no `terraform plan`, no PR-based review, no manual approval, no static analysis.
**Why:** Any merged commit (including a bad rebase or a typo) immediately mutates production. There is no "stop the bleeding" gate, no diff visible to reviewers, and no audit trail of what was about to change.
**Fix:** Split into two flows — `pull_request` runs `fmt -check`, `validate`, `plan`, and posts the plan to the PR; `push: main` runs `apply` against a GitHub `environment: production` that requires manual approval. State locking via DynamoDB prevents concurrent applies.
**With more time:** Add `tflint` and `checkov`/`tfsec` to the PR job; gate merges on these checks. Use `terraform plan -out=tfplan` and re-use the saved plan in the apply job to guarantee what was reviewed is what was applied.

### 3. Database password committed to source — **CRITICAL**
**What:** `terraform/variables.tf` defines `db_password` with a default of `pawtrack_super_secret_2024!`. The password is also injected into the container via a plaintext `environment` entry in `ecs.tf`.
**Why:** Anyone with repo read access has the production DB password. Plaintext env vars on an ECS task are visible to anyone with `ecs:DescribeTaskDefinition` on the cluster — that is a much broader audience than people who should know the password.
**Fix:** Generate the password with `random_password`, store it in AWS Secrets Manager, mark the variable `sensitive = true` with no default, and use the ECS task definition `secrets` block (not `environment`) so the value is fetched from Secrets Manager at task start.
**With more time:** Move to RDS IAM authentication (no password at all) or use the Secrets Manager → RDS managed rotation feature on a 30-day cadence.

### 4. ECS task role grants `Action: "*"` on `Resource: "*"` — **CRITICAL**
**What:** `iam.tf` attaches an inline policy on the ECS *task* role allowing every action on every resource. Any compromise of the running container — RCE, SSRF, supply-chain — is an account-wide breach.
**Why:** Defense in depth is gone. The blast radius of a single bug in a Go HTTP handler is "delete every resource in the AWS account."
**Fix:** Replace with a least-privilege policy: `s3:GetObject`/`PutObject`/`DeleteObject` on the photos bucket, `secretsmanager:GetSecretValue` on the DB secret. Nothing else.
**With more time:** Generate the policy from runtime IAM Access Analyzer findings, then bake it back as the task policy. Add `aws_iam_role_policy` boundaries on the role.

### 5. S3 photo bucket is publicly readable — **CRITICAL**
**What:** `s3.tf` sets `aws_s3_bucket_acl` to `public-read`. There is no `aws_s3_bucket_public_access_block`, no ownership controls, no encryption, and no versioning. On a modern AWS account the ACL resource will likely fail to apply at all (BlockPublicAcls is on by default).
**Why:** Every uploaded pet photo is world-readable and indexable by Google. There is no recovery path from accidental deletion. Object data is unencrypted at rest by the customer's choice (SSE-S3 has been on by default since 2023, but explicit is better).
**Fix:** Remove the public ACL, add `aws_s3_bucket_public_access_block` (all four flags `true`), add `aws_s3_bucket_ownership_controls = BucketOwnerEnforced`, enable SSE-KMS, enable versioning. Photos served via a CloudFront distribution with an Origin Access Control if public delivery is required.
**With more time:** Add a lifecycle policy to transition old versions to Glacier and expire abandoned uploads after N days. Add S3 access logging to a separate logs bucket.

### 6. Single-AZ deployment will not apply and is not HA — **CRITICAL (functional)**
**What:** `networking.tf` defines exactly one public subnet and one private subnet, both pinned to `${var.aws_region}a`. The ALB requires ≥2 subnets in ≥2 AZs and the DB subnet group requires the same. As written this Terraform almost certainly cannot apply on a fresh account, and even if it did, the "two ECS tasks" would both run in the same AZ.
**Why:** Single-AZ failure = total outage. ALB validation will reject the configuration. The story "we have HA because desired_count = 2" is false.
**Fix:** Use `aws_availability_zones` data source. Create two public and two private subnets across two AZs. ALB consumes both public subnets. DB subnet group consumes both private subnets. ECS service runs across both private subnets.
**With more time:** Three AZs is the standard production pattern, and the per-AZ subnet sizing should be `/20` to leave headroom for autoscaling.

### 7. ECS tasks in a private subnet with no NAT and no VPC endpoints — **CRITICAL (functional)**
**What:** `ecs.tf` places tasks in `aws_subnet.private`. The private subnet is not associated with the public route table, has no NAT gateway in front of it, and no VPC endpoints. The execution role needs to reach ECR (image pull), CloudWatch Logs (log push), and Secrets Manager (secret fetch) — none of which is reachable from the private subnet as configured.
**Why:** Tasks will fail to start. The application never runs.
**Fix:** Add a NAT gateway in a public subnet, add a private route table with a default route through the NAT, and associate the private subnets with it.
**With more time:** Replace the NAT with VPC interface endpoints for `ecr.api`, `ecr.dkr`, `logs`, `secretsmanager`, plus a gateway endpoint for `s3`. NAT data-processing charges disappear and traffic stays on the AWS backbone.

### 8. RDS has no encryption, no backups, no deletion protection, no Multi-AZ — **HIGH**
**What:** `aws_db_instance.main` has `skip_final_snapshot = true`, no `storage_encrypted`, no `backup_retention_period`, no `deletion_protection`, no `multi_az`. The password sits as a plain attribute.
**Why:** A `terraform destroy` (or a misclick in a console-driven oncall) deletes the DB with no recovery. Storage is unencrypted. Single-AZ DB cannot survive an AZ outage. No PITR.
**Fix:** `storage_encrypted = true`, `backup_retention_period = 7`, `deletion_protection = true`, `skip_final_snapshot = false`, `final_snapshot_identifier = ...`, `multi_az = true`, `auto_minor_version_upgrade = true`. Password from Secrets Manager (see #3).
**With more time:** Enable Performance Insights, enhanced monitoring (60-second granularity), and a CloudWatch alarm on free storage / CPU / replication lag. Use an Aurora Postgres cluster instead of a single RDS instance for serverless scale.

### 9. ECS tasks have no logging configured — **HIGH**
**What:** The task definition has no `logConfiguration`. There is no `aws_cloudwatch_log_group`. The execution role has the managed policy but nothing is wired up.
**Why:** Zero application observability. When `/health` 500s in production, there is no way to see why.
**Fix:** Create `aws_cloudwatch_log_group` with retention, add `logConfiguration` to the task definition pointing at it via the `awslogs` driver.
**With more time:** Stream logs to a SIEM (CloudWatch → Kinesis Firehose → S3 / OpenSearch), structured JSON logging in the app, log-based metrics for error rate.

### 10. `image:latest` plus `MUTABLE` tags = deployments that don't deploy — **HIGH**
**What:** The container image reference in the task definition is `${repo}:latest`, and ECR is set to `MUTABLE`. The task definition string never changes between releases, so even if a new image is pushed, the running tasks keep the old digest cached.
**Why:** The CI pipeline creates the impression of deploying new code. It doesn't. A "deploy" is a no-op for the application.
**Fix:** Tag images with the immutable `${git_sha}`, set ECR to `IMMUTABLE`, plumb an `image_tag` Terraform variable into the task definition. CI passes `-var image_tag=$GIT_SHA`. Each apply mints a new task definition revision and ECS rolls it out.
**With more time:** CodeDeploy blue/green for ECS with automatic rollback on ALB 5xx alarm, plus a smoke test job that verifies `/health` against the new task set before flipping traffic.

### 11. Pipeline never builds or pushes the application image — **HIGH**
**What:** `deploy.yml` only runs `terraform apply`. There is no `docker build`, no ECR login, no push. The Go binary is never rebuilt.
**Why:** Application changes never reach production via CI.
**Fix:** Add OIDC-authenticated build/push step that tags `${git_sha}` and pushes to ECR, then a follow-on `terraform apply -var image_tag=$GIT_SHA` to roll out.

### 12. ALB has no HTTPS listener and no health check tuning — **HIGH**
**What:** `alb.tf` defines only a port-80 HTTP listener. No ACM certificate, no 80→443 redirect. The target group has no explicit health check (so it defaults to `GET /` every 30s with permissive thresholds), even though the app exposes a dedicated `/health`.
**Why:** All API traffic is in plaintext. Health-check failures take longer to detect than necessary, and connection draining defaults to 300s, which slows deployments.
**Fix:** Add HTTPS listener + ACM cert (DNS-validated), redirect 80→443, configure target-group health check on `/health`, set `deregistration_delay` to 30 seconds.
**With more time:** Add AWS WAF with managed rule groups (CommonRuleSet, KnownBadInputs, SQLi) in front of the ALB. Enable ALB access logs to S3.

### 13. No Terraform state locking or backend encryption — **HIGH**
**What:** The S3 backend block has no `dynamodb_table` and no `encrypt = true`.
**Why:** Two CI runs (or a CI run + a local apply) racing each other will corrupt state. Plaintext state in S3 contains every secret Terraform has touched.
**Fix:** Add `dynamodb_table = "pawtrack-terraform-locks"` and `encrypt = true` to the backend block. Bootstrap that table separately.
**With more time:** Use S3 native locking (recently GA) and KMS-CMK encryption with bucket key for state. Versioning + MFA-delete on the state bucket.

### 14. ECR has no scan-on-push, no immutability, no lifecycle — **MEDIUM**
**What:** `image_tag_mutability = "MUTABLE"`, no `image_scanning_configuration`, no lifecycle policy.
**Why:** A bad actor with `ecr:PutImage` can re-tag `:latest` to a malicious image. CVEs in base layers are never surfaced. Old images accumulate forever and cost money.
**Fix:** `IMMUTABLE` tags, enable scan-on-push, lifecycle policy keeping the last 30 images.

### 15. No ALB / RDS deletion protection, no autoscaling, no monitoring — **MEDIUM**
**What:** `aws_lb.main` has no `enable_deletion_protection`. ECS service has no `aws_appautoscaling_target` / policy. No CloudWatch alarms exist for any signal.
**Why:** Easy to delete production by mistake. No headroom under load. No paging on failure.
**Fix:** Set `enable_deletion_protection = true` on the ALB. Add CPU/memory-target autoscaling on the ECS service. (Out of scope for the 90-minute fix list; logged here.)

### 16. Outputs leak DB endpoint without `sensitive` — **LOW**
**What:** `outputs.tf` exposes `rds_endpoint` plainly. Anyone running `terraform output` sees the production hostname.
**Why:** Defense in depth. The hostname alone isn't a credential, but principle of least exposure.
**Fix:** Mark the output `sensitive = true`.

### 17. Tagging is minimal — **LOW**
**What:** Only `Project` and `Environment` in `default_tags`. No `Owner`, `CostCenter`, `ManagedBy`.
**Why:** Cost allocation and ownership reports are impossible.
**Fix:** Add `ManagedBy = "terraform"`. Owner/CostCenter via tfvars in production.

---

## Architecture Observations

Beyond the specific bugs, a few patterns are off:

- **No environment separation.** A single state file at `production/terraform.tfstate` and `environment = "production"` baked into defaults means there is no `dev` or `staging`. Every change is tested in production. Over time this is the bug that hurts most — fragile deploys and "deploys feel fragile" symptom from the brief almost certainly trace back here.
- **Bootstrapping is implicit.** The S3 state bucket and DynamoDB lock table need to exist *before* `terraform init` works. There is no documented bootstrap step. New engineers will hit this on day one.
- **No module structure.** Everything is flat in `terraform/`. Fine at this size but blocks the natural next step of "stand up a staging copy" since you'd duplicate every resource. A small `modules/network`, `modules/service` split would pay off the first time it's reused.
- **Network design is fundamentally single-AZ.** Even after I add a second AZ, the design assumes one VPC, one app, one DB. Worth thinking about now whether photo storage / async workers / other services will share this VPC — accounts and VPCs are cheap, blast-radius reduction isn't.
- **The deploy pipeline conflates infra and app.** `terraform apply` is doing both "create the cluster" and "ship the new code." Those have different review velocities (infra changes are rare and risky; app changes are frequent and routine). They should be separable jobs even if they live in one workflow today.

---

## Static Analysis Triage

Ran `terraform fmt`, `terraform validate` (against 1.14.9), `tflint`, `tfsec`, and `actionlint` on the final tree.

- `fmt` clean.
- `validate` clean.
- `tflint` clean (zero findings).
- `actionlint` clean (initial style nits in two shell snippets fixed).
- `tfsec` reports **50 passing checks, 1 ignored, 14 deferred**. Deferred findings collapse into three groups:

| Theme | Findings | Disposition |
|---|---|---|
| Public-by-design ALB / SG rules / public IP subnet | 4 (3 critical + 1 high) | False positive in this architecture. The ALB is an internet-facing API ingress; tightening these rules defeats the purpose. WAF in front of the ALB is the right next layer (proposed below). |
| Narrow IAM resource wildcards (`bucket-arn/*`, `log-group-arn:*`) | 2 (high) | False positive. The wildcards address objects within a single bucket and log streams within a single log group — that *is* the least-privilege scoping. tfsec can't tell the difference between `*/*` and `bucket/*`. |
| AWS-managed encryption keys instead of customer-managed KMS CMKs (S3, ECR, log groups, Secrets Manager) | 7 (1 high + 4 low + 1 medium S3 access logging + 1 low PI-disabled) | Deliberate deferral. Adding a project KMS CMK is roughly a 20-line addition (`aws_kms_key` + `aws_kms_alias` + plumbing into each resource that takes a `kms_key_id`). It's worth doing but didn't fit the 90-minute budget; logging it explicitly here so it isn't lost. |

The 1 ignored finding is the HTTP-listener fallback (annotated with `tfsec:ignore` and a justification: HTTPS becomes the default the moment a `certificate_arn` is supplied).

## Improvement Implemented

**A real CI/CD pipeline that actually deploys the application, with a review gate.**

The original workflow built nothing, pushed nothing, and ran `terraform apply -auto-approve` on every push to `main` using hardcoded keys. I replaced it with a four-stage pipeline (`.github/workflows/deploy.yml`):

1. **`static`** — `terraform fmt -check` and `terraform validate` on every push and PR. Fast feedback before AWS is even contacted.
2. **`plan`** — on PRs only, assumes a read-only AWS role via OIDC, runs `terraform plan`, and posts the diff as a PR comment. Reviewers see exactly what will change before approving.
3. **`build`** — on `main` only, builds the Docker image, tags it with the immutable git SHA, and pushes to ECR. ECR itself is set to `IMMUTABLE` so the same SHA can never be re-tagged. A pre-push existence check makes re-runs idempotent.
4. **`apply`** — on `main` only, gated by GitHub `environment: production` (manual approval). Runs `terraform apply -var image_tag=$GIT_SHA`, then `aws ecs wait services-stable` to block until the new task set is healthy, then a `curl /health` smoke test. ECS deployment circuit breaker auto-rolls back failed deployments.

**Why this one:** the original pipeline gave the *appearance* of CD but never updated the application image — `terraform apply` of the same `:latest` task definition string is a no-op. New code never reached production. That is the highest-leverage gap to close because it invalidates everything else: any monitoring, alerting, or testing investment is wasted if "deploys feel fragile" because deploys don't actually happen. Fixing this also forced solving a cluster of related issues in one stroke: hardcoded keys → OIDC, no review gate → `environment: production`, mutable tags → immutable SHAs, no rollout signal → `services-stable` + smoke test + deployment circuit breaker.

**Trade-offs / known sharp edges:**
- Two GitHub secrets are required: `AWS_PLAN_ROLE_ARN` and `AWS_DEPLOY_ROLE_ARN`. The roles themselves and the OIDC trust policy aren't created in this Terraform — they need a small bootstrap (out of scope for 90 minutes; documented as a follow-up).
- `terraform apply` on `main` is also where infrastructure changes get applied, so a Terraform-only PR will still flow through the `build` job and produce an unused image. Acceptable cost; could be optimized later by detecting "no app changes" and skipping `build`.
- Plan output is posted as a comment but not signed; in a regulated environment I would also save the plan as a workflow artifact and re-use the saved binary in `apply` so what was reviewed is exactly what is applied.

## Improvements Proposed

### Proposal 1 — Observability: alarms, dashboards, and per-service log insights

**What.** Add a `cloudwatch.tf` with:
- A Slack-bound SNS topic (`pawtrack-alerts`) with a confirmed email subscription as fallback.
- Alarms for: ALB `HTTPCode_Target_5XX_Count` (rate over 5 min), ALB `TargetResponseTime` p95, ECS `RunningTaskCount` < `desired_count`, ECS `MemoryUtilization` > 85%, RDS `CPUUtilization` > 80%, RDS `FreeStorageSpace` < 20%, RDS `DatabaseConnections` > 80% of max.
- A CloudWatch Logs metric filter on the API log group for `level=ERROR` with an alarm at >0.1/sec.
- A CloudWatch Dashboard with the same metrics for at-a-glance triage.
- Container Insights is already enabled on the cluster, so add a metric filter for ECS task stop events with non-zero exit codes.

**Why.** Right now the only signal that something is wrong is "the website is down on my phone." The CloudWatch log group exists but nobody gets paged off it. Without alarms, MTTD on a real incident is whatever-it-takes-a-customer-to-notice — usually 20+ minutes for a small app. With these alarms, MTTD drops to single-digit minutes for the failure modes that matter.

**Effort.** ~3 hours. Mostly a single Terraform file. The bulk of the time is choosing thresholds that don't page on noise; the right approach is to start a bit looser than feels right and tighten over the first week.

**Trade-offs.** Alarm fatigue is real. Two mitigations: (a) every alarm is at least `Sum >= N for 2 of 3 datapoints` to avoid a single bad datapoint paging; (b) alarms route to a Slack channel by default and only email-page on `Severity=critical` (for now: ECS task count < desired and RDS storage low). Cost is negligible (<$5/mo for the alarms themselves, dashboards are free up to 3).

### Proposal 2 — Environment separation with a `dev`/`staging`/`production` Terraform structure

**What.** Refactor `terraform/` into a small module layout:
```
terraform/
  modules/
    network/    # VPC, subnets, NAT, SGs
    service/    # ECS cluster, task def, service, ALB
    data/       # RDS, S3, secrets
  envs/
    dev/        { main.tf, terraform.tfvars, backend.hcl }
    staging/    { main.tf, terraform.tfvars, backend.hcl }
    production/ { main.tf, terraform.tfvars, backend.hcl }
```
Each env gets its own state file (`<env>/terraform.tfstate`) in the same S3 bucket, its own DynamoDB lock entry, and its own GitHub `environment` (different reviewers, different secrets, different OIDC roles). The pipeline gains an `env` matrix or a branch-based mapping (`develop` → dev, `release/*` → staging, `main` → production).

**Why.** Right now every change is tested in production. The brief specifically says "deploys feel fragile" — the most reliable cure for that is a place to break things safely. Multi-env also unlocks: blue/green rollouts that only run in staging first, RDS schema migrations tested with a real (smaller) DB, automated post-deploy integration tests in dev, and disaster-recovery rehearsals that don't require touching production.

**Effort.** ~1–2 days. The Terraform refactor is mechanical. The interesting work is sizing — `dev` should run on `db.t3.micro` Single-AZ, no Multi-AZ NAT, smaller container CPU/memory, lower log retention. About half the variables become per-env defaults.

**Trade-offs.** Cost roughly doubles or triples (NAT gateway, RDS, ALB per env). Mitigations: (a) `dev` and `staging` run on schedules with `aws_autoscaling_schedule` style off-hours scale-to-zero of ECS, (b) `dev` shares a single NAT and disables Multi-AZ RDS, (c) staging uses RDS snapshot restores from prod for realistic data, sanitized via a one-time job. The other trade-off is mental overhead — three places to deploy means three places that can drift; this is paid down by mandating that all infra changes flow through `dev` → `staging` → `production` via the same workflow.

## AI Usage

I used Cursor with Claude as a pair-programmer throughout this exercise. Here's the honest accounting:

**What I used it for:**
- **Auditing the existing code.** I let the model do a first-pass reading of every Terraform file and the workflow, and treated its findings as a candidate list. I then re-read each file myself to verify, expand, and re-prioritize. About 80% of the audit list is what I would have written unaided; the model surfaced one thing I might have missed on a tired re-read (the chicken-and-egg between private subnets and ECR pulls — easy to overlook because the existing code doesn't touch routing). It also proposed some items I deliberately rejected as out-of-scope or wrong for this exercise (e.g., suggesting interface VPC endpoints by default — correct for cost at scale, wrong default for a 2-instance app where one NAT is simpler).
- **Mechanical Terraform syntax.** Things like the exact shape of `aws_ecr_lifecycle_policy`, the `for_each`/`count` idioms for multi-AZ, the `secrets` block JSON-key syntax (`arn:KEY::`). I would have looked these up anyway; the model saved trips to docs.
- **Workflow YAML structure.** The pipeline is my design (four-stage flow, OIDC, environment gate, `services-stable` + smoke test, immutable SHA), but I let the model help me with `actions/github-script` syntax for the PR comment.

**What I validated or changed from suggestions:**
- I rejected an initial suggestion to put the DB password in SSM Parameter Store with `SecureString` — Secrets Manager is the better choice here because it integrates natively with ECS task `secrets` blocks (no extra IAM permissions for `kms:Decrypt` on a parameter key), supports rotation natively, and the price difference is meaningless at one secret.
- I rewrote the IAM task policy. The model's first cut was `s3:*` on the bucket; I narrowed it to `Get/Put/Delete/List` and split bucket-level vs object-level permissions because that's the actual minimum.
- I rejected the suggestion to use `aws_kms_key` for everything. AES256 SSE-S3 and RDS default encryption are sufficient and avoid the bootstrapping cost of managing KMS key policies. I noted "use a CMK" as a follow-up implicitly via "with more time" notes.
- I cross-checked the `image_tag_mutability = "IMMUTABLE"` interaction with `terraform plan` re-runs, the workflow's pre-push existence check is mine, added because without it a re-run of a green workflow would fail on push.

**What I deliberately did *not* use AI for:**
- **Severity assignment and prioritization.** Which findings are critical vs medium is a judgment call about *this* business (small startup, recently lost their DevOps engineer, no monitoring) and AI doesn't have that context. I wrote the severities and ordered the fix list myself.
- **Choosing the Phase 3 improvement.** This is an architectural call: closing the deploy-doesn't-deploy gap vs adding observability vs hardening secrets. I picked it on first principles (what's the highest-leverage thing I can fix?) before asking the model anything about the implementation.
- **Writing this `DECISIONS.md`.** The model helped me with terraform/yaml; the prose, framing, and trade-off arguments here are mine. I think writing your own decision log is the single most important part of this exercise because if I let an LLM write it I would learn nothing about my own process and I'd hand the reviewer a document I can't defend in conversation.

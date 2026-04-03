# PawTrack DevOps Challenge

## The Scenario

You're joining **PawTrack**, a pet-sitting startup that connects pet owners with local sitters. The company has a small engineering team and recently lost its only DevOps engineer. You're the first dedicated infrastructure hire.

The previous engineer set up AWS infrastructure using Terraform and a GitHub Actions deployment pipeline. Things are running, but the team suspects there are problems -- deploys feel fragile, and nobody is confident the infrastructure follows best practices.

Your job: **audit what exists, fix what's broken, and propose improvements.** The codebase is intentionally small so you can focus on infrastructure quality rather than application complexity.

## Time Limit

**90 minutes.** We value thoughtfulness over completeness. It's better to fix fewer things well and explain your reasoning than to rush through everything. Document your decisions as you go in `DECISIONS.md`.

## What You'll Find

```
pawtrack-devops-challenge/
  app/                          # Go health-check API (do NOT modify)
  terraform/                    # Infrastructure-as-code (this is your focus)
  .github/workflows/deploy.yml  # CI/CD pipeline (this is your focus)
  DECISIONS.md                  # Your working document
```

The health-check application uses Go because it compiles to a small static binary, keeping the Dockerfile trivial. Your focus should be on infrastructure and CI/CD, not application code. **Do not modify anything in `app/`.**

## The Three Phases

### Phase 1: Audit (suggested: ~25 minutes)

Review all Terraform files and the GitHub Actions workflow. Document every issue you find in `DECISIONS.md`, including:

- What the issue is
- Why it matters (security risk, reliability impact, operational concern)
- Severity (critical / high / medium / low)

Don't fix anything yet. Just document.

### Phase 2: Fix (suggested: ~40 minutes)

Fix the issues you found. Prioritize by severity -- start with the most critical problems. Make your changes directly in the Terraform and workflow files.

For each fix, update `DECISIONS.md` with what you changed and why.

### Phase 3: Improve (suggested: ~25 minutes)

Choose **one** meaningful improvement to implement beyond fixing bugs. This could be adding monitoring, improving the deployment pipeline, hardening security, or anything else you think matters most. Implement it in code.

Then **propose two additional improvements** you would make given more time. Write these up in `DECISIONS.md` with enough detail that another engineer could implement them: what, why, estimated effort, and trade-offs.

## Getting Started

1. Clone this repository
2. Review `terraform/` -- read every file carefully
3. Review `.github/workflows/deploy.yml`
4. Review `app/` to understand what's being deployed (but don't change it)
5. Open `DECISIONS.md` and start documenting

## What We're Evaluating

| Area | What We're Looking For |
|---|---|
| **Security awareness** | Can you identify and fix security issues in infrastructure code? |
| **Reliability & architecture** | Do you understand high-availability patterns and failure modes? |
| **CI/CD best practices** | Can you build a safe, repeatable deployment pipeline? |
| **Operational maturity** | Do you think about logging, monitoring, and day-2 operations? |
| **Decision-making** | Can you prioritize, make trade-offs, and explain your reasoning? |

We're not looking for perfection. We're looking for someone who thinks critically about infrastructure, understands the "why" behind best practices, and communicates clearly.

## AI Usage Policy

You may use AI tools (ChatGPT, Copilot, Claude, etc.). If you do, document your usage honestly in `DECISIONS.md`:

- Which tools you used and how
- What you validated or changed from AI suggestions
- What you chose **not** to use AI for and why

We assess critical thinking about AI output, not whether you used it. Blindly pasting AI suggestions without understanding them is worse than not using AI at all.

## Submission

<!-- Submission instructions will be provided separately -->

When you're done, make sure all your changes are committed and your `DECISIONS.md` is complete. Push to your fork or submit as instructed.

## Technical Requirements

- [Terraform](https://www.terraform.io/) >= 1.5.0
- [AWS Provider](https://registry.terraform.io/providers/hashicorp/aws/latest/docs) ~> 5.0
- [GitHub Actions](https://docs.github.com/en/actions)
- Familiarity with AWS services: VPC, ECS/Fargate, RDS, ALB, S3, IAM

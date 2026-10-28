# Ephemeral GitHub Actions Runners on AWS EC2

## Architecture

The design uses one short-lived EC2 instance for each dispatched workflow run. A GitHub-hosted bootstrap job assumes a narrowly scoped AWS role through GitHub OIDC, prepares a short-lived runner registration token in SSM Parameter Store, and launches the instance. The instance registers as an ephemeral runner, executes one job, and terminates. A GitHub-hosted cleanup job handles failures that prevent the instance from self-terminating.

Terraform also provisions a separate persistent Amazon Linux agent instance. It uses its own IAM instance profile for Systems Manager access and restricted S3 object operations; it is not used as the GitHub Actions runner.

```text
GitHub workflow_dispatch
				|
				v
GitHub-hosted bootstrap job
	|  GH_TOKEN -> create runner registration token
	|  GitHub OIDC -> AWS STS AssumeRoleWithWebIdentity
	|  SSM SecureString + EC2 RunInstances
	v
EC2 launch template -> user data bootstrap
	|  instance profile -> retrieve one-time registration token
	v
Ephemeral runner (--ephemeral) -> one build/test/deploy job
	|  runner exits -> local shutdown/termination
	v
GitHub-hosted cleanup job -> terminate instance on failure or timeout
```

The organization `GH_TOKEN` secret is used to request the GitHub runner registration token. AWS OIDC authenticates the bootstrap job to AWS, but does not authorize GitHub runner management.

## Workflow and runner lifecycle

1. A `workflow_dispatch` starts on a GitHub-hosted runner. The bootstrap job obtains AWS credentials through OIDC and uses the organization `GH_TOKEN` secret, which must have repository Administration: write permission, to manage repository runners.
2. The bootstrap job requests a runner registration token from GitHub, stores it as an SSM `SecureString` under a unique path for this workflow run, and launches the EC2 instance from a launch template. Pass the unique parameter name as user data; never put the token itself in user data or logs.
3. Instance user data installs or starts the pinned runner version, retrieves the parameter using its instance profile, removes the parameter, and configures the runner with `--ephemeral`. Add a unique run-specific label so the build job can target the runner created for that run.
4. The build/test/deploy job depends on bootstrap and targets that unique label. The ephemeral runner accepts one job and deregisters after it completes.
5. After the runner process exits, the instance shuts itself down; configure the launch template's instance-initiated shutdown behavior to `terminate`. A workflow `always()` cleanup job terminates the recorded instance if bootstrap, registration, scheduling, or the job fails. Add an independent orphan-instance and stale-parameter cleanup mechanism because workflow cleanup is not guaranteed to run (for example, if the workflow is canceled).

Runner registration tokens expire quickly. Create them immediately before launch, use a unique parameter per run, and delete the parameter after retrieval. Parameter Store has no native TTL, so stale parameters need explicit cleanup. Configure workflow and instance timeouts to bound pending runners and jobs.

## Security boundaries

- Restrict the IAM role trust policy to the intended GitHub organization, repository, branch or environment, and the `sts.amazonaws.com` audience. Grant the bootstrap role only the required EC2 launch/describe/terminate actions, access to the relevant SSM parameter path, and `iam:PassRole` for the runner instance profile.
- Give the ephemeral runner profile only `ssm:GetParameter` for its run-specific parameter and the required KMS decrypt permission. The separate persistent agent role has S3 access limited to `agent_s3_prefix` and Systems Manager permissions for Session Manager. Do not give either instance broad AWS permissions.
- Store `GH_TOKEN` as a GitHub Actions secret, grant it only the repository runner-management permissions needed, restrict its organization-secret repository access, and avoid printing credentials or runner tokens.
- Require IMDSv2, encrypt the root volume, use a security group with no inbound access, and limit outbound access to GitHub and required AWS services. Prefer private subnets and VPC endpoints where practical.
- Do not run untrusted pull-request code on runners that can access deployment credentials or sensitive networks. Use a dedicated AWS account or isolated environment for workloads with different trust levels.
- Pin the AMI, runner version, and bootstrap dependencies; apply instance tagging that records the repository and workflow run for cleanup and auditing.

## Operational checks

- Confirm the bootstrap role can launch only the intended launch template and pass only the runner instance role.
- Verify a normal run registers one runner, executes one job, deregisters it, and terminates its EC2 instance.
- Test launch failure, registration failure, job timeout, workflow cancellation, and cleanup failure; verify the orphan cleanup removes leftover instances and parameters.
- Alarm on runner startup time, pending-job duration, failed launches, and instances that exceed their maximum lifetime.

## Deploy and run

### Prerequisites

- An AWS account with permissions to create IAM roles and policies, an EC2 launch template and security group, an OIDC provider, a Lambda function, and an EventBridge schedule.
- Terraform creates a `makrsoft`-prefixed VPC, public subnet, internet gateway, route table, route-table association, and security group. The chosen design assigns public IPv4 addresses for outbound GitHub and Systems Manager access; the security group has no inbound rules.
- Separate globally unique S3 bucket names for application objects and Terraform state. Example names include the AWS account ID suffix but must still be checked for availability because S3 names are global.
- Terraform 1.17.0 or later. For the CI-only setup, an AWS account administrator must bootstrap the state bucket, lock table, GitHub OIDC provider, and Terraform deployment role in account `783161622588`; the GitHub workflow then uses OIDC. The repository enforces this account ID and Terraform version.
- An organization-level `GH_TOKEN` secret accessible to this repository. The token must have repository Administration: write permission to create and delete repository runners.

### Provision AWS resources

For the CI-only bootstrap, an AWS account administrator must first create these prerequisites in account `783161622588` (the Terraform workflow cannot create its own backend or the role needed to start):

1. In `ap-southeast-2`, create the S3 state bucket `makrsoft-terraform-state-s3-783161622588` if that global bucket name is available. Enable block-public-access, versioning, and SSE-S3 encryption. Create DynamoDB table `makrsoft-terraform-state-s3-783161622588-lock` with partition key `LockID` (String) and on-demand billing.
2. In IAM, add the GitHub Actions OIDC identity provider `https://token.actions.githubusercontent.com` with audience `sts.amazonaws.com`. Its expected ARN is `arn:aws:iam::783161622588:oidc-provider/token.actions.githubusercontent.com`.
3. Create a separate role such as `makrsoft-terraform-deploy`. Its trust policy must allow `sts:AssumeRoleWithWebIdentity` from that provider, audience `sts.amazonaws.com`, and subjects `repo:MAKRSOFT-INTERNAL/aws-ec2-instance-agent:ref:refs/heads/main` and `repo:MAKRSOFT-INTERNAL/aws-ec2-instance-agent:environment:production`. Attach a reviewed policy allowing the Terraform resources in this repository and access to the state bucket and lock table. Do not grant the existing runner role or long-lived organization access keys this responsibility.
4. Configure the GitHub organization variables below and allow this repository to access them. Create the `production` GitHub environment; add required reviewers before enabling main-branch applies.
5. After reviewing the backend bucket name for global availability and the VPC CIDRs for overlap, push the Terraform changes to `main`. CI will validate, plan, and—after any configured production-environment approval—apply the main infrastructure. It creates the VPC and subnet, so no existing VPC or subnet IDs are required.
6. After apply, set the ephemeral-runner organization variables from Terraform outputs:
	- `AWS_RUNNER_ROLE_ARN`: Terraform output `bootstrap_role_arn`.
	- `RUNNER_LAUNCH_TEMPLATE_ID`: Terraform output `runner_launch_template_id`.
	- `RUNNER_PARAMETER_PREFIX`: Terraform output `runner_parameter_prefix`.
	- `AWS_REGION`: the region used for this Terraform deployment.
7. The bootstrap role trust policy defaults to `refs/heads/main`. Dispatch the ephemeral workflow from `main`, or set `allowed_github_ref` to the intended workflow ref before applying.

If you prefer to bootstrap with Terraform locally instead of the AWS console, use `infra/state-backend/terraform.tfvars.example` and `infra/state-backend/` with short-lived AWS credentials for account `783161622588`. The backend stack creates the same S3 bucket and lock table. Never place AWS access keys in the repository or share them in chat.

The `agent_instance_id`, `object_bucket_name`, `vpc_id`, and `public_subnet_id` Terraform outputs identify the persistent agent, application bucket, and created network. Manage the agent through AWS Systems Manager Session Manager; it has public IPv4 egress but no inbound security-group rules, and can access only its configured `agent_s3_prefix`. The application object bucket and Terraform state bucket are separate. Both are private, encrypted, versioned, and protected against insecure transport. State-bucket bootstrap state remains local initially, so preserve that state file or migrate it separately after bootstrap. Review the Terraform plan and generated IAM policies before applying them to a production account.

### Terraform GitHub Actions workflow

`.github/workflows/terraform.yml` runs `terraform fmt -check` and validates both Terraform configurations on pull requests targeting `main`, pushes to `main`, and manual dispatch. It plans the main infrastructure on pushes and manual dispatch, then, for `main` only, applies that exact saved plan after the GitHub `production` environment's approval rules are satisfied. Pull requests do not receive AWS credentials and do not run a Terraform plan. Runs are serialized to prevent overlapping plans and applies. Create the `production` environment in GitHub and configure required reviewers if apply must be manually approved.

Configure these GitHub Actions **organization variables** and grant this repository access to them before running the Terraform workflow:

- `TF_DEPLOY_ROLE_ARN`: ARN of the separately created `makrsoft-terraform-deploy` IAM role. Its OIDC provider is `token.actions.githubusercontent.com`, audience is `sts.amazonaws.com`, and its `sub` trust condition must allow both `repo:MAKRSOFT-INTERNAL/aws-ec2-instance-agent:ref:refs/heads/main` (plan job) and `repo:MAKRSOFT-INTERNAL/aws-ec2-instance-agent:environment:production` (apply job). Grant it access to the state bucket and lock table plus the IAM, EC2 networking/instances, S3, Lambda, EventBridge, SSM, CloudWatch Logs, and related resources in the Terraform configuration. Do not use the ephemeral runner bootstrap role.
- `TF_GITHUB_OIDC_PROVIDER_ARN`: use Terraform output `github_oidc_provider_arn`. For the account shown, the expected ARN is `arn:aws:iam::783161622588:oidc-provider/token.actions.githubusercontent.com`. The provider must exist before the Terraform deployment role can trust it.
- `TF_AWS_REGION`: `ap-southeast-2`, the deployment region for EC2, networking, and application resources.
- `TF_STATE_REGION`: `ap-southeast-2` if the Terraform state bucket is created there; otherwise set it to the bucket's actual region.
- CI pins the AWS account ID to `783161622588`; the provider refuses to plan/apply against a different account.
- `TF_STATE_BUCKET`: `makrsoft-terraform-state-s3-783161622588` from the state bootstrap example, if the globally unique name is available.
- `TF_STATE_LOCK_TABLE`: `makrsoft-terraform-state-s3-783161622588-lock`, the state bootstrap table name.
- `TF_GITHUB_OWNER` and `TF_GITHUB_REPOSITORY`: GitHub owner and repository used by the runner configuration, currently `MAKRSOFT-INTERNAL` and `aws-ec2-instance-agent`.
- `TF_RUNNER_VERSION`: pinned GitHub Actions runner release, currently shown as `2.329.0` in the tfvars example.
- `TF_OBJECT_BUCKET_NAME`: `makrsoft-app-objects-s3-783161622588` from the main tfvars example, if globally available. It must differ from `TF_STATE_BUCKET`.

All AWS resources created by the main stack use the `makrsoft` name prefix. It creates one public subnet in each supplied Sydney AZ: `ap-southeast-2a` (`apse2-az1`), `ap-southeast-2b` (`apse2-az3`), and `ap-southeast-2c` (`apse2-az2`), plus an internet gateway and internet route. The persistent agent and current ephemeral runner launch template use `runner_subnet_az_id`, defaulting to `apse2-az1`; the other subnets are available for future placement. No existing VPC or subnet IDs need to be supplied. The VPC defaults to `10.42.0.0/16`, with subnet CIDRs `10.42.1.0/24`, `10.42.2.0/24`, and `10.42.3.0/24`. Change the VPC CIDR in `infra/terraform.tfvars` if it overlaps networks reachable from this account. Instances receive public IPv4 addresses for outbound access, but the security group has no inbound rules. Public IPv4 addresses can incur AWS charges.

The Terraform workflow uses GitHub OIDC, so it does not need the `AWS_ACCESSKEYID` or `AWS_SECRET_ACCESSKEY` organization secrets. The AWS deployment role's trust policy must allow both the branch subject and the `production` environment subject above. The IAM role's permission policy must allow Terraform to manage the resources and remote state; review and scope it to this account and repository. Manual Terraform workflow dispatches must select `main`; other branches run format/validation only.

The separate ephemeral-runner workflow uses organization variables `AWS_RUNNER_ROLE_ARN` (set this to Terraform output `bootstrap_role_arn`, an IAM **role** ARN), `AWS_REGION` (`ap-southeast-2`), `RUNNER_LAUNCH_TEMPLATE_ID` (output `runner_launch_template_id`), and `RUNNER_PARAMETER_PREFIX` (output `runner_parameter_prefix`). It uses the organization secret `GH_TOKEN` instead of a GitHub App to create and delete repository runners. Ensure this token is authorized for repository Administration: write. `RUNNER_APP_ID` and `RUNNER_APP_PRIVATE_KEY` are not needed by this workflow.

The organization settings screenshots show `AWS_ACCESSKEYID`, `AWS_SECRET_ACCESSKEY`, and `GH_TOKEN` shared with public repositories. Restrict each secret to only the repositories that need it. Keep the AWS access-key secrets out of workflows using OIDC; rotate the keys if they have been exposed in source code or logs. The displayed `AWS_RUNNER_ROLE_ARN` appears to have an IAM user ARN (`...:user/...`); the ephemeral workflow uses `role-to-assume` and therefore requires an IAM role ARN (`...:role/...`). Set this organization variable to the `bootstrap_role_arn` Terraform output after apply.

Apply the state-backend bootstrap once from a trusted local machine before enabling the workflow. The bootstrap uses local state and is validated in CI, but is deliberately not automatically applied by CI; first create its bucket and lock table, then configure the workflow variables above. On the first deployment, migrate any existing local `infra` state to the remote S3 backend before running the workflow. The saved Terraform plan artifact contains infrastructure details and is retained for one day; repository access controls also govern artifact access.

### Dispatch a job

In GitHub Actions, run **Ephemeral EC2 runner** using `workflow_dispatch` and provide the shell command to execute, such as `make test`. Bootstrap uses `GH_TOKEN` to create a one-time registration token, launches the runner, and passes the command to the one-job EC2 runner. The workflow deregisters and terminates the instance afterward; the scheduled janitor handles abandoned instances and stale SSM parameters.

The dispatch command runs as repository workflow code with access to the runner instance profile. Only dispatch trusted workloads; do not use this runner for untrusted pull requests or commands that should not have access to AWS.
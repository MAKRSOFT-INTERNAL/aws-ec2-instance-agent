# Ephemeral GitHub Actions Runners on AWS EC2

## Architecture

The design uses one short-lived EC2 instance for each dispatched workflow run. A GitHub-hosted bootstrap job assumes a narrowly scoped AWS role through GitHub OIDC, prepares a short-lived runner registration token in SSM Parameter Store, and launches the instance. The instance registers as an ephemeral runner, executes one job, and terminates. A GitHub-hosted cleanup job handles failures that prevent the instance from self-terminating.

Terraform also provisions a separate persistent Amazon Linux agent instance. It uses its own IAM instance profile for Systems Manager access and restricted S3 object operations; it is not used as the GitHub Actions runner.

```text
GitHub workflow_dispatch
				|
				v
GitHub-hosted bootstrap job
	|  GitHub App installation token -> create runner registration token
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

The GitHub App installation token (or another approved GitHub credential) is a separate prerequisite: AWS OIDC authenticates the bootstrap job to AWS, but does not authorize it to create a GitHub runner registration token.

## Workflow and runner lifecycle

1. A `workflow_dispatch` starts on a GitHub-hosted runner. The bootstrap job obtains AWS credentials through OIDC and creates a short-lived GitHub App installation token with permission to manage repository runners.
2. The bootstrap job requests a runner registration token from GitHub, stores it as an SSM `SecureString` under a unique path for this workflow run, and launches the EC2 instance from a launch template. Pass the unique parameter name as user data; never put the token itself in user data or logs.
3. Instance user data installs or starts the pinned runner version, retrieves the parameter using its instance profile, removes the parameter, and configures the runner with `--ephemeral`. Add a unique run-specific label so the build job can target the runner created for that run.
4. The build/test/deploy job depends on bootstrap and targets that unique label. The ephemeral runner accepts one job and deregisters after it completes.
5. After the runner process exits, the instance shuts itself down; configure the launch template's instance-initiated shutdown behavior to `terminate`. A workflow `always()` cleanup job terminates the recorded instance if bootstrap, registration, scheduling, or the job fails. Add an independent orphan-instance and stale-parameter cleanup mechanism because workflow cleanup is not guaranteed to run (for example, if the workflow is canceled).

Runner registration tokens expire quickly. Create them immediately before launch, use a unique parameter per run, and delete the parameter after retrieval. Parameter Store has no native TTL, so stale parameters need explicit cleanup. Configure workflow and instance timeouts to bound pending runners and jobs.

## Security boundaries

- Restrict the IAM role trust policy to the intended GitHub organization, repository, branch or environment, and the `sts.amazonaws.com` audience. Grant the bootstrap role only the required EC2 launch/describe/terminate actions, access to the relevant SSM parameter path, and `iam:PassRole` for the runner instance profile.
- Give the ephemeral runner profile only `ssm:GetParameter` for its run-specific parameter and the required KMS decrypt permission. The separate persistent agent role has S3 access limited to `agent_s3_prefix` and Systems Manager permissions for Session Manager. Do not give either instance broad AWS permissions.
- Keep the GitHub App private key or other credential in GitHub Actions secrets, scope the App installation narrowly, and avoid printing credentials or runner tokens.
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
- A globally unique S3 bucket name for application objects and a separate globally unique S3 bucket name for Terraform state.
- An existing VPC and subnet with outbound internet access. Use a private subnet with NAT and keep `associate_public_ip_address = false`, or set it to `true` for a public subnet. The runner security group has no inbound rules.
- Terraform 1.17.0 or later and AWS credentials configured locally for the initial Terraform deployment. The repository enforces this minimum in both Terraform configurations.
- A GitHub App installed for this repository with `Administration: Read and write` permission. Add the App ID as the `RUNNER_APP_ID` repository secret and its private key as `RUNNER_APP_PRIVATE_KEY`.

### Provision AWS resources

1. Copy `infra/state-backend/terraform.tfvars.example` to `infra/state-backend/terraform.tfvars` and set `aws_region` and a globally unique `state_bucket_name`. The state-backend bootstrap itself uses local state.
2. From `infra/state-backend/`, run `terraform init`, `terraform plan`, and `terraform apply` to create the encrypted, versioned state bucket and DynamoDB lock table.
3. Copy `infra/backend.hcl.example` to `infra/backend.hcl`, and fill in the state bucket, lock-table name, and region from the bootstrap outputs. Keep this configuration file out of source control.
4. Copy `infra/terraform.tfvars.example` to `infra/terraform.tfvars` and replace the example values for `aws_region`, `github_owner`, `github_repository`, `vpc_id`, `subnet_id`, `runner_version`, and globally unique `object_bucket_name`.
5. From `infra/`, initialize the S3 backend and migrate any existing local state with `terraform init -backend-config=backend.hcl -migrate-state`. For a new deployment with no local state, use `terraform init -backend-config=backend.hcl` instead. Review `terraform plan` and then run `terraform apply`.
6. Configure these repository variables from Terraform outputs and your deployment configuration:
	- `AWS_RUNNER_ROLE_ARN`: Terraform output `bootstrap_role_arn`.
	- `RUNNER_LAUNCH_TEMPLATE_ID`: Terraform output `runner_launch_template_id`.
	- `RUNNER_PARAMETER_PREFIX`: Terraform output `runner_parameter_prefix`.
	- `AWS_REGION`: the region used for this Terraform deployment.
7. The bootstrap role trust policy defaults to `refs/heads/main`. Dispatch the workflow from `main`, or set `allowed_github_ref` to the intended workflow ref before applying.

The `agent_instance_id` and `object_bucket_name` Terraform outputs identify the persistent agent and application bucket. Manage the agent through AWS Systems Manager Session Manager; it has no inbound security-group rules and can access only its configured `agent_s3_prefix`. The application object bucket and Terraform state bucket are separate. Both are private, encrypted, versioned, and protected against insecure transport. State-bucket bootstrap state remains local initially, so preserve that state file or migrate it separately after bootstrap. Review the Terraform plan and generated IAM policies before applying them to a production account.

### Terraform GitHub Actions workflow

`.github/workflows/terraform.yml` runs `terraform fmt -check` and validates both Terraform configurations on pull requests targeting `main`, pushes to `main`, and manual dispatch. It plans the main infrastructure on pushes and manual dispatch, then, for `main` only, applies that exact saved plan after the GitHub `production` environment's approval rules are satisfied. Pull requests do not receive AWS credentials and do not run a Terraform plan. Runs are serialized to prevent overlapping plans and applies. Create the `production` environment in GitHub and configure required reviewers if apply must be manually approved.

Configure these GitHub Actions **repository variables** before running the Terraform workflow:

- `TF_DEPLOY_ROLE_ARN`: AWS IAM role ARN for Terraform deployment. Create this role before enabling CI; it is not created by this Terraform configuration. Its OIDC provider is `token.actions.githubusercontent.com`, audience is `sts.amazonaws.com`, and its `sub` trust condition must allow both `repo:MAKRSOFT-INTERNAL/aws-ec2-instance-agent:ref:refs/heads/main` (plan job) and `repo:MAKRSOFT-INTERNAL/aws-ec2-instance-agent:environment:production` (apply job). Grant it access to the state bucket and lock table plus the IAM, EC2, S3, Lambda, EventBridge, SSM, and related resources in the Terraform configuration. Do not use the ephemeral runner bootstrap role.
- `TF_GITHUB_OIDC_PROVIDER_ARN`: ARN of the already-created AWS IAM OIDC provider for `token.actions.githubusercontent.com`, such as `arn:aws:iam::<account-id>:oidc-provider/token.actions.githubusercontent.com`. The Terraform deployment role needs this provider to authenticate, so create it before the first CI run. Passing it to Terraform makes the infrastructure configuration reuse the provider instead of attempting to create a duplicate.
- `TF_AWS_REGION`: AWS deployment and state region, for example `us-east-1`.
- `TF_STATE_BUCKET`: name of the separate state bucket created by `infra/state-backend`.
- `TF_STATE_LOCK_TABLE`: lock table name from the state bootstrap output, which is the state bucket name followed by `-lock`.
- `TF_GITHUB_OWNER` and `TF_GITHUB_REPOSITORY`: GitHub owner and repository used by the runner configuration, currently `MAKRSOFT-INTERNAL` and `aws-ec2-instance-agent`.
- `TF_VPC_ID` and `TF_SUBNET_ID`: real VPC and outbound-connected subnet IDs for the agent and ephemeral runners. Replace the example IDs; they are placeholders.
- `TF_RUNNER_VERSION`: pinned GitHub Actions runner release, currently shown as `2.329.0` in the tfvars example.
- `TF_OBJECT_BUCKET_NAME`: globally unique application-object bucket name. It must differ from `TF_STATE_BUCKET`; the tfvars example uses an illustrative name that you must replace with an available bucket name.

The Terraform workflow uses GitHub OIDC, so it does not need long-lived AWS access-key secrets. The AWS deployment role's trust policy must allow both the branch subject and the `production` environment subject above. The IAM role's permission policy must allow Terraform to manage the resources and remote state; review and scope it to this account and repository. Manual Terraform workflow dispatches must select `main`; other branches run format/validation only.

The separate ephemeral-runner workflow also requires these **repository variables**: `AWS_RUNNER_ROLE_ARN` (Terraform output `bootstrap_role_arn`), `AWS_REGION`, `RUNNER_LAUNCH_TEMPLATE_ID` (output `runner_launch_template_id`), and `RUNNER_PARAMETER_PREFIX` (output `runner_parameter_prefix`). It requires **repository secrets** `RUNNER_APP_ID` and `RUNNER_APP_PRIVATE_KEY` for the GitHub App that can manage repository runners.

Apply the state-backend bootstrap once from a trusted local machine before enabling the workflow. The bootstrap uses local state and is validated in CI, but is deliberately not automatically applied by CI; first create its bucket and lock table, then configure the workflow variables above. On the first deployment, migrate any existing local `infra` state to the remote S3 backend before running the workflow. The saved Terraform plan artifact contains infrastructure details and is retained for one day; repository access controls also govern artifact access.

### Dispatch a job

In GitHub Actions, run **Ephemeral EC2 runner** using `workflow_dispatch` and provide the shell command to execute, such as `make test`. Bootstrap creates a GitHub App token and a one-time registration token, launches the runner, and passes the command to the one-job EC2 runner. The workflow deregisters and terminates the instance afterward; the scheduled janitor handles abandoned instances and stale SSM parameters.

The dispatch command runs as repository workflow code with access to the runner instance profile. Only dispatch trusted workloads; do not use this runner for untrusted pull requests or commands that should not have access to AWS.
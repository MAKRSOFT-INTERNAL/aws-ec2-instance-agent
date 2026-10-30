# EKS on AWS with GitHub Actions

This repository provisions an Amazon EKS cluster and managed EC2 worker nodes in `ap-southeast-2`. The current POC workflow uses AWS access-key secrets as source credentials to assume the existing `GitHubActionsWorkflowRole` with AWS STS. It does not use GitHub OIDC.

## What is provisioned

- A dedicated VPC with public and private subnets across two or three availability zones.
- One NAT gateway for private-subnet egress, to keep the default setup less expensive than one NAT gateway per AZ.
- An EKS control plane with private Kubernetes API access, control-plane API/audit/authenticator logs, and managed `vpc-cni`, `kube-proxy`, and CoreDNS add-ons.
- An EKS managed node group with two `t3.medium` On-Demand nodes by default, scalable from two to three nodes.
- IAM roles for the EKS control plane and worker nodes.
- A GitHub Actions OIDC provider (unless an existing provider ARN is supplied), a repository/ref-restricted deployment role, and a versioned, encrypted S3 state bucket.

The cluster module is in [`modules/eks-cluster`](./modules/eks-cluster). The EKS root configuration is in [`terraform/eks`](./terraform/eks), and the one-time OIDC/state bootstrap is in [`terraform/bootstrap`](./terraform/bootstrap).

## Important costs and access defaults

An EKS control plane, EC2 worker nodes, NAT gateway, public IPv4 addresses, and CloudWatch logs incur AWS charges while running. Review the Terraform plan and AWS pricing before applying. Destroying the cluster does not automatically delete the bootstrap state bucket; it is deliberately protected against accidental deletion.

The Kubernetes API endpoint is private-only by default. To enable public endpoint access, set `cluster_endpoint_public_access = true` and provide a narrow `cluster_endpoint_public_access_cidrs` allowlist. Do not use `0.0.0.0/0` for a production cluster.

The GitHub deployment role that creates the cluster receives the EKS creator's cluster-admin access. To grant a separate human/admin IAM role access, set `cluster_admin_iam_role_arn` in [`terraform/eks/variables.tf`](./terraform/eks/variables.tf). The module creates an EKS access entry and associates `AmazonEKSClusterAdminPolicy` with that role. The role also needs AWS permissions to call `eks:DescribeCluster`; public endpoint access or private network connectivity is required to reach the Kubernetes API.

## One-time bootstrap

The bootstrap needs an AWS identity with permissions to create IAM OIDC providers/roles and an S3 bucket. Use a short-lived AWS SSO session or another approved administrative identity; do not put AWS credentials in this repository.

1. Choose an unused, globally unique S3 bucket name for Terraform state.
2. If the AWS account already has the GitHub Actions OIDC provider, pass its ARN as `existing_github_oidc_provider_arn` to avoid trying to create a duplicate provider.
3. Initialize the bootstrap Terraform configuration:

   ```sh
   cd terraform/bootstrap
   terraform init
   ```

4. Set the bootstrap variables in the same shell. The bootstrap creates a separate, least-privilege EKS deployment role; it does not modify the existing `GitHubActionsWorkflowRole` used by the current POC workflow. The current workflow does not require the bootstrap-created OIDC provider or role.

   ```sh
   export TF_VAR_aws_region=ap-southeast-2
   export TF_VAR_state_bucket_name='makrosft-tfstate-s3'
   export TF_VAR_existing_github_oidc_provider_arn='arn:aws:iam::<account-id>:oidc-provider/token.actions.githubusercontent.com'
   ```

   S3 bucket names are globally unique. If `makrosft-tfstate-s3` is unavailable or already belongs to another account, choose another name and use it consistently for bootstrap and GitHub Actions.

5. Run and review the bootstrap plan before applying. The bootstrap manages its own separate role (`github-eks-terraform-deploy`) and state bucket; it does not replace or change `GitHubActionsWorkflowRole`.

   ```sh
   terraform plan -out=bootstrap.tfplan
   terraform show bootstrap.tfplan
   terraform apply bootstrap.tfplan
   ```

6. Record the output `state_bucket_name`.
7. Allow the IAM user whose access key is stored in GitHub to assume the role. The role's trust relationship must include this principal and action:

   ```json
   {
     "Effect": "Allow",
     "Principal": {
       "AWS": "arn:aws:iam::783161622588:user/makrsoft-admin"
     },
     "Action": "sts:AssumeRole"
   }
   ```

   The IAM user also needs an identity policy allowing `sts:AssumeRole` on `arn:aws:iam::783161622588:role/GitHubActionsWorkflowRole`. The workflow uses this role ARN directly; an `AWS_RUNNER_ROLE_ARN` variable containing a `user/...` ARN is not valid for `role-to-assume`.
8. Add or confirm the following GitHub Actions secrets and variables. Organization-level secrets must be available to this repository; otherwise create repository-level secrets.

   | Type | Name | Value |
   | --- | --- | --- |
   | Secret | `AWS_ACCESSKEYID` | Access key ID for the IAM user allowed to assume the role |
   | Secret | `AWS_SECRET_ACCESSKEY` | Matching secret access key |
   | Variable | `AWS_REGION` | `ap-southeast-2` |
   | Variable | `TF_STATE_BUCKET` | `makrosft-tfstate-s3` (must match bootstrap output `state_bucket_name`) |

9. Protect `main` against unreviewed changes. The workflow assumes the role only for pushes or manual runs on `main`.

For this POC, `GitHubActionsWorkflowRole` retains its existing `AdministratorAccess` policy. This grants GitHub Actions broad permission to change or delete resources across the AWS account. The workflow only assumes the role; neither the workflow nor the bootstrap replaces the role or changes its attached permissions. Long-lived AWS access keys are less secure than OIDC; use a dedicated IAM user whose permissions are limited to assuming this role, protect and rotate its keys, and review all workflow plans before applying.

Bootstrap uses local Terraform state because it creates the remote state bucket itself. Keep that state in a protected location. Re-running bootstrap later requires that local state.

## CI/CD workflow

The [`Terraform EKS` workflow](./.github/workflows/terraform.yml):

- Runs formatting and Terraform validation on pull requests and pushes to `main`. These checks do not receive AWS credentials.
- On pushes to `main`, creates a saved Terraform plan and automatically applies it without an environment approval. Manual dispatch from `main` does the same.
- Uses AWS access-key secrets as source credentials to assume `GitHubActionsWorkflowRole` through AWS STS, then uses the S3 backend with native S3 lock files. It does not request a GitHub OIDC token.

Any push to `main` that changes Terraform, the module, or this workflow can provision, update, or destroy AWS resources according to the plan. Review the plan printed in the workflow logs and protect `main` with required pull-request reviews before enabling this behavior. To manually run the deployment, open **Actions → Terraform EKS → Run workflow** and select `main`. The saved plan artifact is retained for one day.

The AWS role trust policy must permit the IAM user whose access key is stored in GitHub Actions secrets. The workflow currently pins Terraform CLI to `1.10.5`.

The workflow reads optional repository **Actions variables** for deployment settings. If unset, Terraform uses the defaults shown:

| Variable | Default | Example |
| --- | --- | --- |
| `EKS_CLUSTER_NAME` | `makrsoft-eks` | Must match the bootstrap `cluster_name` |
| `EKS_KUBERNETES_VERSION` | `1.35` | A version supported by EKS in the selected region |
| `EKS_VPC_CIDR` | `10.42.0.0/16` | Non-overlapping IPv4 range, `/16` through `/20` |
| `EKS_AVAILABILITY_ZONE_COUNT` | `3` | `2` or `3` |
| `EKS_NODE_INSTANCE_TYPES` | `["t3.medium"]` | JSON list, e.g. `["m6i.large"]` |
| `EKS_NODE_MIN_SIZE` | `2` | Integer |
| `EKS_NODE_DESIRED_SIZE` | `2` | Integer between min and max |
| `EKS_NODE_MAX_SIZE` | `3` | Integer |
| `EKS_CLUSTER_ENDPOINT_PUBLIC_ACCESS` | `false` | `true` only with a restricted CIDR list |
| `EKS_CLUSTER_ENDPOINT_PUBLIC_ACCESS_CIDRS` | `[]` | JSON list of trusted CIDRs |
| `EKS_CLUSTER_ADMIN_IAM_ROLE_ARN` | empty | Optional IAM role to grant cluster-admin |

The workflow assumes `arn:aws:iam::783161622588:role/GitHubActionsWorkflowRole` and defaults `TF_STATE_BUCKET` to `makrosft-tfstate-s3`. Confirm the bucket exists in the account and region used by the bootstrap. Set `AWS_REGION` to `ap-southeast-2` and keep it consistent with the bootstrap region. Configure optional `EKS_*` variables at the repository level so plan and apply receive the same values. Local `terraform.tfvars` files are ignored by Git and are not used by GitHub Actions.

## Local Terraform commands

After bootstrap, initialize the EKS backend and inspect the plan:

```sh
cd terraform/eks
terraform init \
  -backend-config='bucket=<state-bucket-name>' \
  -backend-config='key=eks/terraform.tfstate' \
  -backend-config='region=ap-southeast-2' \
  -backend-config='encrypt=true' \
  -backend-config='use_lockfile=true'
terraform fmt -check -recursive ../..
terraform validate
terraform plan
```

Terraform defaults to the `makrsoft-eks` cluster name, Kubernetes `1.35`, three AZs, and two `t3.medium` nodes. Confirm that the selected Kubernetes version is supported in the target region before deployment. Copy [`terraform/eks/terraform.tfvars.example`](./terraform/eks/terraform.tfvars.example) to an untracked `terraform.tfvars` file for custom sizing, networking, or endpoint access.

After deployment, the output `configure_kubectl` shows the `aws eks update-kubeconfig` command. Use AWS credentials for an IAM principal with EKS access. The default private-only endpoint is reachable only from the VPC or a connected network.

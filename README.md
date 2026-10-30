# EKS on AWS with GitHub Actions

This repository provisions an Amazon EKS cluster and managed EC2 worker nodes in `ap-southeast-2`. The workflow authenticates directly as the `makrsoft-admin` IAM user using GitHub Actions access-key secrets.

## What is provisioned

- A dedicated VPC with public and private subnets across two or three availability zones.
- One NAT gateway for private-subnet egress, to keep the default setup less expensive than one NAT gateway per AZ.
- An EKS control plane with private Kubernetes API access, control-plane API/audit/authenticator logs, and managed `vpc-cni`, `kube-proxy`, and CoreDNS add-ons.
- An EKS managed node group with two `t3.medium` On-Demand nodes by default, scalable from two to three nodes.
- IAM roles for the EKS control plane and worker nodes.
- A versioned, encrypted S3 state bucket for Terraform.

The cluster module is in [`modules/eks-cluster`](./modules/eks-cluster). The EKS root configuration is in [`terraform/eks`](./terraform/eks), and the optional state-bucket setup is in [`terraform/bootstrap`](./terraform/bootstrap).

## Important costs and access defaults

An EKS control plane, EC2 worker nodes, NAT gateway, public IPv4 addresses, and CloudWatch logs incur AWS charges while running. Review the Terraform plan and AWS pricing before applying. Destroying the cluster does not automatically delete the bootstrap state bucket; it is deliberately protected against accidental deletion.

The Kubernetes API endpoint is private-only by default. To enable public endpoint access, set `cluster_endpoint_public_access = true` and provide a narrow `cluster_endpoint_public_access_cidrs` allowlist. Do not use `0.0.0.0/0` for a production cluster.

The IAM principal running Terraform (currently the `makrsoft-admin` user in GitHub Actions) receives the EKS creator's cluster-admin access. To grant a separate human/admin IAM role access, set `cluster_admin_iam_role_arn` in [`terraform/eks/variables.tf`](./terraform/eks/variables.tf). The module creates an EKS access entry and associates `AmazonEKSClusterAdminPolicy` with that role. The role also needs AWS permissions to call `eks:DescribeCluster`; public endpoint access or private network connectivity is required to reach the Kubernetes API.

## One-time bootstrap

The plan job creates the configured S3 state bucket if needed and secures it before Terraform initializes the backend. S3 bucket names are globally unique; choose another `TF_STATE_BUCKET` if `makrosft-tfstate-s3` is already owned by another account. The IAM user's credentials need permission to create/configure the bucket and access its state.

Add or confirm the following GitHub Actions secrets and variables. Organization-level secrets must be available to this repository; otherwise create repository-level secrets, especially if this repository is private.

   | Type | Name | Value |
   | --- | --- | --- |
   | Secret | `AWS_ACCESSKEYID` | Access key ID for `makrsoft-admin` |
   | Secret | `AWS_SECRET_ACCESSKEY` | Matching secret access key |
   | Variable | `AWS_REGION` | `ap-southeast-2` |
   | Variable | `TF_STATE_BUCKET` | `makrosft-tfstate-s3` (must match bootstrap output `state_bucket_name`) |

Protect `main` against unreviewed changes.

The shown `makrsoft-admin` user has `AdministratorAccess`, which grants the workflow broad permission to change or delete resources across the AWS account. Protect and rotate the access keys, restrict workflow changes to trusted reviewers, and review plans before applying.

The optional [`terraform/bootstrap`](./terraform/bootstrap) configuration can manage bucket security settings outside CI. If CI has already created the bucket, import it into bootstrap state before planning:

```sh
cd terraform/bootstrap
terraform init
terraform import aws_s3_bucket.terraform_state makrosft-tfstate-s3
terraform plan
```

Review the plan before applying. Bootstrap uses local Terraform state; keep that state protected. If an older bootstrap state tracks GitHub OIDC resources, removing those resources from configuration can make Terraform propose deleting them; inspect the plan carefully before applying.

## CI/CD workflow

The plan job creates the configured S3 state bucket if needed and secures it before Terraform initializes the backend. The IAM credentials need S3 permissions to create/configure that bucket and subsequently access its state. If bucket creation fails with `BucketAlreadyExists`, the globally unique name is owned by someone else; choose a different `TF_STATE_BUCKET`. If Terraform still reports `NoSuchBucket`, check the create-bucket step and ensure plan and apply use the same bucket and AWS account.

The [`Terraform EKS` workflow](./.github/workflows/terraform.yml):

- Runs formatting and Terraform validation on pull requests and pushes to `main`. These checks do not receive AWS credentials.
- On pushes to `main`, creates a saved Terraform plan and automatically applies it without an environment approval. Manual dispatch from `main` does the same.
- Uses the `AWS_ACCESSKEYID` and `AWS_SECRET_ACCESSKEY` secrets directly as AWS credentials, then uses the S3 backend with native S3 lock files.

Any push to `main` that changes Terraform, the module, or this workflow can provision, update, or destroy AWS resources according to the plan. Review the plan printed in the workflow logs and protect `main` with required pull-request reviews before enabling this behavior. To manually run the deployment, open **Actions → Terraform EKS → Run workflow** and select `main`. The saved plan artifact is retained for one day.

The workflow currently pins Terraform CLI to `1.10.5`.

The workflow reads optional repository **Actions variables** for deployment settings. If unset, Terraform uses the defaults shown:

| Variable | Default | Example |
| --- | --- | --- |
| `EKS_CLUSTER_NAME` | `makrsoft-eks` | EKS cluster name |
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

The workflow authenticates as `makrsoft-admin` with the access-key secrets and defaults `TF_STATE_BUCKET` to `makrosft-tfstate-s3`. Set `AWS_REGION` to `ap-southeast-2`. Configure optional `EKS_*` variables at the repository level so plan and apply receive the same values. Local `terraform.tfvars` files are ignored by Git and are not used by GitHub Actions.

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

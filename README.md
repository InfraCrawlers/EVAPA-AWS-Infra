# EVAPA-AWS-Infra

Enterprise Vulnerability Assessment and Patching Automation on AWS.

This repository provisions a complete vulnerability management lab using Terraform, deploys intentionally vulnerable Linux and Windows targets, runs OpenVAS scanning, exports scan reports to S3, parses high-severity findings into DynamoDB, and exposes results through API Gateway + Lambda.

## 1. What This Project Does

The platform implements a full lifecycle:

1. Provision infrastructure with Terraform.
2. Build vulnerable workloads (Linux and Windows EC2 instances).
3. Deploy OpenVAS scanner on a dedicated EC2 host.
4. Trigger and manage scans through serverless API endpoints.
5. Upload OpenVAS XML reports to S3.
6. Parse XML findings in Lambda and store high-severity issues in DynamoDB.
7. Query findings via API.
8. Apply remediation/patching via Ansible over AWS Systems Manager.

## 2. High-Level Architecture

- Terraform backend:
	- S3 bucket for remote state.
	- DynamoDB table for state locking.
- Compute:
	- Ubuntu target EC2 (vulnerable baseline from user data script).
	- Windows Server 2019 EC2 (vulnerable baseline from PowerShell user data).
	- OpenVAS scanner EC2 (Greenbone Community Edition in Docker).
- Security and access:
	- IAM roles for EC2, Lambda, S3, DynamoDB.
	- Security groups controlling scanner, targets, and Lambda-to-OpenVAS path.
	- SSM-based management for instances.
- Data and API:
	- OpenVAS reports stored in S3.
	- Parser Lambda transforms XML and writes findings to DynamoDB.
	- HTTP API and REST API resources for retrieving findings and controlling OpenVAS entities.

## 3. Repository Structure

```text
.
|-- README.md
|-- terraform.tfstate
|-- aws/
|-- terraform-bootstrap/
|   |-- main.tf
|   `-- README.md
`-- terraform-infra/
		|-- ansible_hosts.tf
		|-- apigateway.tf
		|-- backend.tf
		|-- cloudwatch.tf
		|-- dynamodb.tf
		|-- ec2.tf
		|-- iam.tf
		|-- lambda_api.tf
		|-- lambda_parser.tf
		|-- openvas_api.tf
		|-- openvas_lambda.tf
		|-- outputs.tf
		|-- provider.tf
		|-- README.md
		|-- s3.tf
		|-- sg.tf
		|-- variables.tf
		|-- versions.tf
		|-- lambda/
		|-- packages/
		|-- playbooks/
		`-- scripts/
```

## 4. Terraform Code Explained (File by File)

### terraform-bootstrap/

#### terraform-bootstrap/main.tf
One-time bootstrap stack for Terraform state infrastructure:

- Creates S3 bucket `capstone-terraform-state-vulnmgmt-7f3a`.
- Enables bucket versioning.
- Enforces SSE-S3 encryption.
- Blocks all public access.
- Creates DynamoDB lock table `terraform-state-locks`.

Run this once before main infrastructure deployment.

### terraform-infra/

#### backend.tf
Configures Terraform backend to use:

- S3 bucket: `capstone-terraform-state-vulnmgmt-7f3a`
- State key: `vuln-management/terraform.tfstate`
- DynamoDB lock table: `terraform-state-locks`
- Region: `us-east-1`

#### provider.tf

- Pins AWS provider (`~> 5.0`) and Terraform version (`>= 1.5.0`).
- Uses `us-east-1`.
- Reads an existing VPC by hardcoded ID.
- Pulls subnet IDs in that VPC for Lambda VPC config.

#### versions.tf
Discovers latest matching AMIs for:

- Amazon Linux 2 (currently not used by active EC2 resource).
- Ubuntu 20.04 (Linux vulnerable target).
- Ubuntu 22.04 (OpenVAS scanner host).
- Windows Server 2019 (Windows vulnerable target).

#### variables.tf
Project-wide inputs:

- `project_name` default: `capstone-vuln-mgmt`
- `instance_type` default: `t3.medium`
- `key_name` optional EC2 key pair
- `gmp_user` and `gmp_password` for OpenVAS GMP auth

#### sg.tf
Defines security groups:

- `ec2_sg`
	- Allows full TCP ingress only from OpenVAS SG for scanning.
	- Allows all egress.
- `openvas_sg`
	- Exposes 80/443/22 publicly.
	- Allows 9390 from Lambda SG (GMP over TLS).
	- Allows all egress.
- `lambda_sg`
	- Egress on 9390 to VPC CIDR for Lambda -> OpenVAS connectivity.

#### iam.tf
IAM resources include:

- EC2/SSM role and instance profile:
	- `AmazonSSMManagedInstanceCore`
	- `AmazonSSMFullAccess`
- Policy for OpenVAS EC2 to upload/list report bucket.
- Policy for SSM/Ansible bucket object operations.
- Lambda parser/read role permissions:
	- S3 GetObject
	- DynamoDB PutItem/BatchWriteItem/DescribeTable
	- CloudWatch basic Lambda logging attachment.

#### ec2.tf
Provisioned instances:

- `aws_instance.linux_ubuntu`
	- Ubuntu 20.04
	- Uses `scripts/linux.sh` to install vulnerable app stack.
- `aws_instance.windows`
	- Windows Server 2019
	- Uses `scripts/windows.ps1` to establish vulnerable posture.
- `aws_instance.openvas`
	- Ubuntu 22.04, `t3.large`, 50GB root disk
	- Uses `scripts/openvas.sh` to deploy Greenbone Docker stack.

#### s3.tf
Creates two buckets:

- `${project_name}-openvas-reports` for scan report XML.
- `${project_name}-ssm-ansible-bucket` for SSM/Ansible transport.

Also applies:

- Public access block on SSM bucket.
- Versioning on SSM bucket.
- Placeholder object prefix for reports.

#### dynamodb.tf
Creates findings table:

- Name: `openvas-scan-findings`
- Billing: `PAY_PER_REQUEST`
- PK: `pk` (string)
- SK: `sk` (string)

#### openvas_lambda.tf
Deploys OpenVAS control Lambdas (Python 3.12) in VPC:

- `openvas_create_port_list`
- `openvas_create_target`
- `openvas_create_task`
- `openvas_start_scan`
- `openvas_get_port_lists`
- `openvas_get_targets`
- `openvas_get_tasks`

Important behavior:

- Uses prebuilt zip artifacts from `terraform-infra/lambda/*/*.zip`.
- Uses shared layer `packages/gvm_layer.zip` for python-gvm dependencies.
- Injects env vars:
	- `OPENVAS_IP` from OpenVAS private IP
	- `GMP_USER`
	- `GMP_PASSWORD`

#### openvas_api.tf
Builds REST API Gateway endpoints for OpenVAS operations:

- Resources: `/port-lists`, `/targets`, `/tasks`.
- Methods map to corresponding Lambda actions (GET/POST).
- Extra route: `POST /tasks/{task_id}/start` for scan execution.
- Includes deployment trigger hash to force redeploy on endpoint changes.

#### lambda_parser.tf
Parser pipeline:

- Deploys `s3triggerforlambda` from `lambda/openvas_parser/openvas_lambda.zip`.
- Injects `DYNAMODB_TABLE_NAME` env var.
- Grants S3 invoke permission.
- Configures S3 event notification for `openvas-reports/*.xml` object creation.

#### lambda_api.tf
Findings query pipeline:

- Zips `lambda/dynamodb_api/index.mjs` into payload.
- Deploys Node.js 20 Lambda `dynamodb-read`.
- Grants DynamoDB read permissions (Scan/Query/GetItem).

#### apigateway.tf
Creates an HTTP API v2 endpoint:

- Route: `GET /findings`
- Integration: `dynamodb-read` Lambda
- Stage: `v1`
- Adds invoke permission for API Gateway.

Note: this repository contains both REST API (OpenVAS control plane) and HTTP API (findings query). This is valid, but teams should keep route ownership clear.

#### cloudwatch.tf
Creates log groups (7-day retention) for:

- Parser Lambda.
- DynamoDB read Lambda.

#### ansible_hosts.tf
Generates local Ansible inventory file (`hosts.ini`) with Ubuntu instance IP and SSH settings.

#### outputs.tf
Outputs:

- EC2 instance IDs for Ubuntu, Windows, OpenVAS.
- API base URL from REST API stage.

## 5. Lambda Code Explained

### OpenVAS control Lambdas (Python)

All functions connect to OpenVAS GMP over TLS on port 9390 and authenticate with environment credentials.

1. `create_port_list.py`
	 - Expects JSON body with `name` and `port_range`.
	 - Creates a custom OpenVAS port list.
	 - Returns new `port_list_id`.

2. `create_target.py`
	 - Expects `name`, `hosts`, `port_list_name`, optional `alive_test`.
	 - Resolves port list name to ID.
	 - Handles AliveTest enum compatibility across python-gvm versions.
	 - Creates OpenVAS target and returns `target_id`.

3. `create_task.py`
	 - Expects `name`, `target_name`.
	 - Optional defaults:
		 - scan config: `Full and fast`
		 - scanner: `OpenVAS Default`
	 - Resolves names to IDs and creates task.

4. `start_scan.py`
	 - Reads `task_id` from path parameter, but treats it as task name.
	 - Resolves task name to real task UUID.
	 - Starts scan and returns `report_id` when available.

5. `get_port_lists.py`
	 - `GET` list endpoint.
	 - Supports `?id=<uuid>` to fetch specific port list details.

6. `get_targets.py`
	 - `GET` list endpoint.
	 - Supports `?id=<uuid>` for detailed target fields.

7. `get_tasks.py`
	 - `GET` list endpoint for tasks and status/progress metadata.
	 - Current file includes unresolved merge conflict markers and should be repaired before reliable deployment.

### Parser and Data Lambdas

8. `openvas_parser/openvas_lambda.py`
	 - Triggered by S3 object creation events.
	 - Reads XML report.
	 - Extracts results with severity > 7.0.
	 - Writes one DynamoDB item per report with vulnerability list and counts.

9. `dynamodb_api/index.mjs`
	 - Scans `openvas-scan-findings` and returns JSON data.
	 - Includes CORS header for frontend/API consumer compatibility.

## 6. Script and Playbook Code Explained

### scripts/linux.sh
User-data script that intentionally installs vulnerable Linux software versions and starts exposed services for scanning realism:

- ProFTPD 1.3.5e
- Struts 2.3.20.1 sample apps on Tomcat 8.5.15
- Drupal 7.31
- WordPress 4.7.1
- Elasticsearch 1.1.1

Also creates MySQL databases and service startup state.

### scripts/windows.ps1
User-data script that creates vulnerable Windows posture:

- Disables Windows Update service/policy.
- Enables legacy TLS protocol settings.
- Installs older components and vulnerable service surface (including old Elasticsearch and FileZilla Server).
- Adds startup task for persistence.

### scripts/openvas.sh
Bootstraps OpenVAS host:

- Installs Python tooling, AWS CLI, SSM plugin, Ansible, python-gvm.
- Generates and runs an Ansible playbook that:
	- installs Docker and Compose,
	- deploys Greenbone Community Edition,
	- injects gmp-proxy (9390),
	- schedules periodic report sync script.

### scripts/auto.py
Runs on OpenVAS host (cron) to:

- Enumerate completed reports.
- Download full XML via GMP socket.
- Upload XML to S3 under `openvas-reports/`.
- Track already-sent reports in local state file.

### playbooks/win_patching.yml
Windows remediation playbook:

- Re-enables updates.
- Stabilizes SSM/WinRM profile behavior.
- Removes vulnerable Elasticsearch.
- Installs Elasticsearch 7.17.10.
- Applies critical/security updates with reboot handling.

### playbooks/linux_patching.yml
Linux remediation playbook to upgrade vulnerable stack to modern versions and patch OS.

Current file includes unresolved git merge markers and conflicting host definitions. Resolve before use.

### playbooks/inventory.ini
Static inventory using `community.aws.aws_ssm` connection plugin for Linux and Windows instance IDs.

## 7. API Endpoints

### OpenVAS REST API (API Gateway REST)

- `POST /v1/port-lists`
- `GET /v1/port-lists`
- `POST /v1/targets`
- `GET /v1/targets`
- `POST /v1/tasks`
- `GET /v1/tasks`
- `POST /v1/tasks/{task_id}/start`

### Findings HTTP API (API Gateway HTTP v2)

- `GET /v1/findings`

## 8. End-to-End Deployment Steps

### Prerequisites

- AWS account and credentials configured locally.
- Terraform >= 1.5.
- AWS CLI.
- Ansible (for remediation playbooks from operator workstation if needed).
- Existing target VPC matching `provider.tf` data source ID.

### Step 1: Bootstrap Terraform Backend

```bash
cd terraform-bootstrap
terraform init
terraform apply
```

This creates backend S3 and DynamoDB lock resources.

### Step 2: Deploy Main Infrastructure

```bash
cd ../terraform-infra
terraform init
terraform plan
terraform apply
```

What gets deployed:

- EC2 scanner + targets
- IAM roles/policies/profiles
- Security groups
- S3 buckets
- DynamoDB table
- Lambda functions/layer integrations
- API Gateways and permissions
- CloudWatch log groups

### Step 3: Validate Infrastructure

Check:

- EC2 instances are running and managed in SSM.
- OpenVAS host exposes web UI (ports 80/443) and GMP proxy on 9390 internally.
- Lambda functions exist and have expected env variables.
- APIs deployed with stage `v1`.

### Step 4: Run Scan Workflow

1. Create port list via API.
2. Create target via API.
3. Create task via API.
4. Start task via API.
5. Wait for OpenVAS report completion.
6. `auto.py` sync uploads XML to S3.
7. S3 event triggers parser Lambda.
8. Parser writes high-severity findings to DynamoDB.
9. Query findings through `GET /findings`.

### Step 5: Perform Remediation

- Linux: run Ansible Linux patching playbook.
- Windows: run Ansible Windows patching playbook.
- Re-run scans and compare findings before/after patching.

## 9. Operational Notes and Caveats

- `provider.tf` currently pins a specific VPC ID; change for other environments.
- Lambda artifacts (`*.zip`) and layer zip must be present before Terraform apply.
- API design currently splits across REST and HTTP APIs. Consider standardizing if needed.
- Two files currently contain unresolved merge conflict markers:
	- `terraform-infra/playbooks/linux_patching.yml`
	- `terraform-infra/lambda/get_tasks/get_tasks.py`

## 10. Security Notice

This project intentionally deploys vulnerable software and weak configurations for educational/lab use only. Do not deploy unchanged in production.

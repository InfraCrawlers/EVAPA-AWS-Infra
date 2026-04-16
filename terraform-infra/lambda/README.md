# Lambda Functions

This folder contains Lambda source code and deployment artifacts used by the EVAPA infrastructure stack.

Terraform in the parent folder consumes these files from:

- `openvas_lambda.tf`
- `lambda_parser.tf`
- `lambda_api.tf`
- `openvas_api.tf`
- `apigateway.tf`

## Purpose

The Lambda layer of the project handles three jobs:

1. Control OpenVAS through Greenbone Management Protocol (GMP).
2. Parse OpenVAS XML reports uploaded to S3.
3. Read parsed findings from DynamoDB for API clients or the companion dashboard.

## Directory Map

| Directory | Runtime | Terraform resource | Purpose |
|---|---|---|---|
| `create_port_list/` | Python 3.12 | `aws_lambda_function.openvas_api["create_port_list"]` | Creates OpenVAS port lists. |
| `get_port_lists/` | Python 3.12 | `aws_lambda_function.openvas_api["get_port_lists"]` | Lists OpenVAS port lists. |
| `create_target/` | Python 3.12 | `aws_lambda_function.openvas_api["create_target"]` | Creates OpenVAS scan targets. |
| `get_targets/` | Python 3.12 | `aws_lambda_function.openvas_api["get_targets"]` | Lists OpenVAS scan targets. |
| `create_task/` | Python 3.12 | `aws_lambda_function.openvas_api["create_task"]` | Creates OpenVAS scan tasks. |
| `get_tasks/` | Python 3.12 | `aws_lambda_function.openvas_api["get_tasks"]` | Lists OpenVAS scan tasks. |
| `start_scan/` | Python 3.12 | `aws_lambda_function.openvas_api["start_scan"]` | Starts an OpenVAS task by name or path parameter. |
| `openvas_parser/` | Python 3.11 | `aws_lambda_function.openvas_parser` | Parses XML reports from S3 and writes high-severity findings to DynamoDB. |
| `dynamodb_api/` | Node.js 20.x | `aws_lambda_function.dynamodb_read` | Scans the findings table and returns JSON data. |

## OpenVAS Control Functions

The OpenVAS control functions are deployed with a Terraform `for_each` loop in `openvas_lambda.tf`.

Shared behavior:

- Runtime: Python 3.12.
- Handler pattern: `<directory_name>.lambda_handler`.
- Deployment package: `./lambda/<directory_name>/<directory_name>.zip`.
- Shared layer: `../packages/gvm_layer.zip`.
- VPC config: selected VPC subnets with `aws_security_group.lambda_sg`.
- Environment variables:
  - `OPENVAS_IP`
  - `GMP_USER`
  - `GMP_PASSWORD`

These functions connect to the OpenVAS scanner on TCP `9390` and authenticate with GMP credentials.

## API Mapping

| REST API method | REST API path | Lambda directory |
|---|---|---|
| `POST` | `/port-lists` | `create_port_list/` |
| `GET` | `/port-lists` | `get_port_lists/` |
| `POST` | `/targets` | `create_target/` |
| `GET` | `/targets` | `get_targets/` |
| `POST` | `/tasks` | `create_task/` |
| `GET` | `/tasks` | `get_tasks/` |
| `POST` | `/tasks/{task_id}/start` | `start_scan/` |

## Report Parser Function

`openvas_parser/openvas_lambda.py` is triggered by S3 object-created events on:

```text
openvas-reports/*.xml
```

It performs the following work:

1. Reads the XML report from S3.
2. Finds OpenVAS result entries.
3. Keeps vulnerabilities with severity greater than `7.0`.
4. Stores one DynamoDB item per report with:
   - `pk` set to the S3 key.
   - `sk` set to `REPORT_DETAILS`.
   - `processed_timestamp`.
   - `total_high_severity_count`.
   - `vulnerabilities` list.

## Findings Read Function

`dynamodb_api/index.mjs` uses the AWS SDK for JavaScript v3 to scan the `openvas-scan-findings` table and return JSON.

Terraform uses the `archive_file` data source to package this directory into:

```text
lambda/dynamodb_api/dynamodb_read_payload.zip
```

## Packaging Notes

Most Python functions are deployed from checked-in zip artifacts. When a Python function changes, rebuild the matching zip from inside that function directory.

Example:

```bash
cd terraform-infra/lambda/create_target
zip create_target.zip create_target.py
```

Repeat the pattern for the changed function:

```bash
cd terraform-infra/lambda/start_scan
zip start_scan.zip start_scan.py
```

For the Node.js findings function, Terraform rebuilds the zip with `archive_file` during plan/apply.

## Dependencies

| Dependency | Used by | Where supplied |
|---|---|---|
| `python-gvm` | OpenVAS control functions | `../packages/gvm_layer.zip` |
| `lxml` | OpenVAS sync script and python-gvm workflows | Layer or EC2 script context depending on execution path |
| `boto3` | Parser Lambda | AWS Lambda Python runtime includes boto3 |
| `@aws-sdk/client-dynamodb` | Node.js findings Lambda | Source imports from Node package ecosystem; deployment assumes dependencies are available in the packaged artifact/runtime context |
| `@aws-sdk/lib-dynamodb` | Node.js findings Lambda | Same as above |

## Common Mistakes

| Problem | Cause | Fix |
|---|---|---|
| Lambda handler not found | Zip file does not contain the expected source file at the zip root. | Rebuild the zip from inside the function directory. |
| Terraform cannot find a zip | Artifact was deleted or renamed. | Restore the expected zip path or update Terraform. |
| OpenVAS control calls time out | Lambda cannot reach OpenVAS on `9390` or OpenVAS is not ready. | Check security groups, VPC subnets, and OpenVAS startup logs. |
| Authentication fails | `gmp_user` or `gmp_password` does not match OpenVAS. | Update Terraform variables and re-apply Lambda environment changes. |
| Parser stores no findings | Report has no severity values greater than `7.0` or XML shape differs. | Inspect the XML report and Lambda logs. |
| Findings API returns stale or empty data | DynamoDB table has no parsed report items. | Upload a valid XML report under `openvas-reports/` and check parser logs. |

## Troubleshooting

Tail parser logs:

```bash
aws logs tail /aws/lambda/s3triggerforlambda --follow --region us-east-1
```

Tail findings API logs:

```bash
aws logs tail /aws/lambda/dynamodb-read --follow --region us-east-1
```

List Lambda functions:

```bash
aws lambda list-functions --region us-east-1
```

Inspect the findings table:

```bash
aws dynamodb scan --table-name openvas-scan-findings --region us-east-1
```

## Security Notes

- REST API methods currently have no API Gateway authorizer.
- OpenVAS credentials are passed as Lambda environment variables.
- The OpenVAS control Lambdas run in the selected VPC subnets and connect to the scanner on TCP `9390`.
- Parser and read functions share the Lambda IAM role defined in `iam.tf`.
- For stronger security, move credentials to Secrets Manager or SSM Parameter Store and add API authentication.

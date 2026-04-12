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

All OpenVAS control Lambdas follow a similar structure: imports, shared GMP connection helper, request parsing, one GMP action, and API Gateway-style JSON response.

### 5.1 lambda/create_port_list/create_port_list.py

```python
import os
import json
from contextlib import contextmanager
from gvm.connections import TLSConnection
from gvm.protocols.gmp import Gmp
from gvm.transforms import EtreeTransform
from gvm.errors import GvmError

@contextmanager
def get_gmp_connection():
	openvas_ip = os.environ['OPENVAS_IP']
	gmp_user = os.environ['GMP_USER']
	gmp_password = os.environ['GMP_PASSWORD']
    
	connection = TLSConnection(hostname=openvas_ip, port=9390)
	transform = EtreeTransform()
    
	with Gmp(connection=connection, transform=transform) as gmp:
		gmp.authenticate(gmp_user, gmp_password)
		yield gmp

def lambda_handler(event, context):
	try:
		body = json.loads(event.get('body', '{}'))
		name = body.get('name')
		port_range = body.get('port_range')

		if not name or not port_range:
			return {'statusCode': 400, 'body': json.dumps({'error': 'Missing name or port_range'})}

		with get_gmp_connection() as gmp:
			response = gmp.create_port_list(name=name, port_range=port_range)
			port_list_id = response.get('id')
            
		return {
			'statusCode': 200,
			'body': json.dumps({'port_list_id': port_list_id})
		}
	except GvmError as e:
		return {'statusCode': 500, 'body': json.dumps({'error': str(e)})}
	except Exception as e:
		return {'statusCode': 500, 'body': json.dumps({'error': 'Internal server error', 'details': str(e)})}
```

Explanation :

- Reads OpenVAS connection credentials from environment variables.
- Opens a TLS GMP session on port 9390 and authenticates before use.
- Expects `name` and `port_range` in request body.
- Returns HTTP 400 if required inputs are missing.
- Calls `gmp.create_port_list(...)` and returns generated `port_list_id`.
- Separately handles GVM-specific errors and unexpected runtime errors.

### 5.2 lambda/create_target/create_target.py

```python
import os
import json
import enum
from contextlib import contextmanager
from gvm.connections import TLSConnection
from gvm.protocols.gmp import Gmp
from gvm.transforms import EtreeTransform
from gvm.errors import GvmError

# The Ultimate Bulletproof AliveTest Import
# Greenbone aggressively moves this Enum between GMP version files.
# We try the specific version modules, and if all else fails, 
# we build a perfect mock Enum that bypasses their strict type-check.
try:
	from gvm.protocols.gmpv224 import AliveTest
except ImportError:
	try:
		from gvm.protocols.gmpv225 import AliveTest
	except ImportError:
		try:
			from gvm.protocols.gmpv226 import AliveTest
		except ImportError:
			class AliveTest(enum.Enum):
				CONSIDER_ALIVE = "Consider Alive"
				SCAN_CONFIG_DEFAULT = "Scan Config Default"

@contextmanager
def get_gmp_connection():
	openvas_ip = os.environ['OPENVAS_IP']
	gmp_user = os.environ['GMP_USER']
	gmp_password = os.environ['GMP_PASSWORD']
    
	connection = TLSConnection(hostname=openvas_ip, port=9390)
	transform = EtreeTransform()
    
	with Gmp(connection=connection, transform=transform) as gmp:
		gmp.authenticate(gmp_user, gmp_password)
		yield gmp

# Helper to find an ID by Name
def get_id_by_name(gmp, entity_type, name):
	res = gmp.get_port_lists(filter_string=f"name='{name}'")
	# Handle both lxml (xpath) and standard xml (findall)
	elements = res.xpath('port_list') if hasattr(res, 'xpath') else res.findall('port_list')
	if not elements:
		raise ValueError(f"Could not find a {entity_type} named '{name}'")
	return elements[0].get('id')

def lambda_handler(event, context):
	try:
		body = json.loads(event.get('body', '{}'))
		name = body.get('name')
		hosts = body.get('hosts')
		port_list_name = body.get('port_list_name') 
        
		# Parse the string into the specific Enum object python-gvm demands
		alive_test_input = body.get('alive_test', 'Consider Alive')
        
		if alive_test_input == 'Consider Alive':
			enum_val = AliveTest.CONSIDER_ALIVE
		elif alive_test_input == 'Scan Config Default':
			enum_val = AliveTest.SCAN_CONFIG_DEFAULT
		else:
			enum_val = AliveTest.CONSIDER_ALIVE

		if not all([name, hosts, port_list_name]):
			return {'statusCode': 400, 'body': json.dumps({'error': 'Missing name, hosts, or port_list_name'})}

		with get_gmp_connection() as gmp:
			# Resolve the name to an ID first
			port_list_id = get_id_by_name(gmp, 'port_list', port_list_name)
            
			# Pass the precise Enum object (whether real or mocked)
			response = gmp.create_target(
				name=name,
				hosts=hosts,
				port_list_id=port_list_id,
				alive_test=enum_val 
			)
			target_id = response.get('id')
            
		return {
			'statusCode': 200,
			'headers': {'Content-Type': 'application/json', 'Access-Control-Allow-Origin': '*'},
			'body': json.dumps({'message': 'Target created', 'target_id': target_id})
		}
	except ValueError as ve:
		return {'statusCode': 404, 'body': json.dumps({'error': str(ve)})}
	except GvmError as e:
		return {'statusCode': 500, 'body': json.dumps({'error': str(e)})}
	except Exception as e:
		return {'statusCode': 500, 'body': json.dumps({'error': 'Internal server error', 'details': str(e)})}
```

Explanation :

- Uses compatibility imports for `AliveTest` across multiple python-gvm protocol versions.
- Includes fallback enum definition if none of the versioned imports exist.
- Resolves `port_list_name` to a real OpenVAS UUID before creating target.
- Supports `alive_test` input with sane defaults.
- Requires `name`, `hosts`, and `port_list_name`.
- Returns CORS-enabled JSON response for browser clients.

### 5.3 lambda/create_task/create_task.py

```python
import os
import json
from contextlib import contextmanager
from gvm.connections import TLSConnection
from gvm.protocols.gmp import Gmp
from gvm.transforms import EtreeTransform
from gvm.errors import GvmError

@contextmanager
def get_gmp_connection():
	openvas_ip = os.environ['OPENVAS_IP']
	gmp_user = os.environ['GMP_USER']
	gmp_password = os.environ['GMP_PASSWORD']
    
	connection = TLSConnection(hostname=openvas_ip, port=9390)
	transform = EtreeTransform()
    
	with Gmp(connection=connection, transform=transform) as gmp:
		gmp.authenticate(gmp_user, gmp_password)
		yield gmp

# Updated Helper to find IDs by Name natively in Python
def get_id_by_name(gmp, entity_type, name):
	# Ask for all items without using server-side filters
	if entity_type == 'target':
		res = gmp.get_targets()
	elif entity_type == 'config':
		res = gmp.get_scan_configs()
	elif entity_type == 'scanner':
		res = gmp.get_scanners()
        
	elements = res.xpath(entity_type) if hasattr(res, 'xpath') else res.findall(entity_type)
    
	# Loop through the results and match the name exactly
	for elem in elements:
		elem_name = elem.find('name')
		if elem_name is not None and elem_name.text == name:
			return elem.get('id')
            
	raise ValueError(f"Could not find a {entity_type} named '{name}'")

def lambda_handler(event, context):
	try:
		body = json.loads(event.get('body', '{}'))
		name = body.get('name')
		target_name = body.get('target_name')
        
		# Smart Defaults - if frontend doesn't provide these, use the standards
		config_name = body.get('config_name', 'Full and fast')
		scanner_name = body.get('scanner_name', 'OpenVAS Default')

		if not all([name, target_name]):
			return {'statusCode': 400, 'body': json.dumps({'error': 'Missing name or target_name'})}

		with get_gmp_connection() as gmp:
			# Resolve all names to their hidden UUIDs
			target_id = get_id_by_name(gmp, 'target', target_name)
			config_id = get_id_by_name(gmp, 'config', config_name)
			scanner_id = get_id_by_name(gmp, 'scanner', scanner_name)

			response = gmp.create_task(
				name=name,
				target_id=target_id,
				config_id=config_id,
				scanner_id=scanner_id
			)
			task_id = response.get('id')
            
		return {
			'statusCode': 200,
			'headers': {'Content-Type': 'application/json', 'Access-Control-Allow-Origin': '*'},
			'body': json.dumps({'message': 'Task created', 'task_id': task_id})
		}
	except ValueError as ve:
		return {'statusCode': 404, 'body': json.dumps({'error': str(ve)})}
	except GvmError as e:
		return {'statusCode': 500, 'body': json.dumps({'error': str(e)})}
	except Exception as e:
		return {'statusCode': 500, 'body': json.dumps({'error': 'Internal server error', 'details': str(e)})}
```

Explanation :

- Builds tasks using human-readable names from frontend input.
- Resolves target/config/scanner names to UUIDs in Python logic.
- Uses defaults for config (`Full and fast`) and scanner (`OpenVAS Default`).
- Returns 404 when a dependency name is not found.
- Returns CORS-enabled success payload with `task_id`.

### 5.4 lambda/start_scan/start_scan.py

```python
import os
import json
import urllib.parse
from contextlib import contextmanager
from gvm.connections import TLSConnection
from gvm.protocols.gmp import Gmp
from gvm.transforms import EtreeTransform
from gvm.errors import GvmError

@contextmanager
def get_gmp_connection():
	openvas_ip = os.environ['OPENVAS_IP']
	gmp_user = os.environ['GMP_USER']
	gmp_password = os.environ['GMP_PASSWORD']
    
	connection = TLSConnection(hostname=openvas_ip, port=9390)
	transform = EtreeTransform()
    
	with Gmp(connection=connection, transform=transform) as gmp:
		gmp.authenticate(gmp_user, gmp_password)
		yield gmp

# UPDATED HELPER: Native Python matching to bypass OpenVAS filter bugs
def get_task_id_by_name(gmp, name):
	# Ask for all tasks without using server-side filters
	res = gmp.get_tasks()
    
	# Handle the XML parsing 
	elements = res.xpath('task') if hasattr(res, 'xpath') else res.findall('task')
    
	# Loop through the results and match the name exactly
	for elem in elements:
		elem_name = elem.find('name')
		if elem_name is not None and elem_name.text == name:
			return elem.get('id')
            
	raise ValueError(f"Could not find a task named '{name}'")

def lambda_handler(event, context):
	try:
		path_parameters = event.get('pathParameters') or {}
        
		# Grab the parameter from the URL and decode spaces/special characters
		raw_task_name = path_parameters.get('task_id')
		if not raw_task_name:
			return {'statusCode': 400, 'body': json.dumps({'error': 'Missing task name in path'})}
            
		task_name = urllib.parse.unquote(raw_task_name)

		with get_gmp_connection() as gmp:
			# Resolve the name to the ID using our bulletproof python-side filter
			task_id = get_task_id_by_name(gmp, task_name)
            
			# Start the scan using the resolved ID
			response = gmp.start_task(task_id)
            
			# Extract the report_id generated for this specific scan run
			report_id = None
			if hasattr(response, 'xpath'):
				report_elem = response.xpath('report_id')
				if report_elem:
					 report_id = report_elem[0].text
			elif isinstance(response, dict):
				report_id = response.get('id')
            
		return {
			'statusCode': 200,
			'headers': {'Content-Type': 'application/json', 'Access-Control-Allow-Origin': '*'},
			'body': json.dumps({
				'message': f'Scan "{task_name}" started successfully',
				'report_id': report_id 
			})
		}
	except ValueError as ve:
		return {'statusCode': 404, 'body': json.dumps({'error': str(ve)})}
	except GvmError as e:
		return {'statusCode': 500, 'body': json.dumps({'error': str(e)})}
	except Exception as e:
		return {'statusCode': 500, 'body': json.dumps({'error': 'Internal server error', 'details': str(e)})}
```

Explanation :

- Reads task identifier from API path parameter.
- Decodes URL-encoded task name values.
- Resolves task name to true task UUID.
- Starts scan via `gmp.start_task`.
- Attempts to extract and return generated `report_id`.
- Returns 404 if task name cannot be found.

### 5.5 lambda/get_port_lists/get_port_lists.py

```python
import os
import json
from contextlib import contextmanager
from gvm.connections import TLSConnection
from gvm.protocols.gmp import Gmp
from gvm.transforms import EtreeTransform
from gvm.errors import GvmError

@contextmanager
def get_gmp_connection():
	openvas_ip = os.environ['OPENVAS_IP']
	gmp_user = os.environ['GMP_USER']
	gmp_password = os.environ['GMP_PASSWORD']
    
	connection = TLSConnection(hostname=openvas_ip, port=9390)
	transform = EtreeTransform()
    
	with Gmp(connection=connection, transform=transform) as gmp:
		gmp.authenticate(gmp_user, gmp_password)
		yield gmp

def lambda_handler(event, context):
	try:
		query_params = event.get('queryStringParameters') or {}
		# 1. Grab 'id' from the query string instead of 'name'
		search_id = query_params.get('id')

		with get_gmp_connection() as gmp:
			if search_id:
				# 2. Use the direct ID lookup method
				response = gmp.get_port_list(port_list_id=search_id)
			else:
				# Get all if no ID is provided
				response = gmp.get_port_lists()

			port_lists = []
			for item in response.xpath('port_list'):
				data = {
					'id': item.get('id'),
					'name': item.find('name').text if item.find('name') is not None else '',
					'port_count': item.find('port_count').text if item.find('port_count') is not None else '0'
				}
                
				# If a specific ID was requested, pull the exact port ranges
				if search_id:
					ranges = []
					for pr in item.xpath('port_ranges/port_range'):
						ranges.append(pr.text if pr.text else '')
					data['port_ranges'] = ranges
                    
				port_lists.append(data)
            
		return {
			'statusCode': 200,
			'headers': {'Content-Type': 'application/json', 'Access-Control-Allow-Origin': '*'},
			'body': json.dumps({'port_lists': port_lists})
		}
	except GvmError as e:
		return {'statusCode': 500, 'body': json.dumps({'error': str(e)})}
	except Exception as e:
		return {'statusCode': 500, 'body': json.dumps({'error': 'Internal error', 'details': str(e)})}
```

Explanation:

- Supports two modes: list all port lists or fetch one by `id` query string.
- Always returns normalized JSON structure for frontend usage.
- Includes optional port ranges only in specific-ID mode.
- Handles GMP and generic errors with 500 responses.

### 5.6 lambda/get_targets/get_targets.py

```python
import os
import json
from contextlib import contextmanager
from gvm.connections import TLSConnection
from gvm.protocols.gmp import Gmp
from gvm.transforms import EtreeTransform
from gvm.errors import GvmError

@contextmanager
def get_gmp_connection():
	openvas_ip = os.environ['OPENVAS_IP']
	gmp_user = os.environ['GMP_USER']
	gmp_password = os.environ['GMP_PASSWORD']
    
	connection = TLSConnection(hostname=openvas_ip, port=9390)
	transform = EtreeTransform()
    
	with Gmp(connection=connection, transform=transform) as gmp:
		gmp.authenticate(gmp_user, gmp_password)
		yield gmp

def lambda_handler(event, context):
	try:
		query_params = event.get('queryStringParameters') or {}
		# 1. Grab 'id' from the query string instead of 'name'
		search_id = query_params.get('id')

		with get_gmp_connection() as gmp:
			if search_id:
				# 2. Use the direct ID lookup method for targets
				response = gmp.get_target(target_id=search_id)
			else:
				# Get all if no ID is provided
				response = gmp.get_targets()

			targets = []
			for item in response.xpath('target'):
				port_list_elem = item.find('port_list/name')
                
				data = {
					'id': item.get('id'),
					'name': item.find('name').text if item.find('name') is not None else '',
					'port_list_name': port_list_elem.text if port_list_elem is not None else 'N/A'
				}
                
				# If a specific ID was requested, pull the advanced host details
				if search_id:
					data['hosts'] = item.find('hosts').text if item.find('hosts') is not None else ''
					data['exclude_hosts'] = item.find('exclude_hosts').text if item.find('exclude_hosts') is not None else ''
					data['max_hosts'] = item.find('max_hosts').text if item.find('max_hosts') is not None else '1'
                    
				targets.append(data)
            
		return {
			'statusCode': 200,
			'headers': {'Content-Type': 'application/json', 'Access-Control-Allow-Origin': '*'},
			'body': json.dumps({'targets': targets})
		}
	except GvmError as e:
		return {'statusCode': 500, 'body': json.dumps({'error': str(e)})}
	except Exception as e:
		return {'statusCode': 500, 'body': json.dumps({'error': 'Internal error', 'details': str(e)})}
```

Explanation:

- Supports list-all and get-by-id target retrieval.
- Returns target ID, name, and port-list display name.
- Adds host-specific fields only when querying a specific target.
- Uses consistent response envelope and CORS headers.

### 5.7 lambda/get_tasks/get_tasks.py

```python
def lambda_handler(event, context):
	try:
		query_params = event.get('queryStringParameters') or {}
		search_id = query_params.get('id')

		with get_gmp_connection() as gmp:
			if search_id:
				response = gmp.get_task(task_id=search_id)
			else:
				response = gmp.get_tasks()

			tasks = []
			for item in response.xpath('task'):
				target_elem = item.find('target/name')
                
				# Grab the raw status
				status = item.find('status').text if item.find('status') is not None else 'Unknown'
                
				data = {
					'id': item.get('id'),
					'name': item.find('name').text if item.find('name') is not None else '',
					'status': status,
					'target_name': target_elem.text if target_elem is not None else 'N/A'
				}
                
				if search_id:
					progress_elem = item.find('progress')
					raw_progress = progress_elem.text if progress_elem is not None else '0'
                    
					# --- SMART PROGRESS LOGIC ---
					if status == 'Done':
						clean_progress = '100'
					elif status in ['New', 'Requested', 'Queued'] or raw_progress == '-1':
						clean_progress = '0'
					else:
						clean_progress = raw_progress
                        
					data['progress'] = clean_progress
                    
					report_count_elem = item.find('report_count')
					scanner_elem = item.find('scanner/name')
					data['report_count'] = report_count_elem.text if report_count_elem is not None else '0'
					data['scanner_name'] = scanner_elem.text if scanner_elem is not None else 'N/A'

				tasks.append(data)
            
		return {
			'statusCode': 200,
			'headers': {'Content-Type': 'application/json', 'Access-Control-Allow-Origin': '*'},
			'body': json.dumps({'tasks': tasks})
		}
	except GvmError as e:
		return {'statusCode': 500, 'body': json.dumps({'error': str(e)})}
	except Exception as e:
		return {'statusCode': 500, 'body': json.dumps({'error': 'Internal error', 'details': str(e)})}
```

Explanation:

- Retrieves all tasks or one task by `id`.
- Returns task status and target name in all modes.
- In specific-ID mode, computes normalized progress and includes report/scanner metadata.
- Converts OpenVAS placeholders like `-1` progress into frontend-friendly values.
- Note: current file starts directly at `lambda_handler`; imports/helper definitions are not in this file.

### Parser and Data Lambdas

### 5.8 lambda/openvas_parser/openvas_lambda.py

```python
import os
import json
import urllib.parse
import xml.etree.ElementTree as ET
from datetime import datetime
from decimal import Decimal
import boto3

s3 = boto3.client('s3')
dynamodb = boto3.resource('dynamodb')

TABLE_NAME = os.environ.get('DYNAMODB_TABLE_NAME', 'openvas-scan-findings')
table = dynamodb.Table(TABLE_NAME)

def lambda_handler(event, context):
	for record in event['Records']:
		bucket = record['s3']['bucket']['name']
		key = urllib.parse.unquote_plus(record['s3']['object']['key'], encoding='utf-8')

		try:
			print(f"Fetching {key} from bucket {bucket}")
			response = s3.get_object(Bucket=bucket, Key=key)
			xml_content = response['Body'].read()

			root = ET.fromstring(xml_content)
            
			high_severity_vulns = []

			for result in root.findall('.//results/result'):
				severity_text = result.findtext('severity')
                
				if severity_text:
					try:
						severity_score = float(severity_text)
                        
						if severity_score > 7.0:
							host_elem = result.find('host')
							host_ip = host_elem.text.strip() if (host_elem is not None and host_elem.text) else 'Unknown'
                            
							vuln_data = {
								'vulnerability_name': result.findtext('name', 'Unknown'),
								'host': host_ip,
								'port': result.findtext('port', 'Unknown'),
								'threat_level': result.findtext('threat', 'Unknown'),
								'cvss_severity': Decimal(str(severity_score)), 
								'nvt_oid': result.find('nvt').attrib.get('oid', 'Unknown') if result.find('nvt') is not None else 'Unknown'
							}
							high_severity_vulns.append(vuln_data)
                            
					except ValueError:
						continue


			if high_severity_vulns:
				current_time = datetime.utcnow().isoformat()
                
				item = {
					'pk': key, 
					'sk': 'REPORT_DETAILS',
					'processed_timestamp': current_time,
					'total_high_severity_count': len(high_severity_vulns),
					'vulnerabilities': high_severity_vulns
				}

				table.put_item(Item=item)
				print(f"Successfully saved {len(high_severity_vulns)} high severity vulnerabilities for {key} to DynamoDB.")
			else:
				print(f"No high severity vulnerabilities (>7.0) found in report {key}. No DB write performed.")

		except Exception as e:
			print(f"Error processing file {key} from bucket {bucket}. Exception: {str(e)}")
			raise e

	return {
		'statusCode': 200,
		'body': json.dumps('XML processing and DynamoDB upload complete.')
	}
```

Explanation:

- Triggered by S3 ObjectCreated events.
- Loads XML reports and scans all `<result>` entries.
- Filters only findings with severity greater than 7.0.
- Persists filtered results into DynamoDB with report key as partition key.
- Stores severity as `Decimal` for DynamoDB numeric compatibility.
- Writes one summary item per processed report.

### 5.9 lambda/dynamodb_api/index.mjs

```javascript
// Replace your old require statements with these:
import { DynamoDBClient } from "@aws-sdk/client-dynamodb";
import { DynamoDBDocumentClient, ScanCommand } from "@aws-sdk/lib-dynamodb";

const client = new DynamoDBClient({});
const docClient = DynamoDBDocumentClient.from(client);

export const handler = async (event) => {
  const params = {
	TableName: "openvas-scan-findings", // Make sure this matches your DynamoDB table name
  };

  try {
	const data = await docClient.send(new ScanCommand(params));
	return {
	  statusCode: 200,
	  headers: {
		"Access-Control-Allow-Origin": "*", // Important for your frontend
		"Content-Type": "application/json"
	  },
	  body: JSON.stringify(data.Items),
	};
  } catch (err) {
	return {
	  statusCode: 500,
	  body: JSON.stringify({ error: err.message }),
	};
  }
};
```

Explanation:

- Uses AWS SDK v3 document client to simplify DynamoDB JSON handling.
- Scans the findings table and returns all rows.
- Adds permissive CORS header for browser-based clients.
- Returns raw `data.Items` as JSON body.
- Wraps failures in a 500 error response.

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

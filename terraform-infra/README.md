# Enterprise Vulnerability Assessment & Patching Automation (AWS)

## Project Overview
This project implements an enterprise-style vulnerability management workflow on AWS using Infrastructure as Code (Terraform), AWS Systems Manager, and the open-source vulnerability scanner OpenVAS (Greenbone Community Edition).

The environment simulates a real-world vulnerability management lifecycle where systems are intentionally deployed in a vulnerable state, scanned for vulnerabilities, remediated through patching, and re-scanned to validate remediation effectiveness.

The project architecture mirrors common enterprise security workflows similar to those implemented using tools such as Rapid7 InsightVM and SCCM, but implemented using cloud-native infrastructure.

---

## Architecture Summary
The environment consists of three core components:

- **OpenVAS Scanner EC2**  
  A dedicated Ubuntu-based EC2 instance running the Greenbone Community Edition (OpenVAS) scanner inside Docker containers.
  This scanner performs vulnerability assessments against the target systems and generates security reports.

- **Ubuntu 20.04 Target EC2**  
  An Ubuntu 20.04 EC2 instance intentionally configured with outdated packages and legacy services to simulate real-world vulnerabilities.

- **Windows Server 2019 Target EC2**  
  A Windows Server 2019 EC2 instance with Windows Update disabled to simulate enterprise patch lag scenarios.

All EC2 instances are managed using **AWS Systems Manager (SSM)** with no direct SSH or RDP exposure.

---

## Infrastructure Provisioning
All infrastructure is provisioned using **Terraform**, ensuring:

- Repeatable infrastructure deployments
- Version-controlled environment configuration
- Team collaboration through remote state management
- Infrastructure auditability and traceability

Terraform automatically provisions:

- EC2 instances
- IAM roles and policies
- Security groups
- S3 storage for vulnerability reports

---

### Terraform Backend Configuration
Terraform state is stored remotely to support safe collaboration between team members.

Backend configuration includes:

- **Amazon S3** for remote state storage
- **Amazon DynamoDB** for state locking
- **Server-side encryption enabled**
- **Single AWS region (us-east-1)**

This setup prevents concurrent infrastructure changes and ensures infrastructure state integrity.
---

## Repository Structure
```bash
terraform-bootstrap/
 ├── main.tf
 ├── README.md

terraform-infra/
 ├── backend.tf
 ├── main.tf
 ├── ec2.tf
 ├── sg.tf
 ├── variables.tf
 ├── outputs.tf
 ├── openvas.sh
 ├── README.md
```
**terraform-bootstrap**

Contains Terraform code used once to provision the Terraform backend infrastructure:
- S3 state bucket
- DynamoDB locking table

**terraform-infra**

Contains the main infrastructure configuration for the vulnerability management lab.

---

## OpenVAS Deployment
The OpenVAS scanner is automatically installed using a Terraform user-data script (openvas.sh) that:

1. Installs Ansible and required dependencies
2. Installs Docker
3. Downloads the official Greenbone Community Edition Docker stack
4. Pulls required container images
5. Deploys the OpenVAS stack using Docker Compose
6. The scanner exposes the **Greenbone Web UI on port 9392.**

The OpenVAS EC2 instance uses:

- Instance type: t3.large
- Root disk: 50GB
- Docker-based Greenbone deployment
- Automated provisioning using Ansible

---

## Vulnerability Simulation

To generate realistic vulnerability findings, the target systems are intentionally configured with insecure configurations.

**Ubuntu Target**

The Linux target instance disables automatic updates and installs vulnerable services including:

- Apache
- Samba
- MySQL
- Telnet
- RSH
- SNMP
- PHP
- VSFTPD
This creates multiple detectable vulnerabilities for OpenVAS scanning.

**Windows Target**

The Windows target disables automatic patching by:
- Disabling the Windows Update service
- Blocking automatic updates via registry policy

This allows the scanner to detect missing security patches and OS vulnerabilities.

---

## S3-Based Vulnerability Report Storage

An Amazon S3 bucket is created for storing OpenVAS scan reports.

The bucket includes logical directories for organizing reports:

```bash
s3://capstone-vuln-mgmt-openvas-reports/
 ├── linux/
 └── windows/
```

The OpenVAS instance receives a dedicated IAM policy allowing it to upload scan results to this bucket.

---

## Access Model

Administrative access to the environment follows security best practices:

- AWS Systems Manager Session Manager is used for EC2 management
- SSH access is limited to the OpenVAS host
- No direct RDP access is required for Windows management
- Target machines accept scanning traffic only from the scanner

This architecture reduces attack surface while maintaining operational access.

---

## Project Workflow

1) AWS account hardening and governance
2) Deploy infrastructure using Terraform
3) Establish a vulnerable baseline environment
4) Run vulnerability scans using OpenVAS
5) Export scan reports to Amazon S3
6) Analyze vulnerabilities using CVSS scores
7) Apply remediation patches using AWS Systems Manager
8) Perform re-scans to verify remediation effectiveness
9) Generate final vulnerability metrics and reports

---

## Key Learning Outcomes

This project demonstrates practical experience with:

- Infrastructure as Code using Terraform
- Cloud security architecture design
- Enterprise vulnerability management workflows
- Vulnerability scanning and CVSS risk analysis
- Secure AWS environment configuration
- Automated infrastructure deployment

---

## Disclaimer

This environment intentionally deploys vulnerable systems for educational purposes only. These configurations must never be used in production environments.

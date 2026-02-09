# Enterprise Vulnerability Assessment & Patching Automation (AWS)

## Project Overview
This project implements an enterprise-style vulnerability management workflow on AWS, inspired by industry tools such as Rapid7 InsightVM and SCCM, using cloud-native services and open-source tooling.

The solution demonstrates how operating system–level vulnerabilities can be identified, prioritized, remediated, and validated in a controlled cloud environment using Infrastructure as Code (Terraform) and AWS Systems Manager.

---

## Architecture Summary
The environment consists of three core components:

- **OpenVAS Scanner EC2**  
  Hardened Ubuntu-based instance used exclusively for vulnerability scanning.

- **Ubuntu 20.04 Target EC2**  
  Linux target intentionally left unpatched and configured with vulnerable services for baseline vulnerability assessment.

- **Windows Server 2019 Target EC2**  
  Windows target with automatic updates disabled to simulate enterprise patch lag scenarios.

All EC2 instances are managed using **AWS Systems Manager (SSM)** with no direct SSH or RDP exposure.

---

## Infrastructure as Code
All infrastructure is provisioned using **Terraform**, ensuring:

- Repeatable deployments
- Version-controlled configuration
- Team collaboration using a remote Terraform backend
- Enterprise-aligned governance and auditability

### Terraform Backend
- **S3** for remote state storage
- **DynamoDB** for state locking
- **us-east-1** as the standardized region

---

## OpenVAS Scanner Design Decision
The OpenVAS EC2 instance is provisioned as a **hardened base system only**:

```bash
apt update && apt upgrade -y
```

### Rationale

OpenVAS installation and feed synchronization are intentionally not automated in Terraform user data due to their long-running, stateful, and interactive nature.

This approach:

- Prevents package corruption during bootstrapping

- Avoids cloud-init timeouts

- Mirrors real-world enterprise scanner deployments

- Allows controlled troubleshooting and documentation

Scanner installation and configuration are performed manually by the designated team member responsible for vulnerability assessment.

---

## Intentional Vulnerabilities (Targets)

The Ubuntu and Windows target instances are intentionally configured to introduce vulnerabilities:

Ubuntu 20.04

- Automatic updates disabled

- Kernel updates held

- Legacy and commonly vulnerable services installed

- Used to demonstrate Linux package and configuration vulnerabilities

Windows Server 2019

- Windows Update service disabled

- Automatic updates blocked via registry policy

- Used to demonstrate missing OS patch vulnerabilities

These configurations create a consistent baseline vulnerability state for before-and-after remediation analysis.

## Access Model

- AWS Systems Manager Session Manager is used for all administrative access

- No inbound security group rules

- No public IP exposure

- No SSH or RDP access

This aligns with enterprise security best practices.

## Project Phases

1) AWS account hardening and governance

2) Infrastructure deployment using Terraform

3) Intentional vulnerability baseline creation

4) Vulnerability scanning using OpenVAS

5) Risk-based analysis and prioritization

4) Manual patch remediation using AWS SSM

5) Post-remediation re-scanning and validation

6) Reporting and metrics generation

## Key Learning Outcomes

- Enterprise vulnerability management workflows

- Secure cloud infrastructure design

- Infrastructure as Code collaboration

- Risk-based patch decision-making

- Audit-ready security documentation

## Notes

This repository focuses on infrastructure provisioning and target configuration. Scanner setup, scan execution, and report generation are documented separately as part of the vulnerability assessment phase.

## Disclaimer

This project is for educational purposes only. Vulnerable configurations are intentionally created in an isolated environment and must never be deployed in production systems.
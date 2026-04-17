# OpenVAS Screenshots

This folder contains OpenVAS web interface screenshots extracted from `OpenVas_findings.docx` and renamed for repository use. They are presentation evidence for the vulnerability scanning workflow and should be treated as supporting documentation, not Terraform-managed infrastructure definitions.

## Naming Convention

- Use lowercase kebab-case.
- Prefix each image with `openvas-`.
- Use a name that describes the screen or workflow stage.
- Avoid generic names such as `image1.png`.

## Screenshot Index

| File | What it shows |
|---|---|
| `openvas-dashboard-overview.png` | Dashboard charts for task severity, task status, CVE creation time, and NVT severity. |
| `openvas-tasks-summary-dashboard.png` | Task dashboard with severity, high-results-per-host, and task status charts. |
| `openvas-task-list-severity.png` | OpenVAS task list with completed scans and severity ratings. |
| `openvas-reports-summary-dashboard.png` | Report dashboard with report severity and CVSS chart summaries. |
| `openvas-report-list-severity-counts.png` | Report list showing per-report critical, high, medium, low, and log counts. |
| `openvas-results-summary-dashboard.png` | Results dashboard with severity class and CVSS distribution. |
| `openvas-results-critical-findings.png` | Findings list showing critical vulnerabilities and affected hosts. |
| `openvas-vulnerabilities-summary.png` | Vulnerability dashboard and high-severity vulnerability list. |
| `openvas-hosts-severity-topology.png` | Host severity distribution, host topology, and host inventory. |
| `openvas-operating-systems-severity.png` | Operating system inventory and vulnerability severity distribution. |
| `openvas-tls-certificates-inventory.png` | TLS certificate inventory and validity status. |
| `openvas-nvt-security-information.png` | Network Vulnerability Test catalog summary and NVT records. |
| `openvas-cve-security-information.png` | CVE catalog summary and CVE records. |
| `openvas-cpe-security-information.png` | CPE catalog summary and CPE records. |
| `openvas-configured-targets.png` | Configured scan targets for Ubuntu and Windows hosts. |
| `openvas-port-lists.png` | Available OpenVAS port lists and TCP/UDP coverage. |
| `openvas-scan-configs.png` | Available scan configurations such as Base, Discovery, Full and fast, and Log4Shell. |

## Usage

Reference screenshots from Markdown with repository-relative paths:

```md
![OpenVAS dashboard overview](openvas-dashboard-overview.png)
```

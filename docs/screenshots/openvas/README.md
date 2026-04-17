# OpenVAS Screenshots

This folder contains OpenVAS web interface screenshots used as visual evidence for the vulnerability scanning workflow. The images support the project README by showing the scanner dashboard, scan tasks, reports, findings, asset views, security information, and scan configuration screens.

## Naming Convention

- Use lowercase kebab-case.
- Prefix each image with `openvas-`.
- Use a name that describes the screen or workflow stage.
- Avoid generic names such as `image1.png`.

## Workflow Gallery

| Dashboard overview |
|---|
| ![OpenVAS dashboard overview](openvas-dashboard-overview.png) |
| Shows the main OpenVAS dashboard with task severity, task status, CVE creation time, and NVT severity charts. |

| Task summary | Task list |
|---|---|
| ![OpenVAS tasks summary dashboard](openvas-tasks-summary-dashboard.png) | ![OpenVAS task list severity](openvas-task-list-severity.png) |
| Task dashboard with severity, high-results-per-host, and status charts. | Completed scan tasks with report links and severity ratings. |

| Reports summary | Report severity counts |
|---|---|
| ![OpenVAS reports summary dashboard](openvas-reports-summary-dashboard.png) | ![OpenVAS report list severity counts](openvas-report-list-severity-counts.png) |
| Report dashboard with severity and CVSS chart summaries. | Per-report critical, high, medium, low, and log finding counts. |

| Results summary | Critical findings |
|---|---|
| ![OpenVAS results summary dashboard](openvas-results-summary-dashboard.png) | ![OpenVAS critical findings](openvas-results-critical-findings.png) |
| Results dashboard with severity class and CVSS distribution. | Findings list showing critical vulnerabilities and affected hosts. |

| Vulnerability summary |
|---|
| ![OpenVAS vulnerability summary](openvas-vulnerabilities-summary.png) |
| Vulnerability dashboard and high-severity vulnerability list. |

## Asset And Inventory Views

| Hosts severity and topology |
|---|
| ![OpenVAS hosts severity and topology](openvas-hosts-severity-topology.png) |
| Host severity distribution, host topology, and discovered host inventory. |

| Operating systems severity | TLS certificate inventory |
|---|---|
| ![OpenVAS operating systems severity](openvas-operating-systems-severity.png) | ![OpenVAS TLS certificate inventory](openvas-tls-certificates-inventory.png) |
| Operating system inventory and vulnerability severity distribution. | TLS certificate inventory and validity status. |

## Security Information Views

| NVT security information |
|---|
| ![OpenVAS NVT security information](openvas-nvt-security-information.png) |
| Network Vulnerability Test catalog summary and NVT records. |

| CVE security information | CPE security information |
|---|---|
| ![OpenVAS CVE security information](openvas-cve-security-information.png) | ![OpenVAS CPE security information](openvas-cpe-security-information.png) |
| CVE catalog summary and CVE records. | CPE catalog summary and CPE records. |

## Configuration Views

| Configured targets | Port lists |
|---|---|
| ![OpenVAS configured targets](openvas-configured-targets.png) | ![OpenVAS port lists](openvas-port-lists.png) |
| Configured scan targets for Ubuntu and Windows hosts. | Available OpenVAS port lists and TCP/UDP coverage. |

| Scan configs |
|---|
| ![OpenVAS scan configs](openvas-scan-configs.png) |
| Available scan configurations such as Base, Discovery, Full and fast, and Log4Shell. |

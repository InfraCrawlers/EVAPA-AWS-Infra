# Scripts

This folder contains EC2 bootstrap scripts and the OpenVAS report sync helper used by the EVAPA lab.

Terraform references these scripts from `ec2.tf`, and `openvas.sh` installs `auto.py` onto the scanner host during initialization.

## Files

| File | Used by | Purpose |
|---|---|---|
| `linux.sh` | `aws_instance.linux_ubuntu.user_data` | Builds the Ubuntu vulnerable target by installing vulnerable services and applications. |
| `windows.ps1` | `aws_instance.windows.user_data_base64` | Configures the Windows vulnerable target with weak patch posture and vulnerable services. |
| `openvas.sh` | `aws_instance.openvas.user_data` | Installs dependencies, Docker, Greenbone Community Edition, GMP proxy, AWS tooling, and report sync cron job. |
| `auto.py` | Downloaded by `openvas.sh` onto the OpenVAS host | Exports completed OpenVAS XML reports to the S3 reports bucket. |

## Execution Flow

![alt text](<Scripts flow.png>)

## Linux Target Script

`linux.sh` installs and exposes vulnerable lab software on Ubuntu 20.04, including:

- ProFTPD 1.3.5e
- Apache
- MySQL
- PHP
- Apache Struts 2.3.20.1 samples
- Tomcat 8.5.15
- Drupal 7.31
- WordPress 4.7.1
- Elasticsearch 1.1.1
- Amazon SSM Agent

The script starts services and binds selected applications to network-visible interfaces so OpenVAS can detect them during scans.

## Windows Target Script

`windows.ps1` configures Windows Server 2019 for vulnerability assessment exercises:

- Disables Windows Update.
- Enables legacy TLS 1.0 and TLS 1.1 settings.
- Creates `C:\vulnapps`.
- Opens selected inbound firewall ports.
- Installs Java 8.
- Downloads and configures FileZilla Server 0.9.41.
- Downloads and configures Elasticsearch 1.1.1.
- Registers a startup task to restart lab services.

## OpenVAS Scanner Script

`openvas.sh` prepares the scanner host:

- Installs Python, Ansible, boto3, python-gvm, lxml, AWS CLI v2, and the Session Manager plugin.
- Installs Docker and Docker Compose.
- Downloads the Greenbone Community Edition compose file.
- Modifies the compose file to expose web ports and inject a GMP proxy on `9390`.
- Pulls and starts Greenbone containers.
- Installs a cron job that runs the report sync script every five minutes.
- Writes logs to `/var/log/user-data-openvas-docker.log`.

OpenVAS/Greenbone startup can take a long time because it downloads containers and initializes vulnerability feeds.

## Report Sync Script

`auto.py` connects to the Greenbone Unix socket on the scanner instance, finds completed reports, downloads XML report content, and uploads each new report to:

```text
s3://capstone-vuln-mgmt-openvas-reports/openvas-reports/<report_id>.xml
```

The script tracks sent report IDs in:

```text
/opt/openvas_scripts/sent_reports.json
```

## Important Configuration Notes

- `auto.py` contains project-specific values such as bucket name, OpenVAS credentials, socket path, and S3 prefix.
- `openvas.sh` downloads `auto.py` from the GitHub repository URL configured in the script.
- EC2 user-data runs at first boot. Changing a script after an instance exists does not automatically rerun it.
- The scripts depend on outbound internet access for package downloads and container pulls.

## Re-running User Data

For a clean rerun, recreate the affected EC2 instance through Terraform:

```bash
terraform apply -replace=aws_instance.openvas
```

Use the same pattern for target instances:

```bash
terraform apply -replace=aws_instance.linux_ubuntu
terraform apply -replace=aws_instance.windows
```

Use replacement carefully because it destroys and recreates the instance.

## Validation

Check OpenVAS bootstrap logs:

```bash
sudo tail -f /var/log/user-data-openvas-docker.log
```

Check Linux exposed ports:

```bash
sudo netstat -tulpn
```

Check Windows completion marker:

```powershell
Get-Content C:\vuln-build-complete.txt
Get-Content C:\vuln-setup-log.txt
```

Check uploaded reports:

```bash
aws s3 ls s3://capstone-vuln-mgmt-openvas-reports/openvas-reports/ --region us-east-1
```

## Common Mistakes

| Problem | Cause | Fix |
|---|---|---|
| OpenVAS web UI is not ready | Greenbone feed/container initialization is still running. | Check user-data logs and wait for containers to stabilize. |
| No XML reports reach S3 | `auto.py` has not run, OpenVAS report is not `Done`, or IAM/S3 configuration is wrong. | Check cron logs, S3 permissions, and report status. |
| Script changes do not affect existing EC2 | User-data runs only on initial launch. | Recreate or manually update the instance. |
| Package download failures | Internet access or upstream repository issue. | Retry instance creation or check outbound network path. |
| OpenVAS Lambda cannot connect | GMP proxy on `9390` is not running or security groups block traffic. | Check Docker compose services and security group rules. |

## Security Notes

- These scripts intentionally create vulnerable systems.
- Default credentials and hardcoded project values should be replaced before any serious lab demonstration.
- Public OpenVAS web access should be restricted to trusted IP ranges in a stronger deployment.
- The report sync script should eventually read secrets and bucket names from managed configuration rather than literals.

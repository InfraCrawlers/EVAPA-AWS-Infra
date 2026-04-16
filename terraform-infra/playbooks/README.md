# Ansible Playbooks

This folder contains Ansible assets used for EVAPA patching and remediation exercises.

The current inventory is configured for AWS Systems Manager transport, which aligns with the project goal of avoiding direct SSH/RDP administration for patching.

## Files

| File | Purpose |
|---|---|
| `inventory.ini` | SSM-based inventory with sample EC2 instance IDs for Linux and Windows targets. |
| `linux_patching.yml` | Installs and starts vulnerable Linux lab applications. Despite the filename, the current playbook is a vulnerable lab setup playbook, not a remediation playbook. |
| `win_patching.yml` | Re-enables Windows Update, replaces vulnerable Elasticsearch with a newer version, reboots, and installs Windows security/critical updates. |

## Inventory Model

`inventory.ini` uses EC2 instance IDs instead of IP addresses:

```ini
[linux]
i-06101a19045d951e3

[windows]
i-01db4da2c43c5b202
```

These IDs are examples from a previous environment. After running Terraform, update them with your own output:

```bash
cd terraform-infra
terraform output ec2_instances
```

## Requirements

Install the Ansible collections used by the inventory and playbooks:

```bash
ansible-galaxy collection install amazon.aws community.aws ansible.windows community.windows
```

The control machine also needs:

- AWS credentials for SSM.
- AWS Session Manager plugin.
- Access to the S3 SSM/Ansible bucket.
- EC2 instances with SSM Agent running.
- EC2 instance profile from `aws_iam_instance_profile.ssm_profile`.

## Run Commands

Linux lab setup:

```bash
cd terraform-infra
ansible-playbook -i playbooks/inventory.ini playbooks/linux_patching.yml
```

Windows remediation:

```bash
cd terraform-infra
ansible-playbook -i playbooks/inventory.ini playbooks/win_patching.yml
```

## Linux Playbook Behavior

`linux_patching.yml` currently:

- Installs build and runtime dependencies.
- Downloads and builds ProFTPD 1.3.5e.
- Downloads Struts 2.3.20.1.
- Installs Tomcat 8.5.15.
- Installs Drupal 7.31 and WordPress 4.7.1.
- Installs Elasticsearch 1.1.1.
- Starts MySQL, Tomcat, and Elasticsearch.

This overlaps with `scripts/linux.sh`, which also builds the vulnerable Linux target through EC2 user-data. Treat this playbook as a manual/replayable lab setup asset unless it is refactored into a true remediation playbook.

## Windows Playbook Behavior

`win_patching.yml` currently:

- Re-enables Windows Update through registry and service settings.
- Applies a WinRM profile unload fix.
- Stops running Java/Elasticsearch processes.
- Removes the vulnerable Elasticsearch directory.
- Downloads Elasticsearch 7.17.10.
- Extracts the patched Elasticsearch package.
- Reboots the instance.
- Installs Windows security and critical updates.

## SSM Transport Flow

![alt text](<SSM flow.png>)

## Common Mistakes

| Problem | Cause | Fix |
|---|---|---|
| `TargetNotConnected` | SSM Agent is not online or IAM profile is missing. | Check `aws ssm describe-instance-information`. |
| Playbook runs against old instance | `inventory.ini` contains stale IDs. | Replace IDs with `terraform output ec2_instances`. |
| SSM plugin not found | Session Manager plugin is missing or path differs. | Install the plugin and update `ansible_aws_ssm_plugin` if needed. |
| S3 bucket access fails | IAM role or bucket name mismatch. | Confirm `${project_name}-ssm-ansible-bucket` exists and policies are attached. |
| Windows tasks fail after update changes | Windows Update or reboot temporarily disrupts connectivity. | Re-run after the instance returns to SSM online status. |

## Troubleshooting

Check SSM managed instances:

```bash
aws ssm describe-instance-information --region us-east-1
```

Check the SSM/Ansible bucket:

```bash
aws s3 ls s3://capstone-vuln-mgmt-ssm-ansible-bucket --region us-east-1
```

Run with verbose Ansible logging:

```bash
ansible-playbook -vvv -i playbooks/inventory.ini playbooks/win_patching.yml
```

## Improvement Opportunities

- Rename `linux_patching.yml` if it remains a vulnerable setup playbook.
- Split Linux setup and Linux remediation into separate playbooks.
- Generate `inventory.ini` dynamically from Terraform outputs.
- Add patch result reporting back into S3 or DynamoDB.
- Remove hardcoded sample instance IDs from the checked-in inventory.

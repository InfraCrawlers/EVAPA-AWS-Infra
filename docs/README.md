# Documentation Assets

This folder stores visual assets used by the project README files.

## Folder Convention

| Folder | Asset type | Naming convention |
|---|---|---|
| `diagrams/` | Rendered architecture, workflow, and process diagrams | Lowercase kebab-case, descriptive, ends in `.png` |
| `screenshots/` | AWS console screenshots and presentation evidence | Lowercase kebab-case, service-oriented, ends in `.png` |

## Naming Rules

- Use lowercase letters, numbers, and hyphens.
- Do not use spaces.
- Do not use generic names such as `image.png` or `image-1.png`.
- Include the subject in the filename, such as `aws-lambda-functions.png`.
- Keep screenshots and diagrams separate so README references stay easy to maintain.

## Current Assets

```text
docs/
|-- diagrams/
|   |-- dataflow-sequence.png
|   |-- deployment-lifecycle.png
|   |-- lab-architecture.png
|   |-- scripts-flow.png
|   |-- ssm-ansible-flow.png
|   |-- terraform-bootstrap-flow.png
|   |-- terraform-infra-architecture.png
|   |-- terraform-infra-workflow.png
|   `-- terraform-state-flow.png
`-- screenshots/
    |-- aws-api-gateway-apis.png
    |-- aws-api-gateway-apis-alt.png
    |-- aws-dynamodb-tables.png
    |-- aws-ec2-instances.png
    |-- aws-iam-users.png
    |-- aws-lambda-functions.png
    `-- aws-s3-buckets.png
```

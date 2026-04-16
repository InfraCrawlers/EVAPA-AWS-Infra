# Packages

This folder stores packaged runtime dependencies used by Terraform-managed Lambda functions.

## Files

| File | Used by | Purpose |
|---|---|---|
| `gvm_layer.zip` | `aws_lambda_layer_version.gvm_layer` in `openvas_lambda.tf` | Lambda layer for OpenVAS control functions that use python-gvm/GMP dependencies. |

## How Terraform Uses This Folder

`openvas_lambda.tf` creates the Lambda layer:

```hcl
resource "aws_lambda_layer_version" "gvm_layer" {
  filename            = "./packages/gvm_layer.zip"
  layer_name          = "python_gvm_library"
  compatible_runtimes = ["python3.12"]
  source_code_hash    = filebase64sha256("./packages/gvm_layer.zip")
}
```

The OpenVAS control Lambdas attach the layer:

```hcl
layers = [aws_lambda_layer_version.gvm_layer.arn]
```

## Why It Exists

The OpenVAS control Lambdas need dependencies that are not included in the default AWS Lambda Python runtime. Packaging those dependencies as a Lambda layer keeps each function zip small and avoids duplicating the same dependency files across every OpenVAS control function.

## Operational Notes

- Keep `gvm_layer.zip` in this folder unless Terraform is updated to point elsewhere.
- If the layer changes, Terraform detects the new `source_code_hash` and publishes a new layer version.
- The layer is declared compatible with Python 3.12 because the OpenVAS control Lambdas run on Python 3.12.
- The parser Lambda uses Python 3.11 and does not attach this layer in the current Terraform.

## Common Mistakes

| Problem | Cause | Fix |
|---|---|---|
| Terraform cannot read `gvm_layer.zip` | File is missing or path changed. | Restore the zip or update `openvas_lambda.tf`. |
| Lambda import errors for `gvm` | Layer does not contain expected python-gvm package structure. | Rebuild the layer with dependencies under the correct `python/` directory layout. |
| Runtime mismatch | Layer built for a different Python version. | Rebuild for Python 3.12 or adjust Lambda runtime and layer compatibility together. |

## Future Improvement

Add a reproducible build script for `gvm_layer.zip`, such as:

```bash
mkdir -p layer/python
pip install python-gvm lxml -t layer/python
cd layer
zip -r ../gvm_layer.zip python
```

The exact dependency versions should be pinned before using this in a production-style workflow.

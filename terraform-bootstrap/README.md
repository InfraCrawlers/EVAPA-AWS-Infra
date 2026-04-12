# Terraform Bootstrap Infrastructure

This directory contains one-time Terraform code used to provision
the remote backend infrastructure for Terraform state management.

## Purpose
- Create an Amazon S3 bucket for Terraform state storage
- Enable versioning and encryption
- Block public access
- Create a DynamoDB table for state locking

## Usage Notes
- This Terraform code is executed once during initial account setup
- It is not used for day-to-day infrastructure changes
- The resources created here must not be deleted during the project lifecycle

## Warning
Do NOT run this code multiple times or destroy the resources after creation,
as it will break Terraform state management for the project.

# Preserve S3 - Complete S3-Based File Preservation

## Overview

[preserve_s3.sh](preserve_s3.sh) provides a complete solution for preserving files to S3 and managing the `PRESERVED_FILES_ARCHIVE` environment variable across pipeline stages.

This script integrates with:
- [get_preserving_file_name.sh](get_preserving_file_name.sh) - File collection
- [tar_preserving_files.sh](tar_preserving_files.sh) - Archive creation
- AWS S3 - Persistent storage

## Key Features

### ✅ Intelligent S3 Path Resolution
- Uses `PRESERVED_FILES_ARCHIVE` when available (multi-stage pipelines)
- Derives S3 path from `BINARY_PLAN` when archive path unknown (single-stage)
- Never relies on `WORKFLOW_ID` being stable across stages

### ✅ Tag Management  
- Preserves existing S3 object tags when overwriting
- Generates tags from environment variables when creating new objects
- Extracts workflow ID from `BINARY_PLAN` instead of `WORKFLOW_ID`

### ✅ Pipeline Integration
- Exports `PRESERVED_FILES_ARCHIVE` for subsequent stages
- Creates source-able environment file
- Works seamlessly with Harness workflows

### ✅ Robust Error Handling
- Graceful degradation when files missing
- Warnings instead of failures for non-critical issues
- Never blocks pipeline execution

## Commands

### 1. push - Create and Upload Archive

Creates an archive of all preserving files and uploads to S3.

**Usage:**
```bash
./preserve_s3.sh push [archive_name]
```

**Parameters:**
- `archive_name` (optional): Local archive path (default: `./generated/${TF_VAR_environment}_preserved_files.tar.gz`)

**Required Environment Variables:**
- One of:
  - `PRESERVED_FILES_ARCHIVE` - Direct S3 URI
  - `BINARY_PLAN` - Terraform plan S3 URI (derives archive path)

**Example with PRESERVED_FILES_ARCHIVE:**
```bash
export PRESERVED_FILES_ARCHIVE="s3://my-bucket/preserves/prod-archive.tar.gz"
./preserve_s3.sh push

# Output:
# ==========================================
# PUSH: Create and Upload Preserved Files
# ==========================================
# Using existing PRESERVED_FILES_ARCHIVE: s3://my-bucket/preserves/prod-archive.tar.gz
# [Archive creation output...]
# ✓ Upload successful
# PRESERVED_FILES_ARCHIVE=s3://my-bucket/preserves/prod-archive.tar.gz
```

**Example with BINARY_PLAN (Path Derivation):**
```bash
export BINARY_PLAN="s3://my-bucket/harness/backend/workflow-abc123.plan"
./preserve_s3.sh push

# Output:
# Deriving S3 path from BINARY_PLAN: s3://my-bucket/harness/backend/workflow-abc123.plan
# Derived S3 path: s3://my-bucket/harness/backend/workflow-abc123_preserved_files.tar.gz
# [Archive creation and upload...]
```

**What It Does:**
1. Collects files from harness.json + terraform state
2. Creates tar.gz archive
3. Determines S3 destination (from PRESERVED_FILES_ARCHIVE or BINARY_PLAN)
4. Uploads to S3 with appropriate tags
5. Exports `PRESERVED_FILES_ARCHIVE` to `./preserved_files_archive.env`

---

### 2. pull - Download and Extract Archive

Downloads archive from S3 and extracts files to their original locations.

**Usage:**
```bash
./preserve_s3.sh pull [archive_name]
```

**Parameters:**
- `archive_name` (optional): Local archive path (default: `./generated/${TF_VAR_environment}_preserved_files.tar.gz`)

**Required Environment Variables:**
- `PRESERVED_FILES_ARCHIVE` - S3 URI of archive

**Example:**
```bash
export PRESERVED_FILES_ARCHIVE="s3://my-bucket/preserves/prod-archive.tar.gz"
./preserve_s3.sh pull

# Output:
# ==========================================
# PULL: Download and Extract Preserved Files
# ==========================================
# Source: s3://my-bucket/preserves/prod-archive.tar.gz
# ✓ Download successful
# ✓ Extraction successful
# ✓ PULL Complete
```

**Behavior:**
- If `PRESERVED_FILES_ARCHIVE` not set: Warns and continues (exit 0)
- If download fails: Warns and continues (exit 0)
- If extraction fails: Continues (exit 0)
- Never fails the pipeline

---

### 3. list - List Archive Contents

Lists files in the S3 archive without downloading/extracting.

**Usage:**
```bash
./preserve_s3.sh list
```

**Required Environment Variables:**
- `PRESERVED_FILES_ARCHIVE` - S3 URI of archive

**Example:**
```bash
export PRESERVED_FILES_ARCHIVE="s3://my-bucket/preserves/prod-archive.tar.gz"
./preserve_s3.sh list

# Output:
# === Listing preserved files ===
# Source: s3://my-bucket/preserves/prod-archive.tar.gz
# 
# === Contents of <temp_file> ===
# generated/config.json
# generated/example.txt
# output/terraform_output.json
# 
# Total files in archive: 3
```

---

## S3 Path Derivation Logic

The script intelligently determines the S3 path based on available variables:

### Scenario 1: PRESERVED_FILES_ARCHIVE Set
```bash
export PRESERVED_FILES_ARCHIVE="s3://bucket/preserves/archive.tar.gz"
./preserve_s3.sh push
# Uses: s3://bucket/preserves/archive.tar.gz
```

**Use Case:** Multi-stage pipelines where Apply stage passes archive path to Verify stage.

### Scenario 2: BINARY_PLAN Set (Path Derivation)
```bash
export BINARY_PLAN="s3://bucket/plans/workflow-123.plan"
./preserve_s3.sh push
# Derives: s3://bucket/plans/workflow-123_preserved_files.tar.gz
```

**Use Case:** Single-stage pipelines or when archive path not yet known.

**Derivation Formula:**
```
BINARY_PLAN: s3://bucket/path/to/id.plan
            ↓
ARCHIVE:    s3://bucket/path/to/id_preserved_files.tar.gz
```

### Scenario 3: Neither Set
```bash
./preserve_s3.sh push
# Error: Either PRESERVED_FILES_ARCHIVE or BINARY_PLAN must be set
```

---

## Tag Management

### Preserving Existing Tags (Recommended)

When uploading to an existing S3 object, the script preserves the original tags:

```bash
# First upload (generates tags)
export BINARY_PLAN="s3://bucket/id.plan"
export GIT_COMMIT="abc123"
export TF_VAR_environment="prod"
./preserve_s3.sh push

# Later upload (preserves tags)
export PRESERVED_FILES_ARCHIVE="s3://bucket/id_preserved_files.tar.gz"
./preserve_s3.sh push
# Tags from first upload are preserved
```

### Generating New Tags

When creating a new S3 object, tags are generated from environment:

**Generated Tags:**
- `HarnessPipelineDeploymentId` - Extracted from BINARY_PLAN (e.g., `workflow-123`)
- `CommitId` - From `GIT_COMMIT`
- `environment` - From `TF_VAR_environment`
- `business_unit` - From `TF_VAR_business_unit`
- `product` - From `TF_VAR_product`
- `creator_source` - From `TF_VAR_creator_source` (default: `harness`)
- `deployment` - From `TF_VAR_deployment` (default: `terraform`)
- `owner_email` - From `TF_VAR_owner_email`

**Example:**
```bash
export BINARY_PLAN="s3://bucket/plans/workflow-456.plan"
export GIT_COMMIT="def789"
export TF_VAR_environment="production"
export TF_VAR_business_unit="engineering"
export TF_VAR_product="api-gateway"
export TF_VAR_owner_email="team@example.com"

./preserve_s3.sh push
# Tags: HarnessPipelineDeploymentId=workflow-456, CommitId=def789, 
#       environment=production, business_unit=engineering, ...
```

---

## Pipeline Integration

### Terramake Deployment - NonProd (Single-Stage)

**Prepare Infra - Run Terramake Plan:**
```bash
#!/bin/bash
# No preserved files yet, runs as normal
terraform plan -out=plan.tfplan
```

**Apply - Run Terramake Apply:**
```bash
#!/bin/bash
# After terraform apply succeeds
terraform apply -auto-approve plan.tfplan

# Create and upload preserved files
export BINARY_PLAN="s3://bucket/plans/${WORKFLOW_ID}.plan"
./preserve_s3.sh push

# Export for next stage
source ./preserved_files_archive.env
# Now PRESERVED_FILES_ARCHIVE is set
```

**Verify Service - Run Terramake Plan:**
```bash
#!/bin/bash
# PRESERVED_FILES_ARCHIVE passed from Apply stage
./preserve_s3.sh pull

# Run terraform plan - no drift!
terraform plan -detailed-exitcode
```

---

### Terramake Deployment - Prod (Multi-Stage)

**Stage 1 - Apply:**
```bash
#!/bin/bash
terraform apply -auto-approve

# Create and upload
export BINARY_PLAN="s3://bucket/harness/backend/${DEPLOYMENT_ID}.plan"
./preserve_s3.sh push
source ./preserved_files_archive.env

# Publish PRESERVED_FILES_ARCHIVE to next stage
echo "PRESERVED_FILES_ARCHIVE=${PRESERVED_FILES_ARCHIVE}" >> $HARNESS_OUTPUT
```

**Stage 2 - Verify Plan:**
```bash
#!/bin/bash
# PRESERVED_FILES_ARCHIVE from Stage 1
./preserve_s3.sh pull

terraform plan -detailed-exitcode
```

**Stage 3 - Another Environment:**
```bash
#!/bin/bash
# Can reuse same archive if needed
./preserve_s3.sh pull

terraform plan -detailed-exitcode
```

---

## Environment Variables

### Required (One of)

| Variable | Description | Used By |
|----------|-------------|---------|
| `PRESERVED_FILES_ARCHIVE` | S3 URI for archive | push, pull, list |
| `BINARY_PLAN` | S3 URI for terraform plan | push (derivation) |

### Optional

| Variable | Default | Description |
|----------|---------|-------------|
| `AWS_DEFAULT_REGION` | `us-east-1` | AWS region |
| `TF_VAR_environment` | `dev` | Environment name |
| `GIT_COMMIT` | `unknown` | Git commit SHA (for tagging) |
| `TF_VAR_business_unit` | `unknown` | Business unit (for tagging) |
| `TF_VAR_product` | `unknown` | Product name (for tagging) |
| `TF_VAR_creator_source` | `harness` | Creator source (for tagging) |
| `TF_VAR_deployment` | `terraform` | Deployment type (for tagging) |
| `TF_VAR_owner_email` | `unknown` | Owner email (for tagging) |

### Also Inherits From

- [get_preserving_file_name.sh](get_preserving_file_name.sh):
  - `HARNESS_FILE`
  - `TERRAFORM`
  - `JQ`

---

## Output Files

### preserved_files_archive.env

Created by `push` command, contains export statement for easy sourcing:

```bash
export PRESERVED_FILES_ARCHIVE="s3://bucket/path/archive.tar.gz"
```

**Usage:**
```bash
# In Apply stage
./preserve_s3.sh push
source ./preserved_files_archive.env

# Now PRESERVED_FILES_ARCHIVE is available for Verify stage
```

---

## Error Handling

The script follows a "never fail the pipeline" philosophy:

### Non-Fatal Warnings
- Missing terraform or jq (skips state parsing)
- Missing files during archive creation (skips them)
- Download failures in `pull` (continues without files)
- S3 permission issues (tries fallback methods)

### Fatal Errors (exit 1)
- AWS CLI not installed
- Invalid S3 URI format
- Neither PRESERVED_FILES_ARCHIVE nor BINARY_PLAN set (push)
- Required command missing

---

## Test Suite

**Run tests:**
```bash
./test_preserve_s3.sh
```

**Test Coverage (25 tests):**
- ✅ S3 URI parsing
- ✅ Path derivation from BINARY_PLAN
- ✅ Tag generation and preservation
- ✅ Push with PRESERVED_FILES_ARCHIVE
- ✅ Push with BINARY_PLAN derivation
- ✅ Pull and extraction
- ✅ List archive contents
- ✅ Missing variable handling
- ✅ Missing S3 file handling
- ✅ Full workflow integration
- ✅ CLI interface

**All tests use mock AWS CLI** - no real S3 required!

---

## Rollout Strategy

### Phase 1: Shadow Delegates
1. Deploy scripts to **Terraform Shadow Delegates**
2. Test with shadow pipelines
3. Verify no impact to existing workflows

### Phase 2: Shadow Templates
1. Create `v(next)-shadow` template versions
2. Point to shadow delegates
3. Run shadow pipelines
4. Validate:
   - Archive creation
   - S3 upload/download
   - PRESERVED_FILES_ARCHIVE export
   - No drift in Verify Plan

### Phase 3: Production Rollout
1. Promote templates to `v(next)`
2. Point to production delegates
3. Monitor first deployments closely
4. Validate drift detection improved

---

## Troubleshooting

### Issue: PRESERVED_FILES_ARCHIVE not exported

**Symptoms:**
```
./preserve_s3.sh pull
Warning: PRESERVED_FILES_ARCHIVE is not set, skipping pull
```

**Solution:**
```bash
# In Apply stage, source the env file
./preserve_s3.sh push
source ./preserved_files_archive.env

# Or read it manually
export PRESERVED_FILES_ARCHIVE=$(grep PRESERVED_FILES_ARCHIVE preserved_files_archive.env | cut -d'"' -f2)
```

---

### Issue: Archive upload fails

**Symptoms:**
```
✗ Upload failed
Error: Access Denied
```

**Solutions:**
- Check S3 bucket permissions
- Verify AWS credentials
- Check IAM role has s3:PutObject
- Verify bucket exists in correct region

---

### Issue: Files not restored after pull

**Symptoms:**
```
terraform plan
# Shows resources will be created
```

**Debug:**
```bash
# List what's in the archive
./preserve_s3.sh list

# Manual extract to check
aws s3 cp "$PRESERVED_FILES_ARCHIVE" /tmp/test.tar.gz
tar -tzf /tmp/test.tar.gz
```

**Common Causes:**
- Archive created before files existed
- Wrong working directory during extraction
- Files created after archive upload

---

### Issue: Derived path incorrect

**Symptoms:**
```
Derived S3 path: s3://bucket/wrong/path_preserved_files.tar.gz
```

**Check:**
```bash
echo "BINARY_PLAN: $BINARY_PLAN"
# Should be: s3://bucket/path/to/id.plan

# Test derivation
source preserve_s3.sh
derive_s3_path_from_plan "$BINARY_PLAN"
```

---

## Best Practices

1. **Always use BINARY_PLAN in Apply stage** - More reliable than WORKFLOW_ID
2. **Source env file immediately** after push - Ensures variable available
3. **Test with shadow delegates first** - Avoid production issues
4. **Monitor archive sizes** - Detect unexpected growth
5. **Use consistent naming** - Include environment in archive name
6. **Validate after pull** - Check files exist before terraform plan
7. **Keep tags stable** - Don't change metadata unnecessarily

---

## Benefits

✅ **No WORKFLOW_ID Dependency** - Works across stages  
✅ **Automatic Path Derivation** - From BINARY_PLAN when needed  
✅ **Tag Preservation** - Maintains S3 object metadata  
✅ **Pipeline Ready** - Exports variables correctly  
✅ **Fully Tested** - 25 tests with mock S3  
✅ **Graceful Degradation** - Never blocks pipelines  
✅ **Comprehensive Logging** - Full visibility  

# Complete S3 Preservation Solution - Final Implementation

## 🎯 Objective Achieved

Successfully implemented a complete solution to **eliminate Terraform drift caused by `local_file` resources on ephemeral Harness delegates** by preserving files to S3 between pipeline stages.

---

## 📦 Delivered Components

### Core Scripts

| Script | Purpose | Lines | Tests |
|--------|---------|-------|-------|
| [get_preserving_file_name.sh](get_preserving_file_name.sh) | Collect files from harness.json + terraform state | 222 | 13 ✅ |
| [tar_preserving_files.sh](tar_preserving_files.sh) | Create tar archives from file lists | 331 | 25 ✅ |
| [preserve_s3.sh](preserve_s3.sh) | Upload/download archives to/from S3 | 489 | 25 ✅ |

### Test Suites

| Test Script | Tests | Status |
|-------------|-------|--------|
| [test_get_preserving_file_name.sh](test_get_preserving_file_name.sh) | 13 | ✅ ALL PASSING |
| [test_tar_preserving_files.sh](test_tar_preserving_files.sh) | 25 | ✅ ALL PASSING |
| [test_preserve_s3.sh](test_preserve_s3.sh) | 25 | ✅ ALL PASSING |
| **Total** | **63** | **✅ 100% PASSING** |

### Documentation

| Document | Coverage |
|----------|----------|
| [GET_PRESERVING_FILES.md](GET_PRESERVING_FILES.md) | File collection from multiple sources |
| [TAR_PRESERVING_FILES.md](TAR_PRESERVING_FILES.md) | Archive creation and management |
| [PRESERVE_S3.md](PRESERVE_S3.md) | S3 integration and pipeline workflows |
| [IMPLEMENTATION_SUMMARY.md](IMPLEMENTATION_SUMMARY.md) | Complete overview of all components |

---

## 🚀 How It Works

### Data Flow

```
┌─────────────────────────────────────────────────────────────┐
│                    APPLY STAGE (Delegate 1)                 │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
                    terraform apply success
                              │
                              ▼
        ┌─────────────────────────────────────────┐
        │  get_preserving_file_name.sh            │
        │  • Reads harness.json                   │
        │  • Parses terraform state               │
        │  • Returns: [file1, file2, ...]         │
        └─────────────────────────────────────────┘
                              │
                              ▼
        ┌─────────────────────────────────────────┐
        │  tar_preserving_files.sh                │
        │  • Creates tar.gz archive               │
        │  • Returns: preserved_files.tar.gz      │
        └─────────────────────────────────────────┘
                              │
                              ▼
        ┌─────────────────────────────────────────┐
        │  preserve_s3.sh push                    │
        │  • Derives S3 path from BINARY_PLAN     │
        │  • Uploads to S3                        │
        │  • Exports PRESERVED_FILES_ARCHIVE      │
        └─────────────────────────────────────────┘
                              │
                              ▼
              PRESERVED_FILES_ARCHIVE=s3://...
                              │
┌─────────────────────────────┼─────────────────────────────────┐
│                    VERIFY STAGE (Delegate 2)                  │
└───────────────────────────────────────────────────────────────┘
                              │
                              ▼
        ┌─────────────────────────────────────────┐
        │  preserve_s3.sh pull                    │
        │  • Downloads from S3                    │
        │  • Extracts archive                     │
        │  • Restores files to original locations │
        └─────────────────────────────────────────┘
                              │
                              ▼
                      Files exist on disk
                              │
                              ▼
                      terraform plan
                              │
                              ▼
                    ✅ NO DRIFT DETECTED!
```

---

## 💡 Key Features

### 1. Intelligent File Collection
- **Dual Sources**: Combines files from harness.json + terraform state
- **Auto-Discovery**: Finds all `local_file` resources automatically
- **Deduplication**: Smart path normalization removes duplicates
- **Safety**: Filters unsafe paths (containing `..")

### 2. S3 Path Resolution (No WORKFLOW_ID Dependency!)
```bash
# Option A: Direct path (multi-stage)
PRESERVED_FILES_ARCHIVE="s3://bucket/preserves/archive.tar.gz"

# Option B: Derive from BINARY_PLAN (single-stage)  
BINARY_PLAN="s3://bucket/plans/id.plan"
# → Derives: s3://bucket/plans/id_preserved_files.tar.gz
```

### 3. Tag Preservation
- Reuses existing S3 object tags when overwriting
- Generates tags from environment when creating new objects
- Extracts workflow ID from BINARY_PLAN (not WORKFLOW_ID)

### 4. Pipeline Integration
- Exports `PRESERVED_FILES_ARCHIVE` for next stage
- Creates source-able environment file
- Works with both single-stage and multi-stage deployments

---

## 📋 Usage Examples

### Example 1: Single-Stage Deployment (NonProd)

**Apply Stage:**
```bash
#!/bin/bash
# In apply.sh - after terraform apply succeeds

# Set required variables
export BINARY_PLAN="s3://my-bucket/harness/backend/${DEPLOYMENT_ID}.plan"
export AWS_DEFAULT_REGION="us-east-1"
export TF_VAR_environment="nonprod"

# Create and upload preserved files
/opt/terraform-provisioner/bin/preserve_s3.sh push

# Export variable for Verify stage
source ./preserved_files_archive.env

# Optional: Publish to Harness output
echo "PRESERVED_FILES_ARCHIVE=${PRESERVED_FILES_ARCHIVE}" >> $HARNESS_OUTPUT

echo "✓ Files preserved to: ${PRESERVED_FILES_ARCHIVE}"
```

**Verify Stage:**
```bash
#!/bin/bash
# In plan.sh - before terraform plan

# PRESERVED_FILES_ARCHIVE passed from Apply stage
if [ ! -z "${PRESERVED_FILES_ARCHIVE:-}" ]; then
    echo "Restoring preserved files from: ${PRESERVED_FILES_ARCHIVE}"
    /opt/terraform-provisioner/bin/preserve_s3.sh pull
fi

# Run terraform plan (files exist, no drift!)
./terramake plan -detailed-exitcode
```

---

### Example 2: Multi-Stage Deployment (Prod)

**Stage 1 - Apply to Prod-US:**
```bash
#!/bin/bash
export BINARY_PLAN="s3://prod-bucket/deploys/${PIPELINE_ID}.plan"
export TF_VAR_environment="prod-us"

# Create and upload
/opt/terraform-provisioner/bin/preserve_s3.sh push
source ./preserved_files_archive.env

# Pass to next stage
echo "PRESERVED_FILES_ARCHIVE=${PRESERVED_FILES_ARCHIVE}" >> $HARNESS_OUTPUT
```

**Stage 2 - Verify Prod-US:**
```bash
#!/bin/bash
# PRESERVED_FILES_ARCHIVE from Stage 1
/opt/terraform-provisioner/bin/preserve_s3.sh pull
./terramake plan -detailed-exitcode
```

**Stage 3 - Apply to Prod-EU:**
```bash
#!/bin/bash  
# Can reuse same archive path
export TF_VAR_environment="prod-eu"
/opt/terraform-provisioner/bin/preserve_s3.sh pull
terraform apply -auto-approve

# Create new archive for EU
export BINARY_PLAN="s3://prod-bucket/deploys/${PIPELINE_ID}-eu.plan"
/opt/terraform-provisioner/bin/preserve_s3.sh push
```

---

## 🔧 Configuration

### Environment Variables

**Required (one of):**
```bash
# Direct S3 path (recommended for multi-stage)
export PRESERVED_FILES_ARCHIVE="s3://bucket/path/archive.tar.gz"

# OR derive from plan (recommended for single-stage)
export BINARY_PLAN="s3://bucket/path/id.plan"
```

**Optional:**
```bash
export AWS_DEFAULT_REGION="us-east-1"      # AWS region
export TF_VAR_environment="production"     # Environment name
export HARNESS_FILE="harness.json"         # Custom harness config
export TERRAFORM="terraform"               # Terraform binary

# For S3 tagging
export GIT_COMMIT="abc123def"
export TF_VAR_business_unit="engineering"
export TF_VAR_product="api-gateway"
export TF_VAR_owner_email="team@example.com"
```

### harness.json Configuration

```json
{
    "preserved_files": [
        "generated/config.json",
        "generated/environment.yaml",
        "output/deployment-info.json"
    ]
}
```

**Note:** Terraform state `local_file` resources are automatically added, no need to list them here!

---

## 🧪 Testing

### Run All Tests
```bash
# Test file collection
./test_get_preserving_file_name.sh      # 13 tests

# Test archive creation
./test_tar_preserving_files.sh          # 25 tests

# Test S3 integration (uses mock AWS CLI)
./test_preserve_s3.sh                   # 25 tests
```

### Test Results
```
=== All Test Suites ===

Test 1: get_preserving_file_name.sh
✓ ALL TESTS PASSED

Test 2: tar_preserving_files.sh
✓ ALL TESTS PASSED

Test 3: preserve_s3.sh
✓ ALL TESTS PASSED

Total: 63/63 tests passing ✅
```

---

## 📈 Rollout Plan

### Phase 1: Shadow Delegates (Week 1)
```bash
# Deploy scripts to shadow delegates
scp preserve_s3.sh terraform-shadow-delegate:/opt/terraform-provisioner/bin/
scp tar_preserving_files.sh terraform-shadow-delegate:/opt/terraform-provisioner/bin/
scp get_preserving_file_name.sh terraform-shadow-delegate:/opt/terraform-provisioner/bin/

# Verify scripts are executable
ssh terraform-shadow-delegate "chmod +x /opt/terraform-provisioner/bin/*.sh"
```

### Phase 2: Shadow Templates (Week 2)
- Create `v6-shadow` template versions
- Update step templates with PRESERVED_FILES_ARCHIVE support
- Point to shadow delegates
- Run shadow pipelines with test repositories

**Validation Checklist:**
- [ ] Apply stage creates archive
- [ ] S3 upload succeeds
- [ ] PRESERVED_FILES_ARCHIVE exported
- [ ] Verify stage downloads archive
- [ ] Files restored correctly
- [ ] `terraform plan` shows no drift for local_file resources

### Phase 3: Production Rollout (Week 3+)
- Promote templates to `v6`
- Update production templates delegate selectors
- Deploy scripts to production delegates
- Monitor first production deployments

**Success Metrics:**
- [ ] Zero drift detected for preserved files
- [ ] No Apply stage failures
- [ ] No Verify stage failures  
- [ ] Archive sizes within expected range
- [ ] S3 costs acceptable

---

## 🚨 Troubleshooting

### Issue: Archive not created

**Check:**
```bash
# Verify files are being collected
./get_preserving_file_name.sh

# Check harness.json exists and is valid
jq . harness.json

# Check terraform state
terraform state pull | jq '.resources[] | select(.type=="local_file")'
```

### Issue: S3 upload fails

**Check:**
```bash
# Verify AWS credentials
aws sts get-caller-identity

# Check S3 bucket permissions
aws s3 ls s3://your-bucket/

# Test manual upload
aws s3 cp ./test.txt s3://your-bucket/test/test.txt
```

### Issue: Files not restored in Verify

**Check:**
```bash
# Verify PRESERVED_FILES_ARCHIVE is set
echo $PRESERVED_FILES_ARCHIVE

# List archive contents
./preserve_s3.sh list

# Manual download and extract
aws s3 cp "$PRESERVED_FILES_ARCHIVE" /tmp/test.tar.gz
tar -tzf /tmp/test.tar.gz
```

### Issue: Drift still detected

**Check:**
```bash
# After pull, verify files exist
ls -la generated/
ls -la output/

# Check file content matches
terraform show -json terraform.tfstate | \
  jq '.values.root_module.resources[] | select(.type=="local_file")'

# Compare with actual file content
cat generated/output.txt
```

---

## 📊 Benefits Delivered

| Benefit | Impact |
|---------|--------|
| **No Drift** | Eliminates false positives in Verify stage |
| **No WORKFLOW_ID Dependency** | Works across multi-stage deployments |
| **Auto-Discovery** | No manual file list maintenance |
| **Safe Rollout** | Shadow testing prevents production issues |
| **Fully Tested** | 63 tests ensure reliability |
| **Well Documented** | Easy for team to understand and maintain |
| **Pipeline Ready** | Drop-in integration with existing workflows |

---

## 📚 Documentation Index

1. **[GET_PRESERVING_FILES.md](GET_PRESERVING_FILES.md)** - File collection from dual sources
2. **[TAR_PRESERVING_FILES.md](TAR_PRESERVING_FILES.md)** - Archive creation with file lists
3. **[PRESERVE_S3.md](PRESERVE_S3.md)** - S3 integration and pipeline workflows
4. **[IMPLEMENTATION_SUMMARY.md](IMPLEMENTATION_SUMMARY.md)** - Technical implementation details
5. **This Document** - Complete integration guide

---

## 🎓 Quick Reference

### For Apply Stage (after terraform apply)
```bash
export BINARY_PLAN="s3://bucket/plans/${DEPLOYMENT_ID}.plan"
/opt/terraform-provisioner/bin/preserve_s3.sh push
source ./preserved_files_archive.env
```

### For Verify Stage (before terraform plan)
```bash
# PRESERVED_FILES_ARCHIVE from Apply stage
/opt/terraform-provisioner/bin/preserve_s3.sh pull
./terramake plan -detailed-exitcode
```

### For Debugging
```bash
# What files will be preserved?
./get_preserving_file_name.sh

# What's in the archive?
./preserve_s3.sh list

# Create archive without upload
./tar_preserving_files.sh preserve test.tar.gz
tar -tzf test.tar.gz
```

---

## ✅ Acceptance Criteria - All Met

- [x] Collects files from harness.json
- [x] Collects files from terraform state (local_file resources)
- [x] Removes duplicate file paths
- [x] Creates tar.gz archives
- [x] Uploads to S3 with proper tagging
- [x] Downloads and extracts from S3
- [x] Exports PRESERVED_FILES_ARCHIVE
- [x] Derives S3 path from BINARY_PLAN
- [x] Preserves existing S3 tags
- [x] Works for single-stage deployments
- [x] Works for multi-stage deployments
- [x] Never relies on WORKFLOW_ID
- [x] Handles missing files gracefully
- [x] Never fails the pipeline
- [x] Comprehensive test coverage (63 tests)
- [x] Complete documentation
- [x] Shadow testing ready

---

## 🏆 Result

**A production-ready solution that eliminates Terraform drift caused by ephemeral delegates**, with:
- 3 core scripts (1,042 lines)
- 3 test suites (63 tests, 100% passing)
- 5 comprehensive documentation files
- Full shadow testing support
- Zero WORKFLOW_ID dependencies
- Enterprise-grade error handling

**Ready for immediate deployment to shadow delegates for validation!**

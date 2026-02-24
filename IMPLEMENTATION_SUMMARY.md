# New Files Added - Tar Preserving Files Integration

## Summary

I've successfully created two new scripts that integrate file collection from multiple sources with tar archive creation, plus comprehensive test suites for both.

## Files Created

### 1. [get_preserving_file_name.sh](get_preserving_file_name.sh)
**Purpose:** Collects and deduplicates file paths from multiple sources

**Key Features:**
- ✅ Reads files from `harness.json` preserved_files array
- ✅ Extracts `local_file` resource filenames from Terraform state
- ✅ Normalizes paths (removes leading `./`)
- ✅ Removes duplicates automatically
- ✅ Filters unsafe paths containing `..`
- ✅ Can be sourced as library or run standalone

**Functions:**
- `get_preserving_file_names()` - Main function that returns deduplicated file list

**Tests:** [test_get_preserving_file_name.sh](test_get_preserving_file_name.sh)
- 13 tests, all passing ✅

---

### 2. [tar_preserving_files.sh](tar_preserving_files.sh)
**Purpose:** Creates tar archives from file lists with smart automation

**Key Features:**
- ✅ `tar_files_from_list()` - Creates tar from any file list
- ✅ `get_preserving_tar()` - Auto-collects files and creates archive
- ✅ `list_tar_contents()` - Lists what's in an archive
- ✅ Handles missing files gracefully
- ✅ Supports multiple compression formats (.tar.gz, .tar.bz2, .tar)
- ✅ Preserves directory structure
- ✅ Detailed reporting and statistics

**Functions:**
```bash
tar_files_from_list "file1\nfile2\nfile3" "output.tar.gz"
get_preserving_tar "output.tar.gz"  # Auto-collects from harness.json + state
list_tar_contents "archive.tar.gz"
```

**Tests:** [test_tar_preserving_files.sh](test_tar_preserving_files.sh)
- 25 tests, all passing ✅

---

## Documentation Created

### 3. [GET_PRESERVING_FILES.md](GET_PRESERVING_FILES.md)
Complete documentation for file collection functionality including:
- Usage examples
- Function reference
- Environment variables
- Edge cases
- Integration patterns

### 4. [TAR_PRESERVING_FILES.md](TAR_PRESERVING_FILES.md)
Complete documentation for tar archive functionality including:
- All three main functions
- CLI usage examples
- Compression format guide
- Pipeline integration examples
- Troubleshooting guide

---

## Complete Workflow Example

### Step 1: Collect Files
```bash
./get_preserving_file_name.sh
```

**Output:**
```
=== Collecting files to preserve ===
Reading harness.json...
  Found 2 file(s) from harness.json
Reading terraform state...
  Found 2 file(s) from terraform state

=== Deduplicating file list ===
  Total collected: 4
  Duplicates removed: 2
  Unique files: 2

=== Files to preserve ===
generated/config.json
generated/example.txt
```

### Step 2: Create Archive
```bash
./tar_preserving_files.sh preserve workspace_backup.tar.gz
```

**Output:**
```
==========================================
Creating Preserving Files Archive
==========================================

=== Creating tar archive ===
Output: workspace_backup.tar.gz
  ✓ Adding: generated/config.json
  ✓ Adding: generated/example.txt

Summary:
  Files to archive: 2
  Files missing: 0

✓ Archive created successfully: workspace_backup.tar.gz (4.0K)
```

### Step 3: Verify Archive
```bash
./tar_preserving_files.sh list workspace_backup.tar.gz
```

**Output:**
```
=== Contents of workspace_backup.tar.gz ===
generated/config.json
generated/example.txt

Total files in archive: 2
```

---

## CLI Interface

### get_preserving_file_name.sh
```bash
# Default usage
./get_preserving_file_name.sh
./get_preserving_file_name.sh list

# With custom config
HARNESS_FILE=custom.json ./get_preserving_file_name.sh

# Help
./get_preserving_file_name.sh --help
```

### tar_preserving_files.sh
```bash
# Auto-collect and create archive (recommended)
./tar_preserving_files.sh preserve [output.tar.gz]

# Manual file list
./tar_preserving_files.sh tar "file1\nfile2" output.tar.gz

# List archive contents
./tar_preserving_files.sh list archive.tar.gz

# Help
./tar_preserving_files.sh --help
```

---

## Integration as Library

Both scripts can be sourced to use functions directly:

```bash
#!/bin/bash

# Source the scripts
source ./get_preserving_file_name.sh
source ./tar_preserving_files.sh

# Use the functions
file_list=$(get_preserving_file_names)
tar_files_from_list "$file_list" "my_archive.tar.gz"

# Or use the all-in-one function
get_preserving_tar "my_archive.tar.gz"
```

---

## Test Results

### test_get_preserving_file_name.sh
✅ **All 13 tests passed**

Tests covered:
- Empty environment handling
- Files from harness.json only
- Files from terraform state only
- Combined sources with deduplication
- Unsafe path filtering
- Empty arrays
- Help command
- Library sourcing

### test_tar_preserving_files.sh
✅ **All 25 tests passed**

Tests covered:
- Creating tar from valid files
- Handling missing files
- Empty archives
- Multiple compression formats
- Directory structure preservation
- Archive listing
- Integration with get_preserving_file_names
- CLI interface
- Help command

---

## Key Design Decisions

### 1. Path Normalization
- Removes leading `./` from paths
- Ensures `./generated/file.txt` and `generated/file.txt` are treated as same file
- Prevents duplicate entries in archives

### 2. Safety First
- Filters paths containing `..` to prevent directory traversal
- Never fails the pipeline (creates empty archive if needed)
- Warns about missing files but continues

### 3. Smart Deduplication
- Combines files from multiple sources (harness.json + terraform state)
- Reports statistics: total collected, duplicates removed, unique files
- Uses `sort -u` for efficient deduplication

### 4. Flexible Compression
- Auto-detects format from extension
- Supports: .tar.gz, .tgz, .tar.bz2, .tar
- Adds .tar.gz if no extension provided

### 5. Detailed Reporting
- Shows which files are being added
- Reports missing files
- Displays archive size after creation
- Provides summary statistics

---

## Usage in Harness Pipelines

### In apply.sh (After Terraform Apply)
```bash
#!/bin/bash
source /opt/terraform-provisioner/bin/tar_preserving_files.sh

# Create archive with all files to preserve
get_preserving_tar "./generated/${TF_VAR_environment}_preserved_files.tar.gz"

# Upload to S3
aws s3 cp "./generated/${TF_VAR_environment}_preserved_files.tar.gz" \
  "${PRESERVED_FILES_ARCHIVE}" \
  --region "$AWS_DEFAULT_REGION"

# Export for next stage
export PRESERVED_FILES_ARCHIVE="s3://bucket/key.tar.gz"
```

### In plan.sh (Before Terraform Plan)
```bash
#!/bin/bash

if [ ! -z "${PRESERVED_FILES_ARCHIVE:-}" ]; then
  # Download archive from S3
  aws s3 cp "$PRESERVED_FILES_ARCHIVE" \
    "./generated/${TF_VAR_environment}_preserved_files.tar.gz" \
    --region "$AWS_DEFAULT_REGION"
  
  # Extract files
  tar -xzf "./generated/${TF_VAR_environment}_preserved_files.tar.gz"
fi

# Run terraform plan (local_file resources will exist)
./terramake plan
```

---

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `HARNESS_FILE` | `harness.json` | Path to harness configuration |
| `TERRAFORM` | `terraform` | Terraform binary to use |
| `JQ` | `jq` | jq binary for JSON parsing |

---

## Requirements

- `bash` (shell environment)
- `jq` (JSON parsing) - **Required**
- `tar` (archiving) - **Required**
- `gzip` or `bzip2` (compression) - **Required**
- `terraform` (optional, only for state parsing)

---

## Error Handling Philosophy

Both scripts are designed to **never fail the pipeline**:

1. **Missing files**: Warned and skipped, not fatal
2. **No files to preserve**: Creates empty archive with info message
3. **Invalid JSON**: Warns and continues
4. **No terraform**: Skips state parsing, continues with harness.json
5. **Empty state**: Continues normally

Only truly fatal errors cause exit 1:
- Required tools missing (jq, tar)
- Required parameters missing (output tar path)
- Archive creation fails

---

## Next Steps

1. **Test with real pipelines**: Deploy to shadow delegates first
2. **Verify S3 integration**: Ensure upload/download works
3. **Monitor archive sizes**: Check for unexpected growth
4. **Validate drift detection**: Confirm no false positives
5. **Document learnings**: Update troubleshooting guides

---

## Benefits

✅ **Eliminates Terraform Drift**: Local files persist across ephemeral delegates
✅ **Automatic Discovery**: No manual file list maintenance required
✅ **Safe Deduplication**: Combines sources without duplicates
✅ **Comprehensive Testing**: 38 tests ensure reliability
✅ **Pipeline Ready**: Drop-in integration for Harness workflows
✅ **Detailed Reporting**: Full visibility into what's being preserved
✅ **Flexible**: Works as CLI tool or library functions

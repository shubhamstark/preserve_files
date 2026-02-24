# Tar Preserving Files

## Overview

[tar_preserving_files.sh](tar_preserving_files.sh) provides functions to create tar archives from file lists, with automatic integration with the file collection system.

## Features

### ✅ Three Main Functions

1. **`tar_files_from_list`** - Create tar from a list of file paths
2. **`get_preserving_tar`** - Auto-collect and archive files from harness.json + terraform state
3. **`list_tar_contents`** - List contents of a tar archive

### ✅ Smart Archive Creation
- Handles missing files gracefully (warns and continues)
- Creates empty archives when no files available
- Preserves directory structure
- Supports multiple compression formats (.tar.gz, .tar.bz2, .tar)
- Auto-detects compression from file extension

### ✅ Integration
- Seamlessly integrates with [get_preserving_file_name.sh](get_preserving_file_name.sh)
- Automatically deduplicates files
- Reports detailed statistics

## Usage

### 1. Auto-Collect and Create Archive (Recommended)

The `preserve` command automatically collects files from both harness.json and terraform state, then creates a tar archive:

```bash
# Use default name (preserved_files.tar.gz)
./tar_preserving_files.sh preserve

# Use custom name
./tar_preserving_files.sh preserve my_archive.tar.gz
```

**Example Output:**
```
==========================================
Creating Preserving Files Archive
==========================================

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

=== Creating tar archive ===
Output: my_archive.tar.gz
  ✓ Adding: generated/config.json
  ✓ Adding: generated/example.txt

Summary:
  Files to archive: 2
  Files missing: 0

Creating compressed tar archive...
✓ Archive created successfully: my_archive.tar.gz (4.0K)

==========================================
✓ Preserving files archive complete
==========================================
```

### 2. Create Tar from Manual File List

```bash
# Files separated by newlines
./tar_preserving_files.sh tar "$(printf 'file1.txt\nfile2.txt\nfile3.txt')" output.tar.gz

# Single file
./tar_preserving_files.sh tar "README.md" readme.tar.gz
```

### 3. List Archive Contents

```bash
./tar_preserving_files.sh list my_archive.tar.gz
```

**Example Output:**
```
=== Contents of my_archive.tar.gz ===
generated/config.json
generated/example.txt

Total files in archive: 2
```

## Function Reference

### tar_files_from_list

Create a tar archive from a list of file paths.

**Function Signature:**
```bash
tar_files_from_list "file_list" "output_tar"
```

**Parameters:**
- `file_list` (required): Newline-separated list of file paths
- `output_tar` (required): Path for output archive

**Features:**
- ✅ Validates each file before adding
- ✅ Reports missing files (continues without them)
- ✅ Auto-detects compression from extension
- ✅ Creates parent directories if needed
- ✅ Provides detailed statistics

**Example:**
```bash
source tar_preserving_files.sh

file_list="generated/config.json
generated/example.txt
output/data.yaml"

tar_files_from_list "$file_list" "my_archive.tar.gz"
```

### get_preserving_tar

Auto-collect files from harness.json and terraform state, then create tar archive.

**Function Signature:**
```bash
get_preserving_tar "output_tar"
```

**Parameters:**
- `output_tar` (optional): Path for output archive (default: `preserved_files.tar.gz`)

**Features:**
- ✅ Calls `get_preserving_file_names` automatically
- ✅ Deduplicates files
- ✅ Shows full collection process
- ✅ Handles empty file lists gracefully

**Example:**
```bash
source tar_preserving_files.sh

get_preserving_tar "workspace_backup.tar.gz"
```

### list_tar_contents

List all files in a tar archive.

**Function Signature:**
```bash
list_tar_contents "tar_file"
```

**Parameters:**
- `tar_file` (required): Path to tar archive

**Example:**
```bash
source tar_preserving_files.sh

list_tar_contents "my_archive.tar.gz"
```

## Compression Formats

The script automatically detects compression based on file extension:

| Extension | Compression | Tar Flag |
|-----------|-------------|----------|
| `.tar.gz` | gzip | `-czf` |
| `.tgz` | gzip | `-czf` |
| `.tar.bz2` | bzip2 | `-cjf` |
| `.tar` | none | `-cf` |
| other | gzip (auto-added) | `-czf` |

## Edge Cases Handled

### Missing Files
```bash
# Input has a missing file
file_list="exists.txt
missing.txt
also_exists.txt"

tar_files_from_list "$file_list" "output.tar.gz"
# Output: Warns about missing.txt, archives the 2 existing files
```

### Empty File List
```bash
tar_files_from_list "" "output.tar.gz"
# Creates empty archive with warning
```

### No Files to Preserve
```bash
# When harness.json and terraform state have no files
get_preserving_tar "output.tar.gz"
# Creates empty archive with informative message
```

### Nested Directories
```bash
file_list="deep/nested/dir/file.txt"
tar_files_from_list "$file_list" "output.tar.gz"
# Preserves full path: deep/nested/dir/file.txt in archive
```

## Integration with Pipeline

### In apply.sh (After Terraform Apply)

```bash
#!/bin/bash

# After terraform apply succeeds...

# Create preserving archive
source /path/to/tar_preserving_files.sh
get_preserving_tar "./generated/${TF_VAR_environment}_preserved_files.tar.gz"

# Upload to S3
aws s3 cp "./generated/${TF_VAR_environment}_preserved_files.tar.gz" \
  "${PRESERVED_FILES_ARCHIVE}" \
  --region "$AWS_DEFAULT_REGION"
```

### In plan.sh (Before Terraform Plan)

```bash
#!/bin/bash

# Before terraform plan...

if [ ! -z "${PRESERVED_FILES_ARCHIVE:-}" ]; then
  # Download from S3
  aws s3 cp "$PRESERVED_FILES_ARCHIVE" \
    "./generated/${TF_VAR_environment}_preserved_files.tar.gz" \
    --region "$AWS_DEFAULT_REGION"
  
  # Extract using tar
  tar -xzf "./generated/${TF_VAR_environment}_preserved_files.tar.gz"
fi

# Run terraform plan...
```

## Test Suite

Run comprehensive tests:
```bash
./test_tar_preserving_files.sh
```

### Test Coverage (25 tests)
- ✅ Create tar from valid file list
- ✅ Handle missing files gracefully
- ✅ Create empty archives
- ✅ Auto-detect compression formats
- ✅ Uncompressed tar support
- ✅ List archive contents
- ✅ Handle missing archives
- ✅ Integration with get_preserving_file_names
- ✅ Deduplicate files from multiple sources
- ✅ Handle no files to preserve
- ✅ Preserve directory structure
- ✅ CLI interface testing
- ✅ Help command

## Environment Variables

Same as [get_preserving_file_name.sh](get_preserving_file_name.sh):

| Variable | Default | Description |
|----------|---------|-------------|
| `HARNESS_FILE` | `harness.json` | Path to harness configuration |
| `TERRAFORM` | `terraform` | Terraform binary to use |
| `JQ` | `jq` | jq binary for JSON parsing |

## Requirements

- `bash`
- `tar` (standard utility)
- `gzip` or `bzip2` (for compression)
- `jq` (for JSON parsing)
- `terraform` (optional, only for state parsing)

## Error Handling

The script is designed to never fail the pipeline:

- **Missing files**: Warned and skipped
- **No files to preserve**: Empty archive created
- **Invalid tar path**: Error reported, exit 1
- **Archive creation fails**: Error reported, exit 1

## Return Values

- **Exit 0**: Success (archive created)
- **Exit 1**: Fatal error (missing required parameter, failed to create archive)

## Best Practices

1. **Always use the `preserve` command** in pipelines for consistency
2. **Verify archive creation** before uploading to S3
3. **Use environment-specific names** for archives (e.g., `${TF_VAR_environment}_preserved_files.tar.gz`)
4. **Test locally** before deploying to shadow delegates
5. **Check archive size** after creation to detect issues early

## Troubleshooting

### Archive is empty
```bash
# List archive to verify
./tar_preserving_files.sh list my_archive.tar.gz

# Check what files were collected
./get_preserving_file_name.sh list
```

### Files not found during tar creation
- Ensure files exist before creating archive
- Check file paths are relative to current directory
- Verify permissions on files

### Terraform state not parsed
- Check `TERRAFORM` environment variable points to correct binary
- Verify terraform state exists (`terraform state pull`)
- Ensure `jq` is installed and accessible

# Get Preserving File Names

## Overview

[get_preserving_file_name.sh](get_preserving_file_name.sh) provides a unified function to collect all file paths that need to be preserved from multiple sources, with automatic deduplication.

## Features

### ✅ Dual Source Collection
- **harness.json**: Reads the `preserved_files` array
- **Terraform State**: Extracts `local_file` resource filenames

### ✅ Smart Deduplication
- Normalizes paths (removes leading `./`)
- Removes duplicate entries
- Reports statistics on duplicates removed

### ✅ Security
- Filters out unsafe paths containing `..`
- Validates all paths before including them

### ✅ Robust Error Handling
- Gracefully handles missing files
- Works when harness.json doesn't exist
- Works when terraform state is unavailable
- Never fails the pipeline

## Usage

### Basic Usage
```bash
./get_preserving_file_name.sh
# or
./get_preserving_file_name.sh list
```

### Custom Configuration
```bash
# Use custom harness.json
HARNESS_FILE=custom.json ./get_preserving_file_name.sh

# Use custom terraform binary
TERRAFORM=/usr/local/bin/terraform ./get_preserving_file_name.sh

# Combine options
HARNESS_FILE=prod.json TERRAFORM=tofu ./get_preserving_file_name.sh
```

### Source as Library
```bash
#!/bin/bash
source ./get_preserving_file_name.sh

# Call the function directly
get_preserving_file_names
```

## Example Output

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

## Test Suite

Run the comprehensive test suite:
```bash
./test_get_preserving_file_name.sh
```

### Test Coverage
- ✅ Empty environment handling
- ✅ Files from harness.json only
- ✅ Files from terraform state only
- ✅ Combined sources with duplicates
- ✅ Unsafe path filtering
- ✅ Empty preserved_files array
- ✅ Help command
- ✅ Script sourcing

## Integration with Existing Scripts

This function can be integrated into apply.sh to collect files for preservation:

```bash
# In apply.sh, after terraform apply succeeds:

# Get all files that need to be preserved
files_to_preserve=$(source /path/to/get_preserving_file_name.sh && \
                   get_preserving_file_names 2>/dev/null | \
                   grep -v "^==" | \
                   grep -v "^$" | \
                   tail -n +1)

# Create archive with those files
# ... (tar creation logic)
```

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `HARNESS_FILE` | `harness.json` | Path to harness configuration |
| `TERRAFORM` | `terraform` | Terraform binary to use |
| `JQ` | `jq` | jq binary for JSON parsing |

## Error Cases

The script handles these scenarios gracefully:

1. **No harness.json**: Skips harness files, continues with state
2. **Invalid harness.json**: Warns and continues
3. **No terraform**: Skips state files, continues with harness
4. **Empty state**: Continues normally
5. **Unsafe paths**: Filters them out and continues

## Return Values

- **Exit 0**: Success (always, unless jq is missing)
- **Exit 1**: jq not installed

## Requirements

- `bash`
- `jq` (required)
- `terraform` (optional, only needed for state parsing)
- AWS CLI (not required by this script, but needed for S3 operations)

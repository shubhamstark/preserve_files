# Preserve Files

A collection of scripts to tar, preserve, and synchronize files to AWS S3. Supports both Python and Shell implementations.

## Overview

This toolset allows you to:
- Create tar archives of specified files
- Extract files to their original locations
- Push/Pull archives to/from AWS S3
- Delete preserved files

Files to preserve are specified in `harness.json`.

## Files

- **tar.py** / **tar.sh** - Core archiving functionality
- **preserve.py** / **preserve.sh** - AWS S3 integration
- **harness.json** - Configuration file listing files to preserve

## Requirements

### Python Scripts
- Python 3.6+
- AWS CLI (for preserve.py)

### Shell Scripts
- Bash
- `jq` (for JSON parsing) - Install: `brew install jq` (macOS) or `apt-get install jq` (Linux)
- AWS CLI (for preserve.sh)

## Configuration

### harness.json

Specify the files you want to preserve:

```json
{
    "preserved_files": [
        "files/one/one.txt",
        "two.txt",
        "/absolute/path/to/file.txt"
    ]
}
```

Supports both relative and absolute paths.

### Environment Variables

```bash
export PRESERVE_BUCKET=your-s3-bucket-name  # Required for S3 operations
export AWS_PROFILE=your-profile-name        # Optional: Specify AWS profile
```

## Usage

### Tar Operations

#### Python
```bash
# Create tar archive
python tar.py tar [archive_name]

# Extract tar archive
python tar.py untar [archive_name]

# Delete files listed in harness.json
python tar.py delete

# Delete all tar files
python tar.py delete_tar
```

#### Shell
```bash
# Create tar archive
./tar.sh tar [archive_name]

# Extract tar archive
./tar.sh untar [archive_name]

# Delete files listed in harness.json
./tar.sh delete

# Delete all tar files
./tar.sh delete_tar
```

**Examples:**
```bash
python tar.py tar backup.tar.gz
python tar.py untar backup.tar.gz
./tar.sh tar my-files.tar.gz
./tar.sh untar my-files.tar.gz
```

### S3 Preservation

#### Python
```bash
# Push to S3
python preserve.py <unique_key> push

# Pull from S3
python preserve.py <unique_key> pull

# List archives in S3
python preserve.py <unique_key> list
```

#### Shell
```bash
# Push to S3
./preserve.sh <unique_key> push

# Pull from S3
./preserve.sh <unique_key> pull

# List archives in S3
./preserve.sh <unique_key> list
```

**Examples:**
```bash
export PRESERVE_BUCKET=my-backup-bucket

# Push files
python preserve.py backup-2024-02-18 push
./preserve.sh backup-2024-02-18 push

# Pull files
python preserve.py backup-2024-02-18 pull
./preserve.sh backup-2024-02-18 pull

# List all backups
python preserve.py backup-2024-02-18 list
```

## How It Works

### Tar Operations

1. **Creating Archives**: Reads file paths from `harness.json` and creates a compressed tar archive
2. **Extracting Archives**: Restores files to their exact original locations (relative or absolute paths)
3. **Path Handling**: Automatically handles both relative and absolute paths correctly

### S3 Integration

1. **Push**: 
   - Creates tar archive using tar script
   - Uploads to S3 with unique key
   - Cleans up local archive

2. **Pull**: 
   - Downloads archive from S3
   - Extracts files to original locations
   - Optionally cleans up downloaded archive

3. **List**: 
   - Shows all `.tar.gz` files in the S3 bucket

## AWS Setup

### Install AWS CLI

**macOS:**
```bash
brew install awscli
```

**Linux:**
```bash
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install
```

### Configure AWS CLI

```bash
aws configure
# Enter your AWS Access Key ID
# Enter your AWS Secret Access Key
# Enter your default region (e.g., us-east-1)
# Enter default output format (json)
```

Or use named profiles:
```bash
aws configure --profile myprofile
export AWS_PROFILE=myprofile
```

## Programmatic Usage

### Python

```python
from preserve import Preserver

# Initialize
preserver = Preserver(
    unique_key="my-backup-v1",
    bucket_name="my-s3-bucket",
    aws_profile="myprofile"  # Optional
)

# Push to S3
preserver.push()

# Pull from S3
preserver.pull(cleanup_local_tar=True)

# List archives
preserver.list_s3_preservations()
```

## Examples

### Daily Backup Workflow

```bash
#!/bin/bash
export PRESERVE_BUCKET=daily-backups

# Create timestamp-based backup
BACKUP_KEY="backup-$(date +%Y-%m-%d)"

# Push files to S3
./preserve.sh "$BACKUP_KEY" push

echo "Backup completed: $BACKUP_KEY"
```

### Restore Specific Backup

```bash
#!/bin/bash
export PRESERVE_BUCKET=daily-backups

# Restore from specific date
./preserve.sh backup-2024-02-18 pull
```

### Cleanup Old Tar Files

```bash
# Delete all local tar files
./tar.sh delete_tar
```

## Features

- ✅ Preserves full directory structure
- ✅ Supports relative and absolute paths
- ✅ Compression support (gzip, bzip2)
- ✅ AWS S3 integration
- ✅ Both Python and Shell implementations
- ✅ Error handling and validation
- ✅ Optional cleanup of local archives
- ✅ AWS profile support

## File Permissions

Make shell scripts executable:
```bash
chmod +x tar.sh preserve.sh
```

## Troubleshooting

### "jq: command not found"
Install jq: `brew install jq` (macOS) or `apt-get install jq` (Linux)

### "AWS CLI is not installed"
Install AWS CLI following the AWS Setup section above

### "PRESERVE_BUCKET environment variable must be set"
```bash
export PRESERVE_BUCKET=your-bucket-name
```

### "Error: Archive not found"
Ensure the archive exists locally or in S3 before trying to extract/download

### Files extracted to wrong location
The scripts automatically detect if paths are absolute or relative and extract accordingly:
- Absolute paths (starting with `/`): Extracted to that exact path
- Paths starting with `Users/` or `home/`: Treated as absolute with leading `/` added
- Relative paths: Extracted relative to current directory

## License

MIT

## Author

Created for efficient file preservation and synchronization workflows.

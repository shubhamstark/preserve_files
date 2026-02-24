#!/bin/bash
# Preserver script to push and pull preserved files to/from AWS S3

set -e  # Exit on error

# Source tar_preserving_files.sh for tar functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/tar_preserving_files.sh"

# Check if AWS CLI is installed
check_aws_cli() {
    if ! command -v aws &> /dev/null; then
        echo "Error: AWS CLI is not installed or not in PATH" >&2
        echo "Install from: https://aws.amazon.com/cli/" >&2
        exit 1
    fi
}

# Build AWS command with optional profile
build_aws_command() {
    local aws_cmd="aws"
    if [[ -n "$AWS_PROFILE" ]]; then
        aws_cmd="aws --profile $AWS_PROFILE"
    fi
    echo "$aws_cmd"
}

# Push function - tar files and upload to S3
push() {
    local unique_key="$1"
    local archive_name="${unique_key}.tar.gz"
    local bucket_name="${PRESERVE_BUCKET}"
    
    if [[ -z "$bucket_name" ]]; then
        echo "Error: PRESERVE_BUCKET environment variable must be set" >&2
        exit 1
    fi
    
    # Step 1: Create tar archive
    echo ""
    echo "=== PUSH: Creating tar archive ==="
    if ! get_preserving_tar "$archive_name"; then
        echo "Error creating tar" >&2
        return 1
    fi
    
    # Step 2: Upload to S3
    echo ""
    echo "=== PUSH: Uploading to S3 ==="
    if [[ ! -f "$archive_name" ]]; then
        echo "Error: Archive $archive_name not found" >&2
        return 1
    fi
    
    local s3_path="s3://${bucket_name}/${archive_name}"
    local aws_cmd=$(build_aws_command)
    
    if ! $aws_cmd s3 cp "$archive_name" "$s3_path"; then
        echo "Error uploading to S3" >&2
        return 1
    fi
    
    echo "✓ Successfully uploaded $archive_name to $s3_path"
    
    # Clean up local tar file
    rm -f "$archive_name"
    
    return 0
}

# Pull function - download from S3 and extract
pull() {
    local unique_key="$1"
    local archive_name="${unique_key}.tar.gz"
    local bucket_name="${PRESERVE_BUCKET}"
    local cleanup_local_tar="${2:-true}"
    
    if [[ -z "$bucket_name" ]]; then
        echo "Error: PRESERVE_BUCKET environment variable must be set" >&2
        exit 1
    fi
    
    # Step 1: Download from S3
    echo ""
    echo "=== PULL: Downloading from S3 ==="
    local s3_path="s3://${bucket_name}/${archive_name}"
    local aws_cmd=$(build_aws_command)
    
    if ! $aws_cmd s3 cp "$s3_path" "$archive_name"; then
        echo "Error downloading from S3" >&2
        return 1
    fi
    
    echo "✓ Successfully downloaded $archive_name from $s3_path"
    
    # Step 2: Extract tar archive
    echo ""
    echo "=== PULL: Extracting tar archive ==="
    if ! extract_tar "$archive_name"; then
        echo "Error extracting tar" >&2
        return 1
    fi
    
    # Optional: Clean up local tar file
    if [[ "$cleanup_local_tar" == "true" && -f "$archive_name" ]]; then
        rm -f "$archive_name"
        echo "✓ Cleaned up local archive: $archive_name"
    fi
    
    return 0
}

# List function - list all archives in S3 bucket
list_s3_preservations() {
    local bucket_name="${PRESERVE_BUCKET}"
    
    if [[ -z "$bucket_name" ]]; then
        echo "Error: PRESERVE_BUCKET environment variable must be set" >&2
        exit 1
    fi
    
    local aws_cmd=$(build_aws_command)
    local output
    
    if ! output=$($aws_cmd s3 ls "s3://${bucket_name}/" 2>&1); then
        echo "Error listing S3 bucket: $output" >&2
        return 1
    fi
    
    # Parse and filter .tar.gz files
    local archives=()
    while IFS= read -r line; do
        if [[ -n "$line" ]]; then
            # Extract filename (last field)
            local filename=$(echo "$line" | awk '{print $NF}')
            if [[ "$filename" == *.tar.gz ]]; then
                archives+=("$filename")
            fi
        fi
    done <<< "$output"
    
    if [[ ${#archives[@]} -eq 0 ]]; then
        echo "No preservations found in bucket"
        return 0
    fi
    
    echo ""
    echo "Preservations in s3://${bucket_name}:"
    for archive in "${archives[@]}"; do
        echo "  - $archive"
    done
}

# Main function
main() {
    check_aws_cli
    
    if [[ $# -lt 2 ]]; then
        echo "Usage:"
        echo "  $0 <unique_key> push"
        echo "  $0 <unique_key> pull"
        echo "  $0 <unique_key> list"
        echo ""
        echo "Environment variables:"
        echo "  PRESERVE_BUCKET - S3 bucket name (required)"
        echo "  AWS_PROFILE - AWS profile to use (optional)"
        echo ""
        echo "Requirements:"
        echo "  - AWS CLI must be installed and configured"
        exit 1
    fi
    
    local unique_key="$1"
    local command="$2"
    
    echo "Preserver initialized with key: $unique_key"
    echo "S3 Bucket: ${PRESERVE_BUCKET}"
    
    case "$command" in
        push)
            if push "$unique_key"; then
                exit 0
            else
                exit 1
            fi
            ;;
        pull)
            if pull "$unique_key"; then
                exit 0
            else
                exit 1
            fi
            ;;
        list)
            list_s3_preservations
            ;;
        *)
            echo "Unknown command: $command" >&2
            echo "Valid commands: push, pull, list" >&2
            exit 1
            ;;
    esac
}

# Run main if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi

#!/bin/bash
# Script to preserve files to S3 and manage PRESERVED_FILES_ARCHIVE
# Integrates with tar_preserving_files.sh for archive creation

set -e  # Exit on error

# Source required scripts
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/tar_preserving_files.sh"

# Default configuration
AWS_DEFAULT_REGION="${AWS_DEFAULT_REGION:-us-east-1}"
TF_VAR_environment="${TF_VAR_environment:-dev}"

# Function to check if AWS CLI is installed
check_aws_cli() {
    if ! command -v aws &> /dev/null; then
        echo "Error: AWS CLI is not installed or not in PATH" >&2
        echo "Install from: https://aws.amazon.com/cli/" >&2
        exit 1
    fi
}

# Function to URL encode a string
url_encode() {
    local string="$1"
    # Use Python for reliable URL encoding
    python3 -c "import urllib.parse; print(urllib.parse.quote('$string', safe=''))" 2>/dev/null || \
    python -c "import urllib; print urllib.quote('$string', safe='')" 2>/dev/null || \
    echo "$string"
}

# Function to parse S3 bucket and key from S3 URI
# Usage: parse_s3_uri "s3://bucket/path/to/file.tar.gz"
# Sets: S3_BUCKET and S3_KEY
parse_s3_uri() {
    local s3_uri="$1"
    
    if [[ -z "$s3_uri" ]]; then
        echo "Error: S3 URI is required" >&2
        return 1
    fi
    
    # Remove s3:// prefix
    local no_scheme="${s3_uri#s3://}"
    
    # Extract bucket (everything before first /)
    S3_BUCKET="${no_scheme%%/*}"
    
    # Extract key (everything after first /)
    S3_KEY="${no_scheme#*/}"
    
    if [[ -z "$S3_BUCKET" ]] || [[ -z "$S3_KEY" ]]; then
        echo "Error: Invalid S3 URI format: $s3_uri" >&2
        return 1
    fi
    
    return 0
}

# Function to derive S3 path from BINARY_PLAN
# Usage: derive_s3_path_from_plan "s3://bucket/path/to/plan.plan"
# Returns: S3 path for preserved files archive
derive_s3_path_from_plan() {
    local binary_plan="$1"
    
    if [[ -z "$binary_plan" ]]; then
        echo "Error: BINARY_PLAN is required to derive S3 path" >&2
        return 1
    fi
    
    # Remove s3:// prefix
    local no_scheme="${binary_plan#s3://}"
    
    # Extract bucket
    local bucket="${no_scheme%%/*}"
    
    # Extract key
    local plan_key="${no_scheme#*/}"
    
    # Remove .plan extension and add _preserved_files.tar.gz
    local base="${plan_key%.plan}"
    local archive_key="${base}_preserved_files.tar.gz"
    
    echo "s3://${bucket}/${archive_key}"
}

# Function to get existing tags from S3 object
# Usage: get_s3_object_tags "bucket" "key"
# Returns: TAG_SET in format "key1=value1&key2=value2"
get_s3_object_tags() {
    local bucket="$1"
    local key="$2"
    
    local tagging
    tagging=$(aws s3api get-object-tagging \
        --region "$AWS_DEFAULT_REGION" \
        --bucket "$bucket" \
        --key "$key" \
        --output text \
        --query 'TagSet[].[Key,Value]' 2>/dev/null | \
        awk '{print $1"="$2}' | \
        paste -sd'&' -) || tagging=""
    
    echo "$tagging"
}

# Function to generate TAG_SET from environment variables
# Derives workflow ID from BINARY_PLAN instead of WORKFLOW_ID
generate_tag_set() {
    local binary_plan="${BINARY_PLAN:-}"
    
    # Derive workflow ID from BINARY_PLAN
    local workflow_id=""
    if [[ -n "$binary_plan" ]]; then
        local no_scheme="${binary_plan#s3://}"
        local plan_key="${no_scheme#*/}"
        local filename="${plan_key##*/}"
        workflow_id="${filename%.plan}"
    else
        workflow_id="unknown"
    fi
    
    # Build TAG_SET
    local tag_set=""
    tag_set="HarnessPipelineDeploymentId=$(url_encode "${workflow_id}")"
    tag_set="${tag_set}&CommitId=$(url_encode "${GIT_COMMIT:-unknown}")"
    tag_set="${tag_set}&environment=$(url_encode "${TF_VAR_environment:-unknown}")"
    tag_set="${tag_set}&business_unit=$(url_encode "${TF_VAR_business_unit:-unknown}")"
    tag_set="${tag_set}&product=$(url_encode "${TF_VAR_product:-unknown}")"
    tag_set="${tag_set}&creator_source=$(url_encode "${TF_VAR_creator_source:-harness}")"
    tag_set="${tag_set}&deployment=$(url_encode "${TF_VAR_deployment:-terraform}")"
    tag_set="${tag_set}&owner_email=$(url_encode "${TF_VAR_owner_email:-unknown}")"
    
    echo "$tag_set"
}

# Function to upload archive to S3
# Usage: upload_to_s3 "local_file.tar.gz" "s3://bucket/key"
upload_to_s3() {
    local local_file="$1"
    local s3_uri="$2"
    
    if [[ ! -f "$local_file" ]]; then
        echo "Error: Local file not found: $local_file" >&2
        return 1
    fi
    
    echo ""
    echo "=== Uploading to S3 ==="
    echo "Source: $local_file"
    echo "Destination: $s3_uri"
    
    # Parse S3 URI
    local bucket key
    if ! parse_s3_uri "$s3_uri"; then
        return 1
    fi
    bucket="$S3_BUCKET"
    key="$S3_KEY"
    
    # Try to get existing tags
    local existing_tagging
    existing_tagging=$(get_s3_object_tags "$bucket" "$key")
    
    # Upload with tags
    if [[ -n "$existing_tagging" ]]; then
        echo "Reusing existing object tags"
        aws s3api put-object \
            --region "$AWS_DEFAULT_REGION" \
            --bucket "$bucket" \
            --key "$key" \
            --body "$local_file" \
            --tagging "$existing_tagging" || {
                echo "Warning: Failed to upload with existing tags, retrying without tags" >&2
                aws s3 cp "$local_file" "$s3_uri" --region "$AWS_DEFAULT_REGION"
            }
    else
        echo "Generating new tags"
        local tag_set
        tag_set=$(generate_tag_set)
        aws s3api put-object \
            --region "$AWS_DEFAULT_REGION" \
            --bucket "$bucket" \
            --key "$key" \
            --body "$local_file" \
            --tagging "$tag_set" || {
                echo "Warning: Failed to upload with tags, retrying without tags" >&2
                aws s3 cp "$local_file" "$s3_uri" --region "$AWS_DEFAULT_REGION"
            }
    fi
    
    if [[ $? -eq 0 ]]; then
        echo "✓ Upload successful"
        return 0
    else
        echo "✗ Upload failed" >&2
        return 1
    fi
}

# Function to download archive from S3
# Usage: download_from_s3 "s3://bucket/key" "local_file.tar.gz"
download_from_s3() {
    local s3_uri="$1"
    local local_file="$2"
    
    echo ""
    echo "=== Downloading from S3 ==="
    echo "Source: $s3_uri"
    echo "Destination: $local_file"
    
    # Create directory if needed
    local local_dir
    local_dir="$(dirname "$local_file")"
    if [[ ! -d "$local_dir" ]]; then
        mkdir -p "$local_dir"
    fi
    
    # Download from S3
    if aws s3 cp "$s3_uri" "$local_file" --region "$AWS_DEFAULT_REGION" 2>&1; then
        echo "✓ Download successful"
        return 0
    else
        echo "✗ Download failed" >&2
        return 1
    fi
}

# Function to extract archive
# Usage: extract_archive "local_file.tar.gz"
extract_archive() {
    local local_file="$1"
    
    if [[ ! -f "$local_file" ]]; then
        echo "Warning: Archive not found: $local_file" >&2
        return 1
    fi
    
    echo ""
    echo "=== Extracting archive ==="
    echo "Archive: $local_file"
    
    # Extract based on file type
    if [[ "$local_file" == *.tar.gz || "$local_file" == *.tgz ]]; then
        tar -xzf "$local_file"
    elif [[ "$local_file" == *.tar.bz2 ]]; then
        tar -xjf "$local_file"
    else
        tar -xf "$local_file"
    fi
    
    if [[ $? -eq 0 ]]; then
        echo "✓ Extraction successful"
        return 0
    else
        echo "✗ Extraction failed" >&2
        return 1
    fi
}

# Command: push - Create archive and upload to S3
# Usage: preserve_s3.sh push [archive_name]
cmd_push() {
    check_aws_cli
    
    local archive_name="${1:-./generated/${TF_VAR_environment}_preserved_files.tar.gz}"
    
    echo ""
    echo "=========================================="
    echo "PUSH: Create and Upload Preserved Files"
    echo "=========================================="
    
    # Determine S3 destination
    local s3_destination
    if [[ -n "${PRESERVED_FILES_ARCHIVE:-}" ]]; then
        echo "Using existing PRESERVED_FILES_ARCHIVE: ${PRESERVED_FILES_ARCHIVE}"
        s3_destination="$PRESERVED_FILES_ARCHIVE"
    elif [[ -n "${BINARY_PLAN:-}" ]]; then
        echo "Deriving S3 path from BINARY_PLAN: ${BINARY_PLAN}"
        s3_destination=$(derive_s3_path_from_plan "$BINARY_PLAN")
        echo "Derived S3 path: ${s3_destination}"
    else
        echo "Error: Either PRESERVED_FILES_ARCHIVE or BINARY_PLAN must be set" >&2
        exit 1
    fi
    
    # Create archive using tar_preserving_files.sh
    get_preserving_tar "$archive_name"
    
    # Upload to S3
    upload_to_s3 "$archive_name" "$s3_destination"
    
    # Export for next stage
    echo ""
    echo "=== Exporting environment variable ==="
    echo "PRESERVED_FILES_ARCHIVE=${s3_destination}"
    
    # Write to GITHUB_ENV if available (GitHub Actions)
    if [[ -n "${GITHUB_ENV:-}" ]]; then
        echo "PRESERVED_FILES_ARCHIVE=${s3_destination}" >> "$GITHUB_ENV"
    fi
    
    # Write to file for easy sourcing
    echo "export PRESERVED_FILES_ARCHIVE=\"${s3_destination}\"" > ./preserved_files_archive.env
    echo ""
    echo "Note: Export variable set in ./preserved_files_archive.env"
    echo "      Source this file or set the variable in your pipeline"
    
    echo ""
    echo "=========================================="
    echo "✓ PUSH Complete"
    echo "=========================================="
}

# Command: pull - Download and extract archive from S3
# Usage: preserve_s3.sh pull [archive_name]
cmd_pull() {
    check_aws_cli
    
    if [[ -z "${PRESERVED_FILES_ARCHIVE:-}" ]]; then
        echo "Warning: PRESERVED_FILES_ARCHIVE is not set, skipping pull" >&2
        return 0
    fi
    
    local archive_name="${1:-./generated/${TF_VAR_environment}_preserved_files.tar.gz}"
    
    echo ""
    echo "=========================================="
    echo "PULL: Download and Extract Preserved Files"
    echo "=========================================="
    echo "Source: ${PRESERVED_FILES_ARCHIVE}"
    
    # Download from S3
    if download_from_s3 "$PRESERVED_FILES_ARCHIVE" "$archive_name"; then
        # Extract archive
        extract_archive "$archive_name"
        
        echo ""
        echo "=========================================="
        echo "✓ PULL Complete"
        echo "=========================================="
    else
        echo ""
        echo "=========================================="
        echo "✗ PULL Failed - continuing without preserved files"
        echo "=========================================="
        # Don't fail the pipeline
        return 0
    fi
}

# Command: list - List preserved files in S3 archive
# Usage: preserve_s3.sh list
cmd_list() {
    check_aws_cli
    
    if [[ -z "${PRESERVED_FILES_ARCHIVE:-}" ]]; then
        echo "Error: PRESERVED_FILES_ARCHIVE is not set" >&2
        exit 1
    fi
    
    local temp_archive
    temp_archive="$(mktemp -t preserved_XXXXXX.tar.gz)"
    
    trap "rm -f '$temp_archive' 2>/dev/null || true" RETURN
    
    echo ""
    echo "=== Listing preserved files ==="
    echo "Source: ${PRESERVED_FILES_ARCHIVE}"
    
    # Download archive
    if download_from_s3 "$PRESERVED_FILES_ARCHIVE" "$temp_archive"; then
        echo ""
        list_tar_contents "$temp_archive"
    else
        echo "Error: Failed to download archive" >&2
        return 1
    fi
}

# Main execution
main() {
    local command="${1:-}"
    
    case "$command" in
        push)
            shift
            cmd_push "$@"
            ;;
        pull)
            shift
            cmd_pull "$@"
            ;;
        list)
            shift
            cmd_list "$@"
            ;;
        --help|-h)
            cat <<EOF
Usage: $0 <command> [options]

Commands:
  push [archive_name]    Create archive and upload to S3
                         Default: ./generated/\${TF_VAR_environment}_preserved_files.tar.gz
                         
  pull [archive_name]    Download and extract archive from S3
                         Default: ./generated/\${TF_VAR_environment}_preserved_files.tar.gz
                         
  list                   List contents of S3 archive
  
  --help                 Show this help message

Environment Variables (Required):
  One of the following must be set for 'push':
    PRESERVED_FILES_ARCHIVE   S3 URI for archive (s3://bucket/key)
    BINARY_PLAN               S3 URI for terraform plan (derives archive path)
  
  Required for 'pull' and 'list':
    PRESERVED_FILES_ARCHIVE   S3 URI for archive
  
  Optional:
    AWS_DEFAULT_REGION        AWS region (default: us-east-1)
    TF_VAR_environment        Environment name (default: dev)
    TF_VAR_*                  Other terraform variables for tagging

S3 Path Derivation:
  - If PRESERVED_FILES_ARCHIVE is set, it's used directly
  - If BINARY_PLAN is set (e.g., s3://bucket/path/id.plan), then:
    - Archive path = s3://bucket/path/id_preserved_files.tar.gz
  - Tags are preserved when overwriting, or generated from environment

Examples:
  # Push (with PRESERVED_FILES_ARCHIVE set)
  export PRESERVED_FILES_ARCHIVE="s3://my-bucket/preserves/archive.tar.gz"
  $0 push
  
  # Push (with BINARY_PLAN set)
  export BINARY_PLAN="s3://my-bucket/plans/workflow-123.plan"
  $0 push
  # Creates: s3://my-bucket/plans/workflow-123_preserved_files.tar.gz
  
  # Pull
  export PRESERVED_FILES_ARCHIVE="s3://my-bucket/preserves/archive.tar.gz"
  $0 pull
  
  # List
  export PRESERVED_FILES_ARCHIVE="s3://my-bucket/preserves/archive.tar.gz"
  $0 list

Integration with Pipelines:
  # In Apply stage (after terraform apply)
  export BINARY_PLAN="s3://bucket/harness/backend/\${WORKFLOW_ID}.plan"
  ./preserve_s3.sh push
  source ./preserved_files_archive.env  # Sets PRESERVED_FILES_ARCHIVE
  
  # In Verify stage (before terraform plan)
  # PRESERVED_FILES_ARCHIVE passed from Apply stage
  ./preserve_s3.sh pull
  terraform plan  # Files exist, no drift detected
EOF
            ;;
        "")
            echo "Error: Command required" >&2
            echo "Run '$0 --help' for usage" >&2
            exit 1
            ;;
        *)
            echo "Error: Unknown command '$command'" >&2
            echo "Run '$0 --help' for usage" >&2
            exit 1
            ;;
    esac
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi

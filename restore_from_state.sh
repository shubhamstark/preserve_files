#!/bin/bash
# Script to recreate local files from Terraform state file
# This prevents Terraform from detecting files as needing recreation

set -e  # Exit on error

STATE_FILE="${STATE_FILE:-terraform.tfstate}"

# Check if jq is installed
if ! command -v jq &> /dev/null; then
    echo "Error: jq is required but not installed" >&2
    echo "Install with: brew install jq (macOS) or apt-get install jq (Linux)" >&2
    exit 1
fi

# Check if state file exists
if [[ ! -f "$STATE_FILE" ]]; then
    echo "Error: Terraform state file not found: $STATE_FILE" >&2
    exit 1
fi

echo "Recreating local files from Terraform state..."
echo "State file: $STATE_FILE"
echo ""

# Extract local_file resources from state
local_files=$(jq -r '.resources[] | select(.type == "local_file") | .instances[]' "$STATE_FILE" 2>/dev/null)

if [[ -z "$local_files" ]]; then
    echo "No local_file resources found in state"
    exit 0
fi

# Counter for created files
created=0
skipped=0

# Process each local_file resource
while IFS= read -r instance; do
    # Extract attributes
    filename=$(echo "$instance" | jq -r '.attributes.filename // empty')
    content=$(echo "$instance" | jq -r '.attributes.content // empty')
    file_permission=$(echo "$instance" | jq -r '.attributes.file_permission // "0644"')
    
    # Skip if no filename
    if [[ -z "$filename" || "$filename" == "null" ]]; then
        continue
    fi
    
    # Check if file already exists with correct content
    if [[ -f "$filename" ]]; then
        existing_content=$(cat "$filename")
        if [[ "$existing_content" == "$content" ]]; then
            echo "  Skipping: $filename (already exists with correct content)"
            ((skipped++))
            continue
        else
            echo "  Updating: $filename (content differs)"
        fi
    else
        echo "  Creating: $filename"
    fi
    
    # Create parent directory if needed
    parent_dir=$(dirname "$filename")
    if [[ -n "$parent_dir" && "$parent_dir" != "." ]]; then
        mkdir -p "$parent_dir"
    fi
    
    # Write content to file
    printf '%s' "$content" > "$filename"
    
    # Set file permissions
    if [[ -n "$file_permission" && "$file_permission" != "null" ]]; then
        chmod "$file_permission" "$filename"
    fi
    
    ((created++))
    
done < <(jq -c '.resources[] | select(.type == "local_file") | .instances[]' "$STATE_FILE")

echo ""
echo "Summary:"
echo "  Created/Updated: $created"
echo "  Skipped: $skipped"
echo "  Total: $((created + skipped))"
echo ""
echo "Files recreated successfully from state!"

#!/bin/bash
# Script to get list of file paths that need to be preserved
# Sources: harness.json preserved_files + terraform state local_file resources
# Returns: Deduplicated list of file paths

set -e  # Exit on error

# Default configuration
HARNESS_FILE="${HARNESS_FILE:-harness.json}"
TERRAFORM="${TERRAFORM:-terraform}"
JQ="${JQ:-jq}"

# Function to check if jq is installed
check_jq() {
    if ! command -v jq &> /dev/null; then
        echo "Error: jq is required but not installed" >&2
        echo "Install with: brew install jq (macOS) or apt-get install jq (Linux)" >&2
        exit 1
    fi
}

# Function to check if terraform is installed
check_terraform() {
    if ! command -v "$TERRAFORM" &> /dev/null; then
        echo "Warning: terraform not found, skipping state-based files" >&2
        return 1
    fi
    return 0
}

# Function to get files from harness.json
get_harness_files() {
    if [[ ! -f "$HARNESS_FILE" ]]; then
        # Not an error - some repos may not have harness.json
        return 0
    fi
    
    jq -r '.preserved_files[]? // empty' "$HARNESS_FILE" 2>/dev/null || {
        echo "Warning: Could not parse $HARNESS_FILE" >&2
        return 0
    }
}

# Function to get local_file filenames from terraform state
get_state_files() {
    # Check if terraform is available
    if ! check_terraform; then
        return 0
    fi
    
    # Create temp file for state
    local state_file
    state_file="$(mktemp -t tfstate.XXXXXX)"
    
    # Cleanup on exit
    trap "rm -f '$state_file' 2>/dev/null || true" RETURN
    
    # Pull terraform state
    if ! "$TERRAFORM" state pull >"$state_file" 2>/dev/null; then
        return 0
    fi
    
    # Check if state file is empty
    if [[ ! -s "$state_file" ]]; then
        return 0
    fi
    
    # Extract local_file resource filenames
    "$JQ" -r '.resources[]? | 
             select(.mode=="managed" and .type=="local_file") | 
             .instances[]? | 
             .attributes.filename // empty' <"$state_file" 2>/dev/null | \
    while IFS= read -r filename; do
        # Skip empty lines
        [[ -z "$filename" ]] && continue
        
        # Skip unsafe paths (containing ..)
        [[ "$filename" == *".."* ]] && continue
        
        # Output the filename
        echo "$filename"
    done
}

# Function to validate path safety
is_safe_path() {
    local path="$1"
    
    # Reject paths containing ..
    [[ "$path" == *".."* ]] && return 1
    
    # Accept the path
    return 0
}

# Function to normalize path (remove leading ./)
normalize_path() {
    local path="$1"
    # Remove leading ./
    path="${path#./}"
    echo "$path"
}

# Main function to get all preserving file names
get_preserving_file_names() {
    check_jq
    
    # Collect all file paths
    local all_files=()
    
    echo ""
    echo "=== Collecting files to preserve ==="
    
    # Get files from harness.json
    echo "Reading harness.json..."
    local harness_count=0
    while IFS= read -r file; do
        if [[ -n "$file" ]] && is_safe_path "$file"; then
            local normalized
            normalized=$(normalize_path "$file")
            all_files+=("$normalized")
            ((harness_count++))
        fi
    done < <(get_harness_files)
    echo "  Found $harness_count file(s) from harness.json"
    
    # Get files from terraform state
    echo "Reading terraform state..."
    local state_count=0
    while IFS= read -r file; do
        if [[ -n "$file" ]] && is_safe_path "$file"; then
            local normalized
            normalized=$(normalize_path "$file")
            all_files+=("$normalized")
            ((state_count++))
        fi
    done < <(get_state_files)
    echo "  Found $state_count file(s) from terraform state"
    
    # Remove duplicates and sort
    if [[ ${#all_files[@]} -eq 0 ]]; then
        echo ""
        echo "No files to preserve"
        return 0
    fi
    
    echo ""
    echo "=== Deduplicating file list ==="
    local unique_files
    unique_files=$(printf '%s\n' "${all_files[@]}" | sort -u)
    
    local total_count
    total_count=$(echo "$unique_files" | wc -l | tr -d ' ')
    
    local duplicate_count=$((${#all_files[@]} - total_count))
    
    echo "  Total collected: ${#all_files[@]}"
    echo "  Duplicates removed: $duplicate_count"
    echo "  Unique files: $total_count"
    
    # Output the unique list
    echo ""
    echo "=== Files to preserve ==="
    echo "$unique_files"
    
    return 0
}

# Main execution
main() {
    local command="${1:-list}"
    
    case "$command" in
        list)
            get_preserving_file_names
            ;;
        --help|-h)
            cat <<EOF
Usage: $0 [command]

Commands:
  list     Get deduplicated list of files to preserve (default)
  --help   Show this help message

Environment Variables:
  HARNESS_FILE   Path to harness.json (default: harness.json)
  TERRAFORM      Terraform binary to use (default: terraform)
  JQ             jq binary to use (default: jq)

Description:
  This script collects file paths from two sources:
  1. harness.json preserved_files array
  2. Terraform state local_file resource filenames
  
  It combines both lists, removes duplicates, and outputs the unique paths.
  
Examples:
  $0
  $0 list
  HARNESS_FILE=custom.json $0
EOF
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

#!/bin/bash
# Script to create tar archives from file lists
# Integrates with get_preserving_file_name.sh

set -e  # Exit on error

# Source the get_preserving_file_names function
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/get_preserving_file_name.sh"

# Function to create tar archive from a list of file paths
# Usage: tar_files_from_list "file1 file2 file3" "output.tar.gz"
tar_files_from_list() {
    local file_list="$1"
    local output_tar="$2"
    
    if [[ -z "$output_tar" ]]; then
        echo "Error: Output tar path is required" >&2
        return 1
    fi
    
    if [[ -z "$file_list" ]]; then
        echo "Warning: No files provided to tar" >&2
        echo "Creating empty archive: $output_tar"
        # Create empty tar file
        tar -cf "${output_tar%.gz}" --files-from /dev/null
        if [[ "$output_tar" == *.gz ]]; then
            gzip -f "${output_tar%.gz}"
        fi
        return 0
    fi
    
    echo ""
    echo "=== Creating tar archive ==="
    echo "Output: $output_tar"
    
    # Convert file list to array
    local files_array=()
    local existing_count=0
    local missing_count=0
    
    while IFS= read -r file; do
        [[ -z "$file" ]] && continue
        
        if [[ -e "$file" ]]; then
            files_array+=("$file")
            echo "  ✓ Adding: $file"
            ((existing_count++))
        else
            echo "  ✗ Missing: $file (skipping)"
            ((missing_count++))
        fi
    done <<< "$file_list"
    
    echo ""
    echo "Summary:"
    echo "  Files to archive: $existing_count"
    echo "  Files missing: $missing_count"
    
    if [[ ${#files_array[@]} -eq 0 ]]; then
        echo ""
        echo "Warning: No files found to archive"
        echo "Creating empty archive: $output_tar"
        tar -cf "${output_tar%.gz}" --files-from /dev/null
        if [[ "$output_tar" == *.gz ]]; then
            gzip -f "${output_tar%.gz}"
        fi
        return 0
    fi
    
    # Create directory for output if needed
    local output_dir
    output_dir="$(dirname "$output_tar")"
    if [[ ! -d "$output_dir" ]]; then
        mkdir -p "$output_dir"
    fi
    
    # Determine if we need compression
    if [[ "$output_tar" == *.tar.gz || "$output_tar" == *.tgz ]]; then
        echo ""
        echo "Creating compressed tar archive..."
        tar -czf "$output_tar" "${files_array[@]}"
    elif [[ "$output_tar" == *.tar.bz2 ]]; then
        echo ""
        echo "Creating bzip2 compressed tar archive..."
        tar -cjf "$output_tar" "${files_array[@]}"
    elif [[ "$output_tar" == *.tar ]]; then
        echo ""
        echo "Creating uncompressed tar archive..."
        tar -cf "$output_tar" "${files_array[@]}"
    else
        # Default to .tar.gz if no extension
        echo ""
        echo "No compression extension detected, creating .tar.gz..."
        tar -czf "${output_tar}.tar.gz" "${files_array[@]}"
        output_tar="${output_tar}.tar.gz"
    fi
    
    # Verify archive was created
    if [[ -f "$output_tar" ]]; then
        local size
        size=$(du -h "$output_tar" | cut -f1)
        echo "✓ Archive created successfully: $output_tar ($size)"
        return 0
    else
        echo "✗ Error: Failed to create archive" >&2
        return 1
    fi
}

# Function to get preserving files and create tar archive
# Usage: get_preserving_tar "output.tar.gz"
get_preserving_tar() {
    local output_tar="${1:-preserved_files.tar.gz}"
    
    echo ""
    echo "=========================================="
    echo "Creating Preserving Files Archive"
    echo "=========================================="
    
    # Get the list of files to preserve (capture only the file paths)
    local temp_output
    temp_output=$(get_preserving_file_names 2>&1)
    
    # Display the collection output
    echo "$temp_output"
    
    # Extract just the file paths (lines after "=== Files to preserve ===")
    local file_list
    file_list=$(echo "$temp_output" | \
                sed -n '/=== Files to preserve ===/,$p' | \
                tail -n +2 | \
                grep -v '^$' | \
                grep -v '^===')
    
    # Check if we got any files
    if [[ -z "$file_list" ]]; then
        echo ""
        echo "No files to preserve, creating empty archive"
        file_list=""
    fi
    
    # Create the tar archive
    tar_files_from_list "$file_list" "$output_tar"
    
    local exit_code=$?
    
    if [[ $exit_code -eq 0 ]]; then
        echo ""
        echo "=========================================="
        echo "✓ Preserving files archive complete"
        echo "=========================================="
    else
        echo ""
        echo "=========================================="
        echo "✗ Failed to create preserving files archive"
        echo "=========================================="
    fi
    
    return $exit_code
}

# Function to list contents of a tar archive
# Usage: list_tar_contents "archive.tar.gz"
list_tar_contents() {
    local tar_file="$1"
    
    if [[ ! -f "$tar_file" ]]; then
        echo "Error: Archive not found: $tar_file" >&2
        return 1
    fi
    
    echo ""
    echo "=== Contents of $tar_file ==="
    
    if [[ "$tar_file" == *.tar.gz || "$tar_file" == *.tgz ]]; then
        tar -tzf "$tar_file"
    elif [[ "$tar_file" == *.tar.bz2 ]]; then
        tar -tjf "$tar_file"
    else
        tar -tf "$tar_file"
    fi
    
    local file_count
    if [[ "$tar_file" == *.tar.gz || "$tar_file" == *.tgz ]]; then
        file_count=$(tar -tzf "$tar_file" | wc -l | tr -d ' ')
    elif [[ "$tar_file" == *.tar.bz2 ]]; then
        file_count=$(tar -tjf "$tar_file" | wc -l | tr -d ' ')
    else
        file_count=$(tar -tf "$tar_file" | wc -l | tr -d ' ')
    fi
    
    echo ""
    echo "Total files in archive: $file_count"
    
    return 0
}

# Main execution
main() {
    local command="${1:-}"
    
    case "$command" in
        tar)
            shift
            local file_list="$1"
            local output_tar="${2:-preserved_files.tar.gz}"
            tar_files_from_list "$file_list" "$output_tar"
            ;;
        preserve)
            shift
            local output_tar="${1:-preserved_files.tar.gz}"
            get_preserving_tar "$output_tar"
            ;;
        list)
            shift
            local tar_file="$1"
            if [[ -z "$tar_file" ]]; then
                echo "Error: Tar file path required" >&2
                echo "Usage: $0 list <tar_file>" >&2
                exit 1
            fi
            list_tar_contents "$tar_file"
            ;;
        --help|-h)
            cat <<EOF
Usage: $0 <command> [options]

Commands:
  tar <file_list> <output_tar>    Create tar from space/newline separated file list
  preserve [output_tar]           Auto-collect files and create tar (default: preserved_files.tar.gz)
  list <tar_file>                 List contents of a tar archive
  --help                          Show this help message

Examples:
  # Create tar from specific files
  $0 tar "file1.txt file2.txt" output.tar.gz
  
  # Auto-collect and create preserving tar
  $0 preserve
  $0 preserve custom_output.tar.gz
  
  # List archive contents
  $0 list preserved_files.tar.gz

Description:
  This script creates tar archives from file lists. The 'preserve' command
  integrates with get_preserving_file_name.sh to automatically collect files
  from harness.json and terraform state, then creates a tar archive.

Environment Variables:
  HARNESS_FILE   Path to harness.json (default: harness.json)
  TERRAFORM      Terraform binary to use (default: terraform)
  JQ             jq binary to use (default: jq)
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

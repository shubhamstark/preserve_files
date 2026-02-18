#!/bin/bash
# Script to tar, untar, and delete files specified in harness.json

set -e  # Exit on error

HARNESS_FILE="${HARNESS_FILE:-harness.json}"

# Function to load files from harness.json
load_harness_json() {
    if [[ ! -f "$HARNESS_FILE" ]]; then
        echo "Error: $HARNESS_FILE not found" >&2
        exit 1
    fi
    
    # Check if jq is installed
    if ! command -v jq &> /dev/null; then
        echo "Error: jq is required but not installed" >&2
        echo "Install with: brew install jq (macOS) or apt-get install jq (Linux)" >&2
        exit 1
    fi
    
    jq -r '.preserved_files[]' "$HARNESS_FILE" 2>/dev/null || {
        echo "Error: Invalid JSON in $HARNESS_FILE" >&2
        exit 1
    }
}

# Function to create tar archive
tar_files() {
    local archive_name="${1:-preserved_files.tar.gz}"
    
    echo "Creating archive: $archive_name"
    
    # Read files from harness.json into array
    local files=()
    while IFS= read -r file; do
        if [[ -n "$file" ]]; then
            if [[ -e "$file" ]]; then
                echo "  Adding: $file"
                files+=("$file")
            else
                echo "  Warning: File not found, skipping: $file"
            fi
        fi
    done < <(load_harness_json)
    
    if [[ ${#files[@]} -eq 0 ]]; then
        echo "No files to tar"
        return 0
    fi
    
    # Create tar archive with compression
    if [[ "$archive_name" == *.tar.gz || "$archive_name" == *.tgz ]]; then
        tar -czf "$archive_name" "${files[@]}"
    elif [[ "$archive_name" == *.tar.bz2 ]]; then
        tar -cjf "$archive_name" "${files[@]}"
    else
        tar -cf "$archive_name" "${files[@]}"
    fi
    
    echo "Archive created successfully: $archive_name"
}

# Function to extract tar archive
untar_files() {
    local archive_name="${1:-preserved_files.tar.gz}"
    
    if [[ ! -f "$archive_name" ]]; then
        echo "Error: Archive $archive_name not found" >&2
        return 1
    fi
    
    echo "Extracting from archive: $archive_name"
    
    # Get list of files in archive
    local tar_opts=""
    if [[ "$archive_name" == *.tar.gz || "$archive_name" == *.tgz ]]; then
        tar_opts="-tzf"
    elif [[ "$archive_name" == *.tar.bz2 ]]; then
        tar_opts="-tjf"
    else
        tar_opts="-tf"
    fi
    
    # Extract each file to its original location
    while IFS= read -r member; do
        # Skip directories
        [[ "$member" == */ ]] && continue
        
        local target_path="$member"
        
        # Handle absolute paths (tar strips leading /)
        if [[ "$target_path" == Users/* || "$target_path" == home/* ]]; then
            target_path="/$target_path"
        elif [[ "$target_path" != /* ]]; then
            # Make relative paths absolute
            target_path="$(pwd)/$target_path"
        fi
        
        echo "  Extracting: $target_path"
        
        # Create parent directory if needed
        local parent_dir="$(dirname "$target_path")"
        if [[ -n "$parent_dir" ]]; then
            mkdir -p "$parent_dir"
        fi
        
        # Extract the specific file
        if [[ "$archive_name" == *.tar.gz || "$archive_name" == *.tgz ]]; then
            tar -xzf "$archive_name" -O "$member" > "$target_path"
        elif [[ "$archive_name" == *.tar.bz2 ]]; then
            tar -xjf "$archive_name" -O "$member" > "$target_path"
        else
            tar -xf "$archive_name" -O "$member" > "$target_path"
        fi
    done < <(tar $tar_opts "$archive_name")
    
    echo "Extraction completed successfully"
}

# Function to delete files
delete_files() {
    echo "Deleting files..."
    
    local deleted=0
    while IFS= read -r file_path; do
        if [[ -n "$file_path" ]]; then
            if [[ -e "$file_path" ]]; then
                if rm "$file_path" 2>/dev/null; then
                    echo "  Deleted: $file_path"
                    ((deleted++))
                else
                    echo "  Error deleting $file_path" >&2
                fi
            else
                echo "  File not found, skipping: $file_path"
            fi
        fi
    done < <(load_harness_json)
    
    if [[ $deleted -eq 0 ]]; then
        echo "No files to delete"
    else
        echo "Deletion completed"
    fi
}

# Function to delete all tar files
delete_all_tar_files() {
    echo "Deleting all tar files in the current directory..."
    
    local deleted=0
    shopt -s nullglob  # Make glob patterns expand to nothing if no match
    
    for file in *.tar.gz *.tgz *.tar.bz2 *.tar; do
        if [[ -f "$file" ]]; then
            if rm "$file" 2>/dev/null; then
                echo "  Deleted: $file"
                ((deleted++))
            else
                echo "  Error deleting $file" >&2
            fi
        fi
    done
    
    shopt -u nullglob  # Restore default behavior
    
    if [[ $deleted -eq 0 ]]; then
        echo "No tar files found"
    else
        echo "All tar files deleted"
    fi
}

# Main function
main() {
    if [[ $# -lt 1 ]]; then
        echo "Usage:"
        echo "  $0 tar [archive_name]       - Create tar archive"
        echo "  $0 untar [archive_name]     - Extract tar archive"
        echo "  $0 delete                   - Delete all files"
        echo "  $0 delete_tar               - Delete all tar files"
        exit 1
    fi
    
    local command="$1"
    shift
    
    case "$command" in
        tar)
            tar_files "$@"
            ;;
        untar)
            untar_files "$@"
            ;;
        delete)
            delete_files
            ;;
        delete_tar)
            delete_all_tar_files
            ;;
        *)
            echo "Unknown command: $command" >&2
            echo "Valid commands: tar, untar, delete, delete_tar" >&2
            exit 1
            ;;
    esac
}

# Run main if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi

#!/usr/bin/env python3
"""
Script to tar, untar, and delete files specified in harness.json
"""

import json
import tarfile
import os
import sys
from pathlib import Path


def load_harness_json(harness_file='harness.json'):
    """Load and parse the harness.json file."""
    try:
        with open(harness_file, 'r') as f:
            data = json.load(f)
        return data.get('preserved_files', [])
    except FileNotFoundError:
        print(f"Error: {harness_file} not found")
        sys.exit(1)
    except json.JSONDecodeError as e:
        print(f"Error: Invalid JSON in {harness_file}: {e}")
        sys.exit(1)


def tar_files(archive_name='preserved_files.tar.gz', harness_file='harness.json'):
    """
    Create a tar archive of all files listed in harness.json.
    Preserves the full directory structure.
    """
    files_to_tar = load_harness_json(harness_file)
    
    if not files_to_tar:
        print("No files to tar")
        return
    
    print(f"Creating archive: {archive_name}")
    
    with tarfile.open(archive_name, 'w:gz') as tar:
        for file_path in files_to_tar:
            if os.path.exists(file_path):
                # Add file with its full path preserved
                print(f"  Adding: {file_path}")
                tar.add(file_path, arcname=file_path)
            else:
                print(f"  Warning: File not found, skipping: {file_path}")
    
    print(f"Archive created successfully: {archive_name}")


def untar_files(archive_name='preserved_files.tar.gz'):
    """
    Extract files from tar archive to their original locations.
    Creates directories as needed.
    """
    if not os.path.exists(archive_name):
        print(f"Error: Archive {archive_name} not found")
        return
    
    print(f"Extracting from archive: {archive_name}")
    
    # Auto-detect compression type
    try:
        if archive_name.endswith('.tar.gz') or archive_name.endswith('.tgz'):
            tar = tarfile.open(archive_name, 'r:gz')
        elif archive_name.endswith('.tar.bz2'):
            tar = tarfile.open(archive_name, 'r:bz2')
        else:
            tar = tarfile.open(archive_name, 'r')
    except Exception as e:
        print(f"Error opening archive: {e}")
        return
    
    with tar:
        for member in tar.getmembers():
            if member.isfile():
                # Get the path from the archive
                target_path = member.name
                
                # If path was absolute, tar strips the leading '/'
                # Check if we need to add it back
                # (Heuristic: if path starts with 'Users' or 'home', it was likely absolute)
                if target_path.startswith('Users/') or target_path.startswith('home/'):
                    target_path = '/' + target_path
                # Otherwise, treat as relative to current directory
                elif not os.path.isabs(target_path):
                    target_path = os.path.abspath(target_path)
                
                print(f"  Extracting: {target_path}")
                
                # Create parent directories if they don't exist
                parent_dir = os.path.dirname(target_path)
                if parent_dir:
                    os.makedirs(parent_dir, exist_ok=True)
                
                # Extract file content and write to exact location
                file_obj = tar.extractfile(member)
                if file_obj:
                    with open(target_path, 'wb') as f:
                        f.write(file_obj.read())
    
    print("Extraction completed successfully")


def delete_files(harness_file='harness.json'):
    """
    Delete all files listed in harness.json.
    """
    files_to_delete = load_harness_json(harness_file)
    
    if not files_to_delete:
        print("No files to delete")
        return
    
    print("Deleting files...")
    
    for file_path in files_to_delete:
        if os.path.exists(file_path):
            try:
                os.remove(file_path)
                print(f"  Deleted: {file_path}")
            except Exception as e:
                print(f"  Error deleting {file_path}: {e}")
        else:
            print(f"  File not found, skipping: {file_path}")
    
    print("Deletion completed")


def main():
    """Main function with CLI interface."""
    if len(sys.argv) < 2:
        print("Usage:")
        print("  python tar.py tar [archive_name]       - Create tar archive")
        print("  python tar.py untar [archive_name]     - Extract tar archive")
        print("  python tar.py delete                   - Delete all files")
        sys.exit(1)
    
    command = sys.argv[1].lower()
    
    if command == 'tar':
        archive_name = sys.argv[2] if len(sys.argv) > 2 else 'preserved_files.tar.gz'
        tar_files(archive_name)
    
    elif command == 'untar':
        archive_name = sys.argv[2] if len(sys.argv) > 2 else 'preserved_files.tar.gz'
        untar_files(archive_name)
    
    elif command == 'delete':
        delete_files()
    
    else:
        print(f"Unknown command: {command}")
        print("Valid commands: tar, untar, delete")
        sys.exit(1)


if __name__ == '__main__':
    main()

#!/usr/bin/env python3
"""
Script to tar, untar, and delete files specified in harness.json
"""

import json
import subprocess
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
    
    # Filter existing files and warn about missing ones
    existing_files = []
    for file_path in files_to_tar:
        if os.path.exists(file_path):
            print(f"  Adding: {file_path}")
            existing_files.append(file_path)
        else:
            print(f"  Warning: File not found, skipping: {file_path}")
    
    if not existing_files:
        print("No files to tar")
        return
    
    # Determine compression flag
    if archive_name.endswith('.tar.gz') or archive_name.endswith('.tgz'):
        tar_cmd = ['tar', '-czf', archive_name]
    elif archive_name.endswith('.tar.bz2'):
        tar_cmd = ['tar', '-cjf', archive_name]
    else:
        tar_cmd = ['tar', '-cf', archive_name]
    
    # Add files to command
    tar_cmd.extend(existing_files)
    
    # Execute tar command
    try:
        result = subprocess.run(tar_cmd, capture_output=True, text=True, check=True)
        print(f"Archive created successfully: {archive_name}")
    except subprocess.CalledProcessError as e:
        print(f"Error creating archive: {e.stderr}")
        sys.exit(1)


def untar_files(archive_name='preserved_files.tar.gz'):
    """
    Extract files from tar archive to their original locations.
    Creates directories as needed.
    """
    if not os.path.exists(archive_name):
        print(f"Error: Archive {archive_name} not found")
        return
    
    print(f"Extracting from archive: {archive_name}")
    
    # Determine tar list command based on compression
    if archive_name.endswith('.tar.gz') or archive_name.endswith('.tgz'):
        list_cmd = ['tar', '-tzf', archive_name]
    elif archive_name.endswith('.tar.bz2'):
        list_cmd = ['tar', '-tjf', archive_name]
    else:
        list_cmd = ['tar', '-tf', archive_name]
    
    # Get list of files in archive
    try:
        result = subprocess.run(list_cmd, capture_output=True, text=True, check=True)
        members = result.stdout.strip().split('\n')
    except subprocess.CalledProcessError as e:
        print(f"Error listing archive contents: {e.stderr}")
        return
    
    # Extract each file to its original location
    for member in members:
        # Skip empty lines and directories
        if not member or member.endswith('/'):
            continue
        
        target_path = member
        
        # If path was absolute, tar strips the leading '/'
        # Check if we need to add it back
        if target_path.startswith('Users/') or target_path.startswith('home/'):
            target_path = '/' + target_path
        elif not os.path.isabs(target_path):
            target_path = os.path.abspath(target_path)
        
        print(f"  Extracting: {target_path}")
        
        # Create parent directories if they don't exist
        parent_dir = os.path.dirname(target_path)
        if parent_dir:
            os.makedirs(parent_dir, exist_ok=True)
        
        # Determine extract command based on compression
        if archive_name.endswith('.tar.gz') or archive_name.endswith('.tgz'):
            extract_cmd = ['tar', '-xzf', archive_name, '-O', member]
        elif archive_name.endswith('.tar.bz2'):
            extract_cmd = ['tar', '-xjf', archive_name, '-O', member]
        else:
            extract_cmd = ['tar', '-xf', archive_name, '-O', member]
        
        # Extract file content and write to target location
        try:
            result = subprocess.run(extract_cmd, capture_output=True, check=True)
            with open(target_path, 'wb') as f:
                f.write(result.stdout)
        except subprocess.CalledProcessError as e:
            print(f"  Error extracting {member}: {e.stderr}")
        except IOError as e:
            print(f"  Error writing to {target_path}: {e}")
    
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
    
def delete_all_tar_files():
    """Delete all tar files in the current directory."""
    print("Deleting all tar files in the current directory...")
    for file in os.listdir('.'):
        if file.endswith('.tar.gz') or file.endswith('.tgz') or file.endswith('.tar.bz2') or file.endswith('.tar'):
            try:
                os.remove(file)
                print(f"  Deleted: {file}")
            except Exception as e:
                print(f"  Error deleting {file}: {e}")
    print("All tar files deleted")


def main():
    """Main function with CLI interface."""
    if len(sys.argv) < 2:
        print("Usage:")
        print("  python tar.py tar [archive_name]       - Create tar archive")
        print("  python tar.py untar [archive_name]     - Extract tar archive")
        print("  python tar.py delete                   - Delete all files")
        print("  python tar.py delete_tar               - Delete all tar files")
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
    
    elif command == 'delete_tar':
        delete_all_tar_files()
    
    else:
        print(f"Unknown command: {command}")
        print("Valid commands: tar, untar, delete, delete_tar")
        sys.exit(1)


if __name__ == '__main__':
    main()

#!/usr/bin/env python3
"""
Preserver class to push and pull preserved files to/from AWS S3
"""

import os
import subprocess
import json


class Preserver:
    """
    A class to manage preservation of files to AWS S3.
    Files are tarred using tar.py and uploaded to S3.
    Uses AWS CLI for S3 operations.
    """
    
    def __init__(self, unique_key, bucket_name=None, aws_profile=None):
        """
        Initialize the Preserver.
        
        Args:
            unique_key (str): Unique identifier for this preservation (used as S3 object key)
            bucket_name (str, optional): S3 bucket name. If None, must be set via environment variable PRESERVE_BUCKET
            aws_profile (str, optional): AWS profile name to use
        """
        self.unique_key = unique_key
        self.archive_name = f"{unique_key}.tar.gz"
        self.bucket_name = bucket_name or os.environ.get('PRESERVE_BUCKET')
        self.aws_profile = aws_profile or os.environ.get('AWS_PROFILE')
        
        if not self.bucket_name:
            raise ValueError("bucket_name must be provided or PRESERVE_BUCKET environment variable must be set")
        
        # Check if AWS CLI is available
        try:
            subprocess.run(['aws', '--version'], capture_output=True, check=True)
        except (subprocess.CalledProcessError, FileNotFoundError):
            raise RuntimeError("AWS CLI is not installed or not in PATH")
        
        print(f"Preserver initialized with key: {unique_key}")
        print(f"S3 Bucket: {self.bucket_name}")
    
    def _build_aws_command(self, command):
        """
        Build AWS CLI command with optional profile.
        
        Args:
            command (list): Base AWS command
            
        Returns:
            list: Complete command with profile if set
        """
        if self.aws_profile:
            return ['aws', '--profile', self.aws_profile] + command
        return ['aws'] + command
    
    def push(self, harness_file='harness.json'):
        """
        Tar the preserved files and push to S3.
        
        Args:
            harness_file (str): Path to harness.json file
        
        Returns:
            bool: True if successful, False otherwise
        """
        try:
            # Step 1: Create tar archive using tar.py
            print(f"\n=== PUSH: Creating tar archive ===")
            result = subprocess.run(
                ['python', 'tar.py', 'tar', self.archive_name],
                capture_output=True,
                text=True
            )
            
            if result.returncode != 0:
                print(f"Error creating tar: {result.stderr}")
                return False
            
            print(result.stdout)
            
            # Step 2: Upload to S3 using AWS CLI
            print(f"\n=== PUSH: Uploading to S3 ===")
            if not os.path.exists(self.archive_name):
                print(f"Error: Archive {self.archive_name} not found")
                return False
            
            s3_path = f"s3://{self.bucket_name}/{self.archive_name}"
            cmd = self._build_aws_command(['s3', 'cp', self.archive_name, s3_path])
            
            result = subprocess.run(cmd, capture_output=True, text=True)
            
            if result.returncode != 0:
                print(f"Error uploading to S3: {result.stderr}")
                return False
            
            print(result.stdout)
            print(f"✓ Successfully uploaded {self.archive_name} to {s3_path}")
            
            # Optional: Clean up local tar file
            # os.remove(self.archive_name)
            
            return True
            
        except Exception as e:
            print(f"Error during push: {e}")
            return False
    
    def pull(self, cleanup_local_tar=True):
        """
        Download tar from S3 and extract files.
        
        Args:
            cleanup_local_tar (bool): Whether to delete the local tar file after extraction
        
        Returns:
            bool: True if successful, False otherwise
        """
        try:
            # Step 1: Download from S3 using AWS CLI
            print(f"\n=== PULL: Downloading from S3 ===")
            s3_path = f"s3://{self.bucket_name}/{self.archive_name}"
            cmd = self._build_aws_command(['s3', 'cp', s3_path, self.archive_name])
            
            result = subprocess.run(cmd, capture_output=True, text=True)
            
            if result.returncode != 0:
                print(f"Error downloading from S3: {result.stderr}")
                return False
            
            print(result.stdout)
            print(f"✓ Successfully downloaded {self.archive_name} from {s3_path}")
            
            # Step 2: Extract tar archive using tar.py
            print(f"\n=== PULL: Extracting tar archive ===")
            result = subprocess.run(
                ['python', 'tar.py', 'untar', self.archive_name],
                capture_output=True,
                text=True
            )
            
            if result.returncode != 0:
                print(f"Error extracting tar: {result.stderr}")
                return False
            
            print(result.stdout)
            
            # Optional: Clean up local tar file
            if cleanup_local_tar and os.path.exists(self.archive_name):
                os.remove(self.archive_name)
                print(f"✓ Cleaned up local archive: {self.archive_name}")
            
            return True
            
        except Exception as e:
            print(f"Error during pull: {e}")
            return False
    
    def list_s3_preservations(self):
        """
        List all preservation archives in the S3 bucket.
        
        Returns:
            list: List of archive names in the bucket
        """
        try:
            cmd = self._build_aws_command(['s3', 'ls', f"s3://{self.bucket_name}/"])
            result = subprocess.run(cmd, capture_output=True, text=True)
            
            if result.returncode != 0:
                print(f"Error listing S3 bucket: {result.stderr}")
                return []
            
            # Parse ls output
            archives = []
            for line in result.stdout.strip().split('\n'):
                if line and line.strip():
                    # AWS S3 ls format: "2024-01-01 12:00:00    1234 filename.tar.gz"
                    parts = line.split()
                    if len(parts) >= 4 and parts[-1].endswith('.tar.gz'):
                        archives.append(parts[-1])
            
            if not archives:
                print("No preservations found in bucket")
                return []
            
            print(f"\nPreservations in s3://{self.bucket_name}:")
            for archive in archives:
                print(f"  - {archive}")
            
            return archives
            
        except Exception as e:
            print(f"Error listing preservations: {e}")
            return []


# Example usage
if __name__ == '__main__':
    import sys
    
    if len(sys.argv) < 3:
        print("Usage:")
        print("  python preserve.py <unique_key> push")
        print("  python preserve.py <unique_key> pull")
        print("  python preserve.py <unique_key> list")
        print("\nEnvironment variables:")
        print("  PRESERVE_BUCKET - S3 bucket name (required)")
        print("  AWS_PROFILE - AWS profile to use (optional)")
        print("\nRequirements:")
        print("  - AWS CLI must be installed and configured")
        sys.exit(1)
    
    unique_key = sys.argv[1]
    command = sys.argv[2].lower()
    
    bucket = os.environ.get('PRESERVE_BUCKET')
    aws_profile = os.environ.get('AWS_PROFILE')
    
    preserver = Preserver(unique_key, bucket_name=bucket, aws_profile=aws_profile)
    
    if command == 'push':
        success = preserver.push()
        sys.exit(0 if success else 1)
    
    elif command == 'pull':
        success = preserver.pull()
        sys.exit(0 if success else 1)
    
    elif command == 'list':
        preserver.list_s3_preservations()
    
    else:
        print(f"Unknown command: {command}")
        print("Valid commands: push, pull, list")
        sys.exit(1)

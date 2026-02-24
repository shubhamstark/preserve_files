#!/bin/bash
# Test script for preserve.sh approach with S3
# Simulates the Apply -> Verify Plan workflow with S3 preservation
rm -r generated 
rm -r scripts 
rm -r test_temp 
rm -r temp 
rm -r docs 
rm -r build 


terraform apply -auto-approve   

set +e  # Don't exit on error - we want to report where it failed

echo "=========================================="
echo "Test: Preserve.sh with S3 Integration"
echo "=========================================="
echo ""

# Check mandatory environment variables
echo "=== Checking Prerequisites ==="
echo "Verifying PRESERVE_BUCKET environment variable..."

if [[ -z "${PRESERVE_BUCKET}" ]]; then
    echo "✗ TEST FAILED: PRESERVE_BUCKET environment variable not set"
    echo ""
    echo "This variable is MANDATORY for S3 preservation tests."
    echo ""
    echo "Please set it before running the test:"
    echo "  export PRESERVE_BUCKET=your-bucket-name"
    echo "  ./test_preserve_approach.sh"
    exit 1
fi

echo "✓ PRESERVE_BUCKET is set: ${PRESERVE_BUCKET}"

UNIQUE_KEY="test-$(date +%s)"

echo "✓ Test configuration validated"
echo ""
echo "Configuration:"
echo "  PRESERVE_BUCKET: ${PRESERVE_BUCKET}"
echo "  UNIQUE_KEY: ${UNIQUE_KEY}"
echo ""

# Check if AWS CLI is available
if ! command -v aws &> /dev/null; then
    echo "✗ TEST FAILED: AWS CLI not found"
    echo "Install: brew install awscli (macOS) or see README.md"
    exit 1
fi

# Step 1: Verify initial state
echo "=== Step 1: Initialize files if needed ==="
if [[ ! -d generated/ ]]; then
    echo "Command: terraform apply -auto-approve"
    terraform apply -auto-approve > /dev/null 2>&1
    echo "✓ Initial files created"
else
    echo "✓ Files already exist"
fi
echo ""

# Step 2: APPLY Stage - Push files to S3
echo "=== Step 2: APPLY Stage - Push files to S3 ==="
echo "Command: ./preserve.sh $UNIQUE_KEY push"
if ./preserve.sh "$UNIQUE_KEY" push > /dev/null 2>&1; then
    echo "✓ Files pushed to S3"
else
    echo "✗ TEST FAILED: Failed to push files to S3"
    exit 1
fi
echo ""

# Step 3: Simulate environment change - Delete files
echo "=== Step 3: Simulate environment change ==="
echo "Command: rm -rf generated/"
rm -rf generated/
if [[ ! -d generated/ ]]; then
    echo "✓ Files deleted (simulating new environment)"
else
    echo "✗ TEST FAILED: Failed to delete files"
    exit 1
fi
echo ""

# Step 4: VERIFY PLAN Stage - Pull files from S3
echo "=== Step 4: VERIFY PLAN Stage - Pull files from S3 ==="
echo "Command: ./preserve.sh $UNIQUE_KEY pull"
if ./preserve.sh "$UNIQUE_KEY" pull > /dev/null 2>&1; then
    echo "✓ Files restored from S3"
else
    echo "✗ TEST FAILED: Failed to pull files from S3"
    exit 1
fi
echo ""

# Step 5: Verify Terraform Plan after restoration (Drift Detection)
echo "=== Step 5: Drift Detection ==="
echo "Command: terraform plan -detailed-exitcode"
DRIFT_DETECTED=0
if terraform plan -detailed-exitcode > /dev/null 2>&1; then
    echo "✓ No drift detected - files match Terraform state"
else
    echo "✗ DRIFT DETECTED: Terraform sees changes after restoration"
    terraform plan -no-color 2>&1 | tail -15
    DRIFT_DETECTED=1
fi
echo ""

echo "=========================================="
echo "Test Complete: Preserve.sh Approach"
echo "=========================================="
echo ""

# Final test result
if [[ $DRIFT_DETECTED -eq 0 ]]; then
    echo "✓ TEST PASSED"
    echo "=========================================="
    echo "Files successfully preserved and restored via S3"
    echo "No drift detected after restoration"
    exit 0
else
    echo "✗ TEST FAILED: Drift Detection"
    echo "=========================================="
    echo "Files were restored but do not match Terraform state"
    exit 1
fi

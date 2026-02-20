#!/bin/bash
# Test script for restore_from_state.sh approach
# Tests recreating files directly from Terraform state
rm generated/example.txt & rm generated/config.json
terraform apply -auto-approve   
set +e  # Don't exit on error - we want to report where it failed

echo "=========================================="
echo "Test: State Restoration Approach"
echo "=========================================="
echo ""

# Step 1: Show current state
echo "=== Step 1: Current Terraform state ==="
echo "Command: terraform state list"
terraform state list
echo ""

# Step 2: Verify files exist
echo "=== Step 2: Initialize files if needed ==="
if [[ -d generated/ ]]; then
    echo "✓ Files exist"
else
    echo "Command: terraform apply -auto-approve"
    terraform apply -auto-approve > /dev/null 2>&1
    echo "✓ Files created"
fi
echo ""

# Step 3: Delete files to simulate problem
echo "=== Step 3: Simulate files deleted (state intact) ==="
echo "Command: rm -rf generated/"
rm -rf generated/
if [[ ! -d generated/ ]]; then
    echo "✓ Files deleted"
else
    echo "✗ TEST FAILED: Failed to delete files"
    exit 1
fi
echo ""



# Step 4: Restore files from state
echo "=== Step 4: Restore files from Terraform state ==="
echo "Command: ./restore_from_state.sh"
if ./restore_from_state.sh > /dev/null 2>&1; then
    echo "✓ Files restored from state"
else
    echo "✗ TEST FAILED: Failed to restore files from state"
    exit 1
fi
echo ""

# Step 5: Verify restored files
echo "=== Step 5: Verify restored files ==="
if [[ -d generated/ && -f generated/example.txt && -f generated/config.json ]]; then
    echo "✓ Files restored successfully"
else
    echo "✗ TEST FAILED: Files not restored"
    exit 1
fi
echo ""

# Step 6: Verify Terraform Plan after restoration (Drift Detection)
echo "=== Step 6: Drift Detection ==="
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
echo "Test Complete: State Restoration"
echo "=========================================="
echo ""

# Final test result
if [[ $DRIFT_DETECTED -eq 0 ]]; then
    echo "✓ TEST PASSED"
    echo "=========================================="
    echo "Files successfully restored from Terraform state"
    echo "No drift detected after restoration"
    exit 0
else
    echo "✗ TEST FAILED: Drift Detection"
    echo "=========================================="
    echo "Files were restored but do not match Terraform state"
    exit 1
fi

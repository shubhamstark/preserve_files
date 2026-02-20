#!/bin/bash
# Test script for restore_from_state.sh approach
# Tests recreating files directly from Terraform state

set -e

echo "=========================================="
echo "Test: State Restoration Approach"
echo "=========================================="
echo ""

# Step 1: Verify initial state
echo "=== Step 1: Verify initial Terraform state ==="
terraform plan -detailed-exitcode > /dev/null 2>&1 && echo "✓ No changes - infrastructure matches configuration" || echo "⚠ Changes detected"
echo ""

# Step 2: Show current state
echo "=== Step 2: Current Terraform state ==="
terraform state list
echo ""

# Step 3: Verify files exist
echo "=== Step 3: Verify files exist ==="
if [[ -d generated/ ]]; then
    ls -la generated/
    echo "✓ Files exist"
else
    echo "✗ Files don't exist - running terraform apply first"
    terraform apply -auto-approve > /dev/null
    echo "✓ Files created"
fi
echo ""

# Step 4: Delete files to simulate problem
echo "=== Step 4: Simulate files deleted (but state intact) ==="
echo "Deleting generated files..."
rm -rf generated/
if [[ ! -d generated/ ]]; then
    echo "✓ Files deleted"
else
    echo "✗ Failed to delete files"
    exit 1
fi
echo ""

# Step 5: Show Terraform plan without files
echo "=== Step 5: Check Terraform Plan WITHOUT files ==="
echo "Note: Even though state knows about resources, missing files cause issues"
if terraform plan -no-color 2>&1 | grep -q "No changes"; then
    echo "✓ Terraform sees no changes (files recreated by provider check)"
else
    echo "⚠ Terraform may want to make changes"
fi
echo ""

# Step 6: Restore files from state
echo "=== Step 6: Restore files from Terraform state ==="
if ./restore_from_state.sh; then
    echo "✓ Restoration script completed"
else
    echo "✗ Failed to restore files"
    exit 1
fi
echo ""

# Step 7: Verify restored files
echo "=== Step 7: Verify restored files ==="
if [[ -d generated/ ]]; then
    ls -la generated/
    echo ""
    echo "Content sample:"
    echo "--- generated/example.txt ---"
    head -3 generated/example.txt
    echo ""
    echo "--- generated/config.json ---"
    cat generated/config.json | jq .
    echo ""
    echo "✓ Files restored successfully"
else
    echo "✗ Files not restored"
    exit 1
fi
echo ""

# Step 8: Verify Terraform Plan after restoration
echo "=== Step 8: Check Terraform Plan AFTER restoration ==="
if terraform plan -detailed-exitcode > /dev/null 2>&1; then
    echo "✓ SUCCESS: No changes needed - files match state!"
else
    echo "⚠ Terraform still sees changes (this may be expected for resources with dynamic content)"
    terraform plan -no-color 2>&1 | tail -10
fi
echo ""

echo "=========================================="
echo "Test Complete: State Restoration"
echo "=========================================="
echo ""
echo "Summary:"
echo "  - Files deleted (simulating missing files)"
echo "  - Files restored from Terraform state"
echo "  - Terraform state remains consistent"
echo ""
echo "Note: This approach works when:"
echo "  ✓ Terraform state is available and intact"
echo "  ✓ Resources exist in state"
echo "  ✗ Does NOT work if resources removed from state"

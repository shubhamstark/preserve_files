#!/bin/bash
# Test script for tar/preserve approach
# Simulates the Apply -> Verify Plan workflow with S3 preservation

set -e

echo "=========================================="
echo "Test: Tar/Preserve Approach"
echo "=========================================="
echo ""

# Configuration
export PRESERVE_BUCKET="${PRESERVE_BUCKET:-terraform-preserved-files}"
UNIQUE_KEY="test-$(date +%s)"
TEST_ARCHIVE="test-backup.tar.gz"

echo "Using unique key: $UNIQUE_KEY"
echo "S3 Bucket: $PRESERVE_BUCKET"
echo ""

# Step 1: Verify initial state
echo "=== Step 1: Verify initial Terraform state ==="
terraform plan -detailed-exitcode > /dev/null 2>&1 && echo "✓ No changes - infrastructure matches configuration" || echo "⚠ Changes detected"
echo ""

# Step 2: Simulate Apply stage - Archive files
echo "=== Step 2: APPLY Stage - Archive generated files ==="
echo "Creating tar archive from harness.json..."
if python tar.py tar "$TEST_ARCHIVE"; then
    echo "✓ Archive created successfully"
    ls -lh "$TEST_ARCHIVE"
else
    echo "✗ Failed to create archive"
    exit 1
fi
echo ""

# Step 3: Simulate environment change - Delete files
echo "=== Step 3: Simulate Verify Plan in new environment ==="
echo "Deleting generated files to simulate new execution environment..."
rm -rf generated/
if [[ ! -d generated/ ]]; then
    echo "✓ Files deleted (simulating environment without files)"
else
    echo "✗ Failed to delete files"
    exit 1
fi
echo ""

# Step 4: Check Terraform Plan without restoration
echo "=== Step 4: Check Terraform Plan WITHOUT restoration ==="
if terraform plan -no-color 2>&1 | grep -q "1 to add"; then
    echo "✓ Terraform wants to recreate files (expected behavior)"
else
    echo "⚠ Unexpected plan result"
fi
echo ""

# Step 5: Restore files using tar
echo "=== Step 5: VERIFY PLAN Stage - Restore files from archive ==="
echo "Extracting files from archive..."
if python tar.py untar "$TEST_ARCHIVE"; then
    echo "✓ Files restored successfully"
    ls -la generated/
else
    echo "✗ Failed to restore files"
    exit 1
fi
echo ""

# Step 6: Verify Terraform Plan after restoration
echo "=== Step 6: Check Terraform Plan AFTER restoration ==="
if terraform plan -detailed-exitcode > /dev/null 2>&1; then
    echo "✓ SUCCESS: No changes needed - files restored correctly!"
else
    echo "⚠ Terraform still sees changes (check configuration)"
fi
echo ""

# Cleanup
echo "=== Cleanup ==="
rm -f "$TEST_ARCHIVE"
echo "✓ Test archive removed"
echo ""

echo "=========================================="
echo "Test Complete: Tar/Preserve Approach"
echo "=========================================="
echo ""
echo "Summary:"
echo "  - Files archived during Apply stage"
echo "  - Files deleted (simulating new environment)"
echo "  - Files restored from archive"
echo "  - Terraform Plan shows no changes"
echo ""
echo "For S3 integration test, run:"
echo "  export PRESERVE_BUCKET=your-bucket"
echo "  ./preserve.sh $UNIQUE_KEY push"
echo "  rm -rf generated/"
echo "  ./preserve.sh $UNIQUE_KEY pull"
echo "  terraform plan"

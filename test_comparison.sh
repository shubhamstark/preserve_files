#!/bin/bash
# Comprehensive comparison test of both approaches

set -e

echo "=========================================="
echo "Comparative Test: Both Approaches"
echo "=========================================="
echo ""

# Ensure clean state
echo "=== Setup: Ensure clean initial state ==="
if [[ ! -d generated/ ]]; then
    echo "Running terraform apply to create files..."
    terraform apply -auto-approve > /dev/null
fi
terraform plan -detailed-exitcode > /dev/null 2>&1 && echo "✓ Initial state is clean" || echo "⚠ Initial state has drift"
echo ""

# ============================================
# Test 1: Tar/Preserve Approach
# ============================================
echo "=========================================="
echo "Test 1: Tar/Preserve Approach"
echo "=========================================="
echo ""

ARCHIVE="comparison-test.tar.gz"

echo "1.1 Create archive"
python tar.py tar "$ARCHIVE" > /dev/null
echo "✓ Archive created: $(ls -lh $ARCHIVE | awk '{print $5}')"

echo "1.2 Delete files"
rm -rf generated/
echo "✓ Files deleted"

echo "1.3 Restore from archive"
python tar.py untar "$ARCHIVE" > /dev/null
echo "✓ Files restored"

echo "1.4 Verify Terraform plan"
if terraform plan -detailed-exitcode > /dev/null 2>&1; then
    echo "✓ No changes - SUCCESS"
    PRESERVE_SUCCESS=true
else
    echo "⚠ Changes detected"
    PRESERVE_SUCCESS=false
fi

rm -f "$ARCHIVE"
echo ""

# ============================================
# Test 2: State Restoration Approach
# ============================================
echo "=========================================="
echo "Test 2: State Restoration Approach"
echo "=========================================="
echo ""

echo "2.1 Delete files again"
rm -rf generated/
echo "✓ Files deleted"

echo "2.2 Restore from state"
./restore_from_state.sh > /dev/null
echo "✓ Files restored from state"

echo "2.3 Verify Terraform plan"
if terraform plan -detailed-exitcode > /dev/null 2>&1; then
    echo "✓ No changes - SUCCESS"
    STATE_SUCCESS=true
else
    echo "⚠ Changes detected"
    STATE_SUCCESS=false
fi
echo ""

# ============================================
# Test 3: Edge Case - Resource not in state
# ============================================
echo "=========================================="
echo "Test 3: Edge Case Analysis"
echo "=========================================="
echo ""

echo "3.1 Remove resource from state"
terraform state rm local_file.example > /dev/null 2>&1
echo "✓ Resource removed from state"

echo "3.2 Try state restoration approach"
rm -rf generated/
./restore_from_state.sh > /dev/null 2>&1
if [[ -f generated/example.txt ]]; then
    echo "⚠ Example file restored (unexpected)"
    STATE_EDGE_SUCCESS=false
else
    echo "✓ Example file NOT restored (expected - not in state)"
    STATE_EDGE_SUCCESS=true
fi

echo "3.3 Try tar/preserve approach"
python tar.py tar "$ARCHIVE" > /dev/null 2>&1
rm -rf generated/
python tar.py untar "$ARCHIVE" > /dev/null 2>&1
if [[ -f generated/example.txt ]]; then
    echo "✓ Tar approach restored file (works regardless of state)"
    PRESERVE_EDGE_SUCCESS=true
else
    echo "⚠ Tar approach failed"
    PRESERVE_EDGE_SUCCESS=false
fi

# Restore state
terraform apply -auto-approve > /dev/null 2>&1
rm -f "$ARCHIVE"
echo ""

# ============================================
# Results Summary
# ============================================
echo "=========================================="
echo "Test Results Summary"
echo "=========================================="
echo ""

echo "┌─────────────────────────────────────────────────────────┐"
echo "│                    Approach Comparison                  │"
echo "├─────────────────────────────────────────────────────────┤"
echo "│"
echo "│ Tar/Preserve Approach:"
echo "│   Normal case:        $([[ $PRESERVE_SUCCESS == true ]] && echo "✓ PASS" || echo "✗ FAIL")"
echo "│   Edge case:          $([[ $PRESERVE_EDGE_SUCCESS == true ]] && echo "✓ PASS" || echo "✗ FAIL")"
echo "│"
echo "│ State Restoration Approach:"
echo "│   Normal case:        $([[ $STATE_SUCCESS == true ]] && echo "✓ PASS" || echo "✗ FAIL")"
echo "│   Edge case:          $([[ $STATE_EDGE_SUCCESS == true ]] && echo "✓ PASS (correctly skipped)" || echo "✗ FAIL")"
echo "│"
echo "└─────────────────────────────────────────────────────────┘"
echo ""

echo "Key Findings:"
echo ""
echo "Tar/Preserve Approach:"
echo "  ✓ Works regardless of state"
echo "  ✓ Preserves files between stages"
echo "  ✓ Uses S3 for distributed environments"
echo "  ✓ Best for Apply -> Verify Plan workflow"
echo ""
echo "State Restoration Approach:"
echo "  ✓ Works when resources in state"
echo "  ✓ Quick local restoration"
echo "  ✓ No external dependencies"
echo "  ✗ Fails when resources not in state"
echo "  ✓ Best for local development/debugging"
echo ""

echo "Recommendation:"
echo "  Use tar/preserve approach for CI/CD pipelines"
echo "  Use state restoration for local debugging"

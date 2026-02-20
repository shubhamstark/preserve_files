# Test Scripts

This directory contains test scripts to validate both file preservation approaches.

## Test Scripts

### 1. test_demo.sh ⭐ (Recommended)
Quick demonstration showing both approaches working.

```bash
./test_demo.sh
```

**What it does:**
- Shows state restoration approach
- Shows tar/preserve approach
- Verifies files are restored correctly
- Pretty formatted output

**Best for:** Quick validation and demonstrations

---

### 2. test_state_approach.sh
Comprehensive test of the state restoration method.

```bash
./test_state_approach.sh
```

**Tests:**
- Initial state verification
- File deletion simulation
- Restoration from Terraform state
- Terraform plan validation

**Best for:** Testing restore_from_state.sh functionality

---

### 3. test_preserve_approach.sh
Comprehensive test of the tar/preserve method.

```bash
./test_preserve_approach.sh
```

**Tests:**
- Archive creation
- File deletion simulation
- Restoration from archive
- Terraform plan validation
- S3 integration instructions

**Best for:** Testing tar.py/preserve.py functionality

---

### 4. test_comparison.sh
Side-by-side comparison of both approaches with edge cases.

```bash
./test_comparison.sh
```

**Tests:**
- Both approaches in normal scenarios
- Edge case: Resource not in state
- Comprehensive results comparison

**Best for:** Understanding differences and limitations

---

## Quick Start

Run all tests:
```bash
# Quick demo (recommended first)
./test_demo.sh

# Individual approach tests
./test_state_approach.sh
./test_preserve_approach.sh

# Full comparison
./test_comparison.sh
```

## Prerequisites

- Terraform initialized and applied
- Python 3.x
- jq installed (`brew install jq` on macOS)
- AWS CLI (for S3 tests)

## Understanding the Results

### State Restoration Approach
✅ **Works when:**
- Resources exist in Terraform state
- State file is accessible
- Quick local restoration needed

❌ **Doesn't work when:**
- Resources removed from state
- No state file available

### Tar/Preserve Approach
✅ **Works when:**
- Files listed in harness.json
- With or without state
- Distributed environments (via S3)

The tar/preserve approach is the recommended solution for CI/CD pipelines where files need to persist between Apply and Verify Plan stages.

## Test Output

Each test provides:
- ✓ Success indicators
- ⚠ Warnings for expected behavior
- ✗ Failure indicators for unexpected issues
- Summary of results

## Cleanup

Tests automatically clean up temporary files. If needed:
```bash
rm -f *.tar.gz
terraform apply -auto-approve  # Restore clean state
```

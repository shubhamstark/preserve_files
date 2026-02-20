# Running Tests

## Prerequisites

1. **AWS CLI** must be installed:
   ```bash
   brew install awscli  # macOS
   ```

2. **Set PRESERVE_BUCKET environment variable**:
   ```bash
   export PRESERVE_BUCKET=your-s3-bucket-name
   ```

## Test Commands

### Test 1: S3 Preserve Approach
Tests the preserve.sh script with S3 integration (Apply → Push → Delete → Pull → Verify)

```bash
export PRESERVE_BUCKET=your-s3-bucket-name
./test_preserve_approach.sh
```

**Expected Output:**
- ✓ TEST PASSED (if no drift detected)
- ✗ TEST FAILED (if drift detected or any step fails)

---

### Test 2: State Restoration Approach
Tests the restore_from_state.sh script (Delete → Restore from State → Verify)

```bash
./test_state_approach.sh
```

**Expected Output:**
- ✓ TEST PASSED (if no drift detected)
- ✗ TEST FAILED (if drift detected or any step fails)

---

## What Tests Verify

Both tests check for **drift detection**:
- Files are deleted/modified to simulate problems
- Files are restored using different approaches
- `terraform plan` verifies no changes are needed
- Test PASSES only if Terraform sees no drift

## Exit Codes

- `0` - Test passed (no drift)
- `1` - Test failed (drift detected or execution error)

## Example Test Session

```bash
# Set your S3 bucket
export PRESERVE_BUCKET=my-terraform-state-bucket

# Run S3 preserve test
./test_preserve_approach.sh
# Output: ✓ TEST PASSED

# Run state restoration test
./test_state_approach.sh
# Output: ✓ TEST PASSED
```

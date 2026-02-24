#!/bin/bash
# Test script for get_preserving_file_name.sh

# Note: Don't use 'set -e' in test scripts so we can report all failures
set +e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

test_passed=0
test_failed=0

# Test result tracking
print_pass() {
    echo -e "${GREEN}✓${NC} $1"
    ((test_passed++))
}

print_fail() {
    echo -e "${RED}✗${NC} $1"
    ((test_failed++))
}

print_info() {
    echo -e "${YELLOW}ℹ${NC} $1"
}

# Cleanup function
cleanup_test_env() {
    rm -rf test_temp 2>/dev/null || true
}

trap cleanup_test_env EXIT

echo ""
echo "=========================================="
echo "Testing get_preserving_file_name.sh"
echo "=========================================="
echo ""

# Create test environment
echo "=== Setting up test environment ==="
mkdir -p test_temp
cd test_temp

# Test 1: No harness.json, no terraform state
echo ""
echo "=== Test 1: No files (empty environment) ==="
../get_preserving_file_name.sh list > output.txt 2>&1
if grep -q "No files to preserve" output.txt; then
    print_pass "Handles empty environment correctly"
else
    print_fail "Should report no files in empty environment"
    cat output.txt
fi

# Test 2: Only harness.json files
echo ""
echo "=== Test 2: Files from harness.json only ==="
cat > harness.json <<'EOF'
{
    "preserved_files": [
        "generated/config.json",
        "generated/example.txt",
        "output/data.yaml"
    ]
}
EOF

mkdir -p generated output
echo '{"key": "value"}' > generated/config.json
echo "example content" > generated/example.txt
echo "data: test" > output/data.yaml

../get_preserving_file_name.sh list > output.txt 2>&1
if grep -q "generated/config.json" output.txt && \
   grep -q "generated/example.txt" output.txt && \
   grep -q "output/data.yaml" output.txt; then
    print_pass "Reads files from harness.json"
else
    print_fail "Failed to read files from harness.json"
    cat output.txt
fi

if grep -q "Found 3 file(s) from harness.json" output.txt; then
    print_pass "Reports correct count from harness.json"
else
    print_fail "Incorrect count from harness.json"
fi

# Test 3: Only terraform state files
echo ""
echo "=== Test 3: Files from terraform state only ==="
rm -f harness.json

# Create a mock terraform state
mkdir -p .terraform
cat > terraform.tfstate <<'EOF'
{
  "version": 4,
  "terraform_version": "1.0.0",
  "resources": [
    {
      "mode": "managed",
      "type": "local_file",
      "name": "state_file1",
      "instances": [
        {
          "attributes": {
            "filename": "generated/state_output.txt",
            "content": "state content"
          }
        }
      ]
    },
    {
      "mode": "managed",
      "type": "local_file",
      "name": "state_file2",
      "instances": [
        {
          "attributes": {
            "filename": "terraform/modules.json"
          }
        }
      ]
    },
    {
      "mode": "managed",
      "type": "aws_instance",
      "name": "server",
      "instances": [
        {
          "attributes": {
            "id": "i-12345"
          }
        }
      ]
    }
  ]
}
EOF

# Mock terraform command to return our state
cat > mock_terraform.sh <<'EOF'
#!/bin/bash
if [[ "$1" == "state" && "$2" == "pull" ]]; then
    cat terraform.tfstate
    exit 0
fi
exit 1
EOF
chmod +x mock_terraform.sh

TERRAFORM="./mock_terraform.sh" ../get_preserving_file_name.sh list > output.txt 2>&1

if grep -q "generated/state_output.txt" output.txt && \
   grep -q "terraform/modules.json" output.txt; then
    print_pass "Reads files from terraform state"
else
    print_fail "Failed to read files from terraform state"
    cat output.txt
fi

if grep -q "Found 2 file(s) from terraform state" output.txt; then
    print_pass "Reports correct count from terraform state"
else
    print_fail "Incorrect count from terraform state"
fi

if ! grep -q "aws_instance" output.txt; then
    print_pass "Filters out non-local_file resources"
else
    print_fail "Should not include non-local_file resources"
fi

# Test 4: Both sources with duplicates
echo ""
echo "=== Test 4: Combined sources with duplicates ==="
cat > harness.json <<'EOF'
{
    "preserved_files": [
        "generated/config.json",
        "generated/state_output.txt",
        "shared/common.txt"
    ]
}
EOF

mkdir -p generated shared
echo '{"key": "value"}' > generated/config.json
echo "state output" > generated/state_output.txt
echo "common content" > shared/common.txt

TERRAFORM="./mock_terraform.sh" ../get_preserving_file_name.sh list > output.txt 2>&1

if grep -q "generated/state_output.txt" output.txt; then
    print_pass "Includes files from both sources"
else
    print_fail "Failed to combine files from both sources"
fi

# Count unique files (should be 4: config.json, state_output.txt, modules.json, common.txt)
unique_count=$(grep -E "^(generated|terraform|shared)/" output.txt | sort -u | wc -l | tr -d ' ')
if [[ "$unique_count" -eq 4 ]]; then
    print_pass "Correctly deduplicates files (found $unique_count unique files)"
else
    print_fail "Deduplication failed (expected 4, got $unique_count)"
    grep "=== Files to preserve ===" output.txt -A 10
fi

if grep -q "Duplicates removed: 1" output.txt; then
    print_pass "Reports duplicate removal"
else
    print_fail "Should report duplicate removal"
fi

# Test 5: Unsafe paths (containing ..)
echo ""
echo "=== Test 5: Unsafe paths are filtered ==="
cat > harness.json <<'EOF'
{
    "preserved_files": [
        "safe/file.txt",
        "../etc/passwd",
        "another/../unsafe.txt"
    ]
}
EOF

mkdir -p safe
echo "safe content" > safe/file.txt

../get_preserving_file_name.sh list > output.txt 2>&1

if grep -q "safe/file.txt" output.txt && \
   ! grep -q "passwd" output.txt && \
   ! grep -q '\.\\./' output.txt; then
    print_pass "Filters out unsafe paths"
else
    print_fail "Should filter paths containing .."
    cat output.txt
fi

# Test 6: Empty preserved_files array
echo ""
echo "=== Test 6: Empty preserved_files in harness.json ==="
cat > harness.json <<'EOF'
{
    "preserved_files": []
}
EOF

rm -f terraform.tfstate
../get_preserving_file_name.sh list > output.txt 2>&1

if grep -q "Found 0 file(s) from harness.json" output.txt; then
    print_pass "Handles empty preserved_files array"
else
    print_fail "Should handle empty array gracefully"
fi

# Test 7: Help command
echo ""
echo "=== Test 7: Help command ==="
../get_preserving_file_name.sh --help > output.txt 2>&1
if grep -q "Usage:" output.txt && grep -q "Commands:" output.txt; then
    print_pass "Shows help message"
else
    print_fail "Help command should display usage"
fi

# Test 8: Function can be sourced
echo ""
echo "=== Test 8: Script can be sourced ==="
cat > test_source.sh <<'EOF'
#!/bin/bash
source ../get_preserving_file_name.sh
if declare -f get_preserving_file_names > /dev/null; then
    echo "SUCCESS: Function available"
    exit 0
else
    echo "FAIL: Function not available"
    exit 1
fi
EOF
chmod +x test_source.sh

if ./test_source.sh > output.txt 2>&1; then
    print_pass "Can be sourced for function use"
else
    print_fail "Should be sourceable"
    cat output.txt
fi

# Summary
echo ""
echo "=========================================="
echo "Test Summary"
echo "=========================================="
echo -e "Passed: ${GREEN}${test_passed}${NC}"
echo -e "Failed: ${RED}${test_failed}${NC}"
echo ""

if [[ $test_failed -eq 0 ]]; then
    echo -e "${GREEN}✓ ALL TESTS PASSED${NC}"
    echo "=========================================="
    exit 0
else
    echo -e "${RED}✗ SOME TESTS FAILED${NC}"
    echo "=========================================="
    exit 1
fi

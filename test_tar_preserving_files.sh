#!/bin/bash
# Test script for tar_preserving_files.sh

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
    cd /Users/shubhamkaushal/preserve_files 2>/dev/null || cd ..
    rm -rf test_tar_temp 2>/dev/null || true
}

trap cleanup_test_env EXIT

echo ""
echo "=========================================="
echo "Testing tar_preserving_files.sh"
echo "=========================================="
echo ""

# Create test environment
echo "=== Setting up test environment ==="
mkdir -p test_tar_temp
cd test_tar_temp

# Source the script to access functions (disable set -e temporarily)
set +e
source ../tar_preserving_files.sh
set +e  # Re-disable since sourcing might enable it

# Test 1: tar_files_from_list with simple file list
echo ""
echo "=== Test 1: tar_files_from_list with valid files ==="
mkdir -p testfiles
echo "content1" > testfiles/file1.txt
echo "content2" > testfiles/file2.txt
echo "content3" > testfiles/file3.txt

file_list="testfiles/file1.txt
testfiles/file2.txt
testfiles/file3.txt"

if tar_files_from_list "$file_list" "test1.tar.gz" > output.txt 2>&1; then
    if [[ -f "test1.tar.gz" ]]; then
        print_pass "Creates tar archive successfully"
    else
        print_fail "Archive file not created"
    fi
else
    print_fail "tar_files_from_list failed"
    cat output.txt
fi

if tar -tzf test1.tar.gz | grep -q "testfiles/file1.txt"; then
    print_pass "Archive contains expected files"
else
    print_fail "Archive missing expected files"
fi

# Test 2: tar_files_from_list with missing files
echo ""
echo "=== Test 2: tar_files_from_list with missing files ==="
file_list_mixed="testfiles/file1.txt
testfiles/missing.txt
testfiles/file2.txt"

if tar_files_from_list "$file_list_mixed" "test2.tar.gz" > output.txt 2>&1; then
    if grep -q "Missing.*missing.txt" output.txt; then
        print_pass "Reports missing files"
    else
        print_fail "Should report missing files"
    fi
    
    if [[ -f "test2.tar.gz" ]]; then
        count=$(tar -tzf test2.tar.gz | wc -l | tr -d ' ')
        if [[ "$count" -eq 2 ]]; then
            print_pass "Creates archive with existing files only"
        else
            print_fail "Archive should contain 2 files, got $count"
        fi
    else
        print_fail "Archive not created"
    fi
else
    print_fail "tar_files_from_list should succeed even with missing files"
fi

# Test 3: tar_files_from_list with empty list
echo ""
echo "=== Test 3: tar_files_from_list with empty list ==="
if tar_files_from_list "" "test3.tar.gz" > output.txt 2>&1; then
    if [[ -f "test3.tar.gz" ]]; then
        print_pass "Creates empty archive for empty list"
    else
        print_fail "Should create empty archive"
    fi
    
    if grep -q "No files provided" output.txt; then
        print_pass "Reports empty file list"
    else
        print_fail "Should report empty file list"
    fi
else
    print_fail "Should handle empty list gracefully"
fi

# Test 4: tar_files_from_list without tar extension
echo ""
echo "=== Test 4: tar_files_from_list without compression extension ==="
file_list="testfiles/file1.txt"

if tar_files_from_list "$file_list" "test4" > output.txt 2>&1; then
    if [[ -f "test4.tar.gz" ]]; then
        print_pass "Adds .tar.gz extension automatically"
    else
        print_fail "Should add .tar.gz extension"
        ls -la test4*
    fi
else
    print_fail "Should handle missing extension"
    cat output.txt
fi

# Test 5: tar_files_from_list with .tar extension (no compression)
echo ""
echo "=== Test 5: tar_files_from_list with .tar (no compression) ==="
file_list="testfiles/file1.txt"

if tar_files_from_list "$file_list" "test5.tar" > output.txt 2>&1; then
    if [[ -f "test5.tar" ]]; then
        print_pass "Creates uncompressed tar"
    else
        print_fail "Should create .tar file"
    fi
    
    # Verify it's not compressed
    if file test5.tar | grep -q "tar archive"; then
        print_pass "Archive is uncompressed tar format"
    else
        print_fail "Should be uncompressed tar"
    fi
else
    print_fail "Should create uncompressed tar"
fi

# Test 6: list_tar_contents
echo ""
echo "=== Test 6: list_tar_contents ==="
if list_tar_contents "test1.tar.gz" > output.txt 2>&1; then
    print_pass "Lists tar contents successfully"
    
    if grep -q "testfiles/file1.txt" output.txt && \
       grep -q "Total files in archive: 3" output.txt; then
        print_pass "Shows correct file list and count"
    else
        print_fail "Should show all files and count"
        cat output.txt
    fi
else
    print_fail "Should list tar contents"
fi

# Test 7: list_tar_contents with missing file
echo ""
echo "=== Test 7: list_tar_contents with missing archive ==="
if list_tar_contents "nonexistent.tar.gz" > output.txt 2>&1; then
    print_fail "Should fail for missing archive"
else
    if grep -q "Archive not found" output.txt; then
        print_pass "Reports missing archive error"
    else
        print_fail "Should report missing archive"
    fi
fi

# Test 8: get_preserving_tar integration test
echo ""
echo "=== Test 8: get_preserving_tar integration ==="

# Create harness.json
cat > harness.json <<'EOF'
{
    "preserved_files": [
        "generated/config.json",
        "generated/output.txt"
    ]
}
EOF

# Create terraform state with local_file
cat > terraform.tfstate <<'EOF'
{
  "version": 4,
  "terraform_version": "1.0.0",
  "resources": [
    {
      "mode": "managed",
      "type": "local_file",
      "name": "test",
      "instances": [
        {
          "attributes": {
            "filename": "generated/state_file.txt"
          }
        }
      ]
    }
  ]
}
EOF

# Create mock terraform
cat > mock_terraform.sh <<'EOF'
#!/bin/bash
if [[ "$1" == "state" && "$2" == "pull" ]]; then
    cat terraform.tfstate
    exit 0
fi
exit 1
EOF
chmod +x mock_terraform.sh

# Create the actual files
mkdir -p generated
echo '{"test": "data"}' > generated/config.json
echo "output data" > generated/output.txt
echo "state data" > generated/state_file.txt

# Run get_preserving_tar
if TERRAFORM="./mock_terraform.sh" get_preserving_tar "preserve_test.tar.gz" > output.txt 2>&1; then
    print_pass "get_preserving_tar completes successfully"
    
    if [[ -f "preserve_test.tar.gz" ]]; then
        print_pass "Creates preserving archive"
    else
        print_fail "Should create preserve_test.tar.gz"
    fi
    
    # Check archive contents
    archive_files=$(tar -tzf preserve_test.tar.gz)
    
    if echo "$archive_files" | grep -q "generated/config.json" && \
       echo "$archive_files" | grep -q "generated/output.txt"; then
        print_pass "Archive contains harness.json files"
    else
        print_fail "Should contain files from harness.json"
        echo "$archive_files"
    fi
    
    if echo "$archive_files" | grep -q "generated/state_file.txt"; then
        print_pass "Archive contains terraform state files"
    else
        print_fail "Should contain files from terraform state"
        echo "$archive_files"
    fi
    
    # Verify no duplicates (should have 3 files: config.json, output.txt, state_file.txt)
    file_count=$(echo "$archive_files" | wc -l | tr -d ' ')
    if [[ "$file_count" -eq 3 ]]; then
        print_pass "Archive has correct number of unique files"
    else
        print_fail "Expected 3 files, got $file_count"
        echo "$archive_files"
    fi
else
    print_fail "get_preserving_tar should succeed"
    cat output.txt
fi

# Test 9: get_preserving_tar with no files
echo ""
echo "=== Test 9: get_preserving_tar with no files to preserve ==="
rm -f harness.json terraform.tfstate

if get_preserving_tar "empty_preserve.tar.gz" > output.txt 2>&1; then
    print_pass "Handles no files gracefully"
    
    if [[ -f "empty_preserve.tar.gz" ]]; then
        print_pass "Creates empty archive"
    else
        print_fail "Should create empty archive"
    fi
    
    if grep -q "No files to preserve" output.txt; then
        print_pass "Reports no files to preserve"
    else
        print_fail "Should report no files"
    fi
else
    print_fail "Should handle empty case gracefully"
fi

# Test 10: tar_files_from_list with subdirectories
echo ""
echo "=== Test 10: tar_files_from_list preserves directory structure ==="
mkdir -p deep/nested/dir
echo "deep content" > deep/nested/dir/file.txt

file_list="deep/nested/dir/file.txt
testfiles/file1.txt"

if tar_files_from_list "$file_list" "test10.tar.gz" > output.txt 2>&1; then
    contents=$(tar -tzf test10.tar.gz)
    
    if echo "$contents" | grep -q "deep/nested/dir/file.txt"; then
        print_pass "Preserves directory structure in archive"
    else
        print_fail "Should preserve full directory paths"
        echo "$contents"
    fi
else
    print_fail "Should handle nested directories"
fi

# Test 11: Script execution via command line (tar command)
echo ""
echo "=== Test 11: Script CLI - tar command ==="
file_list="testfiles/file1.txt testfiles/file2.txt"
if ../tar_preserving_files.sh tar "$file_list" "cli_test.tar.gz" > output.txt 2>&1; then
    if [[ -f "cli_test.tar.gz" ]]; then
        print_pass "CLI tar command works"
    else
        print_fail "CLI should create archive"
    fi
else
    print_fail "CLI tar command should succeed"
    cat output.txt
fi

# Test 12: Script execution via command line (preserve command)
echo ""
echo "=== Test 12: Script CLI - preserve command ==="

# Recreate test environment
cat > harness.json <<'EOF'
{
    "preserved_files": [
        "testfiles/file1.txt"
    ]
}
EOF

if ../tar_preserving_files.sh preserve "cli_preserve.tar.gz" > output.txt 2>&1; then
    if [[ -f "cli_preserve.tar.gz" ]]; then
        print_pass "CLI preserve command works"
    else
        print_fail "CLI should create preserve archive"
    fi
else
    print_fail "CLI preserve command should succeed"
    cat output.txt
fi

# Test 13: Script execution via command line (list command)
echo ""
echo "=== Test 13: Script CLI - list command ==="
if ../tar_preserving_files.sh list "test1.tar.gz" > output.txt 2>&1; then
    if grep -q "testfiles/file1.txt" output.txt; then
        print_pass "CLI list command works"
    else
        print_fail "CLI should list archive contents"
    fi
else
    print_fail "CLI list command should succeed"
fi

# Test 14: Help command
echo ""
echo "=== Test 14: Help command ==="
if ../tar_preserving_files.sh --help > output.txt 2>&1; then
    if grep -q "Usage:" output.txt && \
       grep -q "Commands:" output.txt && \
       grep -q "preserve" output.txt; then
        print_pass "Shows help message"
    else
        print_fail "Help should show usage and commands"
    fi
else
    print_fail "Help command should succeed"
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

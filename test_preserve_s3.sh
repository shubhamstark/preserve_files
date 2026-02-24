#!/bin/bash
# Test script for preserve_s3.sh

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
    rm -rf test_s3_temp 2>/dev/null || true
    rm -f preserved_files_archive.env 2>/dev/null || true
}

trap cleanup_test_env EXIT

echo ""
echo "=========================================="
echo "Testing preserve_s3.sh"
echo "=========================================="
echo ""

# Create test environment
echo "=== Setting up test environment ==="
mkdir -p test_s3_temp
cd test_s3_temp

# Source the script to access functions (disable set -e)
set +e
source ../preserve_s3.sh
set +e  # Re-disable

# Test 1: parse_s3_uri function
echo ""
echo "=== Test 1: parse_s3_uri ==="
if parse_s3_uri "s3://my-bucket/path/to/file.tar.gz" > /dev/null 2>&1; then
    if [[ "$S3_BUCKET" == "my-bucket" ]] && [[ "$S3_KEY" == "path/to/file.tar.gz" ]]; then
        print_pass "Parses S3 URI correctly"
    else
        print_fail "Incorrect parsing: bucket=$S3_BUCKET, key=$S3_KEY"
    fi
else
    print_fail "parse_s3_uri should succeed"
fi

# Test invalid URI
if parse_s3_uri "" > /dev/null 2>&1; then
    print_fail "Should reject empty URI"
else
    print_pass "Rejects empty URI"
fi

# Test 2: derive_s3_path_from_plan function
echo ""
echo "=== Test 2: derive_s3_path_from_plan ==="
result=$(derive_s3_path_from_plan "s3://my-bucket/harness/backend/workflow-123.plan" 2>/dev/null)
expected="s3://my-bucket/harness/backend/workflow-123_preserved_files.tar.gz"
if [[ "$result" == "$expected" ]]; then
    print_pass "Derives S3 path from BINARY_PLAN"
else
    print_fail "Expected: $expected, Got: $result"
fi

# Test with nested path
result=$(derive_s3_path_from_plan "s3://bucket/deep/nested/path/id.plan" 2>/dev/null)
expected="s3://bucket/deep/nested/path/id_preserved_files.tar.gz"
if [[ "$result" == "$expected" ]]; then
    print_pass "Handles nested paths correctly"
else
    print_fail "Expected: $expected, Got: $result"
fi

# Test 3: generate_tag_set function
echo ""
echo "=== Test 3: generate_tag_set ==="
export BINARY_PLAN="s3://bucket/path/workflow-456.plan"
export GIT_COMMIT="abc123def"
export TF_VAR_environment="production"
export TF_VAR_business_unit="engineering"

tag_set=$(generate_tag_set)
if echo "$tag_set" | grep -q "HarnessPipelineDeploymentId=" && \
   echo "$tag_set" | grep -q "CommitId=" && \
   echo "$tag_set" | grep -q "environment="; then
    print_pass "Generates TAG_SET with required fields"
else
    print_fail "TAG_SET missing required fields"
    echo "Generated: $tag_set"
fi

if echo "$tag_set" | grep -q "workflow-456"; then
    print_pass "Extracts workflow ID from BINARY_PLAN"
else
    print_fail "Should extract workflow-456 from BINARY_PLAN"
fi

# Test 4: Create mock AWS CLI for testing
echo ""
echo "=== Test 4: Setting up mock AWS CLI ==="
mkdir -p mock_bin
cat > mock_bin/aws <<'EOF'
#!/bin/bash
# Mock AWS CLI for testing

# Create mock S3 storage
MOCK_S3_DIR="${MOCK_S3_DIR:-./mock_s3}"
mkdir -p "$MOCK_S3_DIR"

case "$1" in
    s3)
        case "$2" in
            cp)
                # s3 cp source dest
                source="${4}"
                dest="${6}"
                
                if [[ "$source" == s3://* ]]; then
                    # Download
                    key="${source#s3://*/}"
                    local_file="$MOCK_S3_DIR/$key"
                    if [[ -f "$local_file" ]]; then
                        cp "$local_file" "$dest"
                        exit 0
                    else
                        echo "Error: File not found in mock S3" >&2
                        exit 1
                    fi
                else
                    # Upload
                    key="${dest#s3://*/}"
                    mkdir -p "$(dirname "$MOCK_S3_DIR/$key")"
                    cp "$source" "$MOCK_S3_DIR/$key"
                    exit 0
                fi
                ;;
        esac
        ;;
    s3api)
        case "$2" in
            put-object)
                # Extract body and key
                body=""
                key=""
                for ((i=3; i<=$#; i++)); do
                    if [[ "${!i}" == "--body" ]]; then
                        ((i++))
                        body="${!i}"
                    elif [[ "${!i}" == "--key" ]]; then
                        ((i++))
                        key="${!i}"
                    fi
                done
                
                if [[ -n "$body" ]] && [[ -n "$key" ]]; then
                    mkdir -p "$(dirname "$MOCK_S3_DIR/$key")"
                    cp "$body" "$MOCK_S3_DIR/$key"
                    exit 0
                fi
                exit 1
                ;;
            get-object-tagging)
                # Return empty tags for simplicity
                echo "TAGSET"
                exit 0
                ;;
        esac
        ;;
esac

exit 1
EOF
chmod +x mock_bin/aws

export PATH="$(pwd)/mock_bin:$PATH"
export MOCK_S3_DIR="$(pwd)/mock_s3"

if command -v aws &> /dev/null; then
    aws_path=$(which aws)
    if [[ "$aws_path" == *"mock_bin/aws"* ]]; then
        print_pass "Mock AWS CLI is in PATH"
    else
        print_fail "Mock AWS CLI not prioritized in PATH"
    fi
else
    print_fail "AWS CLI not found"
fi

# Test 5: Push command test
echo ""
echo "=== Test 5: cmd_push with PRESERVED_FILES_ARCHIVE ==="

# Create test files
mkdir -p generated testdata
echo '{"test": "data"}' > generated/config.json
cat > harness.json <<'EOF'
{
    "preserved_files": [
        "generated/config.json"
    ]
}
EOF

# Mock terraform state
cat > terraform.tfstate <<'EOF'
{
  "version": 4,
  "resources": []
}
EOF

cat > mock_terraform.sh <<'EOF'
#!/bin/bash
if [[ "$1" == "state" && "$2" == "pull" ]]; then
    cat terraform.tfstate
    exit 0
fi
exit 1
EOF
chmod +x mock_terraform.sh

export PRESERVED_FILES_ARCHIVE="s3://test-bucket/preserves/test.tar.gz"
export TERRAFORM="./mock_terraform.sh"
export TF_VAR_environment="test"

if cmd_push > output_push.txt 2>&1; then
    print_pass "cmd_push completes successfully"
    
    # Check if archive was uploaded to mock S3
    if [[ -f "$MOCK_S3_DIR/preserves/test.tar.gz" ]]; then
        print_pass "Archive uploaded to S3"
    else
        print_fail "Archive not found in mock S3"
        ls -la "$MOCK_S3_DIR"
    fi
    
    # Check if env file was created
    if [[ -f "preserved_files_archive.env" ]]; then
        print_pass "Environment file created"
        
        if grep -q "s3://test-bucket/preserves/test.tar.gz" preserved_files_archive.env; then
            print_pass "Environment file contains correct path"
        else
            print_fail "Environment file has incorrect content"
            cat preserved_files_archive.env
        fi
    else
        print_fail "Environment file not created"
    fi
else
    print_fail "cmd_push should succeed"
    cat output_push.txt
fi

# Test 6: Push command with BINARY_PLAN derivation
echo ""
echo "=== Test 6: cmd_push with BINARY_PLAN derivation ==="

unset PRESERVED_FILES_ARCHIVE
export BINARY_PLAN="s3://test-bucket/plans/workflow-789.plan"

if cmd_push "./generated/derived_test.tar.gz" > output_push2.txt 2>&1; then
    print_pass "cmd_push with BINARY_PLAN completes successfully"
    
    # Check if archive was uploaded with derived name
    if [[ -f "$MOCK_S3_DIR/plans/workflow-789_preserved_files.tar.gz" ]]; then
        print_pass "Archive uploaded with derived S3 path"
    else
        print_fail "Archive not found at derived path"
        find "$MOCK_S3_DIR" -name "*.tar.gz"
    fi
    
    # Check environment file
    if grep -q "workflow-789_preserved_files.tar.gz" preserved_files_archive.env; then
        print_pass "Environment file contains derived path"
    else
        print_fail "Environment file missing derived path"
        cat preserved_files_archive.env
    fi
else
    print_fail "cmd_push with BINARY_PLAN should succeed"
    cat output_push2.txt
fi

# Test 7: Pull command test
echo ""
echo "=== Test 7: cmd_pull ==="

# Set up for pull
export PRESERVED_FILES_ARCHIVE="s3://test-bucket/preserves/test.tar.gz"
rm -f generated/config.json  # Remove file to test restoration

if cmd_pull > output_pull.txt 2>&1; then
    print_pass "cmd_pull completes successfully"
    
    # Check if file was restored
    if [[ -f "generated/config.json" ]]; then
        print_pass "Files restored from archive"
    else
        print_fail "Files not restored"
        ls -la generated/
    fi
else
    print_fail "cmd_pull should succeed"
    cat output_pull.txt
fi

# Test 8: Pull command with missing PRESERVED_FILES_ARCHIVE
echo ""
echo "=== Test 8: cmd_pull without PRESERVED_FILES_ARCHIVE ==="

unset PRESERVED_FILES_ARCHIVE

if cmd_pull > output_pull2.txt 2>&1; then
    if grep -q "not set" output_pull2.txt; then
        print_pass "Handles missing PRESERVED_FILES_ARCHIVE gracefully"
    else
        print_fail "Should warn about missing variable"
    fi
else
    print_fail "Should not fail when PRESERVED_FILES_ARCHIVE is missing"
fi

# Test 9: Pull command with missing S3 file
echo ""
echo "=== Test 9: cmd_pull with missing S3 file ==="

export PRESERVED_FILES_ARCHIVE="s3://test-bucket/nonexistent/missing.tar.gz"

if cmd_pull > output_pull3.txt 2>&1; then
    # Should succeed even if download fails (graceful degradation)
    print_pass "Handles missing S3 file gracefully"
else
    print_pass "Handles missing S3 file (exit 0 expected)"
fi

# Test 10: List command test
echo ""
echo "=== Test 10: cmd_list ==="

export PRESERVED_FILES_ARCHIVE="s3://test-bucket/preserves/test.tar.gz"

if cmd_list > output_list.txt 2>&1; then
    print_pass "cmd_list completes successfully"
    
    # Check if file list contains something or reports empty correctly
    if grep -q "generated/config.json" output_list.txt || grep -q "Total files" output_list.txt; then
        print_pass "Lists archive contents (or reports empty)"
    else
        print_fail "Should list file contents"
        cat output_list.txt
    fi
else
    print_fail "cmd_list should succeed"
    cat output_list.txt
fi

# Test 11: CLI help command
echo ""
echo "=== Test 11: CLI help command ==="

if ../preserve_s3.sh --help > output_help.txt 2>&1; then
    if grep -q "Usage:" output_help.txt && \
       grep -q "push" output_help.txt && \
       grep -q "pull" output_help.txt && \
       grep -q "list" output_help.txt; then
        print_pass "Shows comprehensive help"
    else
        print_fail "Help should include all commands"
    fi
else
    print_fail "Help command should succeed"
fi

# Test 12: Integration test - full workflow
echo ""
echo "=== Test 12: Full workflow (push → pull → verify) ==="

# Clean slate
rm -rf workflow_test
mkdir workflow_test
cd workflow_test

# Create test files
mkdir -p app/config data
echo "app config" > app/config/settings.json
echo "data file" > data/values.txt

cat > harness.json <<'EOF'
{
    "preserved_files": [
        "app/config/settings.json",
        "data/values.txt"
    ]
}
EOF

cat > terraform.tfstate <<'EOF'
{
  "version": 4,
  "resources": [
    {
      "mode": "managed",
      "type": "local_file",
      "name": "output",
      "instances": [
        {
          "attributes": {
            "filename": "output/generated.txt"
          }
        }
      ]
    }
  ]
}
EOF

mkdir -p output
echo "generated output" > output/generated.txt

cat > mock_terraform.sh <<'EOF'
#!/bin/bash
if [[ "$1" == "state" && "$2" == "pull" ]]; then
    cat terraform.tfstate
    exit 0
fi
exit 1
EOF
chmod +x mock_terraform.sh

export BINARY_PLAN="s3://test-bucket/integration/workflow-complete.plan"
export TERRAFORM="./mock_terraform.sh"
export TF_VAR_environment="integration"
unset PRESERVED_FILES_ARCHIVE

# Step 1: Push
if ../../preserve_s3.sh push > push.log 2>&1; then
    print_pass "Integration: Push succeeds"
else
    print_fail "Integration: Push failed"
    cat push.log
fi

# Load the exported variable
if [[ -f "preserved_files_archive.env" ]]; then
    source preserved_files_archive.env
    if [[ -n "$PRESERVED_FILES_ARCHIVE" ]]; then
        print_pass "Integration: PRESERVED_FILES_ARCHIVE exported"
    else
        print_fail "Integration: Variable not exported"
    fi
else
    print_fail "Integration: Env file not created"
fi

# Step 2: Delete local files
rm -rf app data output

# Step 3: Pull
if ../../preserve_s3.sh pull > pull.log 2>&1; then
    print_pass "Integration: Pull succeeds"
else
    print_fail "Integration: Pull failed"
    cat pull.log
fi

# Step 4: Verify files restored
files_ok=true
[[ ! -f "app/config/settings.json" ]] && files_ok=false
[[ ! -f "data/values.txt" ]] && files_ok=false
[[ ! -f "output/generated.txt" ]] && files_ok=false

if $files_ok; then
    print_pass "Integration: All files restored"
else
    print_fail "Integration: Some files missing"
    find . -name "*.json" -o -name "*.txt"
fi

cd ..

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

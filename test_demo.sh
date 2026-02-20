#!/bin/bash
# Quick demonstration test of both approaches

set -e

clear
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║         File Preservation Test Suite - Quick Demo             ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""

# Ensure we have a clean starting point
if [[ ! -d generated/ ]]; then
    echo "Initializing: Creating files with terraform apply..."
    terraform apply -auto-approve > /dev/null 2>&1
fi

echo "📁 Current files:"
ls -lh generated/ | tail -n +2
echo ""

# ============================================
# Demo 1: State Restoration
# ============================================
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Demo 1: State Restoration (restore_from_state.sh)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Scenario: Files deleted but Terraform state intact"
echo ""

echo "⚠️  Deleting files..."
rm -rf generated/
echo "   Files deleted: $(ls generated/ 2>/dev/null | wc -l | xargs) files remaining"
echo ""

echo "🔧 Running restore_from_state.sh..."
./restore_from_state.sh > /dev/null 2>&1
echo "   ✓ Restoration complete"
echo ""

echo "📁 Restored files:"
ls -lh generated/ | tail -n +2
echo ""

echo "🔍 Terraform state check:"
terraform state list | sed 's/^/   /'
echo ""

# ============================================
# Demo 2: Tar/Preserve Approach  
# ============================================
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Demo 2: Tar/Preserve Approach (tar.py)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Scenario: Archive files, delete them, then restore"
echo ""

ARCHIVE="demo-backup.tar.gz"

echo "📦 Creating archive..."
python tar.py tar "$ARCHIVE" > /dev/null 2>&1
ARCHIVE_SIZE=$(ls -lh "$ARCHIVE" | awk '{print $5}')
echo "   ✓ Archive created: $ARCHIVE_SIZE"
echo ""

echo "⚠️  Deleting files..."
rm -rf generated/
echo "   Files deleted: $(ls generated/ 2>/dev/null | wc -l | xargs) files remaining"
echo ""

echo "📂 Extracting from archive..."
python tar.py untar "$ARCHIVE" > /dev/null 2>&1
FILE_COUNT=$(ls generated/ 2>/dev/null | wc -l | xargs)
echo "   ✓ Extracted $FILE_COUNT files"
echo ""

echo "📁 Restored files:"
ls -lh generated/ | tail -n +2
echo ""

# Cleanup
rm -f "$ARCHIVE"

# ============================================
# Summary
# ============================================
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Summary"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "✅ Both approaches successfully restored files:"
echo ""
echo "   1️⃣  State Restoration (restore_from_state.sh)"
echo "       • Fast local restoration"
echo "       • Requires Terraform state"
echo "       • Best for: Local development/debugging"
echo ""
echo "   2️⃣  Tar/Preserve Approach (tar.py + preserve.py)"
echo "       • Works with/without state"
echo "       • S3 integration for CI/CD"
echo "       • Best for: Apply → Verify Plan workflow"
echo ""

# Show file content
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "File Contents Verification"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "📄 generated/example.txt (first 4 lines):"
head -4 generated/example.txt | sed 's/^/   /'
echo ""
echo "📄 generated/config.json:"
cat generated/config.json | jq -r '.application + " v" + .version + " (" + .environment + ")"' | sed 's/^/   /'
echo ""

echo "╔════════════════════════════════════════════════════════════════╗"
echo "║                     Demo Complete! ✨                          ║"
echo "╚════════════════════════════════════════════════════════════════╝"

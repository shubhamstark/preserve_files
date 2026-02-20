# Standup Update - File Preservation Scripts

## What I Did

Built scripts to solve the Terraform file preservation issue where files generated during Apply were being detected as "new" resources in the Verify Plan stage.

## Deliverables

Created 4 scripts (Python + Shell versions):

1. **tar.py / tar.sh**
   - Tar and untar files from harness.json
   - Preserves exact file paths (relative and absolute)
   - Delete functionality for cleanup

2. **preserve.py / preserve.sh**
   - Push: Archives files and uploads to S3 with unique key
   - Pull: Downloads from S3 and extracts to original locations
   - List: Shows all archives in bucket
   - Uses AWS CLI

3. **Supporting files**
   - harness.json config
   - README.md documentation

## How It Works

**After Apply:**
```bash
./preserve.sh build-123 push  # Archive & upload to S3
```

**Before Verify Plan:**
```bash
./preserve.sh build-123 pull  # Download & restore files
```

Files are preserved between stages, eliminating false drift in Terraform plans.

## Testing

✅ Tested tar/untar with relative and absolute paths  
✅ Tested S3 push/pull operations  
✅ Verified files extract to correct locations  

## Status

Ready for integration into Terraform workflow.

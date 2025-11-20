#!/bin/bash
# Configuration
#Test script for monitoring file integrity in a specified directory. Vibe-coded using antigravity by google.
DB_FILE=".integrity_db"
TARGET_DIR="${1:-.}"
# Determine hashing command
if command -v sha256sum >/dev/null 2>&1; then
    HASH_CMD="sha256sum"
elif command -v shasum >/dev/null 2>&1; then
    HASH_CMD="shasum -a 256"
else
    echo "Error: No SHA256 hashing utility found (sha256sum or shasum)."
    exit 1
fi
# Function to get file metadata
get_metadata() {
    local file="$1"
    if [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS stat
        stat -f "    Last Modified: %Sm%n    Size: %z bytes" "$file"
    else
        # Linux stat
        stat -c "    Last Modified: %y%n    Size: %s bytes" "$file"
    fi
}
# Ensure we are in the target directory or handle paths correctly
# To simplify, we will cd to target directory
if [ ! -d "$TARGET_DIR" ]; then
    echo "Error: Directory $TARGET_DIR does not exist."
    exit 1
fi
cd "$TARGET_DIR" || exit 1
echo "Monitoring directory: $(pwd)"
if [ ! -f "$DB_FILE" ]; then
    echo "No baseline found. Creating baseline..."
    # Find files, ignore the DB file itself and the script if it's in the same dir
    # We use a temporary file to store the list to avoid issues with spaces in filenames if not careful,
    # but find -exec is safe.
    find . -type f -not -path "./$DB_FILE" -not -name ".DS_Store" -exec $HASH_CMD {} + > "$DB_FILE"
    echo "Baseline created successfully at $DB_FILE"
    echo "Total files tracked: $(wc -l < "$DB_FILE" | tr -d ' ')"
else
    echo "Baseline found. Verifying integrity..."
    
    # Create temp files
    CURRENT_STATE=$(mktemp)
    SORTED_DB=$(mktemp)
    SORTED_CURRENT=$(mktemp)
    
    # Capture current state
    find . -type f -not -path "./$DB_FILE" -not -name ".DS_Store" -exec $HASH_CMD {} + > "$CURRENT_STATE"
    
    # Sort by filename (2nd field) to facilitate comparison
    sort -k 2 "$DB_FILE" > "$SORTED_DB"
    sort -k 2 "$CURRENT_STATE" > "$SORTED_CURRENT"
    
    # 1. Check for NEW files
    # Files in CURRENT but not in DB
    # We use awk to extract filenames and comm to compare
    comm -13 <(awk '{print $2}' "$SORTED_DB") <(awk '{print $2}' "$SORTED_CURRENT") > new_files_list
    
    # 2. Check for DELETED files
    # Files in DB but not in CURRENT
    comm -23 <(awk '{print $2}' "$SORTED_DB") <(awk '{print $2}' "$SORTED_CURRENT") > deleted_files_list
    
    # 3. Check for MODIFIED files
    # Files in both, but hashes differ
    # We can use join on the sorted files. 
    # join format: HASH1 FILE HASH2 (if joined by file). 
    # But join expects the join field to be sorted. We sorted by field 2 (filename).
    # So we join on field 2.
    join -1 2 -2 2 "$SORTED_DB" "$SORTED_CURRENT" > joined_files
    # joined_files format: FILENAME HASH_OLD HASH_NEW
    
    # Filter where HASH_OLD != HASH_NEW
    awk '$2 != $3 {print $1}' joined_files > modified_files_list
    
    # --- REPORTING ---
    
    CHANGES_DETECTED=false
    
    if [ -s new_files_list ]; then
        CHANGES_DETECTED=true
        echo ""
        echo "--------------------------------------------------"
        echo "WARNING: NEW FILES DETECTED"
        echo "--------------------------------------------------"
        while read -r file; do
            echo "[+] $file"
            get_metadata "$file"
            echo "    Status: New (Not present in last baseline)"
        done < new_files_list
    fi
    
    if [ -s modified_files_list ]; then
        CHANGES_DETECTED=true
        echo ""
        echo "--------------------------------------------------"
        echo "WARNING: MODIFIED FILES DETECTED"
        echo "--------------------------------------------------"
        while read -r file; do
            echo "[*] $file"
            get_metadata "$file"
            echo "    Status: Modified (Hash mismatch)"
        done < modified_files_list
    fi
    
    if [ -s deleted_files_list ]; then
        CHANGES_DETECTED=true
        echo ""
        echo "--------------------------------------------------"
        echo "WARNING: DELETED FILES DETECTED"
        echo "--------------------------------------------------"
        while read -r file; do
            echo "[-] $file"
            echo "    Status: Deleted (Present in baseline but missing now)"
        done < deleted_files_list
    fi
    
    if [ "$CHANGES_DETECTED" = false ]; then
        echo ""
        echo "Status: OK. No changes detected."
    fi
    
    # Cleanup
    rm "$CURRENT_STATE" "$SORTED_DB" "$SORTED_CURRENT" "new_files_list" "deleted_files_list" "joined_files" "modified_files_list"
fi

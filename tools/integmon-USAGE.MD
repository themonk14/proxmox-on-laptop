Usage
Make Executable:

chmod +x integrity_monitor.sh
Create Baseline: Run the script for the first time to generate the baseline database (.integrity_db).

./integrity_monitor.sh [TARGET_DIRECTORY]
If no directory is provided, it defaults to the current directory.

Verify Integrity: Run the script again to check for changes.

./integrity_monitor.sh
Verification Results
I performed the following test sequence:

Initial State: Created file1.txt and file2.txt.
Baseline Creation: Ran 

./integrity_monitor.sh
.
Output: "Baseline created successfully..."

Changes Made:
Created new_file.txt
Modified file1.txt
Deleted file2.txt
Verification Run: Ran 

./integrity_monitor.sh
.
Output Log
Monitoring directory: /Users/prudhvi/.gemini/antigravity/playground/volatile-space
Baseline found. Verifying integrity...
--------------------------------------------------
WARNING: NEW FILES DETECTED
--------------------------------------------------
[+] ./new_file.txt
    Last Modified: Nov 20 17:37:14 2025
    Size: 17 bytes
    Status: New (Not present in last baseline)
--------------------------------------------------
WARNING: MODIFIED FILES DETECTED
--------------------------------------------------
[*] ./file1.txt
    Last Modified: Nov 20 17:37:14 2025
    Size: 29 bytes
    Status: Modified (Hash mismatch)
--------------------------------------------------
WARNING: DELETED FILES DETECTED
--------------------------------------------------
[-] ./file2.txt
    Status: Deleted (Present in baseline but missing now)
The script correctly identified all three types of changes and provided metadata (Last Modified time) for the new and modified files.
# Common Bash Scripting Pitfalls

## 1. Not Quoting Variables

**Problem:**
```bash
file="my file.txt"
rm $file  # Tries to remove "my" and "file.txt"
```

**Solution:**
```bash
file="my file.txt"
rm "$file"  # Correctly removes "my file.txt"
```

## 2. Using `[ ]` Instead of `[[ ]]`

**Problem:**
```bash
if [ $var = "test" ]; then  # Fails if var is unset
```

**Solution:**
```bash
if [[ $var = "test" ]]; then  # Safer
```

## 3. Not Handling Spaces in Filenames

**Problem:**
```bash
for file in $(ls *.txt); do  # Breaks on spaces
    echo $file
done
```

**Solution:**
```bash
for file in *.txt; do
    echo "$file"
done
```

## 4. Ignoring Exit Codes

**Problem:**
```bash
cd /some/directory
rm important_file  # Runs even if cd failed
```

**Solution:**
```bash
cd /some/directory || exit 1
rm important_file
```

Or use `set -e`:
```bash
set -e
cd /some/directory
rm important_file
```

## 5. Using `ls` for Parsing

**Problem:**
```bash
files=$(ls -l | awk '{print $9}')
```

**Solution:**
```bash
# Use globbing
for file in *; do
    [[ -f "$file" ]] && echo "$file"
done

# Or find
while IFS= read -r -d '' file; do
    echo "$file"
done < <(find . -type f -print0)
```

## 6. Not Checking if a File Exists

**Problem:**
```bash
cat file.txt  # Fails if file doesn't exist
```

**Solution:**
```bash
if [[ -f "file.txt" ]]; then
    cat file.txt
else
    echo "File not found" >&2
    exit 1
fi
```

## 7. Incorrect Comparison Operators

**Problem:**
```bash
if [[ $num = 5 ]]; then  # String comparison, not numeric
```

**Solution:**
```bash
if [[ $num -eq 5 ]]; then  # Numeric comparison
```

## 8. Not Using `local` in Functions

**Problem:**
```bash
my_function() {
    result="value"  # Global variable
}
```

**Solution:**
```bash
my_function() {
    local result="value"  # Local variable
}
```

## 9. Forgetting to Make Scripts Executable

**Problem:**
```bash
./script.sh  # Permission denied
```

**Solution:**
```bash
chmod +x script.sh
./script.sh
```

## 10. Using Uppercase Variable Names

**Problem:**
```bash
PATH="/my/path"  # Overwrites system PATH
```

**Solution:**
```bash
my_path="/my/path"  # Use lowercase for custom variables
# Use uppercase only for constants
readonly MAX_RETRIES=3
```

## 11. Not Handling Undefined Variables

**Problem:**
```bash
echo $undefined_variable  # Silently prints nothing
rm -rf /$undefined_path/*  # Dangerous!
```

**Solution:**
```bash
set -u  # Exit on undefined variables
echo "${undefined_variable:-default}"  # Use default
```

## 12. Incorrect Array Usage

**Problem:**
```bash
args="arg1 arg2 arg3"
command $args  # Splits incorrectly
```

**Solution:**
```bash
args=("arg1" "arg2" "arg3")
command "${args[@]}"
```

## Tools for Better Scripts

1. **ShellCheck**: Static analysis tool
   ```bash
   shellcheck script.sh
   ```

2. **set -x**: Enable debug mode
   ```bash
   bash -x script.sh
   ```

3. **set -euo pipefail**: Strict mode
   ```bash
   set -euo pipefail
   ```


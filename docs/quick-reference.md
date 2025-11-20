# Bash Scripting Quick Reference

## Shebang and Options

```bash
#!/bin/bash
set -euo pipefail  # Strict mode
set -x             # Debug mode
```

## Variables

```bash
# Define
name="value"
readonly CONSTANT="value"

# Use
echo "$name"
echo "${name}"

# Default values
echo "${var:-default}"        # Use default if unset
echo "${var:=default}"        # Assign default if unset
echo "${var:?error message}"  # Exit with error if unset
```

## String Operations

```bash
# Length
${#string}

# Substring
${string:position:length}

# Replace
${string/pattern/replacement}   # First occurrence
${string//pattern/replacement}  # All occurrences

# Remove prefix/suffix
${string#prefix}   # Remove shortest prefix
${string##prefix}  # Remove longest prefix
${string%suffix}   # Remove shortest suffix
${string%%suffix}  # Remove longest suffix

# Case conversion
${string^^}  # To uppercase
${string,,}  # To lowercase
```

## Arrays

```bash
# Define
array=("item1" "item2" "item3")

# Access
${array[0]}      # First element
${array[@]}      # All elements
${array[*]}      # All elements (single word)
${#array[@]}     # Array length

# Add elements
array+=("item4")

# Loop through array
for item in "${array[@]}"; do
    echo "$item"
done
```

## Conditionals

```bash
# If statement
if [[ condition ]]; then
    # code
elif [[ condition ]]; then
    # code
else
    # code
fi

# File tests
[[ -f file ]]   # File exists
[[ -d dir ]]    # Directory exists
[[ -r file ]]   # Readable
[[ -w file ]]   # Writable
[[ -x file ]]   # Executable
[[ -s file ]]   # Not empty

# String tests
[[ -z string ]]       # Empty
[[ -n string ]]       # Not empty
[[ str1 = str2 ]]     # Equal
[[ str1 != str2 ]]    # Not equal
[[ str1 < str2 ]]     # Less than (lexicographic)

# Numeric tests
[[ num1 -eq num2 ]]   # Equal
[[ num1 -ne num2 ]]   # Not equal
[[ num1 -lt num2 ]]   # Less than
[[ num1 -le num2 ]]   # Less than or equal
[[ num1 -gt num2 ]]   # Greater than
[[ num1 -ge num2 ]]   # Greater than or equal

# Logical operators
[[ cond1 && cond2 ]]  # AND
[[ cond1 || cond2 ]]  # OR
[[ ! cond ]]          # NOT
```

## Loops

```bash
# For loop
for i in {1..10}; do
    echo "$i"
done

for file in *.txt; do
    echo "$file"
done

# While loop
while [[ condition ]]; do
    # code
done

# Until loop
until [[ condition ]]; do
    # code
done

# C-style for loop
for ((i=0; i<10; i++)); do
    echo "$i"
done
```

## Functions

```bash
# Define
function_name() {
    local var="value"
    echo "$1"  # First argument
    return 0
}

# Call
function_name "arg1" "arg2"

# With return value
result=$(function_name)
```

## Input/Output

```bash
# Read user input
read -p "Prompt: " variable

# Read file line by line
while IFS= read -r line; do
    echo "$line"
done < file.txt

# Redirect output
command > file.txt      # Overwrite
command >> file.txt     # Append
command 2> error.txt    # Stderr
command &> all.txt      # Stdout and stderr
command 2>&1            # Redirect stderr to stdout

# Here document
cat << EOF
Multiple lines
of text
EOF
```

## Command Substitution

```bash
# Modern syntax
result=$(command)

# Old syntax (avoid)
result=`command`
```

## Arithmetic

```bash
# Arithmetic expansion
result=$((1 + 2))
((count++))
((count += 5))

# bc for floating point
result=$(echo "scale=2; 10/3" | bc)
```

## Exit Codes

```bash
# Exit with code
exit 0  # Success
exit 1  # Error

# Check last command
if [[ $? -eq 0 ]]; then
    echo "Success"
fi

# Exit on error
command || exit 1
```

## Useful Commands

```bash
# Command existence
command -v cmd &> /dev/null

# Directory of script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Temporary file/directory
temp_file=$(mktemp)
temp_dir=$(mktemp -d)

# Date and time
date "+%Y-%m-%d"
date "+%H:%M:%S"

# Sleep
sleep 1      # 1 second
sleep 0.5    # 500 milliseconds
```

## Error Handling

```bash
# Trap signals
trap 'cleanup' EXIT
trap 'error_handler' ERR

cleanup() {
    rm -f "$temp_file"
}

error_handler() {
    echo "Error on line $LINENO" >&2
}
```

## Parameter Expansion

```bash
${parameter:-word}       # Use default value
${parameter:=word}       # Assign default value
${parameter:?message}    # Display error if null
${parameter:+word}       # Use alternative value
${#parameter}            # String length
${parameter#pattern}     # Remove prefix
${parameter%pattern}     # Remove suffix
${parameter/pattern/str} # Replace
```

## Process Management

```bash
# Background process
command &

# Get process ID
pid=$!

# Wait for process
wait $pid

# Kill process
kill $pid
kill -9 $pid  # Force kill
```

## Special Variables

```bash
$0      # Script name
$1-$9   # Arguments 1-9
${10}   # Argument 10+
$#      # Argument count
$@      # All arguments (separate words)
$*      # All arguments (single word)
$?      # Last exit code
$$      # Current PID
$!      # Last background PID
```

## File Descriptors

```bash
# Read from file descriptor
exec 3< file.txt
while read -u 3 line; do
    echo "$line"
done
exec 3<&-  # Close

# Write to file descriptor
exec 4> output.txt
echo "data" >&4
exec 4>&-  # Close
```

## Color Output

```bash
# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'  # No color

# Usage
echo -e "${RED}Error${NC}"
echo -e "${GREEN}Success${NC}"
```

## Useful Patterns

```bash
# Check if running as root
if [[ $EUID -ne 0 ]]; then
    echo "Must run as root" >&2
    exit 1
fi

# Check dependencies
for cmd in curl wget; do
    command -v "$cmd" &> /dev/null || {
        echo "$cmd not found" >&2
        exit 1
    }
done

# Process options
while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help) show_help; exit 0 ;;
        -v|--verbose) VERBOSE=true; shift ;;
        --) shift; break ;;
        -*) echo "Unknown option: $1" >&2; exit 1 ;;
        *) break ;;
    esac
done
```

## Best Practices Summary

1. Always quote variables: `"$var"`
2. Use `[[ ]]` instead of `[ ]`
3. Use `set -euo pipefail` for safety
4. Check command existence before use
5. Use functions for reusability
6. Add proper error handling
7. Document your code
8. Use meaningful variable names
9. Test thoroughly
10. Run shellcheck

## Resources

- [Bash Manual](https://www.gnu.org/software/bash/manual/)
- [ShellCheck](https://www.shellcheck.net/)
- [Bash Guide](https://mywiki.wooledge.org/BashGuide)
- [Google Shell Style Guide](https://google.github.io/styleguide/shellguide.html)


# Bash Scripting Best Practices

## General Guidelines

### 1. Always Use Shebang
```bash
#!/bin/bash
```

### 2. Enable Strict Error Handling
```bash
set -euo pipefail
```
- `-e`: Exit on error
- `-u`: Exit on undefined variable
- `-o pipefail`: Fail on pipe errors

### 3. Quote Variables
```bash
# Good
echo "$variable"
rm "$file_path"

# Bad
echo $variable
rm $file_path
```

### 4. Use Meaningful Variable Names
```bash
# Good
user_name="john"
file_count=10

# Bad
un="john"
fc=10
```

### 5. Use Functions for Reusability
```bash
check_file_exists() {
    local file="$1"
    [[ -f "$file" ]] || return 1
}
```

## Error Handling

### Check Command Success
```bash
if ! command_that_might_fail; then
    echo "Command failed" >&2
    exit 1
fi
```

### Use Trap for Cleanup
```bash
cleanup() {
    rm -f "$temp_file"
}
trap cleanup EXIT
```

## Common Patterns

### Check if Command Exists
```bash
if ! command -v required_command &> /dev/null; then
    echo "required_command not found" >&2
    exit 1
fi
```

### Read File Line by Line
```bash
while IFS= read -r line; do
    echo "Line: $line"
done < file.txt
```

### Process Arguments
```bash
while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            exit 1
            ;;
    esac
    shift
done
```

## Security Considerations

1. **Never use `eval`** unless absolutely necessary
2. **Validate user input** before using it
3. **Use absolute paths** or verify commands with `command -v`
4. **Be careful with `rm -rf`** - always check variables
5. **Set appropriate file permissions** for scripts

## Performance Tips

1. Use built-in commands instead of external programs when possible
2. Minimize subprocess creation
3. Use arrays for multiple values
4. Consider using `xargs` for parallel processing

## Documentation

1. Include a header comment with:
   - Script name and description
   - Author and version
   - Usage instructions
   - Dependencies

2. Comment complex logic
3. Provide examples in help text
4. Document exit codes

## Testing

1. Test with different inputs
2. Test error conditions
3. Verify on different systems if possible
4. Use ShellCheck for static analysis


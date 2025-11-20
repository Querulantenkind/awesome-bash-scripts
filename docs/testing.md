# Testing Bash Scripts

## Why Test?

Testing helps ensure:
- Scripts work as expected
- Changes don't break existing functionality
- Edge cases are handled properly
- Scripts are reliable and maintainable

## Manual Testing

### Basic Testing Checklist

Before committing a script, test:

- [ ] Script runs without errors
- [ ] Help/usage information displays correctly (`-h`, `--help`)
- [ ] Valid inputs produce expected outputs
- [ ] Invalid inputs show appropriate error messages
- [ ] Script exits with correct exit codes
- [ ] All command-line options work
- [ ] Script handles missing dependencies gracefully

### Test Different Scenarios

1. **Normal operation**: Test with typical inputs
2. **Edge cases**: Empty inputs, very large inputs, special characters
3. **Error conditions**: Missing files, invalid permissions, network failures
4. **Different environments**: Various Linux distributions if possible

### Example Manual Test Session

```bash
# Test normal operation
./script.sh --option value

# Test with missing arguments
./script.sh

# Test help
./script.sh --help

# Test with invalid input
./script.sh --invalid

# Test with edge case
./script.sh ""

# Check exit codes
./script.sh && echo "Success: $?" || echo "Failed: $?"
```

## Static Analysis with ShellCheck

[ShellCheck](https://www.shellcheck.net/) is an excellent static analysis tool for bash scripts.

### Installation

```bash
# Ubuntu/Debian
sudo apt-get install shellcheck

# Fedora
sudo dnf install shellcheck

# Arch Linux
sudo pacman -S shellcheck

# macOS
brew install shellcheck
```

### Usage

```bash
# Check a single script
shellcheck script.sh

# Check all scripts
find scripts/ -name "*.sh" -type f -exec shellcheck {} \;

# Check with specific severity
shellcheck --severity=warning script.sh
```

### Common ShellCheck Warnings

```bash
# SC2086: Quote variables
echo $variable  # Bad
echo "$variable"  # Good

# SC2046: Quote command substitution
for file in $(ls); do  # Bad
for file in *; do  # Good

# SC2164: Use error handling for cd
cd /some/dir  # Bad
cd /some/dir || exit 1  # Good
```

## Automated Testing

### Simple Test Framework

Create a basic test script:

```bash
#!/bin/bash

# test-script.sh
TEST_SCRIPT="./my-script.sh"
TESTS_PASSED=0
TESTS_FAILED=0

test_case() {
    local description="$1"
    shift
    
    if "$@"; then
        echo "✓ PASS: $description"
        ((TESTS_PASSED++))
    else
        echo "✗ FAIL: $description"
        ((TESTS_FAILED++))
    fi
}

# Run tests
test_case "Script exists and is executable" [[ -x "$TEST_SCRIPT" ]]
test_case "Help option works" "$TEST_SCRIPT" --help &> /dev/null
test_case "Script handles missing argument" ! "$TEST_SCRIPT" "" &> /dev/null

# Summary
echo ""
echo "Tests passed: $TESTS_PASSED"
echo "Tests failed: $TESTS_FAILED"

[[ $TESTS_FAILED -eq 0 ]]
```

### Using BATS (Bash Automated Testing System)

[BATS](https://github.com/bats-core/bats-core) is a TAP-compliant testing framework.

#### Installation

```bash
# Clone BATS
git clone https://github.com/bats-core/bats-core.git
cd bats-core
sudo ./install.sh /usr/local
```

#### Example BATS Test

```bash
#!/usr/bin/env bats

@test "script exists" {
    [ -f "./my-script.sh" ]
}

@test "script is executable" {
    [ -x "./my-script.sh" ]
}

@test "help option works" {
    run ./my-script.sh --help
    [ "$status" -eq 0 ]
}

@test "fails with invalid option" {
    run ./my-script.sh --invalid
    [ "$status" -ne 0 ]
}

@test "produces expected output" {
    run ./my-script.sh
    [ "$output" = "Expected output" ]
}
```

Run BATS tests:
```bash
bats test/my-script.bats
```

## Debug Mode

Enable debug output in scripts:

```bash
# In the script
set -x  # Enable debug mode

# Or run with debug flag
bash -x script.sh

# Or add debug option
if [[ "$DEBUG" == true ]]; then
    set -x
fi
```

## Testing Best Practices

1. **Test early and often** during development
2. **Write tests for bugs** before fixing them
3. **Test on clean systems** or containers
4. **Document test procedures** in script comments
5. **Use shellcheck** regularly
6. **Test with different users** and permissions
7. **Verify cleanup** of temporary files
8. **Check for side effects** on the system

## Test Data

Create test data for consistent testing:

```bash
# Create test directory
mkdir -p test/fixtures

# Create test files
echo "test content" > test/fixtures/test-file.txt

# Use in tests
TEST_FILE="test/fixtures/test-file.txt"
```

## Continuous Integration

### GitHub Actions Example

```yaml
name: Test Scripts

on: [push, pull_request]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v2
      
      - name: Install ShellCheck
        run: sudo apt-get install -y shellcheck
      
      - name: Run ShellCheck
        run: |
          find scripts/ -name "*.sh" -type f -exec shellcheck {} \;
      
      - name: Run tests
        run: |
          chmod +x scripts/**/*.sh
          ./run-tests.sh
```

## Performance Testing

Test script performance:

```bash
# Measure execution time
time ./script.sh

# Detailed timing
/usr/bin/time -v ./script.sh

# Profile with bash
PS4='+ $(date "+%s.%N")\011 '
bash -x script.sh
```

## Summary

Good testing practices include:
- Running shellcheck on all scripts
- Manual testing with various inputs
- Automated tests for critical functionality
- Regular testing during development
- Documentation of test procedures

Remember: **Test before you commit!**


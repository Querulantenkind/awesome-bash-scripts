# Testing Framework

This directory contains the testing infrastructure for Awesome Bash Scripts.

## Structure

```
tests/
├── test-runner.sh      # Main test runner script
├── unit/              # Unit tests for individual functions
├── integration/       # Integration tests for complete scripts
└── fixtures/          # Test data and mock files
```

## Running Tests

### Run All Tests
```bash
./test-runner.sh
```

### Run Specific Test Types
```bash
# Unit tests only
./test-runner.sh --unit

# Integration tests only
./test-runner.sh --integration

# With coverage report
./test-runner.sh --coverage
```

### Run Tests for Specific Scripts
```bash
# Filter by pattern
./test-runner.sh --filter "backup"

# Run in verbose mode
./test-runner.sh --verbose --filter "system"
```

## Writing Tests

### Unit Tests

Unit tests focus on testing individual functions in isolation:

```bash
#!/bin/bash

# Source the library/script being tested
source "$PROJECT_ROOT/lib/common.sh"

test_function_name() {
    # Arrange
    local input="test data"
    
    # Act
    local result=$(function_to_test "$input")
    
    # Assert
    assert_equals "expected" "$result" "Function should return expected value"
}
```

### Integration Tests

Integration tests test complete scripts end-to-end:

```bash
#!/bin/bash

readonly SCRIPT="$PROJECT_ROOT/scripts/category/script-name.sh"

test_script_basic_usage() {
    local output
    output=$("$SCRIPT" --option 2>&1)
    local exit_code=$?
    
    assert_exit_code 0 "$exit_code" "Script should succeed"
    assert_contains "$output" "expected text" "Output should contain expected text"
}
```

## Available Assertions

- `assert_equals expected actual [message]` - Check if two values are equal
- `assert_contains haystack needle [message]` - Check if string contains substring
- `assert_not_contains haystack needle [message]` - Check if string doesn't contain substring
- `assert_true condition [message]` - Check if condition is true
- `assert_false condition [message]` - Check if condition is false
- `assert_exit_code expected actual [message]` - Check exit code
- `assert_file_exists file [message]` - Check if file exists
- `assert_file_not_exists file [message]` - Check if file doesn't exist

## Test Helpers

- `test_skip [reason]` - Skip test with optional reason
- `test_fail [reason]` - Explicitly fail test with reason
- `run_benchmark name command [iterations]` - Run performance benchmark

## Test Environment

The test runner automatically:
- Creates isolated temp directories for each test
- Sets `ABS_TEST_MODE=true` environment variable
- Disables actual notifications (email, desktop, etc.)
- Sets predictable locale and timezone
- Cleans up after tests

## Continuous Integration

Tests are designed to work in CI environments:
- Tests that require special permissions can detect CI and skip
- Output is formatted for easy parsing
- Exit codes indicate success/failure
- Coverage reports can be generated

## Best Practices

1. **Test Naming**: Use descriptive names starting with `test_`
2. **Isolation**: Each test should be independent
3. **Cleanup**: Tests should clean up any files they create
4. **Mocking**: Use fixtures directory for test data
5. **Performance**: Keep tests fast, use `test_skip` for slow tests
6. **Coverage**: Aim for high code coverage but focus on critical paths

## Adding New Tests

1. Create test file: `tests/unit/test_scriptname.sh`
2. Add test functions following naming convention
3. Run tests to ensure they pass
4. Add integration tests for user-facing functionality
5. Update coverage targets if needed

## Performance Testing

Run performance benchmarks:
```bash
./test-runner.sh --performance
```

This will run predefined benchmarks and show timing statistics.

## Debugging Tests

```bash
# Run with verbose output
./test-runner.sh --verbose

# Run single test file
bash -x tests/unit/test_common_lib.sh

# Set debug environment
DEBUG=true ./test-runner.sh
```

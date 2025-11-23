#!/bin/bash

################################################################################
# Test Runner - Awesome Bash Scripts Testing Framework
# Version: 1.0.0
#
# This script runs all tests for the Awesome Bash Scripts collection.
# Supports unit tests, integration tests, and performance benchmarks.
#
# Usage: ./test-runner.sh [options] [test-pattern]
#
# Options:
#   -h, --help          Show help message
#   -v, --verbose       Verbose output
#   -q, --quiet         Quiet mode (only show failures)
#   -u, --unit          Run unit tests only
#   -i, --integration   Run integration tests only
#   -p, --performance   Run performance tests
#   -c, --coverage      Generate coverage report
#   -f, --filter PATTERN  Filter tests by pattern
#   --no-color          Disable colored output
#
################################################################################

set -euo pipefail

# Script directory
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Test configuration
TEST_TYPE="all"
VERBOSE=false
QUIET=false
SHOW_COVERAGE=false
TEST_FILTER=""
PERFORMANCE=false
NO_COLOR=false

# Statistics
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_SKIPPED=0
START_TIME=$(date +%s)

# Source libraries
source "$PROJECT_ROOT/lib/common.sh"
source "$PROJECT_ROOT/lib/colors.sh"

################################################################################
# Test Framework Functions
################################################################################

# Initialize test environment
init_test_env() {
    # Create temp directory for test artifacts
    export TEST_TMP_DIR=$(mktemp -d "/tmp/abs-test.XXXXXX")
    
    # Set test mode for scripts
    export ABS_TEST_MODE=true
    
    # Disable actual notifications in test mode
    export NOTIFY_DESKTOP=false
    export NOTIFY_EMAIL=false
    export NOTIFY_WEBHOOK=false
    export NOTIFY_PUSH=false
    
    # Set predictable environment
    export TZ="UTC"
    export LANG="C"
    export LC_ALL="C"
    
    # Add project scripts to PATH
    export PATH="$PROJECT_ROOT/scripts:$PATH"
}

# Cleanup test environment
cleanup_test_env() {
    if [[ -d "$TEST_TMP_DIR" ]]; then
        rm -rf "$TEST_TMP_DIR"
    fi
}

# Test assertions
assert_equals() {
    local expected="$1"
    local actual="$2"
    local message="${3:-Assertion failed}"
    
    if [[ "$expected" != "$actual" ]]; then
        test_fail "$message: expected '$expected', got '$actual'"
        return 1
    fi
    return 0
}

assert_contains() {
    local haystack="$1"
    local needle="$2"
    local message="${3:-Assertion failed}"
    
    if [[ "$haystack" != *"$needle"* ]]; then
        test_fail "$message: '$haystack' does not contain '$needle'"
        return 1
    fi
    return 0
}

assert_not_contains() {
    local haystack="$1"
    local needle="$2"
    local message="${3:-Assertion failed}"
    
    if [[ "$haystack" == *"$needle"* ]]; then
        test_fail "$message: '$haystack' contains '$needle'"
        return 1
    fi
    return 0
}

assert_true() {
    local condition="$1"
    local message="${2:-Assertion failed}"
    
    if [[ "$condition" != "true" ]] && [[ "$condition" != "0" ]]; then
        test_fail "$message: condition is not true"
        return 1
    fi
    return 0
}

assert_false() {
    local condition="$1"
    local message="${2:-Assertion failed}"
    
    if [[ "$condition" == "true" ]] || [[ "$condition" == "0" ]]; then
        test_fail "$message: condition is not false"
        return 1
    fi
    return 0
}

assert_exit_code() {
    local expected="$1"
    local actual="$2"
    local message="${3:-Exit code assertion failed}"
    
    if [[ "$expected" != "$actual" ]]; then
        test_fail "$message: expected exit code $expected, got $actual"
        return 1
    fi
    return 0
}

assert_file_exists() {
    local file="$1"
    local message="${2:-File assertion failed}"
    
    if [[ ! -f "$file" ]]; then
        test_fail "$message: file '$file' does not exist"
        return 1
    fi
    return 0
}

assert_file_not_exists() {
    local file="$1"
    local message="${2:-File assertion failed}"
    
    if [[ -f "$file" ]]; then
        test_fail "$message: file '$file' exists"
        return 1
    fi
    return 0
}

# Test execution helpers
run_test() {
    local test_name="$1"
    local test_function="$2"
    
    # Check if test matches filter
    if [[ -n "$TEST_FILTER" ]] && [[ "$test_name" != *"$TEST_FILTER"* ]]; then
        return 0
    fi
    
    TESTS_RUN=$((TESTS_RUN + 1))
    
    if [[ "$QUIET" != "true" ]]; then
        echo -n "  Running $test_name... "
    fi
    
    # Create test-specific temp dir
    local test_tmp="$TEST_TMP_DIR/$test_name"
    mkdir -p "$test_tmp"
    cd "$test_tmp"
    
    # Run test in subshell to isolate it
    local test_output
    local test_exit_code=0
    
    if [[ "$VERBOSE" == "true" ]]; then
        echo ""
        (
            set +e
            $test_function
        )
        test_exit_code=$?
    else
        test_output=$(
            set +e
            $test_function 2>&1
        )
        test_exit_code=$?
    fi
    
    # Check result
    if [[ $test_exit_code -eq 0 ]]; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        if [[ "$QUIET" != "true" ]]; then
            print_success "PASS"
        fi
    elif [[ $test_exit_code -eq 2 ]]; then
        TESTS_SKIPPED=$((TESTS_SKIPPED + 1))
        if [[ "$QUIET" != "true" ]]; then
            print_warning "SKIP"
        fi
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        print_error "FAIL"
        if [[ -n "${test_output:-}" ]] && [[ "$VERBOSE" != "true" ]]; then
            echo "$test_output" | sed 's/^/    /'
        fi
    fi
    
    # Return to test root
    cd "$SCRIPT_DIR"
    
    return $test_exit_code
}

# Test lifecycle
test_skip() {
    local reason="${1:-Test skipped}"
    if [[ "$VERBOSE" == "true" ]]; then
        echo "    SKIPPED: $reason"
    fi
    exit 2
}

test_fail() {
    local reason="${1:-Test failed}"
    if [[ "$VERBOSE" == "true" ]]; then
        echo "    FAILED: $reason"
    fi
    return 1
}

################################################################################
# Test Discovery
################################################################################

# Find all test files
find_test_files() {
    local test_dir="$1"
    local pattern="${2:-test_*.sh}"
    
    find "$test_dir" -name "$pattern" -type f | sort
}

# Load and run test file
run_test_file() {
    local test_file="$1"
    local test_name=$(basename "$test_file" .sh)
    
    if [[ "$QUIET" != "true" ]]; then
        print_header "$test_name" 60
    fi
    
    # Source test file
    source "$test_file"
    
    # Find and run all test functions
    local test_functions=$(declare -F | grep "^declare -f test_" | awk '{print $3}' | grep -vE "^(test_fail|test_skip)$")
    
    for func in $test_functions; do
        run_test "$func" "$func" || true
    done
    
    # Unset test functions to avoid conflicts
    for func in $test_functions; do
        unset -f "$func"
    done
}

################################################################################
# Coverage Analysis
################################################################################

# Generate coverage report
generate_coverage() {
    print_info "Generating coverage report..."
    
    # Find all script files
    local scripts=$(find "$PROJECT_ROOT/scripts" -name "*.sh" -type f)
    local total_lines=0
    local covered_lines=0
    
    # This is a placeholder - real coverage would require instrumentation
    # For now, just count which scripts have tests
    for script in $scripts; do
        local script_name=$(basename "$script" .sh)
        local test_file="$SCRIPT_DIR/unit/test_${script_name}.sh"
        
        local lines=$(wc -l < "$script")
        ((total_lines += lines))
        
        if [[ -f "$test_file" ]]; then
            # Assume 80% coverage if test exists
            ((covered_lines += lines * 80 / 100))
        fi
    done
    
    local coverage=0
    if [[ $total_lines -gt 0 ]]; then
        coverage=$(( covered_lines * 100 / total_lines ))
    fi
    
    echo ""
    echo "Coverage Report:"
    echo "  Total lines: $total_lines"
    echo "  Covered lines: $covered_lines (estimated)"
    echo "  Coverage: $coverage%"
}

################################################################################
# Performance Testing
################################################################################

# Run performance benchmark
run_benchmark() {
    local name="$1"
    local command="$2"
    local iterations="${3:-10}"
    
    print_info "Benchmarking: $name"
    
    local total_time=0
    local min_time=999999
    local max_time=0
    
    for ((i=1; i<=iterations; i++)); do
        local start=$(date +%s%N)
        eval "$command" > /dev/null 2>&1
        local end=$(date +%s%N)
        
        local duration=$(( (end - start) / 1000000 ))
        ((total_time += duration))
        
        [[ $duration -lt $min_time ]] && min_time=$duration
        [[ $duration -gt $max_time ]] && max_time=$duration
    done
    
    local avg_time=$(( total_time / iterations ))
    
    echo "  Iterations: $iterations"
    echo "  Average: ${avg_time}ms"
    echo "  Min: ${min_time}ms"
    echo "  Max: ${max_time}ms"
}

################################################################################
# Usage and Help
################################################################################

show_usage() {
    cat << EOF
${WHITE}Awesome Bash Scripts Test Runner${NC}

${CYAN}Usage:${NC}
    $(basename "$0") [OPTIONS] [TEST_PATTERN]

${CYAN}Options:${NC}
    -h, --help          Show this help message
    -v, --verbose       Verbose output (show test details)
    -q, --quiet         Quiet mode (only show failures)
    -u, --unit          Run unit tests only
    -i, --integration   Run integration tests only  
    -p, --performance   Run performance benchmarks
    -c, --coverage      Generate coverage report
    -f, --filter PATTERN  Filter tests by pattern
    --no-color          Disable colored output

${CYAN}Examples:${NC}
    # Run all tests
    $(basename "$0")
    
    # Run only unit tests
    $(basename "$0") --unit
    
    # Run tests matching pattern
    $(basename "$0") --filter "backup"
    
    # Run with coverage report
    $(basename "$0") --coverage
    
    # Run performance benchmarks
    $(basename "$0") --performance

${CYAN}Test Structure:${NC}
    tests/
    ├── unit/           Unit tests for individual functions
    ├── integration/    Integration tests for full scripts
    ├── fixtures/       Test data and fixtures
    └── test-runner.sh  This test runner

EOF
}

################################################################################
# Main Execution
################################################################################

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)
            show_usage
            exit 0
            ;;
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        -q|--quiet)
            QUIET=true
            shift
            ;;
        -u|--unit)
            TEST_TYPE="unit"
            shift
            ;;
        -i|--integration)
            TEST_TYPE="integration"
            shift
            ;;
        -p|--performance)
            PERFORMANCE=true
            shift
            ;;
        -c|--coverage)
            SHOW_COVERAGE=true
            shift
            ;;
        -f|--filter)
            TEST_FILTER="$2"
            shift 2
            ;;
        --no-color)
            NO_COLOR=true
            export NO_COLOR
            shift
            ;;
        *)
            TEST_FILTER="$1"
            shift
            ;;
    esac
done

# Main execution
main() {
    print_header "Awesome Bash Scripts Test Runner" 60
    
    # Initialize test environment
    init_test_env
    
    # Set cleanup trap
    trap cleanup_test_env EXIT INT TERM
    
    # Run tests based on type
    case "$TEST_TYPE" in
        unit)
            print_info "Running unit tests..."
            for test_file in $(find_test_files "$SCRIPT_DIR/unit"); do
                run_test_file "$test_file"
            done
            ;;
        integration)
            print_info "Running integration tests..."
            for test_file in $(find_test_files "$SCRIPT_DIR/integration"); do
                run_test_file "$test_file"
            done
            ;;
        all)
            print_info "Running all tests..."
            
            # Unit tests
            if [[ -d "$SCRIPT_DIR/unit" ]]; then
                print_subheader "Unit Tests"
                for test_file in $(find_test_files "$SCRIPT_DIR/unit"); do
                    run_test_file "$test_file"
                done
            fi
            
            # Integration tests
            if [[ -d "$SCRIPT_DIR/integration" ]]; then
                echo ""
                print_subheader "Integration Tests"
                for test_file in $(find_test_files "$SCRIPT_DIR/integration"); do
                    run_test_file "$test_file"
                done
            fi
            ;;
    esac
    
    # Run performance tests if requested
    if [[ "$PERFORMANCE" == "true" ]]; then
        echo ""
        print_subheader "Performance Benchmarks"
        # Add performance tests here
    fi
    
    # Calculate test duration
    local end_time=$(date +%s)
    local duration=$(( end_time - START_TIME ))
    
    # Show summary
    echo ""
    print_separator "=" 60
    echo "Test Summary:"
    echo "  Total: $TESTS_RUN"
    echo "  ${COLOR_SUCCESS}Passed: $TESTS_PASSED${NC}"
    if [[ $TESTS_FAILED -gt 0 ]]; then
        echo "  ${COLOR_ERROR}Failed: $TESTS_FAILED${NC}"
    else
        echo "  Failed: 0"
    fi
    if [[ $TESTS_SKIPPED -gt 0 ]]; then
        echo "  ${COLOR_WARNING}Skipped: $TESTS_SKIPPED${NC}"
    fi
    echo "  Duration: $(format_duration $duration)"
    
    # Generate coverage if requested
    if [[ "$SHOW_COVERAGE" == "true" ]]; then
        generate_coverage
    fi
    
    # Exit with appropriate code
    if [[ $TESTS_FAILED -gt 0 ]]; then
        echo ""
        print_error "Tests failed!"
        exit 1
    else
        echo ""
        print_success "All tests passed!"
        exit 0
    fi
}

# Run main
main

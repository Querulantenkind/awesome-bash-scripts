#!/bin/bash

################################################################################
# Integration Tests for system-monitor.sh
################################################################################

# Path to the script being tested
readonly SCRIPT="$PROJECT_ROOT/scripts/monitoring/system-monitor.sh"

test_help_option() {
    local output
    output=$("$SCRIPT" --help 2>&1)
    local exit_code=$?
    
    assert_exit_code 0 "$exit_code" "Help should exit with 0"
    assert_contains "$output" "Usage:" "Help should contain usage"
    assert_contains "$output" "Options:" "Help should contain options"
}

test_basic_execution() {
    # Skip if running in CI without proper permissions
    if [[ -n "${CI:-}" ]]; then
        test_skip "Skipping in CI environment"
    fi
    
    local output
    output=$("$SCRIPT" --once 2>&1)
    local exit_code=$?
    
    assert_exit_code 0 "$exit_code" "Basic execution should succeed"
    assert_contains "$output" "SYSTEM RESOURCE MONITOR" "Should show header"
    assert_contains "$output" "CPU Usage:" "Should show CPU usage"
    assert_contains "$output" "Memory:" "Should show memory info"
}

test_json_output() {
    local output
    output=$("$SCRIPT" --json --once 2>&1)
    local exit_code=$?
    
    assert_exit_code 0 "$exit_code" "JSON output should succeed"
    
    # Basic JSON structure validation
    assert_contains "$output" '"cpu":' "JSON should contain CPU data"
    assert_contains "$output" '"memory":' "JSON should contain memory data"
    assert_contains "$output" '"timestamp":' "JSON should contain timestamp"
    
    # Validate it's valid JSON
    if command -v jq &> /dev/null; then
        echo "$output" | jq . > /dev/null 2>&1
        assert_exit_code 0 "$?" "Output should be valid JSON"
    fi
}

test_quiet_mode() {
    local output
    output=$("$SCRIPT" --quiet --once 2>&1)
    local exit_code=$?
    
    assert_exit_code 0 "$exit_code" "Quiet mode should succeed"
    
    # In quiet mode with --once, there should be minimal output
    local line_count=$(echo "$output" | wc -l)
    assert_true "[[ $line_count -le 10 ]]" "Quiet mode should have minimal output"
}

test_invalid_threshold() {
    local output
    output=$("$SCRIPT" --cpu-alert 101 2>&1)
    local exit_code=$?
    
    assert_exit_code 1 "$exit_code" "Invalid threshold should fail"
    assert_contains "$output" "Invalid" "Should show error message"
}

test_network_monitoring() {
    # Check if we have network interfaces
    if [[ -z "$(ls /sys/class/net/ | grep -v lo)" ]]; then
        test_skip "No network interfaces available"
    fi
    
    local output
    output=$("$SCRIPT" --network --once 2>&1)
    local exit_code=$?
    
    assert_exit_code 0 "$exit_code" "Network monitoring should succeed"
    assert_contains "$output" "Network:" "Should show network section"
}

test_process_monitoring() {
    local output
    output=$("$SCRIPT" --processes --once 2>&1)
    local exit_code=$?
    
    assert_exit_code 0 "$exit_code" "Process monitoring should succeed"
    assert_contains "$output" "Top Processes:" "Should show process section"
}

test_log_file_creation() {
    local log_file="$TEST_TMP_DIR/monitor.log"
    
    "$SCRIPT" --log-file "$log_file" --once > /dev/null 2>&1
    local exit_code=$?
    
    assert_exit_code 0 "$exit_code" "Logging should succeed"
    assert_file_exists "$log_file" "Log file should be created"
    
    # Check log content
    local log_content=$(cat "$log_file")
    assert_contains "$log_content" "CPU:" "Log should contain CPU info"
}

test_multiple_options() {
    local output
    output=$("$SCRIPT" --verbose --network --processes --once 2>&1)
    local exit_code=$?
    
    assert_exit_code 0 "$exit_code" "Multiple options should work"
    assert_contains "$output" "Verbose mode enabled" "Should show verbose message"
    assert_contains "$output" "Network:" "Should show network info"
    assert_contains "$output" "Top Processes:" "Should show process info"
}

test_config_file() {
    # Create a test config file
    local config_file="$TEST_TMP_DIR/monitor.conf"
    cat > "$config_file" << EOF
# Test configuration
CPU_ALERT_THRESHOLD=50
MEM_ALERT_THRESHOLD=60
DISK_ALERT_THRESHOLD=70
EOF
    
    local output
    output=$("$SCRIPT" --config "$config_file" --once 2>&1)
    local exit_code=$?
    
    assert_exit_code 0 "$exit_code" "Config file loading should succeed"
    # The script should load but we can't easily verify thresholds without alerts
}

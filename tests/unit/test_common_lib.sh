#!/bin/bash

################################################################################
# Unit Tests for common.sh library
################################################################################

# Source the library being tested
source "$PROJECT_ROOT/lib/common.sh"

# Test validation functions
test_validate_ip() {
    # Valid IPs
    assert_true $(validate_ip "192.168.1.1" && echo true || echo false) "Valid IP should pass"
    assert_true $(validate_ip "10.0.0.1" && echo true || echo false) "Valid IP should pass"
    assert_true $(validate_ip "255.255.255.255" && echo true || echo false) "Valid IP should pass"
    
    # Invalid IPs
    assert_false $(validate_ip "256.1.1.1" && echo true || echo false) "Invalid octet should fail"
    assert_false $(validate_ip "192.168.1" && echo true || echo false) "Incomplete IP should fail"
    assert_false $(validate_ip "192.168.1.1.1" && echo true || echo false) "Too many octets should fail"
    assert_false $(validate_ip "not.an.ip.addr" && echo true || echo false) "Non-numeric should fail"
}

test_validate_port() {
    # Valid ports
    assert_true $(validate_port "80" && echo true || echo false) "Port 80 should be valid"
    assert_true $(validate_port "443" && echo true || echo false) "Port 443 should be valid"
    assert_true $(validate_port "65535" && echo true || echo false) "Port 65535 should be valid"
    assert_true $(validate_port "1" && echo true || echo false) "Port 1 should be valid"
    
    # Invalid ports
    assert_false $(validate_port "0" && echo true || echo false) "Port 0 should be invalid"
    assert_false $(validate_port "65536" && echo true || echo false) "Port 65536 should be invalid"
    assert_false $(validate_port "-1" && echo true || echo false) "Negative port should be invalid"
    assert_false $(validate_port "abc" && echo true || echo false) "Non-numeric port should be invalid"
}

test_validate_email() {
    # Valid emails
    assert_true $(validate_email "user@example.com" && echo true || echo false) "Standard email should be valid"
    assert_true $(validate_email "user.name@example.co.uk" && echo true || echo false) "Email with dots should be valid"
    assert_true $(validate_email "user+tag@example.com" && echo true || echo false) "Email with plus should be valid"
    
    # Invalid emails
    assert_false $(validate_email "notanemail" && echo true || echo false) "String without @ should be invalid"
    assert_false $(validate_email "@example.com" && echo true || echo false) "Email without user should be invalid"
    assert_false $(validate_email "user@" && echo true || echo false) "Email without domain should be invalid"
}

# Test string manipulation functions
test_trim() {
    assert_equals "hello" "$(trim "  hello  ")" "Should trim spaces"
    assert_equals "hello world" "$(trim "hello world")" "Should preserve internal spaces"
    assert_equals "hello" "$(trim $'\t\nhello\n\t')" "Should trim tabs and newlines"
    assert_equals "" "$(trim "   ")" "Should return empty for only spaces"
}

test_to_lower() {
    assert_equals "hello" "$(to_lower "HELLO")" "Should convert to lowercase"
    assert_equals "hello world" "$(to_lower "Hello World")" "Should handle mixed case"
    assert_equals "123abc" "$(to_lower "123ABC")" "Should handle alphanumeric"
}

test_to_upper() {
    assert_equals "HELLO" "$(to_upper "hello")" "Should convert to uppercase"
    assert_equals "HELLO WORLD" "$(to_upper "Hello World")" "Should handle mixed case"
    assert_equals "123ABC" "$(to_upper "123abc")" "Should handle alphanumeric"
}

test_contains() {
    assert_true $(contains "hello world" "world" && echo true || echo false) "Should find substring"
    assert_false $(contains "hello world" "foo" && echo true || echo false) "Should not find missing substring"
    assert_true $(contains "hello world" "hello" && echo true || echo false) "Should find at start"
    assert_true $(contains "hello world" "world" && echo true || echo false) "Should find at end"
}

# Test formatting functions
test_human_readable_size() {
    assert_equals "0B" "$(human_readable_size 0)" "Zero bytes"
    assert_equals "100B" "$(human_readable_size 100)" "Small bytes"
    assert_equals "1.0KB" "$(human_readable_size 1024)" "Exactly 1KB"
    assert_equals "1.5KB" "$(human_readable_size 1536)" "1.5KB"
    assert_equals "1.0MB" "$(human_readable_size 1048576)" "Exactly 1MB"
    assert_equals "1.0GB" "$(human_readable_size 1073741824)" "Exactly 1GB"
}

test_format_duration() {
    assert_equals "0s" "$(format_duration 0)" "Zero seconds"
    assert_equals "30s" "$(format_duration 30)" "30 seconds"
    assert_equals "1m 30s" "$(format_duration 90)" "1 minute 30 seconds"
    assert_equals "1h 0s" "$(format_duration 3600)" "1 hour"
    assert_equals "1d 1h 1m 1s" "$(format_duration 90061)" "Complex duration"
}

# Test file operations
test_create_temp_file() {
    local temp_file=$(create_temp_file "test")
    assert_true $([[ -f "$temp_file" ]] && echo true || echo false) "Temp file should exist"
    assert_contains "$temp_file" "/tmp/test" "Should have correct prefix"
    rm -f "$temp_file"
}

test_create_temp_dir() {
    local temp_dir=$(create_temp_dir "test")
    assert_true $([[ -d "$temp_dir" ]] && echo true || echo false) "Temp dir should exist"
    assert_contains "$temp_dir" "/tmp/test" "Should have correct prefix"
    rm -rf "$temp_dir"
}

# Test system checks
test_command_exists() {
    assert_true $(command_exists "ls" && echo true || echo false) "ls should exist"
    assert_true $(command_exists "echo" && echo true || echo false) "echo should exist"
    assert_false $(command_exists "this_command_does_not_exist" && echo true || echo false) "Fake command should not exist"
}

test_is_root() {
    # This test will always fail for non-root users, skip if not root
    if [[ $EUID -ne 0 ]]; then
        test_skip "Not running as root"
    else
        assert_true $(is_root && echo true || echo false) "Should detect root user"
    fi
}

test_get_cpu_count() {
    local cpus=$(get_cpu_count)
    assert_true $([[ "$cpus" =~ ^[0-9]+$ ]] && echo true || echo false) "CPU count should be a number"
    assert_true $([[ $cpus -ge 1 ]] && echo true || echo false) "Should have at least 1 CPU"
}

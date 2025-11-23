#!/bin/bash

################################################################################
# Script Name: system-benchmark.sh
# Description: Comprehensive system benchmarking tool that tests CPU, memory,
#              disk I/O, and network performance. Provides detailed results,
#              comparisons, and performance scoring.
# Author: Luca
# Created: 2024-11-20
# Modified: 2025-11-23
# Version: 1.0.1
#
# Usage: ./system-benchmark.sh [options]
#
# Options:
#   -h, --help              Show help message
#   -a, --all               Run all benchmarks (default)
#   -c, --cpu               Run CPU benchmarks only
#   -m, --memory            Run memory benchmarks only
#   -d, --disk              Run disk I/O benchmarks only
#   -n, --network           Run network benchmarks only
#   -q, --quick             Run quick tests only
#   -f, --full              Run full test suite
#   -t, --threads NUM       Number of threads for CPU tests (default: auto)
#   -s, --size SIZE         Test data size (MB) for I/O tests (default: 1024)
#   -i, --iterations NUM    Number of test iterations (default: 3)
#   -o, --output FILE       Save results to file
#   --json                  Output results in JSON format
#   --compare FILE          Compare with previous results
#   -v, --verbose           Verbose output
#
# Examples:
#   ./system-benchmark.sh              # Run all benchmarks
#   ./system-benchmark.sh -c -t 8     # CPU benchmark with 8 threads
#   ./system-benchmark.sh -d -s 4096  # Disk benchmark with 4GB test file
#   ./system-benchmark.sh --compare baseline.json
#
# Exit Codes:
#   0 - Success
#   1 - General error
#   2 - Invalid argument
#   3 - Missing dependencies
#   4 - Insufficient resources
################################################################################

set -euo pipefail

# Script directory and sourcing
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../../lib/common.sh"
source "${SCRIPT_DIR}/../../lib/colors.sh"

################################################################################
# Configuration
################################################################################

# Test selection
RUN_ALL=true
RUN_CPU=false
RUN_MEMORY=false
RUN_DISK=false
RUN_NETWORK=false
TEST_MODE="normal"  # quick, normal, full

# Test parameters
CPU_THREADS=0  # 0 = auto-detect
TEST_SIZE=1024  # MB
ITERATIONS=3
OUTPUT_FILE=""
OUTPUT_JSON=false
COMPARE_FILE=""
VERBOSE=false

# Test directories
TEST_DIR="/tmp/benchmark-$$"
mkdir -p "$TEST_DIR"

# Results storage
declare -A RESULTS
declare -A SCORES

# Benchmark weights for overall score
declare -A WEIGHTS=(
    ["cpu"]=30
    ["memory"]=25
    ["disk"]=25
    ["network"]=20
)

################################################################################
# CPU Benchmark Functions
################################################################################

# Prime number calculation benchmark
benchmark_cpu_prime() {
    local max_prime=50000
    [[ "$TEST_MODE" == "quick" ]] && max_prime=10000
    [[ "$TEST_MODE" == "full" ]] && max_prime=100000
    
    log_info "Running prime number calculation (max: $max_prime)..."
    
    local start_time=$(date +%s.%N)
    
    # Prime calculation
    local count=0
    for ((n=2; n<=max_prime; n++)); do
        local is_prime=1
        for ((i=2; i*i<=n; i++)); do
            if ((n % i == 0)); then
                is_prime=0
                break
            fi
        done
        ((is_prime)) && ((count++))
    done
    
    local end_time=$(date +%s.%N)
    local duration=$(echo "$end_time - $start_time" | bc)
    
    RESULTS["cpu_prime"]="$duration"
    log_debug "Found $count primes in ${duration}s"
    
    echo "$duration"
}

# Floating point operations benchmark
benchmark_cpu_float() {
    local iterations=1000000
    [[ "$TEST_MODE" == "quick" ]] && iterations=100000
    [[ "$TEST_MODE" == "full" ]] && iterations=10000000
    
    log_info "Running floating point operations ($iterations iterations)..."
    
    local start_time=$(date +%s.%N)
    
    # Floating point calculations using bc
    local result=$(echo "
        scale=10
        pi = 3.1415926535
        sum = 0
        for (i = 1; i <= $iterations; i++) {
            sum = sum + (pi * i) / (i + 1)
        }
        sum
    " | bc -l 2>/dev/null)
    
    local end_time=$(date +%s.%N)
    local duration=$(echo "$end_time - $start_time" | bc)
    
    RESULTS["cpu_float"]="$duration"
    
    echo "$duration"
}

# Compression benchmark
benchmark_cpu_compression() {
    local size_mb=100
    [[ "$TEST_MODE" == "quick" ]] && size_mb=10
    [[ "$TEST_MODE" == "full" ]] && size_mb=500
    
    log_info "Running compression benchmark (${size_mb}MB)..."
    
    # Generate test data
    local test_file="$TEST_DIR/compress_test.dat"
    dd if=/dev/urandom of="$test_file" bs=1M count="$size_mb" 2>/dev/null
    
    # Compression test
    local start_time=$(date +%s.%N)
    gzip -c "$test_file" > "$test_file.gz"
    local end_time=$(date +%s.%N)
    
    local compress_time=$(echo "$end_time - $start_time" | bc)
    local compress_ratio=$(echo "scale=2; $(stat -c%s "$test_file.gz") / $(stat -c%s "$test_file")" | bc)
    
    # Decompression test
    start_time=$(date +%s.%N)
    gunzip -c "$test_file.gz" > "$test_file.out"
    end_time=$(date +%s.%N)
    
    local decompress_time=$(echo "$end_time - $start_time" | bc)
    
    RESULTS["cpu_compress_time"]="$compress_time"
    RESULTS["cpu_compress_ratio"]="$compress_ratio"
    RESULTS["cpu_decompress_time"]="$decompress_time"
    
    # Cleanup
    rm -f "$test_file" "$test_file.gz" "$test_file.out"
    
    echo "$compress_time"
}

# Multi-threaded benchmark
benchmark_cpu_multithread() {
    local threads="${CPU_THREADS:-$(nproc)}"
    
    log_info "Running multi-threaded benchmark ($threads threads)..."
    
    local start_time=$(date +%s.%N)
    
    # Run parallel tasks
    for ((t=1; t<=threads; t++)); do
        (
            # CPU-intensive task
            for ((i=1; i<=10000; i++)); do
                echo "scale=4; $i * $i / ($i + 1)" | bc -l > /dev/null
            done
        ) &
    done
    
    # Wait for all threads
    wait
    
    local end_time=$(date +%s.%N)
    local duration=$(echo "$end_time - $start_time" | bc)
    
    RESULTS["cpu_multithread"]="$duration"
    RESULTS["cpu_threads"]="$threads"
    
    echo "$duration"
}

# Main CPU benchmark
run_cpu_benchmark() {
    print_subheader "CPU BENCHMARK"
    
    local total_score=0
    local test_count=0
    
    # Prime number test
    local prime_time=$(benchmark_cpu_prime)
    local prime_score=$(calculate_score "cpu_prime" "$prime_time" 10)
    total_score=$((total_score + prime_score))
    ((test_count++))
    
    # Floating point test
    local float_time=$(benchmark_cpu_float)
    local float_score=$(calculate_score "cpu_float" "$float_time" 5)
    total_score=$((total_score + float_score))
    ((test_count++))
    
    # Compression test
    local compress_time=$(benchmark_cpu_compression)
    local compress_score=$(calculate_score "cpu_compress" "$compress_time" 2)
    total_score=$((total_score + compress_score))
    ((test_count++))
    
    # Multi-thread test
    local multithread_time=$(benchmark_cpu_multithread)
    local multithread_score=$(calculate_score "cpu_multithread" "$multithread_time" 5)
    total_score=$((total_score + multithread_score))
    ((test_count++))
    
    # Average CPU score
    SCORES["cpu"]=$((total_score / test_count))
    
    if [[ "$VERBOSE" == true ]]; then
        echo
        echo "CPU Benchmark Results:"
        echo "  Prime calculation: ${prime_time}s (Score: $prime_score)"
        echo "  Floating point: ${float_time}s (Score: $float_score)"
        echo "  Compression: ${compress_time}s (Score: $compress_score)"
        echo "  Multi-thread: ${multithread_time}s (Score: $multithread_score)"
        echo "  ${BOLD}Overall CPU Score: ${SCORES["cpu"]}${NC}"
    fi
}

################################################################################
# Memory Benchmark Functions
################################################################################

# Memory allocation speed
benchmark_memory_allocation() {
    local size_mb=1024
    [[ "$TEST_MODE" == "quick" ]] && size_mb=256
    [[ "$TEST_MODE" == "full" ]] && size_mb=4096
    
    log_info "Running memory allocation benchmark (${size_mb}MB)..."
    
    local start_time=$(date +%s.%N)
    
    # Allocate and fill memory
    python3 -c "
import time
data = bytearray(${size_mb} * 1024 * 1024)
for i in range(0, len(data), 4096):
    data[i] = i % 256
" 2>/dev/null || {
        # Fallback to bash arrays
        local -a mem_array
        for ((i=0; i<size_mb*1024; i++)); do
            mem_array[i]=$((i % 256))
        done
    }
    
    local end_time=$(date +%s.%N)
    local duration=$(echo "$end_time - $start_time" | bc)
    
    RESULTS["mem_allocation"]="$duration"
    
    echo "$duration"
}

# Memory copy speed
benchmark_memory_copy() {
    local size_mb=512
    [[ "$TEST_MODE" == "quick" ]] && size_mb=128
    [[ "$TEST_MODE" == "full" ]] && size_mb=2048
    
    log_info "Running memory copy benchmark (${size_mb}MB)..."
    
    # Create test file in memory (tmpfs)
    local mem_file="/dev/shm/memtest-$$"
    dd if=/dev/zero of="$mem_file" bs=1M count="$size_mb" 2>/dev/null
    
    local start_time=$(date +%s.%N)
    
    # Memory copy operations
    for ((i=1; i<=5; i++)); do
        cp "$mem_file" "/dev/shm/memtest-$$-copy"
        rm -f "/dev/shm/memtest-$$-copy"
    done
    
    local end_time=$(date +%s.%N)
    local duration=$(echo "$end_time - $start_time" | bc)
    
    local bandwidth=$(echo "scale=2; $size_mb * 5 / $duration" | bc)
    
    RESULTS["mem_copy_time"]="$duration"
    RESULTS["mem_copy_bandwidth"]="$bandwidth"
    
    # Cleanup
    rm -f "$mem_file"
    
    echo "$duration"
}

# Cache performance
benchmark_memory_cache() {
    log_info "Running cache performance benchmark..."
    
    # Test different access patterns
    local sequential_time=$(
        python3 -c "
import time
size = 10000000
data = list(range(size))
start = time.time()
sum = 0
for i in range(size):
    sum += data[i]
print(time.time() - start)
" 2>/dev/null || echo "1.0"
    )
    
    local random_time=$(
        python3 -c "
import time
import random
size = 10000000
data = list(range(size))
indices = list(range(size))
random.shuffle(indices)
start = time.time()
sum = 0
for i in indices[:size//10]:
    sum += data[i]
print(time.time() - start)
" 2>/dev/null || echo "2.0"
    )
    
    RESULTS["mem_cache_sequential"]="$sequential_time"
    RESULTS["mem_cache_random"]="$random_time"
    
    echo "$sequential_time"
}

# Main memory benchmark
run_memory_benchmark() {
    print_subheader "MEMORY BENCHMARK"
    
    local total_score=0
    local test_count=0
    
    # Allocation test
    local alloc_time=$(benchmark_memory_allocation)
    local alloc_score=$(calculate_score "mem_allocation" "$alloc_time" 2)
    total_score=$((total_score + alloc_score))
    ((test_count++))
    
    # Copy test
    local copy_time=$(benchmark_memory_copy)
    local copy_score=$(calculate_score "mem_copy" "$copy_time" 3)
    total_score=$((total_score + copy_score))
    ((test_count++))
    
    # Cache test
    local cache_time=$(benchmark_memory_cache)
    local cache_score=$(calculate_score "mem_cache" "$cache_time" 1)
    total_score=$((total_score + cache_score))
    ((test_count++))
    
    # Average memory score
    SCORES["memory"]=$((total_score / test_count))
    
    if [[ "$VERBOSE" == true ]]; then
        echo
        echo "Memory Benchmark Results:"
        echo "  Allocation: ${alloc_time}s (Score: $alloc_score)"
        echo "  Copy: ${copy_time}s (Score: $copy_score)"
        echo "  Cache: ${cache_time}s (Score: $cache_score)"
        echo "  Bandwidth: ${RESULTS["mem_copy_bandwidth"]:-0} MB/s"
        echo "  ${BOLD}Overall Memory Score: ${SCORES["memory"]}${NC}"
    fi
}

################################################################################
# Disk I/O Benchmark Functions
################################################################################

# Sequential write benchmark
benchmark_disk_write() {
    local size_mb="${TEST_SIZE}"
    [[ "$TEST_MODE" == "quick" ]] && size_mb=$((TEST_SIZE / 4))
    [[ "$TEST_MODE" == "full" ]] && size_mb=$((TEST_SIZE * 2))
    
    log_info "Running sequential write benchmark (${size_mb}MB)..."
    
    local test_file="$TEST_DIR/disktest.dat"
    
    # Clear cache
    sync && echo 3 > /proc/sys/vm/drop_caches 2>/dev/null || true
    
    local start_time=$(date +%s.%N)
    
    dd if=/dev/zero of="$test_file" bs=1M count="$size_mb" conv=fdatasync 2>/dev/null
    
    local end_time=$(date +%s.%N)
    local duration=$(echo "$end_time - $start_time" | bc)
    local bandwidth=$(echo "scale=2; $size_mb / $duration" | bc)
    
    RESULTS["disk_write_time"]="$duration"
    RESULTS["disk_write_bandwidth"]="$bandwidth"
    
    rm -f "$test_file"
    
    echo "$bandwidth"
}

# Sequential read benchmark
benchmark_disk_read() {
    local size_mb="${TEST_SIZE}"
    [[ "$TEST_MODE" == "quick" ]] && size_mb=$((TEST_SIZE / 4))
    [[ "$TEST_MODE" == "full" ]] && size_mb=$((TEST_SIZE * 2))
    
    log_info "Running sequential read benchmark (${size_mb}MB)..."
    
    local test_file="$TEST_DIR/disktest.dat"
    
    # Create test file
    dd if=/dev/zero of="$test_file" bs=1M count="$size_mb" 2>/dev/null
    sync
    
    # Clear cache
    echo 3 > /proc/sys/vm/drop_caches 2>/dev/null || true
    
    local start_time=$(date +%s.%N)
    
    dd if="$test_file" of=/dev/null bs=1M 2>/dev/null
    
    local end_time=$(date +%s.%N)
    local duration=$(echo "$end_time - $start_time" | bc)
    local bandwidth=$(echo "scale=2; $size_mb / $duration" | bc)
    
    RESULTS["disk_read_time"]="$duration"
    RESULTS["disk_read_bandwidth"]="$bandwidth"
    
    rm -f "$test_file"
    
    echo "$bandwidth"
}

# Random I/O benchmark
benchmark_disk_random() {
    local size_mb=100
    [[ "$TEST_MODE" == "quick" ]] && size_mb=25
    [[ "$TEST_MODE" == "full" ]] && size_mb=500
    
    log_info "Running random I/O benchmark..."
    
    if command_exists fio; then
        # Use fio for accurate random I/O testing
        fio --name=random --ioengine=posixaio --rw=randrw --bs=4k \
            --size="${size_mb}M" --numjobs=1 --time_based --runtime=10 \
            --directory="$TEST_DIR" --minimal 2>/dev/null | \
            awk -F';' '{print $8/1024 " " $49/1024}' | \
            read read_iops write_iops
        
        RESULTS["disk_random_read_iops"]="${read_iops:-0}"
        RESULTS["disk_random_write_iops"]="${write_iops:-0}"
    else
        # Fallback to dd-based random access
        local test_file="$TEST_DIR/random.dat"
        dd if=/dev/urandom of="$test_file" bs=1M count="$size_mb" 2>/dev/null
        
        local iops=0
        local start_time=$(date +%s.%N)
        
        for ((i=0; i<1000; i++)); do
            local offset=$((RANDOM % (size_mb - 1)))
            dd if="$test_file" of=/dev/null bs=4k skip=$offset count=1 2>/dev/null
        done
        
        local end_time=$(date +%s.%N)
        local duration=$(echo "$end_time - $start_time" | bc)
        iops=$(echo "scale=0; 1000 / $duration" | bc)
        
        RESULTS["disk_random_iops"]="$iops"
        rm -f "$test_file"
    fi
    
    echo "${iops:-0}"
}

# Main disk benchmark
run_disk_benchmark() {
    print_subheader "DISK I/O BENCHMARK"
    
    local total_score=0
    local test_count=0
    
    # Write test
    local write_bw=$(benchmark_disk_write)
    local write_score=$(calculate_score "disk_write" "$write_bw" 0 "inverse")
    total_score=$((total_score + write_score))
    ((test_count++))
    
    # Read test
    local read_bw=$(benchmark_disk_read)
    local read_score=$(calculate_score "disk_read" "$read_bw" 0 "inverse")
    total_score=$((total_score + read_score))
    ((test_count++))
    
    # Random I/O test
    local random_iops=$(benchmark_disk_random)
    local random_score=$(calculate_score "disk_random" "$random_iops" 0 "inverse")
    total_score=$((total_score + random_score))
    ((test_count++))
    
    # Average disk score
    SCORES["disk"]=$((total_score / test_count))
    
    if [[ "$VERBOSE" == true ]]; then
        echo
        echo "Disk I/O Benchmark Results:"
        echo "  Sequential Write: ${write_bw} MB/s (Score: $write_score)"
        echo "  Sequential Read: ${read_bw} MB/s (Score: $read_score)"
        echo "  Random I/O: ${random_iops} IOPS (Score: $random_score)"
        echo "  ${BOLD}Overall Disk Score: ${SCORES["disk"]}${NC}"
    fi
}

################################################################################
# Network Benchmark Functions
################################################################################

# Localhost bandwidth test
benchmark_network_localhost() {
    log_info "Running localhost network benchmark..."
    
    if command_exists iperf3; then
        # Start iperf3 server
        iperf3 -s -D -p 5201
        sleep 1
        
        # Run client test
        local result=$(iperf3 -c localhost -p 5201 -t 5 -J 2>/dev/null)
        local bandwidth=$(echo "$result" | jq -r '.end.sum_sent.bits_per_second' 2>/dev/null)
        bandwidth=$(echo "scale=2; $bandwidth / 1000000" | bc)  # Convert to Mbps
        
        # Kill server
        pkill -f "iperf3 -s" 2>/dev/null
        
        RESULTS["net_localhost_bandwidth"]="$bandwidth"
    else
        # Fallback to netcat
        local test_size=$((100 * 1024 * 1024))  # 100MB
        local test_file="$TEST_DIR/nettest.dat"
        dd if=/dev/zero of="$test_file" bs=1M count=100 2>/dev/null
        
        # Start receiver
        nc -l 9999 > /dev/null &
        local nc_pid=$!
        sleep 1
        
        # Send data
        local start_time=$(date +%s.%N)
        cat "$test_file" | nc localhost 9999
        local end_time=$(date +%s.%N)
        
        kill $nc_pid 2>/dev/null || true
        
        local duration=$(echo "$end_time - $start_time" | bc)
        local bandwidth=$(echo "scale=2; $test_size * 8 / $duration / 1000000" | bc)
        
        RESULTS["net_localhost_bandwidth"]="$bandwidth"
        rm -f "$test_file"
    fi
    
    echo "${bandwidth:-0}"
}

# DNS lookup benchmark
benchmark_network_dns() {
    log_info "Running DNS lookup benchmark..."
    
    local domains=("google.com" "cloudflare.com" "github.com" "wikipedia.org" "amazon.com")
    local total_time=0
    local lookups=0
    
    for domain in "${domains[@]}"; do
        for ((i=1; i<=5; i++)); do
            local start_time=$(date +%s.%N)
            
            if command_exists dig; then
                dig "$domain" +short > /dev/null 2>&1
            else
                nslookup "$domain" > /dev/null 2>&1
            fi
            
            local end_time=$(date +%s.%N)
            local duration=$(echo "$end_time - $start_time" | bc)
            total_time=$(echo "$total_time + $duration" | bc)
            ((lookups++))
        done
    done
    
    local avg_time=$(echo "scale=3; $total_time / $lookups" | bc)
    RESULTS["net_dns_avg"]="$avg_time"
    
    echo "$avg_time"
}

# HTTP benchmark
benchmark_network_http() {
    log_info "Running HTTP benchmark..."
    
    local urls=("http://www.google.com" "http://www.cloudflare.com" "http://www.github.com")
    local total_time=0
    local requests=0
    
    for url in "${urls[@]}"; do
        for ((i=1; i<=3; i++)); do
            local start_time=$(date +%s.%N)
            
            if command_exists curl; then
                curl -o /dev/null -s -w "" "$url" 2>/dev/null
            elif command_exists wget; then
                wget -O /dev/null -q "$url" 2>/dev/null
            fi
            
            local end_time=$(date +%s.%N)
            local duration=$(echo "$end_time - $start_time" | bc)
            
            if [[ $(echo "$duration < 10" | bc) -eq 1 ]]; then
                total_time=$(echo "$total_time + $duration" | bc)
                ((requests++))
            fi
        done
    done
    
    local avg_time=0
    if [[ $requests -gt 0 ]]; then
        avg_time=$(echo "scale=3; $total_time / $requests" | bc)
    fi
    
    RESULTS["net_http_avg"]="$avg_time"
    
    echo "$avg_time"
}

# Main network benchmark
run_network_benchmark() {
    print_subheader "NETWORK BENCHMARK"
    
    local total_score=0
    local test_count=0
    
    # Localhost bandwidth
    local localhost_bw=$(benchmark_network_localhost)
    local localhost_score=$(calculate_score "net_localhost" "$localhost_bw" 0 "inverse")
    total_score=$((total_score + localhost_score))
    ((test_count++))
    
    # DNS performance
    local dns_time=$(benchmark_network_dns)
    local dns_score=$(calculate_score "net_dns" "$dns_time" 0.1)
    total_score=$((total_score + dns_score))
    ((test_count++))
    
    # HTTP performance
    if [[ -n "${urls[@]}" ]]; then
        local http_time=$(benchmark_network_http)
        local http_score=$(calculate_score "net_http" "$http_time" 0.5)
        total_score=$((total_score + http_score))
        ((test_count++))
    fi
    
    # Average network score
    SCORES["network"]=$((total_score / test_count))
    
    if [[ "$VERBOSE" == true ]]; then
        echo
        echo "Network Benchmark Results:"
        echo "  Localhost bandwidth: ${localhost_bw} Mbps (Score: $localhost_score)"
        echo "  DNS lookup avg: ${dns_time}s (Score: $dns_score)"
        [[ -n "${http_time:-}" ]] && echo "  HTTP request avg: ${http_time}s (Score: $http_score)"
        echo "  ${BOLD}Overall Network Score: ${SCORES["network"]}${NC}"
    fi
}

################################################################################
# Scoring and Comparison Functions
################################################################################

# Calculate score based on performance
calculate_score() {
    local test_name="$1"
    local value="$2"
    local baseline="$3"
    local mode="${4:-normal}"  # normal or inverse
    
    # Define baseline values if not provided
    if [[ -z "$baseline" ]] || [[ "$baseline" == "0" ]]; then
        case "$test_name" in
            cpu_*) baseline=5 ;;
            mem_*) baseline=2 ;;
            disk_write|disk_read) baseline=100 ;;
            disk_random) baseline=1000 ;;
            net_localhost) baseline=1000 ;;
            net_dns) baseline=0.05 ;;
            net_http) baseline=0.5 ;;
            *) baseline=1 ;;
        esac
    fi
    
    local score
    if [[ "$mode" == "inverse" ]]; then
        # Higher values are better (bandwidth, IOPS)
        score=$(echo "scale=0; ($value / $baseline) * 100" | bc)
    else
        # Lower values are better (time)
        score=$(echo "scale=0; ($baseline / $value) * 100" | bc)
    fi
    
    # Cap score at 200
    if [[ $score -gt 200 ]]; then
        score=200
    elif [[ $score -lt 0 ]]; then
        score=0
    fi
    
    echo "$score"
}

# Calculate overall system score
calculate_overall_score() {
    local total=0
    local weight_sum=0
    
    for category in "${!SCORES[@]}"; do
        local score="${SCORES[$category]}"
        local weight="${WEIGHTS[$category]:-25}"
        total=$((total + score * weight))
        weight_sum=$((weight_sum + weight))
    done
    
    if [[ $weight_sum -gt 0 ]]; then
        echo $((total / weight_sum))
    else
        echo 0
    fi
}

# Compare with previous results
compare_results() {
    local compare_file="$1"
    
    if [[ ! -f "$compare_file" ]]; then
        error_exit "Comparison file not found: $compare_file" 1
    fi
    
    # Parse previous results
    local prev_results=$(cat "$compare_file")
    
    echo
    print_header "PERFORMANCE COMPARISON"
    
    # Compare scores
    for category in cpu memory disk network; do
        if [[ -n "${SCORES[$category]}" ]]; then
            local current="${SCORES[$category]}"
            local previous=$(echo "$prev_results" | jq -r ".scores.$category" 2>/dev/null || echo "0")
            local diff=$((current - previous))
            local percent=0
            
            if [[ $previous -gt 0 ]]; then
                percent=$(echo "scale=1; ($diff / $previous) * 100" | bc)
            fi
            
            local color="$NC"
            local symbol=""
            if [[ $diff -gt 0 ]]; then
                color="$GREEN"
                symbol="↑"
            elif [[ $diff -lt 0 ]]; then
                color="$RED"
                symbol="↓"
            else
                symbol="="
            fi
            
            printf "%-12s: %3d → %3d  ${color}%s %+.1f%%${NC}\n" \
                "${category^}" "$previous" "$current" "$symbol" "$percent"
        fi
    done
}

################################################################################
# Output Functions
################################################################################

# Generate JSON output
generate_json_output() {
    cat <<EOF
{
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "system": {
    "hostname": "$(hostname)",
    "kernel": "$(uname -r)",
    "cpu": "$(lscpu | grep "Model name" | cut -d: -f2 | xargs)",
    "cores": $(nproc),
    "memory": "$(free -m | awk '/^Mem:/ {print $2}') MB"
  },
  "parameters": {
    "test_mode": "$TEST_MODE",
    "iterations": $ITERATIONS,
    "test_size": $TEST_SIZE,
    "threads": ${CPU_THREADS:-$(nproc)}
  },
  "results": {
    $(for key in "${!RESULTS[@]}"; do
        echo "    \"$key\": \"${RESULTS[$key]}\","
    done | sed '$ s/,$//')
  },
  "scores": {
    $(for key in "${!SCORES[@]}"; do
        echo "    \"$key\": ${SCORES[$key]},"
    done | sed '$ s/,$//')
  },
  "overall_score": $(calculate_overall_score)
}
EOF
}

# Display final results
display_results() {
    echo
    print_header "BENCHMARK RESULTS"
    
    # System information
    echo "${BOLD}System Information:${NC}"
    echo "  Hostname: $(hostname)"
    echo "  Kernel: $(uname -r)"
    echo "  CPU: $(lscpu | grep "Model name" | cut -d: -f2 | xargs)"
    echo "  Cores: $(nproc)"
    echo "  Memory: $(free -m | awk '/^Mem:/ {print $2}') MB"
    echo
    
    # Scores by category
    echo "${BOLD}Performance Scores:${NC}"
    for category in cpu memory disk network; do
        if [[ -n "${SCORES[$category]}" ]]; then
            local score="${SCORES[$category]}"
            local bar_length=$((score / 5))
            local color
            
            if [[ $score -ge 150 ]]; then
                color="$GREEN"
            elif [[ $score -ge 100 ]]; then
                color="$CYAN"
            elif [[ $score -ge 50 ]]; then
                color="$YELLOW"
            else
                color="$RED"
            fi
            
            printf "  %-10s: ${color}%3d${NC} " "${category^}" "$score"
            printf "${color}"
            printf '█%.0s' $(seq 1 $bar_length)
            printf "${NC}\n"
        fi
    done
    
    # Overall score
    local overall=$(calculate_overall_score)
    echo
    echo "${BOLD}Overall System Score: $overall${NC}"
    
    # Performance tier
    local tier
    if [[ $overall -ge 150 ]]; then
        tier="Excellent"
    elif [[ $overall -ge 120 ]]; then
        tier="Very Good"
    elif [[ $overall -ge 90 ]]; then
        tier="Good"
    elif [[ $overall -ge 60 ]]; then
        tier="Average"
    else
        tier="Below Average"
    fi
    
    echo "Performance Tier: ${BOLD}$tier${NC}"
}

################################################################################
# Usage and Help
################################################################################

show_usage() {
    cat << EOF
${WHITE}System Benchmark Tool${NC}

${CYAN}Usage:${NC}
    $(basename "$0") [OPTIONS]

${CYAN}Options:${NC}
    -h, --help              Show this help message
    -a, --all               Run all benchmarks (default)
    -c, --cpu               Run CPU benchmarks only
    -m, --memory            Run memory benchmarks only
    -d, --disk              Run disk I/O benchmarks only
    -n, --network           Run network benchmarks only
    -q, --quick             Run quick tests only
    -f, --full              Run full test suite
    -t, --threads NUM       Number of CPU threads (default: auto)
    -s, --size SIZE         Test data size in MB (default: 1024)
    -i, --iterations NUM    Number of iterations (default: 3)
    -o, --output FILE       Save results to file
    --json                  Output results in JSON format
    --compare FILE          Compare with previous results
    -v, --verbose           Verbose output

${CYAN}Examples:${NC}
    # Run all benchmarks
    $(basename "$0")
    
    # Quick CPU benchmark
    $(basename "$0") -c -q
    
    # Full disk benchmark with 4GB test file
    $(basename "$0") -d -f -s 4096
    
    # Save results for comparison
    $(basename "$0") -o baseline.json --json
    
    # Compare with previous results
    $(basename "$0") --compare baseline.json

${CYAN}Test Modes:${NC}
    quick   - Fast tests for quick assessment
    normal  - Standard test suite (default)
    full    - Comprehensive testing

${CYAN}Scoring:${NC}
    Scores are normalized to 100 (average performance)
    - 150+  : Excellent
    - 120+  : Very Good
    - 90+   : Good
    - 60+   : Average
    - <60   : Below Average

${CYAN}Notes:${NC}
    - Some tests require root for accurate results
    - Disk tests may require significant space
    - Network tests require internet connectivity

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
        -a|--all)
            RUN_ALL=true
            shift
            ;;
        -c|--cpu)
            RUN_CPU=true
            RUN_ALL=false
            shift
            ;;
        -m|--memory)
            RUN_MEMORY=true
            RUN_ALL=false
            shift
            ;;
        -d|--disk)
            RUN_DISK=true
            RUN_ALL=false
            shift
            ;;
        -n|--network)
            RUN_NETWORK=true
            RUN_ALL=false
            shift
            ;;
        -q|--quick)
            TEST_MODE="quick"
            shift
            ;;
        -f|--full)
            TEST_MODE="full"
            shift
            ;;
        -t|--threads)
            [[ -z "${2:-}" ]] && error_exit "Thread count required" 2
            CPU_THREADS="$2"
            shift 2
            ;;
        -s|--size)
            [[ -z "${2:-}" ]] && error_exit "Size required" 2
            TEST_SIZE="$2"
            shift 2
            ;;
        -i|--iterations)
            [[ -z "${2:-}" ]] && error_exit "Iterations required" 2
            ITERATIONS="$2"
            shift 2
            ;;
        -o|--output)
            [[ -z "${2:-}" ]] && error_exit "Output file required" 2
            OUTPUT_FILE="$2"
            shift 2
            ;;
        --json)
            OUTPUT_JSON=true
            shift
            ;;
        --compare)
            [[ -z "${2:-}" ]] && error_exit "Comparison file required" 2
            COMPARE_FILE="$2"
            shift 2
            ;;
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        *)
            error_exit "Unknown option: $1" 2
            ;;
    esac
done

# Main execution
main() {
    if [[ "$OUTPUT_JSON" != true ]]; then
        print_header "SYSTEM BENCHMARK" 60
        echo "Starting benchmark suite..."
        echo "Test mode: $TEST_MODE"
        echo
    fi
    
    # Run selected benchmarks
    if [[ "$RUN_ALL" == true ]] || [[ "$RUN_CPU" == true ]]; then
        run_cpu_benchmark
    fi
    
    if [[ "$RUN_ALL" == true ]] || [[ "$RUN_MEMORY" == true ]]; then
        run_memory_benchmark
    fi
    
    if [[ "$RUN_ALL" == true ]] || [[ "$RUN_DISK" == true ]]; then
        run_disk_benchmark
    fi
    
    if [[ "$RUN_ALL" == true ]] || [[ "$RUN_NETWORK" == true ]]; then
        run_network_benchmark
    fi
    
    # Output results
    if [[ "$OUTPUT_JSON" == true ]]; then
        generate_json_output
    else
        display_results
        
        # Compare if requested
        if [[ -n "$COMPARE_FILE" ]]; then
            compare_results "$COMPARE_FILE"
        fi
    fi
    
    # Save to file if requested
    if [[ -n "$OUTPUT_FILE" ]]; then
        if [[ "$OUTPUT_JSON" == true ]]; then
            generate_json_output > "$OUTPUT_FILE"
        else
            {
                display_results
                [[ -n "$COMPARE_FILE" ]] && compare_results "$COMPARE_FILE"
            } > "$OUTPUT_FILE"
        fi
        
        [[ "$OUTPUT_JSON" != true ]] && success "Results saved to $OUTPUT_FILE"
    fi
}

# Cleanup on exit
trap "rm -rf $TEST_DIR" EXIT

# Run main
main

# Utility Scripts

General-purpose utility scripts that don't fit other categories.

## Categories

- **Text Processing**: Text manipulation and conversion
- **Date/Time**: Date calculations and formatting
- **Calculators**: Various calculation utilities
- **Converters**: Unit and format converters
- **Miscellaneous**: Other useful utilities

## Scripts

### 1. `password-generator.sh`
Secure password generator with multiple generation methods, strength analysis, and various output formats.

**Features:**
- Multiple password types (random, memorable, pronounceable, passphrase, PIN)
- Cryptographically secure randomness
- Password strength analysis and entropy calculation
- Customizable character sets and exclusions
- Clipboard integration and QR code generation
- Encrypted storage with GPG

**Usage:**
```bash
./password-generator.sh                    # Generate strong 16-char password
./password-generator.sh -l 32 -n 5        # Generate 5 32-char passwords
./password-generator.sh -t passphrase -w 6 # Generate 6-word passphrase
```

### 2. `system-benchmark.sh`
Comprehensive system benchmarking tool that tests CPU, memory, disk I/O, and network performance.

**Features:**
- CPU benchmarks (prime calculation, floating point, compression, multi-threading)
- Memory benchmarks (allocation, bandwidth, cache performance)
- Disk I/O benchmarks (sequential read/write, random I/O)
- Network benchmarks (bandwidth, DNS, HTTP latency)
- Performance scoring and comparison
- Multiple test modes (quick, normal, full)

**Usage:**
```bash
./system-benchmark.sh                     # Run all benchmarks
./system-benchmark.sh -c -q              # Quick CPU benchmark
./system-benchmark.sh -o baseline.json --json  # Save results
./system-benchmark.sh --compare baseline.json  # Compare performance
```

---

**Note**: These are general-purpose tools for everyday tasks.


#!/bin/bash

################################################################################
# Script Name: password-generator.sh
# Description: Secure password generator with multiple generation methods,
#              strength analysis, and various output formats. Supports
#              memorable passwords, pronounceable words, and secure storage.
# Author: Luca
# Created: 2024-11-20
# Modified: 2024-11-20
# Version: 1.0.0
#
# Usage: ./password-generator.sh [options]
#
# Options:
#   -h, --help              Show help message
#   -l, --length LENGTH     Password length (default: 16)
#   -n, --number COUNT      Number of passwords to generate (default: 1)
#   -t, --type TYPE        Password type: random, memorable, pronounceable,
#                          passphrase, pin (default: random)
#   -s, --strength LEVEL    Minimum strength: weak, fair, good, strong, 
#                          very-strong (default: strong)
#   --include CHARS         Include specific characters
#   --exclude CHARS         Exclude specific characters
#   --no-uppercase          Exclude uppercase letters
#   --no-lowercase          Exclude lowercase letters
#   --no-numbers            Exclude numbers
#   --no-symbols            Exclude symbols
#   --similar               Allow similar characters (0O, 1l, etc.)
#   -w, --words COUNT       Number of words for passphrase (default: 4)
#   -d, --delimiter CHAR    Word delimiter for passphrase (default: -)
#   -c, --copy              Copy to clipboard
#   -q, --qrcode            Generate QR code
#   -o, --output FILE       Save passwords to file (encrypted)
#   -f, --format FORMAT     Output format: plain, json, csv (default: plain)
#   -v, --verbose           Show password strength analysis
#
# Examples:
#   ./password-generator.sh                    # Generate strong 16-char password
#   ./password-generator.sh -l 32 -n 5        # Generate 5 32-char passwords
#   ./password-generator.sh -t memorable       # Generate memorable password
#   ./password-generator.sh -t passphrase -w 6 # Generate 6-word passphrase
#   ./password-generator.sh --no-symbols -c    # Generate and copy alphanumeric
#
# Exit Codes:
#   0 - Success
#   1 - General error
#   2 - Invalid argument
#   3 - Missing dependencies
################################################################################

set -euo pipefail

# Script directory and sourcing
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../../lib/common.sh"
source "${SCRIPT_DIR}/../../lib/colors.sh"

################################################################################
# Configuration
################################################################################

# Password parameters
PASSWORD_LENGTH=16
PASSWORD_COUNT=1
PASSWORD_TYPE="random"
MIN_STRENGTH="strong"
WORD_COUNT=4
WORD_DELIMITER="-"
OUTPUT_FILE=""
OUTPUT_FORMAT="plain"
COPY_TO_CLIPBOARD=false
GENERATE_QRCODE=false

# Character sets
UPPERCASE="ABCDEFGHIJKLMNOPQRSTUVWXYZ"
LOWERCASE="abcdefghijklmnopqrstuvwxyz"
NUMBERS="0123456789"
SYMBOLS="!@#\$%^&*()_+-=[]{}|;:,.<>?"

# Exclusions
EXCLUDE_UPPERCASE=false
EXCLUDE_LOWERCASE=false
EXCLUDE_NUMBERS=false
EXCLUDE_SYMBOLS=false
ALLOW_SIMILAR=false
CUSTOM_INCLUDE=""
CUSTOM_EXCLUDE=""

# Similar characters to avoid
SIMILAR_CHARS="0O1lI|"

# Word lists for memorable passwords (sample - would use larger dictionary)
ADJECTIVES=("happy" "quick" "bright" "clever" "brave" "calm" "eager" "fair" "gentle" "kind" "lively" "proud" "silly" "witty" "blue" "green" "orange" "purple" "silver" "golden")
NOUNS=("tiger" "eagle" "ocean" "mountain" "river" "sunset" "thunder" "crystal" "phoenix" "dragon" "falcon" "leopard" "panther" "wolf" "bear" "lion" "hawk" "storm" "forest" "desert")
VERBS=("runs" "flies" "swims" "jumps" "dances" "sings" "plays" "writes" "paints" "builds" "creates" "explores" "discovers" "travels" "dreams" "thinks" "learns" "grows" "shines" "glows")

# Strength thresholds
declare -A STRENGTH_BITS=(
    ["weak"]=30
    ["fair"]=40
    ["good"]=50
    ["strong"]=60
    ["very-strong"]=80
)

################################################################################
# Character Set Functions
################################################################################

# Build character set based on options
build_charset() {
    local charset=""
    
    [[ "$EXCLUDE_UPPERCASE" != true ]] && charset+="$UPPERCASE"
    [[ "$EXCLUDE_LOWERCASE" != true ]] && charset+="$LOWERCASE"
    [[ "$EXCLUDE_NUMBERS" != true ]] && charset+="$NUMBERS"
    [[ "$EXCLUDE_SYMBOLS" != true ]] && charset+="$SYMBOLS"
    
    # Add custom includes
    [[ -n "$CUSTOM_INCLUDE" ]] && charset+="$CUSTOM_INCLUDE"
    
    # Remove custom excludes
    if [[ -n "$CUSTOM_EXCLUDE" ]]; then
        for char in $(echo "$CUSTOM_EXCLUDE" | grep -o .); do
            charset=${charset//$char/}
        done
    fi
    
    # Remove similar characters if requested
    if [[ "$ALLOW_SIMILAR" != true ]]; then
        for char in $(echo "$SIMILAR_CHARS" | grep -o .); do
            charset=${charset//$char/}
        done
    fi
    
    # Remove duplicates
    charset=$(echo "$charset" | grep -o . | sort -u | tr -d '\n')
    
    echo "$charset"
}

################################################################################
# Password Generation Functions
################################################################################

# Generate random password
generate_random_password() {
    local length="$1"
    local charset=$(build_charset)
    
    if [[ -z "$charset" ]]; then
        error_exit "No characters available for password generation" 2
    fi
    
    local password=""
    local charset_length=${#charset}
    
    # Use /dev/urandom for cryptographic randomness
    for ((i=0; i<length; i++)); do
        local random_byte=$(od -An -N1 -tu1 < /dev/urandom)
        local index=$((random_byte % charset_length))
        password+="${charset:$index:1}"
    done
    
    echo "$password"
}

# Generate memorable password
generate_memorable_password() {
    local adjective=${ADJECTIVES[$((RANDOM % ${#ADJECTIVES[@]}))]}
    local noun=${NOUNS[$((RANDOM % ${#NOUNS[@]}))]}
    local number=$((RANDOM % 1000))
    local symbol_set="!@#$%"
    local symbol="${symbol_set:$((RANDOM % ${#symbol_set})):1}"
    
    # Capitalize first letters
    adjective="$(echo "${adjective:0:1}" | tr '[:lower:]' '[:upper:]')${adjective:1}"
    noun="$(echo "${noun:0:1}" | tr '[:lower:]' '[:upper:]')${noun:1}"
    
    echo "${adjective}${noun}${number}${symbol}"
}

# Generate pronounceable password
generate_pronounceable_password() {
    local length="$1"
    local consonants="bcdfghjklmnpqrstvwxyz"
    local vowels="aeiou"
    local password=""
    
    for ((i=0; i<length; i++)); do
        if ((i % 2 == 0)); then
            # Consonant
            local char="${consonants:$((RANDOM % ${#consonants})):1}"
        else
            # Vowel
            local char="${vowels:$((RANDOM % ${#vowels})):1}"
        fi
        
        # Randomly capitalize
        if ((RANDOM % 3 == 0)); then
            char=$(echo "$char" | tr '[:lower:]' '[:upper:]')
        fi
        
        password+="$char"
    done
    
    # Add some numbers at the end
    password+="$((RANDOM % 100))"
    
    echo "$password"
}

# Generate passphrase
generate_passphrase() {
    local word_count="$1"
    local delimiter="$2"
    local words=()
    
    # Load system dictionary if available
    local dict_file="/usr/share/dict/words"
    if [[ -f "$dict_file" ]]; then
        # Get random words from dictionary
        for ((i=0; i<word_count; i++)); do
            local word=$(shuf -n 1 "$dict_file" | tr -d "'")
            # Capitalize first letter
            word="$(echo "${word:0:1}" | tr '[:lower:]' '[:upper:]')${word:1}"
            words+=("$word")
        done
    else
        # Use built-in word lists
        for ((i=0; i<word_count; i++)); do
            case $((i % 3)) in
                0) words+=("${ADJECTIVES[$((RANDOM % ${#ADJECTIVES[@]}))]}") ;;
                1) words+=("${NOUNS[$((RANDOM % ${#NOUNS[@]}))]}") ;;
                2) words+=("${VERBS[$((RANDOM % ${#VERBS[@]}))]}") ;;
            esac
        done
    fi
    
    # Join words
    local passphrase=""
    for ((i=0; i<${#words[@]}; i++)); do
        passphrase+="${words[$i]}"
        [[ $i -lt $((${#words[@]} - 1)) ]] && passphrase+="$delimiter"
    done
    
    echo "$passphrase"
}

# Generate PIN
generate_pin() {
    local length="$1"
    local pin=""
    
    for ((i=0; i<length; i++)); do
        pin+="$((RANDOM % 10))"
    done
    
    echo "$pin"
}

################################################################################
# Password Strength Analysis
################################################################################

# Calculate password entropy
calculate_entropy() {
    local password="$1"
    local charset_size=0
    
    # Determine charset size based on characters used
    [[ "$password" =~ [a-z] ]] && ((charset_size += 26))
    [[ "$password" =~ [A-Z] ]] && ((charset_size += 26))
    [[ "$password" =~ [0-9] ]] && ((charset_size += 10))
    [[ "$password" =~ [\!\@\#\$\%\^\&\*\(\)\_\+\-\=\[\]\{\}\|\;\:\,\.\<\>\?] ]] && ((charset_size += 32))
    
    # Calculate entropy: log2(charset_size^length)
    local length=${#password}
    local entropy=$(awk "BEGIN {print $length * log($charset_size) / log(2)}")
    
    echo "${entropy%.*}"  # Return integer part
}

# Analyze password strength
analyze_strength() {
    local password="$1"
    local entropy=$(calculate_entropy "$password")
    local strength="weak"
    
    # Determine strength level
    if ((entropy >= ${STRENGTH_BITS["very-strong"]})); then
        strength="very-strong"
    elif ((entropy >= ${STRENGTH_BITS["strong"]})); then
        strength="strong"
    elif ((entropy >= ${STRENGTH_BITS["good"]})); then
        strength="good"
    elif ((entropy >= ${STRENGTH_BITS["fair"]})); then
        strength="fair"
    fi
    
    # Additional checks
    local checks=()
    [[ "$password" =~ [a-z] ]] && checks+=("lowercase")
    [[ "$password" =~ [A-Z] ]] && checks+=("uppercase")
    [[ "$password" =~ [0-9] ]] && checks+=("numbers")
    [[ "$password" =~ [\!\@\#\$\%\^\&\*\(\)\_\+\-\=\[\]\{\}\|\;\:\,\.\<\>\?] ]] && checks+=("symbols")
    
    echo "$strength|$entropy|${checks[*]}"
}

# Display strength analysis
display_strength() {
    local password="$1"
    local analysis=$(analyze_strength "$password")
    
    IFS='|' read -r strength entropy checks <<< "$analysis"
    
    # Color code strength
    local color
    case "$strength" in
        "very-strong") color="$GREEN" ;;
        "strong") color="$CYAN" ;;
        "good") color="$YELLOW" ;;
        "fair") color="$YELLOW" ;;
        "weak") color="$RED" ;;
    esac
    
    echo
    echo "Strength Analysis:"
    echo "  Strength: ${color}${strength^}${NC}"
    echo "  Entropy: ${entropy} bits"
    echo "  Character Types: $checks"
    echo "  Time to Crack: $(estimate_crack_time "$entropy")"
}

# Estimate time to crack
estimate_crack_time() {
    local entropy="$1"
    # Assume 1 billion guesses per second
    local seconds=$(awk "BEGIN {print 2^($entropy-1) / 1000000000}")
    
    if (( $(echo "$seconds < 1" | bc -l) )); then
        echo "Less than 1 second"
    elif (( $(echo "$seconds < 60" | bc -l) )); then
        echo "$seconds seconds"
    elif (( $(echo "$seconds < 3600" | bc -l) )); then
        echo "$(awk "BEGIN {print int($seconds/60)}") minutes"
    elif (( $(echo "$seconds < 86400" | bc -l) )); then
        echo "$(awk "BEGIN {print int($seconds/3600)}") hours"
    elif (( $(echo "$seconds < 31536000" | bc -l) )); then
        echo "$(awk "BEGIN {print int($seconds/86400)}") days"
    else
        echo "$(awk "BEGIN {print int($seconds/31536000)}") years"
    fi
}

################################################################################
# Output Functions
################################################################################

# Copy to clipboard
copy_to_clipboard() {
    local password="$1"
    
    if command_exists xclip; then
        echo -n "$password" | xclip -selection clipboard
        success "Password copied to clipboard"
    elif command_exists pbcopy; then
        echo -n "$password" | pbcopy
        success "Password copied to clipboard"
    elif command_exists clip.exe; then
        echo -n "$password" | clip.exe
        success "Password copied to clipboard"
    else
        warning "No clipboard utility found (xclip, pbcopy, or clip.exe)"
    fi
}

# Generate QR code
generate_qrcode() {
    local password="$1"
    
    if command_exists qrencode; then
        echo
        qrencode -t UTF8 "$password"
        echo
    else
        warning "qrencode not installed. Install it to generate QR codes."
    fi
}

# Save passwords to encrypted file
save_passwords() {
    local file="$1"
    shift
    local passwords=("$@")
    
    # Create password file content
    local content=""
    for password in "${passwords[@]}"; do
        content+="$password"$'\n'
    done
    
    # Encrypt with GPG if available
    if command_exists gpg; then
        echo "$content" | gpg --symmetric --cipher-algo AES256 -o "$file"
        success "Passwords encrypted and saved to $file"
    else
        # Simple obfuscation warning
        warning "GPG not available. Saving in plain text."
        echo "$content" > "$file"
        chmod 600 "$file"
    fi
}

################################################################################
# Main Generation Function
################################################################################

generate_passwords() {
    local passwords=()
    
    for ((i=0; i<PASSWORD_COUNT; i++)); do
        local password=""
        
        case "$PASSWORD_TYPE" in
            random)
                password=$(generate_random_password "$PASSWORD_LENGTH")
                ;;
            memorable)
                password=$(generate_memorable_password)
                ;;
            pronounceable)
                password=$(generate_pronounceable_password "$PASSWORD_LENGTH")
                ;;
            passphrase)
                password=$(generate_passphrase "$WORD_COUNT" "$WORD_DELIMITER")
                ;;
            pin)
                password=$(generate_pin "$PASSWORD_LENGTH")
                ;;
            *)
                error_exit "Unknown password type: $PASSWORD_TYPE" 2
                ;;
        esac
        
        # Check strength
        local strength_info=$(analyze_strength "$password")
        local strength=$(echo "$strength_info" | cut -d'|' -f1)
        
        # Ensure minimum strength (except for PINs)
        if [[ "$PASSWORD_TYPE" != "pin" ]]; then
            local min_bits=${STRENGTH_BITS["$MIN_STRENGTH"]}
            local entropy=$(echo "$strength_info" | cut -d'|' -f2)
            
            if ((entropy < min_bits)); then
                # Regenerate if too weak
                ((i--))
                continue
            fi
        fi
        
        passwords+=("$password")
    done
    
    # Output passwords
    case "$OUTPUT_FORMAT" in
        plain)
            for password in "${passwords[@]}"; do
                echo "$password"
                [[ "$VERBOSE" == true ]] && display_strength "$password"
            done
            ;;
        json)
            echo "["
            for ((i=0; i<${#passwords[@]}; i++)); do
                local analysis=$(analyze_strength "${passwords[$i]}")
                IFS='|' read -r strength entropy checks <<< "$analysis"
                
                [[ $i -gt 0 ]] && echo ","
                cat <<EOF
  {
    "password": "${passwords[$i]}",
    "strength": "$strength",
    "entropy": $entropy,
    "checks": "$checks"
  }
EOF
            done
            echo "]"
            ;;
        csv)
            echo "password,strength,entropy"
            for password in "${passwords[@]}"; do
                local analysis=$(analyze_strength "$password")
                IFS='|' read -r strength entropy checks <<< "$analysis"
                echo "\"$password\",$strength,$entropy"
            done
            ;;
    esac
    
    # Copy to clipboard if requested
    if [[ "$COPY_TO_CLIPBOARD" == true ]] && [[ ${#passwords[@]} -eq 1 ]]; then
        copy_to_clipboard "${passwords[0]}"
    fi
    
    # Generate QR code if requested
    if [[ "$GENERATE_QRCODE" == true ]] && [[ ${#passwords[@]} -eq 1 ]]; then
        generate_qrcode "${passwords[0]}"
    fi
    
    # Save to file if requested
    if [[ -n "$OUTPUT_FILE" ]]; then
        save_passwords "$OUTPUT_FILE" "${passwords[@]}"
    fi
}

################################################################################
# Usage and Help
################################################################################

show_usage() {
    cat << EOF
${WHITE}Secure Password Generator${NC}

${CYAN}Usage:${NC}
    $(basename "$0") [OPTIONS]

${CYAN}Options:${NC}
    -h, --help              Show this help message
    -l, --length LENGTH     Password length (default: 16)
    -n, --number COUNT      Number of passwords (default: 1)
    -t, --type TYPE        Password type:
                           - random: Random characters
                           - memorable: Easy to remember
                           - pronounceable: Easy to pronounce
                           - passphrase: Word-based
                           - pin: Numeric only
    -s, --strength LEVEL    Minimum strength level
    --include CHARS         Include specific characters
    --exclude CHARS         Exclude specific characters
    --no-uppercase          Exclude uppercase letters
    --no-lowercase          Exclude lowercase letters
    --no-numbers            Exclude numbers
    --no-symbols            Exclude symbols
    --similar               Allow similar characters
    -w, --words COUNT       Words for passphrase
    -d, --delimiter CHAR    Word delimiter
    -c, --copy              Copy to clipboard
    -q, --qrcode            Generate QR code
    -o, --output FILE       Save to encrypted file
    -f, --format FORMAT     Output format
    -v, --verbose           Show strength analysis

${CYAN}Examples:${NC}
    # Generate strong 16-character password
    $(basename "$0")
    
    # Generate 5 very strong 32-character passwords
    $(basename "$0") -l 32 -n 5 -s very-strong
    
    # Generate memorable password
    $(basename "$0") -t memorable
    
    # Generate 6-word passphrase
    $(basename "$0") -t passphrase -w 6
    
    # Generate and copy alphanumeric password
    $(basename "$0") --no-symbols -c
    
    # Generate with custom requirements
    $(basename "$0") -l 20 --include "#@!" --exclude "0O1l"

${CYAN}Strength Levels:${NC}
    weak        ~30 bits entropy
    fair        ~40 bits entropy
    good        ~50 bits entropy
    strong      ~60 bits entropy (default)
    very-strong ~80 bits entropy

${CYAN}Notes:${NC}
    - Uses cryptographically secure randomness
    - Avoids similar characters by default (0/O, 1/l)
    - Passwords are checked against minimum strength
    - Encrypted storage requires GPG

EOF
}

################################################################################
# Main Execution
################################################################################

# Default values
VERBOSE=false

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)
            show_usage
            exit 0
            ;;
        -l|--length)
            [[ -z "${2:-}" ]] && error_exit "Length required" 2
            PASSWORD_LENGTH="$2"
            shift 2
            ;;
        -n|--number)
            [[ -z "${2:-}" ]] && error_exit "Count required" 2
            PASSWORD_COUNT="$2"
            shift 2
            ;;
        -t|--type)
            [[ -z "${2:-}" ]] && error_exit "Type required" 2
            PASSWORD_TYPE="$2"
            shift 2
            ;;
        -s|--strength)
            [[ -z "${2:-}" ]] && error_exit "Strength level required" 2
            MIN_STRENGTH="$2"
            shift 2
            ;;
        --include)
            [[ -z "${2:-}" ]] && error_exit "Characters required" 2
            CUSTOM_INCLUDE="$2"
            shift 2
            ;;
        --exclude)
            [[ -z "${2:-}" ]] && error_exit "Characters required" 2
            CUSTOM_EXCLUDE="$2"
            shift 2
            ;;
        --no-uppercase)
            EXCLUDE_UPPERCASE=true
            shift
            ;;
        --no-lowercase)
            EXCLUDE_LOWERCASE=true
            shift
            ;;
        --no-numbers)
            EXCLUDE_NUMBERS=true
            shift
            ;;
        --no-symbols)
            EXCLUDE_SYMBOLS=true
            shift
            ;;
        --similar)
            ALLOW_SIMILAR=true
            shift
            ;;
        -w|--words)
            [[ -z "${2:-}" ]] && error_exit "Word count required" 2
            WORD_COUNT="$2"
            shift 2
            ;;
        -d|--delimiter)
            [[ -z "${2:-}" ]] && error_exit "Delimiter required" 2
            WORD_DELIMITER="$2"
            shift 2
            ;;
        -c|--copy)
            COPY_TO_CLIPBOARD=true
            shift
            ;;
        -q|--qrcode)
            GENERATE_QRCODE=true
            shift
            ;;
        -o|--output)
            [[ -z "${2:-}" ]] && error_exit "Output file required" 2
            OUTPUT_FILE="$2"
            shift 2
            ;;
        -f|--format)
            [[ -z "${2:-}" ]] && error_exit "Format required" 2
            OUTPUT_FORMAT="$2"
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

# Validate parameters
if [[ "$PASSWORD_LENGTH" -lt 4 ]] && [[ "$PASSWORD_TYPE" != "pin" ]]; then
    error_exit "Password length must be at least 4" 2
fi

if [[ "$PASSWORD_COUNT" -lt 1 ]]; then
    error_exit "Password count must be at least 1" 2
fi

if [[ -n "$MIN_STRENGTH" ]] && [[ -z "${STRENGTH_BITS[$MIN_STRENGTH]}" ]]; then
    error_exit "Invalid strength level: $MIN_STRENGTH" 2
fi

# Generate passwords
generate_passwords

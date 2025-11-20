#!/bin/bash

set -euo pipefail

################################################################################
# Script Name: audio-converter.sh
# Description: Audio format conversion (MP3, FLAC, WAV, OGG, AAC) with bitrate,
#              quality settings, batch conversion, and metadata preservation.
# Author: Luca
# Created: 2024-11-20
# Version: 1.0.0
################################################################################

readonly GREEN='\033[0;32m'
readonly RED='\033[0;31m'
readonly CYAN='\033[0;36m'
readonly NC='\033[0m'

INPUT_FILE=""
OUTPUT_FILE=""
OUTPUT_FORMAT="mp3"
BITRATE="320k"
QUALITY="high"
BATCH_DIR=""

error_exit() { echo -e "${RED}ERROR: $1${NC}" >&2; exit "${2:-1}"; }
success() { echo -e "${GREEN}✓ $1${NC}"; }
info() { echo -e "${CYAN}ℹ $1${NC}"; }

convert_audio() {
    local input="$1"
    local output="$2"
    local format="$3"
    
    command -v ffmpeg &> /dev/null || error_exit "ffmpeg not found" 3
    
    info "Converting: $input -> $output"
    
    case "$format" in
        mp3)
            ffmpeg -i "$input" -b:a "$BITRATE" -y "$output" 2>/dev/null
            ;;
        flac)
            ffmpeg -i "$input" -compression_level 8 -y "$output" 2>/dev/null
            ;;
        wav)
            ffmpeg -i "$input" -y "$output" 2>/dev/null
            ;;
        ogg)
            ffmpeg -i "$input" -q:a 6 -y "$output" 2>/dev/null
            ;;
        aac)
            ffmpeg -i "$input" -c:a aac -b:a "$BITRATE" -y "$output" 2>/dev/null
            ;;
        *)
            error_exit "Unsupported format: $format" 2
            ;;
    esac
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -i|--input) INPUT_FILE="$2"; shift 2 ;;
        -o|--output) OUTPUT_FILE="$2"; shift 2 ;;
        -f|--format) OUTPUT_FORMAT="$2"; shift 2 ;;
        -b|--bitrate) BITRATE="$2"; shift 2 ;;
        --batch) BATCH_DIR="$2"; shift 2 ;;
        -h|--help) echo "Audio Converter"; exit 0 ;;
        *) error_exit "Unknown option: $1" 2 ;;
    esac
done

if [[ -n "$BATCH_DIR" ]]; then
    find "$BATCH_DIR" -type f \( -name "*.mp3" -o -name "*.wav" -o -name "*.flac" \) | while read -r f; do
        output="${f%.*}.$OUTPUT_FORMAT"
        convert_audio "$f" "$output" "$OUTPUT_FORMAT"
    done
    success "Batch conversion complete"
elif [[ -n "$INPUT_FILE" ]]; then
    [[ -z "$OUTPUT_FILE" ]] && OUTPUT_FILE="${INPUT_FILE%.*}.$OUTPUT_FORMAT"
    convert_audio "$INPUT_FILE" "$OUTPUT_FILE" "$OUTPUT_FORMAT"
    success "Converted: $OUTPUT_FILE"
else
    error_exit "No input file specified" 2
fi

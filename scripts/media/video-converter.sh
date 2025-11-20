#!/bin/bash

################################################################################
# Script Name: video-converter.sh
# Description: Advanced video conversion tool using FFmpeg. Supports batch
#              conversion, preset profiles, quality settings, and format detection.
# Author: Luca
# Created: 2024-11-20
# Modified: 2024-11-20
# Version: 1.0.0
#
# Usage: ./video-converter.sh [options] <input> [output]
#
# Options:
#   -h, --help              Show help message
#   -f, --format FORMAT     Output format: mp4, mkv, avi, webm, mov (default: mp4)
#   -p, --preset PRESET     Preset: ultrafast, fast, medium, slow, veryslow
#   -q, --quality QUALITY   Quality: 0-51 (lower is better, 23 is default)
#   -r, --resolution RES    Resolution: 1920x1080, 1280x720, 854x480, etc.
#   -c, --codec CODEC       Video codec: h264, h265, vp9, av1
#   -a, --audio CODEC       Audio codec: aac, mp3, opus, vorbis
#   -b, --bitrate RATE      Video bitrate (e.g., 2M, 5000k)
#   --audio-bitrate RATE    Audio bitrate (e.g., 128k, 192k)
#   --fps FPS               Frame rate (e.g., 24, 30, 60)
#   --batch                 Batch conversion mode
#   --directory DIR         Process all videos in directory
#   --subtitle              Extract/embed subtitles
#   --metadata              Preserve metadata
#   -o, --overwrite         Overwrite existing files
#   --dry-run               Show commands without executing
#   -v, --verbose           Verbose output
#
# Examples:
#   ./video-converter.sh input.avi output.mp4
#   ./video-converter.sh -f webm -q 30 input.mkv
#   ./video-converter.sh --batch --directory ~/Videos --format mp4
#   ./video-converter.sh -r 1280x720 -b 2M input.mov output.mp4
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

# Input/Output
INPUT_FILE=""
OUTPUT_FILE=""
INPUT_DIR=""
BATCH_MODE=false

# Video settings
OUTPUT_FORMAT="mp4"
PRESET="medium"
QUALITY="23"
RESOLUTION=""
VIDEO_CODEC="h264"
AUDIO_CODEC="aac"
VIDEO_BITRATE=""
AUDIO_BITRATE="192k"
FPS=""

# Options
EXTRACT_SUBTITLES=false
PRESERVE_METADATA=true
OVERWRITE=false
DRY_RUN=false
VERBOSE=false

# Codec mapping
declare -A CODEC_MAP=(
    ["h264"]="libx264"
    ["h265"]="libx265"
    ["vp9"]="libvpx-vp9"
    ["av1"]="libaom-av1"
)

declare -A AUDIO_CODEC_MAP=(
    ["aac"]="aac"
    ["mp3"]="libmp3lame"
    ["opus"]="libopus"
    ["vorbis"]="libvorbis"
)

################################################################################
# Dependency Check
################################################################################

check_dependencies() {
    require_command ffmpeg ffmpeg
    require_command ffprobe ffmpeg
}

################################################################################
# Video Information
################################################################################

get_video_info() {
    local file="$1"
    
    if [[ ! -f "$file" ]]; then
        error_exit "File not found: $file" 1
    fi
    
    ffprobe -v quiet -print_format json -show_format -show_streams "$file"
}

display_video_info() {
    local file="$1"
    
    print_header "VIDEO INFORMATION: $(basename "$file")" 70
    
    local info=$(get_video_info "$file")
    
    # Extract information
    local duration=$(echo "$info" | jq -r '.format.duration' | awk '{printf "%.2f", $1}')
    local size=$(echo "$info" | jq -r '.format.size')
    local bitrate=$(echo "$info" | jq -r '.format.bit_rate')
    
    # Video stream info
    local video_codec=$(echo "$info" | jq -r '.streams[] | select(.codec_type=="video") | .codec_name' | head -1)
    local width=$(echo "$info" | jq -r '.streams[] | select(.codec_type=="video") | .width' | head -1)
    local height=$(echo "$info" | jq -r '.streams[] | select(.codec_type=="video") | .height' | head -1)
    local fps=$(echo "$info" | jq -r '.streams[] | select(.codec_type=="video") | .r_frame_rate' | head -1 | bc -l 2>/dev/null | awk '{printf "%.2f", $1}')
    
    # Audio stream info
    local audio_codec=$(echo "$info" | jq -r '.streams[] | select(.codec_type=="audio") | .codec_name' | head -1)
    local sample_rate=$(echo "$info" | jq -r '.streams[] | select(.codec_type=="audio") | .sample_rate' | head -1)
    local channels=$(echo "$info" | jq -r '.streams[] | select(.codec_type=="audio") | .channels' | head -1)
    
    echo
    echo -e "${BOLD}File:${NC} $(basename "$file")"
    echo -e "${BOLD}Size:${NC} $(human_readable_size $size)"
    echo -e "${BOLD}Duration:${NC} $(format_duration ${duration%.*})"
    echo -e "${BOLD}Bitrate:${NC} $((bitrate / 1000)) kbps"
    echo
    echo -e "${BOLD_CYAN}Video:${NC}"
    echo "  Codec: $video_codec"
    echo "  Resolution: ${width}x${height}"
    echo "  FPS: $fps"
    echo
    echo -e "${BOLD_CYAN}Audio:${NC}"
    echo "  Codec: $audio_codec"
    echo "  Sample Rate: $sample_rate Hz"
    echo "  Channels: $channels"
    echo
}

################################################################################
# Conversion Functions
################################################################################

build_ffmpeg_command() {
    local input="$1"
    local output="$2"
    local -a cmd=("ffmpeg")
    
    # Overwrite option
    [[ "$OVERWRITE" == true ]] && cmd+=("-y") || cmd+=("-n")
    
    # Input file
    cmd+=("-i" "$input")
    
    # Video codec
    local video_codec_lib="${CODEC_MAP[$VIDEO_CODEC]:-libx264}"
    cmd+=("-c:v" "$video_codec_lib")
    
    # Preset
    if [[ "$VIDEO_CODEC" =~ ^(h264|h265)$ ]]; then
        cmd+=("-preset" "$PRESET")
    fi
    
    # Quality/CRF
    if [[ -z "$VIDEO_BITRATE" ]]; then
        cmd+=("-crf" "$QUALITY")
    else
        cmd+=("-b:v" "$VIDEO_BITRATE")
    fi
    
    # Resolution
    if [[ -n "$RESOLUTION" ]]; then
        cmd+=("-s" "$RESOLUTION")
    fi
    
    # FPS
    if [[ -n "$FPS" ]]; then
        cmd+=("-r" "$FPS")
    fi
    
    # Audio codec
    local audio_codec_lib="${AUDIO_CODEC_MAP[$AUDIO_CODEC]:-aac}"
    cmd+=("-c:a" "$audio_codec_lib")
    cmd+=("-b:a" "$AUDIO_BITRATE")
    
    # Metadata
    if [[ "$PRESERVE_METADATA" == true ]]; then
        cmd+=("-map_metadata" "0")
    fi
    
    # Subtitles
    if [[ "$EXTRACT_SUBTITLES" == true ]]; then
        cmd+=("-c:s" "copy")
    fi
    
    # Output file
    cmd+=("$output")
    
    echo "${cmd[@]}"
}

convert_video() {
    local input="$1"
    local output="$2"
    
    if [[ ! -f "$input" ]]; then
        error "Input file not found: $input"
        return 1
    fi
    
    # Generate output filename if not provided
    if [[ -z "$output" ]]; then
        local basename=$(basename "$input")
        local filename="${basename%.*}"
        output="${filename}_converted.${OUTPUT_FORMAT}"
    fi
    
    # Check if output exists
    if [[ -f "$output" ]] && [[ "$OVERWRITE" != true ]]; then
        warning "Output file exists: $output (use -o to overwrite)"
        return 1
    fi
    
    # Build command
    local cmd=$(build_ffmpeg_command "$input" "$output")
    
    if [[ "$DRY_RUN" == true ]]; then
        echo -e "${CYAN}Would execute:${NC}"
        echo "  $cmd"
        return 0
    fi
    
    # Display info
    if [[ "$VERBOSE" == true ]]; then
        display_video_info "$input"
    fi
    
    print_header "CONVERTING: $(basename "$input")" 70
    echo
    echo -e "${BOLD}Input:${NC} $input"
    echo -e "${BOLD}Output:${NC} $output"
    echo -e "${BOLD}Format:${NC} $OUTPUT_FORMAT"
    echo -e "${BOLD}Codec:${NC} $VIDEO_CODEC / $AUDIO_CODEC"
    echo -e "${BOLD}Quality:${NC} CRF $QUALITY"
    [[ -n "$RESOLUTION" ]] && echo -e "${BOLD}Resolution:${NC} $RESOLUTION"
    echo
    
    # Start conversion
    local start_time=$(date +%s)
    
    if [[ "$VERBOSE" == true ]]; then
        eval "$cmd"
    else
        eval "$cmd" 2>&1 | grep -E "(frame=|time=|speed=)" | tail -1 || true
    fi
    
    local exit_code=$?
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    echo
    
    if [[ $exit_code -eq 0 ]]; then
        local input_size=$(stat -c%s "$input")
        local output_size=$(stat -c%s "$output")
        local ratio=$(echo "scale=2; $output_size * 100 / $input_size" | bc)
        
        success "Conversion completed in $(format_duration $duration)"
        echo "  Input size: $(human_readable_size $input_size)"
        echo "  Output size: $(human_readable_size $output_size) (${ratio}%)"
        return 0
    else
        error "Conversion failed"
        return 1
    fi
}

################################################################################
# Batch Conversion
################################################################################

batch_convert() {
    local dir="${INPUT_DIR:-.}"
    
    print_header "BATCH CONVERSION" 70
    echo
    echo -e "${BOLD}Directory:${NC} $dir"
    echo -e "${BOLD}Format:${NC} $OUTPUT_FORMAT"
    echo
    
    # Find video files
    local -a video_files=()
    while IFS= read -r -d '' file; do
        video_files+=("$file")
    done < <(find "$dir" -maxdepth 1 -type f \( -iname "*.avi" -o -iname "*.mkv" -o -iname "*.mov" -o -iname "*.wmv" -o -iname "*.flv" -o -iname "*.mp4" -o -iname "*.webm" \) -print0)
    
    if [[ ${#video_files[@]} -eq 0 ]]; then
        warning "No video files found in $dir"
        return 1
    fi
    
    info "Found ${#video_files[@]} video files"
    echo
    
    local converted=0
    local failed=0
    
    for file in "${video_files[@]}"; do
        local basename=$(basename "$file")
        local filename="${basename%.*}"
        local output="$dir/${filename}_converted.${OUTPUT_FORMAT}"
        
        if convert_video "$file" "$output"; then
            ((converted++))
        else
            ((failed++))
        fi
        
        echo
    done
    
    print_separator
    echo -e "${BOLD}Batch Conversion Complete${NC}"
    echo "  Converted: $converted"
    echo "  Failed: $failed"
}

################################################################################
# Preset Profiles
################################################################################

apply_preset_profile() {
    local profile="$1"
    
    case "$profile" in
        web-hd)
            OUTPUT_FORMAT="mp4"
            VIDEO_CODEC="h264"
            QUALITY="23"
            RESOLUTION="1920x1080"
            AUDIO_CODEC="aac"
            AUDIO_BITRATE="192k"
            info "Applied Web HD preset (1080p H.264)"
            ;;
        web-sd)
            OUTPUT_FORMAT="mp4"
            VIDEO_CODEC="h264"
            QUALITY="28"
            RESOLUTION="1280x720"
            AUDIO_CODEC="aac"
            AUDIO_BITRATE="128k"
            info "Applied Web SD preset (720p H.264)"
            ;;
        mobile)
            OUTPUT_FORMAT="mp4"
            VIDEO_CODEC="h264"
            QUALITY="28"
            RESOLUTION="854x480"
            AUDIO_CODEC="aac"
            AUDIO_BITRATE="96k"
            info "Applied Mobile preset (480p H.264)"
            ;;
        high-quality)
            OUTPUT_FORMAT="mkv"
            VIDEO_CODEC="h265"
            QUALITY="18"
            AUDIO_CODEC="aac"
            AUDIO_BITRATE="256k"
            info "Applied High Quality preset (H.265)"
            ;;
        archive)
            OUTPUT_FORMAT="mkv"
            VIDEO_CODEC="h264"
            QUALITY="18"
            AUDIO_CODEC="aac"
            AUDIO_BITRATE="192k"
            PRESERVE_METADATA=true
            EXTRACT_SUBTITLES=true
            info "Applied Archive preset"
            ;;
        *)
            warning "Unknown preset: $profile"
            ;;
    esac
}

################################################################################
# Usage and Help
################################################################################

show_usage() {
    cat << EOF
${WHITE}Video Converter - FFmpeg-based Video Conversion Tool${NC}

${CYAN}Usage:${NC}
    $(basename "$0") [OPTIONS] <input> [output]

${CYAN}Options:${NC}
    -h, --help              Show this help message
    -f, --format FORMAT     Output format: mp4, mkv, avi, webm, mov
    -p, --preset PRESET     Encoding preset: ultrafast, fast, medium, slow
    -q, --quality QUALITY   Quality (CRF): 0-51 (lower is better, 23 default)
    -r, --resolution RES    Resolution (e.g., 1920x1080, 1280x720)
    -c, --codec CODEC       Video codec: h264, h265, vp9, av1
    -a, --audio CODEC       Audio codec: aac, mp3, opus, vorbis
    -b, --bitrate RATE      Video bitrate (e.g., 2M, 5000k)
    --audio-bitrate RATE    Audio bitrate (e.g., 128k, 192k)
    --fps FPS               Frame rate
    --batch                 Batch conversion mode
    --directory DIR         Process directory
    --subtitle              Extract/embed subtitles
    --metadata              Preserve metadata (default: true)
    -o, --overwrite         Overwrite existing files
    --dry-run               Show commands without executing
    -v, --verbose           Verbose output

${CYAN}Preset Profiles:${NC}
    --profile web-hd        1080p H.264 for web
    --profile web-sd        720p H.264 for web
    --profile mobile        480p H.264 for mobile
    --profile high-quality  H.265 high quality
    --profile archive       Lossless archival

${CYAN}Examples:${NC}
    # Convert to MP4
    $(basename "$0") input.avi output.mp4
    
    # Convert with quality setting
    $(basename "$0") -q 20 input.mkv output.mp4
    
    # Resize and convert
    $(basename "$0") -r 1280x720 -f webm input.mov output.webm
    
    # Use preset profile
    $(basename "$0") --profile web-hd input.avi
    
    # Batch convert directory
    $(basename "$0") --batch --directory ~/Videos --format mp4
    
    # H.265 with custom bitrate
    $(basename "$0") -c h265 -b 2M input.mp4 output.mkv

${CYAN}Codecs:${NC}
    Video: h264 (default), h265, vp9, av1
    Audio: aac (default), mp3, opus, vorbis

${CYAN}Quality Guide:${NC}
    CRF 0-18:  Visually lossless
    CRF 18-23: High quality (recommended)
    CRF 23-28: Good quality
    CRF 28+:   Lower quality, smaller files

${CYAN}Notes:${NC}
    - Requires FFmpeg to be installed
    - Lower CRF = better quality, larger file
    - H.265 provides better compression than H.264
    - Use --verbose to see detailed progress

EOF
}

################################################################################
# Main Execution
################################################################################

# Check dependencies
check_dependencies

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)
            show_usage
            exit 0
            ;;
        -f|--format)
            [[ -z "${2:-}" ]] && error_exit "Format required" 2
            OUTPUT_FORMAT="$2"
            shift 2
            ;;
        -p|--preset)
            [[ -z "${2:-}" ]] && error_exit "Preset required" 2
            PRESET="$2"
            shift 2
            ;;
        -q|--quality)
            [[ -z "${2:-}" ]] && error_exit "Quality required" 2
            QUALITY="$2"
            shift 2
            ;;
        -r|--resolution)
            [[ -z "${2:-}" ]] && error_exit "Resolution required" 2
            RESOLUTION="$2"
            shift 2
            ;;
        -c|--codec)
            [[ -z "${2:-}" ]] && error_exit "Codec required" 2
            VIDEO_CODEC="$2"
            shift 2
            ;;
        -a|--audio)
            [[ -z "${2:-}" ]] && error_exit "Audio codec required" 2
            AUDIO_CODEC="$2"
            shift 2
            ;;
        -b|--bitrate)
            [[ -z "${2:-}" ]] && error_exit "Bitrate required" 2
            VIDEO_BITRATE="$2"
            shift 2
            ;;
        --audio-bitrate)
            [[ -z "${2:-}" ]] && error_exit "Audio bitrate required" 2
            AUDIO_BITRATE="$2"
            shift 2
            ;;
        --fps)
            [[ -z "${2:-}" ]] && error_exit "FPS required" 2
            FPS="$2"
            shift 2
            ;;
        --batch)
            BATCH_MODE=true
            shift
            ;;
        --directory)
            [[ -z "${2:-}" ]] && error_exit "Directory required" 2
            INPUT_DIR="$2"
            shift 2
            ;;
        --profile)
            [[ -z "${2:-}" ]] && error_exit "Profile required" 2
            apply_preset_profile "$2"
            shift 2
            ;;
        --subtitle)
            EXTRACT_SUBTITLES=true
            shift
            ;;
        --no-metadata)
            PRESERVE_METADATA=false
            shift
            ;;
        -o|--overwrite)
            OVERWRITE=true
            shift
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        -*)
            error_exit "Unknown option: $1" 2
            ;;
        *)
            if [[ -z "$INPUT_FILE" ]]; then
                INPUT_FILE="$1"
            else
                OUTPUT_FILE="$1"
            fi
            shift
            ;;
    esac
done

# Execute
if [[ "$BATCH_MODE" == true ]]; then
    batch_convert
else
    [[ -z "$INPUT_FILE" ]] && error_exit "Input file required" 2
    convert_video "$INPUT_FILE" "$OUTPUT_FILE"
fi

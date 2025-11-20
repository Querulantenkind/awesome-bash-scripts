#!/bin/bash

################################################################################
# Script Name: image-optimizer.sh
# Description: Batch image optimization tool that compresses and resizes images
#              while maintaining quality. Supports multiple formats and profiles.
# Author: Luca
# Created: 2024-11-20
# Modified: 2024-11-20
# Version: 1.0.0
#
# Usage: ./image-optimizer.sh [options] <input>
#
# Options:
#   -h, --help              Show help message
#   -d, --directory DIR     Process all images in directory
#   -o, --output DIR        Output directory (default: optimized/)
#   -q, --quality QUALITY   JPEG quality 0-100 (default: 85)
#   -r, --resize WIDTHxHEIGHT  Resize images
#   -f, --format FORMAT     Convert to format: jpg, png, webp
#   --max-width WIDTH       Maximum width (maintain aspect ratio)
#   --max-height HEIGHT     Maximum height (maintain aspect ratio)
#   --strip-metadata        Remove EXIF data
#   --progressive           Use progressive JPEG
#   --backup                Backup original files
#   --suffix SUFFIX         Add suffix to filename (default: _opt)
#   --recursive             Process subdirectories
#   --dry-run               Show what would be done
#   -v, --verbose           Verbose output
#
# Examples:
#   ./image-optimizer.sh -d ~/Photos -q 80
#   ./image-optimizer.sh --max-width 1920 --strip-metadata image.jpg
#   ./image-optimizer.sh -d images/ -f webp --recursive
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

INPUT_PATH=""
OUTPUT_DIR="optimized"
QUALITY=85
RESIZE=""
OUTPUT_FORMAT=""
MAX_WIDTH=""
MAX_HEIGHT=""
STRIP_METADATA=false
PROGRESSIVE=false
CREATE_BACKUP=false
SUFFIX="_opt"
RECURSIVE=false
DRY_RUN=false
VERBOSE=false

# Statistics
TOTAL_FILES=0
PROCESSED_FILES=0
FAILED_FILES=0
TOTAL_SIZE_BEFORE=0
TOTAL_SIZE_AFTER=0

################################################################################
# Dependency Check
################################################################################

check_dependencies() {
    # Check for ImageMagick or GraphicsMagick
    if ! command_exists convert && ! command_exists gm; then
        error_exit "ImageMagick or GraphicsMagick required. Install with: sudo apt install imagemagick" 3
    fi
    
    # Check for optional tools
    if command_exists jpegoptim; then
        HAVE_JPEGOPTIM=true
    else
        HAVE_JPEGOPTIM=false
    fi
    
    if command_exists optipng; then
        HAVE_OPTIPNG=true
    else
        HAVE_OPTIPNG=false
    fi
    
    if command_exists cwebp; then
        HAVE_WEBP=true
    else
        HAVE_WEBP=false
    fi
}

################################################################################
# Image Information
################################################################################

get_image_info() {
    local file="$1"
    
    if command_exists identify; then
        identify -format "%wx%h %b %m" "$file" 2>/dev/null
    else
        gm identify -format "%wx%h %b %m" "$file" 2>/dev/null
    fi
}

display_image_info() {
    local file="$1"
    
    local info=$(get_image_info "$file")
    local dimensions=$(echo "$info" | awk '{print $1}')
    local size=$(echo "$info" | awk '{print $2}')
    local format=$(echo "$info" | awk '{print $3}')
    
    echo -e "${BOLD}File:${NC} $(basename "$file")"
    echo -e "${BOLD}Format:${NC} $format"
    echo -e "${BOLD}Dimensions:${NC} $dimensions"
    echo -e "${BOLD}Size:${NC} $size"
}

################################################################################
# Optimization Functions
################################################################################

optimize_jpeg() {
    local input="$1"
    local output="$2"
    
    local -a cmd=()
    
    if [[ "$HAVE_JPEGOPTIM" == true ]] && [[ -z "$RESIZE" ]] && [[ -z "$MAX_WIDTH" ]] && [[ -z "$MAX_HEIGHT" ]]; then
        # Use jpegoptim for lossless JPEG optimization
        cmd+=("jpegoptim")
        cmd+=("-q")
        cmd+=("--max=$QUALITY")
        [[ "$STRIP_METADATA" == true ]] && cmd+=("--strip-all")
        [[ "$PROGRESSIVE" == true ]] && cmd+=("--all-progressive")
        cmd+=("--dest=$(dirname "$output")")
        cmd+=("$input")
        
        eval "${cmd[@]}"
        
        # Rename if needed
        local temp_output="$(dirname "$output")/$(basename "$input")"
        [[ "$temp_output" != "$output" ]] && mv "$temp_output" "$output"
    else
        # Use ImageMagick
        cmd+=("convert")
        cmd+=("$input")
        
        # Resize options
        if [[ -n "$RESIZE" ]]; then
            cmd+=("-resize" "$RESIZE")
        elif [[ -n "$MAX_WIDTH" ]] || [[ -n "$MAX_HEIGHT" ]]; then
            local geom=""
            [[ -n "$MAX_WIDTH" ]] && geom="${MAX_WIDTH}x"
            [[ -n "$MAX_HEIGHT" ]] && geom="${geom}${MAX_HEIGHT}"
            cmd+=("-resize" "${geom}>")
        fi
        
        # Quality
        cmd+=("-quality" "$QUALITY")
        
        # Progressive
        [[ "$PROGRESSIVE" == true ]] && cmd+=("-interlace" "Plane")
        
        # Strip metadata
        [[ "$STRIP_METADATA" == true ]] && cmd+=("-strip")
        
        cmd+=("$output")
        
        eval "${cmd[@]}"
    fi
}

optimize_png() {
    local input="$1"
    local output="$2"
    
    local -a cmd=()
    
    # Use ImageMagick for resizing/conversion
    if [[ -n "$RESIZE" ]] || [[ -n "$MAX_WIDTH" ]] || [[ -n "$MAX_HEIGHT" ]] || [[ "$STRIP_METADATA" == true ]]; then
        cmd+=("convert")
        cmd+=("$input")
        
        # Resize options
        if [[ -n "$RESIZE" ]]; then
            cmd+=("-resize" "$RESIZE")
        elif [[ -n "$MAX_WIDTH" ]] || [[ -n "$MAX_HEIGHT" ]]; then
            local geom=""
            [[ -n "$MAX_WIDTH" ]] && geom="${MAX_WIDTH}x"
            [[ -n "$MAX_HEIGHT" ]] && geom="${geom}${MAX_HEIGHT}"
            cmd+=("-resize" "${geom}>")
        fi
        
        # Strip metadata
        [[ "$STRIP_METADATA" == true ]] && cmd+=("-strip")
        
        cmd+=("$output")
        
        eval "${cmd[@]}"
    else
        # Just copy
        cp "$input" "$output"
    fi
    
    # Optimize with optipng
    if [[ "$HAVE_OPTIPNG" == true ]]; then
        optipng -quiet -o2 "$output" 2>/dev/null || true
    fi
}

optimize_webp() {
    local input="$1"
    local output="$2"
    
    if [[ "$HAVE_WEBP" == true ]]; then
        local -a cmd=("cwebp")
        cmd+=("-q" "$QUALITY")
        cmd+=("-quiet")
        
        # Resize
        if [[ -n "$RESIZE" ]]; then
            cmd+=("-resize" "${RESIZE/x/ }")
        fi
        
        cmd+=("$input")
        cmd+=("-o" "$output")
        
        eval "${cmd[@]}"
    else
        # Fallback to ImageMagick
        local -a cmd=("convert")
        cmd+=("$input")
        
        if [[ -n "$RESIZE" ]]; then
            cmd+=("-resize" "$RESIZE")
        elif [[ -n "$MAX_WIDTH" ]] || [[ -n "$MAX_HEIGHT" ]]; then
            local geom=""
            [[ -n "$MAX_WIDTH" ]] && geom="${MAX_WIDTH}x"
            [[ -n "$MAX_HEIGHT" ]] && geom="${geom}${MAX_HEIGHT}"
            cmd+=("-resize" "${geom}>")
        fi
        
        cmd+=("-quality" "$QUALITY")
        [[ "$STRIP_METADATA" == true ]] && cmd+=("-strip")
        cmd+=("$output")
        
        eval "${cmd[@]}"
    fi
}

optimize_image() {
    local input="$1"
    
    if [[ ! -f "$input" ]]; then
        error "File not found: $input"
        return 1
    fi
    
    # Determine format
    local format=$(identify -format "%m" "$input" 2>/dev/null | tr '[:upper:]' '[:lower:]')
    
    # Skip non-image files
    if [[ ! "$format" =~ ^(jpeg|jpg|png|gif|webp|bmp|tiff)$ ]]; then
        [[ "$VERBOSE" == true ]] && warning "Skipping non-image file: $input"
        return 0
    fi
    
    # Generate output filename
    local basename=$(basename "$input")
    local filename="${basename%.*}"
    local extension="${basename##*.}"
    
    # Determine output format
    local out_format="${OUTPUT_FORMAT:-$extension}"
    
    # Add suffix if not converting format
    if [[ -z "$OUTPUT_FORMAT" ]] && [[ -n "$SUFFIX" ]]; then
        filename="${filename}${SUFFIX}"
    fi
    
    local output="$OUTPUT_DIR/${filename}.${out_format}"
    
    # Create output directory
    mkdir -p "$(dirname "$output")"
    
    # Check if output exists
    if [[ -f "$output" ]] && [[ "$DRY_RUN" != true ]]; then
        warning "Output exists, skipping: $output"
        return 0
    fi
    
    # Get sizes
    local size_before=$(stat -c%s "$input")
    ((TOTAL_SIZE_BEFORE += size_before))
    
    if [[ "$DRY_RUN" == true ]]; then
        echo -e "${CYAN}Would optimize:${NC} $input → $output"
        return 0
    fi
    
    # Backup if requested
    if [[ "$CREATE_BACKUP" == true ]]; then
        cp "$input" "${input}.bak"
    fi
    
    # Optimize based on output format
    case "$out_format" in
        jpg|jpeg)
            optimize_jpeg "$input" "$output"
            ;;
        png)
            optimize_png "$input" "$output"
            ;;
        webp)
            optimize_webp "$input" "$output"
            ;;
        *)
            # Generic conversion
            convert "$input" "$output"
            ;;
    esac
    
    if [[ $? -eq 0 ]] && [[ -f "$output" ]]; then
        local size_after=$(stat -c%s "$output")
        ((TOTAL_SIZE_AFTER += size_after))
        ((PROCESSED_FILES++))
        
        local saved=$((size_before - size_after))
        local percent=0
        [[ $size_before -gt 0 ]] && percent=$((saved * 100 / size_before))
        
        if [[ "$VERBOSE" == true ]]; then
            echo -e "${GREEN}✓${NC} $(basename "$input")"
            echo "  $(human_readable_size $size_before) → $(human_readable_size $size_after) (saved $percent%)"
        else
            echo -n "."
        fi
    else
        ((FAILED_FILES++))
        error "Failed to optimize: $input"
    fi
}

################################################################################
# Batch Processing
################################################################################

process_directory() {
    local dir="$1"
    
    print_header "IMAGE OPTIMIZATION" 70
    echo
    echo -e "${BOLD}Input:${NC} $dir"
    echo -e "${BOLD}Output:${NC} $OUTPUT_DIR"
    echo -e "${BOLD}Quality:${NC} $QUALITY"
    [[ -n "$OUTPUT_FORMAT" ]] && echo -e "${BOLD}Format:${NC} $OUTPUT_FORMAT"
    [[ -n "$RESIZE" ]] && echo -e "${BOLD}Resize:${NC} $RESIZE"
    [[ -n "$MAX_WIDTH" ]] && echo -e "${BOLD}Max Width:${NC} $MAX_WIDTH"
    [[ -n "$MAX_HEIGHT" ]] && echo -e "${BOLD}Max Height:${NC} $MAX_HEIGHT"
    [[ "$STRIP_METADATA" == true ]] && echo -e "${BOLD}Strip Metadata:${NC} Yes"
    echo
    
    # Find images
    local -a find_args=("$dir")
    
    if [[ "$RECURSIVE" != true ]]; then
        find_args+=("-maxdepth" "1")
    fi
    
    find_args+=("-type" "f")
    find_args+=("(" "-iname" "*.jpg" "-o" "-iname" "*.jpeg" "-o" "-iname" "*.png" "-o" "-iname" "*.gif" "-o" "-iname" "*.webp" "-o" "-iname" "*.bmp" ")")
    
    local -a images=()
    while IFS= read -r -d '' file; do
        images+=("$file")
        ((TOTAL_FILES++))
    done < <(find "${find_args[@]}" -print0)
    
    if [[ ${#images[@]} -eq 0 ]]; then
        warning "No images found in $dir"
        return 1
    fi
    
    info "Found ${#images[@]} images"
    echo
    
    # Process each image
    for image in "${images[@]}"; do
        optimize_image "$image"
    done
    
    [[ "$VERBOSE" != true ]] && echo
    echo
    
    # Summary
    print_separator
    echo -e "${BOLD}Optimization Complete${NC}"
    echo "  Total files: $TOTAL_FILES"
    echo "  Processed: $PROCESSED_FILES"
    echo "  Failed: $FAILED_FILES"
    echo "  Original size: $(human_readable_size $TOTAL_SIZE_BEFORE)"
    echo "  Optimized size: $(human_readable_size $TOTAL_SIZE_AFTER)"
    
    if [[ $TOTAL_SIZE_BEFORE -gt 0 ]]; then
        local saved=$((TOTAL_SIZE_BEFORE - TOTAL_SIZE_AFTER))
        local percent=$((saved * 100 / TOTAL_SIZE_BEFORE))
        echo "  ${GREEN}Saved: $(human_readable_size $saved) ($percent%)${NC}"
    fi
}

################################################################################
# Usage and Help
################################################################################

show_usage() {
    cat << EOF
${WHITE}Image Optimizer - Batch Image Optimization Tool${NC}

${CYAN}Usage:${NC}
    $(basename "$0") [OPTIONS] <input>

${CYAN}Options:${NC}
    -h, --help              Show this help message
    -d, --directory DIR     Process all images in directory
    -o, --output DIR        Output directory (default: optimized/)
    -q, --quality QUALITY   JPEG quality 0-100 (default: 85)
    -r, --resize WIDTHxHEIGHT  Resize to exact dimensions
    -f, --format FORMAT     Convert to format: jpg, png, webp
    --max-width WIDTH       Maximum width (maintain aspect)
    --max-height HEIGHT     Maximum height (maintain aspect)
    --strip-metadata        Remove EXIF data
    --progressive           Use progressive JPEG
    --backup                Backup original files
    --suffix SUFFIX         Filename suffix (default: _opt)
    --recursive             Process subdirectories
    --dry-run               Show what would be done
    -v, --verbose           Verbose output

${CYAN}Examples:${NC}
    # Optimize all images in directory
    $(basename "$0") -d ~/Photos
    
    # Convert to WebP with quality 80
    $(basename "$0") -d images/ -f webp -q 80
    
    # Resize and optimize
    $(basename "$0") -d photos/ --max-width 1920 -q 85
    
    # Strip metadata and use progressive
    $(basename "$0") -d images/ --strip-metadata --progressive
    
    # Recursive with format conversion
    $(basename "$0") -d ~/Pictures --recursive -f jpg -q 80

${CYAN}Quality Guide:${NC}
    90-100: Very high quality, large files
    80-90:  High quality (recommended)
    70-80:  Good quality, smaller files
    50-70:  Medium quality, small files
    <50:    Low quality, very small files

${CYAN}Supported Formats:${NC}
    Input:  JPG, PNG, GIF, WebP, BMP, TIFF
    Output: JPG, PNG, WebP

${CYAN}Optimization Tools:${NC}
    Required: ImageMagick or GraphicsMagick
    Optional: jpegoptim, optipng, cwebp (for better compression)

${CYAN}Install Tools:${NC}
    # Debian/Ubuntu
    sudo apt install imagemagick jpegoptim optipng webp
    
    # Fedora
    sudo dnf install ImageMagick jpegoptim optipng libwebp-tools
    
    # Arch
    sudo pacman -S imagemagick jpegoptim optipng libwebp

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
        -d|--directory)
            [[ -z "${2:-}" ]] && error_exit "Directory required" 2
            INPUT_PATH="$2"
            shift 2
            ;;
        -o|--output)
            [[ -z "${2:-}" ]] && error_exit "Output directory required" 2
            OUTPUT_DIR="$2"
            shift 2
            ;;
        -q|--quality)
            [[ -z "${2:-}" ]] && error_exit "Quality required" 2
            QUALITY="$2"
            shift 2
            ;;
        -r|--resize)
            [[ -z "${2:-}" ]] && error_exit "Resize dimensions required" 2
            RESIZE="$2"
            shift 2
            ;;
        -f|--format)
            [[ -z "${2:-}" ]] && error_exit "Format required" 2
            OUTPUT_FORMAT="$2"
            shift 2
            ;;
        --max-width)
            [[ -z "${2:-}" ]] && error_exit "Width required" 2
            MAX_WIDTH="$2"
            shift 2
            ;;
        --max-height)
            [[ -z "${2:-}" ]] && error_exit "Height required" 2
            MAX_HEIGHT="$2"
            shift 2
            ;;
        --strip-metadata)
            STRIP_METADATA=true
            shift
            ;;
        --progressive)
            PROGRESSIVE=true
            shift
            ;;
        --backup)
            CREATE_BACKUP=true
            shift
            ;;
        --suffix)
            [[ -z "${2:-}" ]] && error_exit "Suffix required" 2
            SUFFIX="$2"
            shift 2
            ;;
        --recursive)
            RECURSIVE=true
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
            INPUT_PATH="$1"
            shift
            ;;
    esac
done

# Validate input
[[ -z "$INPUT_PATH" ]] && error_exit "Input path required" 2

# Process
if [[ -f "$INPUT_PATH" ]]; then
    optimize_image "$INPUT_PATH"
elif [[ -d "$INPUT_PATH" ]]; then
    process_directory "$INPUT_PATH"
else
    error_exit "Input not found: $INPUT_PATH" 1
fi

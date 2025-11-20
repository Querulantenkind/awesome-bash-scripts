# Media Scripts

Scripts for audio, video, and image processing and management.

## Categories

- **Video Processing**: Video conversion, compression, editing
- **Audio Processing**: Audio format conversion, editing
- **Image Processing**: Image resizing, conversion, optimization
- **Media Organization**: File renaming, metadata management
- **Streaming**: Media streaming and recording utilities

## Scripts

### 1. `video-converter.sh`
Advanced video conversion tool using FFmpeg with support for batch processing and preset profiles.

**Features:**
- Multiple output formats (MP4, MKV, AVI, WebM, MOV)
- Video codecs: H.264, H.265, VP9, AV1
- Audio codecs: AAC, MP3, Opus, Vorbis
- Quality control (CRF) and bitrate settings
- Resolution scaling and frame rate control
- Preset profiles (web-hd, web-sd, mobile, high-quality, archive)
- Batch conversion mode
- Subtitle extraction/embedding
- Metadata preservation
- Dry-run mode

**Usage:**
```bash
# Convert to MP4
./video-converter.sh input.avi output.mp4

# Use preset profile
./video-converter.sh --profile web-hd input.mkv

# Resize and convert
./video-converter.sh -r 1280x720 -f webm input.mov output.webm

# Batch convert directory
./video-converter.sh --batch --directory ~/Videos --format mp4

# H.265 with custom quality
./video-converter.sh -c h265 -q 20 input.mp4 output.mkv
```

**Quality Guide:**
- CRF 0-18: Visually lossless
- CRF 18-23: High quality (recommended)
- CRF 23-28: Good quality
- CRF 28+: Lower quality, smaller files

**Dependencies:**
- FFmpeg (required)
- jq (for video info)

---

### 2. `image-optimizer.sh`
Batch image optimization tool that compresses and resizes images while maintaining quality.

**Features:**
- Multiple format support (JPG, PNG, GIF, WebP, BMP, TIFF)
- Quality control for lossy compression
- Batch processing with recursive option
- Resize by dimensions or max width/height
- Format conversion
- Metadata stripping
- Progressive JPEG support
- Backup original files
- Statistics and compression ratios
- Dry-run mode

**Usage:**
```bash
# Optimize all images in directory
./image-optimizer.sh -d ~/Photos

# Convert to WebP with quality 80
./image-optimizer.sh -d images/ -f webp -q 80

# Resize to max width 1920px
./image-optimizer.sh -d photos/ --max-width 1920 -q 85

# Strip metadata and use progressive
./image-optimizer.sh -d images/ --strip-metadata --progressive

# Recursive with format conversion
./image-optimizer.sh -d ~/Pictures --recursive -f jpg -q 80
```

**Quality Guide:**
- 90-100: Very high quality, large files
- 80-90: High quality (recommended)
- 70-80: Good quality, smaller files
- 50-70: Medium quality, small files
- <50: Low quality, very small files

**Dependencies:**
- ImageMagick or GraphicsMagick (required)
- jpegoptim (optional, for better JPEG compression)
- optipng (optional, for better PNG compression)
- cwebp (optional, for WebP conversion)

**Installation:**
```bash
# Debian/Ubuntu
sudo apt install imagemagick jpegoptim optipng webp

# Fedora
sudo dnf install ImageMagick jpegoptim optipng libwebp-tools

# Arch
sudo pacman -S imagemagick jpegoptim optipng libwebp
```

---

## Common Workflows

### Video Optimization for Web
```bash
# Optimize for web streaming (1080p)
./video-converter.sh --profile web-hd input.mov

# Optimize for mobile (480p)
./video-converter.sh --profile mobile input.mp4

# Create multiple versions
for profile in web-hd web-sd mobile; do
    ./video-converter.sh --profile $profile input.mp4
done
```

### Image Optimization Pipeline
```bash
# Optimize and resize for web
./image-optimizer.sh -d photos/ --max-width 1920 -q 85 -o web/

# Convert to WebP for modern browsers
./image-optimizer.sh -d photos/ -f webp -q 80 -o webp/

# Create thumbnails
./image-optimizer.sh -d photos/ -r 300x200 -o thumbnails/
```

### Batch Processing
```bash
# Convert all videos in a directory
./video-converter.sh --batch --directory ~/Videos -f mp4 -q 23

# Optimize all images recursively
./image-optimizer.sh -d ~/Photos --recursive -q 85
```

---

## Best Practices

### Video Conversion
1. **Use appropriate codecs**: H.264 for compatibility, H.265 for better compression
2. **Quality settings**: Start with CRF 23 and adjust based on results
3. **Preset profiles**: Use presets for common use cases
4. **Test first**: Use --dry-run to preview commands
5. **Preserve originals**: Always keep backup of source files

### Image Optimization
1. **Quality balance**: 80-85 is usually optimal for photos
2. **Format selection**: WebP for web, PNG for graphics with transparency, JPEG for photos
3. **Progressive JPEG**: Improves perceived loading time
4. **Strip metadata**: Remove EXIF data for privacy and smaller files
5. **Batch processing**: Process directories rather than individual files

---

## Troubleshooting

### Video Converter Issues
- **FFmpeg not found**: Install with `sudo apt install ffmpeg`
- **Slow conversion**: Use faster preset (e.g., `-p fast`)
- **Large output files**: Decrease quality with `-q 28` or use `-b 2M`
- **Audio sync issues**: Try different audio codec with `-a aac`

### Image Optimizer Issues
- **ImageMagick not found**: Install with `sudo apt install imagemagick`
- **Poor quality**: Increase quality setting with `-q 90`
- **Large files**: Decrease quality or resize images
- **Format errors**: Check input format is supported

---

## Performance Tips

### Video Conversion
- Use hardware acceleration if available (requires special FFmpeg build)
- Adjust number of threads based on CPU cores
- Use faster presets for quick previews
- Batch process overnight for large collections

### Image Optimization
- Use specialized tools (jpegoptim, optipng) for better compression
- Process in parallel for large directories
- Use --recursive for entire photo libraries
- Consider WebP format for maximum compression

---

## File Size Estimates

### Video (1 minute of 1080p video)
- H.264 CRF 23: ~15-20 MB
- H.265 CRF 23: ~10-15 MB
- VP9: ~12-18 MB
- WebM: ~10-15 MB

### Images (1920x1080 photo)
- JPEG Quality 85: ~200-400 KB
- PNG: ~1-3 MB
- WebP Quality 85: ~150-300 KB
- WebP Quality 80: ~100-200 KB

---

## Use Cases

### Content Creators
- Convert raw footage to web-friendly formats
- Create multiple quality versions for adaptive streaming
- Optimize thumbnails and preview images
- Batch process video libraries

### Web Developers
- Optimize images for faster page load
- Convert to WebP for modern browsers
- Create responsive image sets
- Reduce bandwidth costs

### Photographers
- Optimize photos for web galleries
- Create watermarked versions
- Batch resize for social media
- Archive originals while sharing compressed versions

### System Administrators
- Reduce storage requirements
- Optimize media for delivery
- Automate media processing pipelines
- Monitor compression ratios

---

**Note**: Many scripts require ffmpeg, imagemagick, or similar tools.


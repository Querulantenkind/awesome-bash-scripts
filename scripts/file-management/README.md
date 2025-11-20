# File Management Scripts

Powerful file management tools for organizing, deduplicating, renaming, and managing files efficiently. These scripts automate common file operations and help maintain an organized filesystem.

## 📁 Available Scripts

### 1. file-organizer.sh
**Intelligent file organization tool with multiple strategies**

Automatically organize files by type, date, size, or extension with powerful filtering options and undo capability.

#### Features
- ✅ **Multiple organization types**: By type, date, size, or extension
- ✅ **Smart categorization**: Automatic file type detection
- ✅ **Flexible filtering**: Size, age, and pattern filters
- ✅ **Move or copy**: Choose between moving or copying files
- ✅ **Recursive processing**: Handle subdirectories
- ✅ **Dry-run mode**: Preview changes before applying
- ✅ **Undo capability**: Reverse organization operations
- ✅ **Duplicate handling**: Automatic rename on conflicts
- ✅ **Custom patterns**: Match specific file patterns

#### Usage Examples

```bash
# Organize Downloads by file type
./file-organizer.sh -s ~/Downloads -o type

# Organize Pictures by date (move instead of copy)
./file-organizer.sh -s ~/Pictures -o date -m

# Organize Documents recursively by extension
./file-organizer.sh -s ~/Documents -o extension -r

# Organize large files only (>10MB)
./file-organizer.sh -s ~/Downloads -o size --min-size 10M

# Organize old files (older than 30 days)
./file-organizer.sh -s ~/Downloads -o type --older-than 30

# Organize specific file types
./file-organizer.sh -s ~/Downloads -p "*.pdf" -o type

# Dry run to preview changes
./file-organizer.sh -s ~/Downloads -o type --dry-run

# Organize with undo capability
./file-organizer.sh -s ~/Downloads -o type --create-index

# Undo previous organization
./file-organizer.sh --undo /path/to/index.txt
```

#### Organization Types

**By Type (--organize-by type)**
- `images/` - jpg, png, gif, svg, webp, etc.
- `videos/` - mp4, avi, mkv, mov, etc.
- `audio/` - mp3, wav, flac, ogg, etc.
- `documents/` - pdf, doc, txt, md, etc.
- `spreadsheets/` - xls, xlsx, csv, etc.
- `presentations/` - ppt, pptx, odp, etc.
- `archives/` - zip, tar, gz, rar, etc.
- `code/` - sh, py, java, js, c, etc.
- `other/` - unrecognized types

**By Date (--organize-by date)**
```
2024/
  11/
    file1.txt
    file2.pdf
  10/
    older-file.doc
```

**By Size (--organize-by size)**
- `tiny/` - Less than 1MB
- `small/` - 1MB to 10MB
- `medium/` - 10MB to 100MB
- `large/` - More than 100MB

**By Extension (--organize-by extension)**
```
pdf/
  document.pdf
txt/
  notes.txt
jpg/
  photo.jpg
```

---

### 2. duplicate-finder.sh
**Find and remove duplicate files based on content**

Identify duplicate files using MD5 or SHA256 checksums with various deletion strategies and interactive mode.

#### Features
- ✅ **Content-based detection**: Uses checksums (MD5/SHA256)
- ✅ **Multiple keep strategies**: Newest, oldest, smallest, largest, first
- ✅ **Interactive mode**: Confirm each deletion
- ✅ **Automatic deletion**: Remove duplicates automatically
- ✅ **Size filtering**: Only check files above minimum size
- ✅ **Recursive search**: Scan subdirectories
- ✅ **Dry-run mode**: Preview without deleting
- ✅ **Space calculation**: Show how much space will be saved
- ✅ **Detailed reports**: List all duplicate sets

#### Usage Examples

```bash
# Find duplicates in Downloads
./duplicate-finder.sh ~/Downloads

# Find duplicates recursively with preview
./duplicate-finder.sh -r ~/Pictures --dry-run

# Delete duplicates automatically, keep newest
./duplicate-finder.sh -d -k newest ~/Documents

# Interactive mode for selective deletion
./duplicate-finder.sh -i ~/Videos

# Only check large files (>10MB)
./duplicate-finder.sh -i -r -m 10M ~/Media

# Use SHA256 for critical files
./duplicate-finder.sh -a sha256 ~/Important

# Keep oldest versions
./duplicate-finder.sh -d -k oldest ~/Archives

# Save results to file
./duplicate-finder.sh -r ~/Documents -o duplicates.txt
```

#### Keep Strategies

- `newest` - Keep the most recently modified file
- `oldest` - Keep the oldest file  
- `smallest` - Keep the smallest file (helpful with corrupted duplicates)
- `largest` - Keep the largest file
- `first` - Keep the first file found (fastest)

---

### 3. bulk-renamer.sh
**Powerful bulk file renaming with pattern matching and transformations**

Advanced batch renaming tool with regex support, case conversion, sequential numbering, and undo capability.

#### Features
- ✅ **Find and replace**: Simple text or regex-based replacement
- ✅ **Case conversion**: Lowercase, uppercase, titlecase
- ✅ **Sequential numbering**: Add sequential numbers with padding
- ✅ **Prefix/suffix**: Add text before/after filenames
- ✅ **Space removal**: Replace spaces with underscores
- ✅ **Pattern matching**: Match specific file patterns
- ✅ **Interactive mode**: Confirm each rename
- ✅ **Dry-run mode**: Preview all changes
- ✅ **Undo capability**: Reverse rename operations
- ✅ **Recursive processing**: Handle subdirectories

#### Usage Examples

```bash
# Replace text in JPG files
./bulk-renamer.sh -p "*.jpg" -f "IMG" -r "Photo"

# Sequential numbering with padding
./bulk-renamer.sh -p "*.mp3" -s 1 -w 3 --prefix "track_"
# Result: track_001.mp3, track_002.mp3, track_003.mp3

# Lowercase and remove spaces
./bulk-renamer.sh -p "*" -l --remove-spaces

# Add prefix to all PDFs
./bulk-renamer.sh -p "*.pdf" --prefix "document_"

# Add suffix before extension
./bulk-renamer.sh -p "*.txt" --suffix "_backup"
# Result: file_backup.txt

# Regex replacement (extract year)
./bulk-renamer.sh -x "([0-9]{4})" -r "year_\1" *.txt

# Interactive renaming
./bulk-renamer.sh -p "*.doc" -f "old" -r "new" -i

# Dry run to preview
./bulk-renamer.sh -p "*" -l --dry-run

# Recursive renaming in directory
./bulk-renamer.sh -d ~/Documents -R -p "*.txt" -u

# Undo previous rename
./bulk-renamer.sh --undo rename_index_20241120_143022.txt
```

#### Transformations

**Case Conversion:**
```bash
# Lowercase: MyFile.TXT → myfile.txt
./bulk-renamer.sh -p "*" -l

# Uppercase: myfile.txt → MYFILE.TXT
./bulk-renamer.sh -p "*" -u

# Title Case: my file.txt → My File.txt
./bulk-renamer.sh -p "*" -t
```

**Sequential Numbering:**
```bash
# Default: file1, file2, file3
./bulk-renamer.sh -p "*.jpg" -s 1

# With padding: file001, file002, file003
./bulk-renamer.sh -p "*.jpg" -s 1 -w 3

# Start from different number
./bulk-renamer.sh -p "*.mp3" -s 10 -w 2
# Result: file10.mp3, file11.mp3, etc.
```

---

##  🔧 Common Workflows

### Clean Up Downloads Folder
```bash
# 1. Find and remove duplicates
./duplicate-finder.sh -d -k newest ~/Downloads

# 2. Organize remaining files by type
./file-organizer.sh -s ~/Downloads -o type -m

# 3. Clean up old files
./file-organizer.sh -s ~/Downloads -o type --older-than 90 -m
```

### Organize Photo Library
```bash
# 1. Remove duplicate photos
./duplicate-finder.sh -r -d -k largest ~/Pictures

# 2. Organize by date
./file-organizer.sh -s ~/Pictures -o date -r -m

# 3. Rename photos with sequential numbers
./bulk-renamer.sh -d ~/Pictures -R -p "*.jpg" -s 1 -w 4 --prefix "photo_"
```

### Clean Up Documents
```bash
# 1. Find large duplicate documents
./duplicate-finder.sh -r -i -m 1M ~/Documents

# 2. Organize by type
./file-organizer.sh -s ~/Documents -o type -r

# 3. Standardize naming
./bulk-renamer.sh -d ~/Documents -R -p "*.pdf" -l --remove-spaces
```

### Prepare Files for Archive
```bash
# 1. Organize old files
./file-organizer.sh -s ~/OldFiles --older-than 365 -o date -m

# 2. Remove duplicates
./duplicate-finder.sh -r -d -k oldest ~/OldFiles

# 3. Rename for consistency
./bulk-renamer.sh -d ~/OldFiles -R -l --remove-spaces
```

---

## 📊 File Organization Strategies

### Strategy 1: By File Type (Recommended for Downloads)
**Best for:**
- Download folders
- Mixed content
- Quick access by file type

```bash
./file-organizer.sh -s ~/Downloads -o type -m --older-than 7
```

### Strategy 2: By Date (Recommended for Media)
**Best for:**
- Photos and videos
- Time-based organization
- Archive management

```bash
./file-organizer.sh -s ~/Pictures -o date -r -m
```

### Strategy 3: By Size (For Storage Management)
**Best for:**
- Finding large files
- Storage optimization
- Cleanup operations

```bash
./file-organizer.sh -s ~/Data -o size -r
```

### Strategy 4: By Extension (For Developers)
**Best for:**
- Source code
- Project files
- Technical documents

```bash
./file-organizer.sh -s ~/Projects -o extension -r
```

---

## 🎯 Best Practices

### Before Running Scripts

1. **Always use dry-run first**
```bash
./file-organizer.sh -s ~/Downloads -o type --dry-run
./duplicate-finder.sh ~/Documents --dry-run
./bulk-renamer.sh -p "*.txt" -l --dry-run
```

2. **Create backups of important files**
```bash
cp -r ~/Important ~/Important.backup
```

3. **Test on small sample first**
```bash
mkdir ~/test-folder
cp ~/Downloads/* ~/test-folder/
./file-organizer.sh -s ~/test-folder -o type
```

### During Operation

1. **Use interactive mode for critical files**
```bash
./duplicate-finder.sh -i ~/Important
./bulk-renamer.sh -p "*.doc" -f "old" -r "new" -i
```

2. **Enable index creation for undo**
```bash
./file-organizer.sh -s ~/Downloads -o type --create-index
./bulk-renamer.sh -p "*" -l  # Automatically creates index
```

3. **Use verbose mode to monitor**
```bash
./file-organizer.sh -s ~/Downloads -o type -v
```

### After Operation

1. **Verify results**
```bash
ls -la ~/organized-folder/
```

2. **Keep undo files safe**
```bash
mv organization_index_*.txt ~/backup/undo-files/
```

3. **Review logs**
```bash
cat /var/log/file-operations.log
```

---

## 🔄 Automation Examples

### Daily Downloads Cleanup
```bash
#!/bin/bash
# daily-cleanup.sh

# Remove duplicates
/path/to/duplicate-finder.sh -d -k newest ~/Downloads -l /var/log/cleanup.log

# Organize files older than 7 days
/path/to/file-organizer.sh -s ~/Downloads -o type --older-than 7 -m -l /var/log/cleanup.log
```

Add to crontab:
```bash
0 2 * * * /path/to/daily-cleanup.sh
```

### Weekly Photo Organization
```bash
#!/bin/bash
# weekly-photos.sh

# Find and remove duplicate photos
/path/to/duplicate-finder.sh -r -d -k largest ~/Pictures

# Organize by date
/path/to/file-organizer.sh -s ~/Pictures -o date -r -m
```

### Monthly Archive Preparation
```bash
#!/bin/bash
# monthly-archive.sh

YEAR=$(date +%Y)
MONTH=$(date +%m)
ARCHIVE_DIR=~/Archives/$YEAR-$MONTH

mkdir -p "$ARCHIVE_DIR"

# Move old files
/path/to/file-organizer.sh -s ~/Documents --older-than 90 -d "$ARCHIVE_DIR" -m

# Remove duplicates in archive
/path/to/duplicate-finder.sh -r -d -k oldest "$ARCHIVE_DIR"

# Standardize names
/path/to/bulk-renamer.sh -d "$ARCHIVE_DIR" -R -l --remove-spaces
```

---

## 📝 Tips and Tricks

### Finding Specific Duplicates
```bash
# Only check image duplicates
./duplicate-finder.sh ~/Pictures -r -m 100K

# Only check large video files
./duplicate-finder.sh ~/Videos -r -m 50M
```

### Complex Renaming Operations
```bash
# Chain multiple operations
./bulk-renamer.sh -p "*.txt" -f "_old" -r "_new" --dry-run
# If looks good, remove --dry-run and run again

# Multiple passes for complex changes
./bulk-renamer.sh -p "*" --remove-spaces
./bulk-renamer.sh -p "*" -l
./bulk-renamer.sh -p "*" -s 1 -w 3
```

### Selective Organization
```bash
# Only organize images
./file-organizer.sh -s ~/Downloads -p "*.{jpg,png,gif}" -o date

# Only organize large files
./file-organizer.sh -s ~/Downloads --min-size 10M -o size

# Only organize recent files
./file-organizer.sh -s ~/Downloads --newer-than 7 -o type
```

---

## ❗ Important Warnings

- **Always use dry-run mode first** on important files
- **Keep backups** before bulk operations
- **Test on copies** before modifying originals
- **Review changes** carefully in dry-run output
- **Save undo files** until you're sure changes are correct
- **Be careful with deletion** - deleted duplicates are gone forever
- **Check permissions** before running on system files
- **Avoid running on system directories** like /etc, /bin, /usr

---

## 🐛 Troubleshooting

### "Permission denied" errors
```bash
# Check file permissions
ls -l problematic-file

# Run with appropriate permissions
sudo ./file-organizer.sh -s /protected/directory
```

### Undo not working
```bash
# Check if index file exists
ls -la *index*.txt

# Manually restore from index
while IFS='|' read -r dest src; do
    mv "$dest" "$src"
done < organization_index_*.txt
```

### Duplicate detection too slow
```bash
# Use faster MD5 instead of SHA256
./duplicate-finder.sh -a md5 ~/large-directory

# Increase minimum file size
./duplicate-finder.sh -m 1M ~/directory
```

---

**Happy File Managing!** 📁

For issues or suggestions, please open an issue on the repository.

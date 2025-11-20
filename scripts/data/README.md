# Data Scripts

Collection of data processing, conversion, validation, and migration tools for ETL workflows, format transformation, and data quality management.

## Scripts

### 1. `data-converter.sh`
Universal data format converter with validation and transformation.

**Features:**
- Multiple format support (JSON, CSV, XML, YAML, TOML)
- Auto-format detection
- Schema validation
- Data filtering (jq-style expressions)
- Batch conversion
- Recursive directory processing
- Pretty-printing
- Custom CSV delimiters

**Usage:**
```bash
# JSON to CSV
./data-converter.sh -i data.json -o data.csv -f json -t csv

# YAML to JSON with pretty print
./data-converter.sh -i config.yaml -o config.json -f yaml -t json --pretty

# CSV to XML
./data-converter.sh -i data.csv -o data.xml -f csv -t xml

# Batch convert all JSON files to CSV
./data-converter.sh --batch ./data/ -f json -t csv --recursive

# Filter and convert
./data-converter.sh -i users.json -t csv --filter '.users[] | select(.active == true)'

# Validate and convert
./data-converter.sh -i data.json -t yaml --validate --pretty
```

**Supported Conversions:**
| From → To | JSON | CSV | XML | YAML |
|-----------|------|-----|-----|------|
| **JSON**  | ✓    | ✓   | ✓   | ✓    |
| **CSV**   | ✓    | ✓   | ✓   | ✓    |
| **XML**   | ✓    | ✓   | ✓   | ✓    |
| **YAML**  | ✓    | ✓   | ✓   | ✓    |

---

### 2. `etl-pipeline.sh`
ETL (Extract, Transform, Load) pipeline runner for data processing workflows.

**Features:**
- Multiple source types (file, database, API)
- Multiple destination types (file, database, API, stdout)
- Custom transformation scripts
- Dry-run mode
- Parallel processing
- Error handling and logging
- Progress tracking
- Validation support

**Usage:**
```bash
# File to file with transformation
./etl-pipeline.sh --source-type file --source-path data.csv \
                  --dest-type file --dest-path output.csv \
                  --transform transform.sh

# API to database
./etl-pipeline.sh --source-type api --source-path https://api.example.com/data \
                  --dest-type database --dest-path "mysql://localhost/db"

# Dry run
./etl-pipeline.sh --source-type file --source-path data.json \
                  --dest-type stdout --dry-run --verbose
```

**Pipeline Stages:**
1. **Extract**: Pull data from source
2. **Transform**: Apply transformations and filters
3. **Load**: Write data to destination

---

### 3. `data-validator.sh`
Comprehensive data validation with schema checking and quality analysis.

**Features:**
- Format validation (JSON, CSV, XML, YAML)
- Schema validation (JSON Schema, XSD)
- Data quality checks
- Type validation
- Null value detection
- Column consistency (CSV)
- Detailed error reporting
- Validation summaries

**Usage:**
```bash
# Validate JSON file
./data-validator.sh -i data.json

# Validate CSV with strict mode
./data-validator.sh -i data.csv --strict --show-errors

# Validate against schema
./data-validator.sh -i data.json -s schema.json

# Validate XML with XSD
./data-validator.sh -i data.xml -s schema.xsd --verbose

# Generate validation report
./data-validator.sh -i data.json --show-errors -o validation_report.txt
```

**Validation Checks:**
- Syntax validation
- Schema compliance
- Data type checking
- Null value detection
- Column count consistency (CSV)
- Data quality metrics
- Constraint validation

---

### 4. `migration-assistant.sh`
Data migration tool with backup, validation, and resume capability.

**Features:**
- File and directory migration
- Format conversion during migration
- Batch processing
- Progress tracking
- Resume interrupted migrations
- Automatic backup creation
- Data validation
- Dry-run mode
- State management

**Usage:**
```bash
# Migrate file
./migration-assistant.sh -s old_data.csv -d new_data.csv

# Migrate with validation
./migration-assistant.sh -s data.json -d backup.json --validate

# Convert format during migration
./migration-assistant.sh -s data.csv -d data.json -t csv-to-json

# Migrate directory
./migration-assistant.sh -s /old/data/ -d /new/data/ -t directory

# Dry run
./migration-assistant.sh -s source.db -d dest.db --dry-run

# Resume interrupted migration
./migration-assistant.sh -s large_file.csv -d dest.csv --resume --batch-size 5000
```

**Migration Types:**
- File-to-file
- Directory migration
- Format conversion (CSV-to-JSON, etc.)
- Database-to-database (with appropriate drivers)

---

## Common Workflows

### Data Processing Pipeline
```bash
# 1. Validate source data
./data-validator.sh -i raw_data.csv --strict

# 2. Convert format
./data-converter.sh -i raw_data.csv -o data.json -f csv -t json --validate

# 3. Run ETL pipeline with transformation
./etl-pipeline.sh --source-type file --source-path data.json \
                  --dest-type file --dest-path processed_data.json \
                  --transform ./transform.sh

# 4. Validate output
./data-validator.sh -i processed_data.json --show-errors
```

### Batch Format Conversion
```bash
# Convert all CSV files in directory to JSON
./data-converter.sh --batch ./csv_files/ -f csv -t json --recursive --pretty

# Validate all converted files
for file in ./csv_files/*.json; do
    ./data-validator.sh -i "$file" --strict
done
```

### Safe Data Migration
```bash
# 1. Validate source
./data-validator.sh -i source_data.json --strict

# 2. Dry-run migration
./migration-assistant.sh -s source_data.json -d dest_data.json --dry-run

# 3. Perform migration with backup
./migration-assistant.sh -s source_data.json -d dest_data.json \
                        --validate --batch-size 1000

# 4. Validate destination
./data-validator.sh -i dest_data.json --strict
```

### ETL with Multiple Transformations
```bash
# Extract
./etl-pipeline.sh --source-type api \
                  --source-path "https://api.example.com/users" \
                  --dest-type file \
                  --dest-path raw_users.json

# Transform (convert format)
./data-converter.sh -i raw_users.json -o users.csv -f json -t csv \
                    --filter '.users[] | select(.active == true)'

# Load to database
./etl-pipeline.sh --source-type file \
                  --source-path users.csv \
                  --dest-type database \
                  --dest-path "postgresql://localhost/mydb"
```

---

## Best Practices

### Data Conversion
1. **Always validate first**: Check source data before conversion
2. **Use dry-run**: Test conversions on sample data first
3. **Keep originals**: Never overwrite source files
4. **Batch processing**: Convert multiple files efficiently
5. **Pretty-print**: Make output human-readable when possible

### ETL Pipelines
1. **Modular transformations**: Keep transform scripts simple and focused
2. **Error handling**: Implement robust error recovery
3. **Logging**: Enable verbose mode for troubleshooting
4. **Testing**: Always dry-run before production
5. **Monitoring**: Track pipeline performance and failures

### Data Validation
1. **Schema-first**: Define schemas before validation
2. **Strict mode**: Use strict validation in production
3. **Regular checks**: Validate data at each pipeline stage
4. **Document constraints**: Maintain clear validation rules
5. **Error reporting**: Save validation reports for auditing

### Data Migration
1. **Backup everything**: Always create backups before migration
2. **Validate twice**: Before and after migration
3. **Use batches**: Process large datasets in chunks
4. **Enable resume**: Use state files for long migrations
5. **Test thoroughly**: Dry-run and verify data integrity

---

## Integration Examples

### With Databases
```bash
# Export from database, convert, and validate
mysql -u user -p database -e "SELECT * FROM users" > users.csv
./data-converter.sh -i users.csv -o users.json -f csv -t json
./data-validator.sh -i users.json --strict
```

### With APIs
```bash
# Fetch from API, transform, and load
curl https://api.example.com/data | \
  jq '.items[]' > raw_data.json

./data-converter.sh -i raw_data.json -o data.csv -f json -t csv --pretty
./migration-assistant.sh -s data.csv -d /data/archive/data.csv
```

### With CI/CD Pipelines
```bash
#!/bin/bash
# data-pipeline.sh

# Validate input
./data-validator.sh -i input.json --strict || exit 1

# Convert format
./data-converter.sh -i input.json -o output.csv -f json -t csv --validate

# Migrate to production
./migration-assistant.sh -s output.csv -d /prod/data/output.csv \
                        --validate --no-backup

echo "Pipeline completed successfully"
```

---

## Dependencies

### Required
- `bash` (≥4.0)
- `coreutils` (basic Unix utilities)

### Recommended
- `jq` - JSON processing (required for JSON operations)
- `yq` - YAML processing (optional, falls back to python)
- `xmlstarlet` - XML processing (optional, falls back to python)
- `python3` - Fallback for YAML/XML operations

### Optional
- `jsonschema` - JSON schema validation
- `xmllint` - XML validation with XSD
- `curl` - API operations
- `bc` - Advanced calculations

### Installation
```bash
# Debian/Ubuntu
sudo apt install jq yq xmlstarlet python3 python3-jsonschema libxml2-utils bc curl

# Fedora/RHEL
sudo dnf install jq python3-yq xmlstarlet python3 python3-jsonschema libxml2 bc curl

# Arch Linux
sudo pacman -S jq yq xmlstarlet python python-jsonschema libxml2 bc curl
```

---

## File Format Examples

### JSON
```json
{
  "users": [
    {"id": 1, "name": "John", "active": true},
    {"id": 2, "name": "Jane", "active": false}
  ]
}
```

### CSV
```csv
id,name,active
1,John,true
2,Jane,false
```

### XML
```xml
<?xml version="1.0"?>
<users>
  <user>
    <id>1</id>
    <name>John</name>
    <active>true</active>
  </user>
</users>
```

### YAML
```yaml
users:
  - id: 1
    name: John
    active: true
  - id: 2
    name: Jane
    active: false
```

---

## Troubleshooting

### Data Converter Issues
- **Format detection fails**: Specify format explicitly with `-f` and `-t`
- **jq not found**: Install jq or use fallback formats
- **Conversion error**: Validate source data first
- **Large files**: Use batch processing with `--batch`

### ETL Pipeline Issues
- **Extract fails**: Verify source accessibility and permissions
- **Transform fails**: Test transformation script independently
- **Load fails**: Check destination permissions and space

### Data Validator Issues
- **False positives**: Adjust validation rules or use less strict mode
- **Schema not found**: Verify schema file path
- **Slow validation**: Reduce data size or validate samples

### Migration Assistant Issues
- **Migration interrupted**: Use `--resume` to continue
- **Out of space**: Check destination disk space
- **Permission denied**: Ensure write access to destination
- **State file conflicts**: Clear state with `rm .migration_state`

---

## Performance Notes

- **Data conversion**: ~10K records/sec for JSON to CSV
- **Validation**: ~50K records/sec for CSV
- **ETL pipeline**: Depends on transformation complexity
- **Migration**: ~100 MB/sec for file-to-file

**Optimization Tips:**
- Use `--no-validate` if pre-validated
- Increase `--batch-size` for large datasets
- Use `--parallel` for ETL pipelines
- Disable pretty-printing for production

---

## Security Considerations

1. **Sensitive data**: Be cautious with data containing PII
2. **File permissions**: Set appropriate permissions on output files
3. **Backup retention**: Implement secure backup deletion policies
4. **API credentials**: Never log or expose credentials
5. **Validation logs**: May contain sensitive data samples

---

## Use Cases

### Data Engineers
- Build ETL pipelines
- Convert between data formats
- Validate data quality
- Migrate data between systems

### Database Administrators
- Export/import data
- Convert database dumps
- Validate data integrity
- Migrate between database systems

### DevOps Engineers
- Automate data processing
- Integrate with CI/CD
- Configure monitoring data pipelines
- Manage configuration files

### Data Analysts
- Prepare data for analysis
- Convert analysis results
- Validate data quality
- Export reports in multiple formats

---

## Related Scripts

- **[log-aggregator.sh](../analytics/)** - Log collection and analysis
- **[db-monitor.sh](../database/)** - Database monitoring
- **[system-monitor.sh](../monitoring/)** - System metrics collection

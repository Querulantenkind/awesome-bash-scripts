# Contributing to Awesome Bash Scripts

Thank you for considering contributing to this repository! Here are some guidelines to help you get started.

## How to Contribute

### Adding a New Script

1. **Choose the Right Category**: Place your script in the appropriate directory under `scripts/`:
   - `system/` - System administration and maintenance
   - `network/` - Network-related utilities
   - `backup/` - Backup and recovery scripts
   - `development/` - Development tools and utilities
   - `file-management/` - File operations and organization
   - `monitoring/` - System and service monitoring
   - `security/` - Security and hardening scripts
   - `utilities/` - General-purpose utilities
   - `media/` - Audio and video processing
   - `database/` - Database management scripts

2. **Script Requirements**:
   - Use meaningful, descriptive names (lowercase with hyphens)
   - Include proper shebang (`#!/bin/bash`)
   - Add comprehensive comments
   - Include error handling
   - Use the script template from `templates/script-template.sh`
   - Make scripts executable: `chmod +x script-name.sh`

3. **Documentation**:
   - Add a clear header comment explaining what the script does
   - Document all parameters and options
   - Include usage examples
   - List any dependencies
   - Update the category README.md

### Code Style Guidelines

- Use 4 spaces for indentation (no tabs)
- Use lowercase for variable names with underscores: `my_variable`
- Use uppercase for constants: `CONSTANT_VALUE`
- Always quote variables: `"$variable"`
- Use `[[` instead of `[` for conditionals
- Check command success with proper error handling

### Testing

- Test your script thoroughly before submitting
- Ensure it works on common Linux distributions
- Test edge cases and error conditions
- Document any specific requirements or limitations

### Pull Request Process

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-script`)
3. Commit your changes with clear messages
4. Push to your fork
5. Open a Pull Request with a clear description

### Commit Message Format

```
category: brief description

Longer explanation if needed.
- Point 1
- Point 2
```

Example: `system: add disk usage analyzer script`

## Questions or Suggestions?

Feel free to open an issue for discussion!


# Development Scripts

Scripts to assist with software development, project management, and build automation.

## Categories

- **Project Setup**: Initialize new projects with templates
- **Git Tools**: Git workflow automation and utilities
- **Build Tools**: Compilation and build automation
- **Code Quality**: Linting, formatting, and analysis
- **Environment Management**: Virtual environments, dependencies

## Scripts

### 1. `git-toolkit.sh`
Advanced git operations and statistics tool with workflow automation.

**Features:**
- Repository statistics and analysis
- Automatic branch cleanup
- Safe sync with remote
- Repository backups
- Commit history search
- Easy undo operations
- Interactive mode

**Usage:**
```bash
./git-toolkit.sh stats              # Show repository statistics
./git-toolkit.sh cleanup --dry-run  # Cleanup branches (dry run)
./git-toolkit.sh sync               # Sync with remote
./git-toolkit.sh interactive        # Interactive mode
```

### 2. `project-init.sh`
Project initialization tool that creates boilerplate structure for various project types.

**Features:**
- Multiple project types (Python, Node.js, Bash, Web)
- Best practice project structure
- Pre-configured tooling
- README and LICENSE templates
- Git initialization
- Interactive wizard

**Usage:**
```bash
./project-init.sh                          # Interactive mode
./project-init.sh -n myproject -t python   # Create Python project
./project-init.sh -n webapp -t nodejs -g   # Create Node.js project with git
```

---

**Note**: These scripts are designed to streamline development workflows.


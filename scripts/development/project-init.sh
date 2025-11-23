#!/bin/bash

################################################################################
# Script Name: project-init.sh
# Description: Project initialization tool that creates boilerplate structure
#              for various project types with best practices and templates.
# Author: Luca
# Created: 2024-11-20
# Modified: 2025-11-23
# Version: 1.0.1
#
# Usage: ./project-init.sh [options]
#
# Options:
#   -h, --help             Show help message
#   -n, --name NAME       Project name
#   -t, --type TYPE       Project type: python, nodejs, bash, web, go, rust
#   -d, --directory DIR   Target directory
#   -g, --git             Initialize git repository
#   -l, --license TYPE    License type: mit, apache, gpl, unlicense
#   --no-interactive      Non-interactive mode
#
# Examples:
#   ./project-init.sh -n myproject -t python
#   ./project-init.sh --name webapp --type nodejs --git
#
# Exit Codes:
#   0 - Success
#   1 - General error
#   2 - Invalid argument
################################################################################

set -euo pipefail

# Script directory and sourcing
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../../lib/common.sh"
source "${SCRIPT_DIR}/../../lib/colors.sh"

################################################################################
# Configuration
################################################################################

PROJECT_NAME=""
PROJECT_TYPE=""
TARGET_DIR="."
INIT_GIT=false
LICENSE_TYPE="mit"
INTERACTIVE=true
AUTHOR_NAME="${GIT_AUTHOR_NAME:-$(git config user.name 2>/dev/null || echo '')}"
AUTHOR_EMAIL="${GIT_AUTHOR_EMAIL:-$(git config user.email 2>/dev/null || echo '')}"

################################################################################
# Project Templates
################################################################################

# Create Python project structure
create_python_project() {
    local name="$1"
    local dir="$2"
    
    info "Creating Python project: $name"
    
    # Directory structure
    mkdir -p "$dir/$name"
    mkdir -p "$dir/tests"
    mkdir -p "$dir/docs"
    
    # Main module
    cat > "$dir/$name/__init__.py" << 'EOF'
"""Main module for PROJECT_NAME."""

__version__ = "0.1.0"
EOF
    
    cat > "$dir/$name/main.py" << 'EOF'
#!/usr/bin/env python3
"""Main entry point for PROJECT_NAME."""

def main():
    """Main function."""
    print("Hello from PROJECT_NAME!")

if __name__ == "__main__":
    main()
EOF
    
    # Requirements
    cat > "$dir/requirements.txt" << 'EOF'
# Production dependencies

EOF
    
    cat > "$dir/requirements-dev.txt" << 'EOF'
# Development dependencies
-r requirements.txt
pytest>=7.0.0
black>=22.0.0
flake8>=4.0.0
mypy>=0.950
EOF
    
    # Setup.py
    cat > "$dir/setup.py" << EOF
"""Setup script for PROJECT_NAME."""

from setuptools import setup, find_packages

with open("README.md", "r", encoding="utf-8") as f:
    long_description = f.read()

setup(
    name="$name",
    version="0.1.0",
    author="$AUTHOR_NAME",
    author_email="$AUTHOR_EMAIL",
    description="A short description of $name",
    long_description=long_description,
    long_description_content_type="text/markdown",
    url="https://github.com/$AUTHOR_NAME/$name",
    packages=find_packages(),
    classifiers=[
        "Programming Language :: Python :: 3",
        "Operating System :: OS Independent",
    ],
    python_requires=">=3.7",
    install_requires=[],
    entry_points={
        "console_scripts": [
            "$name=$name.main:main",
        ],
    },
)
EOF
    
    # Pytest config
    cat > "$dir/pytest.ini" << 'EOF'
[pytest]
testpaths = tests
python_files = test_*.py
python_classes = Test*
python_functions = test_*
EOF
    
    # Test example
    cat > "$dir/tests/test_main.py" << EOF
"""Tests for main module."""

from $name import main

def test_main():
    """Test main function."""
    assert True
EOF
    
    # .gitignore
    cat > "$dir/.gitignore" << 'EOF'
__pycache__/
*.py[cod]
*$py.class
*.so
.Python
build/
develop-eggs/
dist/
downloads/
eggs/
.eggs/
lib/
lib64/
parts/
sdist/
var/
wheels/
*.egg-info/
.installed.cfg
*.egg
.pytest_cache/
.coverage
htmlcov/
.venv/
venv/
ENV/
.idea/
.vscode/
EOF
    
    success "Python project structure created"
}

# Create Node.js project structure
create_nodejs_project() {
    local name="$1"
    local dir="$2"
    
    info "Creating Node.js project: $name"
    
    # Directory structure
    mkdir -p "$dir/src"
    mkdir -p "$dir/tests"
    mkdir -p "$dir/docs"
    
    # Main file
    cat > "$dir/src/index.js" << 'EOF'
/**
 * Main entry point for PROJECT_NAME
 */

function main() {
    console.log('Hello from PROJECT_NAME!');
}

if (require.main === module) {
    main();
}

module.exports = { main };
EOF
    
    # Package.json
    cat > "$dir/package.json" << EOF
{
  "name": "$name",
  "version": "0.1.0",
  "description": "A short description of $name",
  "main": "src/index.js",
  "scripts": {
    "start": "node src/index.js",
    "test": "jest",
    "lint": "eslint src",
    "format": "prettier --write src"
  },
  "keywords": [],
  "author": "$AUTHOR_NAME <$AUTHOR_EMAIL>",
  "license": "MIT",
  "devDependencies": {
    "jest": "^29.0.0",
    "eslint": "^8.0.0",
    "prettier": "^2.7.0"
  },
  "dependencies": {}
}
EOF
    
    # Jest config
    cat > "$dir/jest.config.js" << 'EOF'
module.exports = {
    testEnvironment: 'node',
    coverageDirectory: 'coverage',
    collectCoverageFrom: ['src/**/*.js'],
};
EOF
    
    # ESLint config
    cat > "$dir/.eslintrc.json" << 'EOF'
{
    "env": {
        "node": true,
        "es2021": true
    },
    "extends": "eslint:recommended",
    "parserOptions": {
        "ecmaVersion": 12
    }
}
EOF
    
    # .gitignore
    cat > "$dir/.gitignore" << 'EOF'
node_modules/
npm-debug.log*
yarn-debug.log*
yarn-error.log*
.DS_Store
coverage/
dist/
.env
.idea/
.vscode/
EOF
    
    success "Node.js project structure created"
}

# Create Bash project structure
create_bash_project() {
    local name="$1"
    local dir="$2"
    
    info "Creating Bash project: $name"
    
    # Directory structure
    mkdir -p "$dir/lib"
    mkdir -p "$dir/tests"
    mkdir -p "$dir/docs"
    
    # Main script
    cat > "$dir/$name.sh" << 'EOF'
#!/bin/bash

set -euo pipefail

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source libraries
source "$SCRIPT_DIR/lib/common.sh"

main() {
    echo "Hello from PROJECT_NAME!"
}

main "$@"
EOF
    chmod +x "$dir/$name.sh"
    
    # Common library
    cat > "$dir/lib/common.sh" << 'EOF'
#!/bin/bash

# Common functions for PROJECT_NAME

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

error() {
    echo "[ERROR] $*" >&2
}

success() {
    echo "[SUCCESS] $*"
}
EOF
    
    # Test script
    cat > "$dir/tests/test-runner.sh" << 'EOF'
#!/bin/bash

set -euo pipefail

TESTS_PASSED=0
TESTS_FAILED=0

test_example() {
    echo "Running example test..."
    [[ 1 -eq 1 ]] && ((TESTS_PASSED++)) || ((TESTS_FAILED++))
}

test_example

echo "Tests passed: $TESTS_PASSED"
echo "Tests failed: $TESTS_FAILED"

exit $TESTS_FAILED
EOF
    chmod +x "$dir/tests/test-runner.sh"
    
    # .gitignore
    cat > "$dir/.gitignore" << 'EOF'
*.log
*.tmp
.env
.DS_Store
EOF
    
    success "Bash project structure created"
}

# Create web project structure
create_web_project() {
    local name="$1"
    local dir="$2"
    
    info "Creating Web project: $name"
    
    # Directory structure
    mkdir -p "$dir/src/css"
    mkdir -p "$dir/src/js"
    mkdir -p "$dir/src/assets"
    mkdir -p "$dir/public"
    
    # HTML
    cat > "$dir/public/index.html" << EOF
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>$name</title>
    <link rel="stylesheet" href="../src/css/style.css">
</head>
<body>
    <header>
        <h1>$name</h1>
    </header>
    <main>
        <p>Welcome to $name!</p>
    </main>
    <footer>
        <p>&copy; $(date +%Y) $AUTHOR_NAME</p>
    </footer>
    <script src="../src/js/main.js"></script>
</body>
</html>
EOF
    
    # CSS
    cat > "$dir/src/css/style.css" << 'EOF'
* {
    margin: 0;
    padding: 0;
    box-sizing: border-box;
}

body {
    font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Oxygen, Ubuntu, Cantarell, sans-serif;
    line-height: 1.6;
    color: #333;
    background: #f4f4f4;
}

header {
    background: #333;
    color: #fff;
    padding: 2rem;
    text-align: center;
}

main {
    max-width: 1200px;
    margin: 2rem auto;
    padding: 2rem;
    background: #fff;
    border-radius: 8px;
    box-shadow: 0 2px 4px rgba(0,0,0,0.1);
}

footer {
    text-align: center;
    padding: 2rem;
    color: #666;
}
EOF
    
    # JavaScript
    cat > "$dir/src/js/main.js" << 'EOF'
document.addEventListener('DOMContentLoaded', function() {
    console.log('PROJECT_NAME loaded successfully!');
});
EOF
    
    # .gitignore
    cat > "$dir/.gitignore" << 'EOF'
node_modules/
dist/
.DS_Store
*.log
EOF
    
    success "Web project structure created"
}

################################################################################
# Common Project Files
################################################################################

# Create README
create_readme() {
    local name="$1"
    local dir="$2"
    local type="$3"
    
    cat > "$dir/README.md" << EOF
# $name

A short description of $name.

## Installation

\`\`\`bash
# Installation instructions
\`\`\`

## Usage

\`\`\`bash
# Usage examples
\`\`\`

## Features

- Feature 1
- Feature 2
- Feature 3

## Development

\`\`\`bash
# Setup development environment
\`\`\`

## Testing

\`\`\`bash
# Run tests
\`\`\`

## License

This project is licensed under the $(echo "$LICENSE_TYPE" | tr '[:lower:]' '[:upper:]') License - see the LICENSE file for details.

## Author

$AUTHOR_NAME <$AUTHOR_EMAIL>
EOF
}

# Create LICENSE
create_license() {
    local dir="$1"
    local type="$2"
    
    case "$type" in
        mit)
            cat > "$dir/LICENSE" << EOF
MIT License

Copyright (c) $(date +%Y) $AUTHOR_NAME

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
EOF
            ;;
    esac
}

################################################################################
# Git Initialization
################################################################################

init_git_repo() {
    local dir="$1"
    
    cd "$dir"
    
    if [[ -d ".git" ]]; then
        warning "Git repository already initialized"
        return
    fi
    
    info "Initializing git repository..."
    
    git init
    git add .
    git commit -m "Initial commit"
    
    success "Git repository initialized"
}

################################################################################
# Interactive Mode
################################################################################

interactive_init() {
    clear
    print_header "PROJECT INITIALIZATION" 70
    echo
    
    # Project name
    read -p "Project name: " PROJECT_NAME
    [[ -z "$PROJECT_NAME" ]] && error_exit "Project name required" 2
    
    # Project type
    echo
    echo "Select project type:"
    echo "  1) Python"
    echo "  2) Node.js"
    echo "  3) Bash"
    echo "  4) Web (HTML/CSS/JS)"
    echo
    read -p "Choice (1-4): " type_choice
    
    case "$type_choice" in
        1) PROJECT_TYPE="python" ;;
        2) PROJECT_TYPE="nodejs" ;;
        3) PROJECT_TYPE="bash" ;;
        4) PROJECT_TYPE="web" ;;
        *) error_exit "Invalid choice" 2 ;;
    esac
    
    # Git init
    echo
    read -p "Initialize git repository? [Y/n] " git_choice
    [[ "$git_choice" =~ ^[Nn] ]] || INIT_GIT=true
    
    # License
    echo
    echo "Select license:"
    echo "  1) MIT"
    echo "  2) Apache 2.0"
    echo "  3) GPL v3"
    echo "  4) Unlicense"
    echo
    read -p "Choice (1-4) [1]: " license_choice
    
    case "${license_choice:-1}" in
        1) LICENSE_TYPE="mit" ;;
        2) LICENSE_TYPE="apache" ;;
        3) LICENSE_TYPE="gpl" ;;
        4) LICENSE_TYPE="unlicense" ;;
    esac
    
    # Author info
    if [[ -z "$AUTHOR_NAME" ]]; then
        echo
        read -p "Author name: " AUTHOR_NAME
    fi
    
    if [[ -z "$AUTHOR_EMAIL" ]]; then
        read -p "Author email: " AUTHOR_EMAIL
    fi
}

################################################################################
# Main Creation Function
################################################################################

create_project() {
    local name="$PROJECT_NAME"
    local type="$PROJECT_TYPE"
    local target="$TARGET_DIR/$name"
    
    # Check if directory exists
    if [[ -d "$target" ]]; then
        error_exit "Directory already exists: $target" 1
    fi
    
    # Create project directory
    mkdir -p "$target"
    
    print_header "CREATING PROJECT: $name" 70
    echo
    
    # Create project structure based on type
    case "$type" in
        python)
            create_python_project "$name" "$target"
            ;;
        nodejs)
            create_nodejs_project "$name" "$target"
            ;;
        bash)
            create_bash_project "$name" "$target"
            ;;
        web)
            create_web_project "$name" "$target"
            ;;
        *)
            error_exit "Unknown project type: $type" 2
            ;;
    esac
    
    # Create common files
    create_readme "$name" "$target" "$type"
    create_license "$target" "$LICENSE_TYPE"
    
    # Initialize git if requested
    if [[ "$INIT_GIT" == true ]]; then
        init_git_repo "$target"
    fi
    
    echo
    success "Project created successfully!"
    echo
    echo "Project location: $target"
    echo "Project type: $type"
    echo "License: $LICENSE_TYPE"
    echo
    echo "Next steps:"
    echo "  cd $target"
    
    case "$type" in
        python)
            echo "  python -m venv venv"
            echo "  source venv/bin/activate"
            echo "  pip install -r requirements-dev.txt"
            ;;
        nodejs)
            echo "  npm install"
            echo "  npm start"
            ;;
        bash)
            echo "  ./$name.sh"
            ;;
        web)
            echo "  open public/index.html"
            ;;
    esac
}

################################################################################
# Usage and Help
################################################################################

show_usage() {
    cat << EOF
${WHITE}Project Initialization Tool${NC}

${CYAN}Usage:${NC}
    $(basename "$0") [OPTIONS]

${CYAN}Options:${NC}
    -h, --help             Show this help message
    -n, --name NAME       Project name
    -t, --type TYPE       Project type: python, nodejs, bash, web
    -d, --directory DIR   Target directory (default: current)
    -g, --git             Initialize git repository
    -l, --license TYPE    License type: mit, apache, gpl, unlicense
    --no-interactive      Non-interactive mode

${CYAN}Examples:${NC}
    # Interactive mode (recommended)
    $(basename "$0")
    
    # Create Python project
    $(basename "$0") -n myproject -t python -g
    
    # Create Node.js project in specific directory
    $(basename "$0") -n webapp -t nodejs -d ~/projects -g
    
    # Create web project with MIT license
    $(basename "$0") -n mysite -t web -l mit

${CYAN}Supported Project Types:${NC}
    python    Python project with setuptools and pytest
    nodejs    Node.js project with package.json and Jest
    bash      Bash script project with library structure
    web       HTML/CSS/JavaScript web project

${CYAN}Features:${NC}
    - Best practice project structure
    - Pre-configured tooling
    - README and LICENSE templates
    - Git initialization
    - Multiple project types

EOF
}

################################################################################
# Main Execution
################################################################################

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)
            show_usage
            exit 0
            ;;
        -n|--name)
            [[ -z "${2:-}" ]] && error_exit "Project name required" 2
            PROJECT_NAME="$2"
            INTERACTIVE=false
            shift 2
            ;;
        -t|--type)
            [[ -z "${2:-}" ]] && error_exit "Project type required" 2
            PROJECT_TYPE="$2"
            INTERACTIVE=false
            shift 2
            ;;
        -d|--directory)
            [[ -z "${2:-}" ]] && error_exit "Directory required" 2
            TARGET_DIR="$2"
            shift 2
            ;;
        -g|--git)
            INIT_GIT=true
            shift
            ;;
        -l|--license)
            [[ -z "${2:-}" ]] && error_exit "License type required" 2
            LICENSE_TYPE="$2"
            shift 2
            ;;
        --no-interactive)
            INTERACTIVE=false
            shift
            ;;
        *)
            error_exit "Unknown option: $1" 2
            ;;
    esac
done

# Interactive mode if no arguments
if [[ "$INTERACTIVE" == true ]]; then
    interactive_init
fi

# Validate required arguments
[[ -z "$PROJECT_NAME" ]] && error_exit "Project name required" 2
[[ -z "$PROJECT_TYPE" ]] && error_exit "Project type required" 2

# Create project
create_project

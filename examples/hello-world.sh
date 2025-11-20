#!/bin/bash

################################################################################
# Script Name: hello-world.sh
# Description: Simple hello world example demonstrating basic script structure
# Author: Example Author
# Created: 2024-01-01
# Version: 1.0.0
#
# Usage: ./hello-world.sh [name]
#
# Examples:
#   ./hello-world.sh
#   ./hello-world.sh "World"
################################################################################

set -euo pipefail

# Default name
NAME="${1:-World}"

# Color codes
readonly GREEN='\033[0;32m'
readonly NC='\033[0m'

# Main function
main() {
    echo -e "${GREEN}Hello, ${NAME}!${NC}"
    echo "This is a simple example script."
}

main "$@"


#!/bin/bash
set -euo pipefail
source tests/unit/test_common_lib.sh
declare -F | grep "^declare -f test_"

#!/bin/bash

# Navigate to the project directory
cd "$(dirname "$0")"

# Execute the stop script
./stop-all.sh

# Keep terminal open to show result
echo ""
echo "Services stopped."
echo "Press any key to close this window..."
read -n 1 -s

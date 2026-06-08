#!/bin/bash

# Status check script for Skrift

echo "========================================="
echo "Skrift - Status Check"
echo "========================================="
echo ""

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Check backend
echo "🌐 Backend Status:"
if curl -fsS --connect-timeout 2 --max-time 5 http://localhost:8000/health > /dev/null 2>&1; then
    echo -e "   ${GREEN}✓ Running${NC} on http://localhost:8000"
    if [ -f "backend/backend.pid" ]; then
        echo "   PID: $(cat backend/backend.pid)"
    fi
else
    echo -e "   ${RED}✗ Not running${NC}"
fi

echo ""

# Check frontend
echo "🖥️  Frontend Status:"
if [ -f "frontend/frontend.pid" ] && kill -0 "$(cat frontend/frontend.pid)" 2>/dev/null; then
    echo -e "   ${GREEN}✓ Running${NC}"
    echo "   PID: $(cat frontend/frontend.pid)"
else
    # Fallback: detect electron processes to provide a hint
    ELECTRON_COUNT=$(pgrep -f electron | wc -l)
    if [ $ELECTRON_COUNT -gt 0 ]; then
        echo -e "   ${YELLOW}! PID file missing/stale, but Electron appears to be running (${ELECTRON_COUNT} processes)${NC}"
    else
        echo -e "   ${RED}✗ Not running${NC}"
    fi
fi

echo ""

# Check for electron processes
ELECTRON_COUNT=$(pgrep -f electron | wc -l)
if [ $ELECTRON_COUNT -gt 0 ]; then
    echo -e "   ${GREEN}✓ Electron app detected${NC} ($ELECTRON_COUNT processes)"
fi

echo ""
echo "========================================="

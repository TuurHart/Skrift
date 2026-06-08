#!/bin/bash

# Stop all script for Skrift

echo "========================================="
echo "Skrift - Stopping All Services"
echo "========================================="
echo ""

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Stop frontend
echo -e "${YELLOW}Stopping frontend...${NC}"
if [ -f "frontend/start_frontend.sh" ]; then
    cd frontend
    ./start_frontend.sh stop
    cd ..
else
    pkill -f "npm start" 2>/dev/null || true
    pkill -f "electron" 2>/dev/null || true
fi

# Stop backend
echo -e "${YELLOW}Stopping backend...${NC}"
if [ -f "backend/start_backend.sh" ]; then
    cd backend
    ./start_backend.sh stop
    cd ..
else
    pkill -f "uvicorn.*app:app" 2>/dev/null || true
    pkill -f "python3 main.py" 2>/dev/null || true
    lsof -ti:8000 | xargs kill -9 2>/dev/null || true
fi

echo ""
echo -e "${GREEN}✓ All services stopped${NC}"
echo "========================================="

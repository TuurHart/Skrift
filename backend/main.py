#!/usr/bin/env python3
"""
FastAPI Backend for Audio Transcription Pipeline
Main server entry point with API routing and CORS configuration
"""

import os
import sys
from pathlib import Path
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
import uvicorn
import logging

# Configure root logger so all services.* loggers output to stderr
logging.basicConfig(level=logging.INFO, format="%(name)s %(levelname)s: %(message)s")

# Add the backend directory to Python path for module imports
backend_dir = Path(__file__).parent
sys.path.insert(0, str(backend_dir))

# Import API routers (fail fast if these are not available)
from config.settings import get_dependency_paths, settings
from api.files import router as files_router
from api.processing import router as processing_router
from api.transcribe import router as transcribe_router
from api.enhance import router as enhance_router
from api.export import router as export_router
from api.system import router as system_router
from api.config import router as config_router
from api.batch import router as batch_router
from api.tools import router as tools_router
from api.names import router as names_router

# Initialize FastAPI app
app = FastAPI(
    title="Audio Transcription Pipeline API",
    description="Backend API for processing audio files through transcription, sanitisation, enhancement, and export",
    version="1.0.0"
)

# Configure CORS for Electron frontend
_cors_origins = settings.get('server.cors_origins') or [
    "http://localhost:3000",
    "http://127.0.0.1:3000",
    "file://",
]
# Allow mobile app requests from any origin on the LAN
_cors_origins.append("*")
app.add_middleware(
    CORSMiddleware,
    allow_origins=_cors_origins,
    # No cookies/auth are used (localhost + LAN mobile sync), so credentials are
    # disabled. This keeps the wildcard origin spec-valid instead of the invalid
    # "*" + allow_credentials=True combination that browsers reject.
    allow_credentials=False,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Log resolved dependency paths at startup for easier debugging
_dep_paths = get_dependency_paths()
print("[Deps] parakeet=", _dep_paths.get('parakeet'))
print("[Deps] mlx_models=", _dep_paths.get('mlx_models'))
print("[Deps] mlx_venv=", _dep_paths.get('mlx_venv'))

# Register API routers
app.include_router(files_router, prefix="/api/files", tags=["files"])
app.include_router(processing_router, prefix="/api/process", tags=["processing"])
app.include_router(transcribe_router, prefix="/api/process/transcribe", tags=["transcription"])
app.include_router(enhance_router, prefix="/api/process/enhance", tags=["enhancement"])
app.include_router(export_router, prefix="/api/process/export", tags=["export"])
app.include_router(batch_router, prefix="/api/batch", tags=["batch"])
app.include_router(system_router, prefix="/api/system", tags=["system"])
app.include_router(config_router, prefix="/api/config", tags=["config"])
app.include_router(names_router, prefix="/api/names", tags=["names"])
app.include_router(tools_router)

@app.get("/")
async def root():
    """Health check endpoint"""
    return {
        "message": "Audio Transcription Pipeline API",
        "status": "running",
        "version": "1.0.0"
    }

@app.get("/health")
async def health_check():
    """Detailed health check with system info"""
    return {
        "status": "healthy",
        "backend_path": str(backend_dir),
        "python_version": sys.version,
        "available_endpoints": [
            "/api/files/*",
            "/api/process/*",
            "/api/process/transcribe/*",
            "/api/process/enhance/*",
            "/api/process/export/*",
            "/api/batch/*",
            "/api/system/*",
            "/api/config/*"
        ]
    }

_debug_mode = os.environ.get("DEBUG", "").lower() in ("1", "true", "yes")

@app.exception_handler(Exception)
async def general_exception_handler(request, exc):
    if _debug_mode:
        content = {
            "detail": str(exc),
            "type": type(exc).__name__,
            "path": str(request.url),
        }
    else:
        content = {"detail": "Internal server error"}
    return JSONResponse(status_code=500, content=content)

if __name__ == "__main__":
    print("🚀 Starting Audio Transcription Pipeline Backend...")
    print(f"📁 Backend directory: {backend_dir}")
    print("🌐 CORS enabled for Electron frontend")
    _port = int(settings.get('server.port') or 8000)
    print(f"📡 API endpoints available at: http://localhost:{_port}")
    print(f"📖 API documentation: http://localhost:{_port}/docs")

    uvicorn.run(
        "main:app",
        host="0.0.0.0",
        port=_port,
        reload=_debug_mode,
        log_level="info"
    )

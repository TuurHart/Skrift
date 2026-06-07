"""
System monitoring API endpoints
Handles resource monitoring and processing status
"""

import time
import psutil
import os
from fastapi import APIRouter
from models import SystemResources, SystemStatus
from utils.status_tracker import status_tracker

router = APIRouter()

@router.get("/resources", response_model=SystemResources)
async def get_system_resources():
    """
    Get current system resource usage
    Returns CPU, RAM, and temperature information
    """
    try:
        # CPU usage
        cpu_usage = psutil.cpu_percent(interval=1)
        
        # Memory usage
        memory = psutil.virtual_memory()
        ram_used_gb = memory.used / (1024**3)  # Convert to GB
        ram_total_gb = memory.total / (1024**3)  # Convert to GB
        
        # Disk usage for output folder (optional)
        disk_usage = None
        try:
            from config.settings import get_output_folder
            output_folder = get_output_folder()
            if output_folder.exists():
                disk_stat = psutil.disk_usage(str(output_folder))
                disk_usage = (disk_stat.used / disk_stat.total) * 100
        except (OSError, AttributeError, ImportError):
            pass

        # CPU temperature (Mac-specific, optional)
        core_temp = None
        try:
            # This is Mac-specific and may not work on all systems
            # Temperature monitoring requires additional permissions
            temps = psutil.sensors_temperatures()
            if temps:
                # Try to get CPU temperature from common sensor names
                for name, entries in temps.items():
                    if 'cpu' in name.lower() or 'core' in name.lower():
                        if entries:
                            core_temp = entries[0].current
                            break
        except (OSError, AttributeError):
            pass
        
        return SystemResources(
            cpuUsage=round(cpu_usage, 1),
            ramUsed=round(ram_used_gb, 2),
            ramTotal=round(ram_total_gb, 2),
            coreTemp=core_temp,
            diskUsed=round(disk_usage, 1) if disk_usage else None
        )
    
    except Exception as e:
        # Return default values if monitoring fails
        return SystemResources(
            cpuUsage=0.0,
            ramUsed=8.0,
            ramTotal=24.0,
            coreTemp=None,
            diskUsed=None
        )

@router.get("/status", response_model=SystemStatus)
async def get_system_status():
    """
    Get current processing status
    Returns information about active processing
    """
    try:
        # Get files currently being processed
        processing_files = status_tracker.get_processing_queue()
        
        # Determine current processing status
        processing = len(processing_files) > 0
        current_file = None
        current_step = None
        
        if processing_files:
            # Get the first processing file
            file = processing_files[0]
            current_file = file.filename
            
            # Determine current step
            steps = file.steps
            if steps.transcribe.value == "processing":
                current_step = "transcribing"
            elif steps.sanitise.value == "processing":
                current_step = "sanitizing"
            elif steps.enhance.value == "processing":
                current_step = "enhancing"
            elif steps.export.value == "processing":
                current_step = "exporting"
        
        return SystemStatus(
            processing=processing,
            currentFile=current_file,
            currentStep=current_step,
            queueLength=len(processing_files)
        )
    
    except Exception as e:
        # Return default status if monitoring fails
        return SystemStatus(
            processing=False,
            currentFile=None,
            currentStep=None,
            queueLength=0
        )

@router.get("/health")
async def health_check():
    """
    Comprehensive health check for the system
    Returns detailed system and component status
    """
    try:
        # System resources
        resources = await get_system_resources()
        
        # Processing status
        status = await get_system_status()
        
        # Check transcription engine (parakeet-mlx)
        transcription_modules = {}
        try:
            import importlib
            parakeet_available = importlib.util.find_spec("parakeet_mlx") is not None
            transcription_modules = {
                "parakeet": {
                    "available": parakeet_available,
                    "engine": "parakeet-mlx",
                }
            }
        except Exception as e:
            transcription_modules = {"error": str(e)}
        
        # File statistics
        all_files = status_tracker.get_all_files()
        file_stats = {
            "total_files": len(all_files),
            "processing_files": len(status_tracker.get_processing_queue()),
            "completed_files": len([f for f in all_files if f.steps.export.value == "done"]),
            "error_files": len([f for f in all_files if f.error is not None])
        }
        
        return {
            "status": "healthy",
            "timestamp": time.time(),
            "uptime_hours": round((time.time() - psutil.boot_time()) / 3600, 1),
            "resources": resources.model_dump(),
            "processing": status.model_dump(),
            "transcription_modules": transcription_modules,
            "file_statistics": file_stats,
            "python_version": os.sys.version,
            "platform": os.name
        }
    
    except Exception as e:
        return {
            "status": "error",
            "message": str(e),
            "timestamp": None
        }

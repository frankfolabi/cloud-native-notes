# ============================================
# Week 3: FastAPI App using Redis + ConfigMaps + Secrets
# ============================================

from fastapi import FastAPI, HTTPException
from contextlib import asynccontextmanager
from pydantic import BaseModel
from typing import List, Optional
import uuid
from datetime import datetime
import logging

from app.config import settings
from app.database import store

# Logging
logging.basicConfig(level=settings.LOG_LEVEL.upper())
logger = logging.getLogger(__name__)

# ============ Pydantic Models ============
class NoteCreate(BaseModel):
    title: str
    content: str

class NoteUpdate(BaseModel):
    title: Optional[str] = None
    content: Optional[str] = None

class Note(BaseModel):
    id: str
    title: str
    content: str
    created_at: datetime
    updated_at: datetime

# ============ Lifespan (startup/shutdown) ============
@asynccontextmanager
async def lifespan(app: FastAPI):
    # Startup: connect to Redis
    await store.connect()
    logger.info(f"🚀 {settings.APP_NAME} starting on port {settings.PORT}")
    yield
    # Shutdown
    await store.close()
    logger.info("Shutting down gracefully")

app = FastAPI(title=settings.APP_NAME, lifespan=lifespan)

# ============ Health Endpoints ============
@app.get("/health")
async def health():
    return {
        "status": "healthy",
        "app": settings.APP_NAME,
        "redis_connected": store.connected,
        "max_notes": settings.MAX_NOTES,
    }

@app.get("/")
async def root():
    return {
        "message": settings.APP_NAME,
        "endpoints": ["/health", "/api/notes", "/debug/config"],
    }

# ============ Debug Endpoint (ConfigMap/Secret Demo) ============
@app.get("/debug/config")
async def debug_config():
    """Shows what config was loaded from ConfigMap + Secret"""
    return {
        "app_name": settings.APP_NAME,
        "log_level": settings.LOG_LEVEL,
        "max_notes": settings.MAX_NOTES,
        "redis_host": settings.REDIS_HOST,
        "redis_port": settings.REDIS_PORT,
        "redis_password_set": bool(settings.REDIS_PASSWORD),  # Never return the actual password
        "redis_connected": store.connected,
    }

# ============ CRUD Endpoints (USING REDIS) ============
@app.get("/api/notes", response_model=List[Note])
async def list_notes():
    keys = await store.keys("note:*")
    if not keys:
        return []
    
    notes_data = await store.mget(keys)
    notes = []
    for idx, data in enumerate(notes_data):
        if data:
            note_id = keys[idx].replace("note:", "")
            notes.append(Note(id=note_id, **data))
    
    # Sort by created_at (newest first)
    notes.sort(key=lambda x: x.created_at, reverse=True)
    return notes

@app.post("/api/notes", response_model=Note, status_code=201)
async def create_note(note: NoteCreate):
    # Check MAX_NOTES from ConfigMap
    current_count = await store.count()
    if current_count >= settings.MAX_NOTES:
        raise HTTPException(
            status_code=400,
            detail=f"Maximum notes limit reached ({settings.MAX_NOTES})"
        )
    
    note_id = str(uuid.uuid4())[:8]
    now = datetime.utcnow()
    
    note_data = {
        "title": note.title,
        "content": note.content,
        "created_at": now.isoformat(),
        "updated_at": now.isoformat(),
    }
    
    await store.set(f"note:{note_id}", note_data)
    logger.info(f"Note created: {note_id}")
    
    return Note(id=note_id, **note_data)

@app.get("/api/notes/{note_id}", response_model=Note)
async def get_note(note_id: str):
    data = await store.get(f"note:{note_id}")
    if not data:
        raise HTTPException(status_code=404, detail="Note not found")
    return Note(id=note_id, **data)

@app.put("/api/notes/{note_id}", response_model=Note)
async def update_note(note_id: str, note: NoteUpdate):
    existing = await store.get(f"note:{note_id}")
    if not existing:
        raise HTTPException(status_code=404, detail="Note not found")
    
    if note.title:
        existing["title"] = note.title
    if note.content:
        existing["content"] = note.content
    existing["updated_at"] = datetime.utcnow().isoformat()
    
    await store.set(f"note:{note_id}", existing)
    return Note(id=note_id, **existing)

@app.delete("/api/notes/{note_id}")
async def delete_note(note_id: str):
    deleted = await store.delete(f"note:{note_id}")
    if not deleted:
        raise HTTPException(status_code=404, detail="Note not found")
    return {"message": "Note deleted"}

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=settings.PORT)

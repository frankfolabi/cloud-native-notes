# ============================================
# Week 7: FastAPI App using Redis + ConfigMaps + Secrets + Metrics
# ============================================

from fastapi import FastAPI, HTTPException, Request, Response
from contextlib import asynccontextmanager
from pydantic import BaseModel
from typing import List, Optional
import uuid
from datetime import datetime
import logging
import time

from prometheus_client import generate_latest, CONTENT_TYPE_LATEST

from app.config import settings
from app.database import store
from app.metrics import (
    http_requests_total,
    http_request_duration,
    notes_created,
    active_notes,
    redis_connected,
)

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


# ============ Route normalizer ============
def normalize_route(path: str) -> str:
    """
    Collapse variable path segments so metric labels stay low-cardinality.

    /api/notes/a1b2c3d4   -> /api/notes/{note_id}
    /api/notes/a1b2c3d4/x -> /api/notes/{note_id}/x
    """
    parts = path.strip("/").split("/")
    out = []
    for i, part in enumerate(parts):
        # Replace UUID-ish / short-id segment immediately after 'notes'
        if i > 0 and parts[i - 1] == "notes" and part:
            out.append("{note_id}")
        else:
            out.append(part)
    return "/" + "/".join(out) if out else "/"


# ============ Lifespan (startup/shutdown) ============
@asynccontextmanager
async def lifespan(app: FastAPI):
    # Startup: connect to Redis
    await store.connect()
    logger.info(f"🚀 {settings.APP_NAME} starting on port {settings.PORT}")

    # Mark Redis health for Prometheus
    redis_connected.set(1 if store.connected else 0)

    # Recompute active_notes on boot so the gauge survives restarts
    try:
        count = await store.count()
        active_notes.set(count)
        logger.info(f"📊 active_notes initialised to {count}")
    except Exception as e:
        logger.warning(f"Could not initialise active_notes gauge: {e}")

    yield

    # Shutdown
    await store.close()
    redis_connected.set(0)
    logger.info("Shutting down gracefully")


app = FastAPI(title=settings.APP_NAME, lifespan=lifespan)


# ============ Middleware (prometheus instrumentation) ============
@app.middleware("http")
async def metrics_middleware(request: Request, call_next):
    # Skip instrumenting the /metrics endpoint itself to avoid recursion
    if request.url.path == "/metrics":
        return await call_next(request)

    start = time.time()
    try:
        response = await call_next(request)
        status = response.status_code
    except Exception:
        # Count 500s even if the exception handler changes the response
        status = 500
        raise
    finally:
        duration = time.time() - start
        route = normalize_route(request.url.path)
        http_requests_total.labels(
            method=request.method,
            route=route,
            status=str(status),
        ).inc()
        http_request_duration.labels(
            method=request.method,
            route=route,
        ).observe(duration)

    return response


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
        "endpoints": [
            "/health",
            "/api/notes",
            "/debug/config",
            "/metrics",
        ],
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
        "redis_password_set": bool(settings.REDIS_PASSWORD),
        "redis_connected": store.connected,
    }


# ============ Prometheus metrics endpoint ============
@app.get("/metrics")
async def metrics():
    # Refresh the Redis health gauge on each scrape (cheap: reads a bool)
    redis_connected.set(1 if store.connected else 0)
    return Response(
        content=generate_latest(),
        media_type=CONTENT_TYPE_LATEST,
    )


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

    notes.sort(key=lambda x: x.created_at, reverse=True)
    return notes


@app.post("/api/notes", response_model=Note, status_code=201)
async def create_note(note: NoteCreate):
    current_count = await store.count()
    if current_count >= settings.MAX_NOTES:
        raise HTTPException(
            status_code=400,
            detail=f"Maximum notes limit reached ({settings.MAX_NOTES})",
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

    # --- Metrics ---
    notes_created.inc()
    active_notes.set(current_count + 1)

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

    # --- Metrics ---
    try:
        remaining = await store.count()
        active_notes.set(remaining)
    except Exception as e:
        logger.warning(f"Could not refresh active_notes gauge: {e}")

    return {"message": "Note deleted"}


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=settings.PORT)
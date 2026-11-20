# app/metrics.py
from prometheus_client import Counter, Histogram, Gauge

# --- HTTP request metrics ---
http_requests_total = Counter(
    "http_requests_total",
    "Total number of HTTP requests",
    ["method", "route", "status"],
)

http_request_duration = Histogram(
    "http_request_duration_seconds",
    "HTTP request duration in seconds",
    ["method", "route"],
    buckets=(0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1.0, 2.5, 5.0, 10.0),
)

# --- Business metrics ---
notes_created = Counter(
    "notes_created_total",
    "Total number of notes created since app start",
)

active_notes = Gauge(
    "active_notes",
    "Number of notes currently stored",
)

# --- Dependency health ---
redis_connected = Gauge(
    "redis_connected",
    "1 if the backend is connected to Redis, 0 otherwise",
)

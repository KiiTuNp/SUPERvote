#!/usr/bin/env python3
"""
SUPERvote Production Server - State-of-the-art FastAPI Application
High-performance, fail-proof, production-ready polling system
"""

import asyncio
import logging
import os
import sys
import time
import uuid
from contextlib import asynccontextmanager
from datetime import datetime, timedelta, timezone
from typing import Any, Dict, List, Optional, Set

import uvicorn
from fastapi import (
    FastAPI, HTTPException, WebSocket, WebSocketDisconnect, Depends,
    Request, Response, BackgroundTasks, status
)
from fastapi.middleware.cors import CORSMiddleware
from fastapi.middleware.gzip import GZipMiddleware
from fastapi.middleware.trustedhost import TrustedHostMiddleware
from fastapi.responses import JSONResponse, StreamingResponse
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from motor.motor_asyncio import AsyncIOMotorClient, AsyncIOMotorDatabase
from pydantic import BaseModel, Field, validator
from pymongo import IndexModel, ASCENDING, DESCENDING
from pymongo.errors import DuplicateKeyError
import redis.asyncio as redis
from reportlab.lib.pagesizes import letter
from reportlab.pdfgen import canvas
from reportlab.lib.units import inch
import io
import json
import hashlib
import secrets
from prometheus_client import Counter, Histogram, Gauge, generate_latest
from starlette.middleware.base import BaseHTTPMiddleware
from starlette.requests import Request as StarletteRequest
from starlette.responses import Response as StarletteResponse
import structlog

# Configure structured logging
structlog.configure(
    processors=[
        structlog.stdlib.filter_by_level,
        structlog.stdlib.add_logger_name,
        structlog.stdlib.add_log_level,
        structlog.stdlib.PositionalArgumentsFormatter(),
        structlog.processors.TimeStamper(fmt="iso"),
        structlog.processors.StackInfoRenderer(),
        structlog.processors.format_exc_info,
        structlog.processors.UnicodeDecoder(),
        structlog.processors.JSONRenderer()
    ],
    context_class=dict,
    logger_factory=structlog.stdlib.LoggerFactory(),
    wrapper_class=structlog.stdlib.BoundLogger,
    cache_logger_on_first_use=True,
)

logger = structlog.get_logger()

# Metrics
REQUEST_COUNT = Counter('http_requests_total', 'Total HTTP requests', ['method', 'endpoint', 'status'])
REQUEST_DURATION = Histogram('http_request_duration_seconds', 'Request duration')
ACTIVE_CONNECTIONS = Gauge('websocket_connections_active', 'Active WebSocket connections')
ACTIVE_ROOMS = Gauge('active_rooms_total', 'Total active rooms')
ACTIVE_POLLS = Gauge('active_polls_total', 'Total active polls')

# Configuration
class Config:
    # Database
    MONGO_URL = os.getenv("MONGO_URL", "mongodb://localhost:27017")
    DB_NAME = os.getenv("DB_NAME", "poll_app_prod")
    
    # Redis Cache
    REDIS_URL = os.getenv("REDIS_URL", "redis://localhost:6379")
    CACHE_TTL = int(os.getenv("CACHE_TTL", "300"))  # 5 minutes
    
    # Security
    SECRET_KEY = os.getenv("SECRET_KEY", secrets.token_urlsafe(32))
    CORS_ORIGINS = os.getenv("CORS_ORIGINS", "https://vote.super-csn.ca").split(",")
    TRUSTED_HOSTS = os.getenv("TRUSTED_HOSTS", "vote.super-csn.ca,localhost").split(",")
    
    # Performance
    MAX_CONNECTIONS_PER_IP = int(os.getenv("MAX_CONNECTIONS_PER_IP", "10"))
    RATE_LIMIT_REQUESTS = int(os.getenv("RATE_LIMIT_REQUESTS", "100"))
    RATE_LIMIT_WINDOW = int(os.getenv("RATE_LIMIT_WINDOW", "60"))
    
    # Application
    MAX_ROOM_ID_LENGTH = 10
    MAX_PARTICIPANT_NAME_LENGTH = 50
    MAX_POLL_QUESTION_LENGTH = 500
    MAX_POLL_OPTIONS = 20
    MAX_OPTION_LENGTH = 200
    ROOM_CLEANUP_HOURS = int(os.getenv("ROOM_CLEANUP_HOURS", "24"))

config = Config()

# Enhanced Models with validation
class ParticipantCreate(BaseModel):
    room_id: str = Field(..., min_length=3, max_length=config.MAX_ROOM_ID_LENGTH)
    participant_name: str = Field(..., min_length=1, max_length=config.MAX_PARTICIPANT_NAME_LENGTH)
    
    @validator('room_id')
    def validate_room_id(cls, v):
        if not v.replace('_', '').replace('-', '').isalnum():
            raise ValueError('Room ID must be alphanumeric with optional hyphens and underscores')
        return v.upper()
    
    @validator('participant_name')
    def validate_participant_name(cls, v):
        return v.strip()

class PollCreate(BaseModel):
    room_id: str = Field(..., min_length=3, max_length=config.MAX_ROOM_ID_LENGTH)
    question: str = Field(..., min_length=1, max_length=config.MAX_POLL_QUESTION_LENGTH)
    options: List[str] = Field(..., min_items=2, max_items=config.MAX_POLL_OPTIONS)
    timer_minutes: Optional[int] = Field(None, ge=1, le=120)  # 1-120 minutes
    
    @validator('options')
    def validate_options(cls, v):
        if len(v) != len(set(v)):
            raise ValueError('Poll options must be unique')
        for option in v:
            if len(option.strip()) == 0:
                raise ValueError('Poll options cannot be empty')
            if len(option) > config.MAX_OPTION_LENGTH:
                raise ValueError(f'Poll option too long (max {config.MAX_OPTION_LENGTH} characters)')
        return [opt.strip() for opt in v]

class Vote(BaseModel):
    participant_token: str
    selected_option: str
    
    @validator('selected_option')
    def validate_selected_option(cls, v):
        return v.strip()

# Enhanced Database Models
class Room:
    def __init__(self, room_id: str, organizer_name: str):
        self.room_id = room_id
        self.organizer_name = organizer_name
        self.created_at = datetime.now(timezone.utc)
        self.last_activity = datetime.now(timezone.utc)
        self.participants = []
        self.polls = []
        self.is_active = True

class Participant:
    def __init__(self, participant_id: str, room_id: str, name: str):
        self.participant_id = participant_id
        self.room_id = room_id
        self.name = name
        self.token = secrets.token_urlsafe(32)
        self.joined_at = datetime.now(timezone.utc)
        self.approval_status = "pending"  # pending, approved, denied
        self.is_active = True

class Poll:
    def __init__(self, poll_id: str, room_id: str, question: str, options: List[str], timer_minutes: Optional[int] = None):
        self.poll_id = poll_id
        self.room_id = room_id
        self.question = question
        self.options = options
        self.votes = {}
        self.created_at = datetime.now(timezone.utc)
        self.started_at = None
        self.ends_at = None
        self.status = "created"  # created, active, completed, cancelled
        self.timer_minutes = timer_minutes

# Connection Managers
class ConnectionManager:
    def __init__(self):
        self.active_connections: Dict[str, Set[WebSocket]] = {}
        self.connection_ips: Dict[WebSocket, str] = {}
        self.ip_connections: Dict[str, Set[WebSocket]] = {}
    
    async def connect(self, websocket: WebSocket, room_id: str, client_ip: str):
        # Rate limiting by IP
        if client_ip in self.ip_connections:
            if len(self.ip_connections[client_ip]) >= config.MAX_CONNECTIONS_PER_IP:
                await websocket.close(code=1008, reason="Too many connections from this IP")
                return False
        
        await websocket.accept()
        
        if room_id not in self.active_connections:
            self.active_connections[room_id] = set()
        
        self.active_connections[room_id].add(websocket)
        self.connection_ips[websocket] = client_ip
        
        if client_ip not in self.ip_connections:
            self.ip_connections[client_ip] = set()
        self.ip_connections[client_ip].add(websocket)
        
        ACTIVE_CONNECTIONS.inc()
        logger.info("WebSocket connected", room_id=room_id, client_ip=client_ip)
        return True
    
    def disconnect(self, websocket: WebSocket, room_id: str):
        if room_id in self.active_connections:
            self.active_connections[room_id].discard(websocket)
            if not self.active_connections[room_id]:
                del self.active_connections[room_id]
        
        client_ip = self.connection_ips.pop(websocket, None)
        if client_ip and client_ip in self.ip_connections:
            self.ip_connections[client_ip].discard(websocket)
            if not self.ip_connections[client_ip]:
                del self.ip_connections[client_ip]
        
        ACTIVE_CONNECTIONS.dec()
        logger.info("WebSocket disconnected", room_id=room_id, client_ip=client_ip)
    
    async def broadcast_to_room(self, room_id: str, message: dict):
        if room_id in self.active_connections:
            dead_connections = set()
            for connection in self.active_connections[room_id].copy():
                try:
                    await connection.send_json(message)
                except Exception as e:
                    logger.warning("Failed to send message", error=str(e))
                    dead_connections.add(connection)
            
            # Clean up dead connections
            for dead_conn in dead_connections:
                self.disconnect(dead_conn, room_id)

manager = ConnectionManager()

# Rate Limiting Middleware
class RateLimitMiddleware(BaseHTTPMiddleware):
    def __init__(self, app, calls: int = 100, period: int = 60):
        super().__init__(app)
        self.calls = calls
        self.period = period
        self.requests: Dict[str, List[float]] = {}
    
    async def dispatch(self, request: StarletteRequest, call_next):
        client_ip = request.client.host
        now = time.time()
        
        # Clean old requests
        if client_ip in self.requests:
            self.requests[client_ip] = [req_time for req_time in self.requests[client_ip] 
                                      if now - req_time < self.period]
        else:
            self.requests[client_ip] = []
        
        # Check rate limit
        if len(self.requests[client_ip]) >= self.calls:
            return JSONResponse(
                status_code=429,
                content={"error": "Rate limit exceeded", "retry_after": self.period}
            )
        
        # Add current request
        self.requests[client_ip].append(now)
        
        response = await call_next(request)
        return response

# Metrics Middleware
class MetricsMiddleware(BaseHTTPMiddleware):
    async def dispatch(self, request: StarletteRequest, call_next):
        start_time = time.time()
        
        response = await call_next(request)
        
        duration = time.time() - start_time
        REQUEST_DURATION.observe(duration)
        REQUEST_COUNT.labels(
            method=request.method,
            endpoint=request.url.path,
            status=response.status_code
        ).inc()
        
        return response

# Correlation ID Middleware
class CorrelationIDMiddleware(BaseHTTPMiddleware):
    async def dispatch(self, request: StarletteRequest, call_next):
        correlation_id = request.headers.get("X-Correlation-ID", str(uuid.uuid4()))
        
        # Add to structlog context
        structlog.contextvars.clear_contextvars()
        structlog.contextvars.bind_contextvars(correlation_id=correlation_id)
        
        response = await call_next(request)
        response.headers["X-Correlation-ID"] = correlation_id
        
        return response

# Database and Cache Management
class DatabaseManager:
    def __init__(self):
        self.client: Optional[AsyncIOMotorClient] = None
        self.db: Optional[AsyncIOMotorDatabase] = None
        self.redis_client: Optional[redis.Redis] = None
    
    async def connect_db(self):
        try:
            self.client = AsyncIOMotorClient(
                config.MONGO_URL,
                maxPoolSize=50,
                minPoolSize=10,
                maxIdleTimeMS=30000,
                serverSelectionTimeoutMS=5000,
                socketTimeoutMS=20000,
                connectTimeoutMS=20000,
                retryWrites=True
            )
            self.db = self.client[config.DB_NAME]
            
            # Create indexes for performance
            await self.create_indexes()
            
            # Connect to Redis
            self.redis_client = redis.from_url(
                config.REDIS_URL,
                encoding="utf-8",
                decode_responses=True,
                socket_connect_timeout=5,
                socket_timeout=5,
                retry_on_timeout=True,
                health_check_interval=30
            )
            
            logger.info("Database and cache connected successfully")
            
        except Exception as e:
            logger.error("Failed to connect to database", error=str(e))
            raise
    
    async def create_indexes(self):
        """Create database indexes for optimal performance"""
        try:
            # Rooms collection
            await self.db.rooms.create_indexes([
                IndexModel([("room_id", ASCENDING)], unique=True),
                IndexModel([("created_at", DESCENDING)]),
                IndexModel([("last_activity", DESCENDING)]),
                IndexModel([("is_active", ASCENDING)])
            ])
            
            # Participants collection
            await self.db.participants.create_indexes([
                IndexModel([("participant_id", ASCENDING)], unique=True),
                IndexModel([("room_id", ASCENDING)]),
                IndexModel([("token", ASCENDING)], unique=True),
                IndexModel([("approval_status", ASCENDING)]),
                IndexModel([("joined_at", DESCENDING)])
            ])
            
            # Polls collection
            await self.db.polls.create_indexes([
                IndexModel([("poll_id", ASCENDING)], unique=True),
                IndexModel([("room_id", ASCENDING)]),
                IndexModel([("status", ASCENDING)]),
                IndexModel([("created_at", DESCENDING)]),
                IndexModel([("ends_at", ASCENDING)])
            ])
            
            # Votes collection
            await self.db.votes.create_indexes([
                IndexModel([("poll_id", ASCENDING), ("participant_id", ASCENDING)], unique=True),
                IndexModel([("poll_id", ASCENDING)]),
                IndexModel([("participant_id", ASCENDING)]),
                IndexModel([("created_at", DESCENDING)])
            ])
            
            logger.info("Database indexes created successfully")
            
        except Exception as e:
            logger.error("Failed to create indexes", error=str(e))
    
    async def disconnect_db(self):
        if self.client:
            self.client.close()
        if self.redis_client:
            await self.redis_client.close()
        logger.info("Database connections closed")
    
    async def get_from_cache(self, key: str) -> Optional[Any]:
        try:
            if self.redis_client:
                cached = await self.redis_client.get(key)
                return json.loads(cached) if cached else None
        except Exception as e:
            logger.warning("Cache get failed", key=key, error=str(e))
        return None
    
    async def set_cache(self, key: str, value: Any, ttl: int = None):
        try:
            if self.redis_client:
                await self.redis_client.setex(
                    key, 
                    ttl or config.CACHE_TTL, 
                    json.dumps(value, default=str)
                )
        except Exception as e:
            logger.warning("Cache set failed", key=key, error=str(e))
    
    async def delete_cache(self, key: str):
        try:
            if self.redis_client:
                await self.redis_client.delete(key)
        except Exception as e:
            logger.warning("Cache delete failed", key=key, error=str(e))
    
    async def health_check(self) -> Dict[str, str]:
        """Health check for database and cache"""
        health = {}
        
        try:
            await self.db.command("ping")
            health["mongodb"] = "healthy"
        except Exception as e:
            health["mongodb"] = f"unhealthy: {str(e)}"
        
        try:
            if self.redis_client:
                await self.redis_client.ping()
                health["redis"] = "healthy"
            else:
                health["redis"] = "not_configured"
        except Exception as e:
            health["redis"] = f"unhealthy: {str(e)}"
        
        return health

db_manager = DatabaseManager()

# Lifespan management
@asynccontextmanager
async def lifespan(app: FastAPI):
    # Startup
    await db_manager.connect_db()
    logger.info("SUPERvote Production Server starting up")
    
    # Background tasks
    cleanup_task = asyncio.create_task(cleanup_old_rooms())
    poll_timer_task = asyncio.create_task(poll_timer_manager())
    
    yield
    
    # Shutdown
    cleanup_task.cancel()
    poll_timer_task.cancel()
    await db_manager.disconnect_db()
    logger.info("SUPERvote Production Server shutting down")

# Create FastAPI app with all optimizations
app = FastAPI(
    title="SUPERvote Production API",
    description="State-of-the-art, high-performance polling system",
    version="2.0.0",
    lifespan=lifespan,
    docs_url="/api/docs" if os.getenv("ENVIRONMENT") != "production" else None,
    redoc_url="/api/redoc" if os.getenv("ENVIRONMENT") != "production" else None
)

# Add middleware in correct order
app.add_middleware(CorrelationIDMiddleware)
app.add_middleware(MetricsMiddleware)
app.add_middleware(RateLimitMiddleware, 
                  calls=config.RATE_LIMIT_REQUESTS, 
                  period=config.RATE_LIMIT_WINDOW)
app.add_middleware(GZipMiddleware, minimum_size=1000)
app.add_middleware(TrustedHostMiddleware, allowed_hosts=config.TRUSTED_HOSTS)
app.add_middleware(
    CORSMiddleware,
    allow_origins=config.CORS_ORIGINS,
    allow_credentials=True,
    allow_methods=["GET", "POST", "PUT", "DELETE", "OPTIONS"],
    allow_headers=["*"],
)

# Security
security = HTTPBearer(auto_error=False)

# Dependency injection
async def get_db():
    return db_manager.db

async def get_cache():
    return db_manager.redis_client

# Enhanced Error Handling
class SUPERvoteException(HTTPException):
    def __init__(self, status_code: int, detail: str, error_code: str = None):
        super().__init__(status_code, detail)
        self.error_code = error_code
        logger.error("Application error", 
                    status_code=status_code, 
                    detail=detail, 
                    error_code=error_code)

@app.exception_handler(SUPERvoteException)
async def supervote_exception_handler(request: Request, exc: SUPERvoteException):
    return JSONResponse(
        status_code=exc.status_code,
        content={
            "error": exc.detail,
            "error_code": exc.error_code,
            "timestamp": datetime.now(timezone.utc).isoformat(),
            "path": request.url.path
        }
    )

@app.exception_handler(Exception)
async def global_exception_handler(request: Request, exc: Exception):
    logger.error("Unhandled exception", 
                error=str(exc), 
                path=request.url.path,
                method=request.method)
    
    return JSONResponse(
        status_code=500,
        content={
            "error": "Internal server error",
            "error_code": "INTERNAL_ERROR",
            "timestamp": datetime.now(timezone.utc).isoformat(),
            "path": request.url.path
        }
    )

# Background Tasks
async def cleanup_old_rooms():
    """Cleanup old inactive rooms"""
    while True:
        try:
            cutoff_time = datetime.now(timezone.utc) - timedelta(hours=config.ROOM_CLEANUP_HOURS)
            
            # Find and delete old rooms
            old_rooms = await db_manager.db.rooms.find({
                "last_activity": {"$lt": cutoff_time},
                "is_active": True
            }).to_list(length=100)
            
            for room in old_rooms:
                room_id = room["room_id"]
                
                # Delete associated data
                await db_manager.db.participants.delete_many({"room_id": room_id})
                await db_manager.db.polls.delete_many({"room_id": room_id})
                await db_manager.db.votes.delete_many({"room_id": room_id})
                await db_manager.db.rooms.delete_one({"room_id": room_id})
                
                # Clear cache
                await db_manager.delete_cache(f"room:{room_id}")
                
                logger.info("Cleaned up old room", room_id=room_id)
            
            # Update metrics
            active_rooms_count = await db_manager.db.rooms.count_documents({"is_active": True})
            active_polls_count = await db_manager.db.polls.count_documents({"status": "active"})
            
            ACTIVE_ROOMS.set(active_rooms_count)
            ACTIVE_POLLS.set(active_polls_count)
            
        except Exception as e:
            logger.error("Cleanup task failed", error=str(e))
        
        await asyncio.sleep(3600)  # Run every hour

async def poll_timer_manager():
    """Manage poll timers"""
    while True:
        try:
            now = datetime.now(timezone.utc)
            
            # Find polls that should be stopped
            expired_polls = await db_manager.db.polls.find({
                "status": "active",
                "ends_at": {"$lte": now}
            }).to_list(length=100)
            
            for poll_doc in expired_polls:
                poll_id = poll_doc["poll_id"]
                room_id = poll_doc["room_id"]
                
                # Stop the poll
                await db_manager.db.polls.update_one(
                    {"poll_id": poll_id},
                    {"$set": {"status": "completed"}}
                )
                
                # Broadcast to room
                await manager.broadcast_to_room(room_id, {
                    "type": "poll_stopped",
                    "poll_id": poll_id,
                    "reason": "timer_expired"
                })
                
                logger.info("Auto-stopped poll", poll_id=poll_id, room_id=room_id)
                
        except Exception as e:
            logger.error("Poll timer task failed", error=str(e))
        
        await asyncio.sleep(10)  # Check every 10 seconds

# API Routes with enhanced functionality

@app.get("/api/health")
async def health_check():
    """Comprehensive health check"""
    health_status = await db_manager.health_check()
    
    overall_status = "healthy" if all(
        status == "healthy" or status == "not_configured" 
        for status in health_status.values()
    ) else "unhealthy"
    
    return {
        "status": overall_status,
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "version": "2.0.0",
        "services": health_status,
        "uptime_seconds": time.time() - start_time
    }

@app.get("/api/metrics")
async def get_metrics():
    """Prometheus metrics endpoint"""
    return Response(
        content=generate_latest(),
        media_type="text/plain"
    )

# I'll continue with the rest of the enhanced API endpoints...
# This is getting quite long, so let me create this as a foundation and then continue with more components

start_time = time.time()

if __name__ == "__main__":
    uvicorn.run(
        "server_production:app",
        host="0.0.0.0",
        port=8001,
        workers=1,
        loop="uvloop",
        http="httptools",
        access_log=False,
        log_config={
            "version": 1,
            "disable_existing_loggers": False,
            "formatters": {
                "default": {
                    "format": "%(asctime)s - %(name)s - %(levelname)s - %(message)s",
                },
            },
            "handlers": {
                "default": {
                    "formatter": "default",
                    "class": "logging.StreamHandler",
                    "stream": "ext://sys.stdout",
                },
            },
            "root": {
                "level": "INFO",
                "handlers": ["default"],
            },
        }
    )
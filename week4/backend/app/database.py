# ============================================
# Redis Client – Uses password from Secret
# ============================================

import asyncio
import json
import logging
from typing import Optional, Dict

import redis.asyncio as redis

from app.config import settings

logger = logging.getLogger(__name__)


class NoteStore:
    def __init__(self):
        self.client: Optional[redis.Redis] = None
        self.in_memory: Dict[str, Dict] = {}
        self.connected = False

    async def connect(self):
        self.client = redis.Redis(
            host=settings.REDIS_HOST,
            port=settings.REDIS_PORT,
            password=settings.REDIS_PASSWORD or None,
            decode_responses=True,
        )

        retry_delay = 5

        while True:
            try:
                await self.client.ping()

                self.connected = True

                logger.info(
                    "✅ Connected to Redis at %s:%s",
                    settings.REDIS_HOST,
                    settings.REDIS_PORT,
                )

                logger.info(
                    "🔐 Password provided: %s",
                    "Yes" if settings.REDIS_PASSWORD else "No",
                )

                return

            except Exception as e:
                self.connected = False

                logger.warning(
                    "❌ Redis unavailable: %s. "
                    "Retrying in %s seconds...",
                    e,
                    retry_delay,
                )

                await asyncio.sleep(retry_delay)

    async def get(self, key: str) -> Optional[Dict]:
        if not self.connected or not self.client:
            raise RuntimeError("Redis is not connected")

        data = await self.client.get(key)
        return json.loads(data) if data else None

    async def set(self, key: str, value: Dict) -> None:
        if not self.connected or not self.client:
            raise RuntimeError("Redis is not connected")

        await self.client.set(key, json.dumps(value))

    async def delete(self, key: str) -> bool:
        if not self.connected or not self.client:
            raise RuntimeError("Redis is not connected")

        return await self.client.delete(key) > 0

    async def keys(self, pattern: str = "note:*") -> list:
        if not self.connected or not self.client:
            raise RuntimeError("Redis is not connected")

        return await self.client.keys(pattern)

    async def mget(self, keys: list) -> list:
        if not self.connected or not self.client:
            raise RuntimeError("Redis is not connected")

        values = await self.client.mget(keys)

        return [
            json.loads(value) if value else None
            for value in values
        ]

    async def count(self) -> int:
        if not self.connected or not self.client:
            raise RuntimeError("Redis is not connected")

        return len(await self.client.keys("note:*"))

    async def close(self):
        if self.client:
            await self.client.aclose()


store = NoteStore()
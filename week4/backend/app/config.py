from pydantic_settings import BaseSettings
from typing import Optional

class Settings(BaseSettings):
    # ConfigMap
    PORT: int = 3000
    APP_NAME: str = "Cloud Native Notes"
    LOG_LEVEL: str = "info"
    MAX_NOTES: int = 100
    REDIS_HOST: str = "localhost"
    REDIS_PORT: int = 6379
    
    # Secret
    REDIS_PASSWORD: Optional[str] = None
    
    class Config:
        env_file = ".env"
        env_file_encoding = "utf-8"

settings = Settings()

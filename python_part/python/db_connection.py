"""
Database connection helper.

Reads database credentials from environment variables.
Create a local .env file based on .env.example.
Do not commit the real .env file to GitHub.
"""

import os

from dotenv import load_dotenv
from sqlalchemy import create_engine


load_dotenv()


def get_database_engine():
    """Create a SQLAlchemy engine using environment variables."""
    db_user = os.getenv("DB_USER")
    db_password = os.getenv("DB_PASSWORD")
    db_host = os.getenv("DB_HOST")
    db_port = os.getenv("DB_PORT", "5432")
    db_name = os.getenv("DB_NAME", "postgres")

    missing_values = [
        name
        for name, value in {
            "DB_USER": db_user,
            "DB_PASSWORD": db_password,
            "DB_HOST": db_host,
            "DB_PORT": db_port,
            "DB_NAME": db_name,
        }.items()
        if not value
    ]

    if missing_values:
        raise ValueError(f"Missing environment variables: {', '.join(missing_values)}")

    database_url = (
        f"postgresql+psycopg2://{db_user}:{db_password}"
        f"@{db_host}:{db_port}/{db_name}"
    )

    return create_engine(database_url)

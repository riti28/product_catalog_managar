"""Import structured CSV product records into MySQL."""

from __future__ import annotations

import os
import re
from pathlib import Path
from typing import Any, Dict, List

import mysql.connector

from data_preprocessing import clean_products, parse_args


PRODUCT_COLUMNS = [
    "id",
    "product_name",
    "main_category",
    "sub_category",
    "brand",
    "price",
    "original_price",
    "discount_percentage",
    "rating",
    "review_count",
    "stock_quantity",
    "stock_status",
    "image_url",
    "product_url",
]


def env_database() -> str:
    database = os.getenv("MYSQL_DATABASE", "catalog")
    if not re.match(r"^[A-Za-z0-9_]+$", database):
        raise ValueError("MYSQL_DATABASE must contain only letters, numbers, and underscores")
    return database


def mysql_connection(database: str | None = None):
    return mysql.connector.connect(
        host=os.getenv("MYSQL_HOST", "localhost"),
        port=int(os.getenv("MYSQL_PORT", "3306")),
        user=os.getenv("MYSQL_USER", "root"),
        password=os.getenv("MYSQL_PASSWORD", ""),
        database=database,
        autocommit=False,
    )


def ddl_statements(database: str) -> List[str]:
    return [
        f"CREATE DATABASE IF NOT EXISTS `{database}`",
        f"USE `{database}`",
        "DROP TABLE IF EXISTS products",
        """
        CREATE TABLE IF NOT EXISTS products (
            id INT PRIMARY KEY,
            product_name VARCHAR(500) NOT NULL,
            main_category VARCHAR(80) NOT NULL,
            sub_category VARCHAR(160),
            brand VARCHAR(120),
            price DECIMAL(12, 2) NOT NULL,
            original_price DECIMAL(12, 2),
            discount_percentage DECIMAL(6, 2),
            rating DECIMAL(3, 2),
            review_count INT DEFAULT 0,
            stock_quantity INT DEFAULT 0,
            stock_status VARCHAR(40),
            image_url TEXT,
            product_url TEXT,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
        )
        """,
        "CREATE INDEX idx_products_name ON products(product_name(120))",
        "CREATE INDEX idx_products_category ON products(main_category)",
        "CREATE INDEX idx_products_brand ON products(brand)",
        "CREATE INDEX idx_products_price ON products(price)",
        "CREATE INDEX idx_products_rating ON products(rating)",
        "CREATE INDEX idx_products_reviews ON products(review_count)",
    ]


def execute_ignore_duplicate(cursor, statement: str) -> None:
    try:
        cursor.execute(statement)
    except mysql.connector.Error as error:
        if error.errno != 1061:
            raise


def prepare_schema() -> None:
    database = env_database()
    connection = mysql_connection()
    cursor = connection.cursor()
    try:
        for statement in ddl_statements(database):
            execute_ignore_duplicate(cursor, statement.strip())
        connection.commit()
    except Exception:
        connection.rollback()
        raise
    finally:
        cursor.close()
        connection.close()


def sanitize_product(product: Dict[str, Any]) -> Dict[str, Any]:
    clean: Dict[str, Any] = {}
    for column in PRODUCT_COLUMNS:
        value = product.get(column)
        clean[column] = "" if value is None else value
    return clean


def import_products(csv_path: Path, limit: int) -> int:
    products = clean_products(csv_path, limit)
    prepare_schema()

    placeholders = ", ".join([f"%({column})s" for column in PRODUCT_COLUMNS])
    columns = ", ".join(PRODUCT_COLUMNS)
    insert_sql = f"INSERT INTO products ({columns}) VALUES ({placeholders})"

    connection = mysql_connection(database=env_database())
    cursor = connection.cursor()
    try:
        sanitized = [sanitize_product(product) for product in products]
        if sanitized:
            cursor.executemany(insert_sql, sanitized)
        connection.commit()
        return len(sanitized)
    except Exception:
        connection.rollback()
        raise
    finally:
        cursor.close()
        connection.close()


if __name__ == "__main__":
    args = parse_args("Import electronics_product.csv into MySQL")
    count = import_products(Path(args.csv), args.limit)
    print(f"Imported {count} cleaned products into MySQL {env_database()}.products.")

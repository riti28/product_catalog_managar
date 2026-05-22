"""Generate MongoDB JSON documents and import flexible product specifications."""

from __future__ import annotations

import json
import os
from pathlib import Path
from typing import Any, Dict, List

from data_preprocessing import clean_products, default_json_path, parse_args


def build_documents(products: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
    documents: List[Dict[str, Any]] = []
    for product in products:
        documents.append({
            "product_id": product["id"],
            "product_name": product["product_name"],
            "brand": product["brand"],
            "category": product["main_category"],
            "description": product.get("description", product["product_name"]),
            "features": product.get("features", []),
            "technical_specifications": product.get("technical_specifications", {}),
            "seller": product.get("seller", "Amazon Marketplace"),
            "product_url": product.get("product_url", ""),
            "image_url": product.get("image_url", ""),
            "customer_reviews": product.get("customer_reviews", []),
            "extra_attributes": {
                **product.get("extra_attributes", {}),
                "source": "electronics_product.csv",
                "source_index": product.get("source_index"),
            },
            "color": product.get("color", "Not Available"),
            "storage": product.get("storage", "Not Available"),
            "battery": product.get("battery", "Not Available"),
            "RAM": product.get("RAM", "Not Available"),
            "processor": product.get("processor", "Not Available"),
            "warranty": product.get("warranty", "Not Available"),
        })
    return documents


def write_json(documents: List[Dict[str, Any]]) -> Path:
    path = default_json_path()
    path.write_text(json.dumps(documents, ensure_ascii=False, indent=2), encoding="utf-8")
    return path


def import_documents(documents: List[Dict[str, Any]]) -> int:
    from pymongo import ASCENDING, MongoClient, TEXT

    client = MongoClient(
        os.getenv("MONGO_URI", "mongodb://localhost:27017"),
        serverSelectionTimeoutMS=5000,
        connectTimeoutMS=5000,
    )
    database = client[os.getenv("MONGO_DATABASE", "product_catalog")]
    collection = database[os.getenv("MONGO_COLLECTION", "products")]
    try:
        client.admin.command("ping")
        collection.drop()
        if documents:
            collection.insert_many(documents, ordered=False, bypass_document_validation=True)
        collection.create_index([("product_id", ASCENDING)], unique=True)
        collection.create_index([("category", ASCENDING)])
        collection.create_index([("brand", ASCENDING)])
        collection.create_index([("product_name", TEXT), ("description", TEXT)])
        return len(documents)
    finally:
        client.close()


if __name__ == "__main__":
    args = parse_args("Import electronics_product.csv into MongoDB")
    products = clean_products(Path(args.csv), args.limit)
    documents = build_documents(products)
    output = write_json(documents)
    print(f"Wrote {len(documents)} generated MongoDB documents to {output}")
    if args.json_only:
        print("Skipped MongoDB import because --json-only was provided.")
    else:
        print(f"Imported {import_documents(documents)} documents into MongoDB.")

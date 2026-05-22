"""Dataset preprocessing for the hybrid electronics product catalog.

The CSV used by this mini project has appeared with different header names in
different downloads.  This module intentionally discovers columns dynamically
and returns one clean in-memory product model that both importers can use.
"""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
import re
from pathlib import Path
from typing import Any, Dict, Iterable, List, Optional
from urllib.parse import urlparse


DEFAULT_LIMIT = 10000

FIELD_CANDIDATES = {
    "product_name": ["product name", "product_name", "product", "name", "title"],
    "raw_category": ["main category", "main_category", "category", "categories"],
    "sub_category": ["sub category", "sub_category", "subcategory", "department"],
    "brand": ["brand", "manufacturer", "company"],
    "price": ["discounted price", "discount_price", "discount price", "sale price", "price"],
    "original_price": ["actual price", "actual_price", "original price", "mrp", "list price"],
    "rating": ["ratings", "rating", "stars", "star rating"],
    "review_count": ["number of reviews", "no_of_ratings", "reviews", "review count", "ratings count"],
    "description": ["description", "about product", "about_product", "product description"],
    "features": ["features", "feature", "highlights", "product features"],
    "technical_details": ["technical details", "technical_details", "specifications", "technical specifications"],
    "seller": ["seller", "sold by", "merchant"],
    "product_url": ["product url", "product_url", "link", "url"],
    "image_url": ["image url", "image_url", "image", "image link"],
    "customer_reviews": ["customer reviews", "customer_reviews", "review text", "reviews text"],
}

KNOWN_BRANDS = [
    "Redmi", "OnePlus", "Samsung", "Apple", "Sony", "boAt", "Boult", "Noise",
    "JBL", "HP", "Dell", "Lenovo", "Acer", "Asus", "LG", "Mi", "realme",
    "Fire-Boltt", "Canon", "Nikon", "Portronics", "Zebronics", "Amazon",
    "SanDisk", "Logitech", "TP-Link", "pTron", "Mivi", "Philips", "Boat",
    "MI", "Microsoft", "Google", "Panasonic", "TCL", "Crompton", "Havells",
]

SPEC_PATTERNS = {
    "storage": r"(\d+\s?(?:GB|TB)\s?(?:Storage|SSD|HDD|ROM))",
    "RAM": r"(\d+\s?GB\s?RAM)",
    "battery": r"(\d{3,5}\s?mAh|(?:\d+\s?Hrs?|\d+\s?Hours?)\s?(?:Battery|Playback)?)",
    "processor": r"((?:Snapdragon|MediaTek|Dimensity|Intel|AMD|Apple M\d|Core i\d|Ryzen)[^,|()]{0,45})",
    "color": r"\(([^()]*?(?:Black|Blue|Green|Silver|White|Gold|Grey|Gray|Red|Purple|Pink)[^()]*)\)",
}


def normalize_header(value: str) -> str:
    return re.sub(r"[^a-z0-9]+", "", (value or "").strip().lower())


def normalize_text(value: Any) -> str:
    text = str(value or "").replace("\u00a0", " ")
    return re.sub(r"\s+", " ", text.strip())


def normalize_category_text(value: Any, fallback: str = "General") -> str:
    text = normalize_text(value)
    if not text:
        return fallback
    text = text.replace("&", " and ")
    text = re.sub(r"[^A-Za-z0-9 +,/-]+", " ", text)
    text = re.sub(r"\s+", " ", text).strip(" ,-")
    return text.title() if text else fallback


def find_column(headers: Iterable[str], candidates: Iterable[str]) -> Optional[str]:
    normalized = {normalize_header(header): header for header in headers if header}
    for candidate in candidates:
        match = normalized.get(normalize_header(candidate))
        if match:
            return match
    return None


def build_column_map(headers: Iterable[str]) -> Dict[str, Optional[str]]:
    return {field: find_column(headers, names) for field, names in FIELD_CANDIDATES.items()}


def parse_price(value: Any) -> Optional[float]:
    text = normalize_text(value)
    text = text.encode("ascii", "ignore").decode("ascii").replace("Rs.", "").replace("INR", "")
    text = re.sub(r"[^0-9.]", "", text)
    if not text:
        return None
    try:
        number = float(text)
    except ValueError:
        return None
    return round(number, 2) if number > 0 else None


def parse_rating(value: Any) -> float:
    match = re.search(r"\d+(?:\.\d+)?", normalize_text(value).replace(",", ""))
    if not match:
        return 0.0
    number = float(match.group(0))
    return round(number, 2) if 0 <= number <= 5 else 0.0


def parse_int(value: Any) -> int:
    cleaned = re.sub(r"[^0-9]", "", normalize_text(value))
    return int(cleaned) if cleaned else 0


def clean_url(value: Any) -> str:
    url = normalize_text(value)
    parsed = urlparse(url)
    if parsed.scheme in {"http", "https"} and parsed.netloc:
        return url
    return ""


def valid_image_url(value: Any) -> str:
    url = clean_url(value)
    if not url:
        return ""
    parsed = urlparse(url)
    path = parsed.path.lower()
    if any(path.endswith(ext) for ext in (".jpg", ".jpeg", ".png", ".webp", ".gif")):
        return url
    if "m.media-amazon.com" in parsed.netloc:
        return url
    return ""


def infer_brand(name: str, explicit: str = "") -> str:
    explicit = normalize_text(explicit)
    if explicit:
        return explicit[:120]
    lowered = name.lower()
    for brand in KNOWN_BRANDS:
        token = brand.lower()
        if lowered.startswith(token) or f" {token} " in f" {lowered} ":
            return brand
    first = re.split(r"[\s,(|/-]", name)[0]
    return first[:80] if first else "Unknown"


def infer_category(name: str, raw_category: str, sub_category: str) -> str:
    text = f"{name} {raw_category} {sub_category}".lower()
    if any(word in text for word in ["iphone", "galaxy", "oneplus", "redmi", "realme", "mobile", "phone", "smartphone"]):
        return "Mobile"
    if any(word in text for word in ["laptop", "macbook", "notebook", "chromebook"]):
        return "Laptop"
    if any(word in text for word in ["watch", "band", "fitbit", "wearable"]):
        return "Wearables"
    if any(word in text for word in ["headphone", "earbud", "earphone", "speaker", "soundbar", "neckband"]):
        return "Audio"
    if any(word in text for word in ["mouse", "keyboard", "charger", "adapter", "cable", "case", "cover", "hub", "power bank"]):
        return "Accessories"
    if any(word in text for word in ["camera", "canon", "nikon", "lens", "tripod"]):
        return "Camera"
    if any(word in text for word in ["tv", "television", "monitor", "display"]):
        return "TV and Display"
    return "Electronics"


def discount_percentage(price: float, original_price: float) -> float:
    if original_price <= 0 or original_price <= price:
        return 0.0
    return round(((original_price - price) / original_price) * 100, 2)


def stock_quantity(review_count: int, rating: float, row_number: int) -> int:
    """Generate repeatable local-demo inventory from demand signals."""
    digest = hashlib.sha1(f"{row_number}:{review_count}:{rating}".encode("utf-8")).hexdigest()
    offset = int(digest[:4], 16) % 17
    demand = review_count * max(rating, 2.5)
    if demand >= 250000:
        return 2 + offset % 4
    if demand >= 50000:
        return 6 + offset % 10
    if demand >= 10000:
        return 16 + offset
    return 30 + offset * 3


def stock_status(quantity: int) -> str:
    if quantity <= 0:
        return "Out of Stock"
    if quantity <= 5:
        return "Low Stock"
    if quantity <= 15:
        return "Limited"
    return "In Stock"


def split_list_values(*values: Any, max_items: int = 10) -> List[str]:
    items: List[str] = []
    for value in values:
        text = normalize_text(value)
        if not text:
            continue
        for part in re.split(r"\s*[|;\u2022]\s*|\s*,\s+|\s+-\s+", text):
            item = normalize_text(part.strip(" .:-"))
            if 4 <= len(item) <= 140:
                items.append(item)
    seen = set()
    unique = []
    for item in items:
        key = item.lower()
        if key not in seen:
            seen.add(key)
            unique.append(item)
    return unique[:max_items]


def infer_spec(name: str, features: str, technical_details: str, field: str, fallback: str) -> str:
    text = f"{name} {features} {technical_details}"
    pattern = SPEC_PATTERNS.get(field)
    if not pattern:
        return fallback
    match = re.search(pattern, text, flags=re.IGNORECASE)
    return normalize_text(match.group(1))[:90] if match else fallback


def category_defaults(category: str) -> Dict[str, str]:
    defaults = {
        "Mobile": {"color": "Black", "storage": "128GB Storage", "RAM": "6GB RAM", "battery": "5000mAh", "processor": "Octa Core Processor", "warranty": "1 Year Brand Warranty"},
        "Laptop": {"color": "Silver", "storage": "512GB SSD", "RAM": "8GB RAM", "battery": "Long Life Battery", "processor": "Intel / AMD Processor", "warranty": "1 Year Onsite Warranty"},
        "Wearables": {"color": "Black", "storage": "Not Applicable", "RAM": "Not Applicable", "battery": "7 Days", "processor": "Smart Sensor", "warranty": "1 Year Warranty"},
        "Audio": {"color": "Black", "storage": "Not Applicable", "RAM": "Not Applicable", "battery": "30 Hours Playback", "processor": "Audio Chipset", "warranty": "6 Months Warranty"},
        "Accessories": {"color": "White", "storage": "Not Applicable", "RAM": "Not Applicable", "battery": "Not Applicable", "processor": "Not Applicable", "warranty": "6 Months Warranty"},
        "Camera": {"color": "Black", "storage": "SD Card Support", "RAM": "Not Applicable", "battery": "Rechargeable Battery", "processor": "Image Processor", "warranty": "2 Years Warranty"},
        "TV and Display": {"color": "Black", "storage": "Smart TV Storage", "RAM": "Not Available", "battery": "Not Applicable", "processor": "Display Processor", "warranty": "1 Year Warranty"},
    }
    return defaults.get(category, {"color": "Black", "storage": "Not Available", "RAM": "Not Available", "battery": "Not Available", "processor": "Not Available", "warranty": "1 Year Warranty"})


def build_extra_attributes(row: Dict[str, Any], mapped_columns: Iterable[str]) -> Dict[str, str]:
    mapped = {column for column in mapped_columns if column}
    extras: Dict[str, str] = {}
    for key, value in row.items():
        if key in mapped or normalize_header(key) in {"", "index", "unnamed0"}:
            continue
        text = normalize_text(value)
        if text:
            extras[key] = text[:500]
    return extras


def clean_products(csv_path: Path, limit: int = DEFAULT_LIMIT) -> List[Dict[str, Any]]:
    products: List[Dict[str, Any]] = []
    seen = set()

    with csv_path.open("r", encoding="utf-8-sig", newline="") as file:
        reader = csv.DictReader(file)
        column_map = build_column_map(reader.fieldnames or [])

        for row_number, row in enumerate(reader, start=1):
            def get(field: str) -> str:
                column = column_map.get(field)
                return normalize_text(row.get(column, "")) if column else ""

            name = get("product_name")
            if not name:
                continue

            price = parse_price(get("price"))
            if price is None:
                continue
            original_price = parse_price(get("original_price")) or price
            if original_price < price:
                original_price = price

            image_url = valid_image_url(get("image_url"))
            product_url = clean_url(get("product_url"))
            if not image_url and not product_url:
                continue

            rating = parse_rating(get("rating"))
            reviews = parse_int(get("review_count"))
            raw_category = get("raw_category")
            sub_category = normalize_category_text(get("sub_category"), "General")
            category = infer_category(name, raw_category, sub_category)
            brand = infer_brand(name, get("brand"))
            dedupe_key = (name.lower(), brand.lower(), str(int(price)))
            if dedupe_key in seen:
                continue
            seen.add(dedupe_key)

            features_text = get("features")
            technical_text = get("technical_details")
            defaults = category_defaults(category)
            quantity = stock_quantity(reviews, rating, row_number)
            features = split_list_values(features_text, technical_text, name, max_items=8)
            technical_specifications = {
                "sub_category": sub_category,
                "rating": rating,
                "review_count": reviews,
                "discount_percentage": discount_percentage(price, original_price),
                "stock_quantity": quantity,
                "stock_status": stock_status(quantity),
                "raw_technical_details": technical_text,
            }

            product = {
                "id": len(products) + 1,
                "product_name": name[:500],
                "main_category": category,
                "sub_category": sub_category[:160],
                "brand": brand,
                "price": round(price, 2),
                "original_price": round(original_price, 2),
                "discount_percentage": discount_percentage(price, original_price),
                "rating": rating,
                "review_count": reviews,
                "stock_quantity": quantity,
                "stock_status": stock_status(quantity),
                "image_url": image_url,
                "product_url": product_url,
                "description": get("description") or name,
                "features": features,
                "technical_specifications": technical_specifications,
                "seller": get("seller") or "Amazon Marketplace",
                "customer_reviews": split_list_values(get("customer_reviews"), max_items=5),
                "extra_attributes": build_extra_attributes(row, column_map.values()),
                "source_index": row_number,
            }
            for field, fallback in defaults.items():
                product[field] = infer_spec(name, features_text, technical_text, field, fallback)

            products.append(product)
            if len(products) >= limit:
                break

    return products


def default_csv_path() -> Path:
    return Path(__file__).resolve().parents[1] / "database" / "electronics_product.csv"


def default_json_path() -> Path:
    return Path(__file__).resolve().parents[1] / "database" / "mongodb_data.json"


def write_clean_json(products: List[Dict[str, Any]], path: Path) -> None:
    path.write_text(json.dumps(products, ensure_ascii=False, indent=2), encoding="utf-8")


def parse_args(description: str) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=description)
    parser.add_argument("--csv", default=str(default_csv_path()), help="Path to electronics_product.csv")
    parser.add_argument("--limit", type=int, default=DEFAULT_LIMIT, help="Maximum clean rows to import")
    parser.add_argument("--json-only", action="store_true", help="Only regenerate database/mongodb_data.json")
    return parser.parse_args()


if __name__ == "__main__":
    args = parse_args("Preview cleaned electronics product records")
    cleaned = clean_products(Path(args.csv), args.limit)
    print(f"Cleaned {len(cleaned)} products from {args.csv}")
    if cleaned:
        print(json.dumps(cleaned[0], ensure_ascii=False, indent=2))

# Hybrid Product Catalog Management System

A dataset-driven e-commerce admin dashboard that combines MySQL, MongoDB, Julia, Python, and plain HTML/CSS/JavaScript.

The project imports the Amazon electronics CSV dataset, cleans it, stores structured catalog fields in MySQL, stores flexible product specifications in MongoDB, exposes REST APIs from Julia, and renders a responsive admin dashboard with CRUD and live analytics.

## Project Structure

```text
product-catalog/
|-- backend/
|   |-- server.jl
|   |-- analytics.jl
|   |-- import_mysql.py
|   |-- import_mongodb.py
|   `-- data_preprocessing.py
|-- frontend/
|   |-- index.html
|   |-- style.css
|   `-- script.js
|-- database/
|   |-- electronics_product.csv
|   |-- mongodb_data.json
|   |-- mongodb_category_updates.js
|   `-- mysql_queries.sql
`-- README.md
```

## Architecture

```text
database/electronics_product.csv
        |
        v
backend/data_preprocessing.py
        |
        |------------------------------|
        v                              v
MySQL catalog.products        MongoDB product_catalog.products
structured fields             flexible specifications
        |                              |
        |--------- Julia HTTP API -----|
                       |
                       v
frontend/index.html dashboard
```

## Dataset

The importer reads `database/electronics_product.csv` dynamically. It does not depend on one exact CSV schema.

Supported header variations include product name, name, category, main category, sub category, brand, price, discount price, actual price, rating, ratings, reviews, image, image URL, link, product URL, features, technical details, seller, and customer reviews.

## Preprocessing

`backend/data_preprocessing.py` performs:

- dynamic header mapping
- price, rating, and review-count cleanup
- duplicate removal
- blank product removal
- category normalization and inference
- image URL validation
- invalid row filtering
- repeatable demo stock generation
- stock status generation
- discount percentage calculation
- flexible specification extraction for MongoDB
- safe missing-value handling

By default the scripts import up to 10,000 clean rows for local performance.

## Storage Design

MySQL table: `products`

- `id`
- `product_name`
- `main_category`
- `sub_category`
- `brand`
- `price`
- `original_price`
- `discount_percentage`
- `rating`
- `review_count`
- `stock_quantity`
- `stock_status`
- `image_url`
- `product_url`

MongoDB collection: `product_catalog.products`

- `product_id`
- `product_name`
- `brand`
- `category`
- `description`
- `features`
- `technical_specifications`
- `seller`
- `product_url`
- `image_url`
- `customer_reviews`
- `extra_attributes`
- `color`
- `storage`
- `battery`
- `RAM`
- `processor`
- `warranty`

`product_id` in MongoDB matches `id` in MySQL.

## Setup

Install Python packages:

```powershell
pip install mysql-connector-python pymongo
```

Install Julia packages:

```julia
using Pkg
Pkg.add(["HTTP", "JSON", "MySQL", "DBInterface", "DataFrames", "Statistics", "Mongoc"])
```

Start MySQL and MongoDB locally before importing.

## Environment Variables

PowerShell example:

```powershell
$env:MYSQL_HOST="localhost"
$env:MYSQL_PORT="3306"
$env:MYSQL_USER="root"
$env:MYSQL_PASSWORD="your_mysql_password"
$env:MYSQL_DATABASE="catalog"
$env:MONGO_URI="mongodb://localhost:27017"
$env:MONGO_DATABASE="product_catalog"
$env:MONGO_COLLECTION="products"
$env:SERVER_HOST="127.0.0.1"
$env:SERVER_PORT="8080"
```

If your MySQL root user has no password, set `MYSQL_PASSWORD` to an empty string.

## Import Data

Run these from the `product-catalog` folder:

```powershell
python backend/import_mysql.py --csv database/electronics_product.csv --limit 10000
python backend/import_mongodb.py --csv database/electronics_product.csv --limit 10000
```

The MongoDB import regenerates:

```text
database/mongodb_data.json
```

To only regenerate JSON:

```powershell
python backend/import_mongodb.py --csv database/electronics_product.csv --limit 10000 --json-only
```

## Run

Start the Julia API:

```powershell
cd backend
julia server.jl
```

Open the dashboard:

```text
frontend/index.html
```

The frontend calls:

```text
http://127.0.0.1:8080
```

## REST API

- `GET /health`
- `GET /products?page=1&limit=24&q=&category=&brand=&sort=popularity`
- `GET /search?q=phone`
- `GET /category/:name`
- `GET /brand/:name`
- `GET /analytics`
- `GET /top-products`
- `GET /recommendations`
- `GET /combined`
- `GET /combined?id=1`
- `GET /combined/:id`
- `POST /products`
- `PUT /products/:id`
- `DELETE /products/:id`

Sorting options:

- `popularity`
- `price`
- `price_desc`
- `rating`
- `discount`
- `stock`
- `name`

Example create payload:

```json
{
  "product_name": "Demo Bluetooth Speaker",
  "main_category": "Audio",
  "sub_category": "Speakers",
  "brand": "DemoBrand",
  "price": 1999,
  "original_price": 2999,
  "rating": 4.2,
  "review_count": 120,
  "stock_quantity": 18,
  "image_url": "https://example.com/image.jpg",
  "product_url": "https://example.com/product",
  "features": ["Bluetooth", "Portable"],
  "warranty": "1 Year Warranty"
}
```

## Analytics

`backend/analytics.jl` calculates:

- top selling products
- highest rated products
- most expensive products
- highest discount products
- low stock prediction
- category-wise trends
- brand-wise analysis
- average product price
- top reviewed products
- recommendations

Recommendation examples:

- best mobiles under Rs. 20,000
- best laptops with high ratings
- best budget electronics
- highest discount deals

Analytics are calculated live from MySQL every time the frontend refreshes. CRUD operations call the API, update MySQL and MongoDB, then refresh analytics and products.

## Frontend Features

- responsive admin dashboard
- real product images from the CSV
- image fallback for broken URLs
- product cards
- search
- category filter
- brand filter
- sorting
- pagination
- analytics dashboard
- recommendation section
- product detail modal
- add product modal
- edit product modal
- delete confirmation popup
- dark/light theme toggle

## Screenshots

Add screenshots here after running the project:

```text
screenshots/dashboard.png
screenshots/product-detail.png
screenshots/add-edit-product.png
```

## Troubleshooting

If products do not load:

- confirm Julia server is running on `http://127.0.0.1:8080`
- open `GET /health` in the browser
- verify MySQL credentials in environment variables
- run the MySQL importer again

If images are broken:

- confirm `image_url` values were imported into MySQL
- the frontend automatically falls back to an inline placeholder image
- some remote hosts may block hotlinking, but Amazon media URLs from the dataset usually work

If MongoDB fails on Windows:

- confirm MongoDB service is running
- run `python backend/import_mongodb.py --json-only` to verify JSON generation separately
- keep Mongo documents small and imported through the provided script
- the Julia API catches Mongo sync failures so MySQL CRUD remains stable

If commands are not found:

- install Python and ensure `python` is in PATH
- install Julia and ensure `julia` is in PATH
- restart PowerShell after changing PATH

## Viva Notes

- MySQL is used for structured business fields and indexed queries.
- MongoDB is used for flexible specifications that vary by category.
- Python handles CSV preprocessing and database imports.
- Julia handles REST APIs and analytics.
- The frontend is intentionally plain HTML/CSS/JavaScript to keep the stack beginner-friendly.

CREATE DATABASE IF NOT EXISTS catalog;
USE catalog;

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
);

CREATE INDEX idx_products_name ON products(product_name(120));
CREATE INDEX idx_products_category ON products(main_category);
CREATE INDEX idx_products_brand ON products(brand);
CREATE INDEX idx_products_price ON products(price);
CREATE INDEX idx_products_rating ON products(rating);
CREATE INDEX idx_products_reviews ON products(review_count);

-- Recommended import command:
-- python backend/import_mysql.py --csv database/electronics_product.csv --limit 10000

-- Useful review queries:
SELECT COUNT(*) AS total_products FROM products;
SELECT main_category, COUNT(*) AS products FROM products GROUP BY main_category ORDER BY products DESC;
SELECT brand, COUNT(*) AS products, AVG(rating) AS average_rating FROM products GROUP BY brand ORDER BY products DESC LIMIT 20;
SELECT product_name, price, rating, review_count FROM products ORDER BY review_count DESC LIMIT 20;
SELECT product_name, stock_quantity, stock_status FROM products WHERE stock_quantity <= 5 ORDER BY stock_quantity ASC;

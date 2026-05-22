module CatalogAnalytics

using DataFrames
using Statistics

export product_summary, category_counts, category_trends, brand_analysis,
       top_selling_products, expensive_products, low_stock_products,
       highest_rated_products, most_reviewed_products, highest_discount_products,
       recommendations

function safe_number(value)
    value === missing && return 0.0
    value === nothing && return 0.0
    value isa Number && return Float64(value)
    return try
        parse(Float64, replace(string(value), "," => ""))
    catch
        0.0
    end
end

function has_column(products::DataFrame, column::Symbol)
    return column in Symbol.(names(products))
end

function product_summary(products::DataFrame)
    isempty(products) && return Dict(
        "total_products" => 0,
        "average_price" => 0.0,
        "inventory_value" => 0.0,
        "low_stock_count" => 0,
        "average_rating" => 0.0,
        "total_reviews" => 0
    )
    prices = safe_number.(products.price)
    stocks = safe_number.(products.stock_quantity)
    ratings = safe_number.(products.rating)
    reviews = safe_number.(products.review_count)
    return Dict(
        "total_products" => nrow(products),
        "average_price" => round(mean(prices), digits = 2),
        "inventory_value" => round(sum(prices .* stocks), digits = 2),
        "low_stock_count" => count(stock -> stock <= 5, stocks),
        "average_rating" => round(mean(ratings), digits = 2),
        "total_reviews" => round(Int, sum(reviews))
    )
end

function take_sorted(products::DataFrame, column::Symbol; limit::Int = 8)
    (isempty(products) || !has_column(products, column)) && return DataFrame()
    sorted = sort(products, column, rev = true)
    return first(sorted, min(limit, nrow(sorted)))
end

function top_selling_products(products::DataFrame; limit::Int = 8)
    isempty(products) && return DataFrame()
    scored = copy(products)
    scored.sales_score = safe_number.(scored.rating) .* log.(safe_number.(scored.review_count) .+ 1) .* (1 .+ safe_number.(scored.discount_percentage) ./ 100)
    return select(first(sort(scored, :sales_score, rev = true), min(limit, nrow(scored))), Not(:sales_score))
end

expensive_products(products::DataFrame; limit::Int = 8) = take_sorted(products, :price, limit = limit)
most_reviewed_products(products::DataFrame; limit::Int = 8) = take_sorted(products, :review_count, limit = limit)
highest_discount_products(products::DataFrame; limit::Int = 8) = take_sorted(products, :discount_percentage, limit = limit)

function low_stock_products(products::DataFrame; threshold::Int = 5, limit::Int = 8)
    isempty(products) && return DataFrame()
    rows = products[safe_number.(products.stock_quantity) .<= threshold, :]
    isempty(rows) && return DataFrame()
    return first(sort(rows, :stock_quantity), min(limit, nrow(rows)))
end

function highest_rated_products(products::DataFrame; limit::Int = 8)
    isempty(products) && return DataFrame()
    sorted = sort(products, [:rating, :review_count], rev = [true, true])
    return first(sorted, min(limit, nrow(sorted)))
end

function category_counts(products::DataFrame)
    isempty(products) && return DataFrame(main_category = String[], count = Int[], average_price = Float64[], average_rating = Float64[], total_reviews = Int[])
    grouped = combine(
        groupby(products, :main_category),
        nrow => :count,
        :price => (value -> round(mean(safe_number.(value)), digits = 2)) => :average_price,
        :rating => (value -> round(mean(safe_number.(value)), digits = 2)) => :average_rating,
        :review_count => (value -> round(Int, sum(safe_number.(value)))) => :total_reviews
    )
    return sort(grouped, :count, rev = true)
end

function category_trends(products::DataFrame)
    isempty(products) && return DataFrame(main_category = String[], demand_score = Float64[], stock_risk = Float64[], discount_avg = Float64[])
    grouped = combine(
        groupby(products, :main_category),
        :review_count => (value -> round(mean(log.(safe_number.(value) .+ 1)), digits = 2)) => :demand_score,
        :stock_quantity => (value -> round(count(stock -> stock <= 5, safe_number.(value)) / max(length(value), 1), digits = 2)) => :stock_risk,
        :discount_percentage => (value -> round(mean(safe_number.(value)), digits = 2)) => :discount_avg
    )
    return sort(grouped, :demand_score, rev = true)
end

function brand_analysis(products::DataFrame; limit::Int = 25)
    isempty(products) && return DataFrame(brand = String[], count = Int[], average_rating = Float64[], average_price = Float64[], total_reviews = Int[])
    grouped = combine(
        groupby(products, :brand),
        nrow => :count,
        :rating => (value -> round(mean(safe_number.(value)), digits = 2)) => :average_rating,
        :price => (value -> round(mean(safe_number.(value)), digits = 2)) => :average_price,
        :review_count => (value -> round(Int, sum(safe_number.(value)))) => :total_reviews
    )
    sorted = sort(grouped, [:count, :total_reviews], rev = [true, true])
    return first(sorted, min(limit, nrow(sorted)))
end

function recommendation_slice(products::DataFrame, predicate; limit::Int = 6)
    isempty(products) && return DataFrame()
    filtered = products[predicate.(eachrow(products)), :]
    isempty(filtered) && return DataFrame()
    sorted = sort(filtered, [:rating, :review_count, :discount_percentage], rev = [true, true, true])
    return first(sorted, min(limit, nrow(sorted)))
end

function recommendations(products::DataFrame)
    return Dict(
        "best_mobiles_under_20000" => recommendation_slice(products, row -> string(row.main_category) == "Mobile" && safe_number(row.price) <= 20000 && safe_number(row.rating) >= 4),
        "best_laptops_with_high_ratings" => recommendation_slice(products, row -> string(row.main_category) == "Laptop" && safe_number(row.rating) >= 4),
        "best_budget_electronics" => recommendation_slice(products, row -> safe_number(row.price) <= 5000 && safe_number(row.rating) >= 3.8),
        "best_electronics_under_20000" => recommendation_slice(products, row -> safe_number(row.price) <= 20000 && safe_number(row.rating) >= 4),
        "highest_discount_deals" => highest_discount_products(products, limit = 6)
    )
end

end

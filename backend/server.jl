using HTTP
using JSON
using MySQL
using DBInterface
using DataFrames
using Mongoc

include("analytics.jl")
using .CatalogAnalytics

const MYSQL_HOST = get(ENV, "MYSQL_HOST", "localhost")
const MYSQL_USER = get(ENV, "MYSQL_USER", "root")
const MYSQL_PASSWORD = get(ENV, "MYSQL_PASSWORD", "")
const MYSQL_DATABASE = get(ENV, "MYSQL_DATABASE", "catalog")
const MYSQL_PORT = parse(Int, get(ENV, "MYSQL_PORT", "3306"))
const MONGO_URI = get(ENV, "MONGO_URI", "mongodb://localhost:27017")
const MONGO_DATABASE = get(ENV, "MONGO_DATABASE", "product_catalog")
const MONGO_COLLECTION = get(ENV, "MONGO_COLLECTION", "products")
const SERVER_HOST = get(ENV, "SERVER_HOST", "127.0.0.1")
const SERVER_PORT = parse(Int, get(ENV, "SERVER_PORT", "8080"))
const MAX_LIMIT = 60
const MONGO_CLIENT = Ref{Any}(nothing)

const PRODUCT_COLUMNS = """
id, product_name, main_category, sub_category, brand, price, original_price,
discount_percentage, rating, review_count, stock_quantity, stock_status,
image_url, product_url
"""

function json_response(data; status = 200)
    return HTTP.Response(status, [
        "Content-Type" => "application/json; charset=utf-8",
        "Access-Control-Allow-Origin" => "*",
        "Access-Control-Allow-Methods" => "GET, POST, PUT, DELETE, OPTIONS",
        "Access-Control-Allow-Headers" => "Content-Type"
    ], JSON.json(data))
end

error_response(message; status = 500) = json_response(Dict("success" => false, "error" => message), status = status)

function plain(value)
    value === missing && return nothing
    value === nothing && return nothing
    value isa Integer && return Int(value)
    value isa AbstractFloat && return Float64(value)
    value isa Number && return Float64(value)
    value isa AbstractString && return String(value)
    value isa Bool && return value
    return string(value)
end

function df_to_dicts(df::DataFrame)
    return [Dict(String(name) => plain(row[name]) for name in names(df)) for row in eachrow(df)]
end

mysql_connection() = DBInterface.connect(
    MySQL.Connection,
    MYSQL_HOST,
    MYSQL_USER,
    MYSQL_PASSWORD;
    db = MYSQL_DATABASE,
    port = MYSQL_PORT
)

function sql_execute(conn, sql, params = ())
    if isempty(params)
        return DBInterface.execute(conn, sql)
    end
    statement = DBInterface.prepare(conn, sql)
    return DBInterface.execute(statement, Tuple(params))
end

function sql_dataframe(conn, sql, params = ())
    return DataFrame(sql_execute(conn, sql, params))
end

function parse_target(target)
    uri = HTTP.URI(String(target))
    return uri.path, HTTP.queryparams(uri)
end

function int_param(params, key, default)
    return try
        parse(Int, get(params, key, string(default)))
    catch
        default
    end
end

function maybe_int(value)
    parsed = tryparse(Int, strip(string(value)))
    return parsed === nothing ? nothing : parsed
end

function float_value(value, default = 0.0)
    value === nothing && return Float64(default)
    value === missing && return Float64(default)
    value isa Number && return Float64(value)
    return try
        parse(Float64, replace(string(value), "," => ""))
    catch
        Float64(default)
    end
end

function int_value(value, default = 0)
    return round(Int, float_value(value, default))
end

function text_value(value, default = "")
    value === nothing && return default
    value === missing && return default
    text = strip(string(value))
    return isempty(text) ? default : text
end

function key_name(value)
    return replace(lowercase(string(value)), r"[^a-z0-9]" => "")
end

function field_value(data, keys...; default = nothing)
    data isa Dict || return default
    wanted = Set(key_name.(keys))
    for (key, value) in data
        if key_name(key) in wanted
            return value
        end
    end
    return default
end

function product_dicts(data)
    data isa Dict || return Any[]
    dicts = Any[data]
    wrapper_keys = Set(["product", "data", "payload", "body", "fields", "item", "record"])
    for (key, value) in data
        if value isa Dict && key_name(key) in wrapper_keys
            append!(dicts, product_dicts(value))
        elseif value isa AbstractString && key_name(key) in wrapper_keys
            nested = try
                JSON.parse(value)
            catch
                nothing
            end
            nested isa Dict && append!(dicts, product_dicts(normalize_json_keys(nested)))
        end
    end
    return dicts
end

function has_any_field(data, field_names...)
    wanted = Set(key_name.(field_names))
    for source in product_dicts(data)
        any(key_name(key) in wanted for key in Base.keys(source)) && return true
    end
    return false
end

function usable_value(value)
    value === nothing && return false
    value === missing && return false
    value isa AbstractString && return !isempty(strip(value))
    return true
end

function first_valid_field(data, keys...)
    for source in product_dicts(data)
        for wanted_key in keys
            normalized = key_name(wanted_key)
            for (key, value) in source
                if key_name(key) == normalized && usable_value(value)
                    return value
                end
            end
        end
    end
    return nothing
end

function fallback_field(incoming, existing, keys...; default = nothing)
    value = first_valid_field(incoming, keys...)
    value !== nothing && return value
    value = first_valid_field(existing, keys...)
    value !== nothing && return value
    return default
end

function parsed_float_value(value)
    value === nothing && return nothing
    value === missing && return nothing
    value isa Number && return Float64(value)
    text = strip(string(value))
    isempty(text) && return nothing
    return tryparse(Float64, replace(text, "," => ""))
end

function numeric_field(incoming, existing, keys...; default = 0.0)
    for data in (incoming, existing)
        for source in product_dicts(data)
            for wanted_key in keys
                normalized = key_name(wanted_key)
                for (key, value) in source
                    if key_name(key) != normalized
                        continue
                    end
                    parsed = parsed_float_value(value)
                    parsed !== nothing && return parsed
                end
            end
        end
    end
    return Float64(default)
end

function integer_field(incoming, existing, keys...; default = 0)
    return round(Int, numeric_field(incoming, existing, keys...; default = default))
end

function text_field(incoming, existing, keys...; default = "")
    return text_value(fallback_field(incoming, existing, keys...; default = default), default)
end

function array_value(value)
    value === nothing && return String[]
    if value isa AbstractVector
        return [strip(string(item)) for item in value if usable_value(item) && !isempty(strip(string(item)))]
    end
    text = strip(string(value))
    isempty(text) && return String[]
    return [strip(item) for item in split(text, r"[,;|]") if !isempty(strip(item))]
end

function clean_path_value(value)
    decoded = replace(value, "+" => " ")
    decoded = replace(decoded, "%20" => " ")
    decoded = replace(decoded, "%2C" => ",")
    decoded = replace(decoded, "%26" => "&")
    return strip(decoded)
end

function order_clause(sort)
    sort == "price" && return "price ASC"
    sort == "price_desc" && return "price DESC"
    sort == "rating" && return "rating DESC, review_count DESC"
    sort == "discount" && return "discount_percentage DESC"
    sort == "stock" && return "stock_quantity ASC"
    sort == "name" && return "product_name ASC"
    return "review_count DESC, rating DESC"
end

function where_sql(; q = "", category = "", brand = "", stock = "")
    clauses = String[]
    values = Any[]
    if !isempty(strip(q))
        token = "%$(strip(q))%"
        push!(clauses, "(product_name LIKE ? OR brand LIKE ? OR main_category LIKE ? OR sub_category LIKE ?)")
        append!(values, [token, token, token, token])
    end
    if !isempty(strip(category))
        push!(clauses, "main_category = ?")
        push!(values, strip(category))
    end
    if !isempty(strip(brand))
        push!(clauses, "brand = ?")
        push!(values, strip(brand))
    end
    if stock == "low"
        push!(clauses, "stock_quantity <= 5")
    end
    return isempty(clauses) ? "" : "WHERE " * join(clauses, " AND "), values
end

function query_products(params)
    page = max(int_param(params, "page", 1), 1)
    limit = min(max(int_param(params, "limit", 24), 1), MAX_LIMIT)
    offset = (page - 1) * limit
    where, values = where_sql(
        q = get(params, "q", ""),
        category = get(params, "category", ""),
        brand = get(params, "brand", ""),
        stock = get(params, "stock", "")
    )
    conn = mysql_connection()
    try
        total_df = sql_dataframe(conn, "SELECT COUNT(*) AS total FROM products $where", values)
        total = isempty(total_df) ? 0 : Int(total_df.total[1])
        sort_key = get(params, "sort", "popularity")
        sql = "SELECT $PRODUCT_COLUMNS FROM products $where ORDER BY $(order_clause(sort_key)) LIMIT ? OFFSET ?"
        rows = sql_dataframe(conn, sql, vcat(values, [limit, offset]))
        return Dict(
            "items" => df_to_dicts(rows),
            "page" => page,
            "limit" => limit,
            "total" => total,
            "total_pages" => max(1, ceil(Int, total / limit))
        )
    finally
        DBInterface.close!(conn)
    end
end

function all_products()
    conn = mysql_connection()
    try
        return sql_dataframe(conn, "SELECT $PRODUCT_COLUMNS FROM products ORDER BY id LIMIT 10000")
    finally
        DBInterface.close!(conn)
    end
end

function product_by_id(id::Int)
    conn = mysql_connection()
    try
        df = sql_dataframe(conn, "SELECT $PRODUCT_COLUMNS FROM products WHERE id = ?", (id,))
        return isempty(df) ? nothing : df_to_dicts(df)[1]
    finally
        DBInterface.close!(conn)
    end
end

function combined_product_payload(id::Int)
    product = product_by_id(id)
    product === nothing && return nothing
    return merge(product, Dict("specifications" => mongo_spec(id)))
end

function combined_index_payload(params)
    if haskey(params, "id") && !isempty(strip(params["id"]))
        id = maybe_int(params["id"])
        id === nothing && return Dict("success" => false, "error" => "Invalid product id", "example" => "/combined?id=1")
        product = combined_product_payload(id)
        product === nothing && return nothing
        return product
    end

    conn = mysql_connection()
    try
        samples = sql_dataframe(conn, "SELECT $PRODUCT_COLUMNS FROM products ORDER BY id LIMIT 10")
        return Dict(
            "message" => "Use /combined/:id to view one MySQL + MongoDB merged product.",
            "examples" => ["/combined/1", "/combined?id=1"],
            "sample_products" => df_to_dicts(samples)
        )
    finally
        DBInterface.close!(conn)
    end
end

function bson_to_plain(value)
    if value isa Mongoc.BSON
        return bson_to_plain(try
            Mongoc.as_dict(value)
        catch _
            Dict(value)
        end)
    elseif value isa Dict
        return Dict(string(k) => bson_to_plain(v) for (k, v) in value if string(k) != "_id")
    elseif value isa AbstractVector
        return [bson_to_plain(v) for v in value]
    else
        return plain(value)
    end
end

function mongo_collection()
    if MONGO_CLIENT[] === nothing
        MONGO_CLIENT[] = Mongoc.Client(MONGO_URI)
    end
    return MONGO_CLIENT[][MONGO_DATABASE][MONGO_COLLECTION]
end

function product_filter(id::Int)
    return try
        Mongoc.BSON("product_id" => id)
    catch
        Mongoc.BSON(Dict("product_id" => id))
    end
end

function mongo_spec(id::Int)
    cursor = nothing
    try
        cursor = Mongoc.find(mongo_collection(), product_filter(id))
        for doc in cursor
            return bson_to_plain(doc)
        end
    catch err
        @warn "MongoDB lookup failed" err
    finally
        # Iterate at most one small cursor and release references immediately.
        cursor = nothing
        GC.safepoint()
    end
    return Dict{String, Any}()
end

function mongo_document(data, id)
    return Dict(
        "product_id" => id,
        "product_name" => get(data, "product_name", ""),
        "brand" => get(data, "brand", ""),
        "category" => get(data, "main_category", ""),
        "description" => get(data, "description", get(data, "product_name", "")),
        "features" => array_value(get(data, "features", String[])),
        "technical_specifications" => Dict(
            "sub_category" => get(data, "sub_category", "General"),
            "rating" => get(data, "rating", 0),
            "review_count" => get(data, "review_count", 0),
            "discount_percentage" => get(data, "discount_percentage", 0),
            "stock_quantity" => get(data, "stock_quantity", 0),
            "stock_status" => get(data, "stock_status", "")
        ),
        "seller" => get(data, "seller", "Amazon Marketplace"),
        "product_url" => get(data, "product_url", ""),
        "image_url" => get(data, "image_url", ""),
        "customer_reviews" => array_value(get(data, "customer_reviews", String[])),
        "extra_attributes" => get(data, "extra_attributes", Dict{String, Any}()),
        "color" => get(data, "color", "Not Available"),
        "storage" => get(data, "storage", "Not Available"),
        "battery" => get(data, "battery", "Not Available"),
        "RAM" => get(data, "RAM", "Not Available"),
        "processor" => get(data, "processor", "Not Available"),
        "warranty" => get(data, "warranty", "Not Available")
    )
end

function sync_mongo_replace(data, id)
    try
        collection = mongo_collection()
        Mongoc.delete_one(collection, product_filter(id))
        Mongoc.insert_one(collection, Mongoc.BSON(mongo_document(data, id)))
        return true
    catch err
        @warn "MongoDB sync failed" err
        return false
    end
end

function sync_mongo_delete(id)
    try
        Mongoc.delete_one(mongo_collection(), product_filter(id))
        return true
    catch err
        @warn "MongoDB delete sync failed" err
        return false
    end
end

function normalize_json_keys(value)
    if value isa Dict
        return Dict(string(k) => normalize_json_keys(v) for (k, v) in value)
    elseif value isa AbstractVector
        return [normalize_json_keys(v) for v in value]
    else
        return value
    end
end

function parse_form_body(raw::AbstractString)
    data = Dict{String, Any}()
    for pair in split(raw, "&")
        isempty(pair) && continue
        parts = split(pair, "=", limit = 2)
        key = HTTP.URIs.unescapeuri(replace(parts[1], "+" => " "))
        value = length(parts) == 2 ? HTTP.URIs.unescapeuri(replace(parts[2], "+" => " ")) : ""
        data[key] = value
    end
    return data
end

function request_json(request)
    raw = String(request.body)
    isempty(strip(raw)) && return Dict{String, Any}()
    try
        parsed = JSON.parse(raw)
        if parsed isa AbstractString
            parsed = JSON.parse(parsed)
        end
        return parsed isa Dict ? normalize_json_keys(parsed) : Dict{String, Any}()
    catch err
        @warn "JSON parse failed; trying form body fallback" err raw
        return parse_form_body(raw)
    end
end

function debug_request_payload(label, request, data)
    println("REQUEST TRACE => ", label)
    println("RAW BODY => ", String(request.body))
    println("PARSED JSON => ", data)
    println("PAYLOAD KEYS => ", data isa Dict ? collect(Base.keys(data)) : typeof(data))
end

function stock_status(quantity::Int)
    quantity <= 0 && return "Out of Stock"
    quantity <= 5 && return "Low Stock"
    quantity <= 15 && return "Limited"
    return "In Stock"
end

function normalized_product(data, existing = Dict{String, Any}())
    incoming = data isa Dict ? data : Dict{String, Any}()
    stored = existing isa Dict ? existing : Dict{String, Any}()

    product_name = text_field(incoming, stored, "product_name", "productName", "name"; default = "")
    if isempty(product_name)
        println("NORMALIZER NAME LOOKUP FAILED. INPUT => ", incoming)
        println("NORMALIZER AVAILABLE KEYS => ", incoming isa Dict ? collect(Base.keys(incoming)) : typeof(incoming))
        error("Product name is required")
    end

    category_value = fallback_field(incoming, stored, "main_category", "mainCategory", "category"; default = nothing)
    category_was_sent = has_any_field(incoming, "main_category", "mainCategory", "category")
    if category_value === nothing
        main_category = category_was_sent ? "" : "Electronics"
    else
        main_category = text_value(category_value)
    end
    isempty(main_category) && error("Category is required")

    price = max(numeric_field(incoming, stored, "price"; default = 0), 0.0)
    original = max(
        numeric_field(incoming, stored, "original_price", "originalPrice", "actual_price"; default = price),
        price
    )
    discount_input = numeric_field(incoming, stored, "discount_percentage", "discountPercentage"; default = 0)
    discount = original > price ? round(((original - price) / original) * 100, digits = 2) : max(discount_input, 0.0)

    rating = min(max(numeric_field(incoming, stored, "rating", "ratings"; default = 0), 0.0), 5.0)
    review_count = max(integer_field(incoming, stored, "review_count", "reviewCount", "reviews"; default = 0), 0)
    stock = max(integer_field(incoming, stored, "stock_quantity", "stockQuantity", "stock"; default = 0), 0)

    return Dict(
        "product_name" => product_name,
        "main_category" => main_category,
        "sub_category" => text_field(incoming, stored, "sub_category", "subCategory"; default = "General"),
        "brand" => text_field(incoming, stored, "brand"; default = "Unknown"),
        "price" => price,
        "original_price" => original,
        "discount_percentage" => discount,
        "rating" => rating,
        "review_count" => review_count,
        "stock_quantity" => stock,
        "stock_status" => stock_status(stock),
        "image_url" => text_field(incoming, stored, "image_url", "imageUrl", "image"; default = ""),
        "product_url" => text_field(incoming, stored, "product_url", "productUrl", "url"; default = ""),
        "color" => text_field(incoming, stored, "color"; default = "Not Available"),
        "storage" => text_field(incoming, stored, "storage"; default = "Not Available"),
        "RAM" => text_field(incoming, stored, "RAM", "ram"; default = "Not Available"),
        "battery" => text_field(incoming, stored, "battery"; default = "Not Available"),
        "processor" => text_field(incoming, stored, "processor"; default = "Not Available"),
        "warranty" => text_field(incoming, stored, "warranty"; default = "Not Available"),
        "features" => array_value(fallback_field(incoming, stored, "features"; default = String[])),
        "customer_reviews" => array_value(fallback_field(incoming, stored, "customer_reviews", "customerReviews"; default = String[])),
        "description" => text_field(incoming, stored, "description"; default = product_name),
        "seller" => text_field(incoming, stored, "seller"; default = "Amazon Marketplace"),
        "extra_attributes" => fallback_field(incoming, stored, "extra_attributes", "extraAttributes"; default = Dict{String, Any}())
    )
end

function create_product(data)
    product = normalized_product(data)
    conn = mysql_connection()
    try
        next_id_df = sql_dataframe(conn, "SELECT COALESCE(MAX(id), 0) + 1 AS id FROM products")
        id = Int(next_id_df.id[1])
        sql = "INSERT INTO products ($PRODUCT_COLUMNS) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)"
        sql_execute(conn, sql, (
            id, product["product_name"], product["main_category"], product["sub_category"],
            product["brand"], product["price"], product["original_price"], product["discount_percentage"],
            product["rating"], product["review_count"], product["stock_quantity"], product["stock_status"],
            product["image_url"], product["product_url"]
        ))
        sql_execute(conn, "COMMIT")
        sync_mongo_replace(product, id)
        return product_by_id(id)
    catch err
        try
            sql_execute(conn, "ROLLBACK")
        catch rollback_err
            @warn "MySQL rollback failed" rollback_err
        end
        rethrow(err)
    finally
        DBInterface.close!(conn)
    end
end

function update_product(id::Int, data)
    existing = product_by_id(id)
    existing === nothing && error("Product not found")
    product = normalized_product(data, existing)
    conn = mysql_connection()
    try
        sql = """
        UPDATE products SET product_name=?, main_category=?, sub_category=?, brand=?,
        price=?, original_price=?, discount_percentage=?, rating=?, review_count=?,
        stock_quantity=?, stock_status=?, image_url=?, product_url=? WHERE id=?
        """
        sql_execute(conn, sql, (
            product["product_name"], product["main_category"], product["sub_category"], product["brand"],
            product["price"], product["original_price"], product["discount_percentage"], product["rating"],
            product["review_count"], product["stock_quantity"], product["stock_status"], product["image_url"],
            product["product_url"], id
        ))
        sql_execute(conn, "COMMIT")
        sync_mongo_replace(product, id)
        return product_by_id(id)
    catch err
        try
            sql_execute(conn, "ROLLBACK")
        catch rollback_err
            @warn "MySQL rollback failed" rollback_err
        end
        rethrow(err)
    finally
        DBInterface.close!(conn)
    end
end

function delete_product(id::Int)
    conn = mysql_connection()
    try
        sql_execute(conn, "DELETE FROM products WHERE id = ?", (id,))
        sql_execute(conn, "COMMIT")
        mongo_ok = sync_mongo_delete(id)
        return Dict("success" => true, "deleted_id" => id, "mongo_synced" => mongo_ok)
    catch err
        try
            sql_execute(conn, "ROLLBACK")
        catch rollback_err
            @warn "MySQL rollback failed" rollback_err
        end
        rethrow(err)
    finally
        DBInterface.close!(conn)
    end
end

function analytics_payload()
    products = all_products()
    return Dict(
        "summary" => product_summary(products),
        "category_count" => df_to_dicts(category_counts(products)),
        "category_trends" => df_to_dicts(category_trends(products)),
        "brand_analysis" => df_to_dicts(brand_analysis(products)),
        "top_selling_products" => df_to_dicts(top_selling_products(products)),
        "expensive_products" => df_to_dicts(expensive_products(products)),
        "low_stock_products" => df_to_dicts(low_stock_products(products)),
        "highest_rated_products" => df_to_dicts(highest_rated_products(products)),
        "most_reviewed_products" => df_to_dicts(most_reviewed_products(products)),
        "highest_discount_products" => df_to_dicts(highest_discount_products(products)),
        "recommendations" => Dict(k => df_to_dicts(v) for (k, v) in recommendations(products))
    )
end

function health_payload()
    mysql_ok = false
    mongo_ok = false
    try
        conn = mysql_connection()
        DBInterface.execute(conn, "SELECT 1")
        DBInterface.close!(conn)
        mysql_ok = true
    catch err
        @warn "MySQL health check failed" err
    end
    try
        mongo_collection()
        mongo_ok = true
    catch err
        @warn "MongoDB health check failed" err
    end
    return Dict(
        "status" => mysql_ok ? "ok" : "degraded",
        "mysql" => mysql_ok,
        "mongodb" => mongo_ok,
        "api" => true
    )
end

function route(request::HTTP.Request)
    method = String(request.method)
    path, params = parse_target(request.target)
    method == "OPTIONS" && return json_response(Dict("ok" => true), status = 204)
    try
        if method == "GET" && path == "/products"
            return json_response(query_products(params))
        elseif method == "GET" && path == "/search"
            return json_response(query_products(params))
        elseif method == "GET" && startswith(path, "/category/")
            category = clean_path_value(replace(path, "/category/" => ""))
            return json_response(query_products(merge(params, Dict("category" => category))))
        elseif method == "GET" && startswith(path, "/brand/")
            brand = clean_path_value(replace(path, "/brand/" => ""))
            return json_response(query_products(merge(params, Dict("brand" => brand))))
        elseif method == "GET" && path == "/analytics"
            return json_response(analytics_payload())
        elseif method == "GET" && path == "/top-products"
            products = all_products()
            return json_response(Dict(
                "top_selling" => df_to_dicts(top_selling_products(products)),
                "expensive" => df_to_dicts(expensive_products(products)),
                "rated" => df_to_dicts(highest_rated_products(products)),
                "reviewed" => df_to_dicts(most_reviewed_products(products)),
                "discounted" => df_to_dicts(highest_discount_products(products))
            ))
        elseif method == "GET" && path == "/recommendations"
            products = all_products()
            return json_response(Dict(k => df_to_dicts(v) for (k, v) in recommendations(products)))
        elseif method == "GET" && (path == "/combined" || path == "/combined/")
            payload = combined_index_payload(params)
            payload === nothing && return error_response("Product not found", status = 404)
            return json_response(payload)
        elseif method == "GET" && startswith(path, "/combined/")
            id = maybe_int(replace(path, "/combined/" => ""))
            id === nothing && return error_response("Invalid product id. Use /combined/1", status = 400)
            payload = combined_product_payload(id)
            payload === nothing && return error_response("Product not found", status = 404)
            return json_response(payload)
        elseif method == "POST" && path == "/products"
            data = request_json(request)
            debug_request_payload("POST /products", request, data)
            product = create_product(data)
            return json_response(Dict("success" => true, "product" => product), status = 201)
        elseif method == "PUT" && startswith(path, "/products/")
            id = maybe_int(replace(path, "/products/" => ""))
            id === nothing && return error_response("Invalid product id", status = 400)
            data = request_json(request)
            debug_request_payload("PUT /products/:id", request, data)
            return json_response(Dict("success" => true, "product" => update_product(id, data)))
        elseif method == "DELETE" && startswith(path, "/products/")
            id = maybe_int(replace(path, "/products/" => ""))
            id === nothing && return error_response("Invalid product id", status = 400)
            return json_response(delete_product(id))
        elseif method == "GET" && path == "/health"
            return json_response(health_payload())
        else
            return error_response("Route not found", status = 404)
        end
    catch err
        @error "Request failed" exception = (err, catch_backtrace())
        return error_response("Server error: $(sprint(showerror, err))")
    end
end

println("Hybrid Product Catalog API running at http://$(SERVER_HOST):$(SERVER_PORT)")
HTTP.serve(route, SERVER_HOST, SERVER_PORT)

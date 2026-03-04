#!/usr/bin/env Rscript
# Bun Cha POS - Plumber API Server
# Main API server for the POS system

library(plumber)
library(jsonlite)

# Set working directory to project root
# This allows the script to run from any directory
args <- commandArgs(trailingOnly = FALSE)
script_path <- normalizePath(sub("^--file=", "", args[grep("^--file=", args)]))
script_dir <- dirname(script_path)
project_root <- dirname(script_dir)
setwd(project_root)

# Source all modules (relative to project root)
source("R/config.R")
source("R/excel_handlers.R")
source("R/orders.R")
source("R/summary.R")
source("R/webhooks.R")

# Enable CORS for all responses
#* @filter cors
function(res) {
  res$setHeader("Access-Control-Allow-Origin", "*")
  res$setHeader("Access-Control-Allow-Methods", "GET, POST, PUT, DELETE, OPTIONS")
  res$setHeader("Access-Control-Allow-Headers", "Content-Type, Authorization")
  plumber::forward()
}

# Handle OPTIONS preflight requests
#* @options /.*
function() {
  return(list())
}

# Health check endpoint
#* @get /api/health
function() {
  return(list(
    status = "ok",
    timestamp = format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
    excel_file = get_excel_file()
  ))
}

# GET menu items
#* @get /api/menu
function() {
  return(get_menu())
}

# GET active orders (status = ordered or pending)
#* @get /api/orders/active
function() {
  filepath <- get_excel_file()
  return(get_active_orders(filepath))
}

# GET served orders (status = served)
#* @get /api/orders/served
function() {
  filepath <- get_excel_file()
  return(get_served_orders(filepath))
}

# GET order by table
#* @get /api/orders/table/<table>
function(table) {
  filepath <- get_excel_file()

  # URL decode table name
  table <- URLdecode(table)

  order <- get_order_by_table(table, filepath)

  if (is.null(order)) {
    return(list(error = "No active order for this table"))
  }

  return(order)
}

# GET order by ID
#* @get /api/orders/id/<order_id>
function(order_id) {
  filepath <- get_excel_file()
  order <- get_order_by_id(order_id, filepath)

  if (is.null(order)) {
    return(list(error = "Order not found"))
  }

  return(order)
}

# POST create new order
#* @post /api/orders
function(req, res) {
  # Parse request body
  body <- tryCatch({
    fromJSON(req$postBody, simplifyVector = FALSE)
  }, error = function(e) {
    return(NULL)
  })

  if (is.null(body)) {
    res$status <- 400
    return(list(error = "Invalid JSON"))
  }

  # Validate table
  table_validation <- validate_table(body$table)
  if (!table_validation$valid) {
    res$status <- 400
    return(list(error = table_validation$error))
  }

  # Parse and validate items
  items <- parse_items(body)
  items_validation <- validate_items(items)

  if (!items_validation$valid) {
    res$status <- 400
    return(list(error = items_validation$error))
  }

  # Calculate total (use provided total or calculate)
  order_total <- ifelse(is.null(body$order_total),
                        calculate_order_total(items),
                        body$order_total)

  # Create order
  order <- create_order(
    table = body$table,
    note = body$note,
    items = items,
    order_total = order_total
  )

  if (is.null(order)) {
    res$status <- 500
    return(list(error = "Failed to create order"))
  }

  res$status <- 201
  return(order)
}

# PUT update order (add items - creates new order, marks old as paid)
#* @put /api/orders/<orderId>
function(orderId, req, res) {
  # Parse request body
  body <- tryCatch({
    fromJSON(req$postBody, simplifyVector = FALSE)
  }, error = function(e) {
    return(NULL)
  })

  if (is.null(body)) {
    res$status <- 400
    return(list(error = "Invalid JSON"))
  }

  # Validate items
  items <- parse_items(body)
  items_validation <- validate_items(items)

  if (!items_validation$valid) {
    res$status <- 400
    return(list(error = items_validation$error))
  }

  # Calculate total
  order_total <- ifelse(is.null(body$order_total),
                        calculate_order_total(items),
                        body$order_total)

  # Get old order to get table
  filepath <- get_excel_file()
  old_order <- get_order_by_id(orderId, filepath)

  if (is.null(old_order)) {
    res$status <- 404
    return(list(error = "Order not found"))
  }

  table <- ifelse(is.null(body$table), old_order$table, body$table)

  # Update order (creates new, marks old as paid)
  new_order <- add_items_to_order(
    old_order_id = orderId,
    table = table,
    note = body$note,
    items = items,
    order_total = order_total
  )

  if (is.null(new_order)) {
    res$status <- 500
    return(list(error = "Failed to update order"))
  }

  return(new_order)
}

# POST mark order as served
#* @post /api/orders/<orderId>/serve
function(orderId, req, res) {
  filepath <- get_excel_file()

  # Check if order exists
  order <- get_order_by_id(orderId, filepath)

  if (is.null(order)) {
    res$status <- 404
    return(list(error = "Order not found"))
  }

  # Check if order can be served
  if (order$status == STATUS_SERVED) {
    res$status <- 400
    return(list(error = "Order already served"))
  }

  if (order$status == STATUS_PAID) {
    res$status <- 400
    return(list(error = "Order already paid"))
  }

  # Serve order
  result <- serve_order(orderId)

  if (!is.null(result$error)) {
    res$status <- 500
    return(result)
  }

  return(result)
}

# POST mark order as paid
#* @post /api/orders/<orderId>/paid
function(orderId, req, res) {
  filepath <- get_excel_file()

  # Check if order exists
  order <- get_order_by_id(orderId, filepath)

  if (is.null(order)) {
    res$status <- 404
    return(list(error = "Order not found"))
  }

  # Check if order can be paid
  if (order$status == STATUS_PAID) {
    res$status <- 400
    return(list(error = "Order already paid"))
  }

  # Pay order
  result <- pay_order(orderId)

  if (!is.null(result$error)) {
    res$status <- 500
    return(result)
  }

  return(result)
}

# GET daily summary for today
#* @get /api/summary/today
function() {
  filepath <- get_excel_file()

  # Ensure today's summary is up to date
  update_daily_summary(Sys.Date())

  summary <- get_today_summary()

  if (is.null(summary)) {
    return(list(
      date = as.character(Sys.Date()),
      total_orders = 0,
      total_money = 0,
      dine_in_orders = 0,
      takeaway_orders = 0
    ))
  }

  return(summary)
}

# GET daily summary for specific date
#* @get /api/summary/<date>
function(date) {
  filepath <- get_excel_file()

  # Parse date
  tryCatch({
    target_date <- as.Date(date)
  }, error = function(e) {
    return(NULL)
  })

  if (is.null(target_date)) {
    res$status <- 400
    return(list(error = "Invalid date format. Use YYYY-MM-DD"))
  }

  summary <- get_daily_summary(target_date)

  if (is.null(summary)) {
    res$status <- 404
    return(list(error = "No summary found for this date"))
  }

  return(summary)
}

# GET month summary
#* @get /api/summary/month/<year>/<month>
function(year, month, res) {
  tryCatch({
    start_date <- as.Date(paste0(year, "-", month, "-01"))
    end_date <- as.Date(paste0(year, "-", month, "-01")) %m+% months(1) - 1
  }, error = function(e) {
    res$status <- 400
    return(list(error = "Invalid year/month format"))
  })

  summaries <- get_summary_range(start_date, end_date)

  return(list(
    year = as.integer(year),
    month = as.integer(month),
    summaries = summaries
  ))
}

# POST recalculate summaries (admin function)
#* @post /api/summary/recalculate
function(req, res) {
  filepath <- get_excel_file()

  success <- recalculate_all_summaries()

  if (success) {
    return(list(message = "Summaries recalculated"))
  } else {
    res$status <- 500
    return(list(error = "Failed to recalculate summaries"))
  }
}

# Main entry point - start the Plumber server
if (!interactive()) {
  # Get port from environment or use default
  port <- Sys.getenv("PORT", "3003")
  port <- as.integer(port)

  cat(paste0("\n"))
  cat(paste0("========================================\n"))
  cat(paste0("  Bun Cha POS - Plumber API Server\n"))
  cat(paste0("========================================\n"))
  cat(paste0("Starting server on port ", port, "...\n"))
  cat(paste0("Excel file: ", get_excel_file(), "\n"))
  cat(paste0("Data directory: ", get_data_dir(), "\n"))
  cat(paste0("Socket.IO relay: ", socket_relay_url, "\n"))
  cat(paste0("========================================\n\n"))
}

# Run the server when script is executed directly
# In production, run with: Rscript plumber.R

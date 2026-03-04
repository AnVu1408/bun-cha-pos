# Bun Cha POS - Order CRUD Operations
# This file contains all order management functions

library(jsonlite)

# Source dependencies (relative to project root)
source("R/config.R")
source("R/excel_handlers.R")
source("R/webhooks.R")
source("R/summary.R")

# Create a new order
# Returns: order object (list) or NULL on failure
create_order <- function(table, note, items, order_total) {
  filepath <- get_excel_file()

  # Generate order ID
  order_id <- generate_order_id()

  # Create order object
  order <- list(
    order_id = order_id,
    table = table,
    note = note,
    items = items,
    order_total = order_total,
    status = STATUS_ORDERED,
    created_timestamp = format(Sys.time(), "%Y-%m-%d %H:%M:%S")
  )

  # Write to Excel
  success <- write_order(order, filepath)

  if (success) {
    # Add initial timestamp
    add_timestamp(order_id, table, STATUS_ORDERED, filepath)

    # Notify Socket.IO relay
    notify_socket("new_order", list(
      order = order,
      active_orders = get_active_orders(filepath)
    ))

    return(order)
  }

  return(NULL)
}

# Add items to existing order (creates new order, marks old as paid)
# This matches the current frontend behavior where updating an order
# creates a new order ID
add_items_to_order <- function(old_order_id, table, note, items, order_total) {
  filepath <- get_excel_file()

  # Get old order
  old_order <- get_order_by_id(old_order_id, filepath)

  if (is.null(old_order)) {
    return(NULL)
  }

  # Mark old order as paid
  update_order_status(old_order_id, STATUS_PAID, filepath)

  # Create new order with updated items
  new_order <- list(
    order_id = generate_order_id(),
    table = table,
    note = note,
    items = items,
    order_total = order_total,
    status = STATUS_ORDERED,
    created_timestamp = format(Sys.time(), "%Y-%m-%d %H:%M:%S")
  )

  # Write new order to Excel
  success <- write_order(new_order, filepath)

  if (success) {
    # Add timestamp
    add_timestamp(new_order$order_id, table, STATUS_ORDERED, filepath)

    # Update daily summary for the paid order
    update_daily_summary_for_order(old_order)

    # Notify Socket.IO relay
    notify_socket("order_updated", list(
      old_order_id = old_order_id,
      new_order = new_order,
      active_orders = get_active_orders(filepath)
    ))

    return(new_order)
  }

  return(NULL)
}

# Mark order as served
serve_order <- function(order_id) {
  filepath <- get_excel_file()

  # Get order first
  order <- get_order_by_id(order_id, filepath)

  if (is.null(order)) {
    return(list(error = "Order not found"))
  }

  # Update status
  success <- update_order_status(order_id, STATUS_SERVED, filepath)

  if (success) {
    # Get updated order
    updated_order <- get_order_by_id(order_id, filepath)

    # Notify Socket.IO relay
    notify_socket("order_served", list(
      order = updated_order,
      order_id = order_id
    ))

    return(updated_order)
  }

  return(list(error = "Failed to update order"))
}

# Mark order as paid
pay_order <- function(order_id) {
  filepath <- get_excel_file()

  # Get order first
  order <- get_order_by_id(order_id, filepath)

  if (is.null(order)) {
    return(list(error = "Order not found"))
  }

  # Update status
  success <- update_order_status(order_id, STATUS_PAID, filepath)

  if (success) {
    # Get updated order
    updated_order <- get_order_by_id(order_id, filepath)

    # Update daily summary
    update_daily_summary_for_order(updated_order)

    # Notify Socket.IO relay
    notify_socket("order_paid", list(
      order_id = order_id,
      active_orders = get_active_orders(filepath)
    ))

    return(updated_order)
  }

  return(list(error = "Failed to update order"))
}

# Mark order as finished (complete lifecycle)
finish_order <- function(order_id) {
  filepath <- get_excel_file()

  # Get order first
  order <- get_order_by_id(order_id, filepath)

  if (is.null(order)) {
    return(list(error = "Order not found"))
  }

  # Check if order can be finished
  if (order$status == STATUS_FINISHED) {
    return(list(error = "Order already finished"))
  }

  # Update status to finished
  success <- update_order_status(order_id, STATUS_FINISHED, filepath)

  if (success) {
    # Get updated order
    updated_order <- get_order_by_id(order_id, filepath)

    # Notify Socket.IO relay
    notify_socket("order_finished", list(
      order_id = order_id,
      active_orders = get_active_orders(filepath)
    ))

    return(updated_order)
  }

  return(list(error = "Failed to finish order"))
}

# Mark order as pending (kitchen starts preparing)
pending_order <- function(order_id) {
  filepath <- get_excel_file()

  # Get order first
  order <- get_order_by_id(order_id, filepath)

  if (is.null(order)) {
    return(list(error = "Order not found"))
  }

  # Check if order can be marked as pending
  if (order$status != STATUS_ORDERED) {
    return(list(error = "Order must be in 'ordered' status to mark as pending"))
  }

  # Update status to pending
  success <- update_order_status(order_id, STATUS_PENDING, filepath)

  if (success) {
    # Get updated order
    updated_order <- get_order_by_id(order_id, filepath)

    # Notify Socket.IO relay
    notify_socket("order_pending", list(
      order = updated_order,
      order_id = order_id,
      active_orders = get_active_orders(filepath)
    ))

    return(updated_order)
  }

  return(list(error = "Failed to mark order as pending"))
}

# Get menu items
get_menu <- function() {
  # Convert to list of objects for JSON response
  menu_list <- lapply(1:nrow(menu), function(i) {
    list(
      item_id = menu$item_id[i],
      item_name = menu$item_name[i],
      price = menu$price[i]
    )
  })

  return(menu_list)
}

# Calculate order total from items
calculate_order_total <- function(items) {
  total <- 0
  for (item in items) {
    price <- get_item_price(item$item_id)
    total <- total + (price * item$qty)
  }
  return(total)
}

# Validate order items
validate_items <- function(items) {
  if (is.null(items) || length(items) == 0) {
    return(list(valid = FALSE, error = "No items provided"))
  }

  for (item in items) {
    if (is.null(item$item_id) || is.null(item$qty)) {
      return(list(valid = FALSE, error = "Invalid item format"))
    }

    # Check if item exists in menu
    if (!(item$item_id %in% menu$item_id)) {
      return(list(valid = FALSE, error = paste("Unknown item_id:", item$item_id)))
    }

    # Check quantity
    if (item$qty < 0) {
      return(list(valid = FALSE, error = "Negative quantity not allowed"))
    }
  }

  return(list(valid = TRUE))
}

# Validate table
validate_table <- function(table) {
  if (is.null(table) || table == "") {
    return(list(valid = FALSE, error = "Table is required"))
  }

  if (!(table %in% tables)) {
    return(list(valid = FALSE, error = paste("Invalid table:", table)))
  }

  return(list(valid = TRUE))
}

# Parse items from request body
# Handles both array format and direct item submission
parse_items <- function(request_data) {
  items <- request_data$items

  if (is.null(items)) {
    return(NULL)
  }

  # Ensure items is a list
  if (!is.list(items)) {
    return(NULL)
  }

  return(items)
}

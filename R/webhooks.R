# Bun Cha POS - Webhook Notifications
# This file contains functions to notify the Node.js Socket.IO relay

library(httr)
library(jsonlite)

# Source configuration (relative to project root)
source("R/config.R")

# Notify Node.js Socket.IO relay of changes
# This function sends a POST request to the Node.js webhook endpoint
# which then broadcasts the event via Socket.IO to connected clients
notify_socket <- function(event_type, data) {
  tryCatch({
    # Build request body
    body <- list(
      event = event_type,
      data = data,
      timestamp = format(Sys.time(), "%Y-%m-%d %H:%M:%S")
    )

    # Convert to JSON
    body_json <- toJSON(body, auto_unbox = TRUE)

    # Send POST request to Node.js relay
    response <- POST(
      socket_relay_url,
      body = body_json,
      content_type_json(),
      timeout(2)  # 2 second timeout - don't block if relay is down
    )

    # Check response
    if (http_type(response) == "application/json") {
      content <- content(response, "text", encoding = "UTF-8")
      return(TRUE)
    }

    return(FALSE)

  }, error = function(e) {
    warning(paste("Failed to notify Socket.IO relay:", e$message))
    return(FALSE)
  })
}

# Notify new order event
notify_new_order <- function(order, active_orders) {
  notify_socket("new_order", list(
    order = order,
    active_orders = active_orders
  ))
}

# Notify order served event
notify_order_served <- function(order) {
  notify_socket("order_served", list(
    order = order,
    order_id = order$order_id
  ))
}

# Notify order paid event
notify_order_paid <- function(order_id, active_orders) {
  notify_socket("order_paid", list(
    order_id = order_id,
    active_orders = active_orders
  ))
}

# Notify orders update event (general refresh)
notify_orders_update <- function(active_orders) {
  notify_socket("orders_update", list(
    orders = active_orders
  ))
}

# Notify order served update event
notify_order_served_update <- function(order_id) {
  notify_socket("order_served_update", list(
    order_id = order_id
  ))
}

# Check if Socket.IO relay is available
check_relay_available <- function() {
  tryCatch({
    response <- GET(socket_relay_url, timeout(1))
    return(status_code(response) == 200)
  }, error = function(e) {
    return(FALSE)
  })
}

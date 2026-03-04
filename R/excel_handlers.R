# Bun Cha POS - Excel File Handlers
# This file contains all Excel file I/O operations

library(openxlsx)
library(lubridate)

# Source configuration (relative to project root)
source("R/config.R")

# Initialize Excel file with proper sheets if it doesn't exist
initialize_excel_file <- function(filepath) {
  if (!file.exists(filepath)) {
    # Ensure data directory exists
    data_dir <- dirname(filepath)
    if (!dir.exists(data_dir)) {
      dir.create(data_dir, recursive = TRUE)
    }

    # Create Orders sheet with item ID columns
    orders_df <- data.frame(
      order_id = character(),
      table = character(),
      note = character(),
      created_timestamp = character(),
      stringsAsFactors = FALSE
    )
    # Add item columns
    for (item in menu$item_id) {
      orders_df[[item]] <- integer()
    }
    orders_df$total <- numeric()
    orders_df$status <- character()
    # Timestamps for each status
    orders_df$ordered_timestamp <- character()
    orders_df$pending_timestamp <- character()
    orders_df$served_timestamp <- character()
    orders_df$paid_timestamp <- character()
    orders_df$finished_timestamp <- character()

    # Create Timestamps sheet
    timestamps_df <- data.frame(
      timestamp = character(),
      order_id = character(),
      table = character(),
      status = character(),
      stringsAsFactors = FALSE
    )

    # Create DailySummary sheet
    summary_df <- data.frame(
      date = character(),
      total_orders = integer(),
      total_money = numeric(),
      dine_in_orders = integer(),
      takeaway_orders = integer(),
      stringsAsFactors = FALSE
    )
    # Add dish count columns
    for (item in menu$item_id) {
      summary_df[[paste0("count_", item)]] <- integer()
    }

    # Write to file
    wb <- createWorkbook()
    addWorksheet(wb, "Orders")
    addWorksheet(wb, "Timestamps")
    addWorksheet(wb, "DailySummary")
    writeData(wb, "Orders", orders_df)
    writeData(wb, "Timestamps", timestamps_df)
    writeData(wb, "DailySummary", summary_df)
    saveWorkbook(wb, filepath, overwrite = TRUE)

    message(paste("Created new Excel file:", filepath))
  }
  return(filepath)
}

# Read all orders from Excel file
read_orders <- function(filepath = get_excel_file()) {
  initialize_excel_file(filepath)

  tryCatch({
    wb <- loadWorkbook(filepath)
    orders <- readWorkbook(wb, sheet = "Orders")
    return(orders)
  }, error = function(e) {
    warning(paste("Error reading orders:", e$message))
    return(data.frame())
  })
}

# Write a new order to Excel file
write_order <- function(order_data, filepath = get_excel_file()) {
  initialize_excel_file(filepath)

  tryCatch({
    wb <- loadWorkbook(filepath)
    existing_orders <- readWorkbook(wb, sheet = "Orders")

    # Create new row with all columns
    new_row <- data.frame(
      order_id = order_data$order_id,
      table = order_data$table,
      note = ifelse(is.null(order_data$note), "", order_data$note),
      created_timestamp = order_data$created_timestamp,
      stringsAsFactors = FALSE
    )

    # Add item columns
    for (item in menu$item_id) {
      qty <- 0
      if (!is.null(order_data$items)) {
        for (i in seq_along(order_data$items)) {
          if (order_data$items[[i]]$item_id == item) {
            qty <- order_data$items[[i]]$qty
            break
          }
        }
      }
      new_row[[item]] <- qty
    }

    new_row$total <- order_data$order_total
    new_row$status <- order_data$status
    # Set ordered_timestamp for new orders
    new_row$ordered_timestamp <- ifelse(is.null(order_data$created_timestamp), "", order_data$created_timestamp)
    new_row$pending_timestamp <- ""
    new_row$served_timestamp <- ""
    new_row$paid_timestamp <- ""
    new_row$finished_timestamp <- ""

    # Append to existing orders
    updated_orders <- rbind(existing_orders, new_row)

    # Write back
    writeData(wb, "Orders", updated_orders)
    saveWorkbook(wb, filepath, overwrite = TRUE)

    return(TRUE)
  }, error = function(e) {
    warning(paste("Error writing order:", e$message))
    return(FALSE)
  })
}

# Update order status in Excel file
update_order_status <- function(order_id, status, filepath = get_excel_file()) {
  initialize_excel_file(filepath)

  tryCatch({
    wb <- loadWorkbook(filepath)
    orders <- readWorkbook(wb, sheet = "Orders")

    # Find and update the order
    idx <- which(orders$order_id == order_id)
    if (length(idx) > 0) {
      orders$status[idx] <- status

      # Add appropriate timestamp based on status
      timestamp <- format(Sys.time(), "%Y-%m-%d %H:%M:%S")
      if (status == STATUS_ORDERED) {
        orders$ordered_timestamp[idx] <- timestamp
      } else if (status == STATUS_PENDING) {
        orders$pending_timestamp[idx] <- timestamp
      } else if (status == STATUS_SERVED) {
        orders$served_timestamp[idx] <- timestamp
      } else if (status == STATUS_PAID) {
        orders$paid_timestamp[idx] <- timestamp
      } else if (status == STATUS_FINISHED) {
        orders$finished_timestamp[idx] <- timestamp
      }

      writeData(wb, "Orders", orders)
      saveWorkbook(wb, filepath, overwrite = TRUE)

      # Add to timestamps sheet - this tracks ALL actions
      add_timestamp(order_id, orders$table[idx], status, filepath)

      return(TRUE)
    }
    return(FALSE)
  }, error = function(e) {
    warning(paste("Error updating order status:", e$message))
    return(FALSE)
  })
}

# Add timestamp entry to Timestamps sheet
add_timestamp <- function(order_id, table, status, filepath = get_excel_file()) {
  initialize_excel_file(filepath)

  tryCatch({
    wb <- loadWorkbook(filepath)
    timestamps <- readWorkbook(wb, sheet = "Timestamps")

    new_timestamp <- data.frame(
      timestamp = format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
      order_id = order_id,
      table = table,
      status = status,
      stringsAsFactors = FALSE
    )

    updated_timestamps <- rbind(timestamps, new_timestamp)
    writeData(wb, "Timestamps", updated_timestamps)
    saveWorkbook(wb, filepath, overwrite = TRUE)

    return(TRUE)
  }, error = function(e) {
    warning(paste("Error adding timestamp:", e$message))
    return(FALSE)
  })
}

# Read all timestamps
read_timestamps <- function(filepath = get_excel_file()) {
  initialize_excel_file(filepath)

  tryCatch({
    wb <- loadWorkbook(filepath)
    timestamps <- readWorkbook(wb, sheet = "Timestamps")
    return(timestamps)
  }, error = function(e) {
    warning(paste("Error reading timestamps:", e$message))
    return(data.frame())
  })
}

# Write or update daily summary
write_daily_summary <- function(summary_data, filepath = get_excel_file()) {
  initialize_excel_file(filepath)

  tryCatch({
    wb <- loadWorkbook(filepath)
    summaries <- readWorkbook(wb, sheet = "DailySummary")

    # Check if summary for this date exists
    idx <- which(summaries$date == summary_data$date)

    # Create summary row
    new_row <- data.frame(
      date = summary_data$date,
      total_orders = summary_data$total_orders,
      total_money = summary_data$total_money,
      dine_in_orders = summary_data$dine_in_orders,
      takeaway_orders = summary_data$takeaway_orders,
      stringsAsFactors = FALSE
    )

    # Add dish count columns
    for (item in menu$item_id) {
      count_key <- paste0("count_", item)
      new_row[[count_key]] <- summary_data[[count_key]]
    }

    if (length(idx) > 0) {
      # Update existing row
      for (col in names(new_row)) {
        summaries[idx, col] <- new_row[[col]]
      }
      updated_summaries <- summaries
    } else {
      # Append new row
      updated_summaries <- rbind(summaries, new_row)
    }

    writeData(wb, "DailySummary", updated_summaries)
    saveWorkbook(wb, filepath, overwrite = TRUE)

    return(TRUE)
  }, error = function(e) {
    warning(paste("Error writing daily summary:", e$message))
    return(FALSE)
  })
}

# Read daily summaries
read_daily_summaries <- function(filepath = get_excel_file()) {
  initialize_excel_file(filepath)

  tryCatch({
    wb <- loadWorkbook(filepath)
    summaries <- readWorkbook(wb, sheet = "DailySummary")
    return(summaries)
  }, error = function(e) {
    warning(paste("Error reading daily summaries:", e$message))
    return(data.frame())
  })
}

# Convert order row from Excel to JSON-like structure
order_row_to_json <- function(row) {
  # Convert single row data frame to named list
  row_list <- as.list(row)
  row_names <- names(row_list)

  # Build items array from columns
  items <- list()
  for (item in menu$item_id) {
    if (item %in% row_names) {
      qty_val <- row_list[[item]]
      # Check if qty exists and is valid
      if (!is.null(qty_val) && length(qty_val) > 0) {
        qty <- as.integer(qty_val)
        if (!is.na(qty) && qty > 0) {
          items <- c(items, list(list(
            item_id = item,
            item_name = get_item_name(item),
            qty = qty
          )))
        }
      }
    }
  }

  # Handle empty/NA notes
  note_val <- NULL
  if ("note" %in% row_names) {
    note_val <- row_list$note
    if (is.null(note_val) || (is.atomic(note_val) && length(note_val) == 1 && is.na(note_val))) {
      note_val <- ""
    } else if (is.null(note_val)) {
      note_val <- ""
    }
  } else {
    note_val <- ""
  }

  # Helper to handle timestamp fields
  handle_ts <- function(ts) {
    if (is.null(ts)) {
      return(NULL)
    }
    if (length(ts) == 0) {
      return(NULL)
    }
    if (is.na(ts[1]) || ts[1] == "") {
      return(NULL)
    }
    return(ts[1])
  }

  return(list(
    order_id = row_list$order_id,
    table = row_list$table,
    note = note_val,
    items = items,
    order_total = as.numeric(row_list$total),
    status = row_list$status,
    created_timestamp = row_list$created_timestamp,
    ordered_timestamp = handle_ts(row_list$ordered_timestamp),
    pending_timestamp = handle_ts(row_list$pending_timestamp),
    served_timestamp = handle_ts(row_list$served_timestamp),
    paid_timestamp = handle_ts(row_list$paid_timestamp),
    finished_timestamp = handle_ts(row_list$finished_timestamp)
  ))
}

# Get active orders (status = ordered or pending)
get_active_orders <- function(filepath = get_excel_file()) {
  orders <- read_orders(filepath)
  active <- orders[orders$status %in% c(STATUS_ORDERED, STATUS_PENDING), ]

  # Convert to JSON format
  result <- lapply(1:nrow(active), function(i) {
    order_row_to_json(active[i, ])
  })

  return(result)
}

# Get served orders
get_served_orders <- function(filepath = get_excel_file()) {
  orders <- read_orders(filepath)
  served <- orders[orders$status == STATUS_SERVED, ]

  # Convert to JSON format
  result <- lapply(1:nrow(served), function(i) {
    order_row_to_json(served[i, ])
  })

  return(result)
}

# Get order by table
get_order_by_table <- function(table, filepath = get_excel_file()) {
  orders <- read_orders(filepath)
  order <- orders[orders$table == table & orders$status %in% c(STATUS_ORDERED, STATUS_PENDING), ]

  if (nrow(order) > 0) {
    return(order_row_to_json(order[1, ]))
  }

  return(NULL)
}

# Get order by order_id
get_order_by_id <- function(order_id, filepath = get_excel_file()) {
  orders <- read_orders(filepath)
  order <- orders[orders$order_id == order_id, ]

  if (nrow(order) > 0) {
    return(order_row_to_json(order[1, ]))
  }

  return(NULL)
}

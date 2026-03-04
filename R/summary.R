# Bun Cha POS - Daily Summary Calculations
# This file contains functions for calculating and updating daily summaries

library(lubridate)

# Source dependencies (relative to project root)
source("R/config.R")
source("R/excel_handlers.R")

# Update daily summary for a specific date
# If date is not provided, uses today's date
update_daily_summary <- function(date = Sys.Date()) {
  filepath <- get_excel_file()
  date_str <- as.character(date)

  # Read all orders
  orders <- read_orders(filepath)

  if (nrow(orders) == 0) {
    return(FALSE)
  }

  # Extract date from created_timestamp
  order_dates <- sapply(orders$created_timestamp, function(ts) {
    # Parse timestamp and get date part
    ts_date <- as.Date(ts, format = "%Y-%m-%d %H:%M:%S")
    if (is.na(ts_date)) {
      return(NA)
    }
    return(as.character(ts_date))
  })

  # Filter orders for the specified date
  daily_mask <- order_dates == date_str & !is.na(order_dates)
  daily_orders <- orders[daily_mask, ]

  if (nrow(daily_orders) == 0) {
    return(FALSE)
  }

  # Calculate totals
  total_orders <- nrow(daily_orders)
  total_money <- sum(daily_orders$total, na.rm = TRUE)

  # Count dine-in vs takeaway
  dine_in_count <- sum(!daily_orders$table %in% c("Delivery", "Goka"), na.rm = TRUE)
  takeaway_count <- sum(daily_orders$table %in% c("Delivery", "Goka"), na.rm = TRUE)

  # Count each dish
  dish_counts <- list()
  for (item in menu$item_id) {
    count_key <- paste0("count_", item)
    dish_counts[[count_key]] <- sum(daily_orders[[item]], na.rm = TRUE)
  }

  # Build summary object
  summary <- list(
    date = date_str,
    total_orders = total_orders,
    total_money = total_money,
    dine_in_orders = dine_in_count,
    takeaway_orders = takeaway_count
  )

  # Add dish counts
  for (key in names(dish_counts)) {
    summary[[key]] <- dish_counts[[key]]
  }

  # Write to Excel
  success <- write_daily_summary(summary, filepath)

  return(success)
}

# Update daily summary for a specific order (called when order is paid)
update_daily_summary_for_order <- function(order) {
  # Extract date from order's created_timestamp
  order_date <- as.Date(order$created_timestamp, format = "%Y-%m-%d %H:%M:%S")

  if (is.na(order_date)) {
    return(FALSE)
  }

  return(update_daily_summary(order_date))
}

# Get daily summary for a specific date
get_daily_summary <- function(date = Sys.Date()) {
  filepath <- get_excel_file()
  date_str <- as.character(date)

  summaries <- read_daily_summaries(filepath)

  if (nrow(summaries) == 0) {
    return(NULL)
  }

  # Find summary for the specified date
  idx <- which(summaries$date == date_str)

  if (length(idx) > 0) {
    summary_row <- summaries[idx, ]
    return(list(
      date = summary_row$date,
      total_orders = summary_row$total_orders,
      total_money = summary_row$total_money,
      dine_in_orders = summary_row$dine_in_orders,
      takeaway_orders = summary_row$takeaway_orders
    ))
  }

  return(NULL)
}

# Get summary for a date range
get_summary_range <- function(start_date, end_date) {
  filepath <- get_excel_file()

  summaries <- read_daily_summaries(filepath)

  if (nrow(summaries) == 0) {
    return(list())
  }

  # Filter by date range
  start_str <- as.character(start_date)
  end_str <- as.character(end_date)

  mask <- summaries$date >= start_str & summaries$date <= end_str
  filtered <- summaries[mask, ]

  # Convert to list
  result <- lapply(1:nrow(filtered), function(i) {
    row <- filtered[i, ]
    summary_obj <- list(
      date = row$date,
      total_orders = row$total_orders,
      total_money = row$total_money,
      dine_in_orders = row$dine_in_orders,
      takeaway_orders = row$takeaway_orders
    )

    # Add dish counts
    for (item in menu$item_id) {
      count_key <- paste0("count_", item)
      summary_obj[[count_key]] <- row[[count_key]]
    }

    return(summary_obj)
  })

  return(result)
}

# Get today's summary
get_today_summary <- function() {
  return(get_daily_summary(Sys.Date()))
}

# Get current month summary
get_month_summary <- function() {
  start_date <- floor_date(Sys.Date(), "month")
  end_date <- ceiling_date(Sys.Date(), "month") - 1

  return(get_summary_range(start_date, end_date))
}

# Recalculate all daily summaries (utility function for fixing data)
recalculate_all_summaries <- function() {
  filepath <- get_excel_file()

  # Read all orders
  orders <- read_orders(filepath)

  if (nrow(orders) == 0) {
    return(FALSE)
  }

  # Get unique dates from orders
  order_dates <- sapply(orders$created_timestamp, function(ts) {
    ts_date <- as.Date(ts, format = "%Y-%m-%d %H:%M:%S")
    if (is.na(ts_date)) {
      return(NA)
    }
    return(as.character(ts_date))
  })

  unique_dates <- unique(order_dates[!is.na(order_dates)])

  # Recalculate each date
  for (date_str in unique_dates) {
    date <- as.Date(date_str)
    update_daily_summary(date)
  }

  return(TRUE)
}

# Bun Cha POS - Configuration File
# This file contains menu, table, and file path configuration

# Menu configuration - data frame with all menu items
menu <- data.frame(
  item_id = c("bun_cha", "bun_cha_dac_biet", "giay", "nem_nho", "nem_lon",
              "thit_them", "tac", "chanh", "pepsi", "sting", "7up", "suoi"),
  item_name = c("Bún Chả", "Bún Chả Đặc Biệt", "Giả Cày", "Nem Nhỏ", "Nem Lớn",
                "Thịt Thêm", "Tắc", "Chanh", "Pepsi", "Sting", "7Up", "Suối"),
  price = c(40000, 60000, 150000, 20000, 40000, 35000, 15000, 15000, 15000, 15000, 15000, 10000),
  stringsAsFactors = FALSE
)

# Table IDs - 10 numeric tables + Delivery + Goka (takeaway)
tables <- c("1", "2", "3", "4", "5", "6", "7", "8", "9", "10", "Delivery", "Goka")

# Get Excel file path for current month
# Returns absolute path to the Excel file
get_excel_file <- function() {
  month <- format(Sys.Date(), "%Y-%m")
  # Use the project root that was set during initialization
  # Fallback to current working directory if not set
  root <- getOption("buncha.project.root")
  if (is.null(root)) {
    # Try to determine based on current working directory
    cwd <- getwd()
    if (basename(cwd) == "R") {
      root <- dirname(cwd)
    } else if (basename(dirname(cwd)) == "buncha") {
      root <- dirname(dirname(cwd))
    } else {
      root <- cwd
    }
  }
  paste0(root, "/data/pos-data-", month, ".xlsx")
}

# Get data directory path (relative to script location)
get_data_dir <- function() {
  "data"
}

# Node.js Socket.IO relay URL for webhooks
socket_relay_url <- "http://localhost:3004/webhook"

# Order status constants
STATUS_ORDERED <- "ordered"
STATUS_PENDING <- "pending"
STATUS_SERVED <- "served"
STATUS_PAID <- "paid"
STATUS_FINISHED <- "finished"

# Helper function to get item price by item_id
get_item_price <- function(item_id) {
  idx <- which(menu$item_id == item_id)
  if (length(idx) > 0) {
    return(menu$price[idx[1]])
  }
  return(0)
}

# Helper function to get item name by item_id
get_item_name <- function(item_id) {
  idx <- which(menu$item_id == item_id)
  if (length(idx) > 0) {
    return(menu$item_name[idx[1]])
  }
  return(item_id)
}

# Helper function to check if table is special (Delivery or Goka)
is_special_table <- function(table) {
  table %in% c("Delivery", "Goka")
}

# Generate unique order ID
generate_order_id <- function() {
  # Simple ID generation based on timestamp
  paste0("ORD", format(Sys.time(), "%Y%m%d%H%M%S"))
}

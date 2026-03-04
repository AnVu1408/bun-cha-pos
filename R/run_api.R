#!/usr/bin/env Rscript
# Bun Cha POS - Plumber API Startup Script

# Set working directory to project root
args <- commandArgs(trailingOnly = FALSE)
script_path <- normalizePath(sub("^--file=", "", args[grep("^--file=", args)]))
script_dir <- dirname(script_path)
project_root <- dirname(script_dir)
setwd(project_root)

# Store project root for use in config.R
options(buncha.project.root = project_root)

# Load required libraries
library(plumber)
library(jsonlite)
library(openxlsx)
library(lubridate)
library(httr)

# Source all modules
source("R/config.R")
source("R/excel_handlers.R")
source("R/orders.R")
source("R/summary.R")
source("R/webhooks.R")

# Print startup message
cat("\n========================================\n")
cat("  Bun Cha POS - Plumber API Server\n")
cat("========================================\n")
cat("Starting server on port 3003...\n")
cat("Working directory:", getwd(), "\n")
cat("Excel file:", get_excel_file(), "\n")
cat("Data directory:", get_data_dir(), "\n")
cat("Socket.IO relay:", socket_relay_url, "\n")
cat("========================================\n\n")

# Start the Plumber server
pr <- plumb("R/api.R")
pr$run(host="0.0.0.0", port=3003, swagger=TRUE)

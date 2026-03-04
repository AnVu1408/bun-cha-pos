# Bun Cha POS - R Backend + Excel Storage Implementation

A hybrid POS (Point of Sale) system for Bún chả Hà Nội restaurant using:
- **R with Plumber** for REST API and data persistence
- **Node.js + Socket.IO** for real-time updates only
- **Excel files** as the database (monthly files with structured sheets)

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                         Frontend (HTML/JS)                       │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────────────┐   │
│  │ tables.html  │  │ waiter.html  │  │   kitchen.html       │   │
│  └──────┬───────┘  └──────┬───────┘  └──────────┬───────────┘   │
│         │                 │                      │               │
│         └─────────────────┴──────────────────────┘               │
│                           │                                      │
│                           ▼                                      │
│  ┌────────────────────────────────────────────────────────────┐ │
│  │              Node.js (Socket.IO Only) - Port 3004          │ │
│  │  - Broadcasts real-time events to connected clients        │ │
│  │  - Receives webhook notifications from R API               │ │
│  └────────────────────┬───────────────────────────────────────┘ │
│                       │                                          │
│                       ▼                                          │
│  ┌────────────────────────────────────────────────────────────┐ │
│  │              R Plumber API - Port 3003                     │ │
│  │  - CRUD operations for orders                              │ │
│  │  - Excel file I/O                                          │ │
│  │  - Daily summary calculations                              │ │
│  └────────────────────┬───────────────────────────────────────┘ │
│                       │                                          │
│                       ▼                                          │
│  ┌────────────────────────────────────────────────────────────┐ │
│  │         Excel Files (Monthly)                              │ │
│  │  pos-data-YYYY-MM.xlsx                                     │ │
│  └────────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────┘
```

## File Structure

```
workspace/buncha/
├── R/                         # R Backend
│   ├── plumber.R              # Main Plumber API server (port 3003)
│   ├── config.R               # Configuration (menu, tables, file paths)
│   ├── excel_handlers.R       # Excel read/write functions
│   ├── orders.R               # Order CRUD operations
│   ├── summary.R              # Daily summary calculations
│   └── webhooks.R             # Notify Node.js of changes
│
├── node_socket/               # Node.js Socket.IO Relay (port 3004)
│   ├── package.json
│   ├── socket_relay.js        # Minimal Socket.IO server
│   └── README.md
│
├── frontend/                  # Frontend (no changes needed)
│   ├── waiter.html
│   ├── kitchen.html
│   └── tables.html
│
├── data/                      # Excel storage
│   └── pos-data-YYYY-MM.xlsx  # Monthly files (auto-created)
│
├── start.sh                   # Startup script
├── server.js                  # OLD: Node.js server (deprecated)
└── package.json               # OLD: Root package.json (deprecated)
```

## Excel File Structure

Monthly files: `data/pos-data-YYYY-MM.xlsx`

### Sheet 1: Orders
| order_id | table | note | created_timestamp | bun_cha | giay | ... | total | status | served_timestamp | paid_timestamp |
|----------|-------|------|-------------------|---------|------|-----|-------|--------|------------------|----------------|

### Sheet 2: Timestamps
| timestamp | order_id | table | status |
|-----------|----------|-------|--------|

### Sheet 3: DailySummary
| date | total_orders | total_money | dine_in_orders | takeaway_orders | count_bun_cha | count_giay | ... |
|------|--------------|-------------|----------------|-----------------|---------------|------------|-----|

## Prerequisites

### R (version 4.0+)
Install required packages:
```r
install.packages(c("plumber", "openxlsx", "lubridate", "jsonlite", "httr"))
```

### Node.js (version 16+)
```bash
cd node_socket
npm install
```

## Quick Start

### Option 1: Using the startup script (recommended)
```bash
./start.sh
```

### Option 2: Manual startup

Terminal 1 - Start R Plumber API:
```bash
cd /Users/anvu/workspace/buncha/R
Rscript plumber.R
```

Terminal 2 - Start Node.js Socket.IO relay:
```bash
cd /Users/anvu/workspace/buncha/node_socket
npm start
```

### Access the application
- Frontend: http://localhost:3004/tables.html
- API Health: http://localhost:3003/api/health
- Relay Health: http://localhost:3004/health

## API Endpoints

| Method | Endpoint | Purpose |
|--------|----------|---------|
| GET | `/api/health` | Health check |
| GET | `/api/menu` | Get menu items |
| GET | `/api/orders/active` | Get active orders |
| GET | `/api/orders/served` | Get served orders |
| GET | `/api/orders/table/:table` | Get order by table |
| POST | `/api/orders` | Create new order |
| PUT | `/api/orders/:orderId` | Add items to order |
| POST | `/api/orders/:orderId/serve` | Mark order as served |
| POST | `/api/orders/:orderId/paid` | Mark order as paid |
| GET | `/api/summary/today` | Get today's summary |
| GET | `/api/summary/:date` | Get summary for date |

## Configuration

Edit `R/config.R` to change:
- Menu items and prices
- Table IDs
- Excel file paths
- Node.js relay URL

## Migration Notes

### Frontend Changes Required: NONE
The frontend works unchanged because:
1. API contract is identical
2. Socket.IO events are identical
3. Node.js relay serves the frontend files

### Table IDs
- Tables 1-10: Numeric (dine-in)
- "Delivery": Delivery orders
- "Goka": Takeaway orders (was "Takeaway" in plan, kept "Goka" for compatibility)

### Order Status Flow
1. `ordered` → Initial status when created
2. `served` → Marked as served by kitchen
3. `paid` → Marked as paid by cashier

## Development

### Adding new menu items
Edit `R/config.R`:
```r
menu <- data.frame(
  item_id = c("bun_cha", "new_item", ...),
  item_name = c("Bún Chả", "New Item", ...),
  price = c(40000, 50000, ...),
  stringsAsFactors = FALSE
)
```

### Testing
```bash
# Get menu
curl http://localhost:3003/api/menu

# Create order
curl -X POST http://localhost:3003/api/orders \
  -H "Content-Type: application/json" \
  -d '{"table":"1","note":"","items":[{"item_id":"bun_cha","qty":2}],"order_total":80000}'
```

## Troubleshooting

### R fails to start
- Check R packages are installed
- Verify port 3003 is not in use

### Node.js fails to start
- Run `npm install` in node_socket directory
- Verify port 3004 is not in use

### Excel file errors
- Check data directory exists
- Verify write permissions

### Socket.IO not working
- Ensure Node.js relay is running on port 3004
- Check R can reach http://localhost:3004/webhook

## License

MIT

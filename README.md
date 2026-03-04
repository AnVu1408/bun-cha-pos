# 🍜 Bún Chả POS System

A full-featured Point of Sale (POS) system for Bún Chả Hà Nội restaurant. Built with Node.js, Express, Socket.IO, and vanilla JavaScript.

![Node.js](https://img.shields.io/badge/Node.js-18+-green.svg)
![Socket.IO](https://img.shields.io/badge/Socket.IO-4.7+-black.svg)

## ✨ Features

### Order Management
- 📋 Create, update, and track orders in real-time
- 🍽️ Support for Dine-in, Takeaway, and Goka (Delivery) orders
- 🔢 Multiple concurrent orders for Takeaway and Delivery
- 📊 Real-time order synchronization across all devices

### Kitchen Display
- ⏱️ Live timer showing wait time for each order
- 🎨 Color-coded alerts (Amber → Yellow → Red based on wait time)
- 🔔 Audio alerts at 3, 5, and 10 minutes
- 📝 Customer notes highlighted for kitchen staff

### Excel Export
- 📊 Two-sheet Excel export with complete data
  - **Sheet 1:** Orders (one row per order, item quantities in columns)
  - **Sheet 2:** Daily Summary (date, order counts, item sales, revenue)
- 💾 Automatic data persistence to JSON files
- 📦 Monthly archival of old data

### Multi-Device Support
- 🖥️ **Tables Page** - Manage table availability and orders
- 👨‍🍳 **Kitchen Page** - View and manage active orders
- 📝 **Waiter Page** - Create and edit orders
- 📈 **Excel Page** - View summaries and export data

## 🚀 Quick Start

### Prerequisites
- Node.js 18+ installed
- npm or yarn package manager

### Installation

```bash
# Clone the repository
git clone https://github.com/AnVu1408/bun-cha-pos.git
cd bun-cha-pos

# Install dependencies
npm install

# Start the server
npm start
```

The server will start on `http://localhost:3003`

### Access the Application

| Page | URL |
|------|-----|
| Tables | http://localhost:3003/tables.html |
| Kitchen | http://localhost:3003/kitchen.html |
| Excel | http://localhost:3003/excel.html |

## 📁 Project Structure

```
bun-cha-pos/
├── server.js           # Main Express server with Socket.IO
├── data-store.js       # Data persistence layer (JSON files)
├── package.json        # Dependencies and scripts
├── frontend/           # Frontend pages
│   ├── tables.html     # Table management
│   ├── kitchen.html    # Kitchen display
│   ├── waiter.html     # Order creation/editing
│   ├── excel.html      # Data export
│   └── sound.mp3       # Alert sound
├── data/               # Data storage (auto-generated)
│   ├── orders.json     # All orders
│   ├── summaries.json  # Daily summaries
│   └── archive/        # Archived old data
├── R/                  # R implementation (alternative)
└── node_socket/        # Socket relay (legacy)
```

## 🎯 Menu Items

| Item ID | Item Name | Price (₫) |
|---------|-----------|------------|
| bun_cha | Bún Chả | 40,000 |
| bun_cha_dac_biet | Bún Chả Đặc Biệt | 60,000 |
| giay | Giả Cày | 150,000 |
| nem_nho | Nem Nhỏ | 20,000 |
| nem_lon | Nem Lớn | 40,000 |
| thit_them | Thịt Thêm | 35,000 |
| tac | Tắc | 15,000 |
| chanh | Chanh | 15,000 |
| pepsi | Pepsi | 15,000 |
| sting | Sting | 15,000 |
| 7up | 7Up | 15,000 |
| suoi | Suối | 10,000 |

## 🔧 Configuration

### Port
Default port is `3003`. Change with environment variable:
```bash
PORT=8080 npm start
```

### Data Storage
- Orders stored in `data/orders.json`
- Summaries stored in `data/summaries.json`
- Archived monthly to `data/archive/`

## 📊 API Endpoints

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/api/menu` | Get all menu items |
| GET | `/api/orders/active` | Get active orders |
| GET | `/api/orders/served` | Get served orders |
| GET | `/api/orders/table/:table` | Get order by table |
| POST | `/api/orders` | Create new order |
| PUT | `/api/orders/:orderId` | Update order |
| POST | `/api/orders/:orderId/serve` | Mark as served |
| POST | `/api/orders/:orderId/paid` | Mark as paid |
| GET | `/api/export/excel` | Download Excel file |
| GET | `/api/summary/today` | Get today's summary |

## 🎨 Order Types

### Dine-In (Tables 1-10)
- One active order per table
- Orders shown in Active Orders section
- Must be served before payment

### Takeaway
- Multiple concurrent orders supported
- Each order has unique Order ID
- Same flow as dine-in orders

### Goka (Delivery)
- Multiple concurrent orders supported
- Tracked separately in summaries
- For delivery app orders

## 📈 Daily Summary Columns

| Column | Description |
|--------|-------------|
| Date | Order date |
| Total Orders | Total paid orders |
| Dine In | Dine-in order count |
| Takeaway | Takeaway order count |
| Goka (Delivery) | Goka delivery count |
| [Item Names] | Quantity sold per item |
| Total Money | Total revenue (₫) |

## 🔄 Data Flow

```
1. Waiter creates order → POST /api/orders
2. Kitchen sees order → Socket.IO event 'new_order'
3. Kitchen serves order → POST /api/orders/:id/serve
4. Tables page updates → Socket.IO event 'order_served'
5. Payment → POST /api/orders/:id/paid
6. Data saved → JSON files updated
```

## 🛠️ Development

### Adding New Menu Items

Edit `server.js`:

```javascript
const menu = [
  // ... existing items
  { item_id: 'new_item', item_name: 'New Item', price: 50000 }
];
```

### Changing Port

```javascript
// In server.js
const PORT = process.env.PORT || 3003;
```

Or use environment variable:
```bash
PORT=8080 npm start
```

## 📝 License

This project is open source and available under the [MIT License](LICENSE).

## 👨‍💻 Author

**AnVu1408** - [GitHub](https://github.com/AnVu1408)

## 🙏 Acknowledgments

Built with ❤️ for Bún chả Hà Nội - Minh Hương

- Frontend: Tailwind CSS
- Backend: Express + Socket.IO
- Excel Export: ExcelJS
- Real-time: Socket.IO

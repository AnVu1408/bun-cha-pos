const express = require('express');
const { createServer } = require('http');
const { Server } = require('socket.io');
const { v4: uuidv4 } = require('uuid');
const path = require('path');
const ExcelJS = require('exceljs');
const dataStore = require('./data-store');

const app = express();
const httpServer = createServer(app);
const io = new Server(httpServer, {
  cors: { origin: "*" }
});

// CORS middleware
app.use((req, res, next) => {
  res.header('Access-Control-Allow-Origin', '*');
  res.header('Access-Control-Allow-Methods', 'GET, POST, PUT, DELETE, OPTIONS');
  res.header('Access-Control-Allow-Headers', 'Content-Type, Authorization');
  if (req.method === 'OPTIONS') {
    return res.sendStatus(200);
  }
  next();
});

app.use(express.json());

const menu = [
  { item_id: 'bun_cha', item_name: 'Bún Chả', price: 40000 },
  { item_id: 'bun_cha_dac_biet', item_name: 'Bún Chả Đặc Biệt', price: 60000 },
  { item_id: 'giay', item_name: 'Giả Cày', price: 150000 },
  { item_id: 'nem_nho', item_name: 'Nem Nhỏ', price: 20000 },
  { item_id: 'nem_lon', item_name: 'Nem Lớn', price: 40000 },
  { item_id: 'thit_them', item_name: 'Thịt Thêm', price: 35000 },
  { item_id: 'tac', item_name: 'Tắc', price: 15000 },
  { item_id: 'chanh', item_name: 'Chanh', price: 15000 },
  { item_id: 'pepsi', item_name: 'Pepsi', price: 15000 },
  { item_id: 'sting', item_name: 'Sting', price: 15000 },
  { item_id: '7up', item_name: '7Up', price: 15000 },
  { item_id: 'suoi', item_name: 'Suối', price: 10000 }
];

let orderIdCounter = 1000;

// API Routes

// GET menu
app.get('/api/menu', (req, res) => {
  res.json(menu);
});

// GET active orders
app.get('/api/orders/active', (req, res) => {
  const activeOrders = dataStore.getActiveOrders();
  res.json(activeOrders);
});

// GET served orders
app.get('/api/orders/served', (req, res) => {
  const servedOrders = dataStore.getServedOrders();
  res.json(servedOrders);
});

// GET order by table
app.get('/api/orders/table/:table', (req, res) => {
  const table = decodeURIComponent(req.params.table);
  const activeOrder = dataStore.getActiveOrders().find(o => o.table === table);
  if (!activeOrder) {
    return res.status(404).json({ error: 'No active order for this table' });
  }
  res.json(activeOrder);
});

// POST new order
app.post('/api/orders', async (req, res) => {
  const { table, note, items, order_total } = req.body;

  const order = {
    order_id: 'ORD' + (++orderIdCounter),
    table,
    note: note || '',
    items,
    order_total,
    status: 'active',
    created_timestamp: new Date().toISOString()
  };

  await dataStore.upsertOrder(order);

  // Notify all clients
  io.emit('new_order', order);
  io.emit('orders_update', { orders: dataStore.getActiveOrders() });

  res.json(order);
});

// PUT update existing order in place
app.put('/api/orders/:orderId', async (req, res) => {
  const orderId = req.params.orderId;
  const { note, items, order_total } = req.body;

  const order = await dataStore.updateOrder(orderId, { note, items, order_total });

  if (!order) {
    return res.status(404).json({ error: 'Order not found' });
  }

  // Notify all clients
  io.emit('order_updated', order);
  io.emit('orders_update', { orders: dataStore.getActiveOrders() });

  res.json(order);
});

// POST serve order
app.post('/api/orders/:orderId/serve', async (req, res) => {
  const orderId = req.params.orderId;

  const order = await dataStore.updateOrderStatus(orderId, 'served', 'served_timestamp');

  if (!order) {
    return res.status(404).json({ error: 'Order not found' });
  }

  io.emit('order_served', order);
  io.emit('order_served_update', { order_id: orderId });

  res.json(order);
});

// POST mark order as paid
app.post('/api/orders/:orderId/paid', async (req, res) => {
  const orderId = req.params.orderId;

  const order = await dataStore.markOrderPaid(orderId);

  if (!order) {
    return res.status(404).json({ error: 'Order not found' });
  }

  io.emit('order_paid', { order_id: orderId });

  // Clean up paid orders older than 1 hour from memory (not from disk)
  dataStore.cleanupOldPaidOrders();

  res.json(order);
});

// GET all timestamps
app.get('/api/timestamps', (req, res) => {
  const orders = dataStore.getOrders();
  const timestamps = [];

  orders.forEach(order => {
    // Created timestamp
    if (order.created_timestamp) {
      timestamps.push({
        order_id: order.order_id,
        table: order.table,
        status: 'ordered',
        timestamp: order.created_timestamp
      });
    }

    // Served timestamp
    if (order.served_timestamp) {
      timestamps.push({
        order_id: order.order_id,
        table: order.table,
        status: 'served',
        timestamp: order.served_timestamp
      });
    }

    // Paid timestamp
    if (order.paid_timestamp) {
      timestamps.push({
        order_id: order.order_id,
        table: order.table,
        status: 'paid',
        timestamp: order.paid_timestamp
      });
    }
  });

  res.json(timestamps);
});

// GET today's summary
app.get('/api/summary/today', (req, res) => {
  const today = new Date().toISOString().split('T')[0];
  const summary = dataStore.getDailySummary(today);

  res.json({
    total_orders: summary.total_orders || 0,
    total_money: summary.total_money || 0,
    dine_in_orders: summary.dine_in_orders || 0,
    takeaway_orders: summary.takeaway_orders || 0,
    goka_orders: summary.goka_orders || 0
  });
});

// GET all orders (for Excel export)
app.get('/api/orders/all', (req, res) => {
  res.json(dataStore.getOrders());
});

// GET export as Excel with 2 sheets
app.get('/api/export/excel', async (req, res) => {
  try {
    const today = new Date();
    const dateStr = today.toISOString().split('T')[0];

    // Create a new workbook
    const workbook = new ExcelJS.Workbook();
    workbook.creator = 'Bun Cha POS';
    workbook.created = new Date();

    // ============================================
    // SHEET 1: ORDERS
    // ============================================
    const ordersSheet = workbook.addWorksheet('Orders');

    // Build columns: ORDER ID, Table, each menu item, Total, Created, Served, Paid, Updated, Note
    const orderColumns = [
      { header: 'ORDER ID', key: 'order_id', width: 15 },
      { header: 'Table', key: 'table', width: 15 }
    ];

    // Add menu item columns
    menu.forEach(item => {
      orderColumns.push({ header: item.item_name, key: item.item_id, width: 12 });
    });

    // Add remaining columns
    orderColumns.push(
      { header: 'Total', key: 'total', width: 12 },
      { header: 'Created', key: 'created', width: 18 },
      { header: 'Served', key: 'served', width: 18 },
      { header: 'Paid', key: 'paid', width: 18 },
      { header: 'Updated', key: 'updated', width: 18 },
      { header: 'Note', key: 'note', width: 30 }
    );

    ordersSheet.columns = orderColumns;

    // Style header row
    ordersSheet.getRow(1).font = { bold: true, color: { argb: 'FFFFFFFF' } };
    ordersSheet.getRow(1).fill = { type: 'pattern', pattern: 'solid', fgColor: { argb: 'FF1F4E78' } };

    // Get all orders
    const allOrders = dataStore.getOrders();

    // Add order data (one row per order)
    allOrders.forEach(order => {
      const rowData = {
        order_id: order.order_id,
        table: order.table,
        total: order.order_total,
        created: formatDateTime(order.created_timestamp),
        served: formatDateTime(order.served_timestamp),
        paid: formatDateTime(order.paid_timestamp),
        updated: formatDateTime(order.updated_timestamp),
        note: order.note || ''
      };

      // Add item quantities (0 if not in order)
      menu.forEach(item => {
        const orderItem = order.items && order.items.find(i => i.item_id === item.item_id);
        rowData[item.item_id] = orderItem ? orderItem.qty : 0;
      });

      ordersSheet.addRow(rowData);
    });

    // ============================================
    // SHEET 2: DAILY SUMMARY
    // ============================================
    const summarySheet = workbook.addWorksheet('Daily Summary');

    // Get all summaries
    const summaries = dataStore.getSummaries();
    const sortedDates = Object.keys(summaries).sort();

    // Build headers dynamically with all menu items
    const summaryColumns = [
      { header: 'Date', key: 'date', width: 15 },
      { header: 'Total Orders', key: 'total_orders', width: 15 },
      { header: 'Dine In', key: 'dine_in', width: 12 },
      { header: 'Takeaway', key: 'takeaway', width: 12 },
      { header: 'Goka (Delivery)', key: 'goka', width: 18 }
    ];

    // Add menu item columns
    menu.forEach(item => {
      summaryColumns.push({ header: item.item_name, key: item.item_id, width: 15 });
    });

    summaryColumns.push({ header: 'Total Money', key: 'total_money', width: 18 });

    summarySheet.columns = summaryColumns;

    // Style header row
    summarySheet.getRow(1).font = { bold: true, color: { argb: 'FFFFFFFF' } };
    summarySheet.getRow(1).fill = { type: 'pattern', pattern: 'solid', fgColor: { argb: 'FF1F4E78' } };

    // Add summary data
    sortedDates.forEach(dateStr => {
      const summary = summaries[dateStr];
      const rowData = {
        date: formatDate(dateStr),
        total_orders: summary.total_orders || 0,
        dine_in: summary.dine_in_orders || 0,
        takeaway: summary.takeaway_orders || 0,
        goka: summary.goka_orders || 0
      };

      // Add item quantities
      menu.forEach(item => {
        rowData[item.item_id] = summary.items_sold && summary.items_sold[item.item_id]
          ? summary.items_sold[item.item_id].quantity
          : 0;
      });

      rowData.total_money = (summary.total_money || 0).toLocaleString('vi-VN') + ' ₫';

      summarySheet.addRow(rowData);
    });

    // Generate Excel buffer
    const buffer = await workbook.xlsx.writeBuffer();

    // Set headers for download
    res.setHeader('Content-Type', 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');
    res.setHeader('Content-Disposition', `attachment; filename="bun-cha-pos-${dateStr}.xlsx"`);
    res.send(buffer);

  } catch (err) {
    console.error('Error generating Excel:', err);
    res.status(500).json({ error: 'Failed to generate Excel file' });
  }
});

// Helper function to format date/time for Excel
function formatDateTime(isoString) {
  if (!isoString) return '';
  const date = new Date(isoString);
  return date.toLocaleString('vi-VN');
}

// Helper function to format date for Excel
function formatDate(dateStr) {
  const date = new Date(dateStr);
  return date.toLocaleDateString('vi-VN');
}

// Add error handling middleware
app.use((err, req, res, next) => {
  console.error('Error:', err);
  res.status(500).json({ error: err.message });
});
app.use(express.static(path.join(__dirname, 'frontend')));

// Socket.IO connection handling
io.on('connection', (socket) => {
  console.log('Client connected:', socket.id);

  // Send current active orders on connection
  socket.emit('orders_update', {
    orders: dataStore.getActiveOrders()
  });

  socket.on('disconnect', () => {
    console.log('Client disconnected:', socket.id);
  });
});

// Start server
const PORT = process.env.PORT || 3003;

async function startServer() {
  try {
    // Initialize data store (load from disk, check archives)
    await dataStore.init();

    httpServer.listen(PORT, () => {
      console.log(`Bun Cha POS Server running on http://localhost:${PORT}`);
    });
  } catch (err) {
    console.error('Failed to start server:', err);
    process.exit(1);
  }
}

startServer();

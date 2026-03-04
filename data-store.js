const fs = require('fs').promises;
const path = require('path');

// Data file paths
const DATA_DIR = path.join(__dirname, 'data');
const ORDERS_FILE = path.join(DATA_DIR, 'orders.json');
const SUMMARIES_FILE = path.join(DATA_DIR, 'summaries.json');
const ARCHIVE_DIR = path.join(DATA_DIR, 'archive');

// In-memory cache
let ordersCache = [];
let summariesCache = {};

// Ensure data directory exists
async function ensureDataDir() {
  try {
    await fs.mkdir(DATA_DIR, { recursive: true });
    await fs.mkdir(ARCHIVE_DIR, { recursive: true });
  } catch (err) {
    console.error('Error creating data directory:', err);
  }
}

// Load orders from file
async function loadOrders() {
  try {
    const data = await fs.readFile(ORDERS_FILE, 'utf8');
    ordersCache = JSON.parse(data);
    return ordersCache;
  } catch (err) {
    if (err.code === 'ENOENT') {
      ordersCache = [];
      return ordersCache;
    }
    console.error('Error loading orders:', err);
    ordersCache = [];
    return ordersCache;
  }
}

// Save orders to file
async function saveOrders() {
  try {
    await ensureDataDir();
    await fs.writeFile(ORDERS_FILE, JSON.stringify(ordersCache, null, 2));
  } catch (err) {
    console.error('Error saving orders:', err);
  }
}

// Load summaries from file
async function loadSummaries() {
  try {
    const data = await fs.readFile(SUMMARIES_FILE, 'utf8');
    summariesCache = JSON.parse(data);
    return summariesCache;
  } catch (err) {
    if (err.code === 'ENOENT') {
      summariesCache = {};
      return summariesCache;
    }
    console.error('Error loading summaries:', err);
    summariesCache = {};
    return summariesCache;
  }
}

// Save summaries to file
async function saveSummaries() {
  try {
    await ensureDataDir();
    await fs.writeFile(SUMMARIES_FILE, JSON.stringify(summariesCache, null, 2));
  } catch (err) {
    console.error('Error saving summaries:', err);
  }
}

// Get orders (from cache)
function getOrders() {
  return ordersCache;
}

// Add or update order
async function upsertOrder(order) {
  const existingIndex = ordersCache.findIndex(o => o.order_id === order.order_id);

  if (existingIndex >= 0) {
    // Update existing order
    ordersCache[existingIndex] = { ...ordersCache[existingIndex], ...order };
  } else {
    // Add new order
    ordersCache.push(order);
  }

  await saveOrders();
  // Only update summary for new orders or if items changed
  const isNewOrder = existingIndex < 0;
  await updateDailySummary(order, isNewOrder);

  return ordersCache[existingIndex >= 0 ? existingIndex : ordersCache.length - 1];
}

// Get order by ID
function getOrderById(orderId) {
  return ordersCache.find(o => o.order_id === orderId);
}

// Get active orders
function getActiveOrders() {
  return ordersCache.filter(o => o.status === 'active');
}

// Get served orders
function getServedOrders() {
  return ordersCache.filter(o => o.status === 'served');
}

// Update order status
async function updateOrderStatus(orderId, status, timestampField = null) {
  const order = ordersCache.find(o => o.order_id === orderId);
  if (!order) return null;

  order.status = status;
  if (timestampField) {
    order[timestampField] = new Date().toISOString();
  }

  await saveOrders();
  // Don't update summary on status change (only items/count matters)

  return order;
}

// Update order in place (for modifying items/note)
async function updateOrder(orderId, updates) {
  const order = ordersCache.find(o => o.order_id === orderId);
  if (!order) return null;

  Object.assign(order, updates);
  order.updated_timestamp = new Date().toISOString();

  await saveOrders();
  // Update summary if items changed
  await updateDailySummary(order, false);

  return order;
}

// Get or create daily summary
function getDailySummary(dateStr) {
  if (!summariesCache[dateStr]) {
    summariesCache[dateStr] = {
      date: dateStr,
      total_orders: 0,
      dine_in_orders: 0,
      takeaway_orders: 0,
      goka_orders: 0,
      total_money: 0,
      items_sold: {}
    };
  }
  return summariesCache[dateStr];
}

// Update daily summary based on order
async function updateDailySummary(order, isNewOrder = false) {
  const createdDate = new Date(order.created_timestamp);
  const dateStr = createdDate.toISOString().split('T')[0];

  const summary = getDailySummary(dateStr);

  // Only count order type for new orders
  if (isNewOrder) {
    if (order.table === 'Goka (Delivery)') {
      summary.goka_orders = (summary.goka_orders || 0) + 1;
    } else if (order.table === 'Takeaway') {
      summary.takeaway_orders = (summary.takeaway_orders || 0) + 1;
    } else {
      summary.dine_in_orders = (summary.dine_in_orders || 0) + 1;
    }
  }

  // Always update item counts (rebuild from scratch for accuracy)
  // Reset items_sold to 0 and rebuild
  summary.items_sold = summary.items_sold || {};

  // Get all orders for this date and recount items
  const daysOrders = ordersCache.filter(o => {
    const orderDate = new Date(o.created_timestamp);
    return orderDate.toISOString().split('T')[0] === dateStr;
  });

  // Reset all quantities
  Object.keys(summary.items_sold).forEach(itemId => {
    summary.items_sold[itemId].quantity = 0;
  });

  // Recount items from all orders
  daysOrders.forEach(o => {
    if (o.items) {
      o.items.forEach(item => {
        if (!summary.items_sold[item.item_id]) {
          summary.items_sold[item.item_id] = {
            item_id: item.item_id,
            item_name: item.item_name,
            quantity: 0
          };
        }
        summary.items_sold[item.item_id].quantity += item.qty;
      });
    }
  });

  await saveSummaries();
}

// Mark order as paid and finalize summary
async function markOrderPaid(orderId) {
  const order = ordersCache.find(o => o.order_id === orderId);
  if (!order) return null;

  order.status = 'paid';
  order.paid_timestamp = new Date().toISOString();

  const createdDate = new Date(order.created_timestamp);
  const dateStr = createdDate.toISOString().split('T')[0];

  const summary = getDailySummary(dateStr);
  summary.total_orders += 1;
  summary.total_money += order.order_total || 0;

  await saveOrders();
  await saveSummaries();

  return order;
}

// Archive old data (older than 1 month)
async function archiveOldData() {
  const now = new Date();
  const oneMonthAgo = new Date(now.getFullYear(), now.getMonth() - 1, now.getDate());

  // Find orders older than 1 month
  const ordersToArchive = ordersCache.filter(order => {
    const createdDate = new Date(order.created_timestamp);
    return createdDate < oneMonthAgo && order.status === 'paid';
  });

  if (ordersToArchive.length === 0) {
    return { archived: 0, message: 'No old orders to archive' };
  }

  // Create archive file
  const archiveDate = now.toISOString().split('T')[0];
  const archiveFile = path.join(ARCHIVE_DIR, `archive-${archiveDate}.json`);

  // Group by date for archiving
  const archiveData = {};
  ordersToArchive.forEach(order => {
    const dateStr = new Date(order.created_timestamp).toISOString().split('T')[0];
    if (!archiveData[dateStr]) {
      archiveData[dateStr] = [];
    }
    archiveData[dateStr].push(order);
  });

  await fs.writeFile(archiveFile, JSON.stringify(archiveData, null, 2));

  // Remove archived orders from cache
  const archivedIds = new Set(ordersToArchive.map(o => o.order_id));
  ordersCache = ordersCache.filter(o => !archivedIds.has(o.order_id));

  await saveOrders();

  // Also archive summaries
  const summariesToArchive = {};
  const summaryDatesToArchive = [];

  Object.keys(summariesCache).forEach(dateStr => {
    const summaryDate = new Date(dateStr);
    if (summaryDate < oneMonthAgo) {
      summariesToArchive[dateStr] = summariesCache[dateStr];
      summaryDatesToArchive.push(dateStr);
    }
  });

  if (summaryDatesToArchive.length > 0) {
    const summaryArchiveFile = path.join(ARCHIVE_DIR, `summaries-${archiveDate}.json`);
    await fs.writeFile(summaryArchiveFile, JSON.stringify(summariesToArchive, null, 2));

    // Remove archived summaries from cache
    summaryDatesToArchive.forEach(dateStr => {
      delete summariesCache[dateStr];
    });

    await saveSummaries();
  }

  return {
    archived: ordersToArchive.length,
    message: `Archived ${ordersToArchive.length} orders from ${summaryDatesToArchive.length} days`
  };
}

// Clean up paid orders older than 1 hour (for memory management)
function cleanupOldPaidOrders() {
  const oneHourAgo = new Date(Date.now() - 60 * 60 * 1000);
  ordersCache = ordersCache.filter(o => {
    if (o.status !== 'paid') return true;
    const paidTime = new Date(o.paid_timestamp);
    return paidTime > oneHourAgo;
  });
}

// Get all summaries
function getSummaries() {
  return summariesCache;
}

// Initialize data store
async function init() {
  await ensureDataDir();
  await loadOrders();
  await loadSummaries();

  // Check for archival on startup (once daily)
  const now = new Date();
  const lastArchiveCheck = path.join(DATA_DIR, '.last-archive');
  try {
    const lastCheck = await fs.readFile(lastArchiveCheck, 'utf8');
    const lastCheckDate = new Date(lastCheck);
    const daysSinceCheck = Math.floor((now - lastCheckDate) / (1000 * 60 * 60 * 24));

    if (daysSinceCheck >= 1) {
      const result = await archiveOldData();
      console.log('Archive check:', result.message);
      await fs.writeFile(lastArchiveCheck, now.toISOString());
    }
  } catch (err) {
    // First run or error
    await fs.writeFile(lastArchiveCheck, now.toISOString());
  }

  console.log(`Data store loaded: ${ordersCache.length} orders, ${Object.keys(summariesCache).length} days of summaries`);
}

module.exports = {
  init,
  getOrders,
  getActiveOrders,
  getServedOrders,
  getOrderById,
  upsertOrder,
  updateOrderStatus,
  updateOrder,
  markOrderPaid,
  getSummaries,
  getDailySummary,
  archiveOldData,
  cleanupOldPaidOrders
};

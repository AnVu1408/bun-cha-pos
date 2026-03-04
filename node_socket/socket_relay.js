const express = require('express');
const { createServer } = require('http');
const { Server } = require('socket.io');
const path = require('path');

const app = express();
app.use(express.json());

const httpServer = createServer(app);
const io = new Server(httpServer, {
  cors: { origin: "*" }
});

// Webhook endpoint for R API
// This receives notifications from the R backend and broadcasts them via Socket.IO
app.post('/webhook', (req, res) => {
  const { event, data } = req.body;

  console.log(`[Webhook] Event: ${event}`);

  // Broadcast to all connected clients based on event type
  switch(event) {
    case 'new_order':
      io.emit('new_order', data.order);
      io.emit('orders_update', { orders: data.active_orders });
      break;

    case 'order_updated':
      // When an order is updated (items added), old order is paid, new one created
      io.emit('order_paid', { order_id: data.old_order_id });
      io.emit('new_order', data.new_order);
      io.emit('orders_update', { orders: data.active_orders });
      break;

    case 'order_served':
      io.emit('order_served', data.order);
      io.emit('order_served_update', { order_id: data.order_id });
      break;

    case 'order_paid':
      io.emit('order_paid', { order_id: data.order_id });
      if (data.active_orders) {
        io.emit('orders_update', { orders: data.active_orders });
      }
      break;

    case 'orders_update':
      io.emit('orders_update', { orders: data.orders });
      break;

    default:
      console.log(`[Webhook] Unknown event type: ${event}`);
  }

  res.json({ received: true, event: event });
});

// Health check endpoint
app.get('/health', (req, res) => {
  res.json({
    status: 'ok',
    timestamp: new Date().toISOString(),
    connected_clients: io.engine.clientsCount
  });
});

// Serve frontend static files
app.use(express.static(path.join(__dirname, '../frontend')));

// Socket.IO connection handling
io.on('connection', (socket) => {
  console.log(`[Socket.IO] Client connected: ${socket.id}`);

  // Send current active orders on connection
  // We make a request to the R API to get current state
  fetch('http://localhost:3003/api/orders/active')
    .then(res => res.json())
    .then(orders => {
      socket.emit('orders_update', { orders: orders });
    })
    .catch(err => {
      console.error('[Socket.IO] Failed to fetch initial orders:', err.message);
    });

  socket.on('disconnect', () => {
    console.log(`[Socket.IO] Client disconnected: ${socket.id}`);
  });

  socket.on('error', (err) => {
    console.error(`[Socket.IO] Socket error: ${err.message}`);
  });
});

// Start server
const PORT = process.env.PORT || 3004;
httpServer.listen(PORT, () => {
  console.log('\n========================================');
  console.log('  Bun Cha POS - Socket.IO Relay Server');
  console.log('========================================');
  console.log(`Server running on http://localhost:${PORT}`);
  console.log(`Socket.IO endpoint: http://localhost:${PORT}/socket.io/`);
  console.log(`Webhook endpoint: http://localhost:${PORT}/webhook`);
  console.log(`Frontend served from: http://localhost:${PORT}/`);
  console.log('========================================\n');
});

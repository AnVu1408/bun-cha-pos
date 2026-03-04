# Bun Cha POS - Socket.IO Relay Server

This is a minimal Node.js server that handles real-time updates for the Bun Cha POS system using Socket.IO. It acts as a relay between the R Plumber API and frontend clients.

## Purpose

- Receives webhook notifications from the R Plumber API (port 3003)
- Broadcasts real-time events to connected frontend clients via Socket.IO
- Serves the static frontend files

## Installation

```bash
cd node_socket
npm install
```

## Usage

Start the server:

```bash
npm start
```

The server will run on port 3004 by default.

## Architecture

```
Frontend (HTML/JS)         R Plumber API (Port 3003)
       |                            |
       | Socket.IO                  |
       |<---------------------------+
       |                            |
       | HTTP API                   |
       +--------------------------->|
       |                            |
       +                            |
    Node.js Relay              Excel Storage
    (Port 3004)                 (Monthly Files)
```

## Webhook Events

The relay server accepts POST requests to `/webhook` with the following events:

### `new_order`
Broadcasted when a new order is created.
- Emits: `new_order`, `orders_update`

### `order_updated`
Broadcasted when items are added to an existing order.
- Emits: `order_paid`, `new_order`, `orders_update`

### `order_served`
Broadcasted when an order is marked as served.
- Emits: `order_served`, `order_served_update`

### `order_paid`
Broadcasted when an order is marked as paid.
- Emits: `order_paid`, `orders_update`

## Socket.IO Events

Clients can listen to these events:

- `new_order` - New order created
- `order_served` - Order marked as served
- `order_served_update` - Order served update
- `order_paid` - Order marked as paid
- `orders_update` - Active orders list updated

## API Endpoints

- `POST /webhook` - Webhook endpoint for R API
- `GET /health` - Health check
- `/*` - Static files from `../frontend/`

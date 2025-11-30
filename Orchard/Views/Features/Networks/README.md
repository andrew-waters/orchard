# Networks Feature

This directory contains the SwiftUI views and components for managing container networks in the Orchard app.

## Overview

The Networks feature allows users to:
- View all available container networks
- Create new networks with different modes (NAT, Bridge, Host)
- Delete networks (except the default network)
- View network details including connected containers
- Navigate between networks and containers

## Files

### `ListNetworks.swift`
- Main list view for displaying networks in the sidebar
- Shows network status, mode, and IP address ranges
- Provides context menu for network deletion
- Includes "Add Network" button

### `AddNetwork.swift`
- Modal sheet for creating new networks
- Network name validation
- Subnet specification (optional)
- Label management (key-value pairs)
- Form validation and error handling

### `DetailNetwork.swift`
- Detailed view showing network information
- Lists all containers connected to the network
- Shows network configuration (ID, state, mode, address range, gateway)
- Provides actions for network management

## Network Models

The feature uses these models defined in `Models.swift`:

- `ContainerNetwork`: Main network object with ID, state, config, and status
- `NetworkConfig`: Network configuration including labels (no mode field)
- `NetworkStatus`: Network status with gateway and address information

## Integration

The Networks feature is integrated into the main app through:

1. **TabSelection**: Added `.networks` case with "wifi" icon
2. **ContainerService**: Added network management methods:
   - `loadNetworks()`: Fetch networks from container CLI
   - `createNetwork()`: Create new network
   - `deleteNetwork()`: Remove network
   - `parseNetworksFromJSON()`: Parse CLI output

3. **Main Interface**: Added network bindings and state management
4. **Sidebar**: Integrated network list view
5. **Detail View**: Added network detail view routing

## CLI Integration

The feature integrates with the container CLI using these commands:

- `container network ls --format=json`: List all networks
- `container network create [--label <label>] [--subnet <subnet>] <name>`: Create network
- `container network rm <id>`: Delete network

## Network Configuration

### Labels
- Key-value metadata for networks
- Multiple labels can be added
- Optional but useful for organization and filtering

### Subnet
- Optional subnet specification in CIDR notation (e.g., 192.168.1.0/24)
- If not specified, automatic allocation is used
- Must be valid CIDR format when provided

## Usage

1. Select the "Networks" tab from the sidebar
2. View existing networks with their status, labels, and configuration
3. Click "Add Network" to create a new network with optional subnet and labels
4. Select a network to view details and connected containers
5. Use context menus or detail view to delete networks (except default)

## Example JSON Structure

The CLI returns network data in this format:

```json
[
  {
    "id": "default",
    "state": "running",
    "config": {
      "labels": {},
      "id": "default"
    },
    "status": {
      "gateway": "192.168.65.1",
      "address": "192.168.65.0/24"
    }
  },
  {
    "id": "my-network",
    "state": "running",
    "config": {
      "labels": {
        "environment": "development",
        "team": "backend"
      },
      "id": "my-network"
    },
    "status": {
      "gateway": "192.168.64.1",
      "address": "192.168.64.0/24"
    }
  }
]
```

## Navigation

Networks support deep-linking navigation through the `NavigateToNetwork` notification, allowing other parts of the app to programmatically navigate to specific networks.
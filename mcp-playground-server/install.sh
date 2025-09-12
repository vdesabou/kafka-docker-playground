#!/bin/bash

# Kafka Docker Playground MCP Server Installation Script

set -e

echo "🚀 Installing Kafka Docker Playground MCP Server..."

# Get the current directory
MCP_SERVER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
echo "📍 MCP Server directory: $MCP_SERVER_DIR"

# Install dependencies
echo "📦 Installing dependencies..."
cd "$MCP_SERVER_DIR"
npm install

# Build the project
echo "🔨 Building TypeScript project..."
npm run build

# Create VS Code settings path
VSCODE_SETTINGS_PATH="$HOME/Library/Application Support/Code/User/settings.json"

echo "⚙️  VS Code Configuration"
echo "To enable the MCP server in VS Code, you need to add the following to your settings.json:"
echo ""
echo "File location: $VSCODE_SETTINGS_PATH"
echo ""
cat << EOF
{
  "mcp": {
    "servers": {
      "kafka-playground": {
        "command": "node",
        "args": [
          "$MCP_SERVER_DIR/dist/index.js"
        ],
        "env": {}
      }
    }
  }
}
EOF

echo ""
echo "📋 Next Steps:"
echo "1. Copy the configuration above to your VS Code settings.json"
echo "2. If you don't have a settings.json file, create it at: $VSCODE_SETTINGS_PATH"
echo "3. If you already have settings.json, merge the 'mcp' section with your existing configuration"
echo "4. Restart VS Code"
echo "5. The MCP server will provide intelligent assistance for playground commands"
echo ""
echo "🧪 Testing:"
echo "You can test the server by running: npm start"
echo ""
echo "✅ Installation complete!"
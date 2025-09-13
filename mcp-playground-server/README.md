# MCP Playground Server

This is a Model Context Protocol (MCP) server that provides intelligent command completion and assistance for the Kafka Docker Playground CLI. It integrates with GitHub Copilot to offer contextual help, command suggestions, and debugging assistance for playground commands.

## Features

- **Command Completion**: Auto-complete playground commands with context-aware suggestions
- **Command Help**: Get detailed help for any playground command or subcommand  
- **Command Validation**: Validate playground commands before execution
- **Container Inspection**: List and filter Docker containers related to the playground
- **Interactive Assistance**: Works seamlessly with GitHub Copilot for natural language queries

## Installation

### Prerequisites

- Node.js (version 18 or higher)
- npm or yarn
- Kafka Docker Playground repository

### Setup

1. **Install dependencies:**
   ```bash
   cd mcp-playground-server
   npm install
   ```

2. **Build the server:**
   ```bash
   npm run build
   ```

3. **Configure VS Code MCP Integration:**
   
   Create a `.vscode/mcp.json` file in your workspace root with the following configuration:
   ```json
   {
     "mcpServers": {
       "playground": {
         "command": "node",
         "args": ["./mcp-playground-server/dist/index.js"]
       }
     }
   }
   ```

4. **Optional: VS Code Settings (Alternative Method)**
   
   You can also configure MCP through VS Code settings. Copy the provided `vscode-mcp-settings.json` template and update your VS Code settings accordingly.

## Usage

Once configured, the MCP server will be available through GitHub Copilot. You can ask natural language questions about playground commands:

### Example Queries

- "What playground commands are available for managing connectors?"
- "How do I debug connection issues with a connector?"
- "Show me playground commands for container management"
- "What debug options are available for Java class loading?"
- "How do I restart a specific connector?"

### Direct MCP Tools

The server exposes several tools that GitHub Copilot can use automatically:

- `playground_command_help`: Get detailed help for any command
- `playground_command_suggest`: Get command suggestions and completions  
- `playground_command_validate`: Validate command syntax
- `playground_list_containers`: List available Docker containers

### Environment Variables

This MCP server runs without requiring any environment variables since it uses relative paths within the repository.

## Development

### Building

```bash
npm run build
```

### Running in Development

```bash
npm run dev
```

### Testing

The server can be tested by running it directly:

```bash
npm run build
node dist/index.js
```

## Configuration Details

The server automatically locates the playground's `scripts/cli/bashly.yml` file using relative paths within the repository structure.

## Architecture

- **MCP Protocol**: Implements the Model Context Protocol for seamless integration with AI assistants
- **Command Parser**: Parses the Bashly YAML configuration to understand available commands
- **Suggestion Engine**: Provides intelligent command completion based on context
- **Docker Integration**: Inspects running containers to provide relevant suggestions

## File Structure

```
mcp-playground-server/
├── src/
│   ├── index.ts          # Main MCP server implementation
│   ├── parser.ts         # Bashly YAML parser for command structure
│   ├── suggester.ts      # Command suggestion engine
│   └── docker.ts         # Docker container inspection
├── package.json          # Dependencies and scripts
├── tsconfig.json         # TypeScript configuration
├── .gitignore            # Git ignore patterns
└── README.md             # This file
```

## Docker Deployment

For containerized environments and docker model runners, you can use the Docker version:

### Quick Start

```bash
# Build the Docker image
./docker-build.sh build

# Run with Docker
docker run --rm -i \
  -v /var/run/docker.sock:/var/run/docker.sock:ro \
  mcp-playground-server:1.0.0 \
  node dist/index.js
```

### Configuration

The `bashly.yml` configuration is embedded directly in the Docker image, requiring only Docker socket access for container inspection.

For detailed Docker documentation, see [README-DOCKER.md](README-DOCKER.md).

## Advanced Configuration

### Manual MCP Integration

For manual integration with other MCP-compatible clients:

1. Build and start the server: `npm run build && node dist/index.js`
2. Connect your MCP client to the server endpoint
3. The server will automatically provide command completion and help functionality

## Troubleshooting

### Common Issues

1. **Server won't start**: Ensure the server is built (`npm run build`) and run from the correct directory
2. **Commands not found**: Verify that `bashly.yml` exists at `scripts/cli/src/bashly.yml` relative to the repository root
3. **No completion suggestions**: Check that the server is running and properly configured in VS Code

### Debug Mode

Run the server with debug logging:

```bash
DEBUG=* node dist/index.js
```

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Run tests: `npm test`
5. Submit a pull request

## License

This project is licensed under the MIT License.
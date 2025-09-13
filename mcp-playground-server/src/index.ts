import { Server } from "@modelcontextprotocol/sdk/server/index.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import {
  CallToolRequestSchema,
  ListToolsRequestSchema,
  McpError,
  ErrorCode,
  CallToolRequest,
} from "@modelcontextprotocol/sdk/types.js";
import { PlaygroundCliParser } from "./parser.js";
import { CommandSuggester } from "./suggester.js";

export class PlaygroundMcpServer {
  private server: Server;
  private parser: PlaygroundCliParser;
  private suggester: CommandSuggester;

  constructor() {
    this.server = new Server(
      {
        name: "mcp-playground-server",
        version: "1.0.0",
      },
      {
        capabilities: {
          tools: {},
        },
      }
    );

    this.parser = new PlaygroundCliParser();
    this.suggester = new CommandSuggester();

    this.setupToolHandlers();
  }

  private setupToolHandlers(): void {
    this.server.setRequestHandler(ListToolsRequestSchema, async () => {
      return {
        tools: [
          {
            name: "playground_command_suggest",
            description: "Get command suggestions and completions for the Kafka Docker Playground CLI",
            inputSchema: {
              type: "object",
              properties: {
                partial_command: {
                  type: "string",
                  description: "Partial playground command to complete",
                },
                context: {
                  type: "string",
                  description: "Additional context about what you're trying to do",
                },
              },
              required: ["partial_command"],
            },
          },
          {
            name: "playground_command_validate",
            description: "Validate a complete playground command and suggest corrections",
            inputSchema: {
              type: "object",
              properties: {
                command: {
                  type: "string",
                  description: "Complete playground command to validate",
                },
              },
              required: ["command"],
            },
          },
          {
            name: "playground_command_help",
            description: "Get detailed help for playground commands",
            inputSchema: {
              type: "object",
              properties: {
                command: {
                  type: "string",
                  description: "Command to get help for (e.g., 'connector restart', 'container logs')",
                },
              },
              required: ["command"],
            },
          },
        ],
      };
    });

    this.server.setRequestHandler(CallToolRequestSchema, async (request: CallToolRequest) => {
      const { name, arguments: args } = request.params;

      try {
        switch (name) {
          case "playground_command_suggest":
            return await this.handleCommandSuggest(args);
          
          case "playground_command_validate":
            return await this.handleCommandValidate(args);
          
          case "playground_command_help":
            return await this.handleCommandHelp(args);

          default:
            throw new McpError(
              ErrorCode.MethodNotFound,
              `Unknown tool: ${name}`
            );
        }
      } catch (error) {
        throw new McpError(
          ErrorCode.InternalError,
          `Error executing tool ${name}: ${error}`
        );
      }
    });
  }

  private async handleCommandSuggest(args: any) {
    const { partial_command, context } = args;
    
    const suggestions = await this.suggester.getSuggestions(partial_command, context);
    
    return {
      content: [
        {
          type: "text",
          text: JSON.stringify({
            suggestions,
            command_structure: this.parser.getCommandStructure(partial_command),
          }, null, 2),
        },
      ],
    };
  }

  private async handleCommandValidate(args: any) {
    const { command } = args;
    
    const validation = await this.suggester.validateCommand(command);
    
    return {
      content: [
        {
          type: "text",
          text: JSON.stringify(validation, null, 2),
        },
      ],
    };
  }

  private async handleCommandHelp(args: any) {
    const { command } = args;
    
    const help = this.parser.getCommandHelp(command);
    
    return {
      content: [
        {
          type: "text",
          text: JSON.stringify(help, null, 2),
        },
      ],
    };
  }

  async run(): Promise<void> {
    const transport = new StdioServerTransport();
    await this.server.connect(transport);
    console.error("Playground MCP server running on stdio");
  }
}

async function main() {
  const server = new PlaygroundMcpServer();
  await server.run();
}

if (import.meta.url === `file://${process.argv[1]}`) {
  main().catch((error) => {
    console.error("Server failed:", error);
    process.exit(1);
  });
}
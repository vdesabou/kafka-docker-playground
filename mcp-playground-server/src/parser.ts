import * as yaml from 'yaml';
import * as fs from 'fs';
import * as path from 'path';
import { fileURLToPath } from 'url';
import { dirname } from 'path';

export interface PlaygroundCommand {
  name: string;
  description?: string;
  options?: PlaygroundOption[];
  subcommands?: PlaygroundCommand[];
  examples?: string[];
}

export interface PlaygroundOption {
  name: string;
  description?: string;
  type?: string;
  required?: boolean;
  repeatable?: boolean;
  values?: string[];
}

export class PlaygroundCliParser {
  private commands: PlaygroundCommand[] = [];
  private yamlPath: string;

  constructor() {
    // Priority order for bashly.yml location:
    // 1. Environment variable (for custom mount)
    // 2. Embedded file in Docker image
    // 3. Relative path (for local development)
    if (process.env.BASHLY_YML_PATH && fs.existsSync(process.env.BASHLY_YML_PATH)) {
      this.yamlPath = process.env.BASHLY_YML_PATH;
    } else if (fs.existsSync('/app/bashly.yml')) {
      // Embedded in Docker image
      this.yamlPath = '/app/bashly.yml';
    } else {
      // Use relative path since MCP server is part of the repo
      // Get the directory of this file in ES modules
      const __filename = fileURLToPath(import.meta.url);
      const __dirname = dirname(__filename);
      this.yamlPath = path.join(__dirname, '..', '..', 'scripts', 'cli', 'src', 'bashly.yml');
    }
    this.loadCommands();
  }

  private loadCommands(): void {
    const isDebug = process.env.NODE_ENV !== 'production';
    
    try {
      if (isDebug) console.error(`Looking for bashly.yml at: ${this.yamlPath}`);
      
      if (fs.existsSync(this.yamlPath)) {
        if (isDebug) console.error(`Loading bashly.yml from: ${this.yamlPath}`);
        const yamlContent = fs.readFileSync(this.yamlPath, 'utf8');
        const parsed = yaml.parse(yamlContent);
        this.commands = this.parseYamlCommands(parsed);
        if (isDebug) console.error(`Successfully loaded ${this.commands.length} commands from bashly.yml`);
      } else {
        console.error(`bashly.yml not found at ${this.yamlPath}`);
        if (isDebug) console.error('Using default command structure');
        this.commands = this.getDefaultCommands();
      }
    } catch (error) {
      console.error('Error loading bashly.yml:', error);
      if (isDebug) console.error('Falling back to default command structure');
      this.commands = this.getDefaultCommands();
    }
  }

  private parseYamlCommands(yamlData: any): PlaygroundCommand[] {
    // Parse the bashly.yml structure to extract commands
    const commands: PlaygroundCommand[] = [];
    
    if (yamlData.commands) {
      for (const commandData of yamlData.commands) {
        if (commandData.name && !commandData.private) {
          commands.push(this.parseCommand(commandData.name, commandData));
        }
      }
    }
    
    return commands;
  }

  private parseCommand(name: string, data: any): PlaygroundCommand {
    const command: PlaygroundCommand = {
      name,
      description: data.help || data.description,
      options: [],
      subcommands: [],
      examples: data.examples || []
    };

    // Parse flags as options
    if (data.flags) {
      for (const flagData of data.flags) {
        command.options!.push(this.parseOption(flagData.long?.replace('--', '') || flagData.short?.replace('-', ''), flagData));
      }
    }

    // Parse args as options
    if (data.args) {
      for (const argData of data.args) {
        command.options!.push({
          name: argData.name,
          description: argData.help,
          type: 'string',
          required: argData.required || false,
          repeatable: false
        });
      }
    }

    // Parse subcommands
    if (data.commands) {
      for (const subcommandData of data.commands) {
        if (subcommandData.name && !subcommandData.private) {
          command.subcommands!.push(this.parseCommand(subcommandData.name, subcommandData));
        }
      }
    }

    return command;
  }

  private parseOption(name: string, data: any): PlaygroundOption {
    return {
      name,
      description: data.help || data.description,
      type: data.arg || 'flag',
      required: data.required || false,
      repeatable: false,
      values: data.allowed || data.completions
    };
  }

  private getDefaultCommands(): PlaygroundCommand[] {
    // Fallback commands based on the bashly.yml structure we've seen
    return [
      {
        name: 'connector',
        description: 'Manage Kafka connectors',
        subcommands: [
          {
            name: 'restart',
            description: 'Restart a connector',
            options: [
              { name: 'task-id', description: 'Task ID to restart', type: 'string' },
              { name: 'container', description: 'Container name', type: 'string', repeatable: true }
            ]
          },
          {
            name: 'status',
            description: 'Get connector status',
            options: [
              { name: 'container', description: 'Container name', type: 'string', repeatable: true }
            ]
          }
        ]
      },
      {
        name: 'container',
        description: 'Manage Docker containers',
        subcommands: [
          {
            name: 'logs',
            description: 'View container logs',
            options: [
              { name: 'container', description: 'Container name', type: 'string', repeatable: true },
              { name: 'tail', description: 'Number of lines to tail', type: 'integer' }
            ]
          },
          {
            name: 'kill',
            description: 'Kill containers',
            options: [
              { name: 'container', description: 'Container name', type: 'string', repeatable: true }
            ]
          }
        ]
      },
      {
        name: 'debug',
        description: 'Debug tools',
        subcommands: [
          {
            name: 'block-traffic',
            description: 'Block network traffic',
            options: [
              { name: 'container', description: 'Container name', type: 'string', repeatable: true }
            ]
          },
          {
            name: 'set-environment-variables',
            description: 'Set environment variables',
            options: [
              { name: 'container', description: 'Container name', type: 'string', repeatable: true }
            ]
          }
        ]
      }
    ];
  }

  public getCommands(): PlaygroundCommand[] {
    return this.commands;
  }

  public findCommand(commandPath: string[]): PlaygroundCommand | null {
    let current = this.commands;
    let command: PlaygroundCommand | null = null;

    for (const part of commandPath) {
      command = current.find(cmd => cmd.name === part) || null;
      if (!command) return null;
      current = command.subcommands || [];
    }

    return command;
  }

  public getCommandStructure(partialCommand: string): any {
    const parts = partialCommand.trim().split(' ').filter(p => p.length > 0);
    
    if (parts.length === 0) {
      return {
        available_commands: this.commands.map(cmd => ({
          name: cmd.name,
          description: cmd.description
        }))
      };
    }

    // Remove 'playground' if it's the first part
    if (parts[0] === 'playground') {
      parts.shift();
    }

    const command = this.findCommand(parts);
    
    if (command) {
      return {
        command: command.name,
        description: command.description,
        options: command.options || [],
        subcommands: command.subcommands?.map(sub => ({
          name: sub.name,
          description: sub.description
        })) || [],
        examples: command.examples || []
      };
    }

    // Try to find partial matches
    const parentPath = parts.slice(0, -1);
    const parent = parentPath.length > 0 ? this.findCommand(parentPath) : null;
    const lastPart = parts[parts.length - 1];

    if (parent && parent.subcommands) {
      const matches = parent.subcommands.filter(cmd => 
        cmd.name.startsWith(lastPart)
      );
      
      return {
        parent_command: parent.name,
        partial_match: lastPart,
        possible_completions: matches.map(cmd => ({
          name: cmd.name,
          description: cmd.description
        }))
      };
    }

    return {
      error: 'Command not found',
      partial_command: partialCommand
    };
  }

  public getCommandHelp(commandString: string): any {
    const parts = commandString.trim().split(' ').filter(p => p.length > 0);
    
    // Remove 'playground' if it's the first part
    if (parts[0] === 'playground') {
      parts.shift();
    }

    const command = this.findCommand(parts);
    
    if (command) {
      return {
        command: parts.join(' '),
        description: command.description,
        options: command.options || [],
        subcommands: command.subcommands?.map(sub => ({
          name: sub.name,
          description: sub.description,
          options: sub.options || []
        })) || [],
        examples: command.examples || [],
        usage: this.generateUsage(command, parts.join(' '))
      };
    }

    return {
      error: 'Command not found',
      command: commandString
    };
  }

  private generateUsage(command: PlaygroundCommand, commandPath: string): string {
    let usage = `playground ${commandPath}`;
    
    if (command.options && command.options.length > 0) {
      const requiredOptions = command.options.filter(opt => opt.required);
      const optionalOptions = command.options.filter(opt => !opt.required);
      
      requiredOptions.forEach(opt => {
        usage += ` --${opt.name} <${opt.type || 'value'}>`;
      });
      
      if (optionalOptions.length > 0) {
        usage += ' [OPTIONS]';
      }
    }

    if (command.subcommands && command.subcommands.length > 0) {
      usage += ' <SUBCOMMAND>';
    }

    return usage;
  }
}
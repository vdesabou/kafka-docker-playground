import { PlaygroundCliParser, PlaygroundCommand, PlaygroundOption } from './parser.js';

export interface CommandSuggestion {
  completion: string;
  description: string;
  type: 'command' | 'option' | 'value';
  score: number;
}

export interface ValidationResult {
  valid: boolean;
  errors: string[];
  warnings: string[];
  suggestions: string[];
}

export class CommandSuggester {
  private parser: PlaygroundCliParser;

  constructor() {
    this.parser = new PlaygroundCliParser();
  }

  async getSuggestions(partialCommand: string, context?: string): Promise<CommandSuggestion[]> {
    const suggestions: CommandSuggestion[] = [];
    const parts = partialCommand.trim().split(' ').filter(p => p.length > 0);
    
    // Remove 'playground' if it's the first part
    if (parts.length > 0 && parts[0] === 'playground') {
      parts.shift();
    }

    if (parts.length === 0) {
      // Suggest top-level commands
      const commands = this.parser.getCommands();
      commands.forEach(cmd => {
        suggestions.push({
          completion: `playground ${cmd.name}`,
          description: cmd.description || '',
          type: 'command',
          score: 1.0
        });
      });
      return suggestions;
    }

    // Check if the last part is incomplete (doesn't start with --)
    const lastPart = parts[parts.length - 1];
    const isOption = lastPart.startsWith('--');
    
    if (isOption) {
      return this.getOptionSuggestions(parts);
    } else {
      return this.getCommandSuggestions(parts, context);
    }
  }

  private getCommandSuggestions(parts: string[], context?: string): CommandSuggestion[] {
    const suggestions: CommandSuggestion[] = [];
    const lastPart = parts[parts.length - 1];
    const parentParts = parts.slice(0, -1);
    
    // Find parent command
    const parentCommand = parentParts.length > 0 ? this.parser.findCommand(parentParts) : null;
    const searchSpace = parentCommand?.subcommands || this.parser.getCommands();
    
    // Find matching subcommands
    searchSpace.forEach(cmd => {
      if (cmd.name.startsWith(lastPart)) {
        const completion = parentParts.length > 0 
          ? `playground ${parentParts.join(' ')} ${cmd.name}`
          : `playground ${cmd.name}`;
        
        suggestions.push({
          completion,
          description: cmd.description || '',
          type: 'command',
          score: this.calculateScore(cmd.name, lastPart)
        });
      }
    });

    // Also suggest options for the current command path
    const currentCommand = this.parser.findCommand(parts);
    if (currentCommand?.options) {
      currentCommand.options.forEach(option => {
        suggestions.push({
          completion: `playground ${parts.join(' ')} --${option.name}`,
          description: option.description || '',
          type: 'option',
          score: 0.8
        });
      });
    }

    return suggestions.sort((a, b) => b.score - a.score);
  }

  private getOptionSuggestions(parts: string[]): CommandSuggestion[] {
    const suggestions: CommandSuggestion[] = [];
    const lastPart = parts[parts.length - 1];
    const optionName = lastPart.replace(/^--?/, '');
    
    // Find the command these options belong to
    const commandParts = parts.filter(part => !part.startsWith('--'));
    const command = this.parser.findCommand(commandParts);
    
    if (!command?.options) {
      return suggestions;
    }

    // Suggest matching options
    command.options.forEach(option => {
      if (option.name.startsWith(optionName)) {
        const fullCommand = commandParts.join(' ');
        const completion = `playground ${fullCommand} --${option.name}`;
        
        suggestions.push({
          completion,
          description: option.description || '',
          type: 'option',
          score: this.calculateScore(option.name, optionName)
        });

        // If option has predefined values, suggest them too
        if (option.values) {
          option.values.forEach(value => {
            suggestions.push({
              completion: `${completion} ${value}`,
              description: `${option.description} (value: ${value})`,
              type: 'value',
              score: 0.9
            });
          });
        }
      }
    });

    return suggestions.sort((a, b) => b.score - a.score);
  }

  private calculateScore(fullString: string, partial: string): number {
    if (fullString === partial) return 1.0;
    if (fullString.startsWith(partial)) return 0.9;
    
    // Simple fuzzy matching score
    let score = 0;
    let j = 0;
    for (let i = 0; i < fullString.length && j < partial.length; i++) {
      if (fullString[i] === partial[j]) {
        score += 1 / fullString.length;
        j++;
      }
    }
    
    return j === partial.length ? score : 0;
  }

  async validateCommand(command: string): Promise<ValidationResult> {
    const result: ValidationResult = {
      valid: true,
      errors: [],
      warnings: [],
      suggestions: []
    };

    const parts = command.trim().split(' ').filter(p => p.length > 0);
    
    if (parts.length === 0) {
      result.valid = false;
      result.errors.push('Empty command');
      return result;
    }

    // Check if starts with 'playground'
    if (parts[0] !== 'playground') {
      result.valid = false;
      result.errors.push('Command must start with "playground"');
      return result;
    }

    const commandParts = parts.slice(1).filter(part => !part.startsWith('--'));
    const optionParts = parts.slice(1).filter(part => part.startsWith('--'));

    // Validate command path
    if (commandParts.length === 0) {
      result.valid = false;
      result.errors.push('No command specified');
      return result;
    }

    const foundCommand = this.parser.findCommand(commandParts);
    if (!foundCommand) {
      result.valid = false;
      result.errors.push(`Unknown command: ${commandParts.join(' ')}`);
      
      // Suggest similar commands
      const suggestions = await this.getSuggestions(commandParts.join(' '));
      result.suggestions = suggestions.slice(0, 3).map(s => s.completion);
      
      return result;
    }

    // Validate options
    const providedOptions = new Set<string>();
    for (let i = 0; i < optionParts.length; i++) {
      const optionPart = optionParts[i];
      const optionName = optionPart.replace(/^--?/, '');
      
      const option = foundCommand.options?.find(opt => opt.name === optionName);
      if (!option) {
        result.valid = false;
        result.errors.push(`Unknown option: ${optionPart}`);
        continue;
      }

      if (providedOptions.has(optionName) && !option.repeatable) {
        result.warnings.push(`Option --${optionName} specified multiple times but is not repeatable`);
      }
      
      providedOptions.add(optionName);
    }

    // Check required options
    foundCommand.options?.forEach(option => {
      if (option.required && !providedOptions.has(option.name)) {
        result.valid = false;
        result.errors.push(`Missing required option: --${option.name}`);
      }
    });

    // Check if command needs subcommands
    if (foundCommand.subcommands && foundCommand.subcommands.length > 0) {
      // Check if this is a terminal command or needs subcommands
      const hasSubcommand = commandParts.length > 1;
      if (!hasSubcommand) {
        result.warnings.push('This command has subcommands available');
        result.suggestions.push(
          ...foundCommand.subcommands.slice(0, 3).map(sub => 
            `playground ${commandParts.join(' ')} ${sub.name}`
          )
        );
      }
    }

    return result;
  }
}
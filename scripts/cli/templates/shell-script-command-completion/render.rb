# render script - shell-script-command-completion
#
# Writes playground.yaml, the command spec of the "Shell Script Command Completion" VS Code extension
# (https://github.com/yamaton/vscode-h2o), installed by 'playground tools install-vscode-extension'.
# bashly-reload converts it to playground.json, downloaded by the extension from the master branch.
#
# The spec is built as a Hash and dumped with to_yaml, so that it follows the schema the extension
# validates whatever the help texts contain: "argument" is always a string, "subcommands" is only set
# when there are some, every level of commands is nested (playground debug log-level set), and private
# commands and flags are left out.
require 'yaml'

def kdp_option_spec(flag)
  description = flag.help.to_s.rstrip
  attributes = []
  attributes << "Required: ✓ Yes" if flag.required
  attributes << "Repeatable: ✓ Yes" if flag.repeatable
  attributes << "Default value: #{flag.default}" if flag.default && flag.default != ''
  attributes << "Allowed values: #{flag.allowed.join(', ')}" if flag.allowed
  attributes << "Conflicts with: #{flag.conflicts.join(', ')}" if flag.conflicts
  description = [description, attributes.join("\n")].reject(&:empty?).join("\n\n")

  {
    'names' => [flag.long, flag.short, *flag.alt].compact.uniq,
    'argument' => flag.arg ? flag.arg.upcase : '',
    'description' => description,
  }
end

def kdp_command_spec(command, name)
  spec = {
    'name' => name,
    'description' => command.help.to_s.rstrip,
    'usage' => command.usage_string.sanitize_for_print,
    'options' => command.flags.reject(&:private).map { |flag| kdp_option_spec(flag) },
  }
  spec['aliases'] = command.alt unless command.alt.empty?
  subcommands = command.commands.reject(&:private)
  spec['subcommands'] = subcommands.map { |subcommand| kdp_command_spec(subcommand, subcommand.name) } unless subcommands.empty?
  spec
end

File.write("#{target}/playground.yaml", kdp_command_spec(command, command.full_name).to_yaml)

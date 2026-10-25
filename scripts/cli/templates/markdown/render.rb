# render script - markdown
require 'gtx'

# for previewing only (not needed for rendering)
require 'tty-markdown'

# Markdown formatting helpers of the help texts (for_kdp_markdown, KdpMarkdown.values)
load "#{source}/kdp_markdown.rb"

# Load the GTX template
template = "#{source}/markdown.gtx"
gtx = GTX.load_file template

# Load the GTX template
template = "#{source}/index.gtx"
gtxindex = GTX.load_file template

# Render the file for the main command
save "#{target}/index.md", gtxindex.parse(command)

# Render a file for each public subcommand (private commands and their subcommands are skipped)
public_deep_commands = ->(cmd) { cmd.commands.reject(&:private).flat_map { |c| [c] + public_deep_commands.(c) } }
public_deep_commands.(command).each do |subcommand|
  save "#{target}/#{subcommand.full_name}.md", gtx.parse(subcommand)
end

# Show one of the files if requested
if show
  file = "#{target}/#{show}"
  puts TTY::Markdown.parse_file(file) if File.exist?(file)
end

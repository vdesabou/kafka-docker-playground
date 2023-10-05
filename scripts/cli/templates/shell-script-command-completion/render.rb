# render script - shell-script-command-completion
require 'gtx'

# Load the GTX template
template = "#{source}/main.gtx"
gtx = GTX.load_file template

File.open("#{target}/playground.yaml", "w") do |file|
  file.write(gtx.parse(command))
end

template = "#{source}/subcommand.gtx"
gtx = GTX.load_file template

# Append to a file for each subcommand
command.deep_commands.reject(&:private).each do |subcommand|
  File.open("#{target}/playground.yaml", "a") do |file|
    file.write(gtx.parse(subcommand))
  end
end
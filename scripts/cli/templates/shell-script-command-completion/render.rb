# render script - shell-script-command-completion
require 'gtx'

# Load the GTX template
template = "#{source}/main.gtx"
gtx = GTX.load_file template

File.open("#{target}/playground.yaml", "w") do |file|
  file.write(gtx.parse(command))
end

template = "#{source}/subcommand.gtx"
gtxsub = GTX.load_file template

template = "#{source}/subsubcommand.gtx"
gtxsubsub = GTX.load_file template

# Append to a file for each subcommand
command.deep_commands.reject(&:private).each do |subcommand|

  if subcommand.commands.any?
    File.open("#{target}/playground.yaml", "a") do |file|
      file.write(gtxsub.parse(subcommand))
    end
    subcommand.commands.reject(&:private).each do |subsubcommand|
      File.open("#{target}/playground.yaml", "a") do |file|
        file.write(gtxsubsub.parse(subsubcommand))
      end
    end
  else
    # File.open("#{target}/playground.yaml", "a") do |file|
    #   file.write(gtxsub.parse(subcommand))
    # end
  end
end
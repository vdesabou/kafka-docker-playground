# render script - shell-script-command-completion
require 'gtx'

require 'logger'

# Create a new logger instance
logger = Logger.new(STDOUT)

# Set the logging level to INFO
logger.level = Logger::INFO

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
processed_subcommands = []

command.deep_commands.reject(&:private).each do |subcommand|
  if subcommand.commands.any?
    File.open("#{target}/playground.yaml", "a") do |file|
      file.write(gtxsub.parse(subcommand))
    end
    subcommand.commands.reject(&:private).each do |subsubcommand|
      unless processed_subcommands.include?(subsubcommand.full_name)
        File.open("#{target}/playground.yaml", "a") do |file|
          file.write(gtxsubsub.parse(subsubcommand))
        end
        processed_subcommands << subsubcommand.full_name
        logger.info("process subcommand")
        logger.info(subsubcommand.full_name)
      end
    end
    processed_subcommands << subcommand.full_name
  else
    unless processed_subcommands.include?(subcommand.full_name)
      File.open("#{target}/playground.yaml", "a") do |file|
        file.write(gtxsub.parse(subcommand))
      end
      processed_subcommands << subcommand.full_name
      logger.info("process command")
      logger.info(subcommand.full_name)
    end
  end
end
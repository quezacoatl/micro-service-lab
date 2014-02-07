require './app'

$log = Logger.new(STDERR)

EM.error_handler do |e|
  $log.error "Error in EventMachine event loop: #{e}\n#{e.backtrace.join("\n")}"
end

run App

require 'bundler/setup'

require 'eventmachine'
require 'amqp'
require 'json'

class App

  APP_ID = 'jl_app'

  def initialize
    connection = AMQP.connect 'amqp://kwiwswxf:2buomLESEgNRRdMWXJ-fFLbpP61mX8Pu@striped-ibex.rmq.cloudamqp.com/kwiwswxf'

    channel = AMQP::Channel.new(connection, :auto_recovery => true)

    @queue = channel.queue(APP_ID)#, :auto_delete => true)

    @exchange = channel.topic('lab', passive: true)

    @queue.bind(@exchange, routing_key: '#').subscribe do |headers, payload|
      puts "headers: #{headers}"
      puts "payload: #{payload}"
    end

    channel.on_error do |ch, channel_close|
      puts channel_close.reply_text
    end
  end

  def service_up
    publish()
  end

  def publish(data, app_id, stream_id, type, headers, routing_key)
    @exchange.publish(data,
       app_id: app_id,
       type: type,
       headers: {
          stream_id: stream_id
       },
       timestamp: Time.now.to_i,
       routing_key: routing_key)
  end
end

EM.run do
  App.new
end


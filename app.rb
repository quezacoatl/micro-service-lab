require 'bundler/setup'

require 'logger'
require 'securerandom'

require 'sinatra'
require 'eventmachine'
require 'amqp'
require 'json'

class App < Sinatra::Base

  APP_ID = 'jl_app'

  def initialize(app = nil)
    super(app)

    connection = AMQP.connect 'amqp://kwiwswxf:2buomLESEgNRRdMWXJ-fFLbpP61mX8Pu@striped-ibex.rmq.cloudamqp.com/kwiwswxf'

    channel = AMQP::Channel.new(connection, :auto_recovery => true)

    @queue = channel.queue("#{APP_ID}_queue", :auto_delete => true)

    @exchange = channel.topic('lab', passive: true)

    @messages_received = 0

    @queue.bind(@exchange, routing_key: '#').subscribe do |header, payload|
      @messages_received += 1
      $log.debug "---------- received message ----------"
      $log.debug "content type: #{header.content_type}"
      $log.debug "headers: #{header.headers}"
      $log.debug "payload: #{payload}"
    end

    channel.on_error do |ch, channel_close|
      $log.error channel_close.reply_text
    end

    service_up
  end

  def service_up
    publish({
      createdBy: "Johan Lundahl",
      description: "My incredible service",
      sourceUrl: "https://github.com/quezacoatl/micro-service-lab",
      serviceUrl: "http://young-crag-4311.herokuapp.com"
    }.to_json, APP_ID, APP_ID, 'ServiceOnlineEvent', 'service')
  end

  def service_down
    publish('', APP_ID, APP_ID, 'ServiceOfflineEvent', 'service')
  end

  def publish(data, app_id, stream_id, type, routing_key)
    @exchange.publish(data,
      message_id: SecureRandom.uuid,
      app_id: app_id,
      type: type,
      headers: {
        streamId: stream_id
      },
      content_type: 'application/json',
      timestamp: Time.now.to_i,
      routing_key: routing_key)
  end

  get '/' do
    "Number of messages received: #{@messages_received}"
  end
end
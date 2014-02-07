require 'bundler/setup'

require 'logger'
require 'securerandom'

require 'sinatra'
require 'eventmachine'
require 'amqp'
require 'json'

class Numeric
  def duration
    secs  = self.to_int
    mins  = secs / 60
    hours = mins / 60
    days  = hours / 24

    if days > 0
      "#{days} days and #{hours % 24} hours"
    elsif hours > 0
      "#{hours} hours and #{mins % 60} minutes"
    elsif mins > 0
      "#{mins} minutes and #{secs % 60} seconds"
    elsif secs >= 0
      "#{secs} seconds"
    end
  end
end

class App < Sinatra::Base

  APP_ID = 'jl_app'

  def initialize(app = nil)
    super(app)

    connection = AMQP.connect 'amqp://kwiwswxf:2buomLESEgNRRdMWXJ-fFLbpP61mX8Pu@striped-ibex.rmq.cloudamqp.com/kwiwswxf'

    channel = AMQP::Channel.new(connection, :auto_recovery => true)

    @queue = channel.queue("#{APP_ID}_queue", :auto_delete => true)

    @exchange = channel.topic('lab', passive: true)

    @messages_received = 0

    @ongoing_games = {}
    @finished_games = {}

    @node_id = SecureRandom.uuid

    @queue.bind(@exchange, routing_key: '#').subscribe do |header, payload|
      @messages_received += 1

      $log.debug "---------- received message ----------"
      $log.debug "content type: #{header.content_type}"
      $log.debug "headers: #{header.headers}"
      $log.debug "payload: #{payload}"

      stream_id = header.headers['streamId']

      if header.type == 'GameCreatedEvent'
        log "Added new game - #{stream_id}"
        game = JSON.parse(payload) rescue 'bad payload'
        @ongoing_games[stream_id] = game
      elsif header.type == 'GameEndedEvent'
        if @ongoing_games.has_key? stream_id
          log "Known game has ended - #{stream_id}"
          game = JSON.parse(payload) rescue 'bad payload'
          ongoing_game = @ongoing_games.delete(stream_id)

          if game.is_a?(Hash) && ongoing_game.is_a?(Hash)
            game.merge! ongoing_game
          end

          @finished_games[stream_id] = game
        end
      end
    end

    channel.on_error do |ch, channel_close|
      $log.error channel_close.reply_text
    end

    service_up

    EM.add_periodic_timer(10) do
      time_diff = Time.new(2014,02,07,18,30) - Time.now
      if time_diff < 0
        log "It's time for dinner!"
      else
        log "It's dinner in #{time_diff.duration}."
      end
    end
  end

  def log(msg, level = 'DEBUG')
    publish({
      message: msg,
      level: level,
    }.to_json, APP_ID, @node_id, 'LogEvent', 'log')
  end

  def service_up
    publish({
      createdBy: "Johan Lundahl",
      description: "My incredible service",
      sourceUrl: "https://github.com/quezacoatl/micro-service-lab",
      serviceUrl: "http://young-crag-4311.herokuapp.com"
    }.to_json, APP_ID, APP_ID, 'ServiceOnlineEvent', 'service')
    log "#{APP_ID} is up and running!"
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
    content_type 'application/json'
    {
      messages_received: @messages_received,
      games: {
        ongoing: @ongoing_games,
        finished: @finished_games
      }
    }.to_json
  end
end
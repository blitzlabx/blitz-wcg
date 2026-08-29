require 'telegram/bot'
require 'concurrent'
require 'fileutils'
require 'time'
require 'json'
require 'logger'
require 'securerandom'
require 'digest'

require_relative 'blitz_wcg/config'
require_relative 'blitz_wcg/persistence/store'
require_relative 'blitz_wcg/dictionary/client'
require_relative 'blitz_wcg/floket/verifier'
require_relative 'blitz_wcg/game/state'
require_relative 'blitz_wcg/game/engine'
require_relative 'blitz_wcg/challenge/manager'
require_relative 'blitz_wcg/admin/controller'
require_relative 'blitz_wcg/utils/helpers'
require_relative 'blitz_wcg/handlers/commands'
require_relative 'blitz_wcg/handlers/callbacks'
require_relative 'blitz_wcg/handlers/messages'
require_relative 'blitz_wcg/health_server'

module BlitzWCG
  class Bot
    def initialize
      Config.load!
      @store = Persistence::Store.new(Config.data_dir)
      @dict = Dictionary::Client.new(Config.dict_url, File.join(Config.data_dir, 'cache'), Config.word_cache_ttl)
      @engine = Game::Engine.new(@store, @dict)
      @floket = Floket::Verifier.new(@store, Config.floket_ttl)
      @running = true
    end

    def start
      Config.logger.info('Starting Blitz WCG...')
      @health = HealthServer.new(Config.port, @store)
      @health.start

      Telegram::Bot::Client.run(Config.token) do |bot|
        @api = bot.api
        @admin = Admin::Controller.new(@store, @api, @engine)
        @challenges = Challenge::Manager.new(@store, @engine)

        ctx = {
          bot: bot,
          api: @api,
          store: @store,
          engine: @engine,
          challenges: @challenges,
          floket: @floket,
          admin: @admin,
          dict: @dict
        }

        @commands = Handlers::Commands.new(ctx)
        @callbacks = Handlers::Callbacks.new(ctx)
        @messages = Handlers::Messages.new(ctx)

        @engine.recover_active_games

        setup_signals(bot)

        Config.logger.info('Blitz WCG is live. Created by Blitz · blitzlabx')

        bot.listen do |update|
          break unless @running
          process_update(update)
        end
      end
    ensure
      @health&.stop
      Config.logger.info('Blitz WCG stopped.')
    end

    def process_update(update)
      message = nil
      callback = nil

      if update.is_a?(Telegram::Bot::Types::Message)
        message = update
      elsif update.is_a?(Telegram::Bot::Types::CallbackQuery)
        callback = update
      elsif update.respond_to?(:message) && update.message
        message = update.message
      elsif update.respond_to?(:callback_query) && update.callback_query
        callback = update.callback_query
      end

      if message
        if message.text&.start_with?('/')
          @commands.handle(message)
        else
          @messages.handle(message)
        end
      elsif callback
        @callbacks.handle(callback)
      end
    rescue => e
      Config.logger.error("Update error: #{e.class} #{e.message}\n#{e.backtrace&.first(5)&.join("\n")}")
    end

    def setup_signals(bot)
      %w[INT TERM].each do |sig|
        Signal.trap(sig) do
          Config.logger.info("Signal #{sig} received, shutting down...")
          @running = false
          bot.stop
        end
      end
    end
  end
end

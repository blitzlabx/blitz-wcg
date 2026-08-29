require 'dotenv'
require 'logger'
require 'fileutils'

module BlitzWCG
  class Config
    class << self
      def load!(path = nil)
        Dotenv.load(path || File.expand_path('../../.env', __dir__))
        @token = ENV.fetch('TELEGRAM_BOT_TOKEN') { raise 'TELEGRAM_BOT_TOKEN missing' }
        @admin_id = ENV.fetch('ADMIN_ID', '0').to_i
        @donation_url = ENV.fetch('DONATION_URL', 'https://t.me/blitzlabx')
        @logo_url = ENV.fetch('LOGO_URL', '')
        @dict_url = ENV.fetch('DICTIONARY_API_URL', 'https://api.dictionaryapi.dev/api/v2/entries/en')
        @turn_timeout = ENV.fetch('TURN_TIMEOUT_SECONDS', '45').to_i
        @min_players = ENV.fetch('MIN_PLAYERS', '2').to_i
        @max_players = ENV.fetch('MAX_PLAYERS', '10').to_i
        @maintenance = ENV.fetch('MAINTENANCE_MODE', 'false') == 'true'
        @port = ENV.fetch('PORT', '3000').to_i
        @data_dir = ENV.fetch('DATA_DIR', File.expand_path('../../data', __dir__))
        @log_level = ENV.fetch('LOG_LEVEL', 'info')
        @floket_enabled = ENV.fetch('FLOKET_ENABLED', 'true') == 'true'
        @floket_ttl = ENV.fetch('FLOKET_CHALLENGE_TTL', '3600').to_i
        @word_cache_ttl = ENV.fetch('WORD_CACHE_TTL', '86400').to_i
        @broadcast_delay = ENV.fetch('BROADCAST_DELAY_MS', '50').to_i
        FileUtils.mkdir_p(@data_dir)
        FileUtils.mkdir_p(File.join(@data_dir, 'cache'))
        true
      end

      attr_reader :token, :admin_id, :donation_url, :logo_url, :dict_url,
                  :turn_timeout, :min_players, :max_players, :port, :data_dir,
                  :log_level, :floket_enabled, :floket_ttl, :word_cache_ttl,
                  :broadcast_delay

      def maintenance?
        @maintenance
      end

      def maintenance=(val)
        @maintenance = !!val
      end

      def admin?(user_id)
        user_id.to_i == @admin_id
      end

      def logger
        @logger ||= begin
          l = Logger.new($stdout)
          l.level = Logger.const_get(@log_level.upcase) rescue Logger::INFO
          l.formatter = proc do |severity, datetime, _progname, msg|
            "[#{datetime.strftime('%Y-%m-%d %H:%M:%S')}] #{severity} -- #{msg}\n"
          end
          l
        end
      end
    end
  end
end

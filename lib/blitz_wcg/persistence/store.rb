require 'json'
require 'fileutils'
require 'securerandom'
require 'monitor'

module BlitzWCG
  module Persistence
    class Store
      include MonitorMixin

      def initialize(data_dir)
        super()
        @data_dir = data_dir
        @users_file = File.join(data_dir, 'users.json')
        @games_file = File.join(data_dir, 'games.json')
        @challenges_file = File.join(data_dir, 'challenges.json')
        @bans_file = File.join(data_dir, 'bans.json')
        @stats_file = File.join(data_dir, 'stats.json')
        @verified_file = File.join(data_dir, 'verified.json')
        @settings_file = File.join(data_dir, 'settings.json')
        ensure_files!
        @users = load_json(@users_file)
        @games = load_json(@games_file)
        @challenges = load_json(@challenges_file)
        @bans = load_json(@bans_file)
        @stats = load_json(@stats_file) || default_stats
        @verified = load_json(@verified_file)
        @settings = load_json(@settings_file) || {}
      end

      def default_stats
        {
          'total_games' => 0,
          'total_words' => 0,
          'total_users' => 0,
          'started_at' => Time.now.to_i
        }
      end

      def ensure_files!
        FileUtils.mkdir_p(@data_dir)
        [@users_file, @games_file, @challenges_file, @bans_file, @stats_file, @verified_file, @settings_file].each do |f|
          File.write(f, '{}') unless File.exist?(f)
        end
      end

      def load_json(path)
        synchronize do
          data = File.read(path)
          JSON.parse(data)
        rescue
          {}
        end
      end

      def save_json(path, data)
        synchronize do
          tmp = "#{path}.tmp"
          File.write(tmp, JSON.pretty_generate(data))
          File.rename(tmp, path)
        end
      end

      def get_user(id)
        synchronize { @users[id.to_s] }
      end

      def upsert_user(id, attrs)
        synchronize do
          key = id.to_s
          @users[key] ||= {
            'id' => id,
            'username' => nil,
            'first_name' => nil,
            'score' => 0,
            'wins' => 0,
            'games_played' => 0,
            'words_played' => 0,
            'created_at' => Time.now.to_i,
            'last_seen' => Time.now.to_i,
            'muted' => false
          }
          @users[key].merge!(attrs.transform_keys(&:to_s))
          @users[key]['last_seen'] = Time.now.to_i
          save_json(@users_file, @users)
          @users[key]
        end
      end

      def all_users
        synchronize { @users.dup }
      end

      def ban_user(id, reason = nil)
        synchronize do
          @bans[id.to_s] = { 'reason' => reason, 'at' => Time.now.to_i }
          save_json(@bans_file, @bans)
        end
      end

      def unban_user(id)
        synchronize do
          @bans.delete(id.to_s)
          save_json(@bans_file, @bans)
        end
      end

      def banned?(id)
        synchronize { @bans.key?(id.to_s) }
      end

      def mute_user(id)
        upsert_user(id, muted: true)
      end

      def unmute_user(id)
        upsert_user(id, muted: false)
      end

      def muted?(id)
        u = get_user(id)
        u && u['muted']
      end

      def get_game(chat_id)
        synchronize { @games[chat_id.to_s] }
      end

      def save_game(chat_id, game_data)
        synchronize do
          if game_data.nil?
            @games.delete(chat_id.to_s)
          else
            @games[chat_id.to_s] = game_data
          end
          save_json(@games_file, @games)
        end
      end

      def all_games
        synchronize { @games.dup }
      end

      def clear_game(chat_id)
        save_game(chat_id, nil)
      end

      def get_challenge(id)
        synchronize { @challenges[id.to_s] }
      end

      def save_challenge(id, data)
        synchronize do
          if data.nil?
            @challenges.delete(id.to_s)
          else
            @challenges[id.to_s] = data
          end
          save_json(@challenges_file, @challenges)
        end
      end

      def find_challenge_by_users(from_id, to_id)
        synchronize do
          @challenges.values.find do |c|
            (c['from_id'] == from_id && c['to_id'] == to_id) ||
              (c['from_id'] == to_id && c['to_id'] == from_id)
          end
        end
      end

      def all_challenges
        synchronize { @challenges.dup }
      end

      def set_verified(user_id, until_ts = nil)
        synchronize do
          @verified[user_id.to_s] = until_ts || (Time.now.to_i + 86400 * 30)
          save_json(@verified_file, @verified)
        end
      end

      def verified?(user_id)
        synchronize do
          exp = @verified[user_id.to_s]
          exp && exp > Time.now.to_i
        end
      end

      def increment_stat(key, by = 1)
        synchronize do
          @stats[key.to_s] = (@stats[key.to_s] || 0) + by
          save_json(@stats_file, @stats)
        end
      end

      def stats
        synchronize { @stats.dup }
      end

      def setting(key, default = nil)
        synchronize { @settings.fetch(key.to_s, default) }
      end

      def set_setting(key, value)
        synchronize do
          @settings[key.to_s] = value
          save_json(@settings_file, @settings)
        end
      end
    end
  end
end

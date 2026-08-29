module BlitzWCG
  module Admin
    class Controller
      def initialize(store, bot_api, engine)
        @store = store
        @api = bot_api
        @engine = engine
      end

      def authorized?(user_id)
        Config.admin?(user_id)
      end

      def panel_text
        stats = @store.stats
        games = @store.all_games.size
        users = @store.all_users.size
        maint = Config.maintenance? ? 'ON' : 'OFF'
        <<~TXT
          🛠 *Blitz WCG Admin Panel*

          Status: #{maint == 'ON' ? '🔧 Maintenance' : '✅ Online'}
          Users: #{users}
          Active/Stored Games: #{games}
          Total Games: #{stats['total_games'] || 0}
          Total Words: #{stats['total_words'] || 0}
          Uptime start: #{Time.at(stats['started_at'] || Time.now.to_i).utc}

          Commands:
          /stats — detailed stats
          /users — user count & sample
          /games — list active games
          /broadcast <text> — text broadcast
          /maintenance on|off
          /ban <user_id> [reason]
          /unban <user_id>
          /mute <user_id>
          /unmute <user_id>
          /shutdown — stop bot
          /restart — soft restart note
          /logs — recent log hint
        TXT
      end

      def stats_text
        s = @store.stats
        u = @store.all_users
        g = @store.all_games
        top = u.values.sort_by { |x| -(x['score'] || 0) }.first(5)
        top_str = top.map.with_index(1) { |p, i| "#{i}. #{p['first_name'] || p['username']} — #{p['score']} pts" }.join("\n")
        <<~TXT
          📊 *Statistics*

          Total users: #{u.size}
          Total games: #{s['total_games']}
          Total words played: #{s['total_words']}
          Stored game states: #{g.size}
          Banned: #{@store.instance_variable_get(:@bans).size rescue 0}

          Top scores:
          #{top_str.empty? ? 'None yet' : top_str}
        TXT
      end

      def set_maintenance(on)
        Config.maintenance = on
        @store.set_setting('maintenance', on)
        on
      end

      def broadcast_text(text, &progress)
        users = @store.all_users
        sent = 0
        failed = 0
        users.each_value do |u|
          begin
            @api.send_message(chat_id: u['id'], text: text, parse_mode: 'HTML')
            sent += 1
          rescue => e
            failed += 1
            Config.logger.warn("Broadcast fail #{u['id']}: #{e.message}")
          end
          sleep(Config.broadcast_delay / 1000.0)
          progress.call(sent, failed) if progress && (sent + failed) % 20 == 0
        end
        { sent: sent, failed: failed }
      end

      def broadcast_media(file_id, type, caption = nil, &progress)
        users = @store.all_users
        sent = 0
        failed = 0
        method = case type
                 when 'photo' then :send_photo
                 when 'video' then :send_video
                 when 'document' then :send_document
                 when 'animation' then :send_animation
                 else :send_photo
                 end
        users.each_value do |u|
          begin
            args = { chat_id: u['id'] }
            args[type.to_sym] = file_id
            args[:caption] = caption if caption && !caption.empty?
            @api.public_send(method, **args)
            sent += 1
          rescue => e
            failed += 1
            Config.logger.warn("Media broadcast fail #{u['id']}: #{e.message}")
          end
          sleep(Config.broadcast_delay / 1000.0)
        end
        { sent: sent, failed: failed }
      end

      def ban(user_id, reason = nil)
        @store.ban_user(user_id, reason)
      end

      def unban(user_id)
        @store.unban_user(user_id)
      end

      def mute(user_id)
        @store.mute_user(user_id)
      end

      def unmute(user_id)
        @store.unmute_user(user_id)
      end

      def list_games
        @store.all_games.map do |cid, g|
          "#{cid}: #{g['status']} players=#{(g['players'] || []).size} letter=#{g['current_letter']}"
        end
      end
    end
  end
end

module BlitzWCG
  module Handlers
    class Callbacks
      def initialize(ctx)
        @api = ctx[:api]
        @store = ctx[:store]
        @engine = ctx[:engine]
        @challenges = ctx[:challenges]
        @floket = ctx[:floket]
        @admin = ctx[:admin]
      end

      def handle(callback)
        data = callback.data.to_s
        uid = callback.from.id
        cid = callback.message.chat.id
        mid = callback.message.message_id

        return if @store.banned?(uid)

        @store.upsert_user(uid, {
          username: callback.from.username,
          first_name: callback.from.first_name
        })

        if data.start_with?('floket:')
          handle_floket(callback, data)
          return
        end

        if Config.maintenance? && !Config.admin?(uid)
          answer(callback, 'Maintenance mode')
          return
        end

        case data
        when 'play'
          answer(callback)
          # Simulate /play
          if callback.message.chat.type == 'private'
            @api.send_message(chat_id: cid, text: 'Use /challenge @username in DM or /play in a group.')
          else
            res = @engine.create_group_game(cid, { 'id' => uid, 'username' => callback.from.username, 'first_name' => callback.from.first_name })
            if res[:ok]
              @api.send_message(chat_id: cid, text: Utils::Helpers.game_status_text(res[:state]), parse_mode: 'Markdown',
                                reply_markup: Utils::Helpers.game_waiting_keyboard(true))
            else
              @api.send_message(chat_id: cid, text: res[:error])
            end
          end
        when 'join_game'
          res = @engine.join(cid, { 'id' => uid, 'username' => callback.from.username, 'first_name' => callback.from.first_name })
          answer(callback, res[:ok] ? 'Joined!' : res[:error])
          if res[:ok]
            @api.edit_message_text(chat_id: cid, message_id: mid, text: Utils::Helpers.game_status_text(res[:state]),
                                   parse_mode: 'Markdown', reply_markup: Utils::Helpers.game_waiting_keyboard(res[:state].host_id == uid))
          end
        when 'start_game'
          res = @engine.start(cid, uid)
          answer(callback, res[:ok] ? 'Started!' : res[:error])
          if res[:ok]
            @api.edit_message_text(chat_id: cid, message_id: mid, text: Utils::Helpers.game_status_text(res[:state]),
                                   parse_mode: 'Markdown', reply_markup: Utils::Helpers.game_active_keyboard)
            @engine.start_timer(cid) do |timeout_res|
              if timeout_res
                begin
                  @api.send_message(chat_id: cid, text: "⏰ Time up for #{timeout_res[:skipped]&.dig('first_name') || 'player'}!\n\n#{Utils::Helpers.game_status_text(timeout_res[:state])}", parse_mode: 'Markdown')
                rescue
                end
              end
            end
          end
        when 'cancel_game'
          res = @engine.cancel(cid)
          answer(callback, res[:ok] ? 'Cancelled' : 'Failed')
          @api.edit_message_text(chat_id: cid, message_id: mid, text: 'Game cancelled.') if res[:ok]
        when 'leave_game'
          res = @engine.leave(cid, uid)
          answer(callback, res[:ok] ? 'Left' : res[:error])
        when 'game_status'
          state = @engine.load(cid)
          answer(callback)
          @api.send_message(chat_id: cid, text: Utils::Helpers.game_status_text(state), parse_mode: 'Markdown')
        when 'leaderboard'
          answer(callback)
          users = @store.all_users.values.sort_by { |x| -(x['score'] || 0) }.first(10)
          lines = users.map.with_index(1) { |u, i| "#{i}. #{u['first_name'] || u['username']} — #{u['score'] || 0}" }
          @api.send_message(chat_id: cid, text: "🏆 *Leaderboard*\n\n#{lines.join("\n")}", parse_mode: 'Markdown')
        when 'profile'
          answer(callback)
          u = @store.get_user(uid) || {}
          @api.send_message(chat_id: cid, text: "👤 Score: #{u['score'] || 0} | Wins: #{u['wins'] || 0} | Games: #{u['games_played'] || 0}", parse_mode: 'Markdown')
        when 'rules'
          answer(callback)
          @api.send_message(chat_id: cid, text: Utils::Helpers.rules_text, parse_mode: 'Markdown')
        when 'donate'
          answer(callback)
          @api.send_message(chat_id: cid, text: "❤️ #{Config.donation_url}")
        when 'challenge_help'
          answer(callback)
          @api.send_message(chat_id: cid, text: "To challenge: open a private chat with me and send\n/challenge @username")
        when /^accept_chal:(.+)/
          res = @challenges.accept($1, uid)
          answer(callback, res[:ok] ? 'Accepted!' : res[:error])
          if res[:ok]
            @api.send_message(chat_id: cid, text: Utils::Helpers.game_status_text(res[:game]), parse_mode: 'Markdown')
          end
        when /^decline_chal:(.+)/
          res = @challenges.decline($1, uid)
          answer(callback, res[:ok] ? 'Declined' : res[:error])
        when 'admin_stats'
          return answer(callback, 'No') unless Config.admin?(uid)
          answer(callback)
          @api.send_message(chat_id: cid, text: @admin.stats_text, parse_mode: 'Markdown')
        when 'admin_users'
          return answer(callback, 'No') unless Config.admin?(uid)
          answer(callback)
          @api.send_message(chat_id: cid, text: "Users: #{@store.all_users.size}")
        when 'admin_games'
          return answer(callback, 'No') unless Config.admin?(uid)
          answer(callback)
          list = @admin.list_games
          @api.send_message(chat_id: cid, text: list.empty? ? 'No games' : list.join("\n"))
        when 'admin_maint'
          return answer(callback, 'No') unless Config.admin?(uid)
          on = !Config.maintenance?
          @admin.set_maintenance(on)
          answer(callback, "Maintenance #{on ? 'ON' : 'OFF'}")
        when 'admin_broadcast_help'
          return answer(callback, 'No') unless Config.admin?(uid)
          answer(callback)
          @api.send_message(chat_id: cid, text: "Use /broadcast <text>\nFor media: reply to a media message with /broadcast_media (not fully wired in text mode)")
        else
          answer(callback)
        end
      rescue => e
        Config.logger.error("Callback error: #{e.message}")
        answer(callback, 'Error') rescue nil
      end

      def handle_floket(callback, data)
        parts = data.split(':')
        token = parts[1]
        chosen = parts[2]
        uid = callback.from.id
        ok = @floket.verify(token, chosen, uid)
        if ok
          answer(callback, 'Verified ✅')
          @api.send_message(chat_id: callback.message.chat.id, text: '✅ Floket verification passed. You can now use the bot.')
        else
          answer(callback, 'Wrong ❌')
        end
      end

      def answer(cb, text = nil)
        opts = { callback_query_id: cb.id }
        opts[:text] = text if text
        @api.answer_callback_query(**opts)
      rescue
      end
    end
  end
end

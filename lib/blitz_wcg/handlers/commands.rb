module BlitzWCG
  module Handlers
    class Commands
      def initialize(ctx)
        @bot = ctx[:bot]
        @api = ctx[:api]
        @store = ctx[:store]
        @engine = ctx[:engine]
        @challenges = ctx[:challenges]
        @floket = ctx[:floket]
        @admin = ctx[:admin]
        @dict = ctx[:dict]
      end

      def handle(message)
        return unless message.text
        text = message.text.strip
        cmd, *args = text.split(/\s+/, 2)
        cmd = cmd.downcase.split('@').first
        user = message.from
        chat = message.chat
        uid = user.id
        cid = chat.id

        return if @store.banned?(uid)
        return if @store.muted?(uid) && !Config.admin?(uid)

        @store.upsert_user(uid, {
          username: user.username,
          first_name: user.first_name,
          last_name: user.last_name
        })

        if Config.maintenance? && !Config.admin?(uid)
          reply(cid, "🔧 Bot is under maintenance. Please try again later.")
          return
        end

        case cmd
        when '/start' then cmd_start(message)
        when '/help' then cmd_help(message)
        when '/play' then cmd_play(message)
        when '/challenge' then cmd_challenge(message, args[0])
        when '/accept' then cmd_accept(message, args[0])
        when '/decline' then cmd_decline(message, args[0])
        when '/cancel' then cmd_cancel(message)
        when '/stats' then cmd_stats(message)
        when '/profile' then cmd_profile(message)
        when '/leaderboard', '/lb' then cmd_leaderboard(message)
        when '/rules' then cmd_rules(message)
        when '/donate' then cmd_donate(message)
        when '/settings' then cmd_settings(message)
        when '/ping' then cmd_ping(message)
        when '/health' then cmd_health(message)
        when '/admin' then cmd_admin(message)
        when '/broadcast' then cmd_broadcast(message, args[0])
        when '/maintenance' then cmd_maintenance(message, args[0])
        when '/shutdown' then cmd_shutdown(message)
        when '/restart' then cmd_restart(message)
        when '/users' then cmd_users(message)
        when '/games' then cmd_games(message)
        when '/logs' then cmd_logs(message)
        when '/ban' then cmd_ban(message, args[0])
        when '/unban' then cmd_unban(message, args[0])
        when '/mute' then cmd_mute(message, args[0])
        when '/unmute' then cmd_unmute(message, args[0])
        end
      end

      def cmd_start(msg)
        uid = msg.from.id
        cid = msg.chat.id
        name = msg.from.first_name || 'Player'

        if @floket.require_verification?(uid, msg.chat.type)
          chal = @floket.create_challenge(uid)
          @api.send_message(
            chat_id: cid,
            text: "🔐 *Floket Verification*\n\nProve you're human:\n`#{chal[:question]}`",
            parse_mode: 'Markdown',
            reply_markup: Utils::Helpers.floket_keyboard(chal[:token], chal[:options])
          )
          return
        end

        welcome = <<~TXT
          👋 Welcome to *Blitz WCG*, #{name}!

          The competitive Word Chain Game for Telegram.

          Play in groups with friends or challenge anyone in DM.

          Created by *Blitz*
          Social: [blitzlabx](https://t.me/blitzlabx)
        TXT

        if Config.logo_url && !Config.logo_url.empty?
          begin
            @api.send_photo(chat_id: cid, photo: Config.logo_url, caption: welcome, parse_mode: 'Markdown', reply_markup: Utils::Helpers.main_keyboard)
            return
          rescue
          end
        end
        @api.send_message(chat_id: cid, text: welcome, parse_mode: 'Markdown', reply_markup: Utils::Helpers.main_keyboard, disable_web_page_preview: true)
      end

      def cmd_help(msg)
        reply(msg.chat.id, <<~TXT)
          📖 *Blitz WCG Help*

          /play — Create or join a group game
          /challenge @user — Challenge someone
          /accept /decline — Respond to challenge
          /cancel — Cancel current game/challenge
          /stats /profile /leaderboard
          /rules /donate /ping

          Just type a word on your turn!
        TXT
      end

      def cmd_play(msg)
        cid = msg.chat.id
        uid = msg.from.id
        if msg.chat.type == 'private'
          reply(cid, "In DMs use /challenge @username to start a 1v1.\nIn groups use /play to create a multiplayer game.")
          return
        end

        if @floket.require_verification?(uid, msg.chat.type)
          chal = @floket.create_challenge(uid)
          @api.send_message(chat_id: cid, text: "🔐 Floket: `#{chal[:question]}`", parse_mode: 'Markdown',
                            reply_markup: Utils::Helpers.floket_keyboard(chal[:token], chal[:options]))
          return
        end

        result = @engine.create_group_game(cid, {
          'id' => uid,
          'username' => msg.from.username,
          'first_name' => msg.from.first_name
        })
        if result[:ok]
          state = result[:state]
          @api.send_message(
            chat_id: cid,
            text: Utils::Helpers.game_status_text(state),
            parse_mode: 'Markdown',
            reply_markup: Utils::Helpers.game_waiting_keyboard(true)
          )
        else
          reply(cid, result[:error])
        end
      end

      def cmd_challenge(msg, target)
        cid = msg.chat.id
        unless msg.chat.type == 'private'
          reply(cid, 'Challenges are started from private chat with the bot.')
          return
        end
        unless target && !target.empty?
          reply(cid, 'Usage: /challenge @username')
          return
        end

        if @floket.require_verification?(msg.from.id, 'private')
          chal = @floket.create_challenge(msg.from.id)
          @api.send_message(chat_id: cid, text: "🔐 Floket: `#{chal[:question]}`", parse_mode: 'Markdown',
                            reply_markup: Utils::Helpers.floket_keyboard(chal[:token], chal[:options]))
          return
        end

        res = @challenges.create({
          'id' => msg.from.id,
          'username' => msg.from.username,
          'first_name' => msg.from.first_name
        }, target)
        if res[:ok]
          c = res[:challenge]
          reply(cid, "⚔️ Challenge sent to @#{c['to_username']}!\nThey need to open the bot and accept.\nChallenge ID: `#{c['id']}`", md: true)
          known = @store.all_users.values.find { |u| u['username']&.downcase == c['to_username'].downcase }
          if known
            begin
              @api.send_message(
                chat_id: known['id'],
                text: "⚔️ *Challenge from #{c['from_name']}!*\n\nAccept or decline:",
                parse_mode: 'Markdown',
                reply_markup: Utils::Helpers.challenge_keyboard(c['id'])
              )
              c['to_id'] = known['id']
              @store.save_challenge(c['id'], c)
            rescue
            end
          end
        else
          reply(cid, res[:error])
        end
      end

      def cmd_accept(msg, id)
        res = @challenges.accept(id || '', msg.from.id)
        if res[:ok]
          reply(msg.chat.id, "✅ Challenge accepted! Game starting...\nLetter: *#{res[:game].current_letter.upcase}*", md: true)
          [res[:challenge]['from_id'], res[:challenge]['to_id']].each do |pid|
            begin
              @api.send_message(chat_id: pid, text: Utils::Helpers.game_status_text(res[:game]), parse_mode: 'Markdown')
            rescue
            end
          end
        else
          reply(msg.chat.id, res[:error] || 'Could not accept.')
        end
      end

      def cmd_decline(msg, id)
        res = @challenges.decline(id || '', msg.from.id)
        reply(msg.chat.id, res[:ok] ? 'Challenge declined.' : (res[:error] || 'Failed'))
      end

      def cmd_cancel(msg)
        res = @engine.cancel(msg.chat.id)
        reply(msg.chat.id, res[:ok] ? 'Game cancelled.' : (res[:error] || 'Nothing to cancel.'))
      end

      def cmd_stats(msg)
        if Config.admin?(msg.from.id)
          reply(msg.chat.id, @admin.stats_text, md: true)
        else
          cmd_profile(msg)
        end
      end

      def cmd_profile(msg)
        u = @store.get_user(msg.from.id) || {}
        text = <<~TXT
          👤 *Profile — #{u['first_name'] || msg.from.first_name}*

          Score: #{u['score'] || 0}
          Wins: #{u['wins'] || 0}
          Games: #{u['games_played'] || 0}
          Words: #{u['words_played'] || 0}
        TXT
        reply(msg.chat.id, text, md: true)
      end

      def cmd_leaderboard(msg)
        users = @store.all_users.values.sort_by { |x| -(x['score'] || 0) }.first(10)
        lines = users.map.with_index(1) { |u, i| "#{i}. #{u['first_name'] || u['username'] || u['id']} — #{u['score'] || 0}" }
        reply(msg.chat.id, "🏆 *Leaderboard*\n\n#{lines.join("\n")}", md: true)
      end

      def cmd_rules(msg)
        reply(msg.chat.id, Utils::Helpers.rules_text, md: true)
      end

      def cmd_donate(msg)
        reply(msg.chat.id, "❤️ Support Blitz WCG\n#{Config.donation_url}")
      end

      def cmd_settings(msg)
        reply(msg.chat.id, "Settings are managed by the admin.\nTurn timeout: #{Config.turn_timeout}s")
      end

      def cmd_ping(msg)
        reply(msg.chat.id, "🏓 Pong — Blitz WCG online")
      end

      def cmd_health(msg)
        reply(msg.chat.id, "✅ OK\nRuby #{RUBY_VERSION}\nGames: #{@store.all_games.size}")
      end

      def cmd_admin(msg)
        return reply(msg.chat.id, 'Unauthorized.') unless Config.admin?(msg.from.id)
        @api.send_message(chat_id: msg.chat.id, text: @admin.panel_text, parse_mode: 'Markdown',
                          reply_markup: Utils::Helpers.admin_keyboard)
      end

      def cmd_broadcast(msg, text)
        return reply(msg.chat.id, 'Unauthorized.') unless Config.admin?(msg.from.id)
        return reply(msg.chat.id, 'Usage: /broadcast <message>') if text.nil? || text.empty?
        reply(msg.chat.id, 'Broadcasting...')
        result = @admin.broadcast_text(text)
        reply(msg.chat.id, "Done. Sent: #{result[:sent]}, Failed: #{result[:failed]}")
      end

      def cmd_maintenance(msg, arg)
        return reply(msg.chat.id, 'Unauthorized.') unless Config.admin?(msg.from.id)
        on = arg.to_s.downcase == 'on'
        @admin.set_maintenance(on)
        reply(msg.chat.id, "Maintenance mode: #{on ? 'ON' : 'OFF'}")
      end

      def cmd_shutdown(msg)
        return reply(msg.chat.id, 'Unauthorized.') unless Config.admin?(msg.from.id)
        reply(msg.chat.id, 'Shutting down...')
        Thread.new { sleep 1; exit 0 }
      end

      def cmd_restart(msg)
        return reply(msg.chat.id, 'Unauthorized.') unless Config.admin?(msg.from.id)
        reply(msg.chat.id, 'Restart requested. On Render this will cycle the service.')
      end

      def cmd_users(msg)
        return reply(msg.chat.id, 'Unauthorized.') unless Config.admin?(msg.from.id)
        reply(msg.chat.id, "Total users: #{@store.all_users.size}")
      end

      def cmd_games(msg)
        return reply(msg.chat.id, 'Unauthorized.') unless Config.admin?(msg.from.id)
        list = @admin.list_games
        reply(msg.chat.id, list.empty? ? 'No games.' : list.join("\n"))
      end

      def cmd_logs(msg)
        return reply(msg.chat.id, 'Unauthorized.') unless Config.admin?(msg.from.id)
        reply(msg.chat.id, 'Logs stream to stdout (check Render logs).')
      end

      def cmd_ban(msg, arg)
        return reply(msg.chat.id, 'Unauthorized.') unless Config.admin?(msg.from.id)
        id = arg.to_s.split.first.to_i
        return reply(msg.chat.id, 'Usage: /ban <user_id>') if id.zero?
        @admin.ban(id, arg.to_s.split[1..].join(' '))
        reply(msg.chat.id, "Banned #{id}")
      end

      def cmd_unban(msg, arg)
        return reply(msg.chat.id, 'Unauthorized.') unless Config.admin?(msg.from.id)
        id = arg.to_s.to_i
        @admin.unban(id)
        reply(msg.chat.id, "Unbanned #{id}")
      end

      def cmd_mute(msg, arg)
        return reply(msg.chat.id, 'Unauthorized.') unless Config.admin?(msg.from.id)
        id = arg.to_s.to_i
        @admin.mute(id)
        reply(msg.chat.id, "Muted #{id}")
      end

      def cmd_unmute(msg, arg)
        return reply(msg.chat.id, 'Unauthorized.') unless Config.admin?(msg.from.id)
        id = arg.to_s.to_i
        @admin.unmute(id)
        reply(msg.chat.id, "Unmuted #{id}")
      end

      private

      def reply(chat_id, text, md: false)
        opts = { chat_id: chat_id, text: text }
        opts[:parse_mode] = 'Markdown' if md
        @api.send_message(**opts)
      rescue => e
        Config.logger.error("Reply failed: #{e.message}")
      end
    end
  end
end

module BlitzWCG
  module Utils
    module Helpers
      module_function

      def mention(user)
        name = user['first_name'] || user['username'] || 'Player'
        if user['username']
          "[#{name}](https://t.me/#{user['username']})"
        else
          name
        end
      end

      def escape_md(text)
        text.to_s.gsub(/([_*`\[])/, '\\\\\1')
      end

      def player_list(state)
        state.players.map.with_index(1) do |p, i|
          marker = (state.current_player && state.current_player['id'] == p['id']) ? '▶️ ' : '• '
          score = state.scores[p['id'].to_s] || 0
          "#{marker}#{p['first_name']} (#{score})"
        end.join("\n")
      end

      def game_status_text(state)
        return 'No active game.' unless state
        case state.status
        when 'waiting'
          "⏳ *Waiting for players*\n\nPlayers (#{state.player_count}):\n#{player_list(state)}\n\nHost can /start when ready."
        when 'active'
          cur = state.current_player
          time_left = [state.turn_deadline - Time.now.to_i, 0].max
          <<~TXT
            🎮 *Word Chain — Live*

            Letter: *#{state.current_letter.upcase}*
            Turn: #{cur ? cur['first_name'] : '?'} (#{time_left}s)
            Round: #{state.round}
            Words used: #{state.used_words.size}

            #{player_list(state)}

            Send a word starting with *#{state.current_letter.upcase}*
          TXT
        when 'finished'
          winner = state.winner_id ? state.players.find { |p| p['id'] == state.winner_id } : nil
          scores = state.scores.sort_by { |_, v| -v }.map { |id, sc| "#{state.players.find { |p| p['id'].to_s == id }&.dig('first_name') || id}: #{sc}" }.join("\n")
          "🏁 *Game Over*\n\nWinner: #{winner ? winner['first_name'] : 'Draw'}\n\nScores:\n#{scores}"
        else
          "Status: #{state.status}"
        end
      end

      def main_keyboard
        {
          inline_keyboard: [
            [
              { text: '🎮 Play', callback_data: 'play' },
              { text: '⚔️ Challenge', callback_data: 'challenge_help' }
            ],
            [
              { text: '📊 Leaderboard', callback_data: 'leaderboard' },
              { text: '👤 Profile', callback_data: 'profile' }
            ],
            [
              { text: '📜 Rules', callback_data: 'rules' },
              { text: '❤️ Donate', callback_data: 'donate' }
            ]
          ]
        }
      end

      def game_waiting_keyboard(is_host)
        rows = [
          [{ text: '➕ Join', callback_data: 'join_game' }]
        ]
        rows << [{ text: '▶️ Start Game', callback_data: 'start_game' }] if is_host
        rows << [{ text: '❌ Cancel', callback_data: 'cancel_game' }]
        { inline_keyboard: rows }
      end

      def game_active_keyboard
        {
          inline_keyboard: [
            [{ text: '📊 Status', callback_data: 'game_status' }, { text: '🚪 Leave', callback_data: 'leave_game' }]
          ]
        }
      end

      def challenge_keyboard(challenge_id)
        {
          inline_keyboard: [
            [
              { text: '✅ Accept', callback_data: "accept_chal:#{challenge_id}" },
              { text: '❌ Decline', callback_data: "decline_chal:#{challenge_id}" }
            ]
          ]
        }
      end

      def floket_keyboard(token, options)
        {
          inline_keyboard: options.each_slice(2).map do |pair|
            pair.map { |o| { text: o.to_s, callback_data: "floket:#{token}:#{o}" } }
          end
        }
      end

      def admin_keyboard
        {
          inline_keyboard: [
            [{ text: '📊 Stats', callback_data: 'admin_stats' }, { text: '👥 Users', callback_data: 'admin_users' }],
            [{ text: '🎮 Games', callback_data: 'admin_games' }, { text: '🔧 Maintenance', callback_data: 'admin_maint' }],
            [{ text: '📢 Broadcast Help', callback_data: 'admin_broadcast_help' }]
          ]
        }
      end

      def rules_text
        <<~TXT
          📜 *Blitz WCG Rules*

          1. Players take turns saying a valid English word.
          2. Each word must start with the last letter of the previous word.
          3. No repeated words in the same game.
          4. Minimum length starts at 3 letters.
          5. You have limited time per turn.
          6. Score = word length + bonus for longer words.
          7. Last player standing or highest score wins.

          Commands:
          /play — start or join a group game
          /challenge @username — challenge in DM
          /accept /decline
          /stats /profile /leaderboard /rules /donate
        TXT
      end
    end
  end
end

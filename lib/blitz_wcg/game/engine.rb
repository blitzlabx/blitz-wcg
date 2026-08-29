require_relative 'state'

module BlitzWCG
  module Game
    class Engine
      STARTING_LETTERS = ('a'..'z').to_a

      def initialize(store, dictionary)
        @store = store
        @dict = dictionary
        @timers = Concurrent::Map.new
      end

      def create_group_game(chat_id, host)
        existing = load(chat_id)
        if existing && (existing.active? || existing.waiting?)
          return { ok: false, error: 'A game is already running in this chat.' }
        end

        state = State.new(chat_id, mode: 'group')
        state.host_id = host['id']
        state.add_player(host)
        state.status = 'waiting'
        save(state)
        { ok: true, state: state }
      end

      def create_dm_game(chat_id, players)
        state = State.new(chat_id, mode: 'dm')
        players.each { |p| state.add_player(p) }
        state.host_id = players.first['id']
        state.status = 'waiting'
        save(state)
        { ok: true, state: state }
      end

      def join(chat_id, user)
        state = load(chat_id)
        return { ok: false, error: 'No open game found.' } unless state&.waiting?
        return { ok: false, error: 'Game is full.' } if state.player_count >= Config.max_players
        return { ok: false, error: 'You are already in the game.' } if state.players.any? { |p| p['id'] == user['id'] }

        state.add_player(user)
        save(state)
        { ok: true, state: state }
      end

      def leave(chat_id, user_id)
        state = load(chat_id)
        return { ok: false, error: 'No game found.' } unless state
        state.remove_player(user_id)
        if state.player_count < 1
          cancel(chat_id)
          return { ok: true, state: nil, cancelled: true }
        end
        if state.active? && state.player_count < Config.min_players
          finish(state, reason: 'Not enough players remaining.')
          return { ok: true, state: state, finished: true }
        end
        save(state)
        { ok: true, state: state }
      end

      def start(chat_id, user_id)
        state = load(chat_id)
        return { ok: false, error: 'No game to start.' } unless state&.waiting?
        return { ok: false, error: 'Only the host can start.' } unless state.host_id == user_id || Config.admin?(user_id)
        return { ok: false, error: "Need at least #{Config.min_players} players." } if state.player_count < Config.min_players

        state.status = 'active'
        state.started_at = Time.now.to_i
        state.current_index = 0
        state.current_letter = STARTING_LETTERS.sample
        state.used_words = []
        state.round = 1
        state.last_move_at = Time.now.to_i
        state.turn_deadline = Time.now.to_i + Config.turn_timeout
        save(state)
        @store.increment_stat('total_games')
        { ok: true, state: state }
      end

      def play_word(chat_id, user_id, raw_word)
        state = load(chat_id)
        return { ok: false, error: 'No active game.' } unless state&.active?

        player = state.current_player
        return { ok: false, error: 'It is not your turn.' } unless player && player['id'] == user_id

        word = @dict.normalize(raw_word)
        return { ok: false, error: 'Invalid characters. Use letters only.' } if word.nil? || word.empty?
        return { ok: false, error: "Word must start with '#{state.current_letter.upcase}'." } unless word[0] == state.current_letter
        return { ok: false, error: "Word too short (min #{state.min_len})." } if word.length < state.min_len
        return { ok: false, error: 'Word already used in this game.' } if state.used_words.include?(word)

        unless @dict.valid_word?(word)
          return { ok: false, error: "'#{word}' is not a valid English word." }
        end

        state.used_words << word
        points = calculate_points(word)
        state.scores[user_id.to_s] = (state.scores[user_id.to_s] || 0) + points
        state.current_letter = word[-1]
        state.next_turn!
        save(state)
        @store.increment_stat('total_words')
        user = @store.get_user(user_id) || {}
        @store.upsert_user(user_id, {
          words_played: (user['words_played'] || 0) + 1,
          score: (user['score'] || 0) + points
        })

        { ok: true, state: state, word: word, points: points, next_player: state.current_player }
      end

      def timeout_turn(chat_id)
        state = load(chat_id)
        return unless state&.active?
        return if state.turn_deadline && state.turn_deadline > Time.now.to_i

        skipped = state.current_player
        state.next_turn!
        if state.player_count <= 1
          finish(state, reason: 'Only one player left.')
        else
          save(state)
        end
        { state: state, skipped: skipped }
      end

      def cancel(chat_id)
        state = load(chat_id)
        return { ok: false, error: 'No game.' } unless state
        state.status = 'cancelled'
        save(state)
        @store.clear_game(chat_id)
        stop_timer(chat_id)
        { ok: true }
      end

      def finish(state, reason: nil, winner_id: nil)
        state.status = 'finished'
        if winner_id
          state.winner_id = winner_id
        else
          max_score = state.scores.values.max || 0
          winners = state.scores.select { |_, s| s == max_score }.keys
          state.winner_id = winners.size == 1 ? winners.first.to_i : nil
        end
        save(state)
        state.players.each do |p|
          u = @store.get_user(p['id']) || {}
          wins = u['wins'] || 0
          wins += 1 if state.winner_id && state.winner_id == p['id']
          @store.upsert_user(p['id'], {
            games_played: (u['games_played'] || 0) + 1,
            wins: wins
          })
        end
        stop_timer(state.chat_id)
        state
      end

      def load(chat_id)
        data = @store.get_game(chat_id)
        State.from_h(data)
      end

      def save(state)
        @store.save_game(state.chat_id, state.to_h)
      end

      def calculate_points(word)
        base = word.length
        bonus = word.length >= 7 ? 3 : (word.length >= 5 ? 1 : 0)
        base + bonus
      end

      def start_timer(chat_id, &callback)
        stop_timer(chat_id)
        task = Concurrent::TimerTask.new(execution_interval: 5, run_now: false) do
          result = timeout_turn(chat_id)
          callback.call(result) if result && callback
        end
        task.execute
        @timers[chat_id.to_s] = task
      end

      def stop_timer(chat_id)
        t = @timers.delete(chat_id.to_s)
        t.shutdown if t
      end

      def recover_active_games
        @store.all_games.each do |cid, data|
          state = State.from_h(data)
          next unless state&.active?
          if state.turn_deadline && state.turn_deadline < Time.now.to_i - 10
            timeout_turn(cid)
          end
        end
      end
    end
  end
end

module BlitzWCG
  module Game
    class State
      STATUSES = %w[waiting active finished cancelled].freeze

      attr_accessor :chat_id, :mode, :status, :players, :current_index,
                    :current_letter, :used_words, :scores, :started_at,
                    :last_move_at, :turn_deadline, :winner_id, :host_id,
                    :message_id, :round, :min_len

      def initialize(chat_id, mode: 'group')
        @chat_id = chat_id
        @mode = mode
        @status = 'waiting'
        @players = []
        @current_index = 0
        @current_letter = nil
        @used_words = []
        @scores = {}
        @started_at = nil
        @last_move_at = nil
        @turn_deadline = nil
        @winner_id = nil
        @host_id = nil
        @message_id = nil
        @round = 0
        @min_len = 3
      end

      def to_h
        {
          'chat_id' => @chat_id,
          'mode' => @mode,
          'status' => @status,
          'players' => @players,
          'current_index' => @current_index,
          'current_letter' => @current_letter,
          'used_words' => @used_words,
          'scores' => @scores,
          'started_at' => @started_at,
          'last_move_at' => @last_move_at,
          'turn_deadline' => @turn_deadline,
          'winner_id' => @winner_id,
          'host_id' => @host_id,
          'message_id' => @message_id,
          'round' => @round,
          'min_len' => @min_len
        }
      end

      def self.from_h(h)
        return nil unless h
        s = new(h['chat_id'], mode: h['mode'] || 'group')
        s.status = h['status']
        s.players = h['players'] || []
        s.current_index = h['current_index'] || 0
        s.current_letter = h['current_letter']
        s.used_words = h['used_words'] || []
        s.scores = h['scores'] || {}
        s.started_at = h['started_at']
        s.last_move_at = h['last_move_at']
        s.turn_deadline = h['turn_deadline']
        s.winner_id = h['winner_id']
        s.host_id = h['host_id']
        s.message_id = h['message_id']
        s.round = h['round'] || 0
        s.min_len = h['min_len'] || 3
        s
      end

      def add_player(user)
        return false if @players.any? { |p| p['id'] == user['id'] }
        return false if @players.size >= Config.max_players
        @players << {
          'id' => user['id'],
          'username' => user['username'],
          'first_name' => user['first_name'] || user['username'] || 'Player'
        }
        @scores[user['id'].to_s] = 0
        true
      end

      def remove_player(user_id)
        @players.reject! { |p| p['id'] == user_id }
        @scores.delete(user_id.to_s)
        if @current_index >= @players.size
          @current_index = 0
        end
      end

      def current_player
        return nil if @players.empty?
        @players[@current_index % @players.size]
      end

      def next_turn!
        return if @players.empty?
        @current_index = (@current_index + 1) % @players.size
        @round += 1
        @last_move_at = Time.now.to_i
        @turn_deadline = Time.now.to_i + Config.turn_timeout
      end

      def player_count
        @players.size
      end

      def active?
        @status == 'active'
      end

      def waiting?
        @status == 'waiting'
      end

      def finished?
        @status == 'finished'
      end
    end
  end
end

module BlitzWCG
  module Handlers
    class Messages
      def initialize(ctx)
        @api = ctx[:api]
        @store = ctx[:store]
        @engine = ctx[:engine]
        @floket = ctx[:floket]
      end

      def handle(message)
        return unless message.text
        return if message.text.start_with?('/')
        uid = message.from.id
        cid = message.chat.id

        return if @store.banned?(uid)
        return if @store.muted?(uid)

        if Config.maintenance? && !Config.admin?(uid)
          return
        end

        state = @engine.load(cid)
        return unless state&.active?

        player = state.current_player
        return unless player && player['id'] == uid

        res = @engine.play_word(cid, uid, message.text)
        if res[:ok]
          text = "✅ *#{message.from.first_name}* played *#{res[:word]}* (+#{res[:points]})\n\n#{Utils::Helpers.game_status_text(res[:state])}"
          @api.send_message(chat_id: cid, text: text, parse_mode: 'Markdown', reply_markup: Utils::Helpers.game_active_keyboard)
          @engine.start_timer(cid) do |timeout_res|
            if timeout_res
              begin
                @api.send_message(chat_id: cid, text: "⏰ Time's up for #{timeout_res[:skipped]&.dig('first_name') || 'player'}!\n\n#{Utils::Helpers.game_status_text(timeout_res[:state])}", parse_mode: 'Markdown')
              rescue
              end
            end
          end
        else
          @api.send_message(chat_id: cid, text: "❌ #{res[:error]}", reply_to_message_id: message.message_id)
        end
      rescue => e
        Config.logger.error("Message handler: #{e.message}")
      end
    end
  end
end

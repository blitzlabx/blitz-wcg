require 'securerandom'

module BlitzWCG
  module Floket
    class Verifier
      def initialize(store, ttl)
        @store = store
        @ttl = ttl
        @pending = Concurrent::Map.new
      end

      def verified?(user_id)
        return true unless Config.floket_enabled
        @store.verified?(user_id)
      end

      def require_verification?(user_id, chat_type)
        return false unless Config.floket_enabled
        return false if verified?(user_id)
        true
      end

      def create_challenge(user_id)
        a = rand(2..12)
        b = rand(2..12)
        op = %w[+ - *].sample
        answer = case op
                 when '+' then a + b
                 when '-' then a - b
                 when '*' then a * b
                 end
        token = SecureRandom.hex(8)
        @pending[token] = {
          user_id: user_id,
          answer: answer,
          created_at: Time.now.to_i,
          expires: Time.now.to_i + @ttl
        }
        {
          token: token,
          question: "#{a} #{op} #{b} = ?",
          options: generate_options(answer)
        }
      end

      def verify(token, chosen, user_id)
        entry = @pending[token]
        return false unless entry
        return false if entry[:expires] < Time.now.to_i
        return false if entry[:user_id].to_i != user_id.to_i
        @pending.delete(token)
        if chosen.to_i == entry[:answer]
          @store.set_verified(user_id)
          true
        else
          false
        end
      end

      def cleanup!
        now = Time.now.to_i
        @pending.each_key do |k|
          e = @pending[k]
          @pending.delete(k) if e && e[:expires] < now
        end
      end

      private

      def generate_options(correct)
        opts = [correct]
        while opts.size < 4
          delta = rand(-8..8)
          next if delta.zero?
          candidate = correct + delta
          next if candidate < 0 || opts.include?(candidate)
          opts << candidate
        end
        opts.shuffle
      end
    end
  end
end

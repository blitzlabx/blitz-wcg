require 'securerandom'

module BlitzWCG
  module Challenge
    class Manager
      def initialize(store, engine)
        @store = store
        @engine = engine
      end

      def create(from_user, to_username)
        to_username = to_username.to_s.gsub(/^@/, '').downcase
        return { ok: false, error: 'Invalid username.' } if to_username.empty?

        existing = @store.find_challenge_by_users(from_user['id'], nil)
        # find by username later resolved

        id = SecureRandom.hex(6)
        data = {
          'id' => id,
          'from_id' => from_user['id'],
          'from_username' => from_user['username'],
          'from_name' => from_user['first_name'],
          'to_username' => to_username,
          'to_id' => nil,
          'status' => 'pending',
          'created_at' => Time.now.to_i,
          'expires_at' => Time.now.to_i + 3600
        }
        @store.save_challenge(id, data)
        { ok: true, challenge: data }
      end

      def resolve_target(challenge_id, to_user)
        c = @store.get_challenge(challenge_id)
        return { ok: false, error: 'Challenge not found.' } unless c
        return { ok: false, error: 'Already resolved.' } if c['to_id']
        return { ok: false, error: 'Expired.' } if c['expires_at'] < Time.now.to_i

        if c['to_username'].downcase != (to_user['username'] || '').downcase
          return { ok: false, error: 'This challenge is not for you.' }
        end

        c['to_id'] = to_user['id']
        c['to_name'] = to_user['first_name']
        @store.save_challenge(challenge_id, c)
        { ok: true, challenge: c }
      end

      def accept(challenge_id, user_id)
        c = @store.get_challenge(challenge_id)
        return { ok: false, error: 'Challenge not found.' } unless c
        return { ok: false, error: 'Not your challenge.' } unless c['to_id'] == user_id
        return { ok: false, error: 'Already handled.' } unless c['status'] == 'pending'
        return { ok: false, error: 'Expired.' } if c['expires_at'] < Time.now.to_i

        c['status'] = 'accepted'
        @store.save_challenge(challenge_id, c)

        from = @store.get_user(c['from_id']) || { 'id' => c['from_id'], 'username' => c['from_username'], 'first_name' => c['from_name'] }
        to = @store.get_user(c['to_id']) || { 'id' => c['to_id'], 'username' => c['to_username'], 'first_name' => c['to_name'] }

        # Create a synthetic chat_id for DM game (negative unique)
        chat_id = -("1#{c['from_id']}#{c['to_id']}".to_i % 1_000_000_000)
        result = @engine.create_dm_game(chat_id, [from, to])
        if result[:ok]
          start_res = @engine.start(chat_id, c['from_id'])
          { ok: true, challenge: c, game: start_res[:state], chat_id: chat_id }
        else
          { ok: false, error: result[:error] }
        end
      end

      def decline(challenge_id, user_id)
        c = @store.get_challenge(challenge_id)
        return { ok: false, error: 'Challenge not found.' } unless c
        return { ok: false, error: 'Not your challenge.' } unless c['to_id'] == user_id || c['from_id'] == user_id
        c['status'] = 'declined'
        @store.save_challenge(challenge_id, c)
        { ok: true, challenge: c }
      end

      def cancel(challenge_id, user_id)
        c = @store.get_challenge(challenge_id)
        return { ok: false, error: 'Not found.' } unless c
        return { ok: false, error: 'Only challenger can cancel.' } unless c['from_id'] == user_id
        c['status'] = 'cancelled'
        @store.save_challenge(challenge_id, nil)
        { ok: true }
      end

      def get(id)
        @store.get_challenge(id)
      end

      def pending_for(user_id)
        @store.all_challenges.values.select do |c|
          c['status'] == 'pending' && (c['to_id'] == user_id || (c['to_id'].nil? && c['to_username']))
        end
      end
    end
  end
end

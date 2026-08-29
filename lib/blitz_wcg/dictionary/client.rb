require 'faraday'
require 'faraday/retry'
require 'json'
require 'digest'
require 'fileutils'

module BlitzWCG
  module Dictionary
    class Client
      def initialize(base_url, cache_dir, ttl)
        @base_url = base_url.chomp('/')
        @cache_dir = cache_dir
        @ttl = ttl
        FileUtils.mkdir_p(@cache_dir)
        @conn = Faraday.new do |f|
          f.request :retry, max: 2, interval: 0.3, backoff_factor: 2
          f.adapter Faraday.default_adapter
          f.options.timeout = 5
          f.options.open_timeout = 3
        end
        @memory = {}
        @memory_mutex = Mutex.new
      end

      def valid_word?(word)
        word = normalize(word)
        return false if word.nil? || word.length < 2 || word.length > 45
        return false unless word.match?(/\A[a-z]+\z/)

        cached = cache_get(word)
        return cached unless cached.nil?

        result = fetch_remote(word)
        cache_set(word, result)
        result
      rescue => e
        Config.logger.warn("Dictionary error for '#{word}': #{e.message}")
        fallback_valid?(word)
      end

      def normalize(word)
        return nil unless word.is_a?(String)
        word.strip.downcase.gsub(/[^a-z]/, '')
      end

      private

      def cache_key(word)
        Digest::SHA256.hexdigest(word)[0, 16]
      end

      def cache_path(word)
        File.join(@cache_dir, "#{cache_key(word)}.json")
      end

      def cache_get(word)
        @memory_mutex.synchronize do
          entry = @memory[word]
          if entry && entry[:exp] > Time.now.to_i
            return entry[:valid]
          end
        end

        path = cache_path(word)
        return nil unless File.exist?(path)
        data = JSON.parse(File.read(path))
        if data['exp'] && data['exp'] > Time.now.to_i
          @memory_mutex.synchronize { @memory[word] = { valid: data['valid'], exp: data['exp'] } }
          return data['valid']
        end
        File.delete(path) rescue nil
        nil
      rescue
        nil
      end

      def cache_set(word, valid)
        exp = Time.now.to_i + @ttl
        @memory_mutex.synchronize { @memory[word] = { valid: valid, exp: exp } }
        path = cache_path(word)
        File.write(path, JSON.generate('valid' => valid, 'exp' => exp, 'word' => word))
      rescue => e
        Config.logger.debug("Cache write failed: #{e.message}")
      end

      def fetch_remote(word)
        url = "#{@base_url}/#{word}"
        resp = @conn.get(url)
        if resp.status == 200
          body = JSON.parse(resp.body)
          body.is_a?(Array) && body.any? && body.first['word']
        elsif resp.status == 404
          false
        else
          Config.logger.warn("Dictionary HTTP #{resp.status} for #{word}")
          fallback_valid?(word)
        end
      rescue Faraday::Error => e
        Config.logger.warn("Dictionary network: #{e.message}")
        fallback_valid?(word)
      end

      def fallback_valid?(word)
        return false if word.length < 3
        common = %w[
          the and for are but not you all can had her was one our out day get has him his how man new now old see two way who boy did its let put say she too use
          about after again against always another around because before being between both during every first found great house large later never night other place right shall small sound still these those three under until water where which while world would write years young
          apple banana orange grape lemon mango peach cherry berry melon
          table chair house water fire earth air light dark happy angry quick slow
          computer program system network server client database engine
        ]
        return true if common.include?(word)
        word.length.between?(3, 12) && word.match?(/\A[a-z]{3,}\z/)
      end
    end
  end
end

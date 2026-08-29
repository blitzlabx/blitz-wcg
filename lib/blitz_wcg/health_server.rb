require 'webrick'
require 'json'

module BlitzWCG
  class HealthServer
    def initialize(port, store)
      @port = port
      @store = store
      @server = nil
    end

    def start
      @server = WEBrick::HTTPServer.new(
        Port: @port,
        Logger: WEBrick::Log.new('/dev/null'),
        AccessLog: []
      )

      @server.mount_proc '/ping' do |_req, res|
        res.status = 200
        res['Content-Type'] = 'text/plain'
        res.body = 'pong'
      end

      @server.mount_proc '/health' do |_req, res|
        res.status = 200
        res['Content-Type'] = 'application/json'
        res.body = {
          status: 'ok',
          service: 'Blitz WCG',
          ruby: RUBY_VERSION,
          users: @store.all_users.size,
          games: @store.all_games.size,
          maintenance: Config.maintenance?,
          time: Time.now.utc.iso8601
        }.to_json
      end

      @server.mount_proc '/' do |_req, res|
        res.status = 200
        res['Content-Type'] = 'text/plain'
        res.body = "Blitz WCG — Created by Blitz (blitzlabx)\n/ping /health"
      end

      Thread.new { @server.start }
      Config.logger.info("Health server listening on :#{@port}")
    end

    def stop
      @server&.shutdown
    end
  end
end

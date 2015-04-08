require 'memcached'
require 'rack/session/abstract/id'
require 'rack/session/memcached/version'

module Rack
  module Session
    class Memcached < Abstract::ID
      DEFAULT_OPTIONS = Abstract::ID::DEFAULT_OPTIONS.merge(
        namespace: 'rack.session',
        memcached_server: 'localhost:11211',
        codec: ::Memcached::MarshalCodec,
        prefix_delimiter: ':'
      )

      attr_reader :mutex, :pool

      def initialize(app, options = {})
        super
        @mutex = Mutex.new
        # For compatibility other Rack::Session modules
        unless @default_options.key?  :prefix_key
          @default_options[:prefix_key] = @default_options[:namespace]
        end
        mserv = @default_options[:memcached_server]
        mopts = @default_options.reject{|k, v| !::Memcached::DEFAULTS.key? k}
        @pool = options[:cache] || ::Memcached.new(mserv, mopts)
      end

      def safe_get(sid, decode = true)
        begin
          @pool.get(sid, decode)
        rescue ::Memcached::NotFound
          nil
        end
      end

      def generate_sid
        loop do
          sid = super
          break sid if safe_get(sid).nil?
        end
      end

      def create_new_session
        sid, session = generate_sid, {}
        @pool.add sid, session
        [sid, session]
      end

      def get_session(env, sid)
        with_lock(env) do
          if sid.nil? || sid == ""
            sid, session = create_new_session
          else
            session = safe_get(sid)
            sid, session = create_new_session if session.nil?
          end
          [sid, session]
        end
      end

      def set_session(env, session_id, new_session, options)
        expiry = options[:expire_after]
        expiry = expiry.nil? ? 0 : expiry + 1
        with_lock(env) do
          @pool.set session_id, new_session, expiry
          session_id
        end
      end

      def destroy_session(env, session_id, options)
        with_lock(env) do
          @pool.delete session_id
          generate_sid unless options[:drop]
        end
      end

      def with_lock(env, default = nil)
        @mutex.lock if env['rack.multithread']
        yield
      rescue ::Memcached::Error
        warn $!
        default
      ensure
        @mutex.unlock if @mutex.locked?
      end

      def clone
        me = super
        memcached = @pool.clone
        me.instance_variable_set('@pool', memcached)
        me
      end
    end
  end

end

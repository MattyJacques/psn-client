# frozen_string_literal: true

module PSN
  module Client
    # Faraday middleware that hands each completed response to a callback. Auth uses it to
    # keep the token response, because oauth2 parses the body before returning it and a
    # JSON::ParserError raised there carries no response.
    class ResponseRecorder
      # oauth2's default Faraday stack (form-encoded requests, default adapter) plus a recorder.
      def self.default_stack(builder, callback)
        builder.request(:url_encoded)
        builder.use(self, callback)
        builder.adapter(Faraday.default_adapter)
      end

      def initialize(app, callback)
        @app = app
        @callback = callback
      end

      def call(env)
        @app.call(env).on_complete { |completed| @callback.call(completed.response) }
      end
    end
  end
end

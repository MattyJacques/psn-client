# frozen_string_literal: true

# Helpers for spec/integration, where WebMock intercepts the HTTP requests the gem
# really makes and answers them with the sanitized responses in spec/fixtures.
module HTTPIntegration
  FIXTURES = File.expand_path('../fixtures', __dir__)
  MOBILE = 'https://m.np.playstation.com/api'
  JSON_HEADERS = { 'Content-Type' => 'application/json' }.freeze

  # The raw fixture body, exactly as it would arrive on the wire.
  def fixture(name)
    File.read(File.join(FIXTURES, "#{name}.json"))
  end

  def json_fixture(name, status: 200, headers: {})
    { status: status, body: fixture(name), headers: JSON_HEADERS.merge(headers) }
  end
end

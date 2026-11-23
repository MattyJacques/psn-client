# frozen_string_literal: true

# Builds real Net::HTTPResponse objects so specs exercise status, header and body handling.
module HTTPResponses
  def http_response(code, body = '', headers = {})
    klass = Net::HTTPResponse::CODE_TO_OBJ.fetch(code.to_s)
    response = klass.new('1.1', code.to_s, klass.name.delete_prefix('Net::HTTP'))
    headers.each { |name, value| response[name] = value }
    response.instance_variable_set(:@body, body)
    response.instance_variable_set(:@read, true)
    response
  end
end

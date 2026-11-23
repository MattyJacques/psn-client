# frozen_string_literal: true

module PSN
  module Client
    # Argument checks shared by the paginated Trophies, Users and Account calls
    module Pagination
      private

      def validate_page_param!(name, value, min:, max: nil)
        return if value.is_a?(Integer) && value >= min && (max.nil? || value <= max)

        range = max ? "between #{min} and #{max}" : "at least #{min}"
        raise ArgumentError, "#{name} must be an Integer #{range}, got #{value.inspect}"
      end
    end
  end
end

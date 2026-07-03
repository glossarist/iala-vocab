# frozen_string_literal: true

require "iala_vocab"
require "tmpdir"

RSpec.configure do |config|
  config.expect_with :rspec do |c|
    c.syntax = %i[should expect]
  end
  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end
end
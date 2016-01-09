require 'minitest/autorun'
require 'minispec-metadata'
require 'vcr'
require 'minitest-vcr'
require 'webmock/minitest'
require 'mocha/setup'

require 'miasma'
require 'miasma/specs'

VCR.configure do |c|
  c.cassette_library_dir = 'test/cassettes'
  c.hook_into :webmock
  c.default_cassette_options = {
    :match_requests_on => [:method, :body,
      VCR.request_matchers.uri_without_params(

      )
    ]
  }
  c.filter_sensitive_data('AZURE_KEY'){ ENV['AZURE_KEY'] }
end

MinitestVcr::Spec.configure!

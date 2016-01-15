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
    :match_requests_on => [:method, :body, :path]
  }
  c.filter_sensitive_data('MIASMA_AZURE_CLIENT_ID'){ ENV['MIASMA_AZURE_CLIENT_ID'] }
  c.filter_sensitive_data('MIASMA_AZURE_CLIENT_SECRET'){ ENV['MIASMA_AZURE_CLIENT_SECRET'] }
  c.filter_sensitive_data('MIASMA_AZURE_SUBSCRIPTION_ID'){ ENV['MIASMA_AZURE_SUBSCRIPTION_ID'] }
  c.filter_sensitive_data('MIASMA_AZURE_TENANT_ID'){ ENV['MIASMA_AZURE_TENANT_ID'] }
  c.filter_sensitive_data('MIASMA_AZURE_BLOB_ACCOUNT_NAME'){ ENV['MIASMA_AZURE_BLOB_ACCOUNT_NAME'] }
  c.filter_sensitive_data('MIASMA_AZURE_BLOB_SECRET_KEY'){ ENV['MIASMA_AZURE_BLOB_SECRET_KEY'] }
  c.filter_sensitive_data('MIASMA_AZURE_REGION'){ ENV['MIASMA_AZURE_REGION'] }
end

MinitestVcr::Spec.configure!

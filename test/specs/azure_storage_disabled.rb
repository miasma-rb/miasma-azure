require_relative '../helper'
require 'miasma/contrib/azure'

describe Miasma::Models::Storage::Azure do

  before do
    @storage = Miasma.api(
      :type => :storage,
      :provider => :azure,
      :credentials => {
      }
    )
  end

  let(:storage){ @storage }

  instance_exec(&MIASMA_STORAGE_ABSTRACT)

end

require_relative '../helper'
require 'miasma/contrib/azure'

describe Miasma::Models::Orchestration::Azure do

  before do
    @orchestration = Miasma.api(
      :type => :orchestration,
      :provider => :azure,
      :credentials => {
      }
    )
  end

  let(:orchestration){ @orchestration }
  let(:build_args){
    Smash.new(
      :name => 'miasma-test-stack',
      :template => {
      },
      :parameters => {
      }
    )
  }

  instance_exec(&MIASMA_ORCHESTRATION_ABSTRACT)

end

require 'miasma'

module Miasma
  module Models
    class Orchestration
      class Azure < Orchestration

        include Contrib::AzureApiCore::ApiCommon

        def orchestration_api_version
          '2015-01-01'
        end

        def orchestration_root_path
          "/subscriptions/#{azure_subscription_id}/resourcegroups/#{azure_resource_group}/providers/microsoft.resources/deployments"
        end

        # Fetch stacks or update provided stack data
        #
        # @param stack [Models::Orchestration::Stack]
        # @return [Array<Models::Orchestration::Stack>]
        def load_stack_data(stack=nil)
          result = request(
            :method => :get
          )
          stacks = result.fetch(:body, :value, []).map do |item|
            new_stack = Stack.new(self)
            current_state = case item.get(:properties, :provisioningState)
                            when 'Failed', 'Canceled'
                              :create_failed
                            when 'Succeeded'
                              :create_complete
                            when 'Deleting'
                              :delete_in_progress
                            when 'Deleted'
                              :delete_complete
                            else
                              :create_in_progress
                            end
            new_stack.load_data(
              :id => item[:id],
              :name => item[:name],
              :parameters => Smash[
                item.fetch(:parameters, {}).map do |p_name, p_value|
                  [p_name, p_value[:value]]
                end
              ],
              :outputs => item.fetch(:outputs, {}).map{ |o_name, o_value|
                Smash.new(:key => o_name, :value => o_value[:value])
              },
              :state => current_state,
              :status => item.get(:properties, :provisioningState),
              :custom => item
            ).valid_state
          end
          stack ? stacks.first : stacks
        end

        # Save the stack
        #
        # @param stack [Models::Orchestration::Stack]
        # @return [Models::Orchestration::Stack]
        def stack_save(stack)
          request(
            :path => stack.name,
            :method => :put,
            :expects => 201,
            :json => {
              :properties => {
                :template => stack.template,
                :parameters => stack.parameters,
                :mode => 'Complete'
              }
            }
          )
          stack
        end


        # Reload the stack data from the API
        #
        # @param stack [Models::Orchestration::Stack]
        # @return [Models::Orchestration::Stack]
        def stack_reload(stack)
          if(stack.persisted?)
            ustack = Stack.new(self)
            ustack.id = stack.id
            load_stack_data(ustack)
            if(ustack.data[:name])
              stack.load_data(ustack.attributes).valid_state
            else
              stack.status = 'Deleted'
              stack.state = :delete_complete
              stack.valid_state
            end
          end
          stack
        end

        # Delete the stack
        #
        # @param stack [Models::Orchestration::Stack]
        # @return [TrueClass, FalseClass]
        def stack_destroy(stack)
          if(stack.persisted?)
            request(
              :method => :delete,
              :expects => 202,
              :path => stack.name
            )
            true
          else
            false
          end
        end

        # Fetch stack template
        #
        # @param stack [Stack]
        # @return [Smash] stack template
        def stack_template_load(stack)
          if(stack.persisted?)
            result = request(
              :method => :post,
              :path => '/',
              :form => Smash.new(
                'Action' => 'GetTemplate',
                'StackName' => stack.id
              )
            )
            MultiJson.load(
              result.get(:body, 'GetTemplateResponse', 'GetTemplateResult', 'TemplateBody')
            ).to_smash
          else
            Smash.new
          end
        end

        # Validate stack template
        #
        # @param stack [Stack]
        # @return [NilClass, String] nil if valid, string error message if invalid
        def stack_template_validate(stack)
          begin
            result = request(
              :method => :post,
              :path => '/',
              :form => Smash.new(
                'Action' => 'ValidateTemplate',
                'TemplateBody' => MultiJson.dump(stack.template)
              )
            )
            nil
          rescue Error::ApiError::RequestError => e
            MultiXml.parse(e.response.body.to_s).to_smash.get(
              'ErrorResponse', 'Error', 'Message'
            )
          end
        end

        # Return single stack
        #
        # @param ident [String] name or ID
        # @return [Stack]
        def stack_get(ident)
          i = Stack.new(self)
          i.id = ident
          i.reload
          i.name ? i : nil
        end

        # Return all stacks
        #
        # @param options [Hash] filter
        # @return [Array<Models::Orchestration::Stack>]
        # @todo check if we need any mappings on state set
        def stack_all
          load_stack_data
        end

        # Return all resources for stack
        #
        # @param stack [Models::Orchestration::Stack]
        # @return [Array<Models::Orchestration::Stack::Resource>]
        def resource_all(stack)
          results = all_result_pages(nil, :body, 'DescribeStackResourcesResponse', 'DescribeStackResourcesResult', 'StackResources', 'member') do |options|
            request(
              :method => :post,
              :path => '/',
              :form => options.merge(
                Smash.new(
                  'Action' => 'DescribeStackResources',
                  'StackName' => stack.id
                )
              )
            )
          end.map do |res|
            Stack::Resource.new(
              stack,
              :id => res['PhysicalResourceId'],
              :name => res['LogicalResourceId'],
              :logical_id => res['LogicalResourceId'],
              :type => res['ResourceType'],
              :state => res['ResourceStatus'].downcase.to_sym,
              :status => res['ResourceStatus'],
              :status_reason => res['ResourceStatusReason'],
              :updated => res['Timestamp']
            ).valid_state
          end
        end

        # Reload the stack resource data from the API
        #
        # @param resource [Models::Orchestration::Stack::Resource]
        # @return [Models::Orchestration::Resource]
        def resource_reload(resource)
          resource.stack.resources.reload
          resource.stack.resources.get(resource.id)
        end

        # Return all events for stack
        #
        # @param stack [Models::Orchestration::Stack]
        # @return [Array<Models::Orchestration::Stack::Event>]
        def event_all(stack, evt_id=nil)
          results = all_result_pages(nil, :body, 'DescribeStackEventsResponse', 'DescribeStackEventsResult', 'StackEvents', 'member') do |options|
            request(
              :method => :post,
              :path => '/',
              :form => options.merge(
                'Action' => 'DescribeStackEvents',
                'StackName' => stack.id
              )
            )
          end
          events = results.map do |event|
            Stack::Event.new(
              stack,
              :id => event['EventId'],
              :resource_id => event['PhysicalResourceId'],
              :resource_name => event['LogicalResourceId'],
              :resource_logical_id => event['LogicalResourceId'],
              :resource_state => event['ResourceStatus'].downcase.to_sym,
              :resource_status => event['ResourceStatus'],
              :resource_status_reason => event['ResourceStatusReason'],
              :time => Time.parse(event['Timestamp'])
            ).valid_state
          end
          if(evt_id)
            idx = events.index{|d| e.id == evt_id}
            idx = idx ? idx + 1 : 0
            events.slice(idx, events.size)
          else
            events
          end
        end

        # Return all new events for event collection
        #
        # @param events [Models::Orchestration::Stack::Events]
        # @return [Array<Models::Orchestration::Stack::Event>]
        def event_all_new(events)
          event_all(events.stack, events.all.first.id)
        end

        # Reload the stack event data from the API
        #
        # @param resource [Models::Orchestration::Stack::Event]
        # @return [Models::Orchestration::Event]
        def event_reload(event)
          event.stack.events.reload
          event.stack.events.get(event.id)
        end

      end
    end
  end
end

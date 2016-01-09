require 'miasma'

module Miasma
  module Models
    class Orchestration
      class Azure < Orchestration

        include Contrib::AzureApiCore::ApiCommon

        STATUS_MAP = Smash.new(
          'Failed' => :create_failed,
          'Canceled' => :create_failed,
          'Succeeded' => :create_complete,
          'Deleting' => :delete_in_progress,
          'Deleted' => :delete_complete
        )

        def orchestration_api_version
          '2015-01-01'
        end

        def orchestration_root_path
          "/subscriptions/#{azure_subscription_id}/resourcegroups/#{azure_resource_group}/providers/microsoft.resources/deployments"
        end

        def status_to_state(val)
          STATUS_MAP.fetch(val, :create_in_progress)
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
              :state => status_to_state(item.get(:properties, :provisioningState)),
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
          stack.custom.fetch(:properties, :dependencies, []).map do |res|
            evt = stack.events.all.detect{|ev| ev.resource_id == res[:id]}
            Stack::Resource.new(
              stack,
              :id => res[:id],
              :type => res[:resourceType],
              :name => res[:resourceName],
              :logical_id => res[:resourceName],
              :state => evt.resource_state,
              :status => evt.resource_status,
              :status_reason => evt.resource_status_reason,
              :updated => evt.time
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
          result = request(
            :path => [stack.name, 'operations'].join('/')
          )
          events = result.get(:body, :value).map do |event|
            Stack::Event.new(
              stack,
              :id => event[:operationId],
              :resource_id => event.get(:properties, :targetResource, :id),
              :resource_name => event.get(:properties, :targetResource, :resourceName),
              :resource_state => status_to_state(event.get(:properties, :provisioningState)),
              :resource_status => event.get(:properties, :provisioningState),
              :resource_status_reason => event.get(:properties, :statusCode),
              :time => Time.parse(event.get(:properties, :timestamp))
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

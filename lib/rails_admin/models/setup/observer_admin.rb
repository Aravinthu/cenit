module RailsAdmin
  module Models
    module Setup
      module ObserverAdmin
        extend ActiveSupport::Concern

        included do
          rails_admin do
            navigation_label 'Workflows'
            weight 511
            label 'Data Event'
            object_label_method { :custom_title }

            wizard_steps do
              steps =
                {
                  start:
                    {
                      :label => I18n.t('admin.config.observer.wizard.start.label'),
                      :description => I18n.t('admin.config.observer.wizard.start.description')
                    },
                  end:
                    {
                      label: I18n.t('admin.config.observer.wizard.end.label'),
                      description: I18n.t('admin.config.observer.wizard.end.description')
                    }
                }
            end

            current_step do
              obj = bindings[:object]
              if obj.data_type.blank?
                :start
              else
                :end
              end
            end

            edit do
              field :namespace, :enum_edit
              field :name
              field :data_type do
                inline_add false
                inline_edit false
                associated_collection_scope do
                  data_type = bindings[:object].data_type
                  Proc.new { |scope|
                    if data_type
                      scope.where(id: data_type.id)
                    else
                      scope
                    end
                  }
                end
                help 'Required'
              end
              field :trigger_evaluator do
                visible { (obj = bindings[:object]).data_type.blank? || obj.trigger_evaluator.present? || obj.triggers.nil? }
                associated_collection_scope do
                  Proc.new { |scope|
                    scope.all.or(:parameters.with_size => 1).or(:parameters.with_size => 2)
                  }
                end
              end
              field :triggers do
                visible do
                  bindings[:controller].instance_variable_set(:@_data_type, data_type = bindings[:object].data_type)
                  bindings[:controller].instance_variable_set(:@_update_field, 'data_type_id')
                  data_type.present? && !bindings[:object].trigger_evaluator.present?
                end
                partial 'form_triggers'
                help false
              end
            end

            show do
              field :namespace
              field :name
              field :data_type
              field :triggers
              field :trigger_evaluator

              field :_id
              field :created_at
              #field :creator
              field :updated_at
              #field :updater
            end

            fields :namespace, :name, :data_type, :triggers, :trigger_evaluator, :updated_at
          end
        end

      end
    end
  end
end

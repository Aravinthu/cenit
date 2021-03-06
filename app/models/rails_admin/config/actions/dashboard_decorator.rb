module RailsAdmin
  module Config
    module Actions
      Dashboard.class_eval do
        register_instance_option :controller do
          proc do
            @history = @auditing_adapter && @auditing_adapter.latest || []
            if @action.statistics?
              #Patch
              @model_configs = {}
              @abstract_models =
                if current_user
                  RailsAdmin::Config.visible_models(controller: self).collect(&:abstract_model).select do |absm|
                    ((model = absm.model) rescue nil) &&
                      (model.is_a?(Mongoff::Model) || model.include?(AccountScoped) || [Account].include?(model)) &&
                      (@model_configs[absm.model_name] = absm.config)
                  end
                else
                  Setup::Models.collect { |m| RailsAdmin::Config.model(m) }.select(&:visible).collect do |config|
                    absm = config.abstract_model
                    @model_configs[absm.model_name] = config
                    absm
                  end
                end
              @most_recent_changes = {}
              @count = {}
              @max = 0
              #Patch
              if current_user
                @abstract_models.each do |t|
                  scope = @authorization_adapter && @authorization_adapter.query(:index, t)
                  current_count = t.count({ cache: true }, scope)
                  @max = current_count > @max ? current_count : @max
                  @count[t.model.name] = current_count
                  # Patch
                  # next unless t.properties.detect { |c| c.name == :updated_at }
                  # @most_recent_changes[t.model.name] = t.first(sort: "#{t.table_name}.updated_at").try(:updated_at)
                end
              else
                @abstract_models.each do |absm|
                  current_count = absm.model.super_count
                  @max = current_count > @max ? current_count : @max
                  @count[absm.model.name] = current_count
                end
              end
            end
            render @action.template_name, status: (flash[:error].present? ? :not_found : 200)
          end
        end

        register_instance_option :link_icon do
          'fa fa-dashboard'
        end
      end
    end
  end
end

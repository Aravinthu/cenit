module Setup
  class Crossing < Setup::Task
    include Setup::BulkableTask
    include RailsAdmin::Models::Setup::CrossingAdmin

    def origin_from(message)
      origin = message['origin'].to_s.to_sym
      model = data_type_from(message).records_model
      if model < CrossOrigin::Document
        fail "Invalid origin :#{origin} for model #{model}" unless model.origins.include?(origin)
      end
      fail "Unauthorized crossing origin :#{origin}" unless authorized_crossing_origins.include?(origin)
      origin
    end

    def run(message)
      origin = origin_from(message)
      criteria = objects_from(message)
      model = data_type.records_model
      if model < CrossOrigin::Document
        criteria = criteria.and(:origin.in => authorized_crossing_origins)
        if model < Trackable
          criteria = criteria.with_tracking
        end
        criteria.cross(origin) do |_, non_tracked_ids|
          if non_tracked_ids.present?
            Account.each do |account|
              if account == Account.current
                model.clear_pins_for(account, non_tracked_ids)
              else
                model.clear_config_for(account, non_tracked_ids)
              end
            end
          end
        end
      end
      if model.instance_methods.include?(:cross_to)
        criteria.each { |record| record.cross_to(origin, :origin.in => authorized_crossing_origins) }
      end
    end

    def authorized_crossing_origins
      self.class.authorized_crossing_origins
    end

    class << self

      def authorized_crossing_origins
        if User.current.super_admin?
          CrossOrigin.names
        else
          [:default, :owner]
        end
      end
    end
  end
end

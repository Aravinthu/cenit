module Setup
  class Updater < Translator
    include RailsAdmin::Models::Setup::UpdaterAdmin

    transformation_type :Update
    allow :new

    build_in_data_type.with(:namespace, :name, :target_data_type, :discard_events, :style,:source_handler, :snippet).referenced_by(:namespace, :name)

  end
end

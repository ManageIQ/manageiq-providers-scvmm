module ManageIQ
  module Providers
    module Scvmm
      class Engine < ::Rails::Engine
        isolate_namespace ManageIQ::Providers::Scvmm

        config.autoload_paths << root.join('lib').to_s

        def self.vmdb_plugin?
          true
        end

        def self.plugin_name
          _('Microsoft SCVMM Provider')
        end

        def self.init_loggers
          $scvmm_log ||= Vmdb::Loggers.create_logger("scvmm.log")
        end

        def self.apply_logger_config(config)
          Vmdb::Loggers.apply_config_value(config, $scvmm_log, :level_scvmm)
        end
      end
    end
  end
end

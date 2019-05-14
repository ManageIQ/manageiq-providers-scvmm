module ManageIQ
  module Providers
    module Scvmm
      class Engine < ::Rails::Engine
        isolate_namespace ManageIQ::Providers::Scvmm

        def self.vmdb_plugin?
          true
        end

        def self.plugin_name
          _('Microsoft SCVMM Provider')
        end
      end
    end
  end
end

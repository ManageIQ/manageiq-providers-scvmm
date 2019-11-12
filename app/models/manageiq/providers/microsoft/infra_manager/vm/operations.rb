module ManageIQ::Providers::Microsoft::InfraManager::Vm::Operations
  extend ActiveSupport::Concern

  include_concern 'Guest'
end

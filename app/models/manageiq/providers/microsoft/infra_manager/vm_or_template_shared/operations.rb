module ManageIQ::Providers::Microsoft::InfraManager::VmOrTemplateShared::Operations
  extend ActiveSupport::Concern

  include_concern 'Power'
end

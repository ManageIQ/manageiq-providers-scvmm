module ManageIQ::Providers::Microsoft::InfraManager::VmOrTemplateShared
  extend ActiveSupport::Concern
  include_concern 'Scanning'
  include_concern 'Operations'
end

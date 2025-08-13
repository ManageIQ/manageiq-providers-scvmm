class ManageIQ::Providers::Microsoft::InfraManager::Provision < ::MiqProvision
  include Cloning
  include Placement
  include StateMachine
end

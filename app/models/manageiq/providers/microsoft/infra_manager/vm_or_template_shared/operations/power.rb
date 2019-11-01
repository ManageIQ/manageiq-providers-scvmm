module ManageIQ::Providers::Microsoft::InfraManager::VmOrTemplateShared::Operations::Power
  extend ActiveSupport::Concern

  def raw_start
    run_command_via_parent(:vm_start)
  end

  def raw_stop
    run_command_via_parent(:vm_stop)
  end
end

module ManageIQ::Providers::Microsoft::InfraManager::Vm::Operations::Guest
  extend ActiveSupport::Concern

  def raw_shutdown_guest
    run_command_via_parent(:vm_shutdown_guest)
  end

  def raw_reboot_guest
    run_command_via_parent(:vm_reboot_guest)
  end

  def raw_reset
    run_command_via_parent(:vm_reset)
  end
end

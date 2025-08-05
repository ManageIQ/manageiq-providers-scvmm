class ManageIQ::Providers::Microsoft::InfraManager::Vm < ManageIQ::Providers::InfraManager::Vm
  include ManageIQ::Providers::Microsoft::InfraManager::VmOrTemplateShared
  include Operations

  supports :reboot_guest do
    if !supports?(:control)
      unsupported_reason(:control)
    elsif current_state != 'on'
      _('The VM is not powered on')
    end
  end

  supports :shutdown_guest do
    if !supports?(:control)
      unsupported_reason(:control)
    elsif current_state != 'on'
      _('The VM is not powered on')
    end
  end

  supports :reset do
    if !supports?(:control)
      unsupported_reason(:control)
    elsif current_state != 'on'
      _('The VM is not powered on')
    end
  end

  POWER_STATES = {
    "Running"  => "on",
    "Paused"   => "suspended",
    "Saved"    => "suspended",
    "PowerOff" => "off",
  }.freeze

  def self.calculate_power_state(raw_power_state)
    POWER_STATES[raw_power_state] || super
  end

  def proxies4job(_job = nil)
    {
      :proxies => [MiqServer.my_server],
      :message => 'Perform SmartState Analysis on this VM'
    }
  end

  def has_active_proxy?
    true
  end

  def has_proxy?
    true
  end

  def self.display_name(number = 1)
    n_('Virtual Machine (Microsoft)', 'Virtual Machines (Microsoft)', number)
  end
end

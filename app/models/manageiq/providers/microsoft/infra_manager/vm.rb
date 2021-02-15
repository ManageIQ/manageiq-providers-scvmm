class ManageIQ::Providers::Microsoft::InfraManager::Vm < ManageIQ::Providers::InfraManager::Vm
  include_concern 'ManageIQ::Providers::Microsoft::InfraManager::VmOrTemplateShared'
  include_concern 'Operations'

  supports_not :migrate, :reason => _("Migrate operation is not supported.")
  supports_not :publish

  supports :reboot_guest do
    unsupported_reason_add(:reboot_guest, unsupported_reason(:control)) unless supports?(:control)
    unless current_state == 'on'
      unsupported_reason_add(:reboot_guest, _('The VM is not powered on'))
    end
  end

  supports :shutdown_guest do
    unsupported_reason_add(:shutdown_guest, unsupported_reason(:control)) unless supports?(:control)
    unless current_state == 'on'
      unsupported_reason_add(:shutdown_guest, _('The VM is not powered on'))
    end
  end

  supports :reset do
    unsupported_reason_add(:reset, unsupported_reason(:control)) unless supports?(:control)
    unless current_state == 'on'
      unsupported_reason_add(:reset, _('The VM is not powered on'))
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

class ManageIQ::Providers::Microsoft::InfraManager::Template < ManageIQ::Providers::InfraManager::Template
  include ManageIQ::Providers::Microsoft::InfraManager::VmOrTemplateShared

  supports :provisioning do
    if !ext_management_system
      _('not connected to ems')
    elsif !ext_management_system.supports?(:provisioning)
      ext_management_system.unsupported_reason(:provisioning)
    end
  end

  supports_not :clone

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
end

class ManageIQ::Providers::Microsoft::InfraManager::Host < ::Host
  def self.display_name(number = 1)
    n_('Host (Microsoft)', 'Hosts (Microsoft)', number)
  end
end

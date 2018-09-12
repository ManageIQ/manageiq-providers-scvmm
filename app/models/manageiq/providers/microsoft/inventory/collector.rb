class ManageIQ::Providers::Microsoft::Inventory::Collector < ManageIQ::Providers::Inventory::Collector
  require_nested :InfraManager

  private

  def log_header
    "EMS: [#{manager.name}], id: [#{manager.id}]"
  end
end

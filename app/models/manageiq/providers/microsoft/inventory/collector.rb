class ManageIQ::Providers::Microsoft::Inventory::Collector < ManagerRefresh::Inventory::Collector
  require_nested :InfraManager

  private

  def log_header
    "EMS: [#{manager.name}], id: [#{manager.id}]"
  end
end

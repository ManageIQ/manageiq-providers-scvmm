class ManageIQ::Providers::Microsoft::Inventory::Parser < ManagerRefresh::Inventory::Parser
  private

  def log_header
    "EMS: [#{manager.name}], id: [#{manager.id}]"
  end
end

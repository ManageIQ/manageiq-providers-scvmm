class ManageIQ::Providers::Microsoft::Inventory::Parser < ManageIQ::Providers::Inventory::Parser
  private

  def log_header
    "EMS: [#{manager.name}], id: [#{manager.id}]"
  end
end

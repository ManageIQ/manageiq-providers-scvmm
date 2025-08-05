class ManageIQ::Providers::Microsoft::Inventory::Collector < ManageIQ::Providers::Inventory::Collector
  private

  def log_header
    "EMS: [#{manager.name}], id: [#{manager.id}]"
  end
end

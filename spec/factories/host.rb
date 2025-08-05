FactoryBot.define do
  factory :host_microsoft, :parent => :host, :class => "ManageIQ::Providers::Microsoft::InfraManager::Host" do
    vmm_vendor  { "microsoft" }
    vmm_product { "Hyper-V" }
  end
end

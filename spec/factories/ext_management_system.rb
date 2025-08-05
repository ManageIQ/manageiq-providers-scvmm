FactoryBot.define do
  factory :ems_microsoft,
          :aliases => ["manageiq/providers/microsoft/infra_manager"],
          :class   => "ManageIQ::Providers::Microsoft::InfraManager",
          :parent  => :ems_infra

  factory :ems_microsoft_with_authentication,
          :parent => :ems_microsoft do
    authtype { "default" }
  end
end

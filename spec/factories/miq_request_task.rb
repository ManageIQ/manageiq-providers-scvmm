FactoryBot.define do
  factory :miq_provision_microsoft,      :parent => :miq_provision,        :class => "ManageIQ::Providers::Microsoft::InfraManager::Provision"
end

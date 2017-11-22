describe :placeholders do
  include_examples :placeholders, ManageIQ::Providers::Scvmm::Engine.root.join('locale').to_s
end

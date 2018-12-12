describe ManageIQ::Providers::Microsoft::InfraManager::ProvisionWorkflow do
  include Spec::Support::WorkflowHelper

  let(:admin)    { FactoryBot.create(:user_with_group) }
  let(:ems)      { FactoryBot.create(:ems_microsoft) }
  let(:template) { FactoryBot.create(:template_microsoft, :name => "template", :ext_management_system => ems) }

  before do
    allow_any_instance_of(described_class).to receive(:update_field_visibility)
  end

  it "pass platform attributes to automate" do
    stub_dialog
    assert_automate_dialog_lookup(admin, 'infra', 'microsoft')

    described_class.new({}, admin.userid)
  end

  describe "#load_hosts_vlans" do
    let(:host)        { FactoryBot.create(:host_with_ref, :switches => [switch]) }
    let(:switch)      { FactoryBot.create(:switch) }
    let!(:lan_parent) { FactoryBot.create(:lan, :switch => switch) }
    let!(:lan)        { FactoryBot.create(:lan, :parent => lan_parent, :switch => switch) }

    it "includes parent lans" do
      stub_dialog
      prov_workflow = described_class.new({}, admin.userid)
      lan_for_host = prov_workflow.load_hosts_vlans([host], {}).detect(&:parent)
      expect(lan_for_host).to be_a(Lan)
      expect(lan_for_host.parent).to be_a(Lan)
    end
  end

  describe "#make_request" do
    let(:alt_user) { FactoryBot.create(:user_with_group) }
    it "creates and update a request" do
      EvmSpecHelper.local_miq_server
      stub_dialog(:get_pre_dialogs)
      stub_dialog(:get_dialogs)

      # if running_pre_dialog is set, it will run 'continue_request'
      workflow = described_class.new(values = {:running_pre_dialog => false}, admin)

      expect(AuditEvent).to receive(:success).with(
        :event        => "vm_provision_request_created",
        :target_class => "Vm",
        :userid       => admin.userid,
        :message      => "VM Provisioning requested by <#{admin.userid}> for Vm:#{template.id}"
      )

      # creates a request
      stub_get_next_vm_name

      # the dialogs populate this
      values.merge!(:src_vm_id => template.id, :vm_tags => [])

      request = workflow.make_request(nil, values)

      expect(request).to be_valid
      expect(request).to be_a_kind_of(MiqProvisionRequest)
      expect(request.request_type).to eq("template")
      expect(request.description).to eq("Provision from [#{template.name}] to [New VM]")
      expect(request.requester).to eq(admin)
      expect(request.userid).to eq(admin.userid)
      expect(request.requester_name).to eq(admin.name)

      # updates a request

      stub_get_next_vm_name

      workflow = described_class.new(values, alt_user)

      expect(AuditEvent).to receive(:success).with(
        :event        => "vm_provision_request_updated",
        :target_class => "Vm",
        :userid       => alt_user.userid,
        :message      => "VM Provisioning request updated by <#{alt_user.userid}> for Vm:#{template.id}"
      )
      workflow.make_request(request, values)
    end
  end
end

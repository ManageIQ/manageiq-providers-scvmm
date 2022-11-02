
describe ManageIQ::Providers::Microsoft::InfraManager::Refresher do
  include Spec::Support::EmsRefreshHelper

  before(:each) do
    _guid, _server, zone = EvmSpecHelper.create_guid_miq_server_zone
    FactoryBot.create(:miq_region)
    @ems = FactoryBot.create(
      :ems_microsoft_with_authentication,
      :zone              => zone,
      :hostname          => Rails.application.secrets.scvmm[:hostname],
      :ipaddress         => Rails.application.secrets.scvmm[:ipaddress],
      :security_protocol => "ssl"
    )

    data_file = ManageIQ::Providers::Scvmm::Engine.root.join("spec", "tools", "scvmm_data", "get_inventory_output.json")
    output    = JSON.parse(IO.read(data_file.to_s))
    allow(ManageIQ::Providers::Microsoft::InfraManager).to receive(:execute_powershell_json).and_return(output)
  end

  it ".ems_type" do
    expect(described_class.ems_type).to eq(:scvmm)
  end

  it "will perform a full refresh" do
    1.times do # Run twice to verify that a second run with existing data does not change anything
      @ems.reload

      EmsRefresh.refresh(@ems)
      @ems.reload

      assert_table_counts
      assert_ems
      assert_specific_cluster
      assert_specific_host
      assert_esx_host
      assert_specific_vm_network
      assert_specific_subnet
      assert_specific_vm
      assert_specific_template
      assert_specific_guest_devices
      assert_specific_snapshot
      assert_specific_storage
    end
  end

  def assert_table_counts
    expect(ExtManagementSystem.count).to eq(1)
    expect(EmsFolder.count).to eq(4) # HACK: Folder structure for UI a la VMware
    expect(EmsCluster.count).to eq(1)
    expect(Host.count).to eq(3)
    expect(ResourcePool.count).to eq(0)
    expect(Vm.count).to eq(28)
    expect(VmOrTemplate.count).to eq(50)
    expect(CustomAttribute.count).to eq(0)
    expect(CustomizationSpec.count).to eq(0)
    expect(Disk.count).to eq(61)
    expect(GuestDevice.count).to eq(39)
    expect(Hardware.count).to eq(53)
    expect(Lan.count).to eq(54)
    expect(Subnet.count).to eq(16)
    expect(MiqScsiLun.count).to eq(0)
    expect(MiqScsiTarget.count).to eq(0)
    expect(Network.count).to eq(28)
    expect(OperatingSystem.count).to eq(53)
    expect(Snapshot.count).to eq(7)
    expect(Switch.count).to eq(6)
    expect(SystemService.count).to eq(0)
    expect(Relationship.count).to eq(57)
    expect(MiqQueue.count).to eq(50)
    expect(Storage.count).to eq(14)
  end

  def assert_ems
    expect(@ems).to have_attributes(
      :api_version => "2.1.0",
      :uid_ems     => "a2b45b8b-ff0e-425c-baf7-24626963a27c"
    )

    expect(@ems.ems_folders.size).to eq(4) # HACK: Folder structure for UI a la VMware
    expect(@ems.ems_clusters.size).to eq(1)
    expect(@ems.resource_pools.size).to eq(0)

    expect(@ems.storages.size).to eq(14)
    expect(@ems.hosts.size).to eq(3)
    expect(@ems.vms_and_templates.size).to eq(50)
    expect(@ems.vms.size).to eq(28)
    expect(@ems.miq_templates.size).to eq(22)
    expect(@ems.customization_specs.size).to eq(0)
    expect(@ems.lans.size).to eq(54)
    expect(@ems.subnets.size).to eq(16)
  end

  def assert_specific_storage
    storage_name = "file://qeblade33.cfme-qe-vmm-ad.rhq.lab.eng.bos.redhat.com" \
      "/C:/ClusterStorage/CLUSP04%20Prod%20Volume%203-1"

    @storage = Storage.find_by(:name => storage_name)

    expect(@storage).to have_attributes(
      :ems_ref                     => "8d585b11-3bb2-4be7-931c-b6cec81ec85d",
      :name                        => storage_name,
      :type                        => "ManageIQ::Providers::Microsoft::InfraManager::Storage",
      :store_type                  => "CSVFS",
      :total_space                 => 805_333_626_880,
      :free_space                  => 704_289_169_408,
      :multiplehostaccess          => 1,
      :location                    => "8d585b11-3bb2-4be7-931c-b6cec81ec85d",
      :thin_provisioning_supported => true
      )
  end

  def assert_specific_cluster
    @cluster = ManageIQ::Providers::Microsoft::InfraManager::Cluster.find_by(:name => "hyperv_cluster")

    expect(@cluster).to have_attributes(
      :ems_ref => "8e830204-6448-4817-b220-34af48ccf8ca",
      :uid_ems => "8e830204-6448-4817-b220-34af48ccf8ca",
      :name    => "hyperv_cluster",
    )
  end

  def assert_specific_host
    hostname = "qeblade33.cfme-qe-vmm-ad.rhq.lab.eng.bos.redhat.com"
    @host = ManageIQ::Providers::Microsoft::InfraManager::Host.find_by(:name => hostname)
    expect(@host).to have_attributes(
      :ems_ref          => "18060bb0-05b9-40fb-b1e3-dfccb8d85c6b",
      :name             => hostname,
      :hostname         => hostname,
      :ipaddress        => "10.16.4.54",
      :vmm_vendor       => "microsoft",
      :vmm_version      => "6.3.9600.18623",
      :vmm_product      => "HyperV",
      :power_state      => "on",
      :connection_state => "connected",
      :maintenance      => false,
    )

    expect(@host.operating_system).to have_attributes(
      :product_name => "Microsoft Windows Server 2012 R2 Standard ",
      :version      => "6.3.9600",
      :product_type => "microsoft"
    )

    expect(@host.hardware).to have_attributes(
      :serial_number        => '463b9e30-9f60-e011-8346-5cf3fc1c83ec',
      :cpu_speed            => 2133,
      :cpu_type             => "Intel Xeon 179",
      :manufacturer         => "Intel",
      :model                => "Xeon",
      :memory_mb            => 73_716,
      :memory_console       => nil,
      :cpu_sockets          => 2,
      :cpu_total_cores      => 16,
      :cpu_cores_per_socket => 8,
      :guest_os             => nil,
      :guest_os_full_name   => nil,
      :cpu_usage            => nil,
      :memory_usage         => nil
    )

    expect(@host.hardware.guest_devices.size).to eq(2)
    expect(@host.hardware.nics.size).to eq(2)
    nic = @host.hardware.nics.find_by_device_name("Ethernet")
    expect(nic).to have_attributes(
      :device_name     => "Ethernet",
      :device_type     => "ethernet",
      :location        => "PCI bus 16, device 0, function 0",
      :present         => true,
      :controller_type => "ethernet"
    )

    # @host2 = Host.find_by(:name => "SFBronagh.manageiq.com")
    # expect(@host2.ems_cluster).to eq(@cluster)
  end

  def assert_esx_host
    esx = Host.find_by_vmm_product("VMWareESX")
    expect(esx).to eq(nil)
  end

  def assert_specific_vm_network
    switch = @ems.switches.find_by(:uid_ems => "a840681c-7459-4ba0-9dd5-a706f220822f")   # vswitch-2
    vm_network = switch.lans.find_by(:uid_ems => "53f38ddc-450e-4f43-abde-881ac44608e3") # test-vm-network-1

    expect(vm_network).to have_attributes(
      :name                       => "test-vm-network-1",
      :tag                        => nil,
      :uid_ems                    => "53f38ddc-450e-4f43-abde-881ac44608e3",
      :allow_promiscuous          => nil,
      :forged_transmits           => nil,
      :mac_changes                => nil,
      :computed_allow_promiscuous => nil,
      :computed_forged_transmits  => nil,
      :computed_mac_changes       => nil,
    )

    expect(vm_network.parent).to_not     be_nil
    expect(vm_network.parent.uid_ems).to eq("2babf957-ca0c-45b5-8d26-ce5a7e89e01d")

    expect(vm_network.switch).to_not     be_nil
    expect(vm_network.switch.uid_ems).to eq("a840681c-7459-4ba0-9dd5-a706f220822f")

    expected_subnet_refs = %w(0b83d9f0-1617-4580-ae75-02d01139ed9a faecff5d-b850-4a98-9e62-2a6a8c9508e5)

    expect(vm_network.subnets.size).to           eq(2)
    expect(vm_network.subnets.map(&:ems_ref)).to match_array(expected_subnet_refs)
  end

  def assert_specific_subnet
    subnet = @ems.subnets.find_by(:ems_ref => "0b83d9f0-1617-4580-ae75-02d01139ed9a")
    expect(subnet).to have_attributes(
      :ems_ref => "0b83d9f0-1617-4580-ae75-02d01139ed9a",
      :name    => "vm-network-1-subnet-1",
      :type    => "ManageIQ::Providers::Microsoft::InfraManager::Subnet",
      :cidr    => "192.168.32.0/24"
    )

    expect(subnet.lan).to_not     be_nil
    expect(subnet.lan.uid_ems).to eq("53f38ddc-450e-4f43-abde-881ac44608e3")
  end

  def assert_specific_vm
    v = ManageIQ::Providers::Microsoft::InfraManager::Vm.find_by(:name => "WS2008R2Core")

    location = "\\WS2008R2Core\\Virtual Machines\\F36C31F0-A138-4F24-8F56-10A3BFBD7D14.xml"

    expect(v).to have_attributes(
      :template         => false,
      :ems_ref          => "f9d6d611-d835-4f95-ae3d-152eb43652f1",
      :vendor           => "microsoft",
      :power_state      => "off",
      :location         => location,
      :tools_status     => "OS shutdown: true, Time synchronization: true, Data exchange: true, Heartbeat: true, Backup: true",
      :boot_time        => nil,
      :connection_state => "connected",
    )

    expect(v.ext_management_system).to eq(@ems)
    expect(v.host).to eq(@host)

    expect(v.operating_system).to have_attributes(
      :product_name => "Unknown"
    )

    expect(v.custom_attributes.size).to eq(0)
    expect(v.snapshots.size).to eq(1)

    expect(v.hardware).to have_attributes(
      :guest_os             => "Unknown",
      :guest_os_full_name   => "Unknown",
      :bios                 => "2c67139b-76e1-40fd-896f-407ee9efc447",
      :cpu_total_cores      => 1,
      :annotation           => nil,
      :memory_mb            => 512
    )

    expect(v.hardware.disks.size).to eq(1)
    disk = v.hardware.disks.find_by_device_name("WS2008R2Corex64Ent_C02F48D6-ED11-4F67-B77C-B9EC821A4A3E")

    location = "C:\\WS2008R2Core\\WS2008R2Corex64Ent_C02F48D6-ED11-4F67-B77C-B9EC821A4A3E.avhd"

    expect(disk).to have_attributes(
      :device_name     => "WS2008R2Corex64Ent_C02F48D6-ED11-4F67-B77C-B9EC821A4A3E",
      :device_type     => "disk",
      :controller_type => "IDE",
      :present         => true,
      :filename        => location,
      :location        => location,
      :size            => 136_365_211_648,
      :mode            => "persistent",
      :disk_type       => "thin",  # TODO: need to add a differencing disk
      :start_connected => true
    )

    # TODO: Add "Stored" status value in DB. This is a VM that has been provisioned but not deployed
  end

  def assert_specific_template
    template = @ems.miq_templates.find_by(:ems_ref => "3184d261-3226-490c-bb2f-010d547059f5")
    expect(template).to have_attributes(
      :name            => "miq-nightly-201709012000",
      :uid_ems         => "3184d261-3226-490c-bb2f-010d547059f5",
      :power_state     => "never",
      :type            => "ManageIQ::Providers::Microsoft::InfraManager::Template",
      :raw_power_state => "never"
    )
  end

  def assert_specific_snapshot
    v = ManageIQ::Providers::Microsoft::InfraManager::Vm.find_by(:name => "WS2008R2Core")

    expect(v.snapshots.size).to eq(1)
    snapshot = v.snapshots.first

    expect(snapshot).to have_attributes(
      :type        => "ManageIQ::Providers::Microsoft::InfraManager::Snapshot",
      :uid         => "16FF0C08-04D3-4BEE-9E74-34393E087F4A",
      :ems_ref     => "16FF0C08-04D3-4BEE-9E74-34393E087F4A",
      :parent_uid  => "F36C31F0-A138-4F24-8F56-10A3BFBD7D14",
      :name        => "WS2008R2Core - (6/10/2016 - 8:41:12 AM)",
      :description => nil
    )
  end

  def assert_specific_guest_devices
    v0 = ManageIQ::Providers::Microsoft::InfraManager::Vm.find_by(:name => "cfme-vmm-ad-bu-DND")
    v1 = ManageIQ::Providers::Microsoft::InfraManager::Vm.find_by(:name => "centos7min-vm")
    v2 = ManageIQ::Providers::Microsoft::InfraManager::Vm.find_by(:name => "DualDVDa")

    expect(v0.hardware.guest_devices.size).to eq(1)
    expect(v1.hardware.guest_devices.size).to eq(2)
    expect(v2.hardware.guest_devices.size).to eq(3)

    expect(v0.hardware.guest_devices.first).to have_attributes(
      :uid_ems         => "07be840c-12a1-4ff6-a8ce-72dd0c90ae72",
      :device_name     => "cfme-vmm-ad-bu-DND",
      :device_type     => "ethernet",
      :controller_type => "ethernet",
      :address         => "00:15:5D:04:2F:24",
      :present         => true,
      :start_connected => true,
    )

    v1_cdroms = v1.hardware.guest_devices.select { |dev| dev[:device_type] == "cdrom" }
    expect(v1_cdroms.first).to have_attributes(
      :device_name     => "vmguest",
      :device_type     => "cdrom",
      :filename        => "C:\\Windows\\system32\\vmguest.iso",
      :controller_type => "IDE",
      :present         => true,
      :start_connected => true,
    )

    v2_cdroms = v2.hardware.guest_devices.order(:device_name).select { |dev| dev[:device_type] == "cdrom" }
    expect(v2_cdroms.first).to have_attributes(
      :device_name     => "en_office_professional_plus_2016_x86_x64_dvd_6962141",
      :device_type     => "cdrom",
      :filename        => "C:\\tmp\\en_office_professional_plus_2016_x86_x64_dvd_6962141.iso",
      :controller_type => "IDE",
      :present         => true,
      :start_connected => true,
    )

    expect(v2_cdroms.last).to have_attributes(
      :device_name     => "en_visio_professional_2016_x86_x64_dvd_6962139",
      :device_type     => "cdrom",
      :filename        => "C:\\tmp\\en_visio_professional_2016_x86_x64_dvd_6962139.iso",
      :controller_type => "IDE",
      :present         => true,
      :start_connected => true,
    )
  end
end

class ManageIQ::Providers::Microsoft::Inventory::Parser::InfraManager < ManageIQ::Providers::Microsoft::Inventory::Parser
  include ManageIQ::Providers::Microsoft::InfraManager::ParserMixin

  def parse
    collector.collect!

    parse_ems
    parse_datacenters
    parse_folders
    parse_volumes
    parse_storage_fileshares
    parse_hosts
    parse_clusters
    parse_vms
    parse_images
  end

  private

  def parse_ems
    api_version, guid = collector.ems.values_at("Version", "Guid")

    # TODO: shouldn't have to update the ems directly from the parser
    manager = collector.manager
    manager.api_version = api_version
    manager.uid_ems     = guid
    manager.save!
  end

  def parse_datacenters
    persister.ems_folders.build(
      :type    => "Datacenter",
      :name    => "SCVMM",
      :uid_ems => "scvmm",
      :ems_ref => "scvmm",
      :hidden  => false,
    )
  end

  def parse_folders
    persister.ems_folders.build(
      :name    => "Datacenters",
      :ems_ref => "root_dc",
      :uid_ems => "root_dc",
      :hidden  => true,
    )

    persister.ems_folders.build(
      :name    => "host",
      :ems_ref => "host_folder",
      :uid_ems => "host_folder",
      :hidden  => true,
    )

    persister.ems_folders.build(
      :name    => "vm",
      :ems_ref => "vm_folder",
      :uid_ems => "vm_folder",
      :hidden  => true,
    )
  end

  def parse_volumes
    collector.volumes.each do |volume|
      uid = volume["ID"]

      persister.storages.build(
        :ems_ref                     => uid,
        :name                        => path_to_uri(volume["Name"], volume["VMHost"]),
        :store_type                  => volume["FileSystem"],
        :total_space                 => volume["Capacity"],
        :multiplehostaccess          => true,
        :thin_provisioning_supported => true,
        :location                    => uid,
      )
    end
  end

  def parse_storage_fileshares
    collector.fileshares.each do |fileshare|
      uid = fileshare["ID"]

      persister.storages.build(
        :ems_ref                     => uid,
        :name                        => path_to_uri(fileshare['SharePath']),
        :store_type                  => 'StorageFileShare',
        :total_space                 => fileshare['Capacity'],
        :free_space                  => fileshare['FreeSpace'],
        :multiplehostaccess          => true,
        :thin_provisioning_supported => true,
        :location                    => uid,
      )
    end
  end

  def parse_hosts
    collector.hosts.each do |data|
      # Skip VMware ESX/ESXi hosts
      next if host_platform_unsupported?(data)

      host = persister.hosts.build(
        :name             => data["Name"],
        :uid_ems          => data["ID"],
        :ems_ref          => data["ID"],
        :hostname         => data["Name"],
        :ipaddress        => identify_primary_ip(data),
        :vmm_vendor       => "microsoft",
        :vmm_version      => data["HyperVVersionString"],
        :vmm_product      => data["VirtualizationPlatformString"],
        :power_state      => lookup_power_state(data['HyperVStateString']),
        :maintenance      => lookup_overall_state(data['OverallState']),
        :connection_state => lookup_connected_state(data['CommunicationStateString']),
      )

      parse_host_hardware(host, data)
      parse_host_storages(host, data)
      parse_host_virtual_switches(host, data["VirtualSwitch"])
    end
  end

  def parse_host_hardware(host, data)
    cpu_family       = data['ProcessorFamily']
    cpu_manufacturer = data['ProcessorManufacturer']
    cpu_model        = data['ProcessorModel']
    serial_number    = data['SMBiosGUIDString'].presence

    hardware = persister.host_hardwares.build(
      :host                 => host,
      :cpu_type             => "#{cpu_manufacturer} #{cpu_model} #{cpu_family}",
      :manufacturer         => cpu_manufacturer,
      :model                => cpu_model,
      :cpu_speed            => data['ProcessorSpeed'],
      :memory_mb            => data['TotalMemory'] / 1.megabyte,
      :cpu_sockets          => data['PhysicalCPUCount'],
      :cpu_total_cores      => data['LogicalProcessorCount'],
      :cpu_cores_per_socket => data['CoresPerCPU'],
      :serial_number        => serial_number,
    )

    parse_host_guest_devices(hardware, data)
  end

  def parse_host_guest_devices(hardware, data)
    switches = data["VirtualSwitch"]
    adapters = switches.collect { |s| s["VMHostNetworkAdapters"] }.flatten

    adapters.each do |adapter|
      persister.host_guest_devices.build(
        :hardware        => hardware,
        :uid_ems         => adapter["ID"],
        :device_name     => adapter["ConnectionName"],
        :device_type     => "ethernet",
        :model           => adapter["Name"],
        :location        => adapter["BDFLocationInformation"],
        :present         => true,
        :start_connected => true,
        :controller_type => "ethernet",
        :address         => adapter["MacAddress"],
      )
    end

    data["DVDDriveList"].each do |dvd|
      persister.host_guest_devices.build(
        :hardware        => hardware,
        :device_type     => "cdrom",
        :present         => true,
        :controller_type => "IDE",
        :mode            => "persistent",
        :filename        => dvd,
      )
    end
  end

  def parse_host_storages(host, data)
  end

  def parse_host_virtual_switches(host, virtual_switches)
    switches = virtual_switches.map do |data|
      switch = persister.switches.build(
        :uid_ems => data["ID"],
        :name    => data["Name"],
      )

      parse_logical_networks(switch, data["LogicalNetworks"])

      switch
    end

    switches.each { |switch| persister.host_switches.build(:switch => switch, :host => host) }
  end

  def parse_logical_networks(switch, logical_networks)
    logical_networks.each do |net|
      lan = persister.lans.build(
        :switch  => switch,
        :name    => net["Name"],
        :uid_ems => net["ID"],
      )

      net["VMNetworks"].to_a.each do |vm_network|
        vm_net = persister.lans.build(
          :switch  => switch,
          :name    => vm_network["Name"],
          :uid_ems => vm_network["ID"],
          :parent  => lan,
        )

        vm_network["VMSubnet"].to_a.each do |subnet|
          persister.subnets.build(
            :lan     => vm_net,
            :name    => subnet["Name"],
            :ems_ref => subnet["ID"],
            :cidr    => process_cidr(subnet["SubnetVLans"]),
          )
        end
      end
    end
  end

  def parse_clusters
    collector.clusters.each do |cluster|
      uid  = cluster["ID"]
      name = cluster["ClusterName"]

      # TODO: link clusters to hosts

      persister.ems_clusters.build(
        :ems_ref => uid,
        :uid_ems => uid,
        :name    => name,
      )
    end
  end

  def parse_vms
    drive_letter = /\A[a-z][:]/i

    collector.vms.each do |data|
      vm = persister.vms.build(
        :name            => data["Name"],
        :ems_ref         => data["ID"],
        :uid_ems         => data["ID"],
        :vendor          => "microsoft",
        :raw_power_state => data["VirtualMachineStateString"],
        :location        => data["VMCPath"].blank? ? "unknown" : data["VMCPath"].sub(drive_letter, "").strip,
      )

      parse_vm_operating_system(vm, data)
      parse_vm_hardware(vm, data)
      parse_vm_networks(vm, data)
    end
  end

  def parse_vm_operating_system(vm, data)
    persister.operating_systems.build(
      :vm_or_template => vm,
      :product_name   => data.fetch_path("OperatingSystem", "Name"),
    )
  end

  def parse_vm_hardware(vm, data)
    hardware = persister.hardwares.build(
      :vm_or_template     => vm,
      :cpu_total_cores    => data['CPUCount'],
      :guest_os           => data['OperatingSystem']['Name'],
      :guest_os_full_name => process_vm_os_description(data),
      :memory_mb          => data['Memory'],
      :cpu_type           => data['CPUType']['Name'],
      :bios               => data['BiosGuid']
    )

    parse_vm_disks(hardware, data["VirtualHardDisks"])
    parse_vm_guest_devices(hardware, data)
    parse_vm_networks(hardware, data)
  end

  def parse_vm_disks(hardware, virtual_hard_disks)
    virtual_hard_disks&.each do |data|
      persister.disks.build(
        :hardware        => hardware,
        :device_name     => data["Name"],
        :size            => data["MaximumSize"],
        :size_on_disk    => data["Size"],
        :disk_type       => lookup_disk_type(data),
        :device_type     => "disk",
        :present         => true,
        :filename        => data["SharePath"],
        :location        => data["Location"],
        :mode            => "persistent",
        :controller_type => "IDE",
      )
    end
  end

  def parse_vm_guest_devices(hardware, data)
    data["VirtualNetworkAdapters"].to_a.each do |vnic|
      persister.guest_devices.build(
        :hardware        => hardware,
        :uid_ems         => vnic["ID"],
        :present         => vnic["Enabled"],
        :start_connected => vnic["Enabled"],
        :address         => vnic["MACAddress"],
        :device_name     => vnic["Name"],
        :device_type     => "ethernet",
        :controller_type => "ethernet",
      )
    end

    data["VirtualDVDDrives"].to_a.each do |dvd|
      next if dvd["HostDrive"].blank?

      persister.guest_devices.build(
        :hardware        => hardware,
        :uid_ems         => dvd["ID"],
        :present         => true,
        :mode            => "persistent",
        :controller_type => "IDE",
        :device_type     => "cdrom",
        :device_name     => dvd["Name"],
        :filename        => dvd["HostDrive"],
      )
    end

    if data["DVDISO"].present?
      data["DVDISO"].each do |iso|
        persister.guest_devices.build(
          :hardware        => hardware,
          :uid_ems         => iso["ID"],
          :size            => iso["Size"] / 1.megabyte,
          :present         => true,
          :mode            => "persistent",
          :device_type     => "cdrom",
          :device_name     => iso["Name"],
          :filename        => iso["SharePath"],
          :controller_type => "IDE",
        )
      end
    end
  end

  def parse_vm_networks(hardware, data)
    hostname = process_computer_name(data["ComputerName"])

    data["VirtualNetworkAdapters"].each do |vnic|
      # TODO: this looks like it could container more than one IP but
      # isn't an array, possibly comma separated?
      ipv4addr = vnic["IPv4Addresses"]
      ipv6addr = vnic["IPv6Addresses"]

      persister.networks.build(
        :hardware  => hardware,
        :hostname  => hostname,
        :ipaddress => ipv4addr,
        :ipv6address => ipv6addr,
      )
    end
  end

  def parse_images
    collector.images.each do |data|
      template = persister.miq_templates.build(
        :uid_ems         => data["ID"],
        :ems_ref         => data["ID"],
        :name            => data["Name"],
        :vendor          => "microsoft",
        :raw_power_state => "never",
        :template        => true,
        :location        => "unknown",
      )

      parse_image_operating_system(template, data)
      parse_image_hardware(template, data)
    end
  end

  def parse_image_operating_system(template, data)
    persister.operating_systems.build(
      :vm_or_template => template,
      :product_name   => data["OperatingSystemString"],
    )
  end

  def parse_image_hardware(template, data)
    hardware = persister.hardwares.build(
      :vm_or_template     => template,
      :cpu_total_cores    => data['CPUCount'],
      :memory_mb          => data['Memory'],
      :cpu_type           => data['CPUTypeString'],
      :guest_os           => data['OperatingSystemString'],
      :guest_os_full_name => data['OperatingSystemString'],
    )

    parse_vm_disks(hardware, data["VirtualHardDisks"])
    parse_vm_guest_devices(hardware, data)
  end
end

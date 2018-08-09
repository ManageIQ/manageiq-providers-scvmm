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
        #:ipaddress        => identify_primary_ip(data),
        :vmm_vendor       => "microsoft",
        :vmm_version      => data["HyperVVersionString"],
        :vmm_product      => data["VirtualizationPlatformString"],
        :power_state      => lookup_power_state(data['HyperVStateString']),
        :maintenance      => lookup_overall_state(data['OverallState']),
        :connection_state => lookup_connected_state(data['CommunicationStateString']),
      )

      parse_host_hardware(host, data)
    end
  end

  def parse_host_hardware(host, data)
    cpu_family       = data['ProcessorFamily']
    cpu_manufacturer = data['ProcessorManufacturer']
    cpu_model        = data['ProcessorModel']
    serial_number    = data['SMBiosGUIDString'].blank? ? nil : data['SMBiosGUIDString']

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
  end
end

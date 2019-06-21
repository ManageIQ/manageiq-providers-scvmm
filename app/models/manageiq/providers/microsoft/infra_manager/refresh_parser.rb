module ManageIQ::Providers::Microsoft
  class InfraManager::RefreshParser < EmsRefresh::Parsers::Infra
    include ManageIQ::Providers::Microsoft::InfraManager::ParserMixin

    INVENTORY_SCRIPT           = File.join(File.dirname(__FILE__), 'ps_scripts/get_inventory.ps1')
    DRIVE_LETTER               = /\A[a-z][:]/i

    def self.ems_inv_to_hashes(ems, options = nil)
      new(ems, options).ems_inv_to_hashes
    end

    def initialize(ems, _options = nil)
      @ems                = ems
      @connection         = ems.connect
      @data               = {}
      @data_index         = {}
    end

    def ems_inv_to_hashes
      log_header = "MIQ(#{self.class.name}.#{__method__}) Collecting data for EMS name: [#{@ems.name}] id: [#{@ems.id}]"
      $scvmm_log.info("#{log_header}...")

      script = IO.read(INVENTORY_SCRIPT)
      @inventory = ManageIQ::Providers::Microsoft::InfraManager.execute_powershell_json(@connection, script)

      if @inventory.empty? || @inventory['ems'].empty?
        $scvmm_log.warn("#{log_header}...Empty inventory set returned from SCVMM.")
        return
      end

      get_ems
      get_datastores
      get_storage_fileshares
      get_hosts
      get_clusters
      get_vms
      get_images
      create_relationship_tree
      $scvmm_log.info("#{log_header}...Complete")
      @data
    end

    private

    def get_ems
      @ems.api_version = @inventory['ems']['Version']
      @ems.uid_ems = @inventory['ems']['Guid']
    end

    def get_datastores
      datastores = @inventory['hosts'].collect{ |host| host['DiskVolumes'] }.flatten
      datastores.reject! { |e| e['VolumeLabel'] == 'System Reserved' }
      process_collection(datastores, :storages) { |ds| parse_datastore(ds) }
    end

    def get_storage_fileshares
      fileshares = @inventory['hosts'].collect{ |host| host['RegisteredStorageFileShares'] }.flatten
      fileshares.uniq! { |fs| fs["ID"] }
      process_collection(fileshares, :storages) { |fs| parse_storage_fileshare(fs) }
    end

    def get_hosts
      hosts = @inventory['hosts']

      switches = Array(@inventory['vnets'])
      vm_networks = Array(@inventory['vmnetworks'])

      switches_by_host_name = switches.group_by { |switch| switch['VMHostName'] }
      vm_nets_by_logical_network_id = vm_networks.group_by { |vmnet| vmnet['LogicalNetwork']['ID'] }

      # Set VirtualSwitch as a path to LogicalNetworks, VMHostNetworkAdapters, etc.
      hosts.each do |host|
        host['VirtualSwitch'] = Array(switches_by_host_name[host['Name']])
        host['VirtualSwitch'].each do |switch|
          switch['LogicalNetworks'].each do |logical_network|
            logical_network['VMNetworks'] = Array(vm_nets_by_logical_network_id[logical_network['ID']])
          end
        end
      end

      process_collection(hosts, :hosts) { |host| parse_host(host) }
    end

    def get_clusters
      clusters = @inventory['clusters']
      process_collection(clusters, :clusters) { |cluster| parse_cluster(cluster) }
    end

    def get_vms
      vms = @inventory['vms']
      process_collection(vms, :vms) { |vm| parse_vm(vm) }
    end

    def get_images
      images = @inventory['images']
      process_collection(images, :vms) { |image| parse_image(image) }
    end

    def parse_storage_fileshare(volume)
      uid = volume['ID']

      new_result = {
        :ems_ref                     => uid,
        :name                        => path_to_uri(volume['SharePath']),
        :store_type                  => 'StorageFileShare',
        :total_space                 => volume['Capacity'],
        :free_space                  => volume['FreeSpace'],
        :multiplehostaccess          => true,
        :thin_provisioning_supported => true,
        :location                    => uid,
      }

      return uid, new_result
    end

    def parse_datastore(volume)
      uid = volume['ID']

      new_result = {
        :ems_ref                     => uid,
        :name                        => path_to_uri(volume['Name'], volume['VMHost']),
        :store_type                  => volume['FileSystem'],
        :total_space                 => volume['Capacity'],
        :free_space                  => volume['FreeSpace'],
        :multiplehostaccess          => true,
        :thin_provisioning_supported => true,
        :location                    => uid,   # HACK: get around save_inventory issues by reusing uid.
      }

      return uid, new_result
    end

    def parse_cluster(cluster)
      uid   = cluster['ID']
      nodes = cluster['Nodes']
      name  = cluster['ClusterName']

      new_result = {
        :ems_ref => uid,
        :uid_ems => uid,
        :name    => name,
      }

      set_relationship_on_hosts(new_result, nodes)

      # ignore clusters that are left without any hosts after hosts were filtered for UNSUPPORTED_HOST_PLATFORMS
      return uid, new_result if @data[:hosts].any? { |host| host[:ems_cluster] == new_result }
    end

    def parse_host(host)
      uid       = host['ID']
      host_name = host['Name']

      host_platform = host['VirtualizationPlatformString']

      if host_platform_unsupported?(host)
        $scvmm_log.warn("#{host_platform} servers are not supported, skipping #{host_name}")
        return
      end

      hardware = process_host_hardware(host)
      storages = process_host_storages(host)
      switches = process_virtual_switches(host)

      new_result = {
        :name             => host_name,
        :type             => 'ManageIQ::Providers::Microsoft::InfraManager::Host',
        :uid_ems          => uid,
        :ems_ref          => uid,
        :hostname         => host_name,
        :ipaddress        => identify_primary_ip(host),
        :vmm_vendor       => 'microsoft',
        :vmm_version      => host['HyperVVersionString'],
        :vmm_product      => host_platform,
        :power_state      => lookup_power_state(host['HyperVStateString']),
        :maintenance      => lookup_overall_state(host['OverallState']),
        :connection_state => lookup_connected_state(host['CommunicationStateString']),
        :operating_system => process_os(host),
        :hardware         => hardware,
        :storages         => storages,
        :switches         => switches,
        :host_switches    => switches,
      }

      @data_index.store_path(:hosts_by_host_name, host_name, new_result)
      @data_index.store_path(:host_uid_to_datastore_mount_point_mapping, uid, map_mount_point_to_datastore(host))

      return uid, new_result
    end

    def process_virtual_switches(host)
      result = []

      virtual_switches = host['VirtualSwitch']
      return result if virtual_switches.blank?

      virtual_switches.each do |v_switch|
        switch = {
          :uid_ems => v_switch['ID'],
          :name    => v_switch['Name'],
          :lans    => process_logical_networks(v_switch['LogicalNetworks'])
        }
        result << switch
        v_switch['VMHostNetworkAdapters'].collect { |adapter| set_switch_on_pnic(adapter, switch) }
      end

      result
    end

    def process_logical_networks(logical_networks)
      network_hashes = []

      logical_networks.each do |ln|
        result = {
          :name    => ln['Name'],
          :uid_ems => ln['ID'],
        }

        network_hashes << result

        Array(ln['VMNetworks']).each do |vm_network|
          network_hashes << {
            :name    => vm_network['Name'],
            :uid_ems => vm_network['ID'],
            :subnets => process_subnets(vm_network),
            :parent  => result,
          }
        end
      end

      network_hashes
    end

    def process_subnets(vm_network)
      Array(vm_network['VMSubnet']).map do |subnet|
        {
          :type    => 'ManageIQ::Providers::Microsoft::InfraManager::Subnet',
          :name    => subnet['Name'],
          :ems_ref => subnet['ID'],
          :cidr    => process_cidr(subnet['SubnetVLans'])
        }
      end
    end

    def set_switch_on_pnic(pnic, switch)
      pnic_obj = @data_index.fetch_path(:physical_nic, pnic['ID'])
      pnic_obj[:switch] = switch
    end

    def parse_vm(vm)
      uid      = vm['ID']
      vmname   = vm['Name']
      hostname = vm['HostName']
      status   = vm['StatusString']

      host = @data_index.fetch_path(:hosts_by_host_name, hostname)

      if host.nil? || status == 'Missing'
        msg = "Could not fetch host for #{vmname} on #{hostname}. Status is: #{status}."
        $scvmm_log.warn(msg)
        return
      end

      connection_state = vm['ServerConnection']['IsConnected'].to_s

      new_result = {
        :name              => vmname,
        :ems_ref           => uid,
        :uid_ems           => uid,
        :type              => 'ManageIQ::Providers::Microsoft::InfraManager::Vm',
        :vendor            => 'microsoft',
        :raw_power_state   => vm['VirtualMachineStateString'],
        :operating_system  => {:product_name => vm['OperatingSystem']['Name']},
        :connection_state  => lookup_connected_state(connection_state),
        :tools_status      => process_tools_status(vm),
        :host              => host,
        :ems_cluster       => host[:ems_cluster],
        :hardware          => process_vm_hardware(vm),
        :custom_attributes => process_vm_custom_properties(vm),
        :snapshots         => process_snapshots(vm),
        :storage           => process_vm_storage(vm['VMCPath'], host),
        :storages          => process_vm_storages(vm)
      }

      new_result[:location] = vm['VMCPath'].blank? ? 'unknown' : vm['VMCPath'].sub(DRIVE_LETTER, "").strip
      return uid, new_result
    end

    def parse_image(image)
      uid = image['ID']

      new_result = {
        :type             => 'ManageIQ::Providers::Microsoft::InfraManager::Template',
        :uid_ems          => uid,
        :ems_ref          => uid,
        :vendor           => 'microsoft',
        :operating_system => {:product_name => image['OperatingSystemString']},
        :name             => image['Name'],
        :raw_power_state  => 'never',
        :template         => true,
        :storages         => process_vm_storages(image),
        :hardware         => {
          :cpu_total_cores    => image['CPUCount'],
          :memory_mb          => image['Memory'],
          :cpu_type           => image['CPUTypeString'],
          :disks              => process_disks(image),
          :guest_devices      => process_vm_guest_devices(image),
          :guest_os           => image['OperatingSystemString'],
          :guest_os_full_name => image['OperatingSystemString'],
        },
      }

      return uid, new_result
    end

    def process_host_hardware(host)
      cpu_family       = host['ProcessorFamily']
      cpu_manufacturer = host['ProcessorManufacturer']
      cpu_model        = host['ProcessorModel']
      serial_number    = host['SMBiosGUIDString'].blank? ? nil : host['SMBiosGUIDString']

      {
        :cpu_type             => "#{cpu_manufacturer} #{cpu_model} #{cpu_family}",
        :manufacturer         => cpu_manufacturer,
        :model                => cpu_model,
        :cpu_speed            => host['ProcessorSpeed'],
        :memory_mb            => host['TotalMemory'] / 1.megabyte,
        :cpu_sockets          => host['PhysicalCPUCount'],
        :cpu_total_cores      => host['LogicalProcessorCount'],
        :cpu_cores_per_socket => host['CoresPerCPU'],
        :guest_devices        => process_host_guest_devices(host),
        :serial_number        => serial_number
      }
    end

    def process_host_storages(properties)
      disk_volumes = properties['DiskVolumes'].collect do |dv|
        @data_index.fetch_path(:storages, dv['ID'])
      end.compact

      file_shares = properties['RegisteredStorageFileShares'].collect do |fs|
        @data_index.fetch_path(:storages, fs['ID'])
      end.compact

      disk_volumes + file_shares
    end

    def map_mount_point_to_datastore(properties)
      log_header = "MIQ(#{self.class.name}.#{__method__})"

      properties['DiskVolumes'].each.with_object({}) do |dv, h|
        mount_point = dv['Name'].match(DRIVE_LETTER).to_s
        next if mount_point.blank?
        storage = @data_index.fetch_path(:storages, dv['ID'])
        h[mount_point] = storage
      end
    end

    def process_host_guest_devices(host)
      switches = host['VirtualSwitch']
      adapters = switches.collect{ |s| s['VMHostNetworkAdapters'] }.flatten

      result = []

      adapters.each do |adapter|
        new_result = build_network_adapter_hash(adapter)
        result << new_result
      end

      host['DVDDriveList'].each do |dvd|
        result << build_dvd_hash(dvd)
      end

      result
    end

    def build_network_adapter_hash(adapter)
      nic = {
        :uid_ems         => adapter['ID'],
        :device_name     => adapter['ConnectionName'],
        :device_type     => 'ethernet',
        :model           => adapter['Name'],
        :location        => adapter['BDFLocationInformation'],
        :present         => 'true',
        :start_connected => 'true',
        :controller_type => 'ethernet',
        :address         => adapter['MacAddress'],
      }

      @data_index.store_path(:physical_nic, adapter['ID'], nic)
    end

    def build_dvd_hash(dvd)
      {
        :device_type     => 'cdrom', # TODO: add DVD to model
        :present         => true,
        :controller_type => 'IDE',
        :mode            => 'persistent',
        :filename        => dvd,
      }
    end

    def process_vm_hardware(vm)
      {
        :cpu_total_cores      => vm['CPUCount'],
        :guest_os             => vm['OperatingSystem']['Name'],
        :guest_os_full_name   => process_vm_os_description(vm),
        :memory_mb            => vm['Memory'],
        :cpu_type             => vm['CPUType']['Name'],
        :disks                => process_disks(vm),
        :networks             => process_hostname_and_ip(vm),
        :guest_devices        => process_vm_guest_devices(vm),
        :bios                 => vm['BiosGuid']
      }
    end

    def process_vm_custom_properties(vm)
      vm['CustomProperty'].map do |key, value|
        {
          :section => 'custom_field',
          :name    => key,
          :value   => value,
          :source  => 'VC'
        }
      end
    end

    def process_snapshots(vm)
      result = []

      if vm['VMCheckpoints'].blank?
        $scvmm_log.info("No snapshot information available for #{vm['Name']}")
        return result
      end

      vm['VMCheckpoints'].collect do |cp|
        {
          :uid_ems     => cp['CheckpointID'],
          :uid         => cp['CheckpointID'],
          :ems_ref     => cp['CheckpointID'],
          :parent_uid  => cp['ParentCheckpointID'],
          :name        => cp['Name'],
          :description => cp['Description'].blank? ? nil : cp['Description'],
          :create_time => convert_windows_date_string_to_ruby_time(cp['AddedTime']),
          :current     => cp['CheckpointID'] == vm['LastRestoredCheckpointID']
        }
      end
    end

    def process_hostname_and_ip(vm)
      vnics = Array(vm['VirtualNetworkAdapters'])

      [
        {
          :hostname    => process_computer_name(vm['ComputerName']),
          :ipaddress   => vnics.map { |nic| nic['IPv4Addresses'] }.first,
          :ipv6address => vnics.map { |nic| nic['IPv6Addresses'] }.first,
        }
      ]
    end

    def process_disks(vm)
      return if vm['VirtualHardDisks'].blank?

      vm['VirtualHardDisks'].collect do |disk|
        {
          :device_name     => disk['Name'],
          :size            => disk['MaximumSize'],
          :size_on_disk    => disk['Size'],
          :disk_type       => lookup_disk_type(disk),
          :device_type     => 'disk',
          :present         => true,
          :filename        => disk['SharePath'],
          :location        => disk['Location'],
          :mode            => 'persistent',
          :controller_type => 'IDE',
        }
      end
    end

    def process_vm_guest_devices(vm)
      devices = []

      vm['VirtualNetworkAdapters'].to_a.each do |vnic|
        devices << process_vm_virtual_nic(vnic)
      end

      vm['VirtualDVDDrives'].to_a.each do |dvd|
        devices << process_vm_physical_dvd_drive(dvd) unless dvd['HostDrive'].blank?
      end

      devices.concat(process_iso_image(vm['DVDISO'])) unless vm['DVDISO'].blank?

      devices.flatten.compact.uniq
    end

    def process_vm_virtual_nic(vnic)
      {
        :uid_ems         => vnic['ID'],
        :present         => vnic['Enabled'],
        :start_connected => vnic['Enabled'],
        :address         => vnic['MACAddress'],
        :device_name     => vnic['Name'],
        :device_type     => 'ethernet',
        :controller_type => 'ethernet',
      }
    end

    def process_vm_physical_dvd_drive(dvd)
      {
        :device_type     => 'cdrom',  # TODO: add DVD to model
        :present         => true,
        :controller_type => 'IDE',
        :mode            => 'persistent',
        :filename        => dvd['HostDrive'],
        :uid_ems         => dvd['ID'],
        :device_name     => dvd['Name']
      }
    end

    def process_iso_image(isos)
      isos.collect do |iso|
        {
          :size            => iso['Size'] / 1.megabyte,
          :device_type     => 'cdrom', # TODO: add DVD to model
          :present         => true,
          :controller_type => 'IDE',
          :mode            => 'persistent',
          :filename        => iso['SharePath'],
          :uid_ems         => iso['ID'],
          :device_name     => iso['Name']
        }
      end
    end

    def process_vm_storages(properties)
      return if properties['VirtualHardDisks'].blank?

      properties['VirtualHardDisks'].collect do |vhd|
        @data_index.fetch_path(:storages, vhd['HostVolumeId'])
      end.compact.uniq
    end

    def process_vm_storage(vmcpath, host)
      return nil if vmcpath.nil? || host.nil?

      mount_point  = vmcpath.match(DRIVE_LETTER).to_s
      return nil if mount_point.nil?

      mapping = @data_index.fetch_path(:host_uid_to_datastore_mount_point_mapping, host[:uid_ems])
      mapping[mount_point]
    end

    def process_os(property_hash)
      {
        :product_name => property_hash['OperatingSystem']['Name'],
        :version      => property_hash['OperatingSystemVersionString'],
        :product_type => 'microsoft'
      }
    end

    def set_relationship_on_hosts(cluster, nodes)
      nodes.each do |host|
        host = @data_index.fetch_path(:hosts, host['ID'])
        host[:ems_cluster] = cluster if host
      end
    end

    def create_relationship_tree
      # HACK: creating a VMware type relationship tree to fit into the UI which
      # was designed specifically for a VMware hierarchy.

      host_folder = {
        :name         => 'host',
        :type         => 'EmsFolder',
        :uid_ems      => "host_folder",
        :ems_ref      => "host_folder",
        :hidden       => true,
        :ems_children => set_host_folder_children

      }
      vm_folder = {
        :name         => 'vm',
        :type         => 'EmsFolder',
        :uid_ems      => "vm_folder",
        :ems_ref      => "vm_folder",
        :hidden       => true,
        :ems_children => {:vms => @data[:vms]}
      }
      scvmm_folder = {
        :name         => 'SCVMM',
        :type         => 'Datacenter',
        :uid_ems      => "scvmm",
        :ems_ref      => "scvmm",
        :hidden       => false,
        :ems_children => {:folders => [host_folder, vm_folder]}
      }
      dc_folder = {
        :name         => 'Datacenters',
        :type         => 'EmsFolder',
        :uid_ems      => 'root_dc',
        :ems_ref      => 'root_dc',
        :hidden       => true,
        :ems_children => {:folders => [scvmm_folder]}
      }
      @data[:folders]  = [dc_folder, scvmm_folder, host_folder, vm_folder]
      @data[:ems_root] = dc_folder
    end

    def set_host_folder_children
      results = {}
      results[:clusters] = @data[:clusters] unless @data[:clusters].empty?
      results[:hosts]    = unclustered_hosts

      results
    end

    def unclustered_hosts
      @data[:hosts].select { |h| h[:ems_cluster].nil? }
    end

    def process_collection(collection, key)
      @data[key] ||= []
      return if collection.nil?

      collection.each do |item|
        uid, new_result = yield(item)
        next if new_result.nil?

        @data[key] << new_result
        @data_index.store_path(key, uid, new_result)
      end
    end

  end
end

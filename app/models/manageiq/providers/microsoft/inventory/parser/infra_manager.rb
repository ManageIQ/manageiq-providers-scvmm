class ManageIQ::Providers::Microsoft::Inventory::Parser::InfraManager < ManageIQ::Providers::Microsoft::Inventory::Parser
  def parse
    collector.collect!

    parse_ems
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
    collector.hosts.each do |host|
      # Skip VMware ESX/ESXi hosts
      next if host_platform_unsupported?(host)

      uid = host["ID"]
      host_name = host["Name"]

      persister.hosts.build(
        :name        => host_name,
        :uid_ems     => uid,
        :ems_ref     => uid,
        :hostname    => host_name,
        # TODO: :ems_cluster => persister.ems_clusters.lazy_find(),
        # TODO: :ipaddress   => identify_primary_ip(host),
        :vmm_vendor  => "microsoft",
        :vmm_version => host["HyperVVersionString"],
        :vmm_product => host["VirtualizationPlatformString"],
        # TODO: :power_state      => lookup_power_state(host['HyperVStateString']),
        # TODO: :maintenance      => lookup_overall_state(host['OverallState']),
        # TODO: :connection_state => lookup_connected_state(host['CommunicationStateString']),
      )
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

    collector.vms.each do |vm|
      persister.vms.build(
        :name            => vm["Name"],
        :ems_ref         => vm["ID"],
        :uid_ems         => vm["ID"],
        :vendor          => "microsoft",
        :raw_power_state => vm["VirtualMachineStateString"],
        :location        => vm["VMCPath"].blank? ? "unknown" : vm["VMCPath"].sub(drive_letter, "").strip,
      )
    end
  end

  def parse_images
    collector.images.each do |image|
      persister.miq_templates.build(
        :uid_ems         => image["ID"],
        :ems_ref         => image["ID"],
        :name            => image["Name"],
        :vendor          => "microsoft",
        :raw_power_state => "never",
        :template        => true,
        :location        => "unknown",
      )
    end
  end

  def path_to_uri(file, hostname = nil)
    file = Addressable::URI.encode(file.tr('\\', '/'))
    hostname = URI::Generic.build(:host => hostname).host if hostname # ensure IPv6 hostnames
    "file://#{hostname}/#{file}"
  end

  def host_platform_unsupported?(host_hash)
    %w(vmwareesx).include?(host_hash["VirtualizationPlatformString"])
  end
end

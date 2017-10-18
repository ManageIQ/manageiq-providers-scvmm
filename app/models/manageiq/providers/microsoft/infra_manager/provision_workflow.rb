class ManageIQ::Providers::Microsoft::InfraManager::ProvisionWorkflow < ::MiqProvisionInfraWorkflow
  def dialog_name_from_automate(message = 'get_dialog_name')
    super(message, {'platform' => 'microsoft'})
  end

  def allowed_provision_types(_options = {})
    {
      "microsoft" => "Microsoft"
    }
  end

  def self.provider_model
    ManageIQ::Providers::Microsoft::InfraManager
  end

  def update_field_visibility(_options = {})
    super

    if get_value(@values[:vm_dynamic_memory])
      display_flag = :edit
    else
      display_flag = :hide
    end
    show_fields(display_flag, [:vm_minimum_memory, :vm_maximum_memory])
  end

  def allowed_datacenters(_options = {})
    allowed_ci(:datacenter, [:cluster, :host, :folder])
  end

  def allowed_clusters(_options = {})
    all_clusters     = EmsCluster.where(:ems_id => get_source_and_targets[:ems].try(:id))
    filtered_targets = process_filter(:cluster_filter, EmsCluster, all_clusters)
    allowed_ci(:cluster, [:host], filtered_targets.collect(&:id))
  end

  def filter_hosts_by_vlan_name(all_hosts)
    vlan_uid, vlan_name = @values[:vlan]
    return all_hosts unless vlan_uid

    _log.info("Filtering hosts with the following network: <#{vlan_name}>")
    all_hosts.reject { |h| !h.lans.pluck(:uid_ems).include?(vlan_uid) }
  end

  def load_hosts_vlans(hosts, vlans)
    hosts.each do |h|
      h.lans.each do |l|
        next if l.switch.shared?

        lan_name = l.parent.nil? ? l.name : "#{l.parent.name} / #{l.name}"
        vlans[l.uid_ems] = lan_name
      end
    end
  end

  def allowed_subnets(_options = {})
    subnets = {}
    src = get_source_and_targets
    return subnets if src.blank?

    hosts = get_selected_hosts(src)
    load_allowed_subnets(hosts, subnets)

    subnets
  end

  def load_allowed_subnets(hosts, subnets)
    hosts.each { |host| load_host_subnets(host, subnets) }
  end

  def load_host_subnets(host, subnets)
    host.subnets.each { |s| subnets[s.ems_ref] = s.name }
  end
end

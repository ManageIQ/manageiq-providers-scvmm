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
    lans_for_hosts = Lan.distinct.select(:id, :switch_id, :uid_ems, :name)
                        .includes(:parent)
                        .joins(:switch => :host_switches)
                        .where(:host_switches => {:host_id => hosts.map(&:id)})
                        .where(:switches => {:shared => [nil, false]})

    lans_for_hosts.each do |l|
      lan_name = l.parent.nil? ? l.name : "#{l.parent.name} / #{l.name}"
      vlans[l.uid_ems] = lan_name
    end
  end

  def allowed_subnets(_options = {})
    src = get_source_and_targets
    return {} if src.blank?

    hosts = get_selected_hosts(src)
    subnet_objs = all_subnets(hosts)
    filter_subnets_by_vlan(subnet_objs)

    subnet_objs.each_with_object({}) { |subnet, hash| hash[subnet.ems_ref] = subnet.name }
  end

  def filter_subnets_by_vlan(subnets)
    vlan_uid, _vlan_name = @values[:vlan]
    return if vlan_uid.nil?

    subnets.reject! { |subnet| subnet.lan.uid_ems != vlan_uid }
  end

  def all_subnets(hosts)
    hosts.flat_map(&:subnets)
  end
end

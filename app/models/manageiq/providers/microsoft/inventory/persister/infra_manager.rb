class ManageIQ::Providers::Microsoft::Inventory::Persister::InfraManager < ManageIQ::Providers::Microsoft::Inventory::Persister
  def initialize_inventory_collections
    add_collection(infra, :disks)
    add_collection(infra, :ems_clusters, :attributes_blacklist => %i(parent))
    add_collection(infra, :ems_folders, :attributes_blacklist => %i(parent))
    add_collection(infra, :guest_devices)
    add_collection(infra, :hardwares)
    add_collection(infra, :hosts, :attributes_blacklist => %i(parent))
    add_collection(infra, :host_guest_devices)
    add_collection(infra, :host_hardwares)
    add_collection(infra, :host_networks)
    add_collection(infra, :host_operating_systems)
    add_collection(infra, :host_storages)
    add_collection(infra, :host_switches)
    add_collection(infra, :lans)
    add_collection(infra, :miq_templates)
    add_collection(infra, :networks)
    add_collection(infra, :operating_systems)
    add_collection(infra, :snapshots)
    add_collection(infra, :storages)
    add_collection(infra, :host_virtual_switches)
    add_collection(infra, :subnets)
    add_collection(infra, :vms, :attributes_blacklist => %i(parent))
    add_relationships
  end

  private

  def add_relationships
    extra_props = {
      :complete       => nil,
      :saver_strategy => nil,
      :strategy       => nil,
      :targeted       => nil,
    }

    settings = {
      :without_model_class => true
    }

    add_collection(infra, :root_folder_relat, extra_props, settings) do |builder|
      builder.add_properties(:custom_save_block => root_folder_save_block)
      builder.add_dependency_attributes(:ems_folders => [collections[:ems_folders]])
    end

    add_collection(infra, :vm_folder_relats, extra_props, settings) do |builder|
      builder.add_properties(:custom_save_block => vm_folder_save_block)
      builder.add_dependency_attributes(:vms => [collections[:vms]])
    end

    add_collection(infra, :host_folder_relats, extra_props, settings) do |builder|
      builder.add_properties(:custom_save_block => host_folder_save_block)
      builder.add_dependency_attributes(
        :hosts => [collections[:hosts]], :ems_clusters => [collections[:ems_clusters]]
      )
    end
  end

  def root_folder_save_block
    lambda do |ems, inventory_collection|
      folder_inv_collection = inventory_collection.dependency_attributes[:ems_folders]&.first
      return if folder_inv_collection.nil?

      # All folders must have a parent except for the root folder
      root_folder_obj = folder_inv_collection.data.detect { |obj| obj.data[:parent].nil? }
      return if root_folder_obj.nil?

      root_folder = folder_inv_collection.model_class.find(root_folder_obj.id)
      root_folder.with_relationship_type(:ems_metadata) { root_folder.parent = ems }
    end
  end

  def vm_folder_save_block
    lambda do |ems, inventory_collection|
      vm_inv_collection = inventory_collection.dependency_attributes[:vms]&.first
      return if vm_inv_collection.nil?

      vms_ids = vm_inv_collection.data.map { |obj| obj.id }

      ActiveRecord::Base.transaction do
        vm_folder = ems.ems_folders.find_by(:uid_ems => "vm_folder")
        unless vm_folder.nil?
          vms = vm_inv_collection.model_class.find(vms_ids)
          vm_folder.add_children(vms)
        end
      end
    end
  end

  def host_folder_save_block
    lambda do |ems, inventory_collection|
      host_inv_collection = inventory_collection.dependency_attributes[:hosts]&.first
      cluster_inv_collection = inventory_collection.dependency_attributes[:ems_clusters]&.first

      cluster_ids = cluster_inv_collection&.data&.map { |obj| obj.id } || []
      host_ids    = host_inv_collection&.data.select { |obj| obj.ems_cluster.nil? }&.map { |obj| obj.id } || []

      ActiveRecord::Base.transaction do
        host_folder = ems.ems_folders.find_by(:uid_ems => "host_folder")
        unless host_folder.nil?
          clusters = cluster_inv_collection.model_class.find(cluster_ids)
          hosts    = host_inv_collection.model_class.find(host_ids)

          host_folder.add_children(clusters)
          host_folder.add_children(hosts)
        end
      end
    end
  end
end

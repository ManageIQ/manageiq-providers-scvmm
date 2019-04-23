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
    add_collection(infra, :miq_templates, :attributes_blacklist => %i(parent))
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

    add_collection(infra, :folder_relats, extra_props, settings) do |builder|
      builder.add_properties(:custom_save_block => folder_save_block)
      builder.add_dependency_attributes(:ems_folders => [collections[:ems_folders]])
    end

    add_collection(infra, :vm_folder_relats, extra_props, settings) do |builder|
      builder.add_properties(:custom_save_block => vm_folder_save_block)
      builder.add_dependency_attributes(
        :vms => [collections[:vms]], :miq_templates => [collections[:miq_templates]]
      )
    end

    add_collection(infra, :host_folder_relats, extra_props, settings) do |builder|
      builder.add_properties(:custom_save_block => host_folder_save_block)
      builder.add_dependency_attributes(
        :hosts => [collections[:hosts]], :ems_clusters => [collections[:ems_clusters]]
      )
    end
  end

  def folder_save_block
    lambda do |ems, inventory_collection|
      folder_inv_collection = inventory_collection.dependency_attributes[:ems_folders]&.first
      return if folder_inv_collection.nil?

      folder_inv_collection.data.each do |obj|
        folder = obj.model_class.find(obj.id)

        parent_lazy_obj = obj.data.delete(:parent)
        if parent_lazy_obj.present?
          parent_obj = parent_lazy_obj.load
          parent = parent_obj.model_class.find(parent_obj.id)
        else
          parent = ems
        end

        folder.with_relationship_type(:ems_metadata) { folder.parent = parent }
      end
    end
  end

  def vm_folder_save_block
    lambda do |ems, inventory_collection|
      vms_ids = inventory_collection.dependency_attributes.each_value.flat_map do |collections|
        collections.first.data.map(&:id)
      end

      ActiveRecord::Base.transaction do
        vm_folder = ems.ems_folders.find_by(:uid_ems => "vm_folder")
        unless vm_folder.nil?
          vms = VmOrTemplate.find(vms_ids)
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

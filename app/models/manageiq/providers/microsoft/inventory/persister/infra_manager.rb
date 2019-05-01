class ManageIQ::Providers::Microsoft::Inventory::Persister::InfraManager < ManageIQ::Providers::Microsoft::Inventory::Persister
  def initialize_inventory_collections
    add_collection(infra, :disks)
    add_collection(infra, :ems_clusters, :attributes_blacklist => %i(parent))
    add_collection(infra, :ems_folders, :attributes_blacklist => %i(parent))
    add_collection(infra, :resource_pools)
    add_collection(infra, :guest_devices)
    add_collection(infra, :hardwares)
    add_collection(infra, :hosts,
                   :attributes_blacklist => %i(parent),
                   :secondary_refs       => {:by_host_name => %i(name)})
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
    add_collection(infra, :root_folder_relationship)
    add_collection(infra, :vm_parent_blue_folders)
    add_collection(infra, :parent_blue_folders)
  end
end

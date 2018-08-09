class ManageIQ::Providers::Microsoft::Inventory::Persister::InfraManager < ManageIQ::Providers::Microsoft::Inventory::Persister
  def initialize_inventory_collections
    add_infra_collection(:disks)
    add_infra_collection(:ems_clusters)
    add_infra_collection(:ems_folders)
    add_infra_collection(:guest_devices)
    add_infra_collection(:hardwares)
    add_infra_collection(:hosts)
    add_infra_collection(:host_guest_devices)
    add_infra_collection(:host_hardwares)
    add_infra_collection(:host_networks)
    add_infra_collection(:host_storages)
    add_infra_collection(:host_switches)
    add_infra_collection(:lans)
    add_infra_collection(:miq_templates)
    add_infra_collection(:networks)
    add_infra_collection(:operating_systems)
    add_infra_collection(:storages)
    add_infra_collection(:switches)
    add_infra_collection(:subnets)
    add_infra_collection(:vms)
  end

  private

  def add_infra_collection(collection_name)
    add_collection(infra, collection_name)
  end
end

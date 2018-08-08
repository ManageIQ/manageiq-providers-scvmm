class ManageIQ::Providers::Microsoft::Inventory::Persister::InfraManager < ManageIQ::Providers::Microsoft::Inventory::Persister
  def initialize_inventory_collections
    add_infra_collection(:datacenters)
    add_infra_collection(:ems_clusters)
    add_infra_collection(:ems_folders)
    add_infra_collection(:hosts)
    add_infra_collection(:miq_templates)
    add_infra_collection(:storages)
    add_infra_collection(:vms)
  end

  private

  def add_infra_collection(collection_name)
    add_collection(infra, collection_name)
  end
end

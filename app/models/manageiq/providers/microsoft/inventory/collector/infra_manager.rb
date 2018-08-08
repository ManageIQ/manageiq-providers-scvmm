class ManageIQ::Providers::Microsoft::Inventory::Collector::InfraManager < ManageIQ::Providers::Microsoft::Inventory::Collector
  def initialize(manager, target)
    super
    @inventory = {}
  end

  def collect!
    $scvmm_log.info("#{log_header} Collecting inventory...")
    @inventory = manager.class.execute_powershell_json(connection, inventory_script)
    $scvmm_log.info("#{log_header} Collecting inventory...Complete")
  end

  def inventory
    @inventory ||= collect!
  end

  def ems
    inventory["ems"] || {}
  end

  def volumes
    @volumes ||= begin
      hosts.collect { |host| host["DiskVolumes"] }.flatten
           .reject { |volume| volume["VolumeLabel"] == "System Reserved" }
    end
  end

  def fileshares
    @fileshares ||= begin
      hosts.collect { |host| host["RegisteredStorageFileShares"] }.flatten
    end
  end

  def hosts
    inventory["hosts"] || []
  end

  def clusters
    inventory["clusters"] || []
  end

  def vms
    inventory["vms"] || []
  end

  def images
    inventory["images"] || []
  end

  private

  def connection
    @connection ||= manager.connect
  end

  def inventory_script
    @inventory_script ||= File.read(inventory_script_path)
  end

  def inventory_script_path
    @inventory_script_path ||= begin
      File.join(File.dirname(__FILE__), "..", "..", "infra_manager", "ps_scripts", "get_inventory.ps1")
    end
  end
end
